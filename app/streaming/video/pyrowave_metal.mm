#ifdef HAVE_PYROWAVE_METAL

#include "pyrowave_metal.h"

#include "pyrowave_color.h"
#include "pyrowave_metal_api.h"
#include "pyrowave_packets.h"
#include "pyrowave_stats.h"
#include "path.h"
#include "streaming/session.h"
#include "streaming/streamutils.h"
#include "streaming/bandwidth.h"

#include <SDL.h>
#include <SDL_metal.h>

#include <atomic>
#include <cstring>
#include <cstdlib>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mutex>
#include <string>
#include <vector>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

namespace {

struct MetalApi {
    void* lib = nullptr;
    std::string path;
    void (*getApiVersion)(uint32_t*, uint32_t*, uint32_t*) = nullptr;
    const char* (*resultString)(int32_t) = nullptr;
    bool (*deviceIsSupported)(void*) = nullptr;
    int32_t (*deviceCreate)(const pyro_metal::DeviceCreateInfo*, void**) = nullptr;
    void (*deviceDestroy)(void*) = nullptr;
    int32_t (*decoderCreate)(const pyro_metal::DecoderCreateInfo*, void**) = nullptr;
    void (*decoderDestroy)(void*) = nullptr;
    int32_t (*pushPacket)(void*, const void*, size_t) = nullptr;
    bool (*decodeIsReady)(void*, bool) = nullptr;
    int32_t (*decodeGpu)(void*, void*, const pyro_metal::GpuBuffers*) = nullptr;
};

const char* metalResult(const MetalApi* api, int32_t code)
{
    if (api != nullptr && api->resultString != nullptr) {
        const char* text = api->resultString(code);
        if (text != nullptr) {
            return text;
        }
    }
    return "error";
}

void metalLog(void*, const char* message)
{
    if (message != nullptr) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "pyrowave-metal: %s", message);
    }
}

template <typename T>
bool loadSymbol(void* lib, const char* name, T* out)
{
    *out = reinterpret_cast<T>(dlsym(lib, name));
    if (*out == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "libpyrowave-metal is missing %s", name);
        return false;
    }
    return true;
}

void* openMetalLibrary(std::string* openedPath)
{
    std::vector<std::string> paths;
    if (const char* env = std::getenv("PYROWAVE_METAL_LIBRARY")) {
        if (env[0] != '\0') {
            paths.emplace_back(env);
        }
    }

    char executable[4096];
    uint32_t executableSize = sizeof(executable);
    if (_NSGetExecutablePath(executable, &executableSize) == 0) {
        std::string dir(executable);
        auto slash = dir.find_last_of('/');
        if (slash != std::string::npos) {
            dir.resize(slash);
        }
        slash = dir.find_last_of('/');
        if (slash != std::string::npos) {
            dir.resize(slash);
        }
        paths.push_back(dir + "/Frameworks/libpyrowave-metal.dylib");
        paths.push_back(dir + "/Frameworks/libpyrowave-metal.0.dylib");
        paths.push_back(dir + "/Frameworks/libpyrowave-metal.0.5.0.dylib");
    }

    // Separate checkout. The pyrowave submodule stays on the MoltenVK pin,
    // which has no metal/ directory. CMake may emit the unversioned name
    // or the 0.5.0 soname from metal/CMakeLists.txt.
    paths.push_back("pyrowave-metal/build/libpyrowave-metal.dylib");
    paths.push_back("pyrowave-metal/build/libpyrowave-metal.0.dylib");
    paths.push_back("pyrowave-metal/build/libpyrowave-metal.0.5.0.dylib");
    paths.push_back("libpyrowave-metal.dylib");

    for (const std::string& path : paths) {
        void* handle = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (handle != nullptr) {
            *openedPath = path;
            return handle;
        }
    }

    const char* error = dlerror();
    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave Metal library not found (%s). "
                "Set PYROWAVE_METAL_LIBRARY to libpyrowave-metal.dylib. "
                "The MoltenVK decoder is unchanged.",
                error != nullptr ? error : "dlopen failed");
    return nullptr;
}

MetalApi* metalApi()
{
    static MetalApi api;
    static int state = 0;
    if (state == 1) {
        return &api;
    }
    if (state < 0) {
        return nullptr;
    }

    api.lib = openMetalLibrary(&api.path);
    if (api.lib == nullptr) {
        state = -1;
        return nullptr;
    }

    bool ok = loadSymbol(api.lib, "pyrowave_get_api_version", &api.getApiVersion)
        && loadSymbol(api.lib, "pyrowave_device_is_supported", &api.deviceIsSupported)
        && loadSymbol(api.lib, "pyrowave_device_create", &api.deviceCreate)
        && loadSymbol(api.lib, "pyrowave_device_destroy", &api.deviceDestroy)
        && loadSymbol(api.lib, "pyrowave_decoder_create", &api.decoderCreate)
        && loadSymbol(api.lib, "pyrowave_decoder_destroy", &api.decoderDestroy)
        && loadSymbol(api.lib, "pyrowave_decoder_push_packet", &api.pushPacket)
        && loadSymbol(api.lib, "pyrowave_decoder_decode_is_ready", &api.decodeIsReady)
        && loadSymbol(api.lib, "pyrowave_decoder_decode_gpu_buffer", &api.decodeGpu);
    api.resultString = reinterpret_cast<const char* (*)(int32_t)>(dlsym(api.lib, "pyrowave_result_to_string"));
    if (!ok) {
        dlclose(api.lib);
        api.lib = nullptr;
        state = -1;
        return nullptr;
    }

    uint32_t major = 0;
    uint32_t minor = 0;
    uint32_t patch = 0;
    api.getApiVersion(&major, &minor, &patch);
    if (major != pyro_metal::kApiMajor || minor != pyro_metal::kApiMinor) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "libpyrowave-metal API %u.%u.%u does not match the 0.5.x snapshot (%s)",
                     major, minor, patch, pyro_metal::kGit);
        dlclose(api.lib);
        api.lib = nullptr;
        state = -1;
        return nullptr;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Loaded PyroWave Metal API %u.%u.%u from %s",
                major, minor, patch, api.path.c_str());
    state = 1;
    return &api;
}

// Retains the returned device. Caller releases it.
id<MTLDevice> pickSupportedDevice(MetalApi* api)
{
    id<MTLDevice> fallback = MTLCreateSystemDefaultDevice();
    if (fallback != nil && api->deviceIsSupported((void*)fallback)) {
        return [fallback retain];
    }

    NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
    id<MTLDevice> found = nil;
    for (id<MTLDevice> device in devices) {
        if (api->deviceIsSupported((void*)device)) {
            found = [device retain];
            break;
        }
    }
    [devices release];
    return found;
}

struct CscParams {
    vector_float3 matrix[3];
    vector_float3 offsets;
};

struct ParamBuffer {
    CscParams cscParams;
    float bitnessScaleFactor;
};

struct Vertex {
    vector_float4 position;
    vector_float2 texCoord;
};

// Same coefficients as VTMetalRenderer, so an 8-bit frame matches HEVC.
// 10-bit planes are normalized floats; the offsets below are scaled to
// 64/1023 and 512/1023, which is how the host wrote a 10-bit limited code.
const CscParams kBt601Lim8 = {
    {
        {1.1644f, 0.0f, 1.5960f},
        {1.1644f, -0.3917f, -0.8129f},
        {1.1644f, 2.0172f, 0.0f},
    },
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
const CscParams kBt601Full8 = {
    {
        {1.0f, 0.0f, 1.4020f},
        {1.0f, -0.3441f, -0.7141f},
        {1.0f, 1.7720f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
const CscParams kBt709Lim8 = {
    {
        {1.1644f, 0.0f, 1.7927f},
        {1.1644f, -0.2132f, -0.5329f},
        {1.1644f, 2.1124f, 0.0f},
    },
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
const CscParams kBt709Full8 = {
    {
        {1.0f, 0.0f, 1.5748f},
        {1.0f, -0.1873f, -0.4681f},
        {1.0f, 1.8556f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
const CscParams kBt2020Lim8 = {
    {
        {1.1644f, 0.0f, 1.6781f},
        {1.1644f, -0.1874f, -0.6505f},
        {1.1644f, 2.1418f, 0.0f},
    },
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
const CscParams kBt2020Full8 = {
    {
        {1.0f, 0.0f, 1.4746f},
        {1.0f, -0.1646f, -0.5714f},
        {1.0f, 1.8814f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};

CscParams cscFor(PyroWaveMatrix matrix, bool fullRange, bool tenBit)
{
    CscParams csc;
    switch (matrix) {
    case PyroWaveMatrix::Bt709:
        csc = fullRange ? kBt709Full8 : kBt709Lim8;
        break;
    case PyroWaveMatrix::Bt2020:
        csc = fullRange ? kBt2020Full8 : kBt2020Lim8;
        break;
    case PyroWaveMatrix::Bt601:
    default:
        csc = fullRange ? kBt601Full8 : kBt601Lim8;
        break;
    }
    if (!tenBit) {
        return csc;
    }
    // Host 10-bit UNORM is code/1023. 16/255 and 128/255 are the 8-bit
    // stand-ins; 64/1023 and 512/1023 are the values actually stored.
    const float yScale = fullRange ? 1.0f : (1023.0f / 876.0f) / (255.0f / 219.0f);
    const float cScale = fullRange ? 1.0f : (1023.0f / 896.0f) / (255.0f / 224.0f);
    for (int row = 0; row < 3; row++) {
        csc.matrix[row].x *= yScale;
        csc.matrix[row].y *= cScale;
        csc.matrix[row].z *= cScale;
    }
    if (fullRange) {
        csc.offsets = {0.0f, 512.0f / 1023.0f, 512.0f / 1023.0f};
    }
    else {
        csc.offsets = {64.0f / 1023.0f, 512.0f / 1023.0f, 512.0f / 1023.0f};
    }
    return csc;
}

}  // namespace

struct PyroWaveMetalVideoDecoder::Impl {
    SDL_Window* window = nullptr;
    int width = 0;
    int height = 0;
    bool yuv444 = false;
    bool tenBit = false;
    std::atomic<bool> hdr{false};
    PyroWavePresentColor present{};
    bool presentValid = false;
    PyroWaveSequenceHeader sequence{};
    bool haveSequence = false;

    void* pyroDevice = nullptr;
    void* decoder = nullptr;
    id<MTLDevice> mtlDevice = nil;
    id<MTLCommandQueue> queue = nil;
    id<MTLTexture> planes[3] = {nil, nil, nil};
    SDL_MetalView metalView = nullptr;
    CAMetalLayer* layer = nullptr;
    id<MTLLibrary> shaderLibrary = nil;
    id<MTLRenderPipelineState> videoPipeline = nil;
    id<MTLRenderPipelineState> overlayPipeline = nil;
    id<MTLBuffer> cscBuffer = nil;
    id<MTLBuffer> vertexBuffer = nil;
    int drawableWidth = 0;
    int drawableHeight = 0;

    id<MTLTexture> overlayTextures[Overlay::OverlayMax] = {};
    SDL_SpinLock overlayLock = 0;

    std::mutex frameLock;
    bool frameReady = false;

    VIDEO_STATS activeStats{};
    VIDEO_STATS lastStats{};
    VIDEO_STATS globalStats{};
    BandwidthTracker bandwidth;
    uint32_t lastFrameNumber = 0;
    std::atomic<uint32_t> renderedFrames{0};
    std::atomic<uint64_t> totalRenderTimeUs{0};
    int statsWindows = 0;
    uint64_t decodeReadyUs = 0;
    std::mutex statsLock;
    PyroWaveSteadyState steady;
};

namespace {

const char* metalPixelFormatName(MTLPixelFormat format);

bool buildPipelines(PyroWaveMetalVideoDecoder::Impl* impl, const PyroWavePresentColor& color)
{
    [impl->videoPipeline release];
    impl->videoPipeline = nil;
    [impl->overlayPipeline release];
    impl->overlayPipeline = nil;
    [impl->cscBuffer release];
    impl->cscBuffer = nil;

    CGColorSpaceRef colorSpace = nullptr;
    ParamBuffer params{};
    // Planes are normalized floats. The CSC offsets already use the code range.
    params.bitnessScaleFactor = 1.0f;
    const bool hdrOutput = color.transfer == PyroWaveTransfer::Pq || color.transfer == PyroWaveTransfer::Hlg;
    CFStringRef colorName = kCGColorSpaceSRGB;
    if (color.transfer == PyroWaveTransfer::Pq) {
        colorName = kCGColorSpaceITUR_2100_PQ;
    }
    else if (color.transfer == PyroWaveTransfer::Hlg) {
        colorName = kCGColorSpaceITUR_2100_HLG;
    }
    else if (color.matrix == PyroWaveMatrix::Bt2020) {
        colorName = kCGColorSpaceITUR_2020;
    }
    else if (color.matrix == PyroWaveMatrix::Bt709) {
        colorName = kCGColorSpaceITUR_709;
    }
    impl->layer.colorspace = colorSpace = CGColorSpaceCreateWithName(colorName);
    impl->layer.pixelFormat = hdrOutput ? MTLPixelFormatBGR10A2Unorm : MTLPixelFormatBGRA8Unorm;
    // VT Metal turns EDR on for any 10-bit format. PQ/HLG also need it so
    // the 10-bit layer can leave the SDR range. SDR 8-bit stays off.
    impl->layer.wantsExtendedDynamicRangeContent = (hdrOutput || impl->tenBit) ? YES : NO;
    params.cscParams = cscFor(color.matrix, color.range == PyroWaveRange::Full, impl->tenBit);
    CGColorSpaceRelease(colorSpace);

    impl->cscBuffer = [impl->mtlDevice newBufferWithBytes:&params
                                                    length:sizeof(params)
                                                   options:MTLResourceStorageModeShared];
    if (impl->cscBuffer == nil) {
        return false;
    }

    if (impl->shaderLibrary == nil) {
        QByteArray sourceBytes = Path::readDataFile("vt_renderer.metal");
        if (sourceBytes.isEmpty()) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave Metal: vt_renderer.metal is missing");
            return false;
        }
        NSError* error = nil;
        NSString* sourceText = [[NSString alloc] initWithBytes:sourceBytes.constData()
                                                              length:(NSUInteger)sourceBytes.size()
                                                            encoding:NSUTF8StringEncoding];
        impl->shaderLibrary = [impl->mtlDevice newLibraryWithSource:sourceText
                                                             options:nil
                                                               error:&error];
        [sourceText release];
        if (impl->shaderLibrary == nil) {
            const char* message = error.localizedDescription.UTF8String;
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave Metal: shader compile failed: %s",
                         message != nullptr ? message : "unknown");
            return false;
        }
    }

    MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor new] autorelease];
    desc.vertexFunction = [[impl->shaderLibrary newFunctionWithName:@"vs_draw"] autorelease];
    desc.fragmentFunction = [[impl->shaderLibrary newFunctionWithName:@"ps_draw_triplanar"] autorelease];
    desc.colorAttachments[0].pixelFormat = impl->layer.pixelFormat;
    NSError* error = nil;
    impl->videoPipeline = [impl->mtlDevice newRenderPipelineStateWithDescriptor:desc error:&error];
    if (impl->videoPipeline == nil) {
        const char* message = error.localizedDescription.UTF8String;
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave Metal: video pipeline failed: %s",
                     message != nullptr ? message : "unknown");
        return false;
    }

    desc = [[MTLRenderPipelineDescriptor new] autorelease];
    desc.vertexFunction = [[impl->shaderLibrary newFunctionWithName:@"vs_draw"] autorelease];
    desc.fragmentFunction = [[impl->shaderLibrary newFunctionWithName:@"ps_draw_rgb"] autorelease];
    desc.colorAttachments[0].pixelFormat = impl->layer.pixelFormat;
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    desc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    impl->overlayPipeline = [impl->mtlDevice newRenderPipelineStateWithDescriptor:desc error:&error];
    if (impl->overlayPipeline == nil) {
        const char* message = error.localizedDescription.UTF8String;
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave Metal: overlay pipeline failed: %s",
                     message != nullptr ? message : "unknown");
        return false;
    }

    char colorDesc[96];
    snprintf(colorDesc, sizeof(colorDesc), "%s %s %s%s",
             pyroWaveMatrixName(color.matrix),
             pyroWaveTransferName(color.transfer),
             pyroWaveRangeName(color.range),
             color.chromaLeft ? " left-sited chroma" : "");
    const char* pixelName = metalPixelFormatName(impl->layer.pixelFormat);
    const char* planeName = impl->tenBit ? "R16Unorm" : "R8Unorm";
    char previous[96];
    char previousPixel[64];
    const bool firstPresent = !impl->presentValid;
    {
        std::lock_guard<std::mutex> lock(impl->statsLock);
        PyroWaveSteadyState::set(previous, sizeof(previous), impl->steady.color);
        PyroWaveSteadyState::set(previousPixel, sizeof(previousPixel), impl->steady.pixelFormat);
        PyroWaveSteadyState::set(impl->steady.color, sizeof(impl->steady.color), colorDesc);
        PyroWaveSteadyState::set(impl->steady.pixelFormat, sizeof(impl->steady.pixelFormat), pixelName);
        PyroWaveSteadyState::set(impl->steady.planeFormat, sizeof(impl->steady.planeFormat), planeName);
    }
    impl->present = color;
    impl->presentValid = true;
    if (firstPresent) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave Metal present: %s pixel=%s planes=%s",
                    colorDesc, pixelName, planeName);
    }
    else {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave reconfigure: present %s pixel=%s -> %s pixel=%s",
                    previous, previousPixel, colorDesc, pixelName);
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: color=%s", colorDesc);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: pixel_format=%s", pixelName);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: plane_format=%s", planeName);
    return true;
}

id<MTLTexture> makePlane(id<MTLDevice> device, int width, int height, bool tenBit)
{
    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:tenBit ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm
                                                                                     width:(NSUInteger)width
                                                                                    height:(NSUInteger)height
                                                                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    desc.storageMode = MTLStorageModePrivate;
    return [device newTextureWithDescriptor:desc];
}

bool updateVertices(PyroWaveMetalVideoDecoder::Impl* impl)
{
    int drawableWidth = 0;
    int drawableHeight = 0;
    SDL_Metal_GetDrawableSize(impl->window, &drawableWidth, &drawableHeight);
    if (drawableWidth <= 0 || drawableHeight <= 0) {
        return false;
    }
    if (impl->vertexBuffer != nil &&
            drawableWidth == impl->drawableWidth &&
            drawableHeight == impl->drawableHeight) {
        return true;
    }
    if (impl->drawableWidth == 0 && impl->drawableHeight == 0) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave Metal drawable: %dx%d", drawableWidth, drawableHeight);
    }
    else if (drawableWidth != impl->drawableWidth || drawableHeight != impl->drawableHeight) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave reconfigure: drawable %dx%d -> %dx%d",
                    impl->drawableWidth, impl->drawableHeight, drawableWidth, drawableHeight);
    }

    SDL_Rect src = {0, 0, impl->width, impl->height};
    SDL_Rect dst = {0, 0, drawableWidth, drawableHeight};
    StreamUtils::scaleSourceToDestinationSurface(&src, &dst);
    SDL_FRect rect;
    StreamUtils::screenSpaceToNormalizedDeviceCoords(&dst, &rect, drawableWidth, drawableHeight);

    Vertex verts[] = {
        {{rect.x, rect.y, 0.0f, 1.0f}, {0.0f, 1.0f}},
        {{rect.x, rect.y + rect.h, 0.0f, 1.0f}, {0.0f, 0.0f}},
        {{rect.x + rect.w, rect.y, 0.0f, 1.0f}, {1.0f, 1.0f}},
        {{rect.x + rect.w, rect.y + rect.h, 0.0f, 1.0f}, {1.0f, 0.0f}},
    };
    [impl->vertexBuffer release];
    impl->vertexBuffer = [impl->mtlDevice newBufferWithBytes:verts
                                                       length:sizeof(verts)
                                                      options:MTLResourceStorageModeShared];
    impl->drawableWidth = drawableWidth;
    impl->drawableHeight = drawableHeight;
    return impl->vertexBuffer != nil;
}

void addVideoStats(VIDEO_STATS& src, VIDEO_STATS& dst);
void stringifyVideoStats(PyroWaveMetalVideoDecoder::Impl* impl, VIDEO_STATS& stats, char* output, int length);

const char* metalPixelFormatName(MTLPixelFormat format)
{
    if (format == MTLPixelFormatBGRA8Unorm) {
        return "BGRA8Unorm";
    }
    if (format == MTLPixelFormatBGR10A2Unorm) {
        return "BGR10A2Unorm";
    }
    return "other";
}

void fillMetalIdentity(PyroWaveMetalVideoDecoder::Impl* impl, PDECODER_PARAMETERS params)
{
    snprintf(impl->steady.resolution, sizeof(impl->steady.resolution), "%dx%d", impl->width, impl->height);
    snprintf(impl->steady.videoFormat, sizeof(impl->steady.videoFormat), "0x%X", params->videoFormat);
    PyroWaveSteadyState::set(impl->steady.vsync, sizeof(impl->steady.vsync), params->enableVsync ? "on" : "off");
    PyroWaveSteadyState::set(impl->steady.planeFormat, sizeof(impl->steady.planeFormat), impl->tenBit ? "R16Unorm" : "R8Unorm");
    PyroWaveSteadyState::set(impl->steady.colorAdvertised, sizeof(impl->steady.colorAdvertised), "Rec.601 limited");
}

void logMetalIdentity(PyroWaveMetalVideoDecoder::Impl* impl, const char* phase)
{
    if (strcmp(impl->steady.gpu, "unknown") == 0 && phase != nullptr && strcmp(phase, "probe") == 0) {
        PyroWaveSteadyState::set(impl->steady.gpu, sizeof(impl->steady.gpu), "not queried on probe");
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave Metal %s: %s %s planes=%s advertised=%s gpu=%s vsync=%s swapchain=%s",
                phase != nullptr ? phase : "init",
                impl->steady.resolution,
                impl->steady.videoFormat,
                impl->steady.planeFormat,
                impl->steady.colorAdvertised,
                impl->steady.gpu,
                impl->steady.vsync,
                impl->steady.swapchainDepth);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: backend=Metal");
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: gpu=%s", impl->steady.gpu);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: resolution=%s", impl->steady.resolution);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: video_format=%s", impl->steady.videoFormat);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: vsync=%s", impl->steady.vsync);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: swapchain_depth=%s", impl->steady.swapchainDepth);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: color_advertised=%s", impl->steady.colorAdvertised);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave metric: plane_format=%s", impl->steady.planeFormat);
}

bool metalWindowHasSamples(const VIDEO_STATS& stats)
{
    return stats.receivedFrames != 0 || stats.decodedFrames != 0 || stats.renderedFrames != 0
        || stats.networkDroppedFrames != 0 || stats.totalFrames != 0;
}

void flushMetalWindow(PyroWaveMetalVideoDecoder::Impl* impl)
{
    impl->activeStats.renderedFrames += impl->renderedFrames.exchange(0);
    impl->activeStats.totalRenderTimeUs += impl->totalRenderTimeUs.exchange(0);
    if (!metalWindowHasSamples(impl->activeStats)) {
        return;
    }
    addVideoStats(impl->activeStats, impl->globalStats);
    SDL_zero(impl->activeStats);
}

PyroWaveRateStats metalRates(const PyroWaveMetalVideoDecoder::Impl* impl)
{
    double elapsedSec = 0;
    if (impl->globalStats.measurementStartUs != 0) {
        uint64_t now = LiGetMicroseconds();
        if (now > impl->globalStats.measurementStartUs) {
            elapsedSec = (double)(now - impl->globalStats.measurementStartUs) / 1000000.0;
        }
    }
    return pyroWaveMakeRates(impl->globalStats.receivedFrames,
                             impl->globalStats.decodedFrames,
                             impl->globalStats.renderedFrames,
                             impl->globalStats.totalFrames,
                             impl->globalStats.networkDroppedFrames,
                             impl->globalStats.totalDecodeTimeUs,
                             impl->globalStats.totalRenderTimeUs,
                             impl->globalStats.totalReassemblyTimeUs,
                             impl->globalStats.receivedVideoBytes,
                             elapsedSec);
}

void logMetalSteady(PyroWaveMetalVideoDecoder::Impl* impl, const char* reason)
{
    const bool endOfSession = reason != nullptr && strcmp(reason, "end of session") == 0;
    if (endOfSession) {
        flushMetalWindow(impl);
        char videoStats[2048];
        stringifyVideoStats(impl, impl->globalStats, videoStats, sizeof(videoStats));
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "\nGlobal video stats\n------------------\n%s",
                    videoStats);
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave steady-state (%s, Metal). First-packet wait is startup context only.",
                reason != nullptr ? reason : "session");
    PyroWaveSteadyState copy;
    {
        std::lock_guard<std::mutex> lock(impl->statsLock);
        copy = impl->steady;
    }
    pyroWaveEmitMetrics("Metal", copy, metalRates(impl), [](const char* line) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "%s", line);
    });
}

void addVideoStats(VIDEO_STATS& src, VIDEO_STATS& dst)
{
    dst.receivedVideoBytes += src.receivedVideoBytes;
    dst.receivedFrames += src.receivedFrames;
    dst.decodedFrames += src.decodedFrames;
    dst.renderedFrames += src.renderedFrames;
    dst.totalFrames += src.totalFrames;
    dst.networkDroppedFrames += src.networkDroppedFrames;
    dst.totalReassemblyTimeUs += src.totalReassemblyTimeUs;
    dst.totalDecodeTimeUs += src.totalDecodeTimeUs;
    dst.totalRenderTimeUs += src.totalRenderTimeUs;
    if (dst.minHostProcessingLatency == 0) {
        dst.minHostProcessingLatency = src.minHostProcessingLatency;
    }
    else if (src.minHostProcessingLatency != 0) {
        dst.minHostProcessingLatency = qMin(dst.minHostProcessingLatency, src.minHostProcessingLatency);
    }
    dst.maxHostProcessingLatency = qMax(dst.maxHostProcessingLatency, src.maxHostProcessingLatency);
    dst.totalHostProcessingLatency += src.totalHostProcessingLatency;
    dst.framesWithHostProcessingLatency += src.framesWithHostProcessingLatency;
    if (!LiGetEstimatedRttInfo(&dst.lastRtt, &dst.lastRttVariance)) {
        dst.lastRtt = 0;
        dst.lastRttVariance = 0;
    }
    if (!dst.measurementStartUs) {
        dst.measurementStartUs = src.measurementStartUs;
    }
    double seconds = (double)(LiGetMicroseconds() - dst.measurementStartUs) / 1000000.0;
    if (seconds > 0) {
        dst.totalFps = (double)dst.totalFrames / seconds;
        dst.receivedFps = (double)dst.receivedFrames / seconds;
        dst.decodedFps = (double)dst.decodedFrames / seconds;
        dst.renderedFps = (double)dst.renderedFrames / seconds;
    }
}

void stringifyVideoStats(PyroWaveMetalVideoDecoder::Impl* impl, VIDEO_STATS& stats, char* output, int length)
{
    int offset = 0;
    output[0] = 0;
    if (stats.receivedFps > 0) {
        int wrote = snprintf(output + offset, length - offset,
                             "Video stream: %dx%d %.2f FPS (Codec: PyroWave Metal %s%s)\n"
                             "Bitrate: %.1f Mbps, Peak (%us): %.1f\n"
                             "Incoming frame rate from network: %.2f FPS\n"
                             "Decoding frame rate: %.2f FPS\n"
                             "Rendering frame rate: %.2f FPS\n",
                             impl->width, impl->height, stats.totalFps,
                             impl->yuv444 ? "4:4:4" : "4:2:0",
                             impl->tenBit ? (impl->hdr.load() ? " 10-bit HDR" : " 10-bit") : "",
                             impl->bandwidth.GetAverageMbps(),
                             impl->bandwidth.GetWindowSeconds(),
                             impl->bandwidth.GetPeakMbps(),
                             stats.receivedFps, stats.decodedFps, stats.renderedFps);
        if (wrote < 0 || wrote >= length - offset) {
            return;
        }
        offset += wrote;
    }
    if (stats.framesWithHostProcessingLatency > 0) {
        int wrote = snprintf(output + offset, length - offset,
                             "Host processing latency min/max/average: %.1f/%.1f/%.1f ms\n",
                             (float)stats.minHostProcessingLatency / 10,
                             (float)stats.maxHostProcessingLatency / 10,
                             (float)stats.totalHostProcessingLatency / 10 / stats.framesWithHostProcessingLatency);
        if (wrote < 0 || wrote >= length - offset) {
            return;
        }
        offset += wrote;
    }
    if (stats.renderedFrames != 0) {
        char rttString[32];
        if (stats.lastRtt != 0) {
            snprintf(rttString, sizeof(rttString), "%u ms (variance: %u ms)", stats.lastRtt, stats.lastRttVariance);
        }
        else {
            snprintf(rttString, sizeof(rttString), "N/A");
        }
        snprintf(output + offset, length - offset,
                 "Frames dropped by your network connection: %.2f%%\n"
                 "Average network latency: %s\n"
                 "Average reassembly/decoding time: %.2f/%.2f ms\n"
                 "Average rendering time (including monitor V-sync latency): %.2f ms\n",
                 stats.totalFrames ? (float)stats.networkDroppedFrames / stats.totalFrames * 100 : 0.0f,
                 rttString,
                 stats.decodedFrames ? (double)(stats.totalReassemblyTimeUs / 1000.0) / stats.decodedFrames : 0.0,
                 stats.decodedFrames ? (double)(stats.totalDecodeTimeUs / 1000.0) / stats.decodedFrames : 0.0,
                 stats.renderedFrames ? (double)(stats.totalRenderTimeUs / 1000.0) / stats.renderedFrames : 0.0);
    }
}

}  // namespace

PyroWaveMetalVideoDecoder::PyroWaveMetalVideoDecoder(bool testOnly)
    : m_Impl(new Impl()),
      m_TestOnly(testOnly)
{
}

PyroWaveMetalVideoDecoder::~PyroWaveMetalVideoDecoder()
{
    if (m_Impl == nullptr) {
        return;
    }
    if (!m_TestOnly) {
        logMetalSteady(m_Impl, "end of session");
    }
    @autoreleasepool {
        if (m_Impl->queue != nil) {
            id<MTLCommandBuffer> drain = [m_Impl->queue commandBuffer];
            [drain commit];
            [drain waitUntilCompleted];
        }
        MetalApi* api = metalApi();
        if (api != nullptr && m_Impl->decoder != nullptr) {
            api->decoderDestroy(m_Impl->decoder);
        }
        if (api != nullptr && m_Impl->pyroDevice != nullptr) {
            api->deviceDestroy(m_Impl->pyroDevice);
        }
        for (int i = 0; i < 3; i++) {
            [m_Impl->planes[i] release];
        }
        for (int i = 0; i < Overlay::OverlayMax; i++) {
            [m_Impl->overlayTextures[i] release];
        }
        [m_Impl->vertexBuffer release];
        [m_Impl->cscBuffer release];
        [m_Impl->videoPipeline release];
        [m_Impl->overlayPipeline release];
        [m_Impl->shaderLibrary release];
        [m_Impl->queue release];
        [m_Impl->mtlDevice release];
        if (m_Impl->metalView != nullptr) {
            SDL_Metal_DestroyView(m_Impl->metalView);
        }
    }
    delete m_Impl;
    m_Impl = nullptr;
}

bool PyroWaveMetalVideoDecoder::runtimeAvailable()
{
    @autoreleasepool {
        MetalApi* api = metalApi();
        if (api == nullptr) {
            return false;
        }
        id<MTLDevice> device = pickSupportedDevice(api);
        bool ok = device != nil;
        [device release];
        if (!ok) {
            static bool logged = false;
            if (!logged) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "PyroWave Metal found no Apple7 GPU; Vulkan remains available when it is built in");
                logged = true;
            }
        }
        return ok;
    }
}

bool PyroWaveMetalVideoDecoder::initialize(PDECODER_PARAMETERS params)
{
    @autoreleasepool {
        if ((params->videoFormat & VIDEO_FORMAT_MASK_PYROWAVE) == 0) {
            return false;
        }
        m_Impl->yuv444 = (params->videoFormat & (VIDEO_FORMAT_PYROWAVE_444 | VIDEO_FORMAT_PYROWAVE10_444)) != 0;
        m_Impl->tenBit = (params->videoFormat & VIDEO_FORMAT_MASK_10BIT) != 0;
        m_Impl->width = params->width & ~1;
        m_Impl->height = params->height & ~1;
        m_Impl->window = params->window;
        if (m_Impl->width < 2 || m_Impl->height < 2) {
            return false;
        }
        fillMetalIdentity(m_Impl, params);

        MetalApi* api = metalApi();
        if (api == nullptr) {
            return false;
        }
        m_Impl->mtlDevice = pickSupportedDevice(api);
        if (m_Impl->mtlDevice == nil) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave Metal: no supported GPU");
            return false;
        }
        const char* gpuName = m_Impl->mtlDevice.name.UTF8String;
        PyroWaveSteadyState::set(m_Impl->steady.gpu, sizeof(m_Impl->steady.gpu),
                                 gpuName != nullptr ? gpuName : "unknown");
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave Metal device: %s",
                    m_Impl->steady.gpu);

        pyro_metal::DeviceCreateInfo deviceInfo{};
        deviceInfo.mtlDevice = (void*)m_Impl->mtlDevice;
        deviceInfo.messageCallback = metalLog;
        void* pyroDevice = nullptr;
        int32_t rc = api->deviceCreate(&deviceInfo, &pyroDevice);
        if (rc != pyro_metal::kSuccess || pyroDevice == nullptr) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave Metal: device create failed (%s)",
                         metalResult(api, rc));
            return false;
        }
        m_Impl->pyroDevice = pyroDevice;

        pyro_metal::DecoderCreateInfo decoderInfo{};
        decoderInfo.device = pyroDevice;
        decoderInfo.width = m_Impl->width;
        decoderInfo.height = m_Impl->height;
        decoderInfo.chroma = m_Impl->yuv444 ? pyro_metal::kChroma444 : pyro_metal::kChroma420;
        void* decoder = nullptr;
        rc = api->decoderCreate(&decoderInfo, &decoder);
        if (rc != pyro_metal::kSuccess || decoder == nullptr) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave Metal: decoder create failed (%s)",
                         metalResult(api, rc));
            return false;
        }
        m_Impl->decoder = decoder;

        if (m_TestOnly) {
            logMetalIdentity(m_Impl, "probe");
            return true;
        }
        if (params->window == nullptr) {
            return false;
        }

        m_Impl->metalView = SDL_Metal_CreateView(params->window);
        if (m_Impl->metalView == nullptr) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave Metal: SDL_Metal_CreateView() failed: %s",
                         SDL_GetError());
            return false;
        }
        m_Impl->layer = (CAMetalLayer*)SDL_Metal_GetLayer(m_Impl->metalView);
        m_Impl->layer.device = m_Impl->mtlDevice;
        m_Impl->layer.maximumDrawableCount = 3;
        m_Impl->layer.displaySyncEnabled = params->enableVsync;
        PyroWaveSteadyState::set(m_Impl->steady.swapchainDepth, sizeof(m_Impl->steady.swapchainDepth), "3");

        m_Impl->queue = [m_Impl->mtlDevice newCommandQueue];
        if (m_Impl->queue == nil) {
            return false;
        }

        int chromaWidth = m_Impl->yuv444 ? m_Impl->width : m_Impl->width / 2;
        int chromaHeight = m_Impl->yuv444 ? m_Impl->height : m_Impl->height / 2;
        m_Impl->planes[0] = makePlane(m_Impl->mtlDevice, m_Impl->width, m_Impl->height, m_Impl->tenBit);
        m_Impl->planes[1] = makePlane(m_Impl->mtlDevice, chromaWidth, chromaHeight, m_Impl->tenBit);
        m_Impl->planes[2] = makePlane(m_Impl->mtlDevice, chromaWidth, chromaHeight, m_Impl->tenBit);
        if (m_Impl->planes[0] == nil || m_Impl->planes[1] == nil || m_Impl->planes[2] == nil) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave Metal: plane texture allocation failed");
            return false;
        }
        if (!buildPipelines(m_Impl, pyroWavePresentColor(false, nullptr))) {
            return false;
        }
        if (Session::get() != nullptr) {
            Session::get()->getOverlayManager().setOverlayRenderer(this);
        }

        logMetalIdentity(m_Impl, "stream");
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave Metal decoder ready: %dx%d %s %s planes=%s advertised=%s",
                    m_Impl->width, m_Impl->height,
                    m_Impl->yuv444 ? "4:4:4" : "4:2:0",
                    m_Impl->tenBit ? "10-bit" : "8-bit",
                    m_Impl->steady.planeFormat,
                    m_Impl->steady.colorAdvertised);
        return true;
    }
}

bool PyroWaveMetalVideoDecoder::isHardwareAccelerated() { return true; }
bool PyroWaveMetalVideoDecoder::isAlwaysFullScreen() { return false; }
bool PyroWaveMetalVideoDecoder::isHdrSupported() { return true; }
int PyroWaveMetalVideoDecoder::getDecoderCapabilities() { return 0; }
int PyroWaveMetalVideoDecoder::getDecoderColorspace() {
    // Same advertisement as VT Metal HEVC, so the host's RGB→YUV matches that stream.
    return COLORSPACE_REC_601;
}
int PyroWaveMetalVideoDecoder::getDecoderColorRange() { return COLOR_RANGE_LIMITED; }
QSize PyroWaveMetalVideoDecoder::getDecoderMaxResolution() { return QSize(0, 0); }

void PyroWaveMetalVideoDecoder::setHdrMode(bool enabled)
{
    m_Impl->hdr.store(enabled);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave Metal: HDR mode %s", enabled ? "enabled" : "disabled");
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave reconfigure: HDR mode %s", enabled ? "enabled" : "disabled");
}

bool PyroWaveMetalVideoDecoder::notifyWindowChanged(PWINDOW_STATE_CHANGE_INFO info)
{
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave reconfigure: window change flags=0x%x size=%dx%d display=%d (handled in place)",
                info->stateChangeFlags, info->width, info->height, info->displayIndex);
    uint32_t unhandled = info->stateChangeFlags;
    unhandled &= ~WINDOW_STATE_CHANGE_SIZE;
    unhandled &= ~WINDOW_STATE_CHANGE_DISPLAY;
    return unhandled == 0;
}

void PyroWaveMetalVideoDecoder::notifyOverlayUpdated(Overlay::OverlayType type)
{
    @autoreleasepool {
        if (m_Impl->mtlDevice == nil || Session::get() == nullptr) {
            return;
        }
        SDL_Surface* surface = Session::get()->getOverlayManager().getUpdatedOverlaySurface(type);
        bool enabled = Session::get()->getOverlayManager().isOverlayEnabled(type);
        if (surface == nullptr && enabled) {
            return;
        }

        SDL_AtomicLock(&m_Impl->overlayLock);
        id<MTLTexture> oldTexture = m_Impl->overlayTextures[type];
        m_Impl->overlayTextures[type] = nil;
        SDL_AtomicUnlock(&m_Impl->overlayLock);
        [oldTexture release];

        if (!enabled || surface == nullptr) {
            SDL_FreeSurface(surface);
            return;
        }
        if (SDL_MUSTLOCK(surface) || surface->format->format != SDL_PIXELFORMAT_ARGB8888) {
            SDL_FreeSurface(surface);
            return;
        }

        MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                         width:surface->w
                                                                                        height:surface->h
                                                                                     mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead;
        desc.storageMode = MTLStorageModeShared;
        id<MTLTexture> texture = [m_Impl->mtlDevice newTextureWithDescriptor:desc];
        if (texture != nil) {
            [texture replaceRegion:MTLRegionMake2D(0, 0, surface->w, surface->h)
                       mipmapLevel:0
                         withBytes:surface->pixels
                       bytesPerRow:surface->pitch];
        }
        SDL_FreeSurface(surface);

        SDL_AtomicLock(&m_Impl->overlayLock);
        m_Impl->overlayTextures[type] = texture;
        SDL_AtomicUnlock(&m_Impl->overlayLock);
    }
}

int PyroWaveMetalVideoDecoder::submitDecodeUnit(PDECODE_UNIT du)
{
    @autoreleasepool {
        Impl* impl = m_Impl;
        if (impl->decoder == nullptr) {
            return DR_OK;
        }

        if (!impl->lastFrameNumber) {
            impl->activeStats.measurementStartUs = LiGetMicroseconds();
            impl->lastFrameNumber = du->frameNumber;
        }
        else {
            impl->activeStats.networkDroppedFrames += du->frameNumber - (impl->lastFrameNumber + 1);
            impl->activeStats.totalFrames += du->frameNumber - (impl->lastFrameNumber + 1);
            impl->lastFrameNumber = du->frameNumber;
        }

        if (LiGetMicroseconds() > impl->activeStats.measurementStartUs + 1000000) {
            impl->activeStats.renderedFrames = impl->renderedFrames.exchange(0);
            impl->activeStats.totalRenderTimeUs = impl->totalRenderTimeUs.exchange(0);
            Session* session = Session::get();
            const bool overlayOn = session != nullptr &&
                    session->getOverlayManager().isOverlayEnabled(Overlay::OverlayDebug);
            if (overlayOn) {
                VIDEO_STATS combined{};
                addVideoStats(impl->lastStats, combined);
                addVideoStats(impl->activeStats, combined);
                char* text = session->getOverlayManager().getOverlayText(Overlay::OverlayDebug);
                const int textLen = session->getOverlayManager().getOverlayMaxTextLength();
                stringifyVideoStats(impl, combined, text, textLen);
                session->getOverlayManager().setOverlayTextUpdated(Overlay::OverlayDebug);
            }
            addVideoStats(impl->activeStats, impl->globalStats);
            if (++impl->statsWindows >= 5) {
                impl->statsWindows = 0;
                logMetalSteady(impl, "session so far");
            }
            impl->lastStats = impl->activeStats;
            SDL_zero(impl->activeStats);
            impl->activeStats.measurementStartUs = LiGetMicroseconds();
        }

        if (du->frameHostProcessingLatency != 0) {
            if (impl->activeStats.minHostProcessingLatency != 0) {
                impl->activeStats.minHostProcessingLatency = qMin(impl->activeStats.minHostProcessingLatency,
                                                                  du->frameHostProcessingLatency);
            }
            else {
                impl->activeStats.minHostProcessingLatency = du->frameHostProcessingLatency;
            }
            impl->activeStats.framesWithHostProcessingLatency += 1;
        }
        impl->activeStats.maxHostProcessingLatency = qMax(impl->activeStats.maxHostProcessingLatency,
                                                           du->frameHostProcessingLatency);
        impl->activeStats.totalHostProcessingLatency += du->frameHostProcessingLatency;
        impl->activeStats.receivedFrames++;
        impl->activeStats.totalFrames++;
        impl->activeStats.receivedVideoBytes += (uint64_t)du->fullLength;
        impl->bandwidth.AddBytes(du->fullLength);
        impl->activeStats.totalReassemblyTimeUs += (du->enqueueTimeUs - du->receiveTimeUs);

        uint64_t decodeStartUs = LiGetMicroseconds();
        std::vector<uint8_t> frame;
        frame.reserve((size_t)du->fullLength);
        for (PLENTRY entry = du->bufferList; entry != nullptr; entry = entry->next) {
            const uint8_t* bytes = reinterpret_cast<const uint8_t*>(entry->data);
            frame.insert(frame.end(), bytes, bytes + entry->length);
        }
        std::vector<PyroWavePacketView> packets;
        if (!pyroWaveUnpackLengthPrefixedFrame(frame.data(), frame.size(), packets, nullptr)) {
            return DR_OK;
        }
        PyroWaveSequenceHeader sequence{};
        const bool haveSequence = pyroWaveFindSequenceHeader(packets, sequence);

        MetalApi* api = metalApi();
        for (const PyroWavePacketView& packet : packets) {
            api->pushPacket(impl->decoder, packet.data, packet.size);
        }
        if (!api->decodeIsReady(impl->decoder, true)) {
            return DR_OK;
        }

        id<MTLCommandBuffer> commandBuffer = [impl->queue commandBuffer];
        pyro_metal::GpuBuffers buffers{};
        buffers.planes[0] = (void*)impl->planes[0];
        buffers.planes[1] = (void*)impl->planes[1];
        buffers.planes[2] = (void*)impl->planes[2];
        int32_t rc = api->decodeGpu(impl->decoder, (void*)commandBuffer, &buffers);
        if (rc != pyro_metal::kSuccess) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "PyroWave Metal: decode failed (%s)", metalResult(api, rc));
            return DR_OK;
        }
        // Same queue as present. A later committed render sees these writes.
        [commandBuffer commit];

        bool replaced = false;
        uint64_t readyUs = 0;
        {
            std::lock_guard<std::mutex> lock(impl->frameLock);
            if (haveSequence) {
                impl->sequence = sequence;
                impl->haveSequence = true;
            }
            replaced = impl->frameReady;
            readyUs = LiGetMicroseconds();
            impl->decodeReadyUs = readyUs;
            impl->frameReady = true;
        }
        uint64_t decodeUs = readyUs - decodeStartUs;
        impl->activeStats.totalDecodeTimeUs += decodeUs;
        impl->activeStats.decodedFrames++;
        {
            std::lock_guard<std::mutex> lock(impl->statsLock);
            impl->steady.decodeSubmitUs.add(decodeUs);
            if (replaced) {
                impl->steady.replacedBeforePresent++;
            }
        }

        SDL_Event event{};
        event.type = SDL_USEREVENT;
        event.user.code = SDL_CODE_FRAME_READY;
        SDL_PushEvent(&event);
        return DR_OK;
    }
}

void PyroWaveMetalVideoDecoder::renderFrameOnMainThread()
{
    @autoreleasepool {
        Impl* impl = m_Impl;
        PyroWaveSequenceHeader sequence{};
        bool haveSequence = false;
        uint64_t frameReadyUs = 0;
        {
            std::lock_guard<std::mutex> lock(impl->frameLock);
            if (!impl->frameReady) {
                return;
            }
            impl->frameReady = false;
            haveSequence = impl->haveSequence;
            sequence = impl->sequence;
            frameReadyUs = impl->decodeReadyUs;
        }
        uint64_t renderStartUs = LiGetMicroseconds();
        auto noteStall = [&]() {
            std::lock_guard<std::mutex> lock(impl->statsLock);
            impl->steady.stalledPresents++;
        };
        if (impl->layer == nullptr || impl->queue == nullptr) {
            noteStall();
            return;
        }

        const PyroWavePresentColor color = pyroWavePresentColor(impl->hdr.load(), haveSequence ? &sequence : nullptr);
        if (impl->videoPipeline == nil || !impl->presentValid || !pyroWavePresentColorEqual(color, impl->present)) {
            if (!buildPipelines(impl, color)) {
                noteStall();
                return;
            }
        }
        int drawableWidth = 0;
        int drawableHeight = 0;
        SDL_Metal_GetDrawableSize(impl->window, &drawableWidth, &drawableHeight);
        if (drawableWidth > 0 && drawableHeight > 0) {
            impl->layer.drawableSize = CGSizeMake(drawableWidth, drawableHeight);
        }
        if (!updateVertices(impl)) {
            noteStall();
            return;
        }

        id<CAMetalDrawable> drawable = [impl->layer nextDrawable];
        if (drawable == nil) {
            // Fullscreen transitions often have no drawable for a frame.
            // Put the frame back so the next event can present it.
            noteStall();
            std::lock_guard<std::mutex> lock(impl->frameLock);
            impl->frameReady = true;
            return;
        }

        MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLCommandBuffer> commandBuffer = [impl->queue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
        [encoder setRenderPipelineState:impl->videoPipeline];
        [encoder setFragmentTexture:impl->planes[0] atIndex:0];
        [encoder setFragmentTexture:impl->planes[1] atIndex:1];
        [encoder setFragmentTexture:impl->planes[2] atIndex:2];
        [encoder setFragmentBuffer:impl->cscBuffer offset:0 atIndex:0];
        [encoder setVertexBuffer:impl->vertexBuffer offset:0 atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];

        for (int i = 0; i < Overlay::OverlayMax; i++) {
            SDL_AtomicLock(&impl->overlayLock);
            id<MTLTexture> overlay = [impl->overlayTextures[i] retain];
            SDL_AtomicUnlock(&impl->overlayLock);
            if (overlay == nil) {
                continue;
            }
            SDL_FRect rect{};
            if (i == Overlay::OverlayStatusUpdate) {
                rect.x = 0;
                rect.y = 0;
            }
            else if (i == Overlay::OverlayDebug) {
                rect.x = 0;
                rect.y = impl->drawableHeight - (int)overlay.height;
            }
            else if (i == Overlay::OverlayDebugAudio) {
                rect.x = impl->drawableWidth - (int)overlay.width;
                rect.y = impl->drawableHeight - (int)overlay.height;
            }
            else if (i == Overlay::OverlayGamepad) {
                // Bottom right. y=0 is the bottom on this path.
                rect.x = SDL_max(0, impl->drawableWidth - (int)overlay.width);
                rect.y = 0;
            }
            rect.w = overlay.width;
            rect.h = overlay.height;
            StreamUtils::screenSpaceToNormalizedDeviceCoords(&rect, impl->drawableWidth, impl->drawableHeight);
            Vertex verts[] = {
                {{rect.x, rect.y, 0.0f, 1.0f}, {0.0f, 1.0f}},
                {{rect.x, rect.y + rect.h, 0.0f, 1.0f}, {0.0f, 0.0f}},
                {{rect.x + rect.w, rect.y, 0.0f, 1.0f}, {1.0f, 1.0f}},
                {{rect.x + rect.w, rect.y + rect.h, 0.0f, 1.0f}, {1.0f, 0.0f}},
            };
            [encoder setRenderPipelineState:impl->overlayPipeline];
            [encoder setFragmentTexture:overlay atIndex:0];
            [encoder setVertexBytes:verts length:sizeof(verts) atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
            [overlay release];
        }
        [encoder endEncoding];
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];

        uint64_t now = LiGetMicroseconds();
        uint64_t presentUs = now - renderStartUs;
        impl->renderedFrames.fetch_add(1);
        impl->totalRenderTimeUs.fetch_add(presentUs);
        {
            std::lock_guard<std::mutex> lock(impl->statsLock);
            impl->steady.presentUs.add(presentUs);
            if (frameReadyUs != 0 && now >= frameReadyUs) {
                impl->steady.decodeToPresentUs.add(now - frameReadyUs);
            }
        }
    }
}

#endif  // HAVE_PYROWAVE_METAL

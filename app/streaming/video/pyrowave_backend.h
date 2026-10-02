#pragma once

// Which PyroWave GPU library presents a frame. The Vulkan decoder is the
// MoltenVK path compiled into this tree. The Metal decoder is a separate
// dylib (metal/pyrowave_metal.h) loaded at runtime. This header is the
// selection rule both the settings UI and Session share, and it does not
// include either library.

enum class PyroWaveBackendRequest {
    Auto = 0,    // macOS: Metal when that dylib and GPU work, otherwise Vulkan
    Metal = 1,
    Vulkan = 2,
};

enum class PyroWaveGpuBackend {
    None = 0,
    Metal = 1,
    Vulkan = 2,
};

struct PyroWaveBackendAvailability {
    bool metal;
    bool vulkan;
};

// Auto prefers Metal. An explicit request never crosses to the other
// library: the SDL window flag (METAL vs VULKAN) has to match the decoder
// that will actually present.
inline PyroWaveGpuBackend selectPyroWaveBackend(PyroWaveBackendRequest request,
                                                PyroWaveBackendAvailability availability)
{
    switch (request) {
    case PyroWaveBackendRequest::Metal:
        return availability.metal ? PyroWaveGpuBackend::Metal : PyroWaveGpuBackend::None;
    case PyroWaveBackendRequest::Vulkan:
        return availability.vulkan ? PyroWaveGpuBackend::Vulkan : PyroWaveGpuBackend::None;
    case PyroWaveBackendRequest::Auto:
    default:
        if (availability.metal) {
            return PyroWaveGpuBackend::Metal;
        }
        if (availability.vulkan) {
            return PyroWaveGpuBackend::Vulkan;
        }
        return PyroWaveGpuBackend::None;
    }
}

inline const char* pyroWaveBackendName(PyroWaveGpuBackend backend)
{
    switch (backend) {
    case PyroWaveGpuBackend::Metal:
        return "Metal";
    case PyroWaveGpuBackend::Vulkan:
        return "Vulkan";
    case PyroWaveGpuBackend::None:
    default:
        return "none";
    }
}

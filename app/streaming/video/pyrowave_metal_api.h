#pragma once

// ABI snapshot of andygrundman/pyrowave metal/pyrowave_metal.h at
// 89f7e47d4abbf650c91fae766728af866c5e32a0 (API 0.5.0, MIT,
// Copyright (c) 2026 Hans-Kristian Arntzen).
//
// That header's C names (pyrowave_decoder_create, pyrowave_device_destroy, …)
// are the same names libpyrowave-shared exports at the MoltenVK pin
// 263ef100. The Metal dylib is dlopen'd with RTLD_LOCAL and these layouts
// are what we pass. Do not include the upstream header from a translation
// unit that also sees the Vulkan pyrowave.h: the struct layouts differ
// (the Vulkan create-info has fragment_path; decode_gpu_buffer takes
// timeline semaphores there and an MTLCommandBuffer here).
//
// metal/ is not in the 263ef100 tree. A newer checkout is built separately
// and is not a submodule bump.

#include <stddef.h>
#include <stdint.h>

namespace pyro_metal {

static const uint32_t kApiMajor = 0;
static const uint32_t kApiMinor = 5;
static const char kGit[] = "89f7e47d4abbf650c91fae766728af866c5e32a0";

static const int32_t kSuccess = 0;
static const int32_t kChroma420 = 0;
static const int32_t kChroma444 = 1;

// pyrowave_device_create_info
struct DeviceCreateInfo {
    void* mtlDevice;
    void (*messageCallback)(void* userdata, const char* msg);
    void* messageUserdata;
};

// pyrowave_decoder_create_info. The Vulkan struct at 263ef100 is larger
// (it carries fragment_path). This is the Metal layout only.
struct DecoderCreateInfo {
    void* device;
    int32_t width;
    int32_t height;
    int32_t chroma;
};

// pyrowave_gpu_buffers. Three single-channel MTLTextures (Y, Cb, Cr).
struct GpuBuffers {
    void* planes[3];
};

static_assert(sizeof(void*) == 8, "PyroWave Metal ABI snapshot is 64-bit");
static_assert(sizeof(DeviceCreateInfo) == 24, "DeviceCreateInfo drifted from pyrowave_metal.h 0.5.0");
static_assert(sizeof(DecoderCreateInfo) == 24, "DecoderCreateInfo drifted from pyrowave_metal.h 0.5.0");
static_assert(sizeof(GpuBuffers) == 24, "GpuBuffers drifted from pyrowave_metal.h 0.5.0");

}  // namespace pyro_metal

#include "pyrowave_backend.h"
#include "pyrowave_metal_api.h"

#include <cstdio>

static int g_Failures = 0;

static void expect(PyroWaveGpuBackend actual, PyroWaveGpuBackend expected, const char* label)
{
    if (actual != expected) {
        std::printf("FAIL %s: got %s, expected %s\n",
                    label, pyroWaveBackendName(actual), pyroWaveBackendName(expected));
        g_Failures++;
    }
}

int main()
{
    const PyroWaveBackendAvailability both{true, true};
    const PyroWaveBackendAvailability metalOnly{true, false};
    const PyroWaveBackendAvailability vulkanOnly{false, true};
    const PyroWaveBackendAvailability neither{false, false};

    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Auto, both), PyroWaveGpuBackend::Metal, "auto both");
    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Auto, metalOnly), PyroWaveGpuBackend::Metal, "auto metal");
    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Auto, vulkanOnly), PyroWaveGpuBackend::Vulkan, "auto vulkan");
    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Auto, neither), PyroWaveGpuBackend::None, "auto none");

    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Metal, both), PyroWaveGpuBackend::Metal, "force metal");
    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Metal, vulkanOnly), PyroWaveGpuBackend::None, "force metal without it");
    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Vulkan, both), PyroWaveGpuBackend::Vulkan, "force vulkan");
    expect(selectPyroWaveBackend(PyroWaveBackendRequest::Vulkan, metalOnly), PyroWaveGpuBackend::None, "force vulkan without it");

    if (g_Failures != 0) {
        std::printf("%d pyrowave backend tests failed\n", g_Failures);
        return 1;
    }
    std::printf("pyrowave backend tests passed\n");
    return 0;
}

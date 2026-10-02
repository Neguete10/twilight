#include "pyrowave_stats.h"

#include <cstdio>
#include <cstring>

static int g_Failures = 0;

static void expect(bool ok, const char* label)
{
    if (!ok) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static void testPercentiles()
{
    PyroWaveUsHistogram hist;
    for (int i = 0; i < 980; i++) {
        hist.add(2000);
    }
    for (int i = 0; i < 20; i++) {
        hist.add(40000);
    }
    uint32_t p50 = 0;
    uint32_t p95 = 0;
    uint32_t p99 = 0;
    expect(hist.percentileUs(0.50, &p50), "p50 exists");
    expect(hist.percentileUs(0.95, &p95), "p95 exists");
    expect(hist.percentileUs(0.99, &p99), "p99 exists");
    // 2000 us is bucket [2000, 2100), midpoint 2050.
    // 40000 us is bucket [40000, 40100), midpoint 40050.
    expect(p50 == 2050, "p50 is the common bucket");
    expect(p95 == 2050, "p95 is still the common bucket");
    expect(p99 == 40050, "p99 reaches the tail");
    expect(hist.overflow == 0, "in-range samples are not overflow");
    expect(hist.count == 1000, "count");

    PyroWaveUsHistogram empty;
    expect(!empty.percentileUs(0.50, &p50), "empty histogram has no percentile");

    PyroWaveUsHistogram hitch;
    hitch.add(250000);
    uint32_t over = 0;
    expect(hitch.percentileUs(0.99, &over), "overflow percentile exists");
    expect(over == 250000, "overflow reports the observed maximum");
    expect(hitch.overflow == 1, "one overflow");
}

static void testFormat()
{
    PyroWaveUsHistogram hist;
    hist.add(1500);
    char line[256];
    pyroWaveFormatPercentile(line, sizeof(line), "decode_submit_ms", hist);
    expect(std::strstr(line, "PyroWave metric: decode_submit_ms ") == line, "percentile prefix");
    expect(std::strstr(line, "n=1") != nullptr, "sample count");
    expect(std::strstr(line, "p50=n/a") == nullptr, "a sample is not n/a");

    pyroWaveFormatPercentile(line, sizeof(line), "present_ms", PyroWaveUsHistogram{});
    expect(std::strcmp(line, "PyroWave metric: present_ms p50=n/a p95=n/a p99=n/a n=0 overflow=0") == 0,
           "empty percentile line");

    PyroWaveRateStats rates = pyroWaveMakeRates(120, 118, 100, 122, 2, 118000, 800000, 40000, 1000000, 2.0);
    expect(rates.haveRates, "rates exist");
    expect(rates.receivedFps == 60.0, "received fps");
    expect(rates.renderedFps == 50.0, "rendered fps");
    expect(rates.networkDropped == 2, "drops");
    expect(rates.haveAvgDecode && rates.avgDecodeMs > 0.9 && rates.avgDecodeMs < 1.1, "avg decode ms");
    expect(rates.haveMbps && rates.avgMbps == 4.0, "mbps");

    PyroWaveSteadyState steady;
    steady.decodeSubmitUs.add(1500);
    char seen[32][640];
    int count = 0;
    pyroWaveEmitMetrics("Vulkan", steady, rates, [&](const char* emitted) {
        if (count < 32) {
            std::snprintf(seen[count], sizeof(seen[0]), "%s", emitted);
            count++;
        }
    });
    expect(count > 5, "emitted several lines");
    expect(std::strstr(seen[0], "backend=Vulkan") != nullptr, "backend is first");
    bool sawNote = false;
    bool sawDecode = false;
    for (int i = 0; i < count; i++) {
        if (std::strstr(seen[i], "timing_note=") != nullptr && std::strstr(seen[i], "not the first-packet wait") != nullptr) {
            sawNote = true;
        }
        if (std::strstr(seen[i], "decode_submit_ms ") != nullptr) {
            sawDecode = true;
        }
    }
    expect(sawDecode, "decode percentile emitted");
    expect(sawNote, "timing note says this is not the first-packet wait");
}

int main()
{
    testPercentiles();
    testFormat();
    if (g_Failures != 0) {
        std::printf("%d pyrowave stats tests failed\n", g_Failures);
        return 1;
    }
    std::printf("pyrowave stats tests passed\n");
    return 0;
}

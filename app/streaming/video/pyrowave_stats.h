#pragma once

// Session-long PyroWave frame-time histograms shared by the Vulkan and Metal
// decoders. Both write the same "PyroWave metric:" lines so a log summary can
// compare them. These are CPU timestamps around submit and present, not
// glass-to-glass latency and not the first-packet wait.

#include <stdint.h>
#include <stdio.h>

struct PyroWaveUsHistogram {
    // 0.1 ms buckets up to 200 ms. Longer samples land in overflow and the
    // percentile falls back to the observed maximum, which the log reports
    // separately so a hitch is not hidden inside a bucket.
    // Enums, not static constexpr data members: this tree builds as C++11.
    enum : uint32_t {
        kBucketUs = 100,
        kMaxUs = 200000,
        kBuckets = kMaxUs / kBucketUs
    };

    uint32_t buckets[kBuckets];
    uint32_t overflow;
    uint64_t count;
    uint64_t sumUs;
    uint32_t maxUs;

    PyroWaveUsHistogram()
        : buckets(),
          overflow(0),
          count(0),
          sumUs(0),
          maxUs(0)
    {
    }

    void add(uint64_t us)
    {
        uint32_t stored = us > 0xffffffffu ? 0xffffffffu : (uint32_t)us;
        if (stored >= kMaxUs) {
            overflow++;
        }
        else {
            buckets[stored / kBucketUs]++;
        }
        count++;
        sumUs += us;
        if (stored > maxUs) {
            maxUs = stored;
        }
    }

    // Nearest-rank percentile. The reported value is the midpoint of the
    // 0.1 ms bucket that contains that rank. Empty histogram returns false.
    bool percentileUs(double p, uint32_t* outUs) const
    {
        if (count == 0 || outUs == nullptr) {
            return false;
        }
        if (p < 0) {
            p = 0;
        }
        if (p > 1) {
            p = 1;
        }
        double rank = p * (double)count;
        uint64_t need = (uint64_t)rank;
        if ((double)need + 1e-6 < rank) {
            need++;
        }
        if (need < 1) {
            need = 1;
        }
        if (need > count) {
            need = count;
        }
        uint64_t seen = 0;
        for (uint32_t i = 0; i < kBuckets; i++) {
            seen += buckets[i];
            if (seen >= need) {
                *outUs = i * kBucketUs + kBucketUs / 2;
                return true;
            }
        }
        *outUs = maxUs > 0 ? maxUs : kMaxUs;
        return true;
    }
};

// Strings are fixed so a stats snapshot does not allocate. "unknown" means
// the decoder has not observed that fact yet.
struct PyroWaveSteadyState {
    PyroWaveUsHistogram decodeSubmitUs;
    PyroWaveUsHistogram presentUs;
    PyroWaveUsHistogram decodeToPresentUs;
    uint32_t stalledPresents;
    uint32_t replacedBeforePresent;
    char gpu[160];
    char cpu[80];
    char resolution[32];
    char videoFormat[16];
    char vsync[8];
    char swapchainDepth[8];
    char colorAdvertised[48];
    char color[96];
    char pixelFormat[64];
    char planeFormat[32];

    PyroWaveSteadyState()
        : stalledPresents(0),
          replacedBeforePresent(0)
    {
        set(gpu, sizeof(gpu), "unknown");
        set(cpu, sizeof(cpu), "not sampled");
        set(resolution, sizeof(resolution), "unknown");
        set(videoFormat, sizeof(videoFormat), "unknown");
        set(vsync, sizeof(vsync), "unknown");
        set(swapchainDepth, sizeof(swapchainDepth), "unknown");
        set(colorAdvertised, sizeof(colorAdvertised), "unknown");
        set(color, sizeof(color), "unknown");
        set(pixelFormat, sizeof(pixelFormat), "unknown");
        set(planeFormat, sizeof(planeFormat), "unknown");
    }

    static void set(char* dst, size_t n, const char* src)
    {
        if (n == 0) {
            return;
        }
        if (src == nullptr) {
            src = "";
        }
        snprintf(dst, n, "%s", src);
    }
};

struct PyroWaveRateStats {
    bool haveRates;
    double receivedFps;
    double decodedFps;
    double renderedFps;
    bool haveAvgDecode;
    double avgDecodeMs;
    bool haveAvgPresent;
    double avgPresentMs;
    bool haveAvgReassembly;
    double avgReassemblyMs;
    bool haveMbps;
    double avgMbps;
    uint32_t networkDropped;
    uint32_t decodedFrames;
    uint32_t renderedFrames;
    uint32_t totalFrames;
};

inline PyroWaveRateStats pyroWaveMakeRates(uint32_t receivedFrames,
                                           uint32_t decodedFrames,
                                           uint32_t renderedFrames,
                                           uint32_t totalFrames,
                                           uint32_t networkDropped,
                                           uint64_t totalDecodeUs,
                                           uint64_t totalPresentUs,
                                           uint64_t totalReassemblyUs,
                                           uint64_t receivedBytes,
                                           double elapsedSec)
{
    PyroWaveRateStats rates = {};
    rates.networkDropped = networkDropped;
    rates.decodedFrames = decodedFrames;
    rates.renderedFrames = renderedFrames;
    rates.totalFrames = totalFrames;
    rates.haveRates = elapsedSec > 0 && (receivedFrames > 0 || decodedFrames > 0 || renderedFrames > 0 || totalFrames > 0);
    if (rates.haveRates) {
        rates.receivedFps = (double)receivedFrames / elapsedSec;
        rates.decodedFps = (double)decodedFrames / elapsedSec;
        rates.renderedFps = (double)renderedFrames / elapsedSec;
    }
    if (decodedFrames > 0) {
        rates.haveAvgDecode = true;
        rates.avgDecodeMs = (totalDecodeUs / 1000.0) / (double)decodedFrames;
        rates.haveAvgReassembly = true;
        rates.avgReassemblyMs = (totalReassemblyUs / 1000.0) / (double)decodedFrames;
    }
    if (renderedFrames > 0) {
        rates.haveAvgPresent = true;
        rates.avgPresentMs = (totalPresentUs / 1000.0) / (double)renderedFrames;
    }
    if (elapsedSec > 0 && receivedBytes > 0) {
        rates.haveMbps = true;
        rates.avgMbps = ((double)receivedBytes * 8.0) / 1000000.0 / elapsedSec;
    }
    return rates;
}

inline const char* pyroWaveTimingNote()
{
    return "decode_submit is CPU time until the GPU command is queued, not GPU completion; "
           "present is CPU time inside the present call and can include a GPU wait; "
           "decode_to_present is present-return minus decode-submit-end; "
           "histogram buckets are 0.1 ms; "
           "not glass-to-glass and not the first-packet wait";
}

inline void pyroWaveFormatPercentile(char* buf, size_t n, const char* key, const PyroWaveUsHistogram& hist)
{
    if (hist.count == 0) {
        snprintf(buf, n, "PyroWave metric: %s p50=n/a p95=n/a p99=n/a n=0 overflow=0", key);
        return;
    }
    uint32_t p50 = 0;
    uint32_t p95 = 0;
    uint32_t p99 = 0;
    hist.percentileUs(0.50, &p50);
    hist.percentileUs(0.95, &p95);
    hist.percentileUs(0.99, &p99);
    snprintf(buf, n,
             "PyroWave metric: %s p50=%.2f p95=%.2f p99=%.2f n=%llu overflow=%u",
             key,
             p50 / 1000.0,
             p95 / 1000.0,
             p99 / 1000.0,
             (unsigned long long)hist.count,
             hist.overflow);
}

inline void pyroWaveFormatOptional(char* buf, size_t n, const char* key, double value, bool valid)
{
    if (!valid) {
        snprintf(buf, n, "PyroWave metric: %s=n/a", key);
    }
    else {
        snprintf(buf, n, "PyroWave metric: %s=%.2f", key, value);
    }
}

// One line per fact. The summary script keeps the last value of each key.
template <typename Log>
void pyroWaveEmitMetrics(const char* backend, const PyroWaveSteadyState& steady, const PyroWaveRateStats& rates, Log log)
{
    char line[640];
    snprintf(line, sizeof(line), "PyroWave metric: backend=%s", backend != nullptr ? backend : "unknown");
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: gpu=%s", steady.gpu);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: cpu=%s", steady.cpu);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: resolution=%s", steady.resolution);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: video_format=%s", steady.videoFormat);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: vsync=%s", steady.vsync);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: swapchain_depth=%s", steady.swapchainDepth);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: color_advertised=%s", steady.colorAdvertised);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: color=%s", steady.color);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: pixel_format=%s", steady.pixelFormat);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: plane_format=%s", steady.planeFormat);
    log(line);
    pyroWaveFormatPercentile(line, sizeof(line), "decode_submit_ms", steady.decodeSubmitUs);
    log(line);
    pyroWaveFormatPercentile(line, sizeof(line), "present_ms", steady.presentUs);
    log(line);
    pyroWaveFormatPercentile(line, sizeof(line), "decode_to_present_ms", steady.decodeToPresentUs);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: network_dropped=%u", rates.networkDropped);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: stalled_presents=%u", steady.stalledPresents);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: replaced_before_present=%u", steady.replacedBeforePresent);
    log(line);
    pyroWaveFormatOptional(line, sizeof(line), "received_fps", rates.receivedFps, rates.haveRates);
    log(line);
    pyroWaveFormatOptional(line, sizeof(line), "decoded_fps", rates.decodedFps, rates.haveRates);
    log(line);
    pyroWaveFormatOptional(line, sizeof(line), "rendered_fps", rates.renderedFps, rates.haveRates);
    log(line);
    pyroWaveFormatOptional(line, sizeof(line), "avg_decode_ms", rates.avgDecodeMs, rates.haveAvgDecode);
    log(line);
    pyroWaveFormatOptional(line, sizeof(line), "avg_present_ms", rates.avgPresentMs, rates.haveAvgPresent);
    log(line);
    pyroWaveFormatOptional(line, sizeof(line), "avg_reassembly_ms", rates.avgReassemblyMs, rates.haveAvgReassembly);
    log(line);
    pyroWaveFormatOptional(line, sizeof(line), "avg_mbps", rates.avgMbps, rates.haveMbps);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: decoded_frames=%u", rates.decodedFrames);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: rendered_frames=%u", rates.renderedFrames);
    log(line);
    snprintf(line, sizeof(line), "PyroWave metric: timing_note=%s", pyroWaveTimingNote());
    log(line);
}

#include "streamhudparse.h"

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

static void testPyroWaveSample()
{
    const char* text =
        "Video stream: 2560x1440 120.00 FPS (Codec: PyroWave Vulkan 4:2:0)\n"
        "Bitrate: 100.0 Mbps requested, 80.0 Mbps encoder target, 74.2 Mbps measured, Peak (3s): 90.5\n"
        "Incoming frame rate from network: 119.50 FPS\n"
        "Average network latency: N/A\n";
    TwilightHudSample sample;
    expect(twilightParseHudSample(text, &sample), "pyro parses");
    expect(sample.fps > 119.9 && sample.fps < 120.1, "pyro fps is the stream fps");
    expect(sample.hasBitrate, "pyro has bitrate");
    expect(sample.bitrateMbps > 74.1 && sample.bitrateMbps < 74.3, "pyro chip uses the measured bitrate");
    expect(!sample.hasLatency, "pyro N/A latency is omitted");
    expect(std::strcmp(sample.codec, "PyroWave Vulkan 4:2:0") == 0, "pyro codec");
    expect(std::strstr(sample.codec, "forward") == nullptr, "pyro codec has no fec wording");
}

static void testFfmpegSampleDropsFec()
{
    const char* text =
        "Video stream: 1920x1080 59.94 FPS (Codec: HEVC)\n"
        "Bitrate: 800.0 kbps, +12% forward error-correction\n"
        "FPS incoming/decoding/rendering: 59.00/58.00/57.00\n"
        "Average network latency: 8 ms (variance: 1 ms)\n"
        "Average decoding time: 1.20 ms\n";
    TwilightHudSample sample;
    expect(twilightParseHudSample(text, &sample), "ffmpeg parses");
    expect(sample.fps > 59.9 && sample.fps < 60.0, "ffmpeg fps");
    expect(sample.hasBitrate, "ffmpeg has bitrate");
    expect(sample.bitrateMbps > 0.79 && sample.bitrateMbps < 0.81, "kbps converted, fec percent ignored");
    expect(sample.hasLatency && sample.latencyMs > 7.9 && sample.latencyMs < 8.1, "rtt without variance");
    expect(std::strcmp(sample.codec, "HEVC") == 0, "hevc codec");
}

static void testLegacyBitrateLine()
{
    const char* text =
        "Video stream: 1920x1080 60.00 FPS (Codec: HEVC)\n"
        "Bitrate: 80.0 Mbps, Peak (3s): 90.5\n"
        "Average network latency: 4 ms\n";
    TwilightHudSample sample;
    expect(twilightParseHudSample(text, &sample), "legacy bitrate line parses");
    expect(sample.hasBitrate, "legacy line has bitrate");
    expect(sample.bitrateMbps > 79.9 && sample.bitrateMbps < 80.1, "legacy line uses the only bitrate");
}

static void testRejectsEmpty()
{
    TwilightHudSample sample;
    expect(!twilightParseHudSample(nullptr, &sample), "null text");
    expect(!twilightParseHudSample("", &sample), "empty text");
    expect(!twilightParseHudSample("no counters here", &sample), "unrelated text");
    expect(!twilightParseHudSample(nullptr, nullptr), "null output");
}

int main()
{
    testPyroWaveSample();
    testFfmpegSampleDropsFec();
    testLegacyBitrateLine();
    testRejectsEmpty();
    if (g_Failures != 0) {
        std::printf("%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("twilight hud parse ok\n");
    return 0;
}

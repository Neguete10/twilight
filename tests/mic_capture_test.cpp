#include "mic_resample.h"
#include "mic_wire.h"

#include <cstdio>
#include <cstring>
#include <vector>

static int g_failures = 0;

static void expect(bool condition, const char* message)
{
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        g_failures++;
    }
}

static void testPacketLayout()
{
    const uint8_t opus[] = {0x11, 0x22, 0x33, 0x44};
    MicWire::Packet packet;
    std::memset(packet.bytes, 0xAB, sizeof(packet.bytes));
    expect(MicWire::buildPacket(0x1234, opus, 4, packet), "build");
    expect(packet.type == MicWire::kPacketType, "type 0x3003");
    expect(packet.type == 0x3003, "literal type");
    expect(packet.length == 8, "length");
    expect(packet.bytes[0] == 0x12 && packet.bytes[1] == 0x34, "sequence big-endian");
    expect(packet.bytes[2] == 1, "mono channel byte");
    expect(packet.bytes[3] == 0, "flags");
    expect(std::memcmp(packet.bytes + 4, opus, 4) == 0, "opus copied");

    expect(MicWire::buildPacket(0, opus, 4, packet), "sequence zero");
    expect(packet.bytes[0] == 0 && packet.bytes[1] == 0, "sequence zero bytes");

    expect(MicWire::buildPacket(0x00AB, opus, 4, packet), "sequence 0x00AB");
    expect(packet.bytes[0] == 0x00 && packet.bytes[1] == 0xAB, "sequence 0x00AB bytes");
}

static void testPacketLimits()
{
    uint8_t opus[MicWire::kMaxOpusBytes + 1];
    std::memset(opus, 0x5A, sizeof(opus));
    MicWire::Packet packet;

    expect(MicWire::buildPacket(1, opus, MicWire::kMaxOpusBytes, packet), "247 byte opus fits");
    expect(packet.length == MicWire::kMaxControlPayload, "payload is 251");
    expect(packet.bytes[0] == 0 && packet.bytes[1] == 1, "sequence of the max packet");
    expect(packet.bytes[MicWire::kHeaderBytes] == 0x5A, "first opus byte");
    expect(packet.bytes[MicWire::kMaxControlPayload - 1] == 0x5A, "last opus byte");

    expect(!MicWire::buildPacket(1, opus, MicWire::kMaxOpusBytes + 1, packet), "248 byte opus rejected");
    expect(!MicWire::buildPacket(1, opus, 0, packet), "empty rejected");
    expect(!MicWire::buildPacket(1, nullptr, 4, packet), "null rejected");
    expect(!MicWire::buildPacket(1, opus, -1, packet), "negative rejected");
}

static void testResamplerIdentity()
{
    const float input[] = {0.f, 0.5f, -0.5f, 1.f};
    const float* planes[] = {input};
    MicResampler resampler;
    resampler.reset(48000);
    std::vector<int16_t> output;
    resampler.process(planes, 1, 4, output);
    expect(output.size() == 4, "48 kHz keeps one sample per input");
    expect(output.size() == 4 && output[0] == 0, "zero");
    expect(output.size() == 4 && output[1] == 16384, "half scale");
    expect(output.size() == 4 && output[2] == -16384, "negative half");
    expect(output.size() == 4 && output[3] == 32767, "full scale");

    float ramp[100];
    for (int i = 0; i < 100; i++) {
        ramp[i] = (float)i / 100.f;
    }
    const float* rampPlanes[] = {ramp};
    resampler.reset(48000);
    output.clear();
    resampler.process(rampPlanes, 1, 100, output);
    expect(output.size() == 100, "48 kHz ramp keeps the sample count");
}

static void testResamplerDownmixAndRates()
{
    const float left[] = {1.f, 0.25f};
    const float right[] = {-1.f, 0.25f};
    const float* planes[] = {left, right};
    MicResampler resampler;
    resampler.reset(48000);
    std::vector<int16_t> output;
    resampler.process(planes, 2, 2, output);
    expect(output.size() == 2, "stereo frame count");
    expect(output.size() == 2 && output[0] == 0, "stereo cancels");
    expect(output.size() == 2 && output[1] == 8192, "stereo average of 0.25");

    const float hot[] = {1.5f, -1.5f};
    const float* hotPlanes[] = {hot};
    resampler.reset(48000);
    output.clear();
    resampler.process(hotPlanes, 1, 2, output);
    expect(output.size() == 2 && output[0] == 32767, "clamp high");
    expect(output.size() == 2 && output[1] == -32767, "clamp low");

    float doubled[4];
    for (int i = 0; i < 4; i++) {
        doubled[i] = 0.25f;
    }
    const float* doubledPlanes[] = {doubled};
    resampler.reset(96000);
    output.clear();
    resampler.process(doubledPlanes, 1, 4, output);
    expect(output.size() == 2, "96 kHz emits half as many samples");
    expect(output.size() == 2 && output[0] == 8192 && output[1] == 8192, "96 kHz constant");

    float cd[20];
    for (int i = 0; i < 20; i++) {
        cd[i] = 0.25f;
    }
    const float* cdPlanes[] = {cd};
    resampler.reset(44100);
    output.clear();
    resampler.process(cdPlanes, 1, 20, output);
    expect(output.size() >= 20, "44.1 kHz upsamples");
    bool constant = !output.empty();
    for (size_t i = 0; i < output.size(); i++) {
        if (output[i] != 8192) {
            constant = false;
        }
    }
    expect(constant, "44.1 kHz constant stays constant");

    resampler.reset(0);
    output.clear();
    resampler.process(cdPlanes, 1, 20, output);
    expect(output.empty(), "unknown rate produces nothing");
}

int main()
{
    testPacketLayout();
    testPacketLimits();
    testResamplerIdentity();
    testResamplerDownmixAndRates();
    if (g_failures != 0) {
        std::fprintf(stderr, "%d microphone capture tests failed\n", g_failures);
        return 1;
    }
    std::printf("microphone capture tests passed\n");
    return 0;
}

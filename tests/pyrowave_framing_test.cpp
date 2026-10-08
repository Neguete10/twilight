// Both PyroWave decoders feed PyroWaveFraming::parse. Record framing is what
// a current Vibeshine host sends. Length-prefixed framing is the older envelope.
// The length-prefixed unpacker must keep rejecting a record frame: that is the
// drop the Vulkan decoder used to do on every packet.

#include "streaming/video/pyrowaveframing.h"
#include "streaming/video/pyrowave_packets.h"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

int g_Failures = 0;

void expect(bool cond, const char* message)
{
    if (!cond) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        g_Failures++;
    }
}

void appendU32(std::vector<uint8_t>& bytes, uint32_t value)
{
    bytes.push_back(static_cast<uint8_t>(value));
    bytes.push_back(static_cast<uint8_t>(value >> 8));
    bytes.push_back(static_cast<uint8_t>(value >> 16));
    bytes.push_back(static_cast<uint8_t>(value >> 24));
}

// 128x128, 4:2:0, no blocks. Bit 31 marks a sequence header, which a packet
// count never sets.
std::vector<uint8_t> sequenceHeader()
{
    const uint32_t word0 = 0x80000000u | (127u << 14) | 127u;
    std::vector<uint8_t> bytes;
    appendU32(bytes, word0);
    appendU32(bytes, 0);
    return bytes;
}

PyroWaveFraming::Frame parseFrame(const std::vector<uint8_t>& bytes, std::string& error)
{
    PyroWaveFraming::Frame frame;
    const bool ok = PyroWaveFraming::parse(bytes.data(), bytes.size(),
                                            {128, 128, false}, frame, error);
    expect(ok, error.empty() ? "parse failed" : error.c_str());
    return frame;
}

void testRecordFraming()
{
    const std::vector<uint8_t> bytes = sequenceHeader();
    expect((bytes[3] & 0x80) != 0, "record frame sets the sequence-header bit");

    std::vector<PyroWavePacketView> packets;
    bool truncated = false;
    expect(!pyroWaveUnpackLengthPrefixedFrame(bytes.data(), bytes.size(), packets, &truncated),
           "length-prefixed unpacker rejects a record frame");
    expect(packets.empty(), "rejected record frame yields no packets");

    std::string error;
    const PyroWaveFraming::Frame frame = parseFrame(bytes, error);
    expect(frame.framing == PyroWaveFraming::Framing::Records, "record framing");
    expect(frame.sequenceHeaderSeen, "record frame has a sequence header");
    expect(!frame.partial, "intact record frame is not partial");
    expect(frame.blockRecords == 0 && frame.announcedBlocks == 0, "header-only frame has no blocks");
    expect(frame.spans.size() == 1, "record frame is one span");
    if (frame.spans.size() == 1) {
        expect(frame.spans[0].offset == 0 && frame.spans[0].size == bytes.size(),
               "record span is the sequence header");
    }
}

void testLengthPrefixedFraming()
{
    const std::vector<uint8_t> header = sequenceHeader();
    std::vector<uint8_t> bytes;
    appendU32(bytes, 1);
    appendU32(bytes, static_cast<uint32_t>(header.size()));
    bytes.insert(bytes.end(), header.begin(), header.end());

    std::vector<PyroWavePacketView> packets;
    expect(pyroWaveUnpackLengthPrefixedFrame(bytes.data(), bytes.size(), packets, nullptr),
           "length-prefixed unpacker accepts the older envelope");
    expect(packets.size() == 1 && packets[0].size == header.size(), "one inner packet");

    std::string error;
    const PyroWaveFraming::Frame frame = parseFrame(bytes, error);
    expect(frame.framing == PyroWaveFraming::Framing::LengthPrefixed, "length-prefixed framing");
    expect(frame.sequenceHeaderSeen && !frame.partial, "intact length-prefixed frame");
    expect(frame.spans.size() == 1, "length-prefixed frame is one span");
    if (frame.spans.size() == 1) {
        expect(frame.spans[0].offset == 8 && frame.spans[0].size == header.size(),
               "span skips the count and size words");
        expect(std::memcmp(bytes.data() + frame.spans[0].offset, header.data(), header.size()) == 0,
               "span bytes are the sequence header");
    }
}

} // namespace

int main()
{
    testRecordFraming();
    testLengthPrefixedFraming();
    if (g_Failures != 0) {
        std::fprintf(stderr, "%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}

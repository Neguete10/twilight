#include "pyrowave_packets.h"

#include <cstdio>
#include <cstring>
#include <vector>

static int g_failures = 0;

static void expect(bool cond, const char* message)
{
    if (!cond) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        g_failures++;
    }
}

static void testLengthPrefix()
{
    // ballot=1, payload_words=2, sequence=3, extended=0, quant=0x10, block=0xAB
    const uint8_t packet[] = {0x01, 0x00, 0x02, 0x30, 0x10, 0xAB, 0x00, 0x00};
    std::vector<uint8_t> frame;
    auto appendU32 = [&](uint32_t v) {
        frame.push_back((uint8_t)(v & 0xFF));
        frame.push_back((uint8_t)((v >> 8) & 0xFF));
        frame.push_back((uint8_t)((v >> 16) & 0xFF));
        frame.push_back((uint8_t)((v >> 24) & 0xFF));
    };
    appendU32(1);
    appendU32(sizeof(packet));
    frame.insert(frame.end(), packet, packet + sizeof(packet));

    std::vector<PyroWavePacketView> packets;
    bool truncated = true;
    expect(pyroWaveUnpackLengthPrefixedFrame(frame.data(), frame.size(), packets, &truncated), "unpack");
    expect(!truncated, "not truncated");
    expect(packets.size() == 1, "one packet");
    expect(packets.size() == 1 && packets[0].size == sizeof(packet), "packet size");
    expect(packets.size() == 1 && std::memcmp(packets[0].data, packet, sizeof(packet)) == 0, "packet bytes");

    PyroWaveBitstreamHeader hdr;
    expect(pyroWaveParseBitstreamHeader(packet, sizeof(packet), hdr), "coeff header");
    expect(hdr.ballot == 0x0001, "ballot");
    expect(hdr.payloadWords == 2, "payload words");
    expect(hdr.sequence == 3, "sequence");
    expect(!hdr.extended, "not extended");
    expect(hdr.quantCode == 0x10, "quant");
    expect(hdr.blockIndex == 0xAB, "block index");

    // Second packet claims more bytes than remain.
    appendU32(0); // will rebuild
    frame.clear();
    appendU32(2);
    appendU32(4);
    frame.insert(frame.end(), packet, packet + 4);
    appendU32(100);
    frame.push_back(0xFF);
    truncated = false;
    expect(pyroWaveUnpackLengthPrefixedFrame(frame.data(), frame.size(), packets, &truncated), "partial unpack");
    expect(truncated, "truncated flag");
    expect(packets.size() == 1 && packets[0].size == 4, "kept the intact prefix");

    const uint8_t hostile[] = {0xFF, 0xFF, 0xFF, 0xFF};
    expect(!pyroWaveUnpackLengthPrefixedFrame(hostile, sizeof(hostile), packets, &truncated), "reject huge count");
    expect(!pyroWaveUnpackLengthPrefixedFrame(nullptr, 0, packets, &truncated), "reject empty");
}

static void testSequenceHeader()
{
    // width=2, height=2, sequence=0, extended=1, total_blocks=1, code=0, 4:2:0
    const uint8_t bytes[] = {0x01, 0x40, 0x00, 0x80, 0x01, 0x00, 0x00, 0x00};
    PyroWaveSequenceHeader seq;
    expect(pyroWaveParseSequenceHeader(bytes, sizeof(bytes), seq), "sof");
    expect(seq.width == 2 && seq.height == 2, "dimensions");
    expect(seq.sequence == 0, "sof sequence");
    expect(seq.totalBlocks == 1, "total blocks");
    expect(seq.code == 0, "start of frame code");
    expect(!seq.chroma444, "420");
    expect(!seq.pqTransfer && !seq.bt2020Primaries && !seq.limitedRange, "sdr flags");

    // chroma 4:4:4 is bit 26 of word1, PQ is bit 28.
    uint8_t hdr444[8] = {0x01, 0x40, 0x00, 0x80, 0x01, 0x00, 0x00, 0x00};
    hdr444[7] = (uint8_t)((1u << 2) | (1u << 4)); // bits 26 and 28 sit in the top byte (bits 24..31)
    expect(pyroWaveParseSequenceHeader(hdr444, sizeof(hdr444), seq), "444 sof");
    expect(seq.chroma444 && seq.pqTransfer, "444 + PQ");
}

int main()
{
    testLengthPrefix();
    testSequenceHeader();
    if (g_failures != 0) {
        std::fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    std::printf("pyrowave packet tests passed\n");
    return 0;
}

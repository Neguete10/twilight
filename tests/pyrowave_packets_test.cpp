#include "pyrowave_color.h"
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

static PyroWaveSequenceHeader headerWith(uint8_t top)
{
    uint8_t bytes[8] = {0x01, 0x40, 0x00, 0x80, 0x01, 0x00, 0x00, top};
    PyroWaveSequenceHeader seq{};
    expect(pyroWaveParseSequenceHeader(bytes, sizeof(bytes), seq), "color sof");
    return seq;
}

static void testPresentColor()
{
    const PyroWavePresentColor sdr = pyroWavePresentColor(false, nullptr);
    expect(sdr.matrix == PyroWaveMatrix::Bt601, "sdr matrix matches HEVC");
    expect(sdr.range == PyroWaveRange::Limited, "sdr limited");
    expect(sdr.transfer == PyroWaveTransfer::Bt709, "sdr transfer");
    expect(!sdr.chromaLeft, "sdr center chroma");

    const PyroWavePresentColor hdr = pyroWavePresentColor(true, nullptr);
    expect(hdr.matrix == PyroWaveMatrix::Bt2020, "hdr matrix");
    expect(hdr.range == PyroWaveRange::Limited, "hdr keeps advertised limited range");
    expect(hdr.transfer == PyroWaveTransfer::Pq, "hdr pq");

    // All-zero usability bits are what current encoders emit. They must not
    // be read as BT.709 full.
    PyroWaveSequenceHeader unset{};
    unset.code = 0;
    const PyroWavePresentColor ignored = pyroWavePresentColor(false, &unset);
    expect(pyroWavePresentColorEqual(ignored, sdr), "unset header stays Rec.601 limited");

    // bit 27 primaries, bit 28 PQ, bit 29 matrix, bit 30 limited → top byte
    const PyroWaveSequenceHeader pq = headerWith((1u << 3) | (1u << 4) | (1u << 5) | (1u << 6));
    const PyroWavePresentColor pqColor = pyroWavePresentColor(true, &pq);
    expect(pqColor.matrix == PyroWaveMatrix::Bt2020, "signaled 2020");
    expect(pqColor.transfer == PyroWaveTransfer::Pq, "signaled pq");
    expect(pqColor.range == PyroWaveRange::Limited, "signaled limited");

    // Explicit BT.2020, transfer bit clear, HDR mode → HLG. bit 27 + bit 29.
    const PyroWaveSequenceHeader hlg = headerWith((1u << 3) | (1u << 5));
    const PyroWavePresentColor hlgColor = pyroWavePresentColor(true, &hlg);
    expect(hlgColor.transfer == PyroWaveTransfer::Hlg, "hdr + bt2020 without pq is hlg");
    expect(hlgColor.range == PyroWaveRange::Full, "unset range bit with an explicit header is full");

    // Explicit BT.709 (no 2020/PQ bits cannot be represented except by setting
    // limited while leaving the others clear). Limited-only keeps Rec.601.
    const PyroWaveSequenceHeader limitedOnly = headerWith(1u << 6);
    const PyroWavePresentColor limitedColor = pyroWavePresentColor(false, &limitedOnly);
    expect(limitedColor.matrix == PyroWaveMatrix::Bt601, "limited-only does not invent 709");
    expect(limitedColor.range == PyroWaveRange::Limited, "limited-only range");

    // PQ without BT.2020 bits is still an explicit header: Rec.709 + PQ.
    const PyroWaveSequenceHeader pq709 = headerWith(1u << 4);
    const PyroWavePresentColor pq709Color = pyroWavePresentColor(false, &pq709);
    expect(pq709Color.matrix == PyroWaveMatrix::Bt709, "pq without 2020 is rec.709");
    expect(pq709Color.transfer == PyroWaveTransfer::Pq, "pq bit selects pq");
    expect(pq709Color.range == PyroWaveRange::Full, "explicit header without limited bit is full");

    // bit 31 chroma left, nothing else.
    const PyroWaveSequenceHeader left = headerWith(1u << 7);
    const PyroWavePresentColor leftColor = pyroWavePresentColor(false, &left);
    expect(leftColor.chromaLeft, "left chroma siting");
    expect(leftColor.matrix == PyroWaveMatrix::Bt601, "siting does not change matrix");
}

int main()
{
    testLengthPrefix();
    testSequenceHeader();
    testPresentColor();
    if (g_failures != 0) {
        std::fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    std::printf("pyrowave packet tests passed\n");
    return 0;
}

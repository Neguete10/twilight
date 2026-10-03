#pragma once

// Length-prefixed PyroWave frames and the 8-byte bitstream headers from
// Themaister/pyrowave bitstream/bitstream.md. This parser does not run the
// inverse wavelet; it only splits a Moonlight frame and reads headers so the
// GPU decoder (or a test) can see where each packet starts.

#include <cstddef>
#include <cstdint>
#include <vector>

struct PyroWavePacketView {
    const uint8_t* data;
    uint32_t size;
};

struct PyroWaveBitstreamHeader {
    uint16_t ballot;
    uint16_t payloadWords; // includes the 8-byte header; byte size is payloadWords * 4
    uint8_t sequence;      // 0..7
    bool extended;
    uint8_t quantCode;
    uint32_t blockIndex;   // 24-bit
};

struct PyroWaveSequenceHeader {
    uint32_t width;
    uint32_t height;
    uint8_t sequence;
    uint32_t totalBlocks;
    uint8_t code; // 0 = start of frame
    bool chroma444;
    bool bt2020Primaries;
    bool pqTransfer;
    bool bt2020Matrix;
    bool limitedRange;
    bool chromaSitingLeft;
};

// Vibeshine write_length_prefixed_frame():
//   uint32le count, then count times { uint32le size, size bytes }.
// A short buffer after a valid count keeps the packets that fit and sets
// *truncated. Returns false when the count word itself is missing or absurd.
inline bool pyroWaveUnpackLengthPrefixedFrame(const uint8_t* frame,
                                              size_t frameSize,
                                              std::vector<PyroWavePacketView>& out,
                                              bool* truncated)
{
    out.clear();
    if (truncated) {
        *truncated = false;
    }
    if (frame == nullptr || frameSize < 4) {
        return false;
    }

    const uint32_t count = (uint32_t)frame[0]
        | ((uint32_t)frame[1] << 8)
        | ((uint32_t)frame[2] << 16)
        | ((uint32_t)frame[3] << 24);
    // Each remaining packet needs a 4-byte size. Reject counts that cannot
    // possibly fit, including a hostile 0xFFFFFFFF.
    if (count > (frameSize - 4) / 4 || count > 1000000u) {
        return false;
    }

    size_t pos = 4;
    for (uint32_t i = 0; i < count; i++) {
        if (pos + 4 > frameSize) {
            if (truncated) {
                *truncated = true;
            }
            break;
        }
        const uint32_t sz = (uint32_t)frame[pos]
            | ((uint32_t)frame[pos + 1] << 8)
            | ((uint32_t)frame[pos + 2] << 16)
            | ((uint32_t)frame[pos + 3] << 24);
        pos += 4;
        if (pos + sz > frameSize) {
            if (truncated) {
                *truncated = true;
            }
            break;
        }
        PyroWavePacketView view;
        view.data = frame + pos;
        view.size = sz;
        out.push_back(view);
        pos += sz;
    }
    return true;
}

inline bool pyroWaveParseBitstreamHeader(const uint8_t* data, size_t size, PyroWaveBitstreamHeader& out)
{
    if (data == nullptr || size < 8) {
        return false;
    }
    out.ballot = (uint16_t)(data[0] | (data[1] << 8));
    const uint16_t packed = (uint16_t)(data[2] | (data[3] << 8));
    out.payloadWords = (uint16_t)(packed & 0x0FFF);
    out.sequence = (uint8_t)((packed >> 12) & 0x7);
    out.extended = (packed & 0x8000) != 0;
    const uint32_t tail = (uint32_t)data[4]
        | ((uint32_t)data[5] << 8)
        | ((uint32_t)data[6] << 16)
        | ((uint32_t)data[7] << 24);
    out.quantCode = (uint8_t)(tail & 0xFF);
    out.blockIndex = tail >> 8;
    return true;
}

// Reinterprets the same 8 bytes when extended == 1 and code == 0
// (BITSTREAM_EXTENDED_CODE_START_OF_FRAME).
inline bool pyroWaveParseSequenceHeader(const uint8_t* data, size_t size, PyroWaveSequenceHeader& out)
{
    PyroWaveBitstreamHeader bits;
    if (!pyroWaveParseBitstreamHeader(data, size, bits) || !bits.extended) {
        return false;
    }
    const uint32_t word0 = (uint32_t)data[0]
        | ((uint32_t)data[1] << 8)
        | ((uint32_t)data[2] << 16)
        | ((uint32_t)data[3] << 24);
    const uint32_t word1 = (uint32_t)data[4]
        | ((uint32_t)data[5] << 8)
        | ((uint32_t)data[6] << 16)
        | ((uint32_t)data[7] << 24);
    out.width = (word0 & 0x3FFF) + 1;
    out.height = ((word0 >> 14) & 0x3FFF) + 1;
    out.sequence = (uint8_t)((word0 >> 28) & 0x7);
    out.totalBlocks = word1 & 0x00FFFFFF;
    out.code = (uint8_t)((word1 >> 24) & 0x3);
    out.chroma444 = ((word1 >> 26) & 0x1) != 0;
    out.bt2020Primaries = ((word1 >> 27) & 0x1) != 0;
    out.pqTransfer = ((word1 >> 28) & 0x1) != 0;
    out.bt2020Matrix = ((word1 >> 29) & 0x1) != 0;
    out.limitedRange = ((word1 >> 30) & 0x1) != 0;
    out.chromaSitingLeft = ((word1 >> 31) & 0x1) != 0;
    return out.code == 0;
}

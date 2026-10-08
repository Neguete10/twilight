#pragma once

// How a decoded PyroWave frame should be converted to RGB.
//
// Vibeshine builds the YUV planes with the colorspace this client advertised
// (Mac HEVC/VideoToolbox is Rec.601 limited) and, when the host display is
// HDR, switches to Rec.2020 + PQ while keeping that range. The wavelet
// sequence header can also carry primaries, transfer, matrix, and range, but
// current encoders leave those bits zero. Zero means "BT.709 full" in the
// spec and is not what the host encoded, so unset bits are ignored.

#include "pyrowave_packets.h"

#include <vector>

enum class PyroWaveMatrix {
    Bt601 = 0,
    Bt709 = 1,
    Bt2020 = 2,
};

enum class PyroWaveTransfer {
    Bt709 = 0,
    Pq = 1,
    Hlg = 2,
};

enum class PyroWaveRange {
    Limited = 0,
    Full = 1,
};

struct PyroWavePresentColor {
    PyroWaveMatrix matrix;
    PyroWaveTransfer transfer;
    PyroWaveRange range;
    bool chromaLeft;
};

inline bool pyroWavePresentColorEqual(const PyroWavePresentColor& a, const PyroWavePresentColor& b)
{
    return a.matrix == b.matrix && a.transfer == b.transfer && a.range == b.range && a.chromaLeft == b.chromaLeft;
}

inline const char* pyroWaveMatrixName(PyroWaveMatrix matrix)
{
    switch (matrix) {
    case PyroWaveMatrix::Bt601:
        return "Rec.601";
    case PyroWaveMatrix::Bt709:
        return "Rec.709";
    case PyroWaveMatrix::Bt2020:
        return "Rec.2020";
    }
    return "unknown";
}

inline const char* pyroWaveTransferName(PyroWaveTransfer transfer)
{
    switch (transfer) {
    case PyroWaveTransfer::Bt709:
        return "BT.709";
    case PyroWaveTransfer::Pq:
        return "PQ";
    case PyroWaveTransfer::Hlg:
        return "HLG";
    }
    return "unknown";
}

inline const char* pyroWaveRangeName(PyroWaveRange range)
{
    return range == PyroWaveRange::Full ? "full" : "limited";
}

// hdrMode is the host display HDR state from the control stream (setHdrMode).
// seq is the start-of-frame header when one was present in this frame.
inline PyroWavePresentColor pyroWavePresentColor(bool hdrMode, const PyroWaveSequenceHeader* seq)
{
    PyroWavePresentColor color;
    color.matrix = PyroWaveMatrix::Bt601;
    color.transfer = PyroWaveTransfer::Bt709;
    color.range = PyroWaveRange::Limited;
    color.chromaLeft = false;

    if (hdrMode) {
        color.matrix = PyroWaveMatrix::Bt2020;
        color.transfer = PyroWaveTransfer::Pq;
    }

    if (seq == nullptr) {
        return color;
    }

    // Any of these bits means the encoder filled the usability fields.
    // An all-zero header is what Vibeshine and upstream pyrowave write today.
    const bool explicitColor = seq->bt2020Primaries || seq->pqTransfer || seq->bt2020Matrix;
    if (explicitColor) {
        color.matrix = (seq->bt2020Matrix || seq->bt2020Primaries)
            ? PyroWaveMatrix::Bt2020
            : PyroWaveMatrix::Bt709;
        color.range = seq->limitedRange ? PyroWaveRange::Limited : PyroWaveRange::Full;
        if (seq->pqTransfer) {
            color.transfer = PyroWaveTransfer::Pq;
        }
        else if (hdrMode && color.matrix == PyroWaveMatrix::Bt2020) {
            // The header has one transfer bit (BT.709 or PQ). HDR mode plus
            // an explicit BT.2020 header that is not PQ is HLG.
            color.transfer = PyroWaveTransfer::Hlg;
        }
        else {
            color.transfer = PyroWaveTransfer::Bt709;
        }
    }
    else if (seq->limitedRange) {
        color.range = PyroWaveRange::Limited;
    }

    color.chromaLeft = seq->chromaSitingLeft;
    return color;
}

inline bool pyroWaveFindSequenceHeader(const std::vector<PyroWavePacketView>& packets,
                                       PyroWaveSequenceHeader& out)
{
    for (const PyroWavePacketView& packet : packets) {
        if (pyroWaveParseSequenceHeader(packet.data, packet.size, out)) {
            return true;
        }
    }
    return false;
}

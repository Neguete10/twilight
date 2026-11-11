#pragma once

#include <utility>
#include <vector>

// The ordered video-format list Session offers the host.
// Front of the vector is the highest priority. Automatic never inserts
// PyroWave. PyroWave is only the list produced for the PyroWave codec choice,
// and the HDR / 4:4:4 masks below still apply to it.
//
// Decoder probes are a callback so this stays free of SDL. Values match
// Session::DecoderAvailability: 0 none, 1 software, 2 hardware.
// On a Mac with HEVC hardware (M1 and later, including M3), Automatic
// deprioritizes AV1 and the first remaining codec is HEVC. AV1 stays first
// only when HEVC hardware is missing and the HDR exception below applies.
// There is no separate M3 check.

namespace CodecOffer {

constexpr int DecodeNone = 0;
constexpr int DecodeSoftware = 1;
constexpr int DecodeHardware = 2;

constexpr int Auto = 0;
constexpr int ForceH264 = 1;
constexpr int ForceHevc = 2;
constexpr int ForceHevcHdrDeprecated = 3;
constexpr int ForceAv1 = 4;
constexpr int ForcePyroWave = 5;

constexpr int H264 = 0x0001;
constexpr int H264High8_444 = 0x0004;
constexpr int H265 = 0x0100;
constexpr int H265Main10 = 0x0200;
constexpr int H265Rext8_444 = 0x0400;
constexpr int H265Rext10_444 = 0x0800;
constexpr int Av1Main8 = 0x1000;
constexpr int Av1Main10 = 0x2000;
constexpr int Av1High8_444 = 0x4000;
constexpr int Av1High10_444 = 0x8000;
constexpr int PyroWave = 0x0010;
constexpr int PyroWave444 = 0x0020;
constexpr int PyroWave10_420 = 0x0040;
constexpr int PyroWave10_444 = 0x0080;

constexpr int MaskH264 = 0x000F;
constexpr int MaskH265 = 0x0F00;
constexpr int MaskAv1 = 0xF000;
constexpr int MaskPyroWave = 0x00F0;
constexpr int Mask10Bit = 0xAAC0;
constexpr int MaskYuv444 = 0xCCA4;

struct Request {
    int codec = Auto;
    bool hdr = false;
    bool yuv444 = false;
    bool forceSoftware = false;
    // True on macOS, and on x86 Unix other than the embedded-Linux exception.
    // False on Windows and on non-x86 Unix, where missing HEVC hardware does
    // not by itself push AV1 down on an SDR stream.
    bool sdrDeprioritizesAv1 = false;
    bool darwin = false;
    bool oldGfe = false;
};

inline void removeByMask(std::vector<int>& formats, int mask)
{
    std::vector<int> kept;
    kept.reserve(formats.size());
    for (int format : formats) {
        if ((format & mask) == 0) {
            kept.push_back(format);
        }
    }
    formats.swap(kept);
}

inline void deprioritizeByMask(std::vector<int>& formats, int mask)
{
    std::vector<int> kept;
    std::vector<int> later;
    kept.reserve(formats.size());
    for (int format : formats) {
        if ((format & mask) != 0) {
            later.push_back(format);
        }
        else {
            kept.push_back(format);
        }
    }
    kept.insert(kept.end(), later.begin(), later.end());
    formats.swap(kept);
}

template <typename Probe>
std::vector<int> build(const Request& request, Probe probe)
{
    std::vector<int> formats;
    if (request.codec == ForcePyroWave) {
        formats.push_back(PyroWave10_444);
        formats.push_back(PyroWave10_420);
        formats.push_back(PyroWave444);
        formats.push_back(PyroWave);
    }
    else {
        formats.push_back(Av1High10_444);
        formats.push_back(Av1Main10);
        formats.push_back(H265Rext10_444);
        formats.push_back(H265Main10);
        formats.push_back(Av1High8_444);
        formats.push_back(Av1Main8);
        formats.push_back(H265Rext8_444);
        formats.push_back(H265);
        formats.push_back(H264High8_444);
        formats.push_back(H264);

        if (request.codec == Auto) {
            const int hevcProbe = request.yuv444
                    ? (request.hdr ? H265Rext10_444 : H265Rext8_444)
                    : (request.hdr ? H265Main10 : H265);
            int hevc = probe(hevcProbe);
            if (hevc == DecodeNone && request.hdr) {
                removeByMask(formats, MaskH265 & Mask10Bit);
                const int av1Ten = probe(request.yuv444 ? Av1High10_444 : Av1Main10);
                if (av1Ten == DecodeNone) {
                    removeByMask(formats, MaskAv1 & Mask10Bit);
                    hevc = probe(request.yuv444 ? H265Rext8_444 : H265);
                }
            }

            if (hevc != DecodeHardware) {
                if (!request.forceSoftware || !request.hdr) {
                    deprioritizeByMask(formats, MaskH265);
                }
            }

            if (hevc == DecodeHardware || (request.sdrDeprioritizesAv1 && !request.hdr)) {
                deprioritizeByMask(formats, MaskAv1);
            }
            else if (!request.hdr &&
                     probe(request.yuv444 ? Av1High8_444 : Av1Main8) != DecodeHardware) {
                deprioritizeByMask(formats, MaskAv1);
            }

            if (request.darwin && request.oldGfe) {
                removeByMask(formats, MaskH265);
            }
        }
        else if (request.codec == ForceH264) {
            removeByMask(formats, ~MaskH264);
        }
        else if (request.codec == ForceHevc || request.codec == ForceHevcHdrDeprecated) {
            removeByMask(formats, ~MaskH265);
        }
        else if (request.codec == ForceAv1) {
            removeByMask(formats, ~(MaskAv1 | MaskH265));
        }
    }

    if (!request.yuv444) {
        removeByMask(formats, MaskYuv444);
    }
    else {
        deprioritizeByMask(formats, ~MaskYuv444);
    }

    if (!request.hdr) {
        removeByMask(formats, Mask10Bit);
    }
    else {
        deprioritizeByMask(formats, ~Mask10Bit);
    }

    return formats;
}

inline bool containsMask(const std::vector<int>& formats, int mask)
{
    for (int format : formats) {
        if ((format & mask) != 0) {
            return true;
        }
    }
    return false;
}

} // namespace CodecOffer

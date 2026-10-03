#!/usr/bin/env python3
"""Apply the PyroWave capability-bit delta onto moonlight-common-c.

The spatial-mixer pin (583754fc) has the macOS clock and high-res stat
changes and does not know PyroWave. andygrundman/moonlight-common-c
2c263da ("PyroWave format support") is the same delta on a different
base, so retargeting the submodule would drop those macOS fixes.

qmake runs this before compiling. It is idempotent: a tree that already
has VIDEO_FORMAT_PYROWAVE is left alone.

It also keeps "Received first video packet after %d ms" and adds a second
line so that wait is startup context, not the steady-state comparison.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "moonlight-common-c" / "moonlight-common-c" / "src"


def ensure(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        sys.stderr.write(f"{path}: expected text not found and {marker!r} is absent\n")
        sys.exit(1)
    path.write_text(text.replace(old, new, 1))
    print(f"patched {path.name}")


def main() -> None:
    if not SRC.is_dir():
        sys.stderr.write(f"moonlight-common-c sources not checked out: {SRC}\n")
        sys.exit(1)

    ensure(
        SRC / "Limelight.h",
        """#define VIDEO_FORMAT_AV1_HIGH10_444  0x8000 // AV1 High 4:4:4 10-bit profile

// Masks for clients to use to match video codecs without profile-specific details.
#define VIDEO_FORMAT_MASK_H264   0x000F
#define VIDEO_FORMAT_MASK_H265   0x0F00
#define VIDEO_FORMAT_MASK_AV1    0xF000
#define VIDEO_FORMAT_MASK_10BIT  0xAA00
#define VIDEO_FORMAT_MASK_YUV444 0xCC04
""",
        """#define VIDEO_FORMAT_AV1_HIGH10_444  0x8000 // AV1 High 4:4:4 10-bit profile
#define VIDEO_FORMAT_PYROWAVE        0x0010 // PyroWave wavelet intra-only 4:2:0 8-bit (Sunshine/Moonlight extension)
#define VIDEO_FORMAT_PYROWAVE_444    0x0020 // PyroWave wavelet intra-only 4:4:4 8-bit (Sunshine/Moonlight extension)
#define VIDEO_FORMAT_PYROWAVE10_420  0x0040 // PyroWave wavelet intra-only 4:2:0 10-bit (Sunshine/Moonlight extension)
#define VIDEO_FORMAT_PYROWAVE10_444  0x0080 // PyroWave wavelet intra-only 4:4:4 10-bit (Sunshine/Moonlight extension)

// Masks for clients to use to match video codecs without profile-specific details.
#define VIDEO_FORMAT_MASK_H264     0x000F
#define VIDEO_FORMAT_MASK_H265     0x0F00
#define VIDEO_FORMAT_MASK_AV1      0xF000
#define VIDEO_FORMAT_MASK_PYROWAVE 0x00F0
#define VIDEO_FORMAT_MASK_10BIT    0xAAC0 // includes PyroWave 10-bit profiles (0x00C0)
#define VIDEO_FORMAT_MASK_YUV444   0xCCA4 // includes PyroWave 4:4:4 profiles (0x00A0)
""",
        "VIDEO_FORMAT_PYROWAVE",
    )
    ensure(
        SRC / "Limelight.h",
        """#define SCM_AV1_HIGH10_444  0x00400000 // Sunshine extension

// SCM masks to identify various codec capabilities
#define SCM_MASK_H264   (SCM_H264 | SCM_H264_HIGH8_444)
#define SCM_MASK_HEVC   (SCM_HEVC | SCM_HEVC_MAIN10 | SCM_HEVC_REXT8_444 | SCM_HEVC_REXT10_444)
#define SCM_MASK_AV1    (SCM_AV1_MAIN8 | SCM_AV1_MAIN10 | SCM_AV1_HIGH8_444 | SCM_AV1_HIGH10_444)
#define SCM_MASK_10BIT  (SCM_HEVC_MAIN10 | SCM_HEVC_REXT10_444 | SCM_AV1_MAIN10 | SCM_AV1_HIGH10_444)
#define SCM_MASK_YUV444 (SCM_H264_HIGH8_444 | SCM_HEVC_REXT8_444 | SCM_HEVC_REXT10_444 | SCM_AV1_HIGH8_444 | SCM_AV1_HIGH10_444)
""",
        """#define SCM_AV1_HIGH10_444  0x00400000 // Sunshine extension
#define SCM_PYROWAVE        0x00800000 // PyroWave 4:2:0 8-bit (Sunshine/Moonlight extension)
#define SCM_PYROWAVE_444    0x01000000 // PyroWave 4:4:4 8-bit (Sunshine/Moonlight extension)
#define SCM_PYROWAVE10_420  0x02000000 // PyroWave 4:2:0 10-bit (Sunshine/Moonlight extension)
#define SCM_PYROWAVE10_444  0x04000000 // PyroWave 4:4:4 10-bit (Sunshine/Moonlight extension)

// SCM masks to identify various codec capabilities
#define SCM_MASK_H264   (SCM_H264 | SCM_H264_HIGH8_444)
#define SCM_MASK_HEVC   (SCM_HEVC | SCM_HEVC_MAIN10 | SCM_HEVC_REXT8_444 | SCM_HEVC_REXT10_444)
#define SCM_MASK_AV1    (SCM_AV1_MAIN8 | SCM_AV1_MAIN10 | SCM_AV1_HIGH8_444 | SCM_AV1_HIGH10_444)
#define SCM_MASK_PYROWAVE (SCM_PYROWAVE | SCM_PYROWAVE_444 | SCM_PYROWAVE10_420 | SCM_PYROWAVE10_444)
#define SCM_MASK_10BIT  (SCM_HEVC_MAIN10 | SCM_HEVC_REXT10_444 | SCM_AV1_MAIN10 | SCM_AV1_HIGH10_444 | SCM_PYROWAVE10_420 | SCM_PYROWAVE10_444)
#define SCM_MASK_YUV444 (SCM_H264_HIGH8_444 | SCM_HEVC_REXT8_444 | SCM_HEVC_REXT10_444 | SCM_AV1_HIGH8_444 | SCM_AV1_HIGH10_444 | SCM_PYROWAVE_444 | SCM_PYROWAVE10_444)
""",
        "SCM_PYROWAVE",
    )
    ensure(
        SRC / "RtspConnection.c",
        """        if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) && strstr(response.payload, "AV1/90000")) {""",
        """        if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_PYROWAVE) && (serverInfo->serverCodecModeSupport & SCM_PYROWAVE)) {
            // PyroWave has no codec-specific SDP media line. Select it when both
            // sides advertise it, then fall through to AV1/HEVC/H.264 otherwise.
            // Profile order matches andygrundman/moonlight-common-c 2c263da.
            if ((serverInfo->serverCodecModeSupport & SCM_PYROWAVE10_444) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE10_444)) {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE10_444;
            }
            else if ((serverInfo->serverCodecModeSupport & SCM_PYROWAVE10_420) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE10_420)) {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE10_420;
            }
            else if ((serverInfo->serverCodecModeSupport & SCM_PYROWAVE_444) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE_444)) {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE_444;
            }
            else {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE;
            }
        }
        else if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) && strstr(response.payload, "AV1/90000")) {""",
        "VIDEO_FORMAT_MASK_PYROWAVE",
    )
    # The block above is what an already-patched tree contains. This second
    # pass rewrites it. A fresh tree gets the 10-bit-first text, then this
    # upgrade. A tree that already says "Prefer 8-bit PyroWave" is left alone.
    # Do not fold this order into the first ensure: that marker would then
    # be present before this old string exists, and a missing old string exits.
    ensure(
        SRC / "RtspConnection.c",
        """        if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_PYROWAVE) && (serverInfo->serverCodecModeSupport & SCM_PYROWAVE)) {
            // PyroWave has no codec-specific SDP media line. Select it when both
            // sides advertise it, then fall through to AV1/HEVC/H.264 otherwise.
            // Profile order matches andygrundman/moonlight-common-c 2c263da.
            if ((serverInfo->serverCodecModeSupport & SCM_PYROWAVE10_444) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE10_444)) {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE10_444;
            }
            else if ((serverInfo->serverCodecModeSupport & SCM_PYROWAVE10_420) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE10_420)) {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE10_420;
            }
            else if ((serverInfo->serverCodecModeSupport & SCM_PYROWAVE_444) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE_444)) {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE_444;
            }
            else {
                NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE;
            }
        }
        else if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) && strstr(response.payload, "AV1/90000")) {""",
        """        // Prefer 8-bit PyroWave. VIDEO_FORMAT_MASK_PYROWAVE is the client's one
        // profile bit; SCM_MASK_PYROWAVE is every host profile, including a
        // 10-bit-only host. HDR puts a 10-bit bit in supportedVideoFormats.
        // No matching profile falls through to AV1/HEVC/H.264.
        if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_PYROWAVE) && (serverInfo->serverCodecModeSupport & SCM_MASK_PYROWAVE) &&
            (serverInfo->serverCodecModeSupport & SCM_PYROWAVE_444) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE_444)) {
            NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE_444;
        }
        else if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_PYROWAVE) && (serverInfo->serverCodecModeSupport & SCM_MASK_PYROWAVE) &&
                 (serverInfo->serverCodecModeSupport & SCM_PYROWAVE) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE)) {
            NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE;
        }
        else if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_PYROWAVE) && (serverInfo->serverCodecModeSupport & SCM_MASK_PYROWAVE) &&
                 (serverInfo->serverCodecModeSupport & SCM_PYROWAVE10_444) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE10_444)) {
            NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE10_444;
        }
        else if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_PYROWAVE) && (serverInfo->serverCodecModeSupport & SCM_MASK_PYROWAVE) &&
                 (serverInfo->serverCodecModeSupport & SCM_PYROWAVE10_420) && (StreamConfig.supportedVideoFormats & VIDEO_FORMAT_PYROWAVE10_420)) {
            NegotiatedVideoFormat = VIDEO_FORMAT_PYROWAVE10_420;
        }
        else if ((StreamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) && strstr(response.payload, "AV1/90000")) {""",
        "Prefer 8-bit PyroWave",
    )
    ensure(
        SRC / "SdpGenerator.c",
        """        if (NegotiatedVideoFormat & VIDEO_FORMAT_MASK_AV1) {
            err |= addAttributeString(&optionHead, "x-nv-vqos[0].bitStreamFormat", "2");
        }""",
        """        if (NegotiatedVideoFormat & VIDEO_FORMAT_MASK_PYROWAVE) {
            // 0 = H.264, 1 = HEVC, 2 = AV1, 3 = PyroWave (Vibeshine BITSTREAM_FORMAT).
            err |= addAttributeString(&optionHead, "x-nv-clientSupportHevc", "0");
            err |= addAttributeString(&optionHead, "x-nv-vqos[0].bitStreamFormat", "3");
        }
        else if (NegotiatedVideoFormat & VIDEO_FORMAT_MASK_AV1) {
            err |= addAttributeString(&optionHead, "x-nv-vqos[0].bitStreamFormat", "2");
        }""",
        "bitStreamFormat\", \"3\"",
    )
    ensure(
        SRC / "VideoDepacketizer.c",
        """        else if (NegotiatedVideoFormat & VIDEO_FORMAT_MASK_AV1) {
            // We don't parse the AV1 bitstream
            LC_ASSERT_VT(decodeUnit->bufferList->bufferType == BUFFER_TYPE_PICDATA);
        }""",
        """        else if (NegotiatedVideoFormat & (VIDEO_FORMAT_MASK_AV1 | VIDEO_FORMAT_MASK_PYROWAVE)) {
            // AV1 and PyroWave are not Annex-B. The picture payload is one buffer.
            LC_ASSERT_VT(decodeUnit->bufferList->bufferType == BUFFER_TYPE_PICDATA);
        }""",
        "VIDEO_FORMAT_MASK_PYROWAVE",
    )
    # Keep the original sentence. The second line tells a reader not to treat
    # that wait as the Vulkan-vs-Metal result. Steady-state numbers are the
    # Global video stats block and the PyroWave metric lines.
    ensure(
        SRC / "VideoStream.c",
        """            Limelog("Received first video packet after %d ms\\n", waitingForVideoMs);

            firstDataTimeMs = PltGetMillis();
""",
        """            Limelog("Received first video packet after %d ms\\n", waitingForVideoMs);
            // Startup context only. The wait until the first UDP datagram is not
            // a frame time. Steady-state numbers are "Global video stats" and
            // "PyroWave metric:" lines written on quit.
            Limelog("First-packet wait is startup context only. Compare steady-state frame times (Global video stats), not this number.\\n");

            firstDataTimeMs = PltGetMillis();
""",
        "startup context only",
    )


if __name__ == "__main__":
    main()

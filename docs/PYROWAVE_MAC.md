# PyroWave on Twilight (macOS)

PyroWave is Hans-Kristian Arntzen’s intra-only GPU wavelet codec
([Themaister/pyrowave](https://github.com/Themaister/pyrowave), bitstream spec
[`bitstream/bitstream.md`](https://github.com/Themaister/pyrowave/blob/master/bitstream/bitstream.md)).
It is a client codec, not a host-only switch. Twilight advertises it only when
this build’s decoder initializes, and otherwise keeps H.264, HEVC, and AV1.

This branch starts from `andyg.coreaudio-spatial-mixer`. The MoltenVK decoder
is the one already written on `andyg.pyrowave-macos` (`6fd162d2`, “PyroWave
integration for macOS using MoltenVK”), ported forward without removing
`HAVE_COREAUDIO` or the spatial mixer. It is **off** unless qmake is run with
`CONFIG+=pyrowave`, so the existing Mac build does not need the submodule.

## What works / what does not

**Works in this change**

- Research notes below, tied to files and symbols that were read.
- `scripts/apply_pyrowave_protocol.py` adds the capability bits to the current
  `moonlight-common-c` pin (`583754fc`) without retargeting that submodule.
- Session negotiation prefers PyroWave when `HAVE_PYROWAVE` is set and the
  decoder probe succeeds, and drops it when the host lacks `SCM_PYROWAVE` or
  the decoder fails to initialize. H.264 / HEVC / AV1 stay in the list.
- Offline parser test for the length-prefixed frame and the 8-byte headers
  (`tests/pyrowave_packets_test.cpp`). It passed on this Linux VM. No GPU
  timing was measured here.

**Does not work yet**

- Live decode of a Vibeshine stream. This VM has no Mac GPU, no MoltenVK, and
  no host.
- The default Mac link (`-lssl.3 -lcrypto.3 -lavcodec.61 …`, no `-lplacebo`)
  is unchanged. `CONFIG+=pyrowave` adds `-lpyrowave-shared -lplacebo` and
  expects SDL to load MoltenVK. The prebuilts on this branch may not contain
  libplacebo or an SDL built with `SDL_vulkan.h`. `andyg.pyrowave-macos` links
  `-lplacebo` and a newer FFmpeg (`avcodec.62`).
- Record framing (see below). This client does not send the RTSP attributes
  that select it, so a current Vibeshine host should stay on length-prefixed
  frames. That was not tested live.
- Partial RTP delivery. Stock `moonlight-common-c` drops a frame it cannot
  fully reassemble. `andyg.xbox-pyrowave` commit `574aab7` delivers a prefix
  for PyroWave; that patch is not applied here.
- A native Metal decoder. See the Metal section.

## Bitstream

Spec: `bitstream/bitstream.md` in Themaister/pyrowave. Draft, little-endian,
tightly packed. Intra-only 5-level CDF 9/7 DWT. A lost 32×32 block decodes as
zeros. There is no 8-bit vs 10-bit flag; the sample is float and the client
quantizes it. Chroma, primaries, transfer, and range live in the start-of-frame
header.

`BitstreamHeader` (8 bytes, not extended):

| Field | Width | Role |
| --- | --- | --- |
| `ballot` | 16 | which 8×8 groups inside the 32×32 block are present |
| `payload_words` | 12 | u32 words in this block, including the header (`* 4` = bytes) |
| `sequence` | 3 | frame counter, modulo 8 |
| `extended` | 1 | 0 for coefficient blocks |
| `quant_code` | 8 | 32×32 dequant |
| `block_index` | 24 | linear index, Y then Cb then Cr, coarse level first |

`BitstreamSequenceHeader` reinterprets those 8 bytes when `extended` is 1 and
`code` is `BITSTREAM_EXTENDED_CODE_START_OF_FRAME` (0). Fields used by a
decoder: `width_minus_1`, `height_minus_1` (14 bits each), `sequence` (3),
`total_blocks` (24), `chroma_resolution` (0 = 4:2:0, 1 = 4:4:4), plus
primaries / transfer / matrix / range / siting. `total_blocks` is how many
non-zero blocks the frame contains; `pyrowave_decoder_decode_is_ready()`
returns true once that many packets have been pushed.

`pyroWaveParseBitstreamHeader()` and `pyroWaveParseSequenceHeader()` in
`app/streaming/video/pyrowave_packets.h` implement that layout. They do not
run the inverse DWT.

The C API the MoltenVK decoder calls is `pyrowave.h` at submodule commit
`263ef100` (“macOS build support”): `pyrowave_decoder_create`,
`pyrowave_decoder_push_packet`, `pyrowave_decoder_decode_is_ready`,
`pyrowave_decoder_decode_gpu_buffer`. Each pushed packet is one bitstream
block, not a whole frame.

## Host framing (Vibeshine)

Read from [Nonary/vibeshine](https://github.com/Nonary/vibeshine) `master` at
the time of this port.

`src/pyrowave_protocol.h`

- `SCM_PYROWAVE` `0x00800000`, `SCM_PYROWAVE_444` `0x01000000`,
  `SCM_PYROWAVE_HDR10` `0x02000000`, `SCM_PYROWAVE_HDR10_444` `0x04000000`.
  The client header names the 10-bit bits `SCM_PYROWAVE10_420` and
  `SCM_PYROWAVE10_444`. Same values.
- `BITSTREAM_FORMAT` `3` (`x-nv-vqos[0].bitStreamFormat`; 0/1/2 are H.264/HEVC/AV1).
- `BITSTREAM_ID` `"186f0393"` (first digits of the vendored pyrowave commit).
  The bitstream has no version field.
- `DESCRIBE_RTPMAP` `"a=rtpmap:99 PYROWAVE/90000"` is informational. The
  client selector does not look for it.
- `ANNOUNCE_ADAPTIVE_FEC` (`x-ss-video[0].pyrowaveAdaptiveFec`) and
  `FEATURE_RECORD_FRAMING` (`0x1` in `x-ss-video[0].pyrowaveFeatures`) opt into
  record framing.

`src/nvhttp.cpp` sets `ServerCodecModeSupport |= SCM_MASK_PYROWAVE` when
`advertised_video.pyrowave_mode >= 2` (probe passed and the option is on).

`src/pyrowave_policy.cpp` `select_framing()`:

- adaptive-FEC attribute or `FEATURE_RECORD_FRAMING` → record framing
  (`write_record_frame`, padding records, shard aligned)
- otherwise → length-prefixed framing

`write_length_prefixed_frame()` appends
`[u32 LE count] { [u32 LE size] [packet bytes] }`.
`app/streaming/video/pyrowave.cpp` `submitDecodeUnit()` reassembles the
decode-unit chain and passes each packet to `pyrowave_decoder_push_packet()`.
That matches the azafrob/dimizago clients the host comment names. Twilight
does not send the record-framing attributes, so this is the layout Vibeshine
should emit.

`src/stream.cpp` `video_short_frame_header_t` is the 8-byte Moonlight header
in front of every frame (`headerType`, latency, `frameType`,
`lastPayloadLen`, `pyrowave_critical_packets`). `moonlight-common-c` strips
that header before the decoder sees the buffer. The length-prefixed bytes are
the picture payload.

`src/rtsp.cpp` reads `x-nv-vqos[0].bitStreamFormat` into
`config.monitor.videoFormat` and treats `BITSTREAM_FORMAT` as a PyroWave
session (IDR and reference-frame invalidation are no-ops, because every frame
is intra).

## Client negotiation

The selector lives in `moonlight-common-c`, not in Qt. `andyg.pyrowave-macos`
points the submodule at `899aa93` / commit `2c263da` (“PyroWave format
support”). This branch stays on `583754fc` because that pin has
`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` in `Platform.c` and the high-res
stat fields the spatial-mixer work uses. `2c263da` is not an ancestor of
`583754fc`.

`scripts/apply_pyrowave_protocol.py` (run from `app/app.pro` and
`moonlight-common-c/moonlight-common-c.pro`) applies the same delta:

- `Limelight.h`: `VIDEO_FORMAT_PYROWAVE` `0x0010`, `VIDEO_FORMAT_PYROWAVE_444`
  `0x0020`, `VIDEO_FORMAT_PYROWAVE10_420` `0x0040`, `VIDEO_FORMAT_PYROWAVE10_444`
  `0x0080`, `VIDEO_FORMAT_MASK_PYROWAVE` `0x00F0`. These sit in the gap between
  `VIDEO_FORMAT_MASK_H264` (`0x000F`) and `VIDEO_FORMAT_MASK_H265` (`0x0F00`).
  `VIDEO_FORMAT_MASK_10BIT` becomes `0xAAC0` and `VIDEO_FORMAT_MASK_YUV444`
  becomes `0xCCA4`, so the existing HDR and 4:4:4 filters include PyroWave.
- `SCM_PYROWAVE` `0x00800000` through `SCM_PYROWAVE10_444` `0x04000000`, and
  `SCM_MASK_PYROWAVE`.
- `RtspConnection.c` `performRtspHandshake()`: if the client mask contains
  `VIDEO_FORMAT_MASK_PYROWAVE` and `/serverinfo` contains `SCM_PYROWAVE`, pick
  the best matching profile (10-bit 4:4:4, then 10-bit 4:2:0, then 8-bit
  4:4:4, else 8-bit 4:2:0). Otherwise the existing AV1, then HEVC, then H.264
  tests run.
- `SdpGenerator.c`: PyroWave sets `x-nv-vqos[0].bitStreamFormat` to `"3"` and
  `x-nv-clientSupportHevc` to `"0"`.
- `VideoDepacketizer.c`: PyroWave IDR units are a single `BUFFER_TYPE_PICDATA`
  buffer, same as AV1.

`SupportedVideoFormatList::maskByServerCodecModes()` in
`app/streaming/session.h` maps those SCM bits. Without that, a debug build
hits `SDL_assert(serverCodecModes == 0)` when a Vibeshine host ORs
`SCM_MASK_PYROWAVE` into `ServerCodecModeSupport`, even if Twilight is not
decoding PyroWave.

Qt side (`app/streaming/session.cpp`), only the advertising and fallback:

- With `HAVE_PYROWAVE`, the four profiles are appended **before** AV1/HEVC/H.264.
  `m_StreamConfig.supportedVideoFormats` is still only `front()` after
  filtering, which is the existing Moonlight behavior.
- Automatic mode probes `PyroWaveVideoDecoder`. `VDS_FORCE_SOFTWARE` or a
  failed probe removes `VIDEO_FORMAT_MASK_PYROWAVE`.
- `validateLaunch()` removes it when `serverCodecModeSupport` has no
  `SCM_PYROWAVE`. The next entry (AV1, HEVC, or H.264, already filtered by
  the HDR / 4:4:4 / GFE rules) becomes `front()`.
- If the real initialize fails later, the launch loop drops PyroWave and
  retries. A failure of H.264/HEVC/AV1 still fails the launch.
- Settings and `--video-codec PyroWave` (`VCC_FORCE_PYROWAVE`) prefer
  PyroWave but do **not** clear the other codecs. `andyg.pyrowave-macos`
  used `removeByMask(~VIDEO_FORMAT_MASK_PYROWAVE)`, which left no fallback.
  Forcing H.264, HEVC, or AV1 still removes PyroWave, same as before.
- A build without `HAVE_PYROWAVE` never adds the profiles. Choosing PyroWave
  in that build logs a warning and continues with H.264/HEVC/AV1.

`chooseDecoder()` returns false on a PyroWave format instead of falling
through to FFmpeg. `FFmpegVideoDecoder::isDecoderMatchForParams()` asserts
the format is H.264, HEVC, or AV1.

## Decoder path (MoltenVK, not Metal)

`app/streaming/video/pyrowave.cpp` / `pyrowave.h` are the `andyg.pyrowave-macos`
decoder.

- **Linux:** PyroWave’s own Vulkan device, exportable dmabuf planes, import
  into libplacebo.
- **macOS:** `VK_NO_PROTOTYPES`. One `VkDevice` shared by PyroWave and
  libplacebo, because MoltenVK has no dmabuf. Plane images are libplacebo
  textures. A timeline semaphore (`pl_vulkan_sem_create` /
  `pyrowave_sync_object_create`) orders decode and present. SDL’s
  `vkGetInstanceProcAddr` loads MoltenVK; the binary is not linked with
  `-lvulkan`.

`PyroWaveVideoDecoder::isHardwareAccelerated()` is true. Colorspace reported
to the host is still `COLORSPACE_REC_601` / `COLOR_RANGE_LIMITED` from that
file; the wavelet header’s BT.709 / BT.2020 / PQ flags are not yet what
Moonlight sends in `colorSpace`. Treat that as unfinished if HDR PyroWave
looks wrong.

`VIDEO_STATS::totalRenderTimeUs` was added in `decoder.h` because the overlay
in the ported decoder records present time and this branch’s struct did not
have the field.

## Metal vs MoltenVK

MoltenVK is the path that already existed and is what `CONFIG+=pyrowave`
compiles. It is a poor App Store default: the app must ship or locate
MoltenVK, SDL must be built with Vulkan, and the decoder still speaks VkImage.

Two Metal codebases exist and are **not** wired in:

1. `metal/` on [andygrundman/pyrowave](https://github.com/andygrundman/pyrowave)
   `master` (`metal/README.md`, `metal/pyrowave_metal.h`). Native Metal, no
   Granite. `pyrowave_decoder_push_packet` /
   `pyrowave_decoder_decode_gpu_buffer` mirror the Vulkan C API but take
   `MTLDevice` / `MTLTexture`. The README says it is an unsupported,
   AI-assisted port and that it was faster than Vulkan-on-KosmicKrisp on
   Apple hardware. Commit `263ef100` (the pin this client builds against)
   is **not** an ancestor of that master. Master does contain bitstream
   commit `186f0393`, which is Vibeshine’s `BITSTREAM_ID`.
2. [EthanLipnik/PyrowaveKit](https://github.com/EthanLipnik/PyrowaveKit), a
   separate Swift/Metal port (packet decode, 4:2:0 and 4:4:4, rate control).
   Not vendored.

Next decoder step on a Mac: build `libpyrowave` from a commit at or after
`186f0393`, confirm `pyrowave.h` still matches `pyrowave.cpp`, then either
keep MoltenVK for a LAN proof or retarget `initialize()` at
`pyrowave_metal.h` and a `CVPixelBuffer` / `MTLTexture` present path. The
length-prefix parser can stay.

## Build

Default (CoreAudio spatial, no PyroWave decoder):

```bash
git submodule update --init moonlight-common-c/moonlight-common-c
# qmake runs scripts/apply_pyrowave_protocol.py
qmake
make
```

The protocol patch is required even when the decoder is off, so
`maskByServerCodecModes()` understands a Vibeshine host. It edits the
submodule working tree and is idempotent. Do not commit that dirty
submodule; the script is the source of the change.

PyroWave decoder (macOS, MoltenVK):

```bash
git submodule update --init pyrowave
cd pyrowave && bash checkout_granite.sh && cd ..
cmake -S pyrowave -B pyrowave/build -DPYROWAVE_SHARED=ON
cmake --build pyrowave/build --target pyrowave-shared
# SDL with Vulkan/MoltenVK, libplacebo as -lplacebo, then:
qmake CONFIG+=pyrowave
make
```

Linux uses the same `CONFIG+=pyrowave` switch and links `-lvulkan` plus
`libdrm` and `libplacebo` via pkg-config. Windows is rejected by qmake.

Offline parser test (no Qt, no GPU):

```bash
g++ -std=c++17 -Wall -Wextra -Iapp/streaming/video \
    tests/pyrowave_packets_test.cpp -o /tmp/pyrowave_packets_test
/tmp/pyrowave_packets_test
```

## Blockers for a live Mac proof

1. No Mac GPU in this environment, so MoltenVK and Metal were not linked or
   timed.
2. Need a Vibeshine (or Vibepollo) host with PyroWave enabled, on a gigabit
   LAN. Bitrate is hundreds of Mbit/s. Nonary’s Windows/Linux Moonlight builds
   are the clients that already decode this; Twilight is the Mac gap.
3. Move the `pyrowave` pin from `263ef100` to a commit whose bitstream matches
   `BITSTREAM_ID` `186f0393` before expecting bit-exact interop, and recheck
   the C API.
4. This branch’s Mac prebuilts may lack libplacebo and a Vulkan-enabled SDL.
   `andyg.pyrowave-macos` is the reference for those library versions.
5. App Store: PyroWave itself is MIT. The MoltenVK build also compiles
   Granite; check that license before shipping. Prefer `metal/pyrowave_metal.h`
   or PyrowaveKit over bundling MoltenVK. Sandbox and UDP buffer sizes are
   unchanged from a normal stream, but the receive rate is much higher.
6. Record framing and partial-frame delivery are still host/client follow-ups.
   Until they exist, do not advertise `x-ss-video[0].pyrowaveAdaptiveFec`.

## CoreAudio spatial

Not modified. Still present:

- `app/app.pro` `DEFINES += HAVE_COREAUDIO` and the `streaming/audio/renderers/coreaudio/` sources, including `au_spatial_renderer.mm`
- `app/streaming/audio/audio.cpp` `TRY_INIT_RENDERER(CoreAudioRenderer, …)` under `HAVE_COREAUDIO`
- `CoreAudioRenderer` / `AUSpatialMixerOutputType` in `coreaudio.h`

Checked with `git diff` on `app/streaming/audio` (empty) and by reading those
symbols after the PyroWave edits. The macOS framework list (`CoreAudio`,
`AudioToolbox`, `AudioUnit`, `Accelerate`, …) is untouched. The protocol
patch does not edit `Platform.c`, so `clock_gettime_nsec_np` stays.

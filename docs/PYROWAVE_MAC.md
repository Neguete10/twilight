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

`CONFIG+=pyrowave` on macOS now compiles two PyroWave decoders. Vulkan
(MoltenVK, `PyroWaveVideoDecoder`) stays linked to `libpyrowave-shared` from
submodule pin `263ef100`. Metal (`PyroWaveMetalVideoDecoder`) dlopens
`libpyrowave-metal` from the `pyrowave-metal` submodule (`89f7e47`) and does
not replace that pin. `qmake CONFIG+=pyrowave && make` builds that dylib and
copies it into the app. Settings
→ Advanced → PyroWave GPU backend is Automatic / Metal / Vulkan when both
are compiled. Automatic prefers Metal when that dylib and an Apple7 GPU are
present, and otherwise uses Vulkan. H.264, HEVC, and AV1 stay on
Metal/VideoToolbox. Video codec = PyroWave is unchanged.

## What works / what does not

**Works in this change**

- Research notes below, tied to files and symbols that were read.
- `scripts/apply_pyrowave_protocol.py` adds the capability bits to the current
  `moonlight-common-c` pin (`583754fc`) without retargeting that submodule.
- Session negotiation prefers PyroWave when `HAVE_PYROWAVE` is set and the
  decoder probe succeeds, and drops it when the host lacks `SCM_PYROWAVE` or
  the decoder fails to initialize. H.264 / HEVC / AV1 stay in the list.
- Offline parser test for the length-prefixed frame and the 8-byte headers
  (`tests/pyrowave_packets_test.cpp`), including the present-color decision
  (Rec.601 limited by default, HDR → Rec.2020 PQ limited, an all-zero header
  ignored, explicit start-of-frame bits, HLG only when HDR and an explicit
  BT.2020 header are not PQ). It passed on this Linux VM. No GPU timing was
  measured here.
- Backend selection test (`tests/pyrowave_backend_test.cpp`): Automatic
  prefers Metal, and an explicit Metal or Vulkan choice does not cross over
  when that library is absent. It passed on this Linux VM. The test also
  includes the Metal ABI snapshot so the 0.5.0 struct sizes are checked.
- A Metal decode/present client (`app/streaming/video/pyrowave_metal.mm`)
  that coexists with the MoltenVK decoder. It was not compiled here (no
  Apple SDK, no Metal).

**Does not work yet**

- Live decode of a Vibeshine / Vibepollo stream on either backend. This VM
  has no Mac GPU, no MoltenVK, and no host.
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
- A GPU run of the Metal decoder. The client is in the tree; the dylib and
  an Apple7 GPU are not. See the Metal section.

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
- `RtspConnection.c` `performRtspHandshake()`: if both sides have a matching
  PyroWave profile, pick it. Order is 8-bit 4:4:4, 8-bit 4:2:0, 10-bit 4:4:4,
  10-bit 4:2:0. The outer check is `VIDEO_FORMAT_MASK_PYROWAVE` and
  `SCM_MASK_PYROWAVE`, so a host that only advertises 10-bit still matches.
  The client sends a single profile bit (`supportedVideoFormats` is
  `front()`). HDR in Twilight moves a 10-bit profile to the front before
  that bit is sent; with HDR off the bit is 8-bit. If no profile matches,
  the existing AV1, then HEVC, then H.264 tests run. The old handshake
  required `SCM_PYROWAVE` (8-bit 4:2:0 only) and preferred 10-bit, which
  made format `0x40` the usual result and skipped a 10-bit-only host.
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

- With `HAVE_PYROWAVE` or `HAVE_PYROWAVE_METAL`, the four profiles are
  appended **before** AV1/HEVC/H.264, 8-bit before 10-bit (4:4:4 then 4:2:0).
  `m_StreamConfig.supportedVideoFormats` is still only `front()` after
  filtering, which is the existing Moonlight behavior. HDR
  (`deprioritizeByMask(~VIDEO_FORMAT_MASK_10BIT)`) still promotes 10-bit,
  because an 8-bit PQ frame from this host looks banded. HDR off removes
  10-bit, so the advertised bit stays 8-bit.
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
- A build without `HAVE_PYROWAVE` or `HAVE_PYROWAVE_METAL` never adds the
  profiles. Choosing PyroWave in that build logs a warning and continues
  with H.264/HEVC/AV1.

`chooseDecoder()` returns false on a PyroWave format instead of falling
through to FFmpeg. `FFmpegVideoDecoder::isDecoderMatchForParams()` asserts
the format is H.264, HEVC, or AV1.

## Decoder path (Vulkan / MoltenVK)

`app/streaming/video/pyrowave.cpp` / `pyrowave.h` are the `andyg.pyrowave-macos`
Vulkan decoder. Metal does not edit this file’s device, plane, or present
calls.

- **Linux:** PyroWave’s own Vulkan device, exportable dmabuf planes, import
  into libplacebo.
- **macOS:** `VK_NO_PROTOTYPES`. One `VkDevice` shared by PyroWave and
  libplacebo, because MoltenVK has no dmabuf. Plane images are libplacebo
  textures. A timeline semaphore (`pl_vulkan_sem_create` /
  `pyrowave_sync_object_create`) orders decode and present. SDL’s
  `vkGetInstanceProcAddr` loads MoltenVK; the binary is not linked with
  `-lvulkan`.

The stream window is `SDL_WINDOW_METAL` on Darwin for VideoToolbox and for
PyroWave Metal. When the probed backend is Vulkan, `Session::execInternal()`
clears that flag and sets `SDL_WINDOW_VULKAN` before `SDL_CreateWindow`.
`SDL_WINDOW_VULKAN` is an enumerator, not a preprocessor macro, so the check
is `SDL_VERSION_ATLEAST(2, 0, 6)` (the flag has existed since SDL 2.0.6).
`#ifdef SDL_WINDOW_VULKAN` is false and used to leave the stream window as
`SDL_WINDOW_METAL`, which cannot create a MoltenVK surface. If
`SDL_CreateWindow` fails, the retry keeps that present flag (Vulkan or
Metal). A flagless window is not used for PyroWave: present would fail and
the stream would recreate. The hidden probe window stays Metal: the Vulkan
probe is `testOnly` and uses `pyrowave_create_default_device()` with no
surface, and H.264/HEVC/AV1 still need a Metal view. Non-PyroWave codecs
never take the Vulkan flag.

`chooseDecoder()` runs inside `initialize()` and calls `Session::get()`.
`execInternal()` acquires `s_ActiveSessionSemaphore` and sets
`s_ActiveSession` before `initialize()`. On initialize failure the pointer
is cleared and the semaphore is released there. The deferred cleanup task
is not also started on that path (it releases the same semaphore).

`PyroWaveVideoDecoder::isHardwareAccelerated()` is true. Both decoders
report `COLORSPACE_REC_601` / `COLOR_RANGE_LIMITED`, the same advertisement
as VT Metal HEVC (`getDecoderColorspace()` in `vt_metal.mm`). The host’s
RGB→YUV uses that, then switches to Rec.2020 PQ when its display is HDR,
without changing the range. See Color below.

`VIDEO_STATS::totalRenderTimeUs` was added in `decoder.h` because the overlay
in the ported decoder records present time and this branch’s struct did not
have the field.

Resize and display changes do not recreate the decoder.
`notifyWindowChanged()` clears `WINDOW_STATE_CHANGE_SIZE` and
`WINDOW_STATE_CHANGE_DISPLAY` and returns true, same as VT Metal.
`renderFrameOnMainThread()` calls `pl_swapchain_resize()`. Recreating the
shared MoltenVK device on those events flashed the window. The swapchain
depth is 3 (`VK_PRESENT_MODE_FIFO_KHR`). A depth of 1 stalls windowed and
fullscreen presents on MoltenVK, for the same reason the Metal layer uses
`maximumDrawableCount = 3`. libplacebo 7.360’s `pl_vulkan_queue` is
`{index, count}`. The import sets `.index` to the queue family and
`.count` to 1. A third initializer (`{family, 1, 0}`) does not compile
against that header.

## Color

`app/streaming/video/pyrowave_color.h` is the decision both presents use.
`setHdrMode()` is the host display HDR flag from the control stream
(`LiGetCurrentHostDisplayHdrMode()`), not a guess from the format code.

| Situation | Matrix | Transfer | Range |
| --- | --- | --- | --- |
| SDR, or a header whose color bits are all zero | Rec.601 | BT.709 (desktop tagged sRGB) | limited |
| Host display HDR, header unset | Rec.2020 | PQ | limited |
| Header has primaries, PQ, or matrix set | those bits | PQ, or HLG if HDR and BT.2020 and the PQ bit is clear | limited if that bit is set, otherwise full |

An all-zero start-of-frame header is what current Vibeshine and upstream
pyrowave encoders write. The spec reads those zeros as BT.709 full. That is
not what the host encoded, so those bits are ignored. Chroma siting is
applied whenever a header is present (0 = center, which is also the
default).

The wavelet sample is a normalized float in `[0, 1]` written to `R8Unorm` or
`R16Unorm`. There is no 8-bit vs 10-bit flag in the bitstream. 8-bit limited
black is `16/255` and chroma zero is `128/255`, the same offsets as the VT
Metal HEVC matrices. 10-bit limited uses `64/1023` and `512/1023`, and the
limited matrix columns are scaled by `(1023/876)/(255/219)` for luma and
`(1023/896)/(255/224)` for chroma. Full-range 10-bit does not scale the
matrix; only the chroma midpoint moves to `512/1023`.

Vulkan (libplacebo) sets `pl_color_repr.bits.sample_depth` and `color_depth`
to 8 or 10 together. The values are already normalized UNORM, not 10-bit
codes in the low bits of an R16 texture (that scaling would blow the image
up). Depth selects the limited-range constants. PQ also fills HDR metadata
from `LiGetHdrMetadata()` and hints the swapchain. HLG uses
`PL_COLOR_TRC_HLG`. Chroma location is `pl_frame_set_chroma_location()`
(left or center).

Metal draws with the existing `vt_renderer.metal` `ps_draw_triplanar`
shader and the same 8-bit CSC numbers as `vt_metal.mm`. `bitnessScaleFactor`
is 1. PQ uses `kCGColorSpaceITUR_2100_PQ` and `MTLPixelFormatBGR10A2Unorm`.
HLG uses `kCGColorSpaceITUR_2100_HLG` and the same 10-bit format. Rec.2020
without PQ/HLG uses `kCGColorSpaceITUR_2020`. Rec.709 uses
`kCGColorSpaceITUR_709`. Rec.601 uses sRGB. The shader writes encoded RGB;
the layer colorspace tags it, same as VT, with no EOTF in the shader.
`wantsExtendedDynamicRangeContent` is on for PQ, HLG, and any 10-bit
format, matching VT Metal. The shared shader has no chroma-siting UV shift,
so left siting is Vulkan-only. Current encoders leave that bit clear
(center), which both backends use.

The bitstream has one transfer bit (BT.709 or PQ). It has no HLG bit. HLG
is inferred only for HDR mode plus an explicit BT.2020 header whose
transfer bit is clear. A log line (`PyroWave present:` / `PyroWave Metal
present:`) prints the matrix, transfer, and range when they change.

## Present stability

- Size and display changes do not recreate either decoder.
- Metal sets `drawableSize` from `SDL_Metal_GetDrawableSize` before
  `nextDrawable`. If that returns nil (common for one frame during
  fullscreen), `frameReady` is set again so the next event presents the
  frame instead of dropping it.
- Vulkan does not recreate MoltenVK on resize, and the swapchain holds
  three images.
- The stream window flag matches the backend: `SDL_WINDOW_METAL` for Metal
  present, `SDL_WINDOW_VULKAN` for Vulkan present. A failed create retries
  with that flag still set.
- `s_ActiveSession` is published before `initialize()`, so the decoder
  probe’s `Session::get()` is this session.

## Metal backend

Checked against [andygrundman/pyrowave](https://github.com/andygrundman/pyrowave)
commit `89f7e47d4abbf650c91fae766728af866c5e32a0` (2026-09-25, “Fix .def file”).
`metal/pyrowave_metal.h` there is API **0.5.0**. `metal/` does **not** exist
at submodule pin `263ef100` (GitHub returns 404 for that path). Master’s
Vulkan export list also moved (`pyrowave_create_default_device2` removed,
`pyrowave_create_device_by_compat2` added in `pyrowave-shared.def`). Bumping
the submodule to pick up Metal would change the Vulkan C API
`pyrowave.cpp` calls (`fragment_path`, timeline `pyrowave_decoder_decode_gpu_buffer`).
The two libraries stay separate.

They cannot be linked into one binary. Both export `pyrowave_decoder_create`,
`pyrowave_device_destroy`, `pyrowave_decoder_push_packet`, and
`pyrowave_decoder_decode_gpu_buffer`. The Metal `decode_gpu_buffer` takes an
`MTLCommandBuffer` and three `MTLTexture`s. The Vulkan one takes timeline
sync ops and `VkImage` views. `PyroWaveMetalVideoDecoder` loads
`libpyrowave-metal` with `dlopen(..., RTLD_NOW | RTLD_LOCAL)` and
`dlsym`. `RTLD_LOCAL` keeps those symbols off the Vulkan decoder, which is
still bound to `libpyrowave-shared` at link time.

The struct layouts Twilight passes are in
`app/streaming/video/pyrowave_metal_api.h`, copied from that 0.5.0 header
(MIT, Hans-Kristian Arntzen). `runtimeAvailable()` refuses any other major
or minor. Patch may differ. Search order for the dylib:

1. `PYROWAVE_METAL_LIBRARY`
2. `Contents/Frameworks/libpyrowave-metal.dylib` (and the `.0` soname) next
   to the app executable
3. `pyrowave-metal/build/libpyrowave-metal.dylib` relative to the working
   directory
4. `libpyrowave-metal.dylib` on the default loader path

`qmake CONFIG+=pyrowave && make` on macOS builds `libpyrowave-metal` from
the `pyrowave-metal` submodule and copies the dylib into
`Twilight.app/Contents/Frameworks`. It does not link it.

Decode matches the length-prefix path the Vulkan decoder already uses
(`pyroWaveUnpackLengthPrefixedFrame`, then `pyrowave_decoder_push_packet`).
`pyrowave_decoder_decode_gpu_buffer` writes three private `R8Unorm` or
`R16Unorm` planes (shader-read and shader-write). Present is a
`CAMetalLayer` draw through the existing `vt_renderer.metal`
`ps_draw_triplanar` shader, on the same `MTLCommandQueue` as decode so the
GPU sees the writes in commit order. The upstream header says the port
needs a 32-wide SIMD group and the Apple7 family. Intel and AMD Macs fail
`pyrowave_device_is_supported` and Automatic falls through to Vulkan.

[EthanLipnik/PyrowaveKit](https://github.com/EthanLipnik/PyrowaveKit) is a
Swift package with its own packet and pixel-buffer API. It is not wired in.
The C Metal library already matches the push/decode calls Twilight uses, and
a Swift runtime is a second integration. The Metal README calls that port
unsupported and AI-assisted; treat a live picture as unproven until it is
run on a Mac.

### Settings

Advanced → **PyroWave GPU backend**, shown only when the build has both
`HAVE_PYROWAVE` and `HAVE_PYROWAVE_METAL` (`SystemProperties.hasPyroWaveVulkan`
and `hasPyroWaveMetal`).

| Choice | Behavior |
| --- | --- |
| Automatic | Metal if the dylib loads and a device is supported, otherwise Vulkan. If Metal’s `initialize()` fails during the probe, Vulkan is tried once, before the stream window exists. |
| Metal | Metal only. No Vulkan fallback. |
| Vulkan | MoltenVK only. No Metal fallback. |

`stream --pyrowave-backend auto|metal|vulkan` sets the same preference.
Video codec = PyroWave is still `VCC_FORCE_PYROWAVE` and still leaves
H.264/HEVC/AV1 in the list. The backend setting does nothing for those
codecs.

Automatic’s fallback happens only in the probe (`testOnly`). The real
window is created afterwards to match the backend that succeeded, and the
live decoder does not switch libraries under that window.

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

PyroWave Vulkan decoder (macOS, MoltenVK). Leave the submodule at
`263ef100`:

```bash
git submodule update --init pyrowave
cd pyrowave && bash checkout_granite.sh && cd ..
scripts/build-pyrowave-shared.sh
# SDL with Vulkan/MoltenVK, libplacebo as -lplacebo, then:
qmake CONFIG+=pyrowave
make
```

On macOS that script passes `CMAKE_OSX_DEPLOYMENT_TARGET` from
`QMAKE_MACOSX_DEPLOYMENT_TARGET` in `globaldefs.pri` (macOS 11.0, the same
floor as `LSMinimumSystemVersion` in `app/Info.plist`). Do not configure
this tree with a bare `cmake` invocation: an unset deployment target
stamps the SDK version, which is why the 7.0.0 dylibs were built for
macOS 27.

That qmake line on macOS also compiles the Metal client and, on a makefile
build, `libpyrowave-metal` itself.

PyroWave Metal library (submodule `pyrowave-metal`, same GitHub repo as
`pyrowave`, pinned commit, not a second checkout of the Vulkan pin):

A fresh clone does not fill submodules until init. This checks out
[andygrundman/pyrowave](https://github.com/andygrundman/pyrowave) at
`89f7e47d4abbf650c91fae766728af866c5e32a0` (“Fix .def file”, API 0.5.0):

```bash
git submodule update --init pyrowave-metal
# Vulkan libpyrowave-shared is still scripts/build-pyrowave-shared.sh, then:
qmake CONFIG+=pyrowave
make
```

`make` runs `scripts/build-pyrowave-metal.sh`, which configures
`pyrowave-metal/metal` with the same macOS 11.0 deployment target and
builds `libpyrowave-metal`, then copies
`libpyrowave-metal*.dylib` into `Twilight.app/Contents/Frameworks`.
Do not commit that dylib. It is cmake output under `pyrowave-metal/build/`
and is not part of the pinned commit. The submodule is marked
`ignore = untracked` so that directory does not show up as a change to
the pin. Do not check `89f7e47` out over the `pyrowave` submodule.
Vulkan stays at `263ef100`.

`metal/CMakeLists.txt` at that commit builds `libpyrowave-metal` (API 0.5.0)
and links Metal and IOSurface. It does not need Granite or MoltenVK.
`git submodule update --init --recursive` from a fresh clone fetches this
checkout together with the other submodules. Optional:
`PYROWAVE_METAL_LIBRARY` still overrides the dlopen path.

Linux uses the same `CONFIG+=pyrowave` switch, compiles only the Vulkan
decoder, and links `-lvulkan` plus `libdrm` and `libplacebo` via pkg-config.
Windows is rejected by qmake. There is no Metal backend off macOS.

Offline tests (no Qt, no GPU):

```bash
g++ -std=c++17 -Wall -Wextra -Iapp/streaming/video \
    tests/pyrowave_packets_test.cpp -o /tmp/pyrowave_packets_test
/tmp/pyrowave_packets_test

g++ -std=c++17 -Wall -Wextra -Iapp/streaming/video \
    tests/pyrowave_backend_test.cpp -o /tmp/pyrowave_backend_test
/tmp/pyrowave_backend_test

g++ -std=c++11 -Wall -Wextra -Iapp/streaming/video \
    tests/pyrowave_stats_test.cpp -o /tmp/pyrowave_stats_test
/tmp/pyrowave_stats_test

python3 scripts/pyrowave_ab_summary.py --self-test
```

## Comparing Vulkan and Metal

The number `Received first video packet after X ms` stays in the log. It is
how long the client waited for the first UDP datagram. That is startup
context. A cold decoder, a paced host, or a late first packet moves it
without saying anything about steady-state frame time. The next line says
so. Do not use it as the Vulkan-vs-Metal result.

Quit the stream. Both PyroWave decoders then write the same block HEVC
already writes, `Global video stats`, plus `PyroWave metric:` lines:

- decode-submit, present, and decode-submit-to-present-return p50/p95/p99
  (0.1 ms histogram, CPU timestamps, not glass-to-glass, not GPU completion)
- network-dropped frames, stalled presents, frames replaced before present
- advertised color, the present color, the swapchain pixel format, and the
  plane format (`R8Unorm` or `R16Unorm`)
- backend, GPU name, and `cpu=not sampled` (this build has no process CPU
  counter; a missing number is not zero)
- the same lines every five seconds, labeled `session so far`, so a killed
  process still has a partial record

Probe and init log the backend that was actually selected, the advertised
Rec.601 limited range, and the plane format. Present logs the color and
pixel format again when they are known. Fallback, HDR, drawable size, and
color changes log `PyroWave reconfigure:`.

Matched runs use the same host, resolution, format, bitrate, and v-sync.
Quit both so the end-of-session lines are the last ones:

```bash
moonlight stream <host> <app> --video-codec PyroWave --pyrowave-backend vulkan
moonlight stream <host> <app> --video-codec PyroWave --pyrowave-backend metal
python3 scripts/pyrowave_ab_summary.py ~/path/Moonlight-vulkan.log ~/path/Moonlight-metal.log
```

The script prints a side-by-side table of the steady-state lines and puts
the first-packet waits under Context. It warns if resolution, format, or
v-sync differ. `python3 scripts/pyrowave_ab_summary.py --self-test` checks
that layout against `scripts/testdata/`.

## Blockers for a live Mac proof

1. This environment has no Mac GPU and no Apple SDK. The Metal `.mm` was
   not compiled. MoltenVK and libplacebo were not linked. The color decision
   and the packet parser were run here; a live picture was not. SDR should
   now negotiate 8-bit (format `0x10`, or `0x20` when 4:4:4 is on). HDR still
   negotiates 10-bit (`0x40` for 4:2:0) and presents it as Rec.2020 PQ
   limited. That was not compared to HEVC on a display.
2. Need a Vibeshine (or Vibepollo) host with PyroWave enabled, on a gigabit
   LAN. Bitrate is hundreds of Mbit/s. Nonary’s Windows/Linux Moonlight builds
   are the clients that already decode this; Twilight is the Mac gap.
3. The Vulkan pin stays at `263ef100` so the working MoltenVK calls are not
   rewritten. Vibeshine’s `BITSTREAM_ID` is `186f0393`, which is an ancestor
   of the Metal tree (`89f7e47`) and is **not** the Vulkan pin. If a live
   Vulkan decode disagrees with the host, that mismatch is still open. Do
   not “fix” it by moving the submodule onto `89f7e47` without re-porting
   `pyrowave.cpp` to that revision’s Vulkan header.
4. Metal refuses to load if `pyrowave_get_api_version` is not 0.5.x. A newer
   `pyrowave_metal.h` needs a matching edit to `pyrowave_metal_api.h`.
5. This branch’s Mac prebuilts may lack libplacebo and a Vulkan-enabled SDL.
   `andyg.pyrowave-macos` is the reference for those library versions.
   `SDL_WINDOW_VULKAN` has to be in that SDL. The stream window requests it
   only for the Vulkan backend.
6. App Store submission is out of scope. PyroWave itself is MIT. The MoltenVK
   build also compiles Granite; check that license before shipping. The
   Metal library is the MIT `metal/` port and does not need MoltenVK. Its
   README says upstream does not support it. Sandbox and UDP buffer sizes
   are unchanged from a normal stream, but the receive rate is much higher.
7. Record framing and partial-frame delivery are still host/client follow-ups.
   Until they exist, do not advertise `x-ss-video[0].pyrowaveAdaptiveFec`.
8. Intel and AMD Macs cannot run the Metal decoder (`pyrowave_device_is_supported`
   requires Apple7). Use Vulkan there.
9. Known picture limits, even after the color change: the bitstream has no
   HLG bit and no 8-vs-10 flag; HLG is inferred, not signaled. Metal present
   uses the shared HEVC shader, which does not shift UV for left chroma
   siting (center is what current encoders write). Record framing and
   partial RTP delivery are still absent. Do not treat a format code alone
   as the colorspace.

## CoreAudio spatial

Not modified. Still present:

- `app/app.pro` `DEFINES += HAVE_COREAUDIO` and the `streaming/audio/renderers/coreaudio/` sources, including `au_spatial_renderer.mm`
- `app/streaming/audio/audio.cpp` `TRY_INIT_RENDERER(CoreAudioRenderer, …)` under `HAVE_COREAUDIO`
- `CoreAudioRenderer` / `AUSpatialMixerOutputType` in `coreaudio.h`

Checked with `git diff` on `app/streaming/audio` (empty) and by reading those
symbols after the PyroWave edits. The macOS framework list (`CoreAudio`,
`AudioToolbox`, `AudioUnit`, `Accelerate`, …) is untouched. The protocol
patch does not edit `Platform.c`, so `clock_gettime_nsec_np` stays.

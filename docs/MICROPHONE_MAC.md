# Mac microphone capture

Twilight can capture the Mac microphone and send it to the host during a stream. Playback of the host's game audio is unchanged. This is client-to-host audio, the reverse of the existing Opus stream.

The setting is macOS only. Other platforms keep a stub that does not open a device and does not send packets.

## What Moonlight does today

Upstream Moonlight Qt does not capture a microphone. `SdlAudioRenderer` opens an output device. There is no `NSMicrophoneUsageDescription` on upstream, and no control-stream packet for voice.

`moonlight-common-c` at `7feb0a6` (upstream `f900dd4` plus PyroWave) has no microphone API. `scripts/apply_mic_control_packet.py` adds two functions to that tree at qmake time. Do not roll the submodule back, and do not run `scripts/apply_pyrowave_protocol.py`: PyroWave packets are already in this pin.

- `LiSendRawControlStreamPacket(type, bytes, length)` sends one payload on the existing ENet control stream (`CTRL_CHANNEL_GENERIC`, flags 0).
- `LiIsControlStreamEncrypted()` reports whether that stream is AES-GCM encrypted.

The patch refuses a payload longer than 251 bytes. `sendMessageEnet()` copies `sizeof(NVCTL_ENET_PACKET_HEADER_V2) + length` into a 256-byte stack buffer and asserts the sum is strictly less than 256. The V2 header is 4 bytes.

## Which host protocol this speaks

Several incompatible microphone experiments exist. This client speaks only the one Vibelight uses with its Vibepollo fork.

| Host / client | On the wire | This build |
| --- | --- | --- |
| xenstalker02 Vibelight + Vibepollo | Control packet `0x3003`. 4-byte header: big-endian sequence, channel count `1`, flags `0`, then one Opus packet. 48 kHz mono, 20 ms, 64 kbps VBR, VOIP, FEC, DTX. AES-GCM because it rides the encrypted control stream. | Sends this. |
| Stock LizardByte Sunshine | No microphone receiver. | Does not decode these packets. The stream itself should keep working. Confirm the host log before relying on that. |
| Nonary/Vibepollo | Issue 169 (the Vibelight `0x3003` design) was closed. That tree does not ship the receiver. | Same as stock Sunshine unless a build cherry-picked the receiver. |
| JimothySnicket moonlight-mic | Control packet `0x5510` plus an 8-byte big-endian frame header, gated by SDP feature flags. | Not sent. |
| logabell moonlight-qt-mic | `LiSendMicrophoneOpusDataEx` on a separate UDP port. | Not sent. |
| moonlight-common-c PR 123 | UDP packet type `0x61` with a 12-byte header. | Not sent. |
| NVIDIA GeForce Experience | No client microphone. | Capture is not started. The log says microphone forwarding stays off. |

Opus bytes are capped at 247 so the 4-byte microphone header plus the Opus packet still fit in the 251-byte control payload. 64 kbps voice is well under that. A frame that does not fit is dropped.

Capture stays off unless all of these are true:

1. macOS.
2. Settings → Audio → "Stream microphone to the host" is checked, and macOS has granted microphone access. The Twilight switch calls `setMicrophoneEnabled`.
3. The host is not GeForce Experience (`NvComputer::isNvidiaServerSoftware`).
4. `LiIsControlStreamEncrypted()` is true. That flag follows the host version (7.1.431 or newer), which is when moonlight-common-c encrypts control packets. Voice is not sent on an unencrypted control stream.

There is no SDP capability bit. A Sunshine build that does not know `0x3003` still receives the packets if the toggle is on. Receiving them is not the same as showing a Windows input device.

## When Windows shows a microphone

xenstalker02/Vibepollo does not create an input device at connect time. On session start it arms passthrough only when `mic_sink` is non-empty (the default on that fork is `Speakers (Steam Streaming Microphone)`) and the control stream negotiated `SS_ENC_CONTROL_V2`. The Steam Streaming Microphone endpoint, the default-capture switch, and the Opus decoder are created on the **first** valid `0x3003` packet. Until that packet arrives, Windows has nothing new to select.

That first packet is ignored, and no device appears, when any of these is true:

- The host is stock Sunshine, Apollo without this patch, or Nonary/Vibepollo. Issue 169 on Nonary/Vibepollo was closed. That tree does not ship the receiver. No client packet can make it grow "Microphone (Steam Streaming Microphone)".
- `mic_sink` was cleared in the host config. The log line is `mic_sink not configured — passthrough disabled`.
- Steam is not running, so the Steam audio endpoint is missing. The log line is `Steam Streaming Microphone unavailable — passthrough disabled`.
- The client never sends a packet. See the capture notes below. A quiet mic used to hit Opus DTX and send nothing; DTX is now off.

A working host log looks like `passthrough armed`, then `First mic packet received from client`, then `using Steam Streaming Microphone backend`. The recording meter for "Microphone (Steam Streaming Microphone)" moves after that. Point Discord or the game at that device, or at Default after Vibepollo switches the default input.

## Mac capture path

`MicrophoneCapture` in `app/streaming/audio/microphone/mic_capture_mac.mm`:

1. `Session::startMicrophone()` runs on the async connection thread. The `AVAudioEngine` graph is created and started on the main thread. Starting it on the connection thread is accepted by `startAndReturnError` and then delivers no buffers.
2. The input node is connected to an `AVAudioSinkNode` before the tap is installed. A tap on an unconnected input does not pull the microphone. The sink does not open a playback device.
3. The tap format is non-interleaved float32. Downmix to mono happens in the tap, then a linear resample to 48 kHz (`MicResampler`).
4. A worker thread slices 960-sample frames, encodes Opus with DTX off, and calls `LiSendRawControlStreamPacket`. Until the tap delivers samples, the worker sends silence so the host can open its device. Mute replaces the frame with silence and still sends.
5. The tap does not encode or send. The worker paces sends at 20 ms and drops queued audio beyond two frames.

`Session::startConnectionAsync()` starts capture after `LiStartConnection()` succeeds. `DeferredSessionCleanupTask` stops it, and joins the worker, before `LiStopConnection()`.

Mute is Ctrl+Alt+Shift+N during the stream. Mute replaces the frame with silence and still sends, so the host plays silence instead of packet-loss concealment. The device stays open, so unmute does not ask for permission again. Mute does not persist across streams. The shortcut is disabled on non-macOS builds so the keys are still delivered to the host there.

Permission is requested from the settings checkbox via `AVCaptureDevice requestAccessForMediaType:`, not from inside the stream. If access is missing when the stream starts, the stream continues and the log says capture did not start. Denied, restricted, and missing-entitlement states leave the checkbox off. A denial shows a toast. When macOS has already denied access, the status line opens System Settings at Privacy & Security → Microphone. The usage string is `NSMicrophoneUsageDescription` in `app/Info.plist`, and it already says Twilight uses the microphone on every Mac build. A Developer ID build and a sandboxed build both need `com.apple.security.device.audio-input`, or macOS denies the device before it can show the prompt. See the entitlements section below and `docs/TWILIGHT_MAS.md`.

## Entitlements

TCC requires the usage string for every Mac build, sandboxed or not.

`com.apple.security.device.audio-input` is also required on a Developer ID build. That build is signed with the Hardened Runtime and is not sandboxed. Without this key, macOS refuses the microphone and never shows the usage-string prompt, so the settings switch snaps back off and Twilight never appears under Privacy & Security → Microphone. The key is the Hardened Runtime audio-input exception. It is not a restricted entitlement and does not need a provisioning profile or the extra Apple approval that head pose and personalized HRTF need. The App Sandbox needs the same key for a different reason: the sandbox denies the device before macOS can show the prompt.

- `app/deploy/macos/Twilight-DeveloperID.entitlements` — used when `TWILIGHT_SIGN=1`. This file contains only `com.apple.security.device.audio-input`. It does not enable the App Sandbox.
- `app/deploy/macos/Twilight-MAS.entitlements` — used when `TWILIGHT_MAS=1`. The store profile includes the same microphone key plus the sandbox.

`scripts/generate-dmg.sh` does not sign with `spatial-audio.entitlements`.

Unsigned and ad-hoc builds that are not running under the Hardened Runtime do not embed this entitlement. They still need the usage string. A signed build that is missing the key is detected at runtime (`SecCodeCopySigningInformation`). Settings then say the build cannot ask for access, and the log says macOS will deny the microphone without asking. That check uses Security.framework APIs that exist on macOS 13.

Do not upload a build or submit it for App Store review.

## Testing

Packet layout and the resampler are covered without a Mac or a host:

```sh
c++ -std=c++11 \
  -I app/streaming/audio/microphone \
  tests/mic_capture_test.cpp \
  app/streaming/audio/microphone/mic_wire.cpp \
  -o /tmp/mic_capture_test
/tmp/mic_capture_test
```

The control-stream patch can be checked against a copy of pin `7feb0a6`:

```sh
python3 scripts/apply_mic_control_packet.py /path/to/moonlight-common-c/src
python3 scripts/apply_mic_control_packet.py /path/to/moonlight-common-c/src
```

The second run prints `already patched` and does not edit the files again.

On a Mac, against a host that actually decodes `0x3003` (xenstalker02 Vibepollo, or another tree that copied the Vibelight receiver):

1. Pair and open Settings → Audio. Check "Stream microphone to the host" and allow the system prompt. A Developer ID build has to be signed with `com.apple.security.device.audio-input`. Without that key there is no prompt: the switch snaps off, and the status line says the build cannot ask for access.
2. Start a stream with Steam running on the Windows host. The Moonlight log should include `Microphone capture started` and `Sent first microphone packet`. The host log should include `First mic packet received from client`. Speak. The recording meter for "Microphone (Steam Streaming Microphone)" should move. Discord or a game has to be set to that device, or to Default after Vibepollo switches the default input.
3. Press Ctrl+Alt+Shift+N. The meter should drop to silence. Press it again and it should return.
4. Quit the stream. The next stream starts unmuted.

Against stock Sunshine or Nonary/Vibepollo:

1. The Moonlight stream should still connect, show video, and play game audio.
2. The host will not grow a virtual microphone from this client.
3. Watch the host log for an unknown control type `0x3003`. If that host treats unknown control packets as fatal, turn the setting off. That failure mode was not reproduced here.

GeForce Experience: the stream starts, capture does not, and the log says forwarding stays off.

This environment is Linux, so AVAudioEngine, the permission prompt, and a live Vibepollo session were not run here.

## Known gaps

- No hardware capture run in CI. The Mac file is compiled only by a macOS qmake build.
- Stock Sunshine and Nonary/Vibepollo do not create a Windows input device. The bytes match Vibelight's client, not an upstream Sunshine spec. xenstalker02/Vibepollo creates "Microphone (Steam Streaming Microphone)" only after the first packet, and only while Steam is running.
- No host capability flag. The client cannot tell a decoding Vibepollo from stock Sunshine before it sends.
- `0x5510` and the separate UDP microphone port are not implemented.
- The linear resampler is for voice. It is not a band-limited converter.
- Opus frames larger than 247 bytes are dropped. Normal 64 kbps speech does not reach that.
- Mute sends encoded silence. It does not release the input device.
- A sandboxed Mac App Store build still needs a provisioning profile for the existing spatial-audio entitlements before it can be signed for the store. Microphone support does not change that, and this work does not submit anything.

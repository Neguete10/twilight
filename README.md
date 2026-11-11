# Twilight

Twilight is an Apple Silicon Mac client for streaming a game from another computer. It is a fork of [Moonlight Qt](https://github.com/moonlight-stream/moonlight-qt). Moonlight has not endorsed it.

This tree is rebuilt on [Andy Grundman's](https://github.com/andygrundman/moonlight-qt) `v6.2.0-metal-v9b` tag, which already contains upstream Moonlight Qt 6.2.0. The interactive shell is Twilight's own. The previous Classic shell is not the app you land in.

## On the Mac

**Twilight's shell.** Hosts along the side, games in a library, and an About page that can check GitHub for a newer release. Nothing is installed for you.

**PyroWave on Metal and Vulkan, opt-in.** Built when `CONFIG+=pyrowave` is set. Settings can force the PyroWave codec. Automatic codec selection stays on HEVC or AV1 and does not advertise PyroWave. The Vulkan backend is MoltenVK and is used only when the PyroWave GPU backend is set to Vulkan. Automatic and Metal use the Metal decoder.

**Spatial audio through Core Audio.** Surround streams can use Apple's spatial mixer. Stereo is passed through. Head tracking stays off until you ask for it.

**Picture-in-picture.** The stream window can shrink into a floating mini player. Control+Option+Shift+P toggles it. Closing the stream window still ends the stream.

**Microphone forwarding.** This Mac's microphone can be sent to the host on the encrypted control stream (packet `0x3003`). Stock Sunshine does not play it. GeForce Experience does not receive it.

**Adaptive triggers.** When the host sends DualSense effects, Twilight programs the triggers over USB or Bluetooth, with an IOKit fallback when SDL cannot. Pairing stays with macOS.

**CoreHID raw mouse.** Off until you turn on **Use CoreHID raw mouse (macOS games)**.

**Game Mode.** The bundle declares Game Mode support. A full-screen stream on a recent Mac can be scheduled ahead of other apps.

**Performance overlay.** The classic yellow stats overlay is still there. Twilight's HUD (frame rate, bitrate, latency, End) is separate and off until you enable it.

## Requirements

- Apple Silicon Mac
- macOS 13 Ventura or later
- Qt 6.11.2 (`qmake` and `macdeployqt`), matching Moonlight Qt 6.2
- Prebuilt libraries from [moonlight-qt-deps](https://github.com/moonlight-stream/moonlight-qt-deps) tag `v19` (`python3 setup-deps.py`). Do not substitute Homebrew libraries into the bundle.
- [create-dmg](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`) for the disk image

Nothing copied into `Twilight.app` may require a newer macOS than 13.0, and every Mach-O in the bundle must have an arm64 slice. `scripts/generate-dmg.sh` runs `scripts/check-macos-availability.py` before compile and `scripts/check-macos-minos.py` on the finished bundle. The bundle check stops if minos is above 13.0, arm64 is missing, or a non-weak `LC_LOAD_DYLIB` pulls in a system framework that macOS 13 does not have. Frameworks and APIs newer than macOS 13 must be weak-linked and used only from `@available` / `__builtin_available`, with a fallback. The Mac compile treats `-Wunguarded-availability-new` as an error at deployment target 13.0.

## Building

Init the submodules, then:

```sh
scripts/generate-dmg.sh Release
```

That configures an arm64 build, passes `CONFIG+=pyrowave` unless `TWILIGHT_PYROWAVE=0`, and writes `build/installer-Release/Twilight-<version>.dmg`. The disk image opens with Twilight.app on the left and an Applications alias on the right. Layout and the window picture live in `app/deploy/macos/dmg/`.

Developer ID signing and notarization are hooks only. They do not run unless you set `TWILIGHT_SIGN=1` and, for notarization, `TWILIGHT_NOTARIZE=1`. Developer ID uses `app/deploy/macos/Twilight-DeveloperID.entitlements`, which contains only the Hardened Runtime microphone exception `com.apple.security.device.audio-input` and does not enable the App Sandbox. The notary keychain profile name is `twilight-notary` (team `TAV97BM6HV`).

`TWILIGHT_MAS=1` is the optional Mac App Store package path. It is not the desktop disk image.

The version in this tree is `7.2.0`. That number is not a published release.

7.2.0 adds optional MetalFX spatial upscaling on macOS. It is off until the video setting is turned on. 7.1.1 keeps a saved V-Sync choice across relaunch. A custom bitrate is no longer replaced when resolution, frame rate, or 4:4:4 changes.

## Tests

Headless checks, from the repo root. No Mac, no GPU, and no host:

```sh
bash scripts/run-tests.sh
```

That runs the Python checks, the C++ logic tests (codec offer, bitrate, V-Sync, update comparison), and the Qt Test binary. The script looks for Qt 6 `qmake6` on `PATH`, then `qmake` if it reports Qt 6, then `QTDIR` (`$QTDIR/bin` or `$QTDIR/macos/bin`), then `~/Qt/*/macos/bin`. Official Qt 6.11.2 is `~/Qt/6.11.2/macos/bin/qmake`. The binary loads the real v2 shell offscreen, toggles settings, and fails if QML reports a warning. CI runs this as the `headless-tests` job. The macOS packaging job compiles the app, including the session codec checks.

A fake GameStream HTTP server, still with no video:

```sh
python3 tests/mock_host_test.py
python3 tests/mock_host.py --port 47989
```

It answers `/serverinfo`, `/applist`, `/launch`, and `/cancel`. Pairing crypto and the video stream are not implemented.

On the Mac that will actually stream, against a paired host:

```sh
python3 scripts/e2e/stream_matrix.py \
  --app /path/to/Twilight.app \
  --host 192.168.1.20 \
  --game Desktop
```

The `.app` must be the build product. The script refuses a path under `/Applications` and refuses to start if a Twilight process is already running. `--host` must answer TCP 47989 or 47984 before any preference is written. It exports `com.moonlight-stream.Moonlight` first and aborts without changes if that export fails. It never deletes the preferences domain. After the run it imports the backup, checks the live plist matches, and leaves the backup file in the report directory. Each case starts `stream`, waits until the log contains `Video stream is`, holds the stream for `--seconds` (default 8), screenshots the Twilight window, then runs `quit` (or sends SIGTERM for that case). Reports land in `build/e2e-report/`. MetalFX is required in the log only when the stream size is smaller than the main display in both dimensions. Pass `--host-end-command` (or `TWILIGHT_HOST_END_COMMAND`) with a shell command that makes the host end the stream; without it that case is skipped.

Still needs a person: whether the picture looks sharp, HDR brightness, VRR smoothness, controller rumble and adaptive triggers, and whether microphone audio sounds right on the host. The script only checks that the stream started, the logged codec and renderer match, MetalFX logged itself when requested, the process exited, and no new crash report appeared.

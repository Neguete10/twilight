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

Developer ID signing and notarization are hooks only. They do not run unless you set `TWILIGHT_SIGN=1` and, for notarization, `TWILIGHT_NOTARIZE=1`. Developer ID uses the empty entitlements file `app/deploy/macos/Twilight-DeveloperID.entitlements`. The notary keychain profile name is `twilight-notary` (team `TAV97BM6HV`).

`TWILIGHT_MAS=1` is the optional Mac App Store package path. It is not the desktop disk image.

The version in this tree is `7.1.0`. That number is not a published release.

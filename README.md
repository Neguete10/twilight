# Twilight

Twilight is a Mac client for streaming a game from another computer. It is a GPL-3.0 fork of [Moonlight Qt](https://github.com/moonlight-stream/moonlight-qt) through [Andy Grundman's moonlight-qt](https://github.com/andygrundman/moonlight-qt), including the CoreAudio spatial-audio work from `andyg.coreaudio-spatial-mixer`. The same license as Moonlight applies. See `LICENSE`.

Upstream Moonlight is a PC client for NVIDIA GameStream and [Sunshine](https://github.com/LizardByte/Sunshine). Twilight keeps that client and adds a Mac app, a second launcher shell, a CoreAudio spatial mixer, optional PyroWave decode, and a picture-in-picture mini player. This repository does not publish the upstream Windows, Snap, Flatpak, Steam Link, or Raspberry Pi packages, and it does not ship translation catalogs.

The interface in this tree is English. Strings are wrapped for Qt translation, but there are no `.ts` or `.qm` catalogs and no translator is loaded. The Mac bundle's development region is `en`, and the only localized bundle strings are `app/deploy/macos/en.lproj`.

## What this tree ships

The product is the Mac app. A makefile build names the bundle `Twilight.app`. `CFBundleName` and `CFBundleDisplayName` are Twilight. The executable stays `Twilight.app/Contents/MacOS/Moonlight`, the bundle id stays `com.moonlight-stream.Moonlight` unless `CONFIG+=twilight-mas`, and `QSettings` stay under the Moonlight name. The bundle's minimum system version is macOS 11.

Two shells share one settings object:

- **Twilight** is the starting shell (`uiVersion` `v2`, including when the key is missing). It is a host sidebar, an app library, and its own settings sheet.
- **Classic** is the Moonlight shell (`uiVersion` `v1`). The toolbar switches shells. The choice is saved and is not offered while a stream is open.

H.264, HEVC, and AV1 decode with VideoToolbox. HDR and YUV 4:4:4 remain host-dependent, as in Moonlight.

### PyroWave

[PyroWave](https://github.com/Themaister/pyrowave) is an intra-only GPU wavelet codec. Twilight can decode it. A normal GameStream or Sunshine host does not send it. A host that advertises it (Vibeshine or a Vibepollo build that does) can.

The decoders are compiled only when qmake is run with `CONFIG+=pyrowave`. That Mac build has two backends:

- **Vulkan** uses MoltenVK and links `libpyrowave-shared` from the `pyrowave` submodule, pin `263ef100`.
- **Metal** does not link that library. It `dlopen`s `libpyrowave-metal` (API 0.5.0) from the `pyrowave-metal` submodule, pin `89f7e47`. The two libraries export the same C names with different signatures, so they stay separate.

When both backends are compiled, Advanced settings offer **PyroWave GPU backend**: Automatic, Metal, or Vulkan. Automatic uses Metal when the dylib loads and the GPU is Apple7, and otherwise uses Vulkan. Choosing Metal or Vulkan uses only that backend. Intel and AMD Macs fail the Metal device check, so Automatic on those machines uses Vulkan. H.264, HEVC, and AV1 stay on VideoToolbox either way.

The current release includes both backends. See [PyroWave on Twilight](docs/PYROWAVE_MAC.md) for the bitstream, the host framing, and what has not been proven on a live stream.

### Spatial audio

On macOS, playback tries `CoreAudioRenderer` before SDL. `app/app.pro` always defines `HAVE_COREAUDIO`.

The settings sheet says the mixer is used on headphones, built-in MacBook speakers, and 2-channel USB devices, and that stereo skips it. In the renderer, a stream with more than two channels uses the mixer unless spatial audio is disabled or the output is classified as external speakers. USB and Bluetooth transports are classified as headphones. HDMI is classified as external speakers and is passed through. The mixer renders binaural audio for headphones and Apple's built-in-speaker processing for the laptop speakers.

**Spatial audio** in settings is Enabled or Disabled. Enabled is the stored default (`SAC_AUTO`). Stereo hides the control. **Head tracking** is off unless you turn it on. The renderer writes `kAudioUnitProperty_SpatialMixerEnableHeadTracking` only for headphones. The settings line says that requires supported Apple or Beats headphones. Signed desktop builds pass `com.apple.developer.coremotion.head-pose` in `app/deploy/macos/spatial-audio.entitlements`.

### Performance stats

Two overlays are independent. Turning one off does not remove the other.

**Classic performance overlay.** Yellow video stats drawn on the stream by the same overlay path Moonlight uses (`OverlayDebug`, color `0xD0D000`). The preference is `showPerformanceOverlay`, stored as `showperfoverlay`. A missing key is off. The Twilight settings sheet calls this switch **Classic performance overlay**. On H.264, HEVC, and AV1 the text includes FEC lines. PyroWave's stats string has no FEC fields, and this overlay does not add any. The same shortcut also toggles the audio stats overlay (`OverlayDebugAudio`).

While a stream is open:

- **Ctrl+Alt+Shift+S** toggles it. On a Mac keyboard that is Control+Option+Shift+S. The key is handled before it is sent to the host.
- **Select+L1+R1+X** does the same thing on a gamepad.

The session starts from `showperfoverlay`. The shortcut flips the live overlay. It does not delete the Twilight HUD, and it does not change the Twilight performance-overlay switch.

**Twilight HUD.** Glass chips for FPS, bitrate, and average network latency, plus End, while a Twilight stream is open. The preference is `showTwilightHud`. A missing key is off. The chips are shown only when the Twilight shell is selected and this switch is on. End asks once, then quits the stream the same way Ctrl+Alt+Shift+Q does. On macOS the HUD is a child of the stream window, including fullscreen and steady-state picture-in-picture. It is not the yellow Classic overlay.

### Picture in picture

On macOS, **Ctrl+Alt+Shift+P** (Control+Option+Shift+P) turns the SDL stream window into a floating mini player at the bottom-right of the current display. **Window → Enter Picture in Picture** does the same thing. Press the shortcut again, use the menu, or press **Ctrl+Alt+Shift+X** to leave. X restores the window you entered from, including fullscreen.

This is not system Picture in Picture. There is no `AVPictureInPictureController` and no second video path. The same decoder keeps presenting into that window, which is what lets Metal and Vulkan streams use it. Closing the window still ends the stream. Behavior and limits are in [Picture in Picture](docs/PIP_MAC.md).

### Other Mac behavior

These are in the tree and documented on their own pages. They are not part of upstream Moonlight Qt.

- [DualSense adaptive triggers and the on-stream pad overlay](docs/DUALSENSE_MAC.md). Local preview is Ctrl+Alt+Shift+T or Select+L1+R1+A. The pad overlay is Ctrl+Alt+Shift+G or Select+L1+R1+Y.
- [CoreHID mouse capture](docs/COREHID_MAC.md). Off unless you enable it. Trackpads stay on SDL.
- [Microphone to the host](docs/MICROPHONE_MAC.md). macOS only, on the encrypted control stream. A Vibepollo build with Vibelight passthrough can play it. Stock Sunshine does not. Ctrl+Alt+Shift+N mutes it during a stream.
- [Network profiles](docs/NETWORK_PROFILES.md) in Classic settings.
- [Mac App Store scaffolding](docs/TWILIGHT_MAS.md). `CONFIG+=twilight-mas` is local signing config. This tree does not submit a build.

## Release

The current release is [v6.1.1](https://github.com/Neguete10/twilight/releases/tag/v6.1.1). The asset is `Twilight-6.1.1.dmg`. That build is ad-hoc signed and not notarized. Its note says it fixes the picture-in-picture crash in the audio decoder, and that the Mac build includes PyroWave Vulkan and Metal (`libpyrowave-metal` 0.5.0, source `89f7e47`). `app/version.txt` in this tree is `6.1.1`.

## Building the Mac app

Run `qmake app.pro` inside `app/`. `app/app.pro` links the static libraries with `-L$$OUT_PWD/../…`. `OUT_PWD` is the directory where that qmake writes the Makefile, so the command has to run in `app/` for those lines to land on the sibling projects. Running `qmake app/app.pro` from the repository root sets `OUT_PWD` to the root and points the link lines outside the tree.

`scripts/generate-dmg.sh` is a different configure. It runs qmake on `moonlight-qt.pro` in a build directory and does not pass `CONFIG+=pyrowave`.

`CONFIG+=pyrowave` is what compiles the Vulkan and Metal decoders. On macOS the qmake line also needs `CONFIG+=sdk_no_version_check` and `CONFIG+=release`. The Metal dylib has to exist before that qmake. `app/app.pro` adds it with `$$files(../pyrowave-metal/build/libpyrowave-metal*.dylib)`, and `$$files()` expands when qmake runs. A dylib produced only later is not in that bundle file list. The makefile still builds and copies one when the app target is built. The file list itself only contains a dylib that was already there.

### Tools

- Xcode, for the macOS SDK and Metal.
- Qt 6's `qmake` and `macdeployqt` on `PATH`.
- CMake, and Python 3. qmake runs the `scripts/apply_*.py` patches before compiling.
- `libplacebo` where the linker will see it. The PyroWave link line is `-lplacebo` with no Homebrew `-L` of its own, so the app link uses `LIBRARY_PATH=/opt/homebrew/lib`.

### Submodules and static libraries

From the repository root:

```sh
git submodule update --init --recursive
```

That checks out every submodule in `.gitmodules`, including `pyrowave-metal`, `pyrowave`, `libs` (the Mac FFmpeg, SDL, and OpenSSL prebuilts), and `app/SDL_GameControllerDB` (embedded by `app/resources.qrc`). If `pyrowave-metal` is missing, qmake with `CONFIG+=pyrowave` stops and tells you to run:

```sh
git submodule update --init pyrowave-metal
```

`app/app.pro` links `libmoonlight-common-c`, `libqmdnsengine`, `libh264bitstream`, and `libsoundio` from the directories next to `app/`. Build those qmake projects first:

```sh
cd moonlight-common-c && qmake moonlight-common-c.pro CONFIG+=release && make release && cd ..
cd qmdnsengine && qmake qmdnsengine.pro CONFIG+=release && make release && cd ..
cd h264bitstream && qmake h264bitstream.pro CONFIG+=release && make release && cd ..
cd soundio && qmake soundio.pro CONFIG+=release && make release && cd ..
```

The archives `app/app.pro` looks for are `moonlight-common-c/libmoonlight-common-c.a`, `qmdnsengine/libqmdnsengine.a`, `h264bitstream/libh264bitstream.a`, and `soundio/libsoundio.a`.

### PyroWave libraries

Vulkan shared library, submodule pin `263ef100`. Leave that pin where it is. Do not check the Metal commit out over `pyrowave`.

```sh
git submodule update --init pyrowave
cd pyrowave && bash checkout_granite.sh && cd ..
cmake -S pyrowave -B pyrowave/build -DPYROWAVE_SHARED=ON
cmake --build pyrowave/build --target pyrowave-shared
```

Metal dylib, before the app qmake. `checkout_granite.sh` is not part of this submodule. The script below is `cmake -S pyrowave-metal/metal -B pyrowave-metal/build` and `cmake --build`.

```sh
git submodule update --init pyrowave-metal
scripts/build-pyrowave-metal.sh build
```

That writes `pyrowave-metal/build/libpyrowave-metal*.dylib`. Do not commit it.

### qmake, make, macdeployqt

From `app/`:

```sh
cd app
LIBRARY_PATH=/opt/homebrew/lib qmake app.pro \
  CONFIG+=sdk_no_version_check CONFIG+=release CONFIG+=pyrowave
make release
macdeployqt Twilight.app -qmldir=gui
```

`qmake app.pro` has to be that command, in that directory, and the Metal dylib has to already be in `pyrowave-metal/build/`. `make release` produces `app/Twilight.app`. `macdeployqt` copies Qt into the bundle. `scripts/generate-dmg.sh` runs `macdeployqt` with `-qmldir` pointed at `app/gui` and with `-appstore-compliant`. That script is a separate configure, as noted above.

Open `app/Twilight.app`. The process name is still Moonlight.

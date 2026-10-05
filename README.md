# Twilight

Twilight is Henrique's Mac client for streaming a game from another computer. He loves [Moonlight](https://github.com/moonlight-stream/moonlight-qt)'s Qt client, and the open source community around it. Twilight is his fork of [Andy Grundman's](https://github.com/andygrundman/moonlight-qt) Core Audio spatial fork ([`andyg.coreaudio-spatial-mixer`](https://github.com/andygrundman/moonlight-qt/tree/andyg.coreaudio-spatial-mixer)), so he can keep helping macOS people specifically. It sits beside Moonlight. Moonlight has not endorsed it.

Twilight is GPL-3.0, the same license as Moonlight. See [`LICENSE`](LICENSE).

You land in a new UI. The classic Moonlight shell is still one click away. The Mac build also has PyroWave on Vulkan and Metal (when the host sends it), spatial audio through Core Audio, picture-in-picture, the Mac microphone sent through to the host, adaptive triggers, a CoreHID raw mouse, macOS Game Mode, and a performance overlay.

## Download

The notarized disk image is on the [v7.0.0 release](https://github.com/Neguete10/twilight/releases/tag/v7.0.0): [Twilight-7.0.0.dmg](https://github.com/Neguete10/twilight/releases/download/v7.0.0/Twilight-7.0.0.dmg). Developer ID signed, notarized by Apple, a direct download. It wants macOS 11 or later.

## Building

To build it, init the submodules and run `scripts/generate-dmg.sh Release`. You will want Qt 6 (`qmake` and `macdeployqt`), Xcode, and [create-dmg](https://github.com/sindresorhus/create-dmg). PyroWave's Vulkan and Metal decoders also need `CONFIG+=pyrowave`. That flag is described in `app/app.pro`. The disk-image script leaves it off.

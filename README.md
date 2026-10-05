# Twilight

Twilight is Henrique's Mac client for streaming a game from another computer. He loves [Moonlight](https://github.com/moonlight-stream/moonlight-qt)'s Qt client, and the open source community around it. Twilight is his fork of [Andy Grundman's](https://github.com/andygrundman/moonlight-qt) Core Audio spatial fork ([`andyg.coreaudio-spatial-mixer`](https://github.com/andygrundman/moonlight-qt/tree/andyg.coreaudio-spatial-mixer)), so he can keep helping macOS people specifically.

It sits beside Moonlight. Moonlight has not endorsed it.

Twilight is GPL-3.0, the same license as Moonlight. See [`LICENSE`](LICENSE).

## On the Mac

**A new UI.** You land in Twilight's own shell: your hosts along the side, your games in a library. The classic Moonlight shell is still one click away, on the toolbar, and Twilight remembers which one you picked. The switch waits until the stream is closed.

**PyroWave on Vulkan and Metal.** Twilight can decode [PyroWave](https://github.com/Themaister/pyrowave) on either backend. Vulkan goes through MoltenVK. Metal is the native path, and settings can pick Automatic, Metal, or Vulkan when both are built in. A normal GameStream or Sunshine host does not send this codec. When a host does, both decoders are in the v7 build.

**Spatial audio through Core Audio.** Surround streams get Apple's spatial mixer. Headphones come out binaural, the MacBook's own speakers get Apple's built-in processing, and something like HDMI is passed through. Stereo is already where it wants to be, so the mixer sits that one out. Head tracking stays off until you ask for it.

**Picture-in-picture.** The stream window can shrink into a floating mini player at the corner of the screen. Same decoder, same picture, just smaller and out of the way. The menu is Window → Enter Picture in Picture, and Control+Option+Shift+P does the same thing. Close that window and the stream ends, the same as always.

**The Mac microphone, sent through to the host.** Twilight can capture this Mac's microphone and send it along on the encrypted control stream. Game audio coming back is unchanged. The host has to know how to play that audio. Stock Sunshine does not.

**Adaptive triggers.** A DualSense can still push back. When the host sends adaptive-trigger effects, Twilight programs the triggers on the Mac, over USB or Bluetooth. Pairing stays with macOS. Twilight just teaches the pad the effect.

**CoreHID raw mouse.** There is an opt-in raw mouse path for macOS games, aimed at the HID reports instead of the usual SDL warp. It is off until you turn on **Use CoreHID raw mouse (macOS games)**. Trackpads stay on SDL either way.

**macOS Game Mode.** That is the project's name for it, and Apple's. On a recent Mac, a full-screen stream can land in Game Mode, which is the system putting that game first: more of the CPU and GPU, and snappier Bluetooth for controllers and headphones.

**A performance overlay.** Two of them, and they mind their own business. The classic one is the yellow stats Moonlight people already know. Twilight's own is a small HUD while its shell is in use: frame rate, bitrate, network latency, and an End button when you are done.

## Download

The notarized disk image is on the [v7.0.0 release](https://github.com/Neguete10/twilight/releases/tag/v7.0.0): [Twilight-7.0.0.dmg](https://github.com/Neguete10/twilight/releases/download/v7.0.0/Twilight-7.0.0.dmg). Developer ID signed, notarized by Apple, a direct download. It wants macOS 11 or later.

## Building

To build it, init the submodules and run `scripts/generate-dmg.sh Release`. You will want Qt 6 (`qmake` and `macdeployqt`), Xcode, and [create-dmg](https://github.com/sindresorhus/create-dmg). PyroWave's Vulkan and Metal decoders also need `CONFIG+=pyrowave`. That flag is described in `app/app.pro`. The disk-image script leaves it off.

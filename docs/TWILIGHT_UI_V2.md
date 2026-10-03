# Twilight UI V2

Twilight keeps the classic Moonlight shell and adds a second one. The starting shell is Twilight. Classic is still one click away, and that choice is remembered.

## Toggle

The main window toolbar has a **Twilight / Classic** control. Twilight is the left segment.

- Twilight is `uiVersion=v2` (the value used when the key is missing).
- Classic is `uiVersion=v1`.
- The key is `uiVersion` in the normal Moonlight `QSettings` store.
- Switching saves immediately and reloads only the main shell. It does nothing while `streamActive` is set, and the toolbar is not available once a stream has hidden the window.
- Command-line pair, quit, and stream windows stay on the classic path.

## Screens

| Screen | What it does |
| --- | --- |
| Shell | Sidebar of hosts, app library, search, one-click stream, Desktop hero |
| Host sheet | Wake, pair, rename, remove, network test, show hidden apps |
| Settings | Video, Audio (including spatial, head tracking, and on macOS the host microphone), Input, Network, Advanced (codec and PyroWave GPU backend). Same `StreamingPreferences` object as Classic |
| Stream start | Twilight launch card, then the existing `Session` |
| In-stream HUD | Glass chips for FPS, bitrate, and RTT, plus End, while a Twilight stream is open |

Pin on an app tile is Moonlight's existing direct-launch flag (one app per host). Right-click a tile to hide or show it. That uses the same app model as Classic.

## Icons and type

On macOS 11 and later, `image://sfsymbol/<name>/<pointSize>/<hex>` draws a real SF Symbol with `NSImage imageWithSystemSymbolName` (`app/gui/sfsymbol_mac.mm`). The draw matches Qt's `qt_mac_toQPixmap`: flip the bitmap context so y grows downward, then `drawInRect:respectFlipped:YES`, and center the glyph in a square. `CGContextDrawImage` after a single flip is upside down, which is why the earlier attempt stayed inverted. Other platforms, and unknown names, use a small geometric stand-in from `twilightDrawFallbackSymbol`.

Type uses `.AppleSystemUIFont` on Darwin, which is SF Pro on current macOS. The font is not bundled. Windows uses Segoe UI. Elsewhere the application font is left alone.

Glass is a translucent fill, a hairline, and a 1px sheen. This tree does not link Qt GraphicalEffects, so there is no backdrop blur.

Light and dark follow `SystemPalette`. Classic still forces the Material dark theme for its own controls. Twilight paints its own surfaces, so it does not retint Classic.

## HUD stats

When `uiVersion` is `v2` and **Twilight performance overlay** is on (`showTwilightHud`, missing key is off), the decoders build the usual overlay string for the chips. The HUD parses FPS, bitrate, and `Average network latency` and drops FEC lines. PyroWave's string has no FEC fields; the parser does not add any. Turning Twilight's overlay off hides the chips and stops that sampling. The yellow Classic stats overlay follows `showperfoverlay` (missing key is off) and Ctrl+Alt+Shift+S or Select+L1+R1+X. It does not add FEC lines to PyroWave.

The HUD is a separate frameless window, not a tool panel. On macOS its position comes from `SDL_GetWindowPosition` (top-left, the same coordinates Qt uses). The stream loop then does the raise that previously drew the chips: show and `orderFrontRegardless`. The HUD window is a child of the SDL window, so it stays in that window's Space and above the video, including fullscreen and steady-state picture-in-picture. Once it is a child it does not set its own level or collection behavior; those come from the stream window. Picture-in-picture detaches the child for the level, collection behavior, fullscreen, and frame change, then attaches it again. It is also detached before the SDL window is destroyed. A zero-size stream frame is ignored. `setFrameOrigin` is not used. The loop keeps draining Qt events so the chips and End stay live. End asks once, then posts the same `SDL_QUIT` as Ctrl+Alt+Shift+Q. The first placement is logged as `Twilight HUD on stream at`.

## Extending

Add pages under `app/gui/ui/v2/` and list them in `app/qml.qrc`. The shell is `ShellV2.qml`, loaded by a `Loader` in `app/gui/main.qml` only after Twilight is selected. Do not edit Classic screens for V2-only layout. Bind new settings to `StreamingPreferences` and call `save()` when the sheet closes.

## Known gaps

- SF Symbols are real only on macOS 11+. Other platforms get the geometric stand-ins.
- No backdrop blur.
- On macOS the HUD is a child of the SDL stream window and follows its position, including picture-in-picture. Elsewhere it sits at the top of the primary screen.
- Gamepad grid navigation stays on Classic. Twilight is pointer-first, with preferences, New, and Escape shortcuts.
- Custom resolution, custom frame rate, and packet size stay in Classic. Twilight can show a custom size that was already saved, and offers 720p, 1080p, 1440p, 4K, and the current display mode.
- Linux CI can compile the HUD parser test without Qt (`tests/twilight_hud_parse_test.cpp`). Loading the QML still needs a Qt build of the app. This VM does not treat a missing full Moonlight link as a V2 failure.

## Not in this pass

CoreHID, picture in picture, DualSense adaptive triggers, and network profiles. The macOS host-microphone switch is in Twilight Audio and uses the same preference as Classic. Session, CoreAudio spatial, and PyroWave decode paths are unchanged except for publishing the overlay text the HUD already knows how to read.

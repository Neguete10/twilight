# Twilight UI

The interactive app is the Twilight shell. There is no Classic shell and no version toggle.

- `uiVersion` is always `v2`. A missing key and a stored `v1` are both rewritten to `v2`.
- The key is `uiVersion` in the normal Moonlight `QSettings` store.
- Command-line pair, quit, and stream windows stay on their existing QML (`CliPair.qml`, `CliQuitStreamSegue.qml`, `CliStartStreamSegue.qml`, plus `StreamSegue.qml` and `QuitSegue.qml`). An empty `initialView` loads Twilight.

## Screens

| Screen | What it does |
| --- | --- |
| Shell | Sidebar of hosts, app library, search, one-click stream, Desktop hero. Arrow keys and the gamepad move between hosts and apps. Menu opens the host sheet or the app menu. Start opens settings. |
| Host sheet | Wake, pair, rename, remove, network test, show hidden apps. Up and down move, confirm activates. |
| Settings | Video, Audio (including spatial, head tracking, and on macOS the host microphone), Input, Network, Advanced (codec and PyroWave GPU backend). Advanced starts with Classic's **Quit app on host PC after ending stream** switch (`quitAppAfter`). Keep that Classic parity toggle. Same `StreamingPreferences` object the stream uses. D-pad up and down walk the focus chain. Resolution and frame rate include a typed custom value, native and notch-excluded sizes, and the refresh rate of every attached display. |
| Stream start | Twilight launch card, then the existing `Session` |
| In-stream HUD | Glass chips for FPS, bitrate, and RTT, plus End, while a Twilight stream is open |

Pin on an app tile is Moonlight's existing direct-launch flag (one app per host). Right-click a tile, or press the menu button, for launch, quit, direct launch, and hide. Hide stays off while that app is running or set to direct launch, unless it is already hidden. Show hidden apps on the host sheet lists every app, including hidden ones. A running tile has its own Quit button, which quits the host app and does not start another. An update pill sits in the shell header when an update is available. About is a Settings section: version, a short notice, Check for Updates, and Source when a browser is available. There is no Licenses control in Twilight Settings. Error dialogs still have a Help button. The shell header does not show Help, About, or Discord.

## Icons and type

On macOS 11 and later, `image://sfsymbol/<name>/<pointSize>/<hex>` draws a real SF Symbol with `NSImage imageWithSystemSymbolName` (`app/gui/sfsymbol_mac.mm`). The draw matches Qt's `qt_mac_toQPixmap`: flip the bitmap context so y grows downward, then `drawInRect:respectFlipped:YES`, and center the glyph in a square. `CGContextDrawImage` after a single flip is upside down, which is why the earlier attempt stayed inverted. Other platforms, and unknown names, use a small geometric stand-in from `twilightDrawFallbackSymbol`.

Type uses `.AppleSystemUIFont` on Darwin, which is SF Pro on current macOS. The font is not bundled. Windows uses Segoe UI. Elsewhere the application font is left alone.

Glass is a translucent fill, a hairline, and a 1px sheen. This tree does not link Qt GraphicalEffects, so there is no backdrop blur.

Light and dark follow `SystemPalette`. Command-line windows and dialogs still use the Material dark theme. Twilight paints its own surfaces.

## HUD stats

When **Twilight performance overlay** is on (`showTwilightHud`, missing key is off), the decoders build the usual overlay string for the chips. `uiVersion` stays `v2`, which is what the sampler checks. The HUD parses FPS, bitrate, and `Average network latency` and drops FEC lines. PyroWave's string has no FEC fields; the parser does not add any. Turning Twilight's overlay off hides the chips and stops that sampling. The yellow stats overlay follows `showperfoverlay` (missing key is off) and Ctrl+Alt+Shift+S or Select+L1+R1+X. It does not add FEC lines to PyroWave.

The HUD is a separate frameless window, not a tool panel. On macOS its position comes from `SDL_GetWindowPosition` (top-left, the same coordinates Qt uses). The stream loop then does the raise that previously drew the chips: show and `orderFrontRegardless`. The HUD window is a child of the SDL window, so it stays in that window's Space and above the video, including fullscreen and steady-state picture-in-picture. Once it is a child it does not set its own level or collection behavior; those come from the stream window. Picture-in-picture detaches the child for the level, collection behavior, fullscreen, and frame change, then attaches it again. It is also detached before the SDL window is destroyed. A zero-size stream frame is ignored. `setFrameOrigin` is not used. The loop keeps draining Qt events so the chips and End stay live. End asks once, then posts the same `SDL_QUIT` as Ctrl+Alt+Shift+Q. The first placement is logged as `Twilight HUD on stream at`.

## Extending

Add pages under `app/gui/ui/v2/` and list them in `app/qml.qrc`. The shell is `ShellV2.qml`, loaded by a `Loader` in `app/gui/main.qml` for every interactive launch. Bind new settings to `StreamingPreferences` and call `save()` when the sheet closes.

Classic parity that has to stay: Settings → Advanced → **Quit app on host PC after ending stream**. The switch reads and writes `StreamingPreferences.quitAppAfter` (QSettings key `quitAppAfter`, default off). When it is on, a graceful stream end quits the app on the host. An unexpected disconnect does not. That is the same path Classic and Moonlight use.

## Known gaps

- SF Symbols are real only on macOS 11+. Other platforms get the geometric stand-ins.
- No backdrop blur.
- On macOS the HUD is a child of the SDL stream window and follows its position, including picture-in-picture. Elsewhere it sits at the top of the primary screen.
- Packet size has no editor in Settings. The saved value still applies, and the command line can still set it.
- Network profiles have no picker in the Twilight shell. The backend, including `StreamingPreferences::applyNetworkProfileSettings`, is unchanged.
- Command-line pair, quit, and stream windows stay on their existing QML.
- Linux CI can compile the HUD parser test without Qt (`tests/twilight_hud_parse_test.cpp`). Loading the QML still needs a Qt build of the app. This VM does not treat a missing full Moonlight link as a V2 failure.

## Not in this pass

CoreHID, picture in picture, DualSense adaptive triggers, and network profiles. The macOS host-microphone switch is in Twilight Audio and calls `setMicrophoneEnabled`. Session, CoreAudio spatial, and PyroWave decode paths are unchanged except for publishing the overlay text the HUD already knows how to read.

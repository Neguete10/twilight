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
| Performance overlay | Yellow stats on the video. Settings → Advanced → Classic performance overlay, the same switch as Classic |

Pin on an app tile is Moonlight's existing direct-launch flag (one app per host). Right-click a tile to hide or show it. That uses the same app model as Classic.

## Icons and type

On macOS 11 and later, `image://sfsymbol/<name>/<pointSize>/<hex>` draws a real SF Symbol with `NSImage imageWithSystemSymbolName` (`app/gui/sfsymbol_mac.mm`). The draw matches Qt's `qt_mac_toQPixmap`: flip the bitmap context so y grows downward, then `drawInRect:respectFlipped:YES`, and center the glyph in a square. `CGContextDrawImage` after a single flip is upside down, which is why the earlier attempt stayed inverted. Other platforms, and unknown names, use a small geometric stand-in from `twilightDrawFallbackSymbol`.

Type uses `.AppleSystemUIFont` on Darwin, which is SF Pro on current macOS. The font is not bundled. Windows uses Segoe UI. Elsewhere the application font is left alone.

Glass is a translucent fill, a hairline, and a 1px sheen. This tree does not link Qt GraphicalEffects, so there is no backdrop blur.

Light and dark follow `SystemPalette`. Classic still forces the Material dark theme for its own controls. Twilight paints its own surfaces, so it does not retint Classic.

## Performance overlay

Settings → Advanced → **Classic performance overlay** draws the yellow stats on the video (`showPerformanceOverlay`, the same switch as Classic). H.264, HEVC, and AV1 include FEC in that overlay. PyroWave keeps its own stats line and does not gain FEC fields. The separate chips window that used to float over the video is gone, and so is the settings preview and toggle that only existed for it. End the stream with Ctrl+Alt+Shift+Q.

## Extending

Add pages under `app/gui/ui/v2/` and list them in `app/qml.qrc`. The shell is `ShellV2.qml`, loaded by a `Loader` in `app/gui/main.qml` only after Twilight is selected. Do not edit Classic screens for V2-only layout. Bind new settings to `StreamingPreferences` and call `save()` when the sheet closes.

## Known gaps

- SF Symbols are real only on macOS 11+. Other platforms get the geometric stand-ins.
- No backdrop blur.
- Gamepad grid navigation stays on Classic. Twilight is pointer-first, with preferences, New, and Escape shortcuts.
- Custom resolution, custom frame rate, and packet size stay in Classic. Twilight can show a custom size that was already saved, and offers 720p, 1080p, 1440p, 4K, and the current display mode.
- Language list in Twilight is the set Classic exposes, not every enum value that is commented out upstream.
- Loading the QML still needs a Qt build of the app. This VM does not treat a missing full Moonlight link as a V2 failure.

## Not in this pass

CoreHID, picture in picture, DualSense adaptive triggers, and network profiles. The macOS host-microphone switch is in Twilight Audio and uses the same preference as Classic. Session, CoreAudio spatial, and PyroWave decode paths are unchanged. Decoders fill the yellow performance overlay only while that switch is on.

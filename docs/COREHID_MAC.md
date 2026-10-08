# CoreHID mouse on Twilight (macOS)

Twilight’s game-mouse path on macOS is SDL relative mode. SDL hides the cursor, warps it back to the window, and sends the warp delta. That delta includes macOS pointer acceleration, and it dies at the screen edge when the warp fails. `LiSendMouseMoveAsMousePositionEvent` is the other workaround in `moonlight-common-c`: it keeps a **virtual client cursor** and sends absolute positions. Twilight does not call that function. This change reads the mouse and sends `LiSendMouseMoveEvent` instead, and only when you turn it on.

Windows and Linux are unchanged. The new code is compiled only in the `macx` qmake block (`app/streaming/input/corehid_mouse.cpp`, `corehid_mouse.mm`).

## What “CoreHID” means here

[CoreHID](https://developer.apple.com/documentation/corehid) is Apple’s Swift framework (macOS 15+) for `HIDDeviceManager` / `HIDDeviceClient`. It is not linked. This Qt/qmake client has no Swift shim.

The capture path uses the C API that framework wraps:

1. **IOHIDManager** (IOKit). Primary path. Matches Generic Desktop / Mouse (`usage page 0x01`, `usage 0x02`). Relative X/Y (`0x30` / `0x31`), wheel (`0x38`), AC Pan (`0x238` on the desktop or consumer page), and buttons 1–5 are decoded and sent to the host. The device is not seized.
2. **GCMouse** (Game Controller). Used only when IOHID cannot open (permission denied, no HID mouse, or `TWILIGHT_COREHID_BACKEND=gcmouse`). Deltas are in points and can still include pointer acceleration. Scroll stays on SDL for this backend, because GCMouse scroll axes are not HID notches.

If neither backend sees a mouse, capture fails and SDL relative mode runs as before. Trackpads are not HID mice, so a trackpad-only Mac keeps SDL.

Absolute / remote-desktop mouse mode (`--absolute-mouse`, Ctrl+Alt+Shift+M) does not start this path. Gamepad mouse emulation (right stick) is unchanged.

## Turn it on

Default is **off**, so an existing stream keeps SDL.

- Settings → Input Settings → **Use CoreHID raw mouse (macOS games)**. The checkbox is macOS-only. Quit and start the stream again after changing it.
- `moonlight stream <host> <app> --corehid-mouse` or `--no-corehid-mouse`.
- `TWILIGHT_COREHID=1` or `=0` overrides the checkbox for that process. `true` / `yes` / `on` and `false` / `no` / `off` work too.
- `TWILIGHT_COREHID_BACKEND=auto|iohid|gcmouse` (default `auto`).
- `TWILIGHT_COREHID_SCALE` multiplies X/Y only. Default `1`. Values outside `(0, 20]` are ignored. Wheel notches are not scaled.

Capture starts when the stream grabs the cursor, not at process launch. The log line is `CoreHID mouse capture started via IOHID` or `via GCMouse`. A failure logs `Falling back to SDL relative mouse` and the stream still grabs the cursor the old way.

While this path is active, SDL mouse-move and mouse-button events are not forwarded (they would double-send). SDL scroll is suppressed only after a relative HID wheel element has been seen. Magic Mouse gesture scroll often is not that element, so it still uses SDL.

Ctrl+Alt+Shift+Z releases capture and puts the cursor back on the pointer (`CGAssociateMouseAndMouseCursorPosition`).

## Permission

IOHID for a mouse needs **Input Monitoring**:

System Settings → Privacy & Security → Input Monitoring → enable the app (Moonlight, unless the bundle was renamed) → recapture the mouse (or restart the stream).

The first capture calls `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`. If the prompt is still pending, that session falls back to SDL. Grant access and capture again.

Signed desktop builds (`scripts/generate-dmg.sh` without `TWILIGHT_MAS=1`) already use Hardened Runtime. `app/deploy/macos/spatial-audio.entitlements` now includes `com.apple.security.device.input-monitoring` so that prompt is allowed. The App Sandbox key was already in that file. Sandbox can still refuse HID mice; the client then tries GCMouse and then SDL.

`CONFIG+=twilight-mas` does **not** get this entitlement. App Store submit is out of scope. A sandboxed MAS build should fall back to SDL rather than fail the stream.

Unsigned local builds (`qmake && make` with no codesign) rely on the TCC prompt only.

## Try it

On a Mac with a USB or Bluetooth mouse, Xcode that can build this tree, and a Sunshine host (Vibepollo/Sunshine or any current Sunshine):

```sh
qmake moonlight-qt.pro
make -j$(sysctl -n hw.logicalcpu)
# Settings checkbox, or:
TWILIGHT_COREHID=1 open app/Twilight.app
```

Or pass `--corehid-mouse` on a `stream` command. In a game (not remote-desktop mouse mode):

- Look around. Motion should keep going when the macOS cursor would have been pinned to the screen edge.
- Clicks, side buttons, and the wheel should match the SDL path, including “Reverse mouse scrolling direction” and “Swap left and right mouse buttons”.
- Pull the mouse out with Ctrl+Alt+Shift+Z. The cursor should move again.
- Toggle remote desktop with Ctrl+Alt+Shift+M. CoreHID stops; absolute mode is SDL.
- Set `TWILIGHT_COREHID=0` and confirm the log does not say CoreHID started.

There is no Mac in this change’s build environment, so the `.mm` file was not compiled here. The decoder, scale, and enable flags are covered by `tests/corehid_mouse_test.cpp` (below).

## Known limits

- Off unless you opt in.
- Trackpads, graphics tablets, and devices whose top-level usage is not Mouse stay on SDL. If a mouse is captured, SDL relative motion is suppressed for the whole grab, including the trackpad.
- IOHID counts are device units, not macOS points. Pointer Y from IOHID Desktop `0x31` and from GCMouse is positive upward, so it is negated once (`coreHidPointerDyForHost`) before scale. That matches SDL `yrel` and `LiSendMouseMoveEvent`, which are positive downward. X and the wheel are not negated. `TWILIGHT_COREHID_SCALE` is the sensitivity knob. The host still applies its own mouse settings.
- SDL can still deliver the wheel event that taught us the device has a wheel, so the first notch may be sent twice. Later notches are HID only.
- GCMouse can be accelerated. It is the fallback, not the raw path.
- Buttons past X2 (HID usage 6+) are tracked so they can be released, and they are not sent. Limelight has no code for them.
- Two mice at once: each button edge is sent. Releasing one mouse’s left button releases host left even if the other mouse is still held.
- No keyboard HID path. Keyboard grab stays SDL. Gamepads stay SDL Game Controller.
- Input Monitoring denied, or a sandboxed build, falls back. The stream should still start.
- Cursor disconnect uses `CGAssociateMouseAndMouseCursorPosition(false)` for the grab. If that call fails, deltas are still sent and the cursor can hit the screen edge. The log says so.

## Test the decoder without a Mac

The parser does not touch IOKit. From the repo root:

```sh
c++ -std=c++11 -Wall -Wextra -Werror \
    tests/corehid_mouse_test.cpp \
    app/streaming/input/corehid_mouse.cpp \
    -Iapp/streaming/input \
    -o /tmp/corehid_mouse_test
/tmp/corehid_mouse_test
```

If that `c++` is a Clang that cannot find `<cstdint>`, use `g++` with the same flags. This passed with `g++ -std=c++11` on the Linux agent that wrote the change.

## Attribution

- USB-IF HID Usage Tables: Generic Desktop (`0x01`), Button (`0x09`), Consumer (`0x0C`), and the usage numbers in `corehid_mouse.h`.
- Apple IOHIDManager, the C HID API documented in Technical Note TN2187 and the IOKit HID headers. CoreHID’s `HIDDeviceClient` is the Swift interface over this same stack ([Core HID](https://developer.apple.com/documentation/corehid)).
- Apple Game Controller `GCMouse` / `GCMouseInput` (macOS 11+), used only as the fallback.
- `IOHIDCheckAccess` / `IOHIDRequestAccess` (`kIOHIDRequestTypeListenEvent`) for the Input Monitoring prompt. The numeric values match `IOKit/hidsystem/IOHIDLib.h` and are resolved with `dlsym`.
- Button codes `BUTTON_LEFT` `0x01`, `BUTTON_MIDDLE` `0x02`, `BUTTON_RIGHT` `0x03`, `BUTTON_X1` `0x04`, `BUTTON_X2` `0x05`, and the note that `LiSendMouseMoveAsMousePositionEvent` keeps a virtual cursor, are from `moonlight-common-c` `Limelight.h` (andygrundman/moonlight-common-c). High-res scroll uses 120 per notch, same as the existing SDL path (`WHEEL_DELTA`).
- SDL relative mode (cursor warp via `CGWarpMouseCursorPosition` / `CGAssociateMouseAndMouseCursorPosition`) is the behavior this opt-in replaces. That code is SDL’s, not Twilight’s.

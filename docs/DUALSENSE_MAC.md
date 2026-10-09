# DualSense on Twilight for Mac

Pairing stays with macOS and SDL. Twilight does not implement Bluetooth or USB pairing. Connect the pad in System Settings (Bluetooth) or with a USB-C cable, grant the app Input Monitoring if macOS asks, and the existing SDL gamepad path picks it up.

Adaptive triggers and the on-stream pad overlay are separate from that pairing path.

## What the stream can do

| Path | What it is | Where it is implemented |
| --- | --- | --- |
| Face buttons, sticks, triggers, touchpad, gyro | Already sent to the host as a PlayStation-style pad | `app/streaming/input/gamepad.cpp` |
| Rumble motors | Host control packet, applied with `SDL_GameControllerRumble` | existing |
| Trigger rumble | Host packet `0x5500`. Vibration amplitude, not resistance | `SdlInputHandler::rumbleTriggers` |
| Adaptive triggers | Host packet `0x5503` (Sunshine extension) | `Session::clSetAdaptiveTriggers` |
| Local trigger preview | Cycles resistance on the Mac without a host packet | Ctrl+Alt+Shift+T |
| Gamepad overlay | Button highlight and stick position during the stream | Ctrl+Alt+Shift+G |

`0x5503` is already in the pinned `moonlight-common-c` commit (`7feb0a6`). Do not run `scripts/apply_adaptive_triggers_protocol.py` and do not roll the submodule back to `583754fc`.

The payload, after the control header, is 25 bytes:

- `uint16` controller number
- `uint8` event flags (`0x04` right trigger, `0x08` left trigger)
- `uint8` left mode, `uint8` right mode
- 10 parameter bytes per trigger

Those 11 bytes per trigger (mode + parameters) are the DualSense HID effect. Twilight copies them into the 47-byte state block and passes it to `SDL_GameControllerSendEffect` (SDL 2.0.16+). That is the same block SDL's HIDAPI PS5 driver writes into USB report `0x02` or Bluetooth report `0x31`.

The client forces `SDL_JOYSTICK_HIDAPI_PS5` and `SDL_JOYSTICK_HIDAPI_PS5_RUMBLE` before SDL opens joysticks. The macOS Game Controller framework can read a paired DualSense, and it cannot program trigger resistance. HIDAPI can.

If `SDL_GameControllerSendEffect` fails, the Mac build falls back to IOKit. It opens the Sony DualSense (`054C:0CE6`) or DualSense Edge (`054C:0DF2`) without seizing it, and writes one output report. A serial from `SDL_GameControllerGetSerial` selects the pad. With one DualSense and no serial, that pad is used. More than one pad and no serial match is skipped, so effects are not mirrored onto the wrong controller. The fallback logs `DualSense adaptive trigger via IOHID`.

## Host requirements

GFE / NVIDIA GameStream does not send adaptive-trigger packets.

Sunshine sends `0x5503` only when the **host** virtual pad produces DualSense trigger effects. That support landed with:

- `moonlight-common-c` adaptive-trigger callback (upstream PR 102, type `0x5503`)
- Sunshine's Linux input stack (inputtino DualSense emulation)

A Windows Sunshine host that emulates an Xbox pad through ViGEm does not have those curves to forward. XInput trigger rumble still arrives as `0x5500` and is played as trigger vibration, which is a different effect from resistance.

There is no client capability bit for adaptive triggers. Advertising `LI_CCAP_TRIGGER_RUMBLE` only tells the host that trigger *motors* can rumble. A Linux Sunshine build that emulates a DualSense will send `0x5503` when a game programs that virtual pad. Games that only speak XInput never generate the packet, on any host.

Until that host path is in the stack you are streaming from, use the local preview to prove the Mac pad.

## Local preview

During a stream:

- **Ctrl+Alt+Shift+T**, or **Select+L1+R1+A** on the pad

The cycle is: follow host, off, rigid resistance, resistance plus vibration, then follow host again. The effect bytes are the ones SDL ships in `testgamecontroller` (clear `0x05`, constant resistance `0x01`, vibration `0x06`).

While a preview step other than "follow host" is selected, host `0x5503` packets are remembered for the overlay and not written to the pad. Returning to "follow host" clears the local effect. The next host packet applies. Quitting the stream sends the clear effect so the triggers are not left rigid.

## Gamepad overlay

The overlay is an SDL text surface on the stream, bottom-right, using the same overlay path as the performance stats. It is not part of the V2 launcher UI.

- **Ctrl+Alt+Shift+G**, or **Select+L1+R1+Y**

It shows, for each connected pad:

- player index
- LT/RT as a value and a 10-step bar
- left and right stick position (`y+` is up, the same sign the stream already uses)
- pressed buttons in brackets

Button names are the Moonlight/SDL Xbox letters plus the DualSense face (`A/Cross` is the bottom face button). Shoulders, d-pad, stick clicks, Back, Start, PS, touchpad, and mic are included.

The last line is the trigger mode: `follow host (no host packet yet)`, `follow host (last L=0x.. R=0x..)`, or the local preview name. That line is how you tell a missing host packet from a pad that ignored the write.

Select+L1+R1+X still toggles the performance stats. Select+L1+R1+Y is the pad overlay. Start+Select+L1+R1 still quits.

## How to test on a Mac

1. Pair or cable the DualSense in macOS. Confirm Twilight lists it as a gamepad before you stream (the existing SDL path). Input Monitoring must be allowed for Twilight.
2. Start a stream. Press **Ctrl+Alt+Shift+G**. The bottom-right overlay should show `No gamepad` only if SDL did not open the pad; otherwise `P1` with live sticks and buttons. Pull each trigger and press Cross, L1, and the d-pad. Pressed names gain brackets. Sticks move off `0.00`.
3. Press **Ctrl+Alt+Shift+T** until the overlay says `rigid (local preview)`. Both triggers should resist through the pull. Cycle once more for vibration, then back through `off` to `follow host`. Triggers should release when you leave the preview.
4. Host packet, when you have a Linux Sunshine that emits `0x5503`: stay on `follow host` and do something in the game that sets a trigger effect. The overlay line changes from `no host packet yet` to `last L=0x.. R=0x..`, and the pad follows the game. A Windows ViGEm host will stay on `no host packet yet`; that is the host limitation, not a pairing failure.
5. Bluetooth and USB both use the same preview. If SDL's effect call fails, Console.app / the Twilight log should contain either `SDL_GameControllerSendEffect failed` or `DualSense adaptive trigger via IOHID USB` / `Bluetooth`.

Offline check. `7feb0a6` already defines `DS_EFFECT_PAYLOAD_SIZE` and the button flags, so the adaptive-trigger protocol script is not part of the build. The test includes `Limelight.h` from the submodule:

```sh
c++ -std=c++17 \
    -I moonlight-common-c/moonlight-common-c/src \
    -I app/streaming/input \
    tests/dualsense_effects_test.cpp \
    app/streaming/input/dualsense_effects.cpp \
    app/streaming/input/gamepad_overlay.cpp \
    -o /tmp/dualsense_effects_test
/tmp/dualsense_effects_test
```

The test checks the Sunshine payload layout, the SDL effect bytes, the Bluetooth CRC, and the overlay text. It does not need a DualSense.

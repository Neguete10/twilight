# Picture in Picture on Twilight (macOS)

Twilight's stream is one SDL window created on the main thread in
`Session::execInternal()` (`app/streaming/session.cpp`). On macOS that
window is an `NSWindow`. Frames are presented by whichever decoder the
session picked:

- VideoToolbox Metal (`vt_metal.mm`) for H.264 / HEVC / AV1
- VideoToolbox `AVSampleBufferDisplayLayer` (`vt_avsamplelayer.mm`) when
  Metal is unavailable
- PyroWave Metal or Vulkan (MoltenVK) when that codec is selected

Qt's window is the setup UI. It is not the video surface. Picture in
Picture does not restyle the Twilight shell. The Twilight performance
overlay follows this same SDL window, including into and out of the
mini player.

## Why this is not `AVPictureInPictureController`

`AVPictureInPictureController` plays an `AVPlayerLayer`, or on macOS 12
and later an `AVSampleBufferDisplayLayer` that the app enqueues into
itself. The Metal and Vulkan presenters do not produce `CMSampleBuffer`s.
Wiring system PiP would be a second video path next to the one SDL is
already drawing, and it would not cover PyroWave.

The slice here keeps that presenter and turns the same SDL window into a
floating mini player. Audio keeps the existing CoreAudio renderer. It is
not a second player owned by the window.

## How to try it

Build Twilight on a Mac the way this branch already builds (qmake on
`app/app.pro`, macOS kit). Start a stream, then either:

- Press **Ctrl+Alt+Shift+P** (Control+Option+Shift+P on a Mac keyboard).
  This is the same modifier chord as the other stream shortcuts
  (quit is Q, fullscreen is X). It is handled in `SdlInputHandler`
  before the key is sent to the host, so it still works while the
  keyboard is grabbed.
- Choose **Window → Enter Picture in Picture**. The item title switches
  to **Exit Picture in Picture** while the mini player is up. The menu
  item has no key equivalent, so it cannot fire twice with the hotkey.

The window moves to the bottom-right of the current display's work area
(menu bar and Dock excluded), 640 points wide for 16:9, with the stream
aspect preserved. Narrower displays still cap it at two fifths of the
usable width. Stage Manager's thumbnail strip is on the left, so the
player sits on the opposite corner. Drag the title bar to move it. The
title gains " - Picture in Picture".

Press the hotkey again, use the menu, or press **Ctrl+Alt+Shift+X** to
leave. X restores the window you entered from, including fullscreen. It
does not also toggle fullscreen; press X again after leaving if you
wanted that.

Click the video to capture the mouse, same as a windowed stream. Click
another app (or press Ctrl+Alt+Shift+Z) to release it. The player stays
on screen either way.

## Stage Manager

Stage Manager groups windows that are `NSWindowCollectionBehaviorManaged`
and sit at `NSNormalWindowLevel`. Entering PiP (`MacPipApplyFloating` in
`app/streaming/mac/pip_window.mm`) does four things:

- Raises the window to `NSFloatingWindowLevel`, which Stage Manager does
  not stage.
- Replaces the collection behavior. `Managed` is left off. `Transient`
  is also left off: that flag is panel behavior and AppKit hides
  transient windows when the app is inactive.
- Sets `CanJoinAllSpaces`, `FullScreenAuxiliary`, `Stationary`, and
  `ParticipatesInCycle`. The player is on every Space, including another
  app's fullscreen space, and Cmd-` can still reach it.
  `CanJoinAllSpaces` and `MoveToActiveSpace` are mutually exclusive;
  only the former is set.
- Sets `hidesOnDeactivate` to NO, and on focus loss calls
  `orderFrontRegardless` so the player stays visible without making
  Twilight the active app.

Leaving PiP restores the level and collection behavior captured before
the first raise. If SDL has recreated the `NSWindow` since then, the
window is put back to a normal document window (`Managed`,
`ParticipatesInCycle`, `FullScreenPrimary`, normal level).

SDL can drop that chrome on resize or deactivation. While PiP is active,
window events call `Session::reapplyPictureInPictureChrome()`.

## HUD while the window changes

The Twilight HUD stays a child of this SDL window during steady-state
picture-in-picture, including the 640-point frame. Entering, leaving, and
reapplying PiP chrome detach that child first
(`StreamHudStats::beginStreamWindowMutation`). AppKit is not given a
child while the parent changes level, collection behavior, fullscreen, or
frame. The HUD is attached again after those calls return.

While the HUD is a child it does not set its own window level or
collection behavior. A child inherits the parent. The previous HUD mask
used `IgnoresCycle`. PiP uses `ParticipatesInCycle` on the stream window,
and follow used to set the child's behavior on every sync, including
across that parent change.

The v6.1.0 crash (binary UUID `10BFCCE9-43FD-37A7-85B5-6B8F15DD1145`,
load address `0x100ed8000`) is AudioDec fetching a non-executable
address. The faulting program counter is `0x7b14d6c300`, which is the
value loaded from `AudioCallbacks.decodeAndPlaySample`
(`decodeInputData` + 436, return into `AudioDecoderThreadProc` + 72,
`ThreadProc` + 32). That slot is copied in `LiStartConnection` and
Twilight does not store it again. The audio renderer and its ring buffer
are not on this stack. Entering picture-in-picture is when the stream
window's level, collection behavior, fullscreen, and frame change while
the HUD is still attached.

AudioDec now calls `TwilightAudioDecodeAndPlaySample` directly. qmake
applies `scripts/apply_audio_decode_direct.py` to the pinned
moonlight-common-c tree. The call target is in the instruction stream, so
a later write into that callback global is not fetched as code.

## Build and test

The Cocoa file is in the existing `macx` sources in `app/app.pro`. A
Linux build does not compile it.

Placement math is pure and covered by `tests/pip_frame_test.cpp`:

```sh
g++ -std=c++11 -Wall -Wextra -Werror -I app tests/pip_frame_test.cpp -o /tmp/pip_frame_test
/tmp/pip_frame_test
```

That test passed on the Linux agent that wrote this change (`picture-in-picture frame tests passed`). It does not open a window. The Cocoa path was not compiled here: this machine has no Apple SDK, so the menu, window level, and Stage Manager behavior need a Mac pass. `c++` on that agent is clang without libstdc++ headers; `g++` is the compiler that ran the test.

On a Mac, after a stream is up:

1. Ctrl+Alt+Shift+P from a windowed stream. The player should shrink to
   the bottom-right and stay up when you click another app.
2. Turn Stage Manager on. The player should stay out of the thumbnail
   strip and remain visible while you switch sets.
3. Ctrl+Alt+Shift+P again. The previous size and position should return.
4. From fullscreen, enter PiP, then leave. The stream should return to
   fullscreen. The first second and a half may correct a display-sized
   frame if the Space animation finishes late (`m_PipSnapBackUntil`).
5. Window menu item title should follow the current state, and the item
   should be gone after the stream ends.

## Limitations

- Not system Picture in Picture. There is no `AVPictureInPictureController`,
  no separate OS PiP window, and no playback chrome. Closing the window
  still ends the stream.
- The mini player is the stream window, so there is only one of it. It
  is not a second view of the same stream.
- Entering from fullscreen tears down the video decoder first, same as
  the existing fullscreen toggle, because of the WindowServer deadlock
  with `AVSampleBufferDisplayLayer` (moonlight-qt #973). Expect a short
  hitch and a new IDR.
- macOS animates fullscreen Spaces. PiP corrects a display-sized window
  for 1.5 seconds after that transition. Resizing the mini player after
  that window is left alone.
- Restoring a window that was fullscreen uses the session's normal
  windowed rect (`getWindowDimensions`) as the size SDL remembers, then
  re-enters fullscreen. A user-resized windowed rect is only saved when
  PiP was entered from windowed mode.
- The Window menu item is added to `NSApp.windowsMenu`, or a Window menu
  is created if Qt did not publish one. Localized menu titles are not
  searched; the created menu is English.
- Minimum size while PiP is active is 160×90. It is cleared on exit.
- App Store submission is out of scope. Nothing here adds an entitlement.

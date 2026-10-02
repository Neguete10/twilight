#pragma once

#include <SDL.h>

// Mac-only chrome for stream picture-in-picture.
//
// The stream is one SDL window. Video is presented by VideoToolbox Metal,
// the AVSampleBufferDisplayLayer fallback, or PyroWave (Metal or Vulkan).
// AVPictureInPictureController is not used: it drives an AVPlayerLayer, or
// (macOS 12+) an AVSampleBufferDisplayLayer that this process would have to
// feed itself. The Metal and Vulkan presenters never enqueue sample buffers,
// so a system PiP controller would be a second video path. This helper keeps
// the existing presenter and changes the NSWindow so the same frames float
// as a mini player.
//
// Stage Manager only groups windows with NSWindowCollectionBehaviorManaged
// at NSNormalWindowLevel. The floating behavior below omits Managed, raises
// the window to NSFloatingWindowLevel, and joins every Space (including
// another app's fullscreen space) without hiding when Twilight is inactive.

// `toggle` is invoked on the main thread from the Window menu. It may be
// null. Pass the same function again to refresh it; the item is not duplicated.
void MacPipInstallMenu(void (*toggle)());
void MacPipRemoveMenu();
void MacPipUpdateMenu(bool active);

// The first call for a given NSWindow stores that window's level, collection
// behavior, and hidesOnDeactivate. Later calls re-apply the floating
// behavior without overwriting the saved values. `orderFront` raises the
// window without making Twilight the active app.
void MacPipApplyFloating(SDL_Window* window, bool orderFront);

// Restores the chrome saved by MacPipApplyFloating when the NSWindow is
// still the one that was saved. Otherwise the level is returned to normal.
void MacPipClearFloating(SDL_Window* window);

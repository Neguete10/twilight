#include "streamhudplace.h"

#include <QWindow>

#include <SDL.h>
#include <SDL_syswm.h>

#import <Cocoa/Cocoa.h>

#include <cmath>

// Manual reference counting, same as the other macOS sources.

// The build that showed the chips (before picture-in-picture follow) did
// three things on every raise: Qt show/raise, the fullscreen-space
// collection behavior, and orderFrontRegardless. It never called
// setFrameOrigin. Moving the NSWindow directly, then letting Qt write its
// own geometry back, parked the chips off the visible space. Position is
// now the SDL window position, which uses the same top-left coordinates as
// QWindow, and the HUD NSWindow is a child of the stream window so it stays
// in that window's Space and above the video.

namespace {

bool s_LoggedPlace = false;

NSWindow* windowFromSdl(SDL_Window* window)
{
    if (window == nullptr) {
        return nil;
    }

    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) {
        return nil;
    }
    return info.info.cocoa.window;
}

NSWindow* nativeWindowFor(QWindow* window)
{
    if (window == nullptr) {
        return nil;
    }
    NSView* view = reinterpret_cast<NSView*>(window->winId());
    return view != nil ? view.window : nil;
}

void applyHudChrome(NSWindow* nativeWindow, bool setLevel)
{
    // Same mask as the raise that previously drew the chips over fullscreen.
    const NSWindowCollectionBehavior behavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorStationary |
        NSWindowCollectionBehaviorIgnoresCycle;

    [nativeWindow setOpaque:NO];
    [nativeWindow setBackgroundColor:[NSColor clearColor]];
    [nativeWindow setHasShadow:NO];
    [nativeWindow setHidesOnDeactivate:NO];
    // Changing the level of a child window detaches it from the stream.
    if (setLevel) {
        [nativeWindow setLevel:NSFloatingWindowLevel];
    }
    [nativeWindow setCollectionBehavior:behavior];
}

} // namespace

void twilightHudDetach(QWindow* window)
{
    if (window == nullptr || window->handle() == nullptr) {
        return;
    }

    NSWindow* nativeWindow = nativeWindowFor(window);
    if (nativeWindow != nil && nativeWindow.parentWindow != nil) {
        [nativeWindow.parentWindow removeChildWindow:nativeWindow];
    }
    s_LoggedPlace = false;
}

void twilightHudSync(QWindow* window, void* sdlWindow, bool raise)
{
    (void)raise;
    if (window == nullptr) {
        return;
    }

    SDL_Window* sdl = static_cast<SDL_Window*>(sdlWindow);
    NSWindow* streamWindow = windowFromSdl(sdl);
    if (streamWindow != nil) {
        int streamX = 0;
        int streamY = 0;
        int streamW = 0;
        int streamH = 0;
        SDL_GetWindowPosition(sdl, &streamX, &streamY);
        SDL_GetWindowSize(sdl, &streamW, &streamH);
        const TwilightHudPlace place = twilightPlaceHudTopLeft(streamX,
                                                               streamY,
                                                               streamW,
                                                               streamH,
                                                               window->width(),
                                                               window->height());
        if (place.ok) {
            const int hudX = (int)std::lround(place.x);
            const int hudY = (int)std::lround(place.y);
            if (window->x() != hudX || window->y() != hudY) {
                window->setPosition(hudX, hudY);
            }
            if (!s_LoggedPlace) {
                s_LoggedPlace = true;
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                            "Twilight HUD on stream at %d,%d size %.0fx%.0f (stream %d,%d %dx%d)",
                            hudX,
                            hudY,
                            window->width(),
                            window->height(),
                            streamX,
                            streamY,
                            streamW,
                            streamH);
            }
        }
    }

    if (!window->isVisible()) {
        window->show();
    }
    window->raise();

    NSWindow* nativeWindow = nativeWindowFor(window);
    if (nativeWindow == nil) {
        return;
    }

    const bool alreadyChild = streamWindow != nil && nativeWindow.parentWindow == streamWindow;
    applyHudChrome(nativeWindow, !alreadyChild);

    if (streamWindow != nil && !alreadyChild) {
        if (nativeWindow.parentWindow != nil) {
            [nativeWindow.parentWindow removeChildWindow:nativeWindow];
        }
        // Child of the SDL window: same Space as fullscreen or PiP, drawn
        // above the video, and moved by AppKit when that window moves.
        [streamWindow addChildWindow:nativeWindow ordered:NSWindowAbove];
    }

    [nativeWindow orderFrontRegardless];
    window->requestUpdate();
}

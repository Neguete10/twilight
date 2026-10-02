#include "streamhudplace.h"

#include <QWindow>

#include <SDL.h>
#include <SDL_syswm.h>

#import <Cocoa/Cocoa.h>

#include <cmath>

// Manual reference counting, same as the other macOS sources.

// The stream loop owns the main thread and then opens an SDL window. A
// Qt.Tool / NSPanel hides when Twilight deactivates, and a normal window
// sits under a fullscreen space. Keep the HUD as a non-activating floating
// window on the stream window's frame, including picture-in-picture.
//
// AppKit and Qt both clear FullScreenAuxiliary when the frame moves.
// Applying that behavior only once leaves the chips on the desktop space,
// behind the fullscreen stream, for the rest of the session.

namespace {

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

void syncQtPosition(QWindow* window, NSPoint origin)
{
    NSArray<NSScreen*>* screens = [NSScreen screens];
    if (screens.count == 0) {
        return;
    }

    // Cocoa's origin is the bottom-left of the primary screen. Qt's is the
    // top-left. Writing the same point into the QWindow stops the next
    // processEvents() from dragging the chips back to (0, 0).
    const CGFloat primaryHeight = NSMaxY([screens[0] frame]);
    const int qtX = (int)std::lround(origin.x);
    const int qtY = (int)std::lround(primaryHeight - (origin.y + window->height()));
    if (window->x() != qtX || window->y() != qtY) {
        window->setPosition(qtX, qtY);
    }
}

} // namespace

void twilightHudSync(QWindow* window, void* sdlWindow, bool raise)
{
    if (window == nullptr) {
        return;
    }

    if (!window->isVisible()) {
        window->show();
    }

    NSView* view = reinterpret_cast<NSView*>(window->winId());
    NSWindow* nativeWindow = view.window;
    if (nativeWindow == nil) {
        return;
    }

    NSWindow* streamWindow = windowFromSdl(static_cast<SDL_Window*>(sdlWindow));
    if (streamWindow != nil) {
        const NSRect streamFrame = [streamWindow frame];
        const TwilightHudPlace place = twilightPlaceHud(streamFrame.origin.x,
                                                        streamFrame.origin.y,
                                                        streamFrame.size.width,
                                                        streamFrame.size.height,
                                                        window->width(),
                                                        window->height());
        if (place.ok) {
            const NSPoint origin = NSMakePoint(std::round(place.x), std::round(place.y));
            if (!NSEqualPoints([nativeWindow frame].origin, origin)) {
                [nativeWindow setFrameOrigin:origin];
            }
            syncQtPosition(window, origin);
            if (!NSEqualPoints([nativeWindow frame].origin, origin)) {
                [nativeWindow setFrameOrigin:origin];
            }
        }
    }

    NSInteger level = NSFloatingWindowLevel;
    if (streamWindow != nil) {
        const NSInteger streamLevel = [streamWindow level];
        if (streamLevel > level) {
            level = streamLevel;
        }
    }

    const NSWindowCollectionBehavior behavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorStationary |
        NSWindowCollectionBehaviorIgnoresCycle;

    [nativeWindow setLevel:level];
    [nativeWindow setHidesOnDeactivate:NO];
    // Checked after the move. A missing FullScreenAuxiliary bit means the
    // chips are on the desktop space, so this raise is required. Reapplying
    // the other bits does not raise; ordering front on every move flickers.
    const NSWindowCollectionBehavior current = [nativeWindow collectionBehavior];
    if ((current & behavior) != behavior) {
        [nativeWindow setCollectionBehavior:behavior];
        if ((current & NSWindowCollectionBehaviorFullScreenAuxiliary) == 0) {
            raise = true;
        }
    }

    if (raise) {
        [nativeWindow orderFrontRegardless];
    }
}

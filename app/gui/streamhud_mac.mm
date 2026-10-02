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

namespace {

bool s_HudChromeReady = false;
NSInteger s_AppliedLevel = 0;
QWindow* s_ChromeWindow = nullptr;

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

    if (s_ChromeWindow != window) {
        s_HudChromeReady = false;
        s_ChromeWindow = window;
    }

    if (!s_HudChromeReady) {
        const NSWindowCollectionBehavior behavior =
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary |
            NSWindowCollectionBehaviorStationary |
            NSWindowCollectionBehaviorIgnoresCycle;

        [nativeWindow setLevel:NSFloatingWindowLevel];
        [nativeWindow setHidesOnDeactivate:NO];
        [nativeWindow setCollectionBehavior:behavior];
        s_AppliedLevel = NSFloatingWindowLevel;
        s_HudChromeReady = true;
        raise = true;
    }

    NSWindow* streamWindow = windowFromSdl(static_cast<SDL_Window*>(sdlWindow));
    if (streamWindow != nil) {
        NSInteger level = [streamWindow level];
        if (level < NSFloatingWindowLevel) {
            level = NSFloatingWindowLevel;
        }
        if (level != s_AppliedLevel) {
            [nativeWindow setLevel:level];
            s_AppliedLevel = level;
        }

        const NSRect streamFrame = [streamWindow frame];
        const CGFloat hudW = window->width();
        const CGFloat hudH = window->height();
        // A short window is the mini player. Sit closer to its top edge.
        const CGFloat margin = streamFrame.size.height < 520.0 ? 8.0 : 28.0;
        CGFloat x = NSMidX(streamFrame) - hudW * 0.5;
        CGFloat y = NSMaxY(streamFrame) - hudH - margin;
        const CGFloat minX = NSMinX(streamFrame);
        const CGFloat maxX = NSMaxX(streamFrame) - hudW;
        if (x < minX) {
            x = minX;
        }
        if (x > maxX) {
            x = maxX;
        }
        const CGFloat minY = NSMinY(streamFrame);
        const CGFloat maxY = NSMaxY(streamFrame) - hudH;
        if (y < minY) {
            y = minY;
        }
        if (y > maxY) {
            y = maxY;
        }

        const NSPoint origin = NSMakePoint(std::round(x), std::round(y));
        if (!NSEqualPoints([nativeWindow frame].origin, origin)) {
            [nativeWindow setFrameOrigin:origin];
        }
    }

    if (raise) {
        [nativeWindow orderFrontRegardless];
    }
}

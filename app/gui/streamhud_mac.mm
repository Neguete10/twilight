#include <QWindow>

#import <Cocoa/Cocoa.h>

// Manual reference counting, same as the other macOS sources.

// The stream loop owns the main thread and then opens an SDL fullscreen
// window. A Qt.Tool / NSPanel hides when Twilight deactivates, and a normal
// window sits under that fullscreen space. Raise the HUD as a non-activating
// floating window that is allowed onto fullscreen spaces.
void twilightHudOrderFront(QWindow* window)
{
    if (window == nullptr) {
        return;
    }

    window->show();
    window->raise();

    NSView* view = reinterpret_cast<NSView*>(window->winId());
    NSWindow* nativeWindow = view.window;
    if (nativeWindow == nil) {
        return;
    }

    const NSWindowCollectionBehavior behavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorStationary |
        NSWindowCollectionBehaviorIgnoresCycle;

    [nativeWindow setLevel:NSFloatingWindowLevel];
    [nativeWindow setHidesOnDeactivate:NO];
    [nativeWindow setCollectionBehavior:behavior];
    [nativeWindow orderFrontRegardless];
}

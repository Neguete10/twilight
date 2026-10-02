#include "streaming/mac/pip_window.h"

#include <SDL_syswm.h>

#import <Cocoa/Cocoa.h>

// Manual reference counting, same as the other macOS renderer sources.

static void (*s_Toggle)() = nullptr;
static bool s_CreatedWindowMenu = false;

@interface TwilightPipMenuTarget : NSObject
- (void)togglePictureInPicture:(id)sender;
@end

@implementation TwilightPipMenuTarget

- (void)togglePictureInPicture:(id)sender
{
    (void)sender;
    if (s_Toggle != nullptr) {
        s_Toggle();
    }
}

@end

static TwilightPipMenuTarget* s_Target = nil;
static NSMenuItem* s_PipItem = nil;
static NSMenuItem* s_Separator = nil;
static NSMenuItem* s_WindowMenuItem = nil;

struct SavedWindowChrome {
    NSWindow* window;
    NSWindowLevel level;
    NSWindowCollectionBehavior behavior;
    BOOL hidesOnDeactivate;
    bool valid;
};

static SavedWindowChrome s_Saved = {};

static NSWindow* windowFromSdl(SDL_Window* window)
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

void MacPipInstallMenu(void (*toggle)())
{
    s_Toggle = toggle;
    if (s_PipItem != nil) {
        return;
    }

    @autoreleasepool {
        NSMenu* mainMenu = [NSApp mainMenu];
        if (mainMenu == nil) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Picture-in-picture menu was not installed (no main menu). "
                        "Ctrl+Alt+Shift+P still toggles it.");
            return;
        }

        NSMenu* windowMenu = [NSApp windowsMenu];
        if (windowMenu == nil) {
            windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
            s_WindowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window"
                                                          action:nil
                                                   keyEquivalent:@""];
            [s_WindowMenuItem setSubmenu:windowMenu];
            [windowMenu release];
            [mainMenu addItem:s_WindowMenuItem];
            // The item is already in the menu bar, so this assigns the
            // windows menu without inserting a second copy.
            [NSApp setWindowsMenu:[s_WindowMenuItem submenu]];
            s_CreatedWindowMenu = true;
            windowMenu = [s_WindowMenuItem submenu];
        }

        s_Target = [[TwilightPipMenuTarget alloc] init];
        s_PipItem = [[NSMenuItem alloc] initWithTitle:@"Enter Picture in Picture"
                                               action:@selector(togglePictureInPicture:)
                                        keyEquivalent:@""];
        // NSMenuItem does not retain its target.
        [s_PipItem setTarget:s_Target];

        if ([windowMenu numberOfItems] > 0) {
            s_Separator = [[NSMenuItem separatorItem] retain];
            [windowMenu addItem:s_Separator];
        }
        [windowMenu addItem:s_PipItem];

        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Picture-in-picture: Window menu, or Ctrl+Alt+Shift+P while streaming");
    }
}

void MacPipRemoveMenu()
{
    s_Toggle = nullptr;

    if (s_PipItem != nil) {
        NSMenu* menu = [s_PipItem menu];
        if (menu != nil) {
            [menu removeItem:s_PipItem];
        }
        [s_PipItem release];
        s_PipItem = nil;
    }
    if (s_Separator != nil) {
        NSMenu* menu = [s_Separator menu];
        if (menu != nil) {
            [menu removeItem:s_Separator];
        }
        [s_Separator release];
        s_Separator = nil;
    }
    if (s_CreatedWindowMenu && s_WindowMenuItem != nil) {
        if ([NSApp windowsMenu] == [s_WindowMenuItem submenu]) {
            [NSApp setWindowsMenu:nil];
        }
        NSMenu* mainMenu = [NSApp mainMenu];
        if (mainMenu != nil && [s_WindowMenuItem menu] == mainMenu) {
            [mainMenu removeItem:s_WindowMenuItem];
        }
        [s_WindowMenuItem release];
        s_WindowMenuItem = nil;
        s_CreatedWindowMenu = false;
    }
    if (s_Target != nil) {
        [s_Target release];
        s_Target = nil;
    }
}

void MacPipUpdateMenu(bool active)
{
    if (s_PipItem == nil) {
        return;
    }
    [s_PipItem setTitle:(active ? @"Exit Picture in Picture" : @"Enter Picture in Picture")];
}

void MacPipApplyFloating(SDL_Window* sdlWindow, bool orderFront)
{
    NSWindow* window = windowFromSdl(sdlWindow);
    if (window == nil) {
        if (!s_Saved.valid) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Picture-in-picture could not read the Cocoa window: %s",
                        SDL_GetError());
        }
        return;
    }

    // Snapshot once, before the first floating change. A later NSWindow
    // (decoder reset recreates it) must not overwrite that snapshot with
    // the floating level, or exit would restore "always on top".
    if (!s_Saved.valid) {
        s_Saved.window = window;
        s_Saved.level = [window level];
        s_Saved.behavior = [window collectionBehavior];
        s_Saved.hidesOnDeactivate = [window hidesOnDeactivate];
        s_Saved.valid = true;
    }

    // Omit NSWindowCollectionBehaviorManaged so Stage Manager does not
    // pull the stream into the active set. Omit Transient: that flag is
    // panel behavior and AppKit hides transient windows when the app is
    // inactive, which is the opposite of a mini player.
    //
    // CanJoinAllSpaces and MoveToActiveSpace are mutually exclusive.
    // CanJoinAllSpaces keeps one window on every Space. FullScreenAuxiliary
    // lets it draw over another app's fullscreen space. Stationary keeps
    // it from sliding away during a Space transition. ParticipatesInCycle
    // leaves Cmd-` able to reach it.
    const NSWindowCollectionBehavior pipBehavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorStationary |
        NSWindowCollectionBehaviorParticipatesInCycle;

    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:pipBehavior];
    [window setHidesOnDeactivate:NO];

    if (orderFront) {
        // Visible above the app the user just focused, without activating
        // Twilight or stealing key focus from that app.
        [window orderFrontRegardless];
    }
}

void MacPipClearFloating(SDL_Window* sdlWindow)
{
    NSWindow* window = windowFromSdl(sdlWindow);
    if (window != nil && s_Saved.valid && s_Saved.window == window) {
        [window setLevel:s_Saved.level];
        [window setCollectionBehavior:s_Saved.behavior];
        [window setHidesOnDeactivate:s_Saved.hidesOnDeactivate];
    }
    else if (window != nil) {
        // The NSWindow was recreated after the snapshot, or picture-in-picture
        // was entered from fullscreen before the windowed chrome existed.
        // SDL's stream window is a normal document window outside of PiP.
        [window setLevel:NSNormalWindowLevel];
        [window setHidesOnDeactivate:NO];
        [window setCollectionBehavior:
            NSWindowCollectionBehaviorManaged |
            NSWindowCollectionBehaviorParticipatesInCycle |
            NSWindowCollectionBehaviorFullScreenPrimary];
    }

    s_Saved.window = nil;
    s_Saved.level = NSNormalWindowLevel;
    s_Saved.behavior = NSWindowCollectionBehaviorDefault;
    s_Saved.hidesOnDeactivate = NO;
    s_Saved.valid = false;
}

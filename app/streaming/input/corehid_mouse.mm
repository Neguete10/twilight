#include "corehid_mouse.h"

#include <SDL.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hid/IOHIDManager.h>
#include <dlfcn.h>

#import <GameController/GameController.h>

struct CoreHidMouseCapture {
    CoreHidMotionFn onMotion;
    CoreHidButtonFn onButtons;
    void* context;
    float scale;
    CoreHidBackendRequest requestedBackend;
    CoreHidBackendRequest activeBackend;
    CoreHidMouseDecoder decoder;
    std::atomic<bool> active;
    std::atomic<bool> threadRun;
    std::atomic<bool> ownsWheel;
    std::thread thread;
    // Published by the IOHID thread, stopped from the main thread.
    std::atomic<uintptr_t> threadLoop;
    IOHIDManagerRef manager;
    int hidDeviceCount;
    bool cursorDisassociated;
    char lastError[256];
    id connectObserver;
    id disconnectObserver;

    CoreHidMouseCapture()
        : onMotion(nullptr),
          onButtons(nullptr),
          context(nullptr),
          scale(1.0f),
          requestedBackend(CoreHidBackendRequest::Auto),
          activeBackend(CoreHidBackendRequest::Auto),
          active(false),
          threadRun(false),
          ownsWheel(false),
          threadLoop(0),
          manager(nullptr),
          hidDeviceCount(0),
          cursorDisassociated(false),
          connectObserver(nil),
          disconnectObserver(nil)
    {
        lastError[0] = '\0';
    }
};

// IOHIDCheckAccess / IOHIDRequestAccess live in IOKit/hidsystem/IOHIDLib.h
// (macOS 10.15+). Twilight's deployment target is 11.0, but the symbols are
// resolved at runtime so a build against headers that omit them still links.
// Values match that header: listen request = 1, granted = 0, denied = 1,
// unknown = 2.

namespace {

constexpr int kHidRequestListenEvent = 1;
constexpr int kHidAccessGranted = 0;
[[maybe_unused]] constexpr int kHidAccessDenied = 1; // IOHIDAccessType denied; kept for the enum map

void setError(CoreHidMouseCapture* capture, const char* text)
{
    std::snprintf(capture->lastError, sizeof(capture->lastError), "%s", text == nullptr ? "" : text);
}

int hidListenAccess()
{
    using CheckFn = int (*)(int);
    CheckFn check = reinterpret_cast<CheckFn>(dlsym(RTLD_DEFAULT, "IOHIDCheckAccess"));
    if (check == nullptr) {
        return kHidAccessGranted;
    }
    return check(kHidRequestListenEvent);
}

bool hidRequestListen()
{
    using RequestFn = bool (*)(int);
    RequestFn request = reinterpret_cast<RequestFn>(dlsym(RTLD_DEFAULT, "IOHIDRequestAccess"));
    if (request == nullptr) {
        return true;
    }
    return request(kHidRequestListenEvent);
}

void disassociateCursor(CoreHidMouseCapture* capture)
{
    const CGError err = CGAssociateMouseAndMouseCursorPosition(false);
    capture->cursorDisassociated = (err == kCGErrorSuccess);
    if (!capture->cursorDisassociated) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "CoreHID mouse: the pointer stayed tied to the cursor (%d). Raw deltas are still sent, but motion can stop at the screen edge.",
                    static_cast<int>(err));
    }
}

void reassociateCursor(CoreHidMouseCapture* capture)
{
    if (!capture->cursorDisassociated) {
        return;
    }
    CGAssociateMouseAndMouseCursorPosition(true);
    capture->cursorDisassociated = false;
}

void emitButtonReleases(CoreHidMouseCapture* capture)
{
    CoreHidButtonUpdate releases[16];
    const int count = capture->decoder.releaseAll(releases, 16);
    if (capture->onButtons == nullptr) {
        return;
    }
    for (int i = 0; i < count; i++) {
        capture->onButtons(releases[i], capture->context);
    }
}

void deliverDecoded(CoreHidMouseCapture* capture, const CoreHidDecodedUpdate& decoded)
{
    if (decoded.hasMotion && capture->onMotion != nullptr) {
        CoreHidMouseDelta delta = decoded.motion;
        if (delta.motion) {
            delta.dx = coreHidApplyScale(delta.dx, capture->scale);
            delta.dy = coreHidApplyScale(delta.dy, capture->scale);
            delta.motion = delta.dx != 0 || delta.dy != 0;
        }
        if (delta.motion || delta.wheelChanged || delta.hWheelChanged) {
            capture->onMotion(delta, capture->context);
        }
    }
    if (capture->decoder.sawWheel()) {
        capture->ownsWheel.store(true);
    }
    if (decoded.hasButtons && decoded.buttons.changed && capture->onButtons != nullptr) {
        capture->onButtons(decoded.buttons, capture->context);
    }
}

void inputValueCallback(void* context, IOReturn result, void* sender, IOHIDValueRef value)
{
    (void)sender;
    if (result != kIOReturnSuccess || context == nullptr || value == nullptr) {
        return;
    }
    CoreHidMouseCapture* capture = static_cast<CoreHidMouseCapture*>(context);
    if (!capture->threadRun.load()) {
        return;
    }

    IOHIDElementRef element = IOHIDValueGetElement(value);
    if (element == nullptr) {
        return;
    }
    IOHIDDeviceRef device = IOHIDElementGetDevice(element);

    CoreHidElementUpdate update = {};
    update.deviceId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(device));
    update.usagePage = IOHIDElementGetUsagePage(element);
    update.usage = IOHIDElementGetUsage(element);
    update.value = static_cast<int32_t>(IOHIDValueGetIntegerValue(value));
    update.logicalMin = static_cast<int32_t>(IOHIDElementGetLogicalMin(element));
    update.logicalMax = static_cast<int32_t>(IOHIDElementGetLogicalMax(element));
    update.relative = IOHIDElementIsRelative(element);

    deliverDecoded(capture, capture->decoder.apply(update));
}

void removalCallback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device)
{
    (void)result;
    (void)sender;
    if (context == nullptr) {
        return;
    }
    CoreHidMouseCapture* capture = static_cast<CoreHidMouseCapture*>(context);
    const uint64_t deviceId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(device));
    CoreHidButtonUpdate released;
    if (capture->decoder.releaseDevice(deviceId, &released, 1) == 1 && capture->onButtons != nullptr) {
        capture->onButtons(released, capture->context);
    }
}

void closeManager(CoreHidMouseCapture* capture, bool scheduled, bool opened)
{
    if (capture->manager == nullptr) {
        return;
    }
    if (scheduled) {
        IOHIDManagerUnscheduleFromRunLoop(capture->manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    }
    if (opened) {
        IOHIDManagerClose(capture->manager, kIOHIDOptionsTypeNone);
    }
    CFRelease(capture->manager);
    capture->manager = nullptr;
}

struct IohidStart {
    std::mutex mu;
    std::condition_variable cv;
    bool done;
    bool ok;
    int devices;
};

void iohidThreadMain(CoreHidMouseCapture* capture, IohidStart* start)
{
    const CFRunLoopRef loop = CFRunLoopGetCurrent();
    capture->threadLoop.store(reinterpret_cast<uintptr_t>(loop));

    int deviceCount = 0;
    bool scheduled = false;
    bool opened = false;
    capture->manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (capture->manager != nullptr) {
        const int page = static_cast<int>(CoreHidUsage::PageGenericDesktop);
        const int usage = static_cast<int>(CoreHidUsage::DesktopMouse);
        CFMutableDictionaryRef match = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                                 &kCFTypeDictionaryKeyCallBacks,
                                                                 &kCFTypeDictionaryValueCallBacks);
        CFNumberRef pageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
        CFNumberRef usageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
        if (match != nullptr && pageNumber != nullptr && usageNumber != nullptr) {
            CFDictionarySetValue(match, CFSTR(kIOHIDDeviceUsagePageKey), pageNumber);
            CFDictionarySetValue(match, CFSTR(kIOHIDDeviceUsageKey), usageNumber);
            IOHIDManagerSetDeviceMatching(capture->manager, match);
            IOHIDManagerRegisterInputValueCallback(capture->manager, inputValueCallback, capture);
            IOHIDManagerRegisterDeviceRemovalCallback(capture->manager, removalCallback, capture);
            IOHIDManagerScheduleWithRunLoop(capture->manager, loop, kCFRunLoopDefaultMode);
            scheduled = true;
            const IOReturn openedResult = IOHIDManagerOpen(capture->manager, kIOHIDOptionsTypeNone);
            opened = openedResult == kIOReturnSuccess;
            if (!opened) {
                std::snprintf(capture->lastError, sizeof(capture->lastError),
                              "IOHIDManagerOpen failed (%d)", static_cast<int>(openedResult));
            }
        }
        if (pageNumber != nullptr) {
            CFRelease(pageNumber);
        }
        if (usageNumber != nullptr) {
            CFRelease(usageNumber);
        }
        if (match != nullptr) {
            CFRelease(match);
        }
    }
    else {
        setError(capture, "IOHIDManagerCreate failed");
    }

    if (opened) {
        CFSetRef devices = IOHIDManagerCopyDevices(capture->manager);
        if (devices != nullptr) {
            deviceCount = static_cast<int>(CFSetGetCount(devices));
            CFRelease(devices);
        }
        if (deviceCount == 0) {
            setError(capture, "IOHID found no mouse devices. Trackpads stay on SDL.");
            closeManager(capture, scheduled, opened);
            scheduled = false;
            opened = false;
        }
    }
    else {
        closeManager(capture, scheduled, opened);
        scheduled = false;
        opened = false;
    }

    if (!capture->threadRun.load() && capture->manager != nullptr) {
        closeManager(capture, scheduled, opened);
        scheduled = false;
        opened = false;
    }

    {
        std::lock_guard<std::mutex> lock(start->mu);
        start->devices = deviceCount;
        start->ok = opened;
        start->done = true;
    }
    start->cv.notify_one();

    if (!opened) {
        capture->threadLoop.store(0);
        return;
    }

    while (capture->threadRun.load()) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }

    closeManager(capture, true, true);
    capture->threadLoop.store(0);
}

bool startIohid(CoreHidMouseCapture* capture)
{
    const int access = hidListenAccess();
    if (access != kHidAccessGranted) {
        if (!hidRequestListen()) {
            setError(capture,
                     "Input Monitoring permission is not granted. Enable this app in System Settings > Privacy & Security > Input Monitoring, then recapture the mouse.");
            return false;
        }
    }

    capture->threadRun.store(true);
    IohidStart start = {};
    try {
        capture->thread = std::thread(iohidThreadMain, capture, &start);
    }
    catch (...) {
        capture->threadRun.store(false);
        setError(capture, "Failed to start the IOHID run-loop thread");
        return false;
    }

    bool finished = false;
    bool ok = false;
    {
        std::unique_lock<std::mutex> lock(start.mu);
        finished = start.cv.wait_for(lock, std::chrono::seconds(2), [&start]() {
            return start.done;
        });
        ok = finished && start.ok;
        if (ok) {
            capture->hidDeviceCount = start.devices;
        }
    }

    if (!ok) {
        // Failure never enters the run loop. The worker exits once threadRun
        // is clear; joining waits for that. Do not CFRunLoopStop here.
        capture->threadRun.store(false);
        if (capture->thread.joinable()) {
            capture->thread.join();
        }
        if (!finished && capture->lastError[0] == '\0') {
            setError(capture, "IOHID manager timed out");
        }
        return false;
    }
    return true;
}

void stopIohid(CoreHidMouseCapture* capture)
{
    capture->threadRun.store(false);
    const CFRunLoopRef loop = reinterpret_cast<CFRunLoopRef>(capture->threadLoop.load());
    if (loop != nullptr) {
        CFRunLoopStop(loop);
    }
    if (capture->thread.joinable()) {
        capture->thread.join();
    }
    capture->hidDeviceCount = 0;
}

void postGcButton(CoreHidMouseCapture* capture, GCMouse* mouse, uint32_t usage, bool pressed)
{
    if (!capture->active.load()) {
        return;
    }
    CoreHidElementUpdate update = {};
    update.deviceId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(mouse));
    update.usagePage = CoreHidUsage::PageButton;
    update.usage = usage;
    update.value = pressed ? 1 : 0;
    deliverDecoded(capture, capture->decoder.apply(update));
}

void detachGcMouse(GCMouse* mouse)
{
    GCMouseInput* input = mouse.mouseInput;
    if (input == nil) {
        return;
    }
    input.mouseMovedHandler = nil;
    input.leftButton.pressedChangedHandler = nil;
    input.rightButton.pressedChangedHandler = nil;
    input.middleButton.pressedChangedHandler = nil;
    for (GCDeviceButtonInput* button in input.auxiliaryButtons) {
        button.pressedChangedHandler = nil;
    }
}

void attachGcMouse(CoreHidMouseCapture* capture, GCMouse* mouse)
{
    if (mouse == nil || mouse.mouseInput == nil) {
        return;
    }
    GCMouseInput* input = mouse.mouseInput;
    input.mouseMovedHandler = ^(GCMouseInput* mouseInput, float deltaX, float deltaY) {
        (void)mouseInput;
        if (!capture->active.load() || capture->onMotion == nullptr) {
            return;
        }
        CoreHidMouseDelta delta = {};
        delta.dx = coreHidApplyScale(static_cast<int32_t>(std::lround(static_cast<double>(deltaX))), capture->scale);
        delta.dy = coreHidApplyScale(coreHidPointerDyForHost(static_cast<int32_t>(std::lround(static_cast<double>(deltaY)))), capture->scale);
        delta.motion = delta.dx != 0 || delta.dy != 0;
        if (delta.motion) {
            capture->onMotion(delta, capture->context);
        }
    };

    input.leftButton.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        postGcButton(capture, mouse, 1, pressed);
    };
    input.rightButton.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        postGcButton(capture, mouse, 2, pressed);
    };
    input.middleButton.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        postGcButton(capture, mouse, 3, pressed);
    };

    uint32_t usage = 4;
    for (GCDeviceButtonInput* button in input.auxiliaryButtons) {
        const uint32_t buttonUsage = usage;
        if (buttonUsage > 8) {
            break;
        }
        usage++;
        button.pressedChangedHandler = ^(GCControllerButtonInput* changed, float value, BOOL pressed) {
            (void)changed;
            (void)value;
            postGcButton(capture, mouse, buttonUsage, pressed);
        };
    }
}

void removeGcObservers(CoreHidMouseCapture* capture)
{
    if (capture->connectObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:capture->connectObserver];
        [capture->connectObserver release];
        capture->connectObserver = nil;
    }
    if (capture->disconnectObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:capture->disconnectObserver];
        [capture->disconnectObserver release];
        capture->disconnectObserver = nil;
    }
}

bool startGcMouse(CoreHidMouseCapture* capture)
{
    if (NSClassFromString(@"GCMouse") == nil) {
        setError(capture, "GCMouse is not available on this OS");
        return false;
    }

    NSArray<GCMouse*>* mice = [GCMouse mice];
    if (mice.count == 0) {
        setError(capture, "Game Controller reported no mice. Trackpads stay on SDL.");
        return false;
    }

    for (GCMouse* mouse in mice) {
        attachGcMouse(capture, mouse);
    }
    capture->hidDeviceCount = static_cast<int>(mice.count);

    id connectObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCMouseDidConnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                    if (!capture->active.load()) {
                        return;
                    }
                    attachGcMouse(capture, note.object);
                }];
    id disconnectObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCMouseDidDisconnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                    GCMouse* mouse = note.object;
                    detachGcMouse(mouse);
                    const uint64_t deviceId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(mouse));
                    CoreHidButtonUpdate released;
                    if (capture->decoder.releaseDevice(deviceId, &released, 1) == 1 && capture->onButtons != nullptr) {
                        capture->onButtons(released, capture->context);
                    }
                }];
    capture->connectObserver = [connectObserver retain];
    capture->disconnectObserver = [disconnectObserver retain];
    return true;
}

void stopGcMouse(CoreHidMouseCapture* capture)
{
    removeGcObservers(capture);
    if (NSClassFromString(@"GCMouse") != nil) {
        for (GCMouse* mouse in [GCMouse mice]) {
            detachGcMouse(mouse);
        }
    }
    capture->hidDeviceCount = 0;
}

}

CoreHidMouseCapture* coreHidMouseCaptureCreate(CoreHidMotionFn onMotion,
                                               CoreHidButtonFn onButtons,
                                               void* context,
                                               float scale,
                                               CoreHidBackendRequest backend)
{
    CoreHidMouseCapture* capture = new CoreHidMouseCapture();
    capture->onMotion = onMotion;
    capture->onButtons = onButtons;
    capture->context = context;
    capture->scale = scale;
    capture->requestedBackend = backend;
    return capture;
}

void coreHidMouseCaptureDestroy(CoreHidMouseCapture* capture)
{
    if (capture == nullptr) {
        return;
    }
    coreHidMouseCaptureStop(capture);
    delete capture;
}

bool coreHidMouseCaptureStart(CoreHidMouseCapture* capture)
{
    if (capture == nullptr) {
        return false;
    }
    if (capture->active.load()) {
        return true;
    }

    capture->lastError[0] = '\0';
    capture->ownsWheel.store(false);
    // Handlers may run as soon as a backend opens. Mark the capture active
    // first so those events are delivered, and clear it if every backend fails.
    capture->active.store(true);
    bool started = false;
    char iohidError[256];
    iohidError[0] = '\0';

    const bool allowIohid = capture->requestedBackend != CoreHidBackendRequest::GameController;
    const bool allowGcMouse = capture->requestedBackend != CoreHidBackendRequest::Iohid;

    if (allowIohid && startIohid(capture)) {
        capture->activeBackend = CoreHidBackendRequest::Iohid;
        started = true;
    }
    else {
        std::snprintf(iohidError, sizeof(iohidError), "%s", capture->lastError);
        if (allowGcMouse && startGcMouse(capture)) {
            capture->activeBackend = CoreHidBackendRequest::GameController;
            started = true;
            if (allowIohid && iohidError[0] != '\0') {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "CoreHID mouse: IOHID unavailable (%s). Using Game Controller GCMouse.",
                            iohidError);
            }
        }
    }

    if (!started) {
        capture->active.store(false);
        if (capture->lastError[0] == '\0') {
            setError(capture, iohidError[0] != '\0' ? iohidError : "No native mouse backend started");
        }
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "CoreHID mouse: %s. Falling back to SDL relative mouse.",
                    capture->lastError);
        return false;
    }

    disassociateCursor(capture);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "CoreHID mouse capture started via %s (%d device%s, scale %.2f). SDL cursor-warp relative mode stays off.",
                capture->activeBackend == CoreHidBackendRequest::Iohid ? "IOHID" : "GCMouse",
                capture->hidDeviceCount,
                capture->hidDeviceCount == 1 ? "" : "s",
                capture->scale);
    return true;
}

void coreHidMouseCaptureStop(CoreHidMouseCapture* capture)
{
    if (capture == nullptr || !capture->active.load()) {
        return;
    }

    // Stop delivery before releasing buttons so a late report cannot
    // press a button we are about to raise.
    capture->active.store(false);

    if (capture->activeBackend == CoreHidBackendRequest::Iohid) {
        stopIohid(capture);
    }
    else if (capture->activeBackend == CoreHidBackendRequest::GameController) {
        stopGcMouse(capture);
    }

    emitButtonReleases(capture);
    reassociateCursor(capture);
    capture->activeBackend = CoreHidBackendRequest::Auto;
    capture->ownsWheel.store(false);
}

bool coreHidMouseCaptureOwnsWheel(const CoreHidMouseCapture* capture)
{
    return capture != nullptr && capture->ownsWheel.load();
}

bool coreHidMouseCaptureIsActive(const CoreHidMouseCapture* capture)
{
    return capture != nullptr && capture->active.load();
}

const char* coreHidMouseCaptureLastError(const CoreHidMouseCapture* capture)
{
    if (capture == nullptr || capture->lastError[0] == '\0') {
        return "";
    }
    return capture->lastError;
}

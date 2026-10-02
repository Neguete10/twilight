#pragma once

#include <cstdint>

// Mac raw-mouse capture for Twilight.
//
// CoreHID.framework (macOS 15+, Swift actors) is the current Apple name for
// this stack. This Qt client does not link that Swift framework. The capture
// backend uses IOHIDManager, the C API CoreHID's HIDDeviceClient reads, and
// can fall back to GCMouse from Game Controller. See docs/COREHID_MAC.md.
//
// Relative HID counts are forwarded as LiSendMouseMoveEvent deltas. This path
// does not use LiSendMouseMoveAsMousePositionEvent, which keeps a virtual
// client cursor and exists for platforms that cannot read raw motion.

namespace CoreHidUsage {

constexpr uint32_t PageGenericDesktop = 0x01;
constexpr uint32_t PageButton = 0x09;
constexpr uint32_t PageConsumer = 0x0C;

constexpr uint32_t DesktopX = 0x30;
constexpr uint32_t DesktopY = 0x31;
constexpr uint32_t DesktopWheel = 0x38;
constexpr uint32_t DesktopACPan = 0x238;
constexpr uint32_t ConsumerACPan = 0x238;

// Primary device usage. Mice, not keyboards (0x06) or joysticks (0x04).
constexpr uint32_t DesktopMouse = 0x02;

}

// How the session decides to capture. Matches Limelight's relative-vs-virtual
// split: raw relative elements become host relative motion. Anything else is
// dropped here so the SDL absolute / cursor-warp path can keep it.
enum class CoreHidMotionPolicy {
    Relative,
    Drop,
};

enum class CoreHidBackendRequest {
    Auto,
    Iohid,
    GameController,
};

struct CoreHidElementUpdate {
    uint64_t deviceId;
    uint32_t usagePage;
    uint32_t usage;
    int32_t value;
    int32_t logicalMin;
    int32_t logicalMax;
    bool relative;
};

struct CoreHidMouseDelta {
    int32_t dx;
    int32_t dy;
    int32_t wheel;
    int32_t hWheel;
    bool motion;
    bool wheelChanged;
    bool hWheelChanged;
};

// pressed/released are bit masks. Bit (usage - 1) corresponds to HID button
// usage 1..8 (left, right, middle, X1, X2, ...).
struct CoreHidButtonUpdate {
    uint64_t deviceId;
    uint32_t pressed;
    uint32_t released;
    bool changed;
};

struct CoreHidDecodedUpdate {
    bool hasMotion;
    CoreHidMouseDelta motion;
    bool hasButtons;
    CoreHidButtonUpdate buttons;
};

// True when an X/Y/wheel element is a delta rather than an absolute position.
// Absolute HID positions are not turned into motion: that would be another
// virtual cursor. The relative flag is authoritative; a signed logical range
// is the fallback used by descriptors that omit the flag.
bool coreHidElementCarriesDelta(const CoreHidElementUpdate& update);

CoreHidMotionPolicy coreHidMotionPolicy(bool relativeElement);

// preference is the saved checkbox. env null or empty leaves it alone.
// "1"/"true"/"yes"/"on" force on. "0"/"false"/"no"/"off" force off.
bool coreHidResolveEnabled(bool preference, const char* env);

// null, empty, or "auto" -> Auto. "iohid" -> Iohid.
// "gcmouse" or "gamecontroller" -> GameController. Anything else -> Auto.
CoreHidBackendRequest coreHidResolveBackend(const char* env);

const char* coreHidBackendName(CoreHidBackendRequest request);

// null or empty or out of (0, 20] -> 1.
float coreHidResolveScale(const char* env);

// Rounds raw * scale into the int16 range LiSendMouseMoveEvent accepts.
int16_t coreHidApplyScale(int32_t raw, float scale);

// One HID wheel notch is 120, matching the SDL high-res scroll path (WHEEL_DELTA).
int16_t coreHidScrollToHighRes(int32_t notches, bool reverse);

// HID button usage -> Limelight BUTTON_* value. 0 if this client does not send it.
// 1 left, 2 right, 3 middle, 4 X1, 5 X2. Values match moonlight-common-c Limelight.h.
int coreHidHostButtonForUsage(uint32_t hidButtonUsage);

class CoreHidMouseDecoder {
public:
    CoreHidMouseDecoder();

    CoreHidDecodedUpdate apply(const CoreHidElementUpdate& update);

    // Buttons that were down, then cleared. Empty if none.
    // The vector is returned by value so the caller can send releases
    // after the device is gone.
    // Implemented out of line to keep this header free of <vector>.
    int releaseDevice(uint64_t deviceId, CoreHidButtonUpdate* out, int outCount);
    int releaseAll(CoreHidButtonUpdate* out, int outCount);

    bool sawWheel() const;
    bool sawHorizontalWheel() const;

private:
    static const int kMaxDevices = 16;

    struct DeviceButtons {
        uint64_t id;
        uint32_t mask;
        bool used;
    };

    DeviceButtons* findDevice(uint64_t deviceId, bool create);

    DeviceButtons m_Devices[kMaxDevices];
    bool m_SawWheel;
    bool m_SawHWheel;
};

#if defined(__APPLE__)

struct CoreHidMouseCapture;

typedef void (*CoreHidMotionFn)(const CoreHidMouseDelta& delta, void* context);
typedef void (*CoreHidButtonFn)(const CoreHidButtonUpdate& update, void* context);

CoreHidMouseCapture* coreHidMouseCaptureCreate(CoreHidMotionFn onMotion,
                                               CoreHidButtonFn onButtons,
                                               void* context,
                                               float scale,
                                               CoreHidBackendRequest backend);
void coreHidMouseCaptureDestroy(CoreHidMouseCapture* capture);
bool coreHidMouseCaptureStart(CoreHidMouseCapture* capture);
void coreHidMouseCaptureStop(CoreHidMouseCapture* capture);
bool coreHidMouseCaptureOwnsWheel(const CoreHidMouseCapture* capture);
bool coreHidMouseCaptureIsActive(const CoreHidMouseCapture* capture);
const char* coreHidMouseCaptureLastError(const CoreHidMouseCapture* capture);

#endif

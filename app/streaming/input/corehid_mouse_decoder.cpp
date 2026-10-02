#include "corehid_mouse.h"

#include <cmath>
#include <cstdlib>
#include <cstring>

namespace {

bool equalsIgnoreCase(const char* value, const char* literal)
{
    if (value == nullptr || literal == nullptr) {
        return false;
    }
    while (*value != '\0' && *literal != '\0') {
        char left = *value;
        char right = *literal;
        if (left >= 'A' && left <= 'Z') {
            left = static_cast<char>(left - 'A' + 'a');
        }
        if (right >= 'A' && right <= 'Z') {
            right = static_cast<char>(right - 'A' + 'a');
        }
        if (left != right) {
            return false;
        }
        value++;
        literal++;
    }
    return *value == '\0' && *literal == '\0';
}

bool envUnset(const char* env)
{
    return env == nullptr || env[0] == '\0';
}

int16_t clampToShort(int32_t value)
{
    if (value > 32767) {
        return 32767;
    }
    if (value < -32768) {
        return static_cast<int16_t>(-32768);
    }
    return static_cast<int16_t>(value);
}

}

bool coreHidElementCarriesDelta(const CoreHidElementUpdate& update)
{
    if (update.relative) {
        return true;
    }
    // Signed logical range, e.g. -127..127, is a delta even when the
    // descriptor forgot the relative flag. 0..N is an absolute axis.
    return update.logicalMin < 0 && update.logicalMax > 0;
}

CoreHidMotionPolicy coreHidMotionPolicy(bool relativeElement)
{
    if (!relativeElement) {
        return CoreHidMotionPolicy::Drop;
    }
    return CoreHidMotionPolicy::Relative;
}

bool coreHidResolveEnabled(bool preference, const char* env)
{
    if (envUnset(env)) {
        return preference;
    }
    if (equalsIgnoreCase(env, "1") || equalsIgnoreCase(env, "true") ||
            equalsIgnoreCase(env, "yes") || equalsIgnoreCase(env, "on")) {
        return true;
    }
    if (equalsIgnoreCase(env, "0") || equalsIgnoreCase(env, "false") ||
            equalsIgnoreCase(env, "no") || equalsIgnoreCase(env, "off")) {
        return false;
    }
    return preference;
}

CoreHidBackendRequest coreHidResolveBackend(const char* env)
{
    if (envUnset(env) || equalsIgnoreCase(env, "auto")) {
        return CoreHidBackendRequest::Auto;
    }
    if (equalsIgnoreCase(env, "iohid")) {
        return CoreHidBackendRequest::Iohid;
    }
    if (equalsIgnoreCase(env, "gcmouse") || equalsIgnoreCase(env, "gamecontroller")) {
        return CoreHidBackendRequest::GameController;
    }
    return CoreHidBackendRequest::Auto;
}

const char* coreHidBackendName(CoreHidBackendRequest request)
{
    switch (request) {
    case CoreHidBackendRequest::Iohid:
        return "iohid";
    case CoreHidBackendRequest::GameController:
        return "gamecontroller";
    case CoreHidBackendRequest::Auto:
    default:
        return "auto";
    }
}

float coreHidResolveScale(const char* env)
{
    if (envUnset(env)) {
        return 1.0f;
    }
    char* end = nullptr;
    float value = std::strtof(env, &end);
    if (end == env || value <= 0.0f || value > 20.0f) {
        return 1.0f;
    }
    return value;
}

int32_t coreHidPointerDyForHost(int32_t dy)
{
    // int32 min cannot be negated. A mouse count will not get here; saturate
    // so the later int16 clamp still points down.
    if (dy == static_cast<int32_t>(0x80000000)) {
        return 2147483647;
    }
    return -dy;
}

int16_t coreHidApplyScale(int32_t raw, float scale)
{
    if (!(scale > 0.0f)) {
        scale = 1.0f;
    }
    const double scaled = static_cast<double>(raw) * static_cast<double>(scale);
    if (scaled >= 32767.0) {
        return 32767;
    }
    if (scaled <= -32768.0) {
        return static_cast<int16_t>(-32768);
    }
    return static_cast<int16_t>(std::lround(scaled));
}

int16_t coreHidScrollToHighRes(int32_t notches, bool reverse)
{
    int32_t amount = notches * 120;
    if (reverse) {
        amount = -amount;
    }
    return clampToShort(amount);
}

int coreHidHostButtonForUsage(uint32_t hidButtonUsage)
{
    // Limelight.h: BUTTON_LEFT 0x01, BUTTON_MIDDLE 0x02, BUTTON_RIGHT 0x03,
    // BUTTON_X1 0x04, BUTTON_X2 0x05.
    switch (hidButtonUsage) {
    case 1:
        return 0x01;
    case 2:
        return 0x03;
    case 3:
        return 0x02;
    case 4:
        return 0x04;
    case 5:
        return 0x05;
    default:
        return 0;
    }
}

CoreHidMouseDecoder::CoreHidMouseDecoder()
    : m_SawWheel(false),
      m_SawHWheel(false)
{
    for (int i = 0; i < kMaxDevices; i++) {
        m_Devices[i].id = 0;
        m_Devices[i].mask = 0;
        m_Devices[i].used = false;
    }
}

CoreHidMouseDecoder::DeviceButtons* CoreHidMouseDecoder::findDevice(uint64_t deviceId, bool create)
{
    CoreHidMouseDecoder::DeviceButtons* freeSlot = nullptr;
    for (int i = 0; i < kMaxDevices; i++) {
        if (m_Devices[i].used && m_Devices[i].id == deviceId) {
            return &m_Devices[i];
        }
        if (!m_Devices[i].used && freeSlot == nullptr) {
            freeSlot = &m_Devices[i];
        }
    }
    if (!create || freeSlot == nullptr) {
        return nullptr;
    }
    freeSlot->used = true;
    freeSlot->id = deviceId;
    freeSlot->mask = 0;
    return freeSlot;
}

CoreHidDecodedUpdate CoreHidMouseDecoder::apply(const CoreHidElementUpdate& update)
{
    CoreHidDecodedUpdate decoded = {};

    const bool axisX = update.usagePage == CoreHidUsage::PageGenericDesktop &&
            update.usage == CoreHidUsage::DesktopX;
    const bool axisY = update.usagePage == CoreHidUsage::PageGenericDesktop &&
            update.usage == CoreHidUsage::DesktopY;
    const bool wheel = update.usagePage == CoreHidUsage::PageGenericDesktop &&
            update.usage == CoreHidUsage::DesktopWheel;
    const bool hWheel =
            (update.usagePage == CoreHidUsage::PageGenericDesktop && update.usage == CoreHidUsage::DesktopACPan) ||
            (update.usagePage == CoreHidUsage::PageConsumer && update.usage == CoreHidUsage::ConsumerACPan);

    if (axisX || axisY || wheel || hWheel) {
        if (coreHidMotionPolicy(coreHidElementCarriesDelta(update)) != CoreHidMotionPolicy::Relative) {
            return decoded;
        }
        if (wheel) {
            m_SawWheel = true;
        }
        if (hWheel) {
            m_SawHWheel = true;
        }
        if (update.value == 0) {
            return decoded;
        }
        decoded.hasMotion = true;
        if (axisX) {
            decoded.motion.dx = update.value;
            decoded.motion.motion = true;
        }
        else if (axisY) {
            decoded.motion.dy = coreHidPointerDyForHost(update.value);
            decoded.motion.motion = true;
        }
        else if (wheel) {
            decoded.motion.wheel = update.value;
            decoded.motion.wheelChanged = true;
        }
        else if (hWheel) {
            decoded.motion.hWheel = update.value;
            decoded.motion.hWheelChanged = true;
        }
        return decoded;
    }

    if (update.usagePage == CoreHidUsage::PageButton && update.usage >= 1 && update.usage <= 8) {
        DeviceButtons* device = findDevice(update.deviceId, true);
        if (device == nullptr) {
            return decoded;
        }
        const uint32_t bit = 1u << (update.usage - 1);
        const uint32_t oldMask = device->mask;
        if (update.value != 0) {
            device->mask |= bit;
        }
        else {
            device->mask &= ~bit;
        }
        decoded.buttons.deviceId = update.deviceId;
        decoded.buttons.pressed = device->mask & ~oldMask;
        decoded.buttons.released = oldMask & ~device->mask;
        decoded.buttons.changed = decoded.buttons.pressed != 0 || decoded.buttons.released != 0;
        decoded.hasButtons = decoded.buttons.changed;
        return decoded;
    }

    return decoded;
}

int CoreHidMouseDecoder::releaseDevice(uint64_t deviceId, CoreHidButtonUpdate* out, int outCount)
{
    DeviceButtons* device = findDevice(deviceId, false);
    if (device == nullptr || device->mask == 0 || out == nullptr || outCount < 1) {
        if (device != nullptr) {
            device->used = false;
            device->mask = 0;
        }
        return 0;
    }
    out[0].deviceId = deviceId;
    out[0].pressed = 0;
    out[0].released = device->mask;
    out[0].changed = true;
    device->mask = 0;
    device->used = false;
    return 1;
}

int CoreHidMouseDecoder::releaseAll(CoreHidButtonUpdate* out, int outCount)
{
    int written = 0;
    for (int i = 0; i < kMaxDevices; i++) {
        if (!m_Devices[i].used) {
            continue;
        }
        if (m_Devices[i].mask != 0 && out != nullptr && written < outCount) {
            out[written].deviceId = m_Devices[i].id;
            out[written].pressed = 0;
            out[written].released = m_Devices[i].mask;
            out[written].changed = true;
            written++;
        }
        m_Devices[i].mask = 0;
        m_Devices[i].used = false;
    }
    return written;
}

bool CoreHidMouseDecoder::sawWheel() const
{
    return m_SawWheel;
}

bool CoreHidMouseDecoder::sawHorizontalWheel() const
{
    return m_SawHWheel;
}

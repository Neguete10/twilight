#include "dualsense_hid.h"

#include <SDL.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>

#include <stdlib.h>
#include <strings.h>

struct DualSenseHidOutput::Impl {
    bool logged;
};

DualSenseHidOutput::DualSenseHidOutput()
    : m_Impl(new Impl())
{
    m_Impl->logged = false;
}

DualSenseHidOutput::~DualSenseHidOutput()
{
    delete m_Impl;
    m_Impl = nullptr;
}

static bool isDualSenseProduct(int vid, int pid)
{
    return vid == 0x054C && (pid == 0x0CE6 || pid == 0x0DF2);
}

static int cfNumber(CFTypeRef value)
{
    int number = 0;
    if (value != nullptr && CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &number);
    }
    return number;
}

// Skip the audio interface that shares the DualSense VID/PID. Missing usage
// keys are treated as a match so a stack that omits them still gets a write.
static bool isGamepadInterface(IOHIDDeviceRef device)
{
    int page = cfNumber(IOHIDDeviceGetProperty(device, CFSTR(kIOHIDPrimaryUsagePageKey)));
    int usage = cfNumber(IOHIDDeviceGetProperty(device, CFSTR(kIOHIDPrimaryUsageKey)));
    if (page == 0 || usage == 0) {
        return true;
    }
    if (page != 0x01) {
        return false;
    }
    return usage == 0x04 || usage == 0x05 || usage == 0x08;
}

static bool transportIsBluetooth(IOHIDDeviceRef device)
{
    CFTypeRef transport = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDTransportKey));
    if (transport == nullptr || CFGetTypeID(transport) != CFStringGetTypeID()) {
        return false;
    }
    CFRange found = CFStringFind((CFStringRef)transport, CFSTR("Bluetooth"), 0);
    return found.location != kCFNotFound;
}

static bool serialEquals(IOHIDDeviceRef device, const char* serial)
{
    char buf[128];
    CFTypeRef value;

    if (serial == nullptr || serial[0] == 0) {
        return false;
    }
    value = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDSerialNumberKey));
    if (value == nullptr || CFGetTypeID(value) != CFStringGetTypeID()) {
        return false;
    }
    if (!CFStringGetCString((CFStringRef)value, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        return false;
    }
    return strcasecmp(buf, serial) == 0;
}

bool DualSenseHidOutput::send(const DualSenseOutputReport& report, const char* serial)
{
    IOHIDManagerRef manager;
    CFMutableDictionaryRef match;
    CFNumberRef vendor;
    CFSetRef devices;
    IOHIDDeviceRef found[8];
    CFIndex count;
    int vid = 0x054C;
    int i;
    int chosen = -1;
    IOReturn openResult;
    IOReturn setResult;
    bool bluetooth;
    DualSenseHidReport hid;

    manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (manager == nullptr) {
        return false;
    }

    match = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                      &kCFTypeDictionaryKeyCallBacks,
                                      &kCFTypeDictionaryValueCallBacks);
    vendor = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFDictionarySetValue(match, CFSTR(kIOHIDVendorIDKey), vendor);
    IOHIDManagerSetDeviceMatching(manager, match);
    CFRelease(vendor);
    CFRelease(match);

    if (IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        CFRelease(manager);
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "DualSense IOHID manager open failed");
        return false;
    }

    devices = IOHIDManagerCopyDevices(manager);
    count = 0;
    if (devices != nullptr) {
        CFIndex allCount = CFSetGetCount(devices);
        IOHIDDeviceRef* all = nullptr;
        if (allCount > 0) {
            all = (IOHIDDeviceRef*)malloc((size_t)allCount * sizeof(IOHIDDeviceRef));
            if (all != nullptr) {
                CFSetGetValues(devices, (const void**)all);
                for (i = 0; i < (int)allCount && count < (CFIndex)(sizeof(found) / sizeof(found[0])); i++) {
                    int product = cfNumber(IOHIDDeviceGetProperty(all[i], CFSTR(kIOHIDProductIDKey)));
                    int vendorId = cfNumber(IOHIDDeviceGetProperty(all[i], CFSTR(kIOHIDVendorIDKey)));
                    if (isDualSenseProduct(vendorId, product) && isGamepadInterface(all[i])) {
                        found[count++] = all[i];
                    }
                }
                free(all);
            }
        }
    }

    for (i = 0; i < (int)count; i++) {
        if (serialEquals(found[i], serial)) {
            chosen = i;
            break;
        }
    }
    if (chosen < 0 && count == 1) {
        chosen = 0;
    }
    if (chosen < 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "DualSense IOHID fallback found %ld controller(s) and no serial match",
                    (long)count);
        if (devices != nullptr) {
            CFRelease(devices);
        }
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
        return false;
    }

    bluetooth = transportIsBluetooth(found[chosen]);
    hid = dualSenseBuildHidReport(bluetooth, &report);
    openResult = IOHIDDeviceOpen(found[chosen], kIOHIDOptionsTypeNone);
    if (openResult != kIOReturnSuccess) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "DualSense IOHIDDeviceOpen failed: 0x%x", openResult);
        if (devices != nullptr) {
            CFRelease(devices);
        }
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
        return false;
    }

    setResult = IOHIDDeviceSetReport(found[chosen], kIOHIDReportTypeOutput,
                                     hid.data[0], hid.data + 1, hid.size - 1);
    IOHIDDeviceClose(found[chosen], kIOHIDOptionsTypeNone);
    if (devices != nullptr) {
        CFRelease(devices);
    }
    IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
    CFRelease(manager);

    if (setResult != kIOReturnSuccess) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "DualSense IOHIDDeviceSetReport failed: 0x%x", setResult);
        return false;
    }

    if (m_Impl != nullptr && !m_Impl->logged) {
        m_Impl->logged = true;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "DualSense adaptive trigger via IOHID %s output report",
                    bluetooth ? "Bluetooth" : "USB");
    }
    return true;
}

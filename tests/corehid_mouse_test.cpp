#include "corehid_mouse.h"

#include <cstdio>
#include <cstring>

static int g_Failures = 0;

static void expectTrue(bool value, const char* label)
{
    if (!value) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static void expectInt(int actual, int expected, const char* label)
{
    if (actual != expected) {
        std::printf("FAIL %s: got %d, expected %d\n", label, actual, expected);
        g_Failures++;
    }
}

static CoreHidElementUpdate element(uint64_t device, uint32_t page, uint32_t usage, int32_t value, bool relative)
{
    CoreHidElementUpdate update = {};
    update.deviceId = device;
    update.usagePage = page;
    update.usage = usage;
    update.value = value;
    update.logicalMin = relative ? -127 : 0;
    update.logicalMax = relative ? 127 : 255;
    update.relative = relative;
    return update;
}

static void testMotionPolicy()
{
    expectTrue(coreHidMotionPolicy(true) == CoreHidMotionPolicy::Relative, "relative element is a delta");
    expectTrue(coreHidMotionPolicy(false) == CoreHidMotionPolicy::Drop, "absolute element is not a virtual cursor");

    CoreHidElementUpdate flagged = element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopX, 4, true);
    expectTrue(coreHidElementCarriesDelta(flagged), "relative flag carries a delta");

    CoreHidElementUpdate signedRange = element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopX, 4, false);
    signedRange.relative = false;
    signedRange.logicalMin = -127;
    signedRange.logicalMax = 127;
    expectTrue(coreHidElementCarriesDelta(signedRange), "signed logical range carries a delta");

    CoreHidElementUpdate absolute = element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopX, 40, false);
    expectTrue(!coreHidElementCarriesDelta(absolute), "0..N axis is absolute");
}

static void testDecoderMotion()
{
    CoreHidMouseDecoder decoder;
    CoreHidDecodedUpdate x = decoder.apply(element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopX, 5, true));
    expectTrue(x.hasMotion && x.motion.motion && x.motion.dx == 5 && x.motion.dy == 0, "relative X");

    CoreHidDecodedUpdate y = decoder.apply(element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopY, -3, true));
    expectTrue(y.hasMotion && y.motion.dy == -3 && y.motion.dx == 0, "IOHID relative Y stays down-positive");
    expectInt(coreHidPointerDyForHost(-3), 3, "GCMouse upward count becomes downward host dy");
    expectInt(coreHidPointerDyForHost(4), -4, "GCMouse downward count becomes upward host dy");
    expectInt(coreHidPointerDyForHost(0), 0, "zero pointer Y stays zero");
    expectInt(coreHidPointerDyForHost(static_cast<int32_t>(0x80000000)), 2147483647, "int32 min Y saturates");

    CoreHidDecodedUpdate zero = decoder.apply(element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopX, 0, true));
    expectTrue(!zero.hasMotion, "zero delta is not sent");

    CoreHidDecodedUpdate absolute = decoder.apply(element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopX, 80, false));
    expectTrue(!absolute.hasMotion, "absolute X is dropped");

    CoreHidDecodedUpdate keyboard = decoder.apply(element(1, 0x07, 0x04, 1, false));
    expectTrue(!keyboard.hasMotion && !keyboard.hasButtons, "keyboard usage is ignored");
}

static void testWheel()
{
    CoreHidMouseDecoder decoder;
    expectTrue(!decoder.sawWheel(), "wheel unseen");

    CoreHidDecodedUpdate notch = decoder.apply(element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopWheel, 1, true));
    expectTrue(notch.hasMotion && notch.motion.wheelChanged && notch.motion.wheel == 1, "wheel notch");
    expectTrue(!notch.motion.motion, "wheel is not pointer motion");
    expectTrue(decoder.sawWheel(), "wheel element remembered");

    CoreHidMouseDecoder absoluteDecoder;
    CoreHidDecodedUpdate absolute = absoluteDecoder.apply(element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopWheel, 1, false));
    expectTrue(!absolute.hasMotion && !absoluteDecoder.sawWheel(), "absolute wheel is not a notch");

    CoreHidDecodedUpdate pan = decoder.apply(element(1, CoreHidUsage::PageConsumer, CoreHidUsage::ConsumerACPan, -2, true));
    expectTrue(pan.motion.hWheelChanged && pan.motion.hWheel == -2, "consumer AC pan");
    expectTrue(decoder.sawHorizontalWheel(), "horizontal wheel remembered");

    CoreHidMouseDecoder resting;
    CoreHidDecodedUpdate quiet = resting.apply(element(1, CoreHidUsage::PageGenericDesktop, CoreHidUsage::DesktopWheel, 0, true));
    expectTrue(!quiet.hasMotion && !resting.sawWheel(), "zero wheel does not claim the wheel");
    expectTrue(decoder.sawWheel(), "a real notch is still remembered after a later zero");
}

static void testButtons()
{
    CoreHidMouseDecoder decoder;
    CoreHidDecodedUpdate press = decoder.apply(element(7, CoreHidUsage::PageButton, 1, 1, false));
    expectTrue(press.hasButtons && press.buttons.pressed == 0x1 && press.buttons.released == 0, "left press");

    CoreHidDecodedUpdate repeat = decoder.apply(element(7, CoreHidUsage::PageButton, 1, 1, false));
    expectTrue(!repeat.hasButtons, "repeat press is not another edge");

    CoreHidDecodedUpdate right = decoder.apply(element(7, CoreHidUsage::PageButton, 2, 1, false));
    expectTrue(right.buttons.pressed == 0x2, "right is bit 1");

    CoreHidDecodedUpdate other = decoder.apply(element(8, CoreHidUsage::PageButton, 1, 1, false));
    expectTrue(other.buttons.pressed == 0x1 && other.buttons.deviceId == 8, "second device is independent");

    CoreHidDecodedUpdate up = decoder.apply(element(7, CoreHidUsage::PageButton, 1, 0, false));
    expectTrue(up.buttons.released == 0x1 && up.buttons.pressed == 0, "left release");

    CoreHidButtonUpdate released[4];
    int count = decoder.releaseDevice(7, released, 4);
    expectInt(count, 1, "release remaining buttons on device 7");
    expectInt(static_cast<int>(released[0].released), 0x2, "right still down on device 7");

    count = decoder.releaseAll(released, 4);
    expectInt(count, 1, "other device still held");
    expectInt(static_cast<int>(released[0].deviceId), 8, "remaining device id");
    expectInt(static_cast<int>(released[0].released), 0x1, "remaining left button");

    count = decoder.releaseAll(released, 4);
    expectInt(count, 0, "second releaseAll is empty");
}

static void testHostButtonsAndScroll()
{
    expectInt(coreHidHostButtonForUsage(1), 0x01, "left");
    expectInt(coreHidHostButtonForUsage(2), 0x03, "right");
    expectInt(coreHidHostButtonForUsage(3), 0x02, "middle");
    expectInt(coreHidHostButtonForUsage(4), 0x04, "x1");
    expectInt(coreHidHostButtonForUsage(5), 0x05, "x2");
    expectInt(coreHidHostButtonForUsage(6), 0, "usage 6 is not sent");

    expectInt(coreHidScrollToHighRes(1, false, false), 120, "one notch, classic direction");
    expectInt(coreHidScrollToHighRes(1, true, false), -120, "natural scrolling negates");
    expectInt(coreHidScrollToHighRes(1, false, true), -120, "reverse-scroll negates");
    expectInt(coreHidScrollToHighRes(1, true, true), 120, "natural and reverse cancel");
    expectInt(coreHidScrollToHighRes(300, false, false), 32767, "scroll clamps high");
    expectInt(coreHidScrollToHighRes(-300, false, false), -32768, "scroll clamps low");

    expectInt(static_cast<int>(kCoreHidSdlSuppressWindowMs), 250, "SDL suppress window");
    expectInt(static_cast<int>(kCoreHidTrackpadSupersedeWindowMs), 100, "trackpad supersede window");
    expectTrue(!coreHidEventIsRecent(-1, 1000, kCoreHidSdlSuppressWindowMs), "never is not recent");
    expectTrue(!coreHidEventIsRecent(1000, 999, kCoreHidSdlSuppressWindowMs), "clock going backwards is not recent");
    expectTrue(coreHidEventIsRecent(1000, 1000, kCoreHidSdlSuppressWindowMs), "same instant is recent");
    expectTrue(coreHidEventIsRecent(1000, 1250, kCoreHidSdlSuppressWindowMs), "edge of the 250 ms window is recent");
    expectTrue(!coreHidEventIsRecent(1000, 1251, kCoreHidSdlSuppressWindowMs), "past the 250 ms window is not recent");
    expectTrue(coreHidEventIsRecent(500, 600, kCoreHidTrackpadSupersedeWindowMs), "edge of the 100 ms window is recent");
    expectTrue(!coreHidEventIsRecent(500, 601, kCoreHidTrackpadSupersedeWindowMs), "past the 100 ms window is not recent");
}

static void testEnableScaleBackend()
{
    expectTrue(coreHidResolveEnabled(false, nullptr) == false, "null env keeps off");
    expectTrue(coreHidResolveEnabled(true, "") == true, "empty env keeps on");
    expectTrue(coreHidResolveEnabled(false, "1"), "1 forces on");
    expectTrue(coreHidResolveEnabled(false, "TRUE"), "TRUE forces on");
    expectTrue(coreHidResolveEnabled(false, "yes"), "yes forces on");
    expectTrue(coreHidResolveEnabled(false, "on"), "on forces on");
    expectTrue(!coreHidResolveEnabled(true, "0"), "0 forces off");
    expectTrue(!coreHidResolveEnabled(true, "Off"), "Off forces off");
    expectTrue(coreHidResolveEnabled(true, "maybe") == true, "unknown env keeps preference");

    expectTrue(coreHidResolveBackend(nullptr) == CoreHidBackendRequest::Auto, "null backend");
    expectTrue(coreHidResolveBackend("auto") == CoreHidBackendRequest::Auto, "auto backend");
    expectTrue(coreHidResolveBackend("IOHID") == CoreHidBackendRequest::Iohid, "iohid backend");
    expectTrue(coreHidResolveBackend("gcmouse") == CoreHidBackendRequest::GameController, "gcmouse backend");
    expectTrue(coreHidResolveBackend("gamecontroller") == CoreHidBackendRequest::GameController, "gamecontroller backend");
    expectTrue(coreHidResolveBackend("nope") == CoreHidBackendRequest::Auto, "unknown backend");
    expectTrue(std::strcmp(coreHidBackendName(CoreHidBackendRequest::Iohid), "iohid") == 0, "iohid name");

    expectTrue(coreHidResolveScale(nullptr) == 1.0f, "null scale");
    expectTrue(coreHidResolveScale("") == 1.0f, "empty scale");
    expectTrue(coreHidResolveScale("0") == 1.0f, "non-positive scale");
    expectTrue(coreHidResolveScale("21") == 1.0f, "huge scale");
    expectTrue(coreHidResolveScale("abc") == 1.0f, "junk scale");
    expectTrue(coreHidResolveScale("1.5") == 1.5f, "1.5 scale");

    expectInt(coreHidApplyScale(10, 0.4f), 4, "scale 0.4");
    expectInt(coreHidApplyScale(1, 0.4f), 0, "scale rounds to zero");
    expectInt(coreHidApplyScale(40000, 1.0f), 32767, "scale clamps high");
    expectInt(coreHidApplyScale(-40000, 2.0f), -32768, "scale clamps low");
    expectInt(coreHidApplyScale(8, 0.0f), 8, "apply treats non-positive scale as 1");
}

int main()
{
    testMotionPolicy();
    testDecoderMotion();
    testWheel();
    testButtons();
    testHostButtonsAndScroll();
    testEnableScaleBackend();

    if (g_Failures != 0) {
        std::printf("%d corehid mouse tests failed\n", g_Failures);
        return 1;
    }
    std::printf("corehid mouse tests passed\n");
    return 0;
}

#include "dualsense_effects.h"
#include "gamepad_overlay.h"

#include <Limelight.h>

#include <cstdio>
#include <cstring>

static int g_failures = 0;

static void expect(bool cond, const char* message)
{
    if (!cond) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        g_failures++;
    }
}

static void testCrcAndReports()
{
    const char* digits = "123456789";
    expect(dualSenseCrc32(0, reinterpret_cast<const uint8_t*>(digits), 9) == 0xCBF43926u,
           "SDL-compatible CRC32");

    DualSenseOutputReport effect;
    std::memset(&effect, 0, sizeof(effect));
    effect.validFlag0 = 0x0C;
    effect.rightTriggerEffectType = 0x01;
    effect.rightTriggerEffect[0] = 0;
    effect.rightTriggerEffect[1] = 110;

    DualSenseHidReport usb = dualSenseBuildHidReport(false, &effect);
    expect(usb.size == 48, "usb report size");
    expect(usb.data[0] == 0x02, "usb report id");
    expect(usb.data[1] == 0x0C, "usb copies the effect at byte 1");
    expect(usb.data[11] == 0x01 && usb.data[13] == 110, "usb trigger bytes");

    DualSenseHidReport bt = dualSenseBuildHidReport(true, &effect);
    expect(bt.size == 78, "bluetooth report size");
    expect(bt.data[0] == 0x31 && bt.data[1] == 0x02, "bluetooth header");
    expect(bt.data[2] == 0x0C, "bluetooth effect starts at byte 2");
    expect(bt.data[12] == 0x01 && bt.data[13] == 0 && bt.data[14] == 110, "bluetooth trigger bytes");

    uint32_t crc = 0;
    std::memcpy(&crc, bt.data + 74, 4);
    expect(crc == 0x8dd42ce4u, "bluetooth CRC matches SDL's algorithm");
}

static void testPreviewEffects()
{
    DualSenseOutputReport report;
    expect(!dualSenseFillPreviewReport(DualSensePreviewFollowHost, &report), "follow-host sends nothing");
    expect(report.validFlag0 == 0, "follow-host report stays clear");

    expect(dualSenseFillPreviewReport(DualSensePreviewRigid, &report), "rigid preview");
    expect(report.validFlag0 == (0x04 | 0x08), "both triggers enabled");
    expect(report.leftTriggerEffectType == 0x01, "rigid mode");
    expect(report.leftTriggerEffect[0] == 0 && report.leftTriggerEffect[1] == 110, "rigid strength");
    expect(report.rightTriggerEffectType == 0x01, "rigid mode on the right trigger");

    expect(dualSenseFillPreviewReport(DualSensePreviewVibration, &report), "vibration preview");
    expect(report.leftTriggerEffectType == 0x06, "vibration mode");
    expect(report.leftTriggerEffect[0] == 15 && report.leftTriggerEffect[1] == 63 &&
               report.leftTriggerEffect[2] == 128,
           "vibration parameters");

    expect(dualSenseFillPreviewReport(DualSensePreviewOff, &report), "off preview");
    expect(report.leftTriggerEffectType == 0x05, "clear effect");

    expect(dualSenseNextTriggerPreview(DualSensePreviewFollowHost) == DualSensePreviewOff, "cycle to off");
    expect(dualSenseNextTriggerPreview(DualSensePreviewOff) == DualSensePreviewRigid, "cycle to rigid");
    expect(dualSenseNextTriggerPreview(DualSensePreviewRigid) == DualSensePreviewVibration, "cycle to vibration");
    expect(dualSenseNextTriggerPreview(DualSensePreviewVibration) == DualSensePreviewFollowHost, "cycle back");
}

static void testHostPacket()
{
    uint8_t payload[kDualSenseAdaptivePacketSize];
    std::memset(payload, 0, sizeof(payload));
    payload[0] = 0x02; // controller 2
    payload[1] = 0x00;
    payload[2] = 0x0C; // both triggers
    payload[3] = 0x21; // left mode
    payload[4] = 0x26; // right mode
    payload[5] = 0x11; // left[0]
    payload[15] = 0x22; // right[0]

    DualSenseAdaptivePacket packet;
    expect(dualSenseParseAdaptivePacket(payload, sizeof(payload), &packet), "parse 0x5503 payload");
    expect(!dualSenseParseAdaptivePacket(payload, 10, &packet), "reject a short payload");
    expect(packet.controllerNumber == 2, "controller number");
    expect(packet.eventFlags == 0x0C && packet.typeLeft == 0x21 && packet.typeRight == 0x26, "modes");
    expect(packet.left[0] == 0x11 && packet.right[0] == 0x22, "parameters");
    expect(kDualSenseEffectParamSize == DS_EFFECT_PAYLOAD_SIZE, "payload size matches Limelight.h");

    DualSenseOutputReport report;
    dualSenseFillHostReport(&packet, &report);
    expect(report.validFlag0 == 0x0C, "host flags become the HID enable bits");
    expect(report.leftTriggerEffectType == 0x21 && report.leftTriggerEffect[0] == 0x11, "left effect");
    expect(report.rightTriggerEffectType == 0x26 && report.rightTriggerEffect[0] == 0x22, "right effect");

    char line[128];
    dualSenseFormatTriggerLine(line, (int)sizeof(line), DualSensePreviewFollowHost, false, 0, 0);
    expect(std::strstr(line, "no host packet yet") != nullptr, "idle trigger line");
    dualSenseFormatTriggerLine(line, (int)sizeof(line), DualSensePreviewFollowHost, true, 0x21, 0x26);
    expect(std::strstr(line, "L=0x21") != nullptr && std::strstr(line, "R=0x26") != nullptr, "host trigger line");
    dualSenseFormatTriggerLine(line, (int)sizeof(line), DualSensePreviewRigid, true, 0x21, 0x26);
    expect(std::strstr(line, "rigid") != nullptr, "preview trigger line");
}

static void testOverlay()
{
    GamepadVizPad pad;
    std::memset(&pad, 0, sizeof(pad));
    pad.present = true;
    pad.playerIndex = 0;
    pad.buttons = A_FLAG | LB_FLAG;
    pad.lsX = 16384;
    pad.lsY = -16384;
    pad.lt = 255;
    pad.rt = 0;

    char text[1024];
    expect(formatGamepadOverlay(text, (int)sizeof(text), &pad, 1, "triggers: follow host (no host packet yet)"),
           "format overlay");
    expect(std::strstr(text, "P1") != nullptr, "player label");
    expect(std::strstr(text, "[A/Cross]") != nullptr, "pressed face button is bracketed");
    expect(std::strstr(text, "[LB]") != nullptr, "pressed shoulder is bracketed");
    expect(std::strstr(text, "B/Circle") != nullptr && std::strstr(text, "[B/Circle]") == nullptr,
           "released face button is not bracketed");
    expect(std::strstr(text, "LT 255 [##########]") != nullptr, "full left trigger bar");
    expect(std::strstr(text, "RT   0 [----------]") != nullptr, "empty right trigger bar");
    expect(std::strstr(text, "LS x=+0.50 y=-0.50") != nullptr, "stick viz");
    expect(std::strstr(text, "triggers: follow host") != nullptr, "trigger line is included");

    expect(formatGamepadOverlay(text, (int)sizeof(text), nullptr, 0, "triggers: off (local preview)"),
           "empty overlay");
    expect(std::strstr(text, "No gamepad") != nullptr, "no pad placeholder");
}

int main()
{
    testCrcAndReports();
    testPreviewEffects();
    testHostPacket();
    testOverlay();
    if (g_failures != 0) {
        std::fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    std::printf("dualsense effects tests passed\n");
    return 0;
}

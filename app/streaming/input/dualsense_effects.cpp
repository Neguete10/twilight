#include "dualsense_effects.h"

#include <stdio.h>
#include <string.h>

static_assert(sizeof(DualSenseOutputReport) == 47, "SDL DualSense effects state is 47 bytes");
static_assert(offsetof(DualSenseOutputReport, rightTriggerEffect) ==
              offsetof(DualSenseOutputReport, rightTriggerEffectType) + 1,
              "trigger mode byte is contiguous with its parameters");

static uint32_t crc32ForByte(uint32_t r)
{
    int i;
    for (i = 0; i < 8; ++i) {
        r = (r & 1 ? 0 : (uint32_t)0xEDB88320L) ^ r >> 1;
    }
    return r ^ (uint32_t)0xFF000000L;
}

uint32_t dualSenseCrc32(uint32_t crc, const uint8_t* data, size_t len)
{
    size_t i;
    for (i = 0; i < len; ++i) {
        crc = crc32ForByte((uint8_t)crc ^ data[i]) ^ crc >> 8;
    }
    return crc;
}

static void writeEffect(uint8_t* type, uint8_t* params, const uint8_t effect[11])
{
    *type = effect[0];
    memcpy(params, effect + 1, kDualSenseEffectParamSize);
}

bool dualSenseParseAdaptivePacket(const uint8_t* data, size_t len, DualSenseAdaptivePacket* out)
{
    if (data == nullptr || out == nullptr || len < (size_t)kDualSenseAdaptivePacketSize) {
        return false;
    }

    memset(out, 0, sizeof(*out));
    out->controllerNumber = (uint16_t)(data[0] | (data[1] << 8));
    out->eventFlags = data[2];
    out->typeLeft = data[3];
    out->typeRight = data[4];
    memcpy(out->left, data + 5, kDualSenseEffectParamSize);
    memcpy(out->right, data + 15, kDualSenseEffectParamSize);
    return true;
}

void dualSenseFillHostReport(const DualSenseAdaptivePacket* packet, DualSenseOutputReport* report)
{
    memset(report, 0, sizeof(*report));
    if (packet == nullptr) {
        return;
    }

    report->validFlag0 = (uint8_t)(packet->eventFlags & (0x04 | 0x08));
    report->leftTriggerEffectType = packet->typeLeft;
    report->rightTriggerEffectType = packet->typeRight;
    memcpy(report->leftTriggerEffect, packet->left, kDualSenseEffectParamSize);
    memcpy(report->rightTriggerEffect, packet->right, kDualSenseEffectParamSize);
}

bool dualSenseFillPreviewReport(int previewMode, DualSenseOutputReport* report)
{
    // Same three effects SDL's testgamecontroller cycles on the mic button.
    static const uint8_t kOff[11] = {0x05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    static const uint8_t kRigid[11] = {0x01, 0, 110, 0, 0, 0, 0, 0, 0, 0, 0};
    static const uint8_t kVibration[11] = {0x06, 15, 63, 128, 0, 0, 0, 0, 0, 0, 0};
    const uint8_t* effect = nullptr;

    memset(report, 0, sizeof(*report));
    switch (previewMode) {
    case DualSensePreviewOff:
        effect = kOff;
        break;
    case DualSensePreviewRigid:
        effect = kRigid;
        break;
    case DualSensePreviewVibration:
        effect = kVibration;
        break;
    default:
        return false;
    }

    report->validFlag0 = 0x04 | 0x08;
    writeEffect(&report->rightTriggerEffectType, report->rightTriggerEffect, effect);
    writeEffect(&report->leftTriggerEffectType, report->leftTriggerEffect, effect);
    return true;
}

int dualSenseNextTriggerPreview(int previewMode)
{
    if (previewMode < DualSensePreviewFollowHost || previewMode >= DualSensePreviewCount - 1) {
        return DualSensePreviewFollowHost;
    }
    return previewMode + 1;
}

const char* dualSenseTriggerPreviewLabel(int previewMode)
{
    switch (previewMode) {
    case DualSensePreviewOff:
        return "off (local preview)";
    case DualSensePreviewRigid:
        return "rigid (local preview)";
    case DualSensePreviewVibration:
        return "vibration (local preview)";
    default:
        return "follow host";
    }
}

void dualSenseFormatTriggerLine(char* out, int outSize, int previewMode,
                                bool sawHostPacket, uint8_t typeLeft, uint8_t typeRight)
{
    if (out == nullptr || outSize <= 0) {
        return;
    }

    if (previewMode == DualSensePreviewFollowHost && sawHostPacket) {
        snprintf(out, (size_t)outSize, "triggers: follow host (last L=0x%02X R=0x%02X)",
                 typeLeft, typeRight);
    }
    else if (previewMode == DualSensePreviewFollowHost) {
        snprintf(out, (size_t)outSize, "triggers: follow host (no host packet yet)");
    }
    else {
        snprintf(out, (size_t)outSize, "triggers: %s", dualSenseTriggerPreviewLabel(previewMode));
    }
}

DualSenseHidReport dualSenseBuildHidReport(bool bluetooth, const DualSenseOutputReport* effect)
{
    DualSenseHidReport report;
    memset(&report, 0, sizeof(report));
    if (effect == nullptr) {
        return report;
    }

    if (!bluetooth) {
        report.data[0] = 0x02;
        memcpy(report.data + 1, effect, sizeof(*effect));
        report.size = kDualSenseUsbOutputReportSize;
        return report;
    }

    report.data[0] = 0x31;
    report.data[1] = 0x02;
    memcpy(report.data + 2, effect, sizeof(*effect));
    report.size = kDualSenseBtOutputReportSize;

    uint8_t header = 0xA2;
    uint32_t crc = dualSenseCrc32(0, &header, 1);
    crc = dualSenseCrc32(crc, report.data, (size_t)(report.size - 4));
    memcpy(report.data + report.size - 4, &crc, 4);
    return report;
}

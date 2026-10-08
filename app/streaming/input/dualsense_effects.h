#pragma once

#include <stdint.h>
#include <stddef.h>

// 47-byte DualSense effects state passed to SDL_GameControllerSendEffect.
// Layout matches SDL's DS5EffectsState_t (mode byte + 10 parameters per
// trigger). The Sunshine packet splits that 11-byte region into type +
// DS_EFFECT_PAYLOAD_SIZE (10) parameter bytes.
static const int kDualSenseEffectParamSize = 10;

struct DualSenseOutputReport {
    uint8_t validFlag0;
    uint8_t validFlag1;
    uint8_t motorRight;
    uint8_t motorLeft;
    uint8_t reserved[4];
    uint8_t muteButtonLed;
    uint8_t powerSaveControl;
    uint8_t rightTriggerEffectType;
    uint8_t rightTriggerEffect[kDualSenseEffectParamSize];
    uint8_t leftTriggerEffectType;
    uint8_t leftTriggerEffect[kDualSenseEffectParamSize];
    uint8_t reserved2[6];
    uint8_t validFlag2;
    uint8_t reserved3[2];
    uint8_t lightbarSetup;
    uint8_t ledBrightness;
    uint8_t playerLeds;
    uint8_t lightbarRed;
    uint8_t lightbarGreen;
    uint8_t lightbarBlue;
};

enum DualSenseTriggerPreview {
    DualSensePreviewFollowHost = 0,
    DualSensePreviewOff,
    DualSensePreviewRigid,
    DualSensePreviewVibration,
    DualSensePreviewCount
};

// Parsed 0x5503 payload, after the control header has been removed.
struct DualSenseAdaptivePacket {
    uint16_t controllerNumber;
    uint8_t eventFlags;
    uint8_t typeLeft;
    uint8_t typeRight;
    uint8_t left[kDualSenseEffectParamSize];
    uint8_t right[kDualSenseEffectParamSize];
};

static const int kDualSenseAdaptivePacketSize = 25;
static const int kDualSenseUsbOutputReportSize = 48;
static const int kDualSenseBtOutputReportSize = 78;

struct DualSenseHidReport {
    uint8_t data[kDualSenseBtOutputReportSize];
    int size;
};

uint32_t dualSenseCrc32(uint32_t crc, const uint8_t* data, size_t len);

// Returns false when the buffer is shorter than the Sunshine payload.
bool dualSenseParseAdaptivePacket(const uint8_t* data, size_t len, DualSenseAdaptivePacket* out);

void dualSenseFillHostReport(const DualSenseAdaptivePacket* packet, DualSenseOutputReport* report);

// Preview modes other than follow-host fill both triggers. Follow-host
// leaves the report zeroed and returns false.
bool dualSenseFillPreviewReport(int previewMode, DualSenseOutputReport* report);

int dualSenseNextTriggerPreview(int previewMode);
const char* dualSenseTriggerPreviewLabel(int previewMode);

// triggerLine is a complete "triggers: ..." sentence, or null.
void dualSenseFormatTriggerLine(char* out, int outSize, int previewMode,
                                bool sawHostPacket, uint8_t typeLeft, uint8_t typeRight);

// USB report id 0x02 (48 bytes) or Bluetooth report id 0x31 (78 bytes,
// SDL CRC32 over 0xA2 || report-without-crc).
DualSenseHidReport dualSenseBuildHidReport(bool bluetooth, const DualSenseOutputReport* effect);

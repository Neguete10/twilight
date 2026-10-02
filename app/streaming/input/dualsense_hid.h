#pragma once

#include "dualsense_effects.h"

// macOS writes a DualSense output report when SDL_GameControllerSendEffect
// is missing or rejects the effect. Other platforms return false.
class DualSenseHidOutput {
public:
    DualSenseHidOutput();
    ~DualSenseHidOutput();

    // serial is SDL_GameControllerGetSerial(), or null. A matching serial
    // wins. Otherwise the only connected DualSense is used.
    bool send(const DualSenseOutputReport& report, const char* serial);

private:
    struct Impl;
    Impl* m_Impl;
};

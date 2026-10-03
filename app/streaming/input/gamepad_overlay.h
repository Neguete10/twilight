#pragma once

// One attached pad, in Moonlight button-flag space (A_FLAG and friends).
struct GamepadVizPad {
    bool present;
    int playerIndex;
    int buttons;
    short lsX;
    short lsY;
    short rsX;
    short rsY;
    unsigned char lt;
    unsigned char rt;
};

// Multi-line stream overlay. triggerLine is appended as its own line.
// Returns false when outSize is too small to hold the text.
bool formatGamepadOverlay(char* out, int outSize,
                          const GamepadVizPad* pads, int padCount,
                          const char* triggerLine);

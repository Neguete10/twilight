#include "gamepad_overlay.h"

#include <Limelight.h>

#include <stdio.h>
#include <string.h>

struct NamedButton {
    int flag;
    const char* label;
};

static const NamedButton kButtons[] = {
    {A_FLAG, "A/Cross"},
    {B_FLAG, "B/Circle"},
    {X_FLAG, "X/Square"},
    {Y_FLAG, "Y/Triangle"},
    {LB_FLAG, "LB"},
    {RB_FLAG, "RB"},
    {UP_FLAG, "U"},
    {DOWN_FLAG, "D"},
    {LEFT_FLAG, "L"},
    {RIGHT_FLAG, "R"},
    {LS_CLK_FLAG, "L3"},
    {RS_CLK_FLAG, "R3"},
    {BACK_FLAG, "Back"},
    {PLAY_FLAG, "Start"},
    {SPECIAL_FLAG, "PS"},
    {TOUCHPAD_FLAG, "Touch"},
    {MISC_FLAG, "Mic"},
};

static int append(char* out, int outSize, int used, const char* text)
{
    int n;
    if (used < 0 || used >= outSize) {
        return -1;
    }
    n = snprintf(out + used, (size_t)(outSize - used), "%s", text);
    if (n < 0 || used + n >= outSize) {
        return -1;
    }
    return used + n;
}

static int appendStick(char* out, int outSize, int used, const char* name, short x, short y)
{
    char buf[64];
    snprintf(buf, sizeof(buf), "%s x=%+.2f y=%+.2f",
             name, x / 32767.0, y / 32767.0);
    return append(out, outSize, used, buf);
}

static int appendTrigger(char* out, int outSize, int used, const char* name, unsigned char value)
{
    char buf[32];
    int filled = (value * 10 + 254) / 255;
    int i;
    if (filled > 10) {
        filled = 10;
    }
    snprintf(buf, sizeof(buf), "%s %3u [", name, value);
    used = append(out, outSize, used, buf);
    if (used < 0) {
        return -1;
    }
    for (i = 0; i < 10; i++) {
        used = append(out, outSize, used, i < filled ? "#" : "-");
        if (used < 0) {
            return -1;
        }
    }
    return append(out, outSize, used, "]");
}

static int appendPad(char* out, int outSize, int used, const GamepadVizPad* pad)
{
    char header[32];
    int i;

    snprintf(header, sizeof(header), "P%d  ", pad->playerIndex + 1);
    used = append(out, outSize, used, header);
    used = appendTrigger(out, outSize, used, "LT", pad->lt);
    used = append(out, outSize, used, "  ");
    used = appendTrigger(out, outSize, used, "RT", pad->rt);
    used = append(out, outSize, used, "\n    ");
    used = appendStick(out, outSize, used, "LS", pad->lsX, pad->lsY);
    used = append(out, outSize, used, "  ");
    used = appendStick(out, outSize, used, "RS", pad->rsX, pad->rsY);
    used = append(out, outSize, used, "\n    ");
    if (used < 0) {
        return -1;
    }

    for (i = 0; i < (int)(sizeof(kButtons) / sizeof(kButtons[0])); i++) {
        char token[40];
        bool down = (pad->buttons & kButtons[i].flag) != 0;
        if (i > 0) {
            used = append(out, outSize, used, " ");
            if (used < 0) {
                return -1;
            }
        }
        if (down) {
            snprintf(token, sizeof(token), "[%s]", kButtons[i].label);
        }
        else {
            snprintf(token, sizeof(token), "%s", kButtons[i].label);
        }
        used = append(out, outSize, used, token);
        if (used < 0) {
            return -1;
        }
    }

    return append(out, outSize, used, "\n");
}

bool formatGamepadOverlay(char* out, int outSize,
                          const GamepadVizPad* pads, int padCount,
                          const char* triggerLine)
{
    int used = 0;
    int shown = 0;
    int i;

    if (out == nullptr || outSize < 2) {
        return false;
    }
    out[0] = 0;

    if (pads != nullptr) {
        for (i = 0; i < padCount; i++) {
            if (!pads[i].present) {
                continue;
            }
            used = appendPad(out, outSize, used, &pads[i]);
            if (used < 0) {
                return false;
            }
            shown++;
        }
    }

    if (shown == 0) {
        used = append(out, outSize, used, "No gamepad\n");
        if (used < 0) {
            return false;
        }
    }

    if (triggerLine != nullptr && triggerLine[0] != 0) {
        used = append(out, outSize, used, triggerLine);
        if (used < 0) {
            return false;
        }
    }
    return true;
}

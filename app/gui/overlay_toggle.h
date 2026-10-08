#pragma once

// Which performance overlays Ctrl+Alt+Shift+S (and the gamepad stats
// combo) should flip. A setting that is off is not part of the toggle,
// so the shortcut cannot turn on an overlay the user did not enable.
// When both are enabled, one press flips both.

enum OverlayToggleTarget
{
    OverlayToggleNone = 0,
    OverlayToggleClassic = 1 << 0,
    OverlayToggleTwilight = 1 << 1,
};

inline int performanceOverlayToggleTargets(bool classicEnabled, bool twilightEnabled)
{
    int targets = OverlayToggleNone;
    if (classicEnabled) {
        targets |= OverlayToggleClassic;
    }
    if (twilightEnabled) {
        targets |= OverlayToggleTwilight;
    }
    return targets;
}

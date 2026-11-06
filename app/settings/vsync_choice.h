#pragma once

// Present-mode numbers match StreamingPreferences::PresentMode. This header
// stays free of Qt so the load rule can be compiled in CI by itself.

namespace VsyncChoice {

constexpr int kPresentAuto = 0;
constexpr int kPresentFixed = 1;
constexpr int kPresentVrr = 2;
constexpr int kPresentNoVsync = 3;

// Settings > Video stores the switch in the "vsync" key. presentMode is a
// separate renderer request. Auto is both the default and the mode that
// still picks variable refresh in fullscreen on an external VRR display, so
// it must not be read back as "V-Sync on".
//
// An explicit vsync key always wins, for every present mode. If the key has
// never been written, an explicit no-vsync present mode still starts the
// switch off. Every other present mode keeps the caller's default.
inline bool loadedEnableVsync(bool savedEnableVsync, bool vsyncKeyPresent, int presentMode)
{
    if (vsyncKeyPresent) {
        return savedEnableVsync;
    }
    if (presentMode == kPresentNoVsync) {
        return false;
    }
    return savedEnableVsync;
}

}

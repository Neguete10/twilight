#include "gui/overlay_toggle.h"

#include <cstdio>

static int g_Failures = 0;

static void expect(bool ok, const char* label)
{
    if (!ok) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

int main()
{
    expect(performanceOverlayToggleTargets(false, false) == OverlayToggleNone,
           "both off toggles nothing");
    expect(performanceOverlayToggleTargets(true, false) == OverlayToggleClassic,
           "classic only");
    expect(performanceOverlayToggleTargets(false, true) == OverlayToggleTwilight,
           "twilight only");
    expect(performanceOverlayToggleTargets(true, true) ==
               (OverlayToggleClassic | OverlayToggleTwilight),
           "both enabled toggles both");

    if (g_Failures != 0) {
        std::printf("%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}

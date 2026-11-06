#include "vsync_choice.h"

#include <cstdio>

using namespace VsyncChoice;

static int g_Failures = 0;

static void expect(bool condition, const char* label)
{
    if (!condition) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

int main()
{
    // The reported plist has vsync written explicitly. Auto is the default
    // present mode, and it used to force the switch back on at the next launch.
    expect(!loadedEnableVsync(false, true, kPresentAuto), "saved off stays off under Auto");
    expect(!loadedEnableVsync(false, true, kPresentFixed), "Fixed does not rewrite a saved off");
    expect(!loadedEnableVsync(false, true, kPresentVrr), "VRR does not rewrite a saved off");
    expect(!loadedEnableVsync(false, true, kPresentNoVsync), "No V-Sync keeps a saved off");

    expect(loadedEnableVsync(true, true, kPresentAuto), "saved on stays on under Auto");
    expect(loadedEnableVsync(true, true, kPresentFixed), "saved on stays on under Fixed");
    expect(loadedEnableVsync(true, true, kPresentVrr), "saved on stays on under VRR");
    expect(loadedEnableVsync(true, true, kPresentNoVsync), "saved on is not cleared by No V-Sync");

    // A plist that never had the vsync key still defaults on, except when an
    // explicit no-vsync present mode was the only record of the choice.
    expect(loadedEnableVsync(true, false, kPresentAuto), "missing key with Auto keeps the default on");
    expect(loadedEnableVsync(true, false, kPresentFixed), "missing key with Fixed keeps the default on");
    expect(loadedEnableVsync(true, false, kPresentVrr), "missing key with VRR keeps the default on");
    expect(!loadedEnableVsync(true, false, kPresentNoVsync), "missing key with No V-Sync starts off");

    if (g_Failures != 0) {
        std::printf("%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}

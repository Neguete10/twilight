#include "gui/streamhudplace.h"

#include <cmath>
#include <cstdio>

static int g_Failures = 0;

static void expectPlace(TwilightHudPlace actual, bool ok, double x, double y, const char* label)
{
    if (actual.ok != ok || (ok && (std::fabs(actual.x - x) > 0.01 || std::fabs(actual.y - y) > 0.01))) {
        std::printf("FAIL %s: got ok=%d %.2f,%.2f expected ok=%d %.2f,%.2f\n",
                    label,
                    actual.ok ? 1 : 0,
                    actual.x,
                    actual.y,
                    ok ? 1 : 0,
                    x,
                    y);
        g_Failures++;
    }
}

int main()
{
    // 1920x1080 with the origin at the bottom-left of the primary screen.
    // 220x44 chips sit on the top edge, 28pt down, centered.
    expectPlace(twilightPlaceHud(0, 0, 1920, 1080, 220, 44),
                true, 850, 1008, "1080p top center");

    // Picture-in-picture is short, so the margin is 8. 640x360 at (1260, 700).
    expectPlace(twilightPlaceHud(1260, 700, 640, 360, 220, 44),
                true, 1470, 1008, "pip");

    // A display to the left of the primary screen has a negative origin.
    expectPlace(twilightPlaceHud(-1920, 0, 1920, 1080, 200, 40),
                true, -1060, 1012, "left display");

    // HUD wider than the stream stays on the stream's left edge.
    expectPlace(twilightPlaceHud(100, 100, 80, 600, 200, 44),
                true, 100, 628, "wider than stream");

    expectPlace(twilightPlaceHud(0, 0, 0, 0, 200, 44),
                false, 0, 0, "empty stream");
    expectPlace(twilightPlaceHud(0, 0, 1920, 1080, 0, 0),
                false, 0, 0, "empty hud");

    // SDL and Qt use a top-left origin. 220x44 chips sit 28pt below the
    // top of a 1080p stream, centered.
    expectPlace(twilightPlaceHudTopLeft(0, 0, 1920, 1080, 220, 44),
                true, 850, 28, "1080p qt");
    expectPlace(twilightPlaceHudTopLeft(1260, 700, 640, 360, 220, 44),
                true, 1470, 708, "pip qt");
    expectPlace(twilightPlaceHudTopLeft(100, 100, 80, 600, 200, 44),
                true, 100, 128, "wider than stream qt");
    expectPlace(twilightPlaceHudTopLeft(0, 0, 0, 0, 200, 44),
                false, 0, 0, "empty stream qt");

    if (g_Failures != 0) {
        std::printf("%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}

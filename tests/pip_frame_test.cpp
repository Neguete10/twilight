#include "streaming/mac/pip_frame.h"

#include <cstdio>

static int g_Failures = 0;

static void expectFrame(PipFrame actual, PipFrame expected, const char* label)
{
    if (actual.x != expected.x || actual.y != expected.y ||
            actual.w != expected.w || actual.h != expected.h) {
        std::printf("FAIL %s: got %d,%d %dx%d, expected %d,%d %dx%d\n",
                    label,
                    actual.x, actual.y, actual.w, actual.h,
                    expected.x, expected.y, expected.w, expected.h);
        g_Failures++;
    }
}

int main()
{
    // 16:9 on a 1080p work area. 640x360 sits in the bottom-right with a
    // 20pt margin. 640 is under the width cap (768) and 360 is under the
    // height cap (486).
    expectFrame(suggestPictureInPictureFrame({0, 0, 1920, 1080}, 1920, 1080),
                {1260, 700, 640, 360},
                "16:9 1080p");

    // Same aspect when the stream size is unknown.
    expectFrame(suggestPictureInPictureFrame({0, 0, 1920, 1080}, 0, 0),
                {1260, 700, 640, 360},
                "unknown aspect");

    // Second display: the usable origin is not the global origin.
    expectFrame(suggestPictureInPictureFrame({1920, 0, 1920, 1080}, 16, 9),
                {3180, 700, 640, 360},
                "second display");

    // Ultrawide stream on a 1512-wide work area. The two-fifths cap is
    // 604, so the 640 target shrinks. 604 * 1440 / 3440 = 252.
    expectFrame(suggestPictureInPictureFrame({0, 0, 1512, 982}, 3440, 1440),
                {888, 710, 604, 252},
                "ultrawide");

    // Portrait stream hits the 45% height cap (486) and the width shrinks.
    // 486 * 1080 / 1920 = 273.
    expectFrame(suggestPictureInPictureFrame({0, 0, 1920, 1080}, 1080, 1920),
                {1627, 574, 273, 486},
                "portrait");

    // 1000px wide: the two-fifths cap is 400, so the 480 target shrinks.
    // 400 * 9 / 16 = 225. Origin is not zero.
    expectFrame(suggestPictureInPictureFrame({100, 50, 1000, 800}, 16, 9),
                {680, 605, 400, 225},
                "narrow display");

    // Work area smaller than the margin. Use the whole area, no pad.
    // maxW = 12, maxH = 13, 12 * 9 / 16 = 6.
    expectFrame(suggestPictureInPictureFrame({0, 0, 30, 30}, 16, 9),
                {18, 24, 12, 6},
                "tiny display");

    expectFrame(suggestPictureInPictureFrame({0, 0, 0, 100}, 16, 9),
                {0, 0, 0, 0},
                "empty width");
    expectFrame(suggestPictureInPictureFrame({5, 5, 100, 0}, 16, 9),
                {0, 0, 0, 0},
                "empty height");

    if (g_Failures != 0) {
        std::printf("%d picture-in-picture frame tests failed\n", g_Failures);
        return 1;
    }
    std::printf("picture-in-picture frame tests passed\n");
    return 0;
}

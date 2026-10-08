#include "streaming/video/auto_codec.h"

#include <cstdio>

static int g_Failures = 0;

static void expect(bool ok, const char* label)
{
    if (!ok) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static void expectOrder(bool av1Hardware, bool hevcHardware, bool keepHevc,
                        int first, int second, int third, const char* label)
{
    int order[3] = {0, 0, 0};
    automaticCodecPriority(av1Hardware, hevcHardware, keepHevc, order);
    expect(order[0] == first && order[1] == second && order[2] == third, label);
}

int main()
{
    expect(!automaticOffersPyroWave(), "automatic never offers PyroWave");
    expect(!automaticDeprioritizesAv1(true), "hardware AV1 stays in front");
    expect(automaticDeprioritizesAv1(false), "software AV1 is deprioritized");

    expectOrder(true, true, false, AutoCodecAv1, AutoCodecHevc, AutoCodecH264,
                "AV1 hardware and HEVC hardware: AV1, HEVC, H.264");
    expectOrder(true, false, false, AutoCodecAv1, AutoCodecH264, AutoCodecHevc,
                "AV1 hardware without HEVC hardware: AV1, H.264, HEVC");
    expectOrder(false, true, false, AutoCodecHevc, AutoCodecH264, AutoCodecAv1,
                "no AV1 hardware with HEVC hardware: HEVC, H.264, AV1");
    expectOrder(false, false, false, AutoCodecH264, AutoCodecHevc, AutoCodecAv1,
                "neither hardware decoder: H.264, HEVC, AV1");
    expectOrder(false, false, true, AutoCodecHevc, AutoCodecH264, AutoCodecAv1,
                "forced software HDR keeps HEVC ahead of H.264");

    if (g_Failures != 0) {
        std::printf("%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}

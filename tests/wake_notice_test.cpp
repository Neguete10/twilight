#include "wake_notice.h"

#include <cstdio>
#include <cstring>

static int g_Failures = 0;

static void expect(bool ok, const char* label)
{
    if (!ok) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static void testSentNotice()
{
    const char* text = wakePacketNotice(WakePacketSent);
    expect(text != nullptr && std::strcmp(text, "Wake packet sent") == 0, "sent confirmation");
}

static void testFailedNotice()
{
    const char* text = wakePacketNotice(WakePacketFailed);
    expect(text != nullptr && std::strcmp(text, "Unable to send the wake packet.") == 0, "failed confirmation");
    expect(std::strcmp(text, "Wake packet sent") != 0, "failure does not claim the packet was sent");
}

static void testNoNoticeUnlessSent()
{
    const char* skipped = wakePacketNotice(WakePacketSkipped);
    const char* unknown = wakePacketNotice(99);
    expect(skipped != nullptr && skipped[0] == '\0', "skipped send has no confirmation");
    expect(unknown != nullptr && unknown[0] == '\0', "unknown outcome has no confirmation");
    expect(std::strcmp(wakePacketNotice(WakePacketSent), "Wake packet sent") == 0, "only a sent packet uses the confirmation");
}

int main()
{
    testSentNotice();
    testFailedNotice();
    testNoNoticeUnlessSent();
    if (g_Failures != 0) {
        std::printf("%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("wake notice ok\n");
    return 0;
}

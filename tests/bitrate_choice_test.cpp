#include "bitrate_choice.h"

#include <cstdio>
#include <string>

using namespace BitrateChoice;

static int g_Failures = 0;

static void expect(bool condition, const char* label)
{
    if (!condition) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static void expectKbps(const char* text, int kbps, const char* label)
{
    const ParseResult parsed = parseMbps(text);
    expect(parsed.accepted && parsed.kbps == kbps, label);
}

static void expectReject(const char* text, const char* label)
{
    const ParseResult parsed = parseMbps(text);
    expect(!parsed.accepted, label);
}

int main()
{
    expectKbps("18.4", 18400, "one decimal");
    expectKbps("18.40", 18400, "trailing zero");
    expectKbps("20", 20000, "whole megabits");
    expectKbps("20.", 20000, "trailing dot");
    expectKbps("0.5", 500, "floor");
    expectKbps(".5", 500, "leading dot");
    expectKbps("500", 500000, "legacy unlimited value is a normal bitrate");
    expectKbps("500.0", 500000, "500 with decimal");
    expectKbps("800", 800000, "wired gigabit is inside the field");
    expectKbps("1000", 1000000, "ceiling");
    expectKbps("1000.0", 1000000, "ceiling with decimal");
    expectKbps("1000.000", 1000000, "ceiling three decimals");
    expectKbps("  12.5 ", 12500, "trimmed");
    expectKbps("18.456", 18456, "three decimals");
    expectKbps("18.4564", 18456, "fourth digit rounds down");
    expectKbps("18.4565", 18457, "fourth digit rounds up");
    expectKbps("18.9996", 19000, "fraction carry");

    expectReject("", "empty");
    expectReject("   ", "blank");
    expectReject(".", "bare dot");
    expectReject("abc", "letters");
    expectReject("18.4.1", "two dots");
    expectReject("-5", "sign");
    expectReject("1e2", "exponent");
    expectReject("0.4", "below floor");
    expectReject("0.499", "just below floor");
    expectReject("1000.001", "just above ceiling");
    expectReject("1001", "above ceiling is not clamped");
    expectReject("0", "zero");

    expect(formatMbps(18400) == "18.4", "format tenth");
    expect(formatMbps(20000) == "20", "format whole");
    expect(formatMbps(18500) == "18.5", "format half");
    expect(formatMbps(18250) == "18.25", "format hundredth");
    expect(formatMbps(18010) == "18.01", "format hundredth with zero");
    expect(formatMbps(500) == "0.5", "format floor");
    expect(formatMbps(500000) == "500", "format the old unlimited value");
    expect(formatMbps(800000) == "800", "format 800");
    expect(formatMbps(1000000) == "1000", "format ceiling");
    expect(formatMbps(2500000) == "2500", "format an old unlocked value above the ceiling");
    expect(formatMbps(1234) == "1.234", "format three places");

    expect(parseMbps(formatMbps(18400)).kbps == 18400, "round trip tenth");
    expect(parseMbps(formatMbps(18250)).kbps == 18250, "round trip hundredth");
    expect(parseMbps(formatMbps(500000)).accepted && parseMbps(formatMbps(500000)).kbps == 500000, "saved 500 Mb/s is still legal");
    expect(parseMbps(formatMbps(2500000)).accepted == false, "saved display above the ceiling is not a new legal value");

    expect(kMaxKbps == 1000000, "slider top is 1 Gbps");
    expect(kLegacyUnlimitedKbps == 500000, "old unlimited value is 500 Mb/s");
    expect(kAbsoluteSendCapKbps == 1500000, "send cap is 1.5 Gbps");
    expect(kHostBitrateLimitKbps == 500000, "adaptive ceiling stays the host limit");
    expect(kMinKbps == 500, "floor stays 0.5 Mb/s");
    expect(kGfeCapKbps == 100000, "GFE cap stays 100 Mb/s");

    expect(storedBitrateKbps("500000", 0) == 500000, "a stored 500000 loads as 500000");
    expect(storedBitrateKbps("unlimited", 0) == 500000, "the word unlimited loads as 500000");
    expect(storedBitrateKbps("Unlimited", 18400) == 500000, "the word unlimited ignores case");
    expect(storedBitrateKbps("2500000", 0) == 2500000, "old unlocked number is kept");
    expect(storedBitrateKbps("1000000", 0) == 1000000, "stored 1 Gbps is kept");
    expect(storedBitrateKbps("nope", 18400) == 18400, "unreadable prefs use the fallback");
    expect(storedBitrateKbps("", 18400) == 18400, "empty prefs use the fallback");

    expect(bitrateToSendKbps(800000) == 800000, "a typed value is sent as typed");
    expect(bitrateToSendKbps(500000) == 500000, "typed 500 Mb/s is sent as 500 Mb/s");
    expect(bitrateToSendKbps(2500000) == 1500000, "an old unlocked value is capped at 1.5 Gbps");
    expect(bitrateToSendKbps(100) == 100, "a stored low number is not raised");
    expect(bitrateToSendKbps(-5) == 0, "a negative stored number sends nothing");

    expect(sunshineConfiguredKbps(20000) == 20000, "sunshine gets the typed number");
    expect(sunshineConfiguredKbps(500000) == 500000, "sunshine gets a kept 500 Mb/s");
    expect(sunshineConfiguredKbps(1000000) == 1000000, "sunshine gets 1 Gbps");
    expect(sunshineConfiguredKbps(800000) == 800000, "sunshine is not clamped by this client");

    expect(estimatedEncoderTargetKbps(20000) == 16000, "encoder target is 80 percent");
    expect(estimatedEncoderTargetKbps(1000000) == 800000, "1 Gbps request estimates 800 Mb/s");
    expect(estimatedEncoderTargetKbps(0) == 0, "no request has no target");
    const std::string overlay = formatBitrateOverlay(1000000, 74.0);
    expect(overlay == "1000.0 Mbps requested, 800.0 Mbps estimated encoder target, 74.0 Mbps measured", "overlay lists requested, estimated target, measured");
    const std::string adaptiveOverlay = formatBitrateOverlay(1000000, 74.0, 350000);
    expect(adaptiveOverlay == "1000.0 Mbps requested, 800.0 Mbps estimated encoder target, 74.0 Mbps measured, 350.0 Mbps adaptive", "overlay can add the adaptive target");

    expect(adaptiveBitrateCeilingKbps(20000) == 20000, "adaptive ceiling is the user bitrate");
    expect(adaptiveBitrateCeilingKbps(500000) == 500000, "adaptive ceiling allows the host limit");
    expect(adaptiveBitrateCeilingKbps(1000000) == 500000, "adaptive ceiling does not follow the 1 Gbps slider");

    expect(gfeLocalInitialKbps(20000) == 16000, "local GFE keeps the 80 percent FEC budget");
    expect(gfeLocalInitialKbps(100000) == 80000, "100 Mb/s request is under the GFE cap after FEC");
    expect(gfeLocalInitialKbps(150000) == 100000, "150 Mb/s local hits the GFE cap");
    expect(gfeLocalInitialKbps(500000) == 100000, "500 Mb/s still encodes at 100 Mb/s on GFE");
    expect(gfeLocalInitialKbps(1000000) == 100000, "1 Gbps still encodes at 100 Mb/s on GFE");
    expect(gfeRemoteInitialKbps(20000) == 15500, "remote GFE subtracts 500 kbps");
    expect(gfeRemoteInitialKbps(500) == 400, "remote budget under 500 kbps is not reduced again");
    expect(gfeRemoteInitialKbps(1000000) == 100000, "remote 1 Gbps hits the same GFE cap");

    if (g_Failures != 0) {
        std::printf("%d failed\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}

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
    expectKbps("500", 500000, "ceiling");
    expectKbps("500.0", 500000, "ceiling with decimal");
    expectKbps("500.000", 500000, "ceiling three decimals");
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
    expectReject("500.001", "just above ceiling");
    expectReject("800", "above ceiling is not clamped");
    expectReject("0", "zero");

    expect(formatMbps(18400) == "18.4", "format tenth");
    expect(formatMbps(20000) == "20", "format whole");
    expect(formatMbps(18500) == "18.5", "format half");
    expect(formatMbps(18250) == "18.25", "format hundredth");
    expect(formatMbps(18010) == "18.01", "format hundredth with zero");
    expect(formatMbps(500) == "0.5", "format floor");
    expect(formatMbps(500000) == "500", "format ceiling");
    expect(formatMbps(800000) == "800", "format a saved value above the ceiling");
    expect(formatMbps(1234) == "1.234", "format three places");

    expect(parseMbps(formatMbps(18400)).kbps == 18400, "round trip tenth");
    expect(parseMbps(formatMbps(18250)).kbps == 18250, "round trip hundredth");
    expect(parseMbps(formatMbps(800000)).accepted == false, "saved display is not a new legal value");

    expect(kMaxKbps == 500000, "unlimited is the 500 Mb/s protocol ceiling");
    expect(kMinKbps == 500, "floor stays 0.5 Mb/s");
    expect(kGfeCapKbps == 100000, "GFE cap stays 100 Mb/s");

    expect(sunshineConfiguredKbps(20000) == 20000, "sunshine gets the typed number");
    expect(sunshineConfiguredKbps(500000) == 500000, "sunshine gets unlimited");
    expect(sunshineConfiguredKbps(800000) == 800000, "sunshine is not clamped by this client");

    expect(gfeLocalInitialKbps(20000) == 16000, "local GFE keeps the 80 percent FEC budget");
    expect(gfeLocalInitialKbps(100000) == 80000, "100 Mb/s request is under the GFE cap after FEC");
    expect(gfeLocalInitialKbps(150000) == 100000, "150 Mb/s local hits the GFE cap");
    expect(gfeLocalInitialKbps(500000) == 100000, "unlimited still encodes at 100 Mb/s on GFE");
    expect(gfeRemoteInitialKbps(20000) == 15500, "remote GFE subtracts 500 kbps");
    expect(gfeRemoteInitialKbps(500) == 400, "remote budget under 500 kbps is not reduced again");
    expect(gfeRemoteInitialKbps(500000) == 100000, "remote unlimited hits the same GFE cap");

    if (g_Failures != 0) {
        std::printf("%d failed\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}

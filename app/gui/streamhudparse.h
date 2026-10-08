#pragma once

// Parses the existing Moonlight performance-overlay text into the few numbers
// Twilight's quiet HUD shows. FEC percentages and the long per-stage lines are
// intentionally ignored so PyroWave and H.264/HEVC/AV1 share one chip layout.

struct TwilightHudSample
{
    double fps;
    double bitrateMbps;
    double latencyMs;
    bool hasBitrate;
    bool hasLatency;
    char codec[96];
};

bool twilightParseHudSample(const char* text, TwilightHudSample* out);

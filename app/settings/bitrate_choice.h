#pragma once

#include <cstdint>
#include <cstdio>
#include <string>

// The slider and the typed field accept 0.5 Mb/s through 1 Gbps. There is no
// Unlimited control. A stored 500000 (the old Unlimited value) is kept as
// 500 Mb/s. A stored number outside the field, including the old unlocked
// slider, is kept until the user changes it.
//
// Sunshine reads x-ml-video.configuredBitrateKbps as the user's number. The
// overlay's encoder-target estimate is 80% of that request (the FEC budget).
// It is not the GeForce Experience cap and it is not the adaptive-bitrate cap.
//
// GeForce Experience imposes 100 Mbit/s on maximumBitrateKbps. SdpGenerator.c
// copies that onto the NVIDIA bitrate attributes (after the 80% FEC budget)
// and leaves configuredBitrateKbps alone for Sunshine. That GFE clamp stays.
//
// Adaptive bitrate is separate. Its ceiling is the user's bitrate, and it
// never asks the host for more than 500000 kbps (the host /bitrate limit).

namespace BitrateChoice {

// 0.5 Mb/s. Same floor as the slider, the command line, and network profiles.
constexpr int kMinKbps = 500;

// 1000 Mb/s. Highest value the slider and the typed field accept. Not a silent
// clamp of a larger stored number: callers reject new input above this and
// leave an already-saved higher number untouched until the user changes it.
constexpr int kMaxKbps = 1000000;

// What Unlimited used to store. Loading it keeps 500 Mb/s. It is not remapped
// to the new top of the slider.
constexpr int kLegacyUnlimitedKbps = 500000;

// Host /bitrate limit. Adaptive bitrate may use the user's bitrate only up
// to this. The slider is allowed to go higher.
constexpr int kHostBitrateLimitKbps = 500000;

// SdpGenerator.c caps the NVIDIA x-nv-video bitrate attributes here.
constexpr int kGfeCapKbps = 100000;

// FEC budget shown on the overlay as the estimated encoder target.
constexpr double kEncoderTargetFraction = 0.80;

struct ParseResult {
    bool accepted;
    int kbps;
};

inline std::string trimCopy(const std::string& text)
{
    std::size_t begin = 0;
    while (begin < text.size() && (text[begin] == ' ' || text[begin] == '\t')) {
        begin++;
    }
    std::size_t end = text.size();
    while (end > begin && (text[end - 1] == ' ' || text[end - 1] == '\t')) {
        end--;
    }
    return text.substr(begin, end - begin);
}

// Mbps text, dot as the decimal mark. At most three decimal places are stored
// (1 kbps). A fourth digit rounds. Out of range is rejected, not clamped.
inline ParseResult parseMbps(const std::string& text)
{
    ParseResult rejected = {false, 0};
    const std::string raw = trimCopy(text);
    if (raw.empty()) {
        return rejected;
    }

    std::size_t index = 0;
    if (raw[index] == '.') {
        // ".5" is 0.5. A bare "." is not.
    }

    std::int64_t whole = 0;
    bool sawDigit = false;
    while (index < raw.size() && raw[index] >= '0' && raw[index] <= '9') {
        sawDigit = true;
        whole = whole * 10 + (raw[index] - '0');
        if (whole > 1000000) {
            return rejected;
        }
        index++;
    }

    int frac = 0;
    int places = 0;
    int roundDigit = -1;
    if (index < raw.size() && raw[index] == '.') {
        index++;
        while (index < raw.size() && raw[index] >= '0' && raw[index] <= '9') {
            sawDigit = true;
            if (places < 3) {
                frac = frac * 10 + (raw[index] - '0');
                places++;
            } else if (roundDigit < 0) {
                roundDigit = raw[index] - '0';
            }
            index++;
        }
    }
    if (!sawDigit || index != raw.size()) {
        return rejected;
    }
    while (places < 3) {
        frac *= 10;
        places++;
    }
    if (roundDigit >= 5) {
        frac += 1;
    }
    if (frac >= 1000) {
        whole += 1;
        frac -= 1000;
    }

    const std::int64_t kbps64 = whole * 1000 + frac;
    if (kbps64 < kMinKbps || kbps64 > kMaxKbps) {
        return rejected;
    }
    ParseResult accepted = {true, static_cast<int>(kbps64)};
    return accepted;
}

// Display form of a stored kbps value, including one the field would now
// reject. Trailing zeros after the decimal point are dropped.
inline std::string formatMbps(int kbps)
{
    const bool negative = kbps < 0;
    int value = negative ? -kbps : kbps;
    const int whole = value / 1000;
    int frac = value % 1000;
    std::string text = std::to_string(whole);
    if (frac != 0) {
        text.push_back('.');
        text.push_back(static_cast<char>('0' + (frac / 100) % 10));
        frac %= 100;
        if (frac != 0) {
            text.push_back(static_cast<char>('0' + (frac / 10) % 10));
            frac %= 10;
            if (frac != 0) {
                text.push_back(static_cast<char>('0' + frac));
            }
        }
    }
    if (negative) {
        text.insert(text.begin(), '-');
    }
    return text;
}

// What SdpGenerator puts in x-ml-video.configuredBitrateKbps. Unchanged.
inline int sunshineConfiguredKbps(int kbps)
{
    return kbps;
}

// Local-stream NVIDIA attributes: 80% FEC budget, then the 100 Mb/s GFE cap.
// Matches SdpGenerator.c for STREAM_CFG_LOCAL (no extra 500 kbps subtraction).
inline int gfeLocalInitialKbps(int kbps)
{
    int adjusted = static_cast<int>(kbps * 0.80);
    if (adjusted > kGfeCapKbps) {
        adjusted = kGfeCapKbps;
    }
    return adjusted;
}

// Remote-stream NVIDIA attributes. Same cap, after the extra 500 kbps the
// generator subtracts once the 80% budget is above 500.
inline int gfeRemoteInitialKbps(int kbps)
{
    int adjusted = static_cast<int>(kbps * 0.80);
    if (adjusted > 500) {
        adjusted -= 500;
    }
    if (adjusted > kGfeCapKbps) {
        adjusted = kGfeCapKbps;
    }
    return adjusted;
}

// Overlay estimate only. Not capped by GFE and not capped by the host
// /bitrate limit.
inline int estimatedEncoderTargetKbps(int requestedKbps)
{
    if (requestedKbps <= 0) {
        return 0;
    }
    return static_cast<int>(static_cast<double>(requestedKbps) * kEncoderTargetFraction);
}

// User bitrate, capped at the host's 500000 kbps /bitrate limit.
inline int adaptiveBitrateCeilingKbps(int userKbps)
{
    if (userKbps > kHostBitrateLimitKbps) {
        return kHostBitrateLimitKbps;
    }
    return userKbps;
}

// "100.0 Mbps requested, 80.0 Mbps encoder target, 74.2 Mbps measured"
inline std::string formatBitrateOverlay(int requestedKbps, double measuredMbps)
{
    char buf[192];
    std::snprintf(buf, sizeof(buf),
                  "%.1f Mbps requested, %.1f Mbps encoder target, %.1f Mbps measured",
                  static_cast<double>(requestedKbps) / 1000.0,
                  static_cast<double>(estimatedEncoderTargetKbps(requestedKbps)) / 1000.0,
                  measuredMbps);
    return std::string(buf);
}

inline bool equalsIgnoreCase(const std::string& text, const char* literal)
{
    if (literal == nullptr) {
        return false;
    }
    std::size_t index = 0;
    while (index < text.size() && literal[index] != '\0') {
        char left = text[index];
        char right = literal[index];
        if (left >= 'A' && left <= 'Z') {
            left = static_cast<char>(left - 'A' + 'a');
        }
        if (right >= 'A' && right <= 'Z') {
            right = static_cast<char>(right - 'A' + 'a');
        }
        if (left != right) {
            return false;
        }
        index++;
    }
    return index == text.size() && literal[index] == '\0';
}

// Prefs load. "unlimited" (any case) stays at the old 500 Mb/s value. A
// numeric string is kept even when it is outside the slider. Anything else
// uses fallback. Does not throw.
inline int storedBitrateKbps(const std::string& text, int fallback)
{
    const std::string raw = trimCopy(text);
    if (raw.empty()) {
        return fallback;
    }
    if (equalsIgnoreCase(raw, "unlimited")) {
        return kLegacyUnlimitedKbps;
    }

    std::size_t index = 0;
    bool negative = false;
    if (raw[index] == '+') {
        index++;
    } else if (raw[index] == '-') {
        negative = true;
        index++;
    }
    if (index >= raw.size()) {
        return fallback;
    }

    std::int64_t value = 0;
    for (; index < raw.size(); index++) {
        if (raw[index] < '0' || raw[index] > '9') {
            return fallback;
        }
        value = value * 10 + (raw[index] - '0');
        if (value > 2147483647LL) {
            return fallback;
        }
    }
    if (negative) {
        value = -value;
    }
    return static_cast<int>(value);
}

} // namespace BitrateChoice

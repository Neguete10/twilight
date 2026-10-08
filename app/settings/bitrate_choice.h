#pragma once

#include <cstdint>
#include <string>

// Twilight's bitrate field and the Unlimited control share these limits with
// the stream. The numbers are the ones the host protocol actually accepts.
//
// Sunshine reads x-ml-video.configuredBitrateKbps as the user's number. There
// is no higher numeric ceiling in that attribute. The frame itself is capped
// by the 10-bit FEC packet index (1024 packets per block, 4 blocks) and by
// Reed-Solomon's 255 shards. With the usual 20% FEC and this client's 1392-byte
// LAN packet, one frame holds about 560 Mbit of encoded video at 60 fps.
// Moonlight stops the slider at 500 Mbit/s so a frame stays inside that budget
// at 60 fps and above. Going past it is the 1 Gbit/s case Sunshine's packet
// pacer was not written for, so Unlimited does not raise the cap.
//
// GeForce Experience imposes 100 Mbit/s on maximumBitrateKbps. SdpGenerator.c
// copies that onto the NVIDIA bitrate attributes (after the 80% FEC budget)
// and leaves configuredBitrateKbps alone for Sunshine. That GFE clamp stays.

namespace BitrateChoice {

// 0.5 Mb/s. Same floor as the slider, the command line, and network profiles.
constexpr int kMinKbps = 500;

// 500 Mb/s. Highest value this client will request. Not a silent UI clamp of
// a larger stored number: callers reject new input above this and leave an
// already-saved higher number untouched until the user changes it.
constexpr int kMaxKbps = 500000;

// SdpGenerator.c caps the NVIDIA x-nv-video bitrate attributes here.
constexpr int kGfeCapKbps = 100000;

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

} // namespace BitrateChoice

#include "streamhudparse.h"

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static bool readDoubleBefore(const char* begin, const char* marker, double* out)
{
    if (begin == nullptr || marker == nullptr || marker < begin || out == nullptr) {
        return false;
    }

    const char* end = marker;
    while (end > begin && (end[-1] == ' ' || end[-1] == '\t')) {
        --end;
    }

    const char* start = end;
    while (start > begin && (std::isdigit(static_cast<unsigned char>(start[-1])) || start[-1] == '.')) {
        --start;
    }
    if (start == end) {
        return false;
    }

    char buf[64];
    const size_t n = static_cast<size_t>(end - start);
    if (n >= sizeof(buf)) {
        return false;
    }
    std::memcpy(buf, start, n);
    buf[n] = '\0';

    char* parsedEnd = nullptr;
    const double value = std::strtod(buf, &parsedEnd);
    if (parsedEnd == buf) {
        return false;
    }
    *out = value;
    return true;
}

static void copyTrimmed(char* dest, size_t destLen, const char* begin, const char* end)
{
    if (destLen == 0) {
        return;
    }
    while (begin < end && (*begin == ' ' || *begin == '\t')) {
        ++begin;
    }
    while (end > begin && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r')) {
        --end;
    }
    size_t n = static_cast<size_t>(end - begin);
    if (n >= destLen) {
        n = destLen - 1;
    }
    std::memcpy(dest, begin, n);
    dest[n] = '\0';
}

bool twilightParseHudSample(const char* text, TwilightHudSample* out)
{
    if (out == nullptr) {
        return false;
    }
    std::memset(out, 0, sizeof(*out));
    if (text == nullptr || text[0] == '\0') {
        return false;
    }

    const char* fpsMarker = std::strstr(text, " FPS");
    if (fpsMarker == nullptr || !readDoubleBefore(text, fpsMarker, &out->fps)) {
        return false;
    }

    const char* bitrate = std::strstr(text, "Bitrate:");
    if (bitrate != nullptr) {
        double value = 0.0;
        bool got = false;
        bool isKbps = false;
        // Prefer the measured number when the overlay lists requested, the
        // 0.8x encoder target, and measured. Older lines still use the first number.
        const char* measured = std::strstr(bitrate, "Mbps measured");
        const char* measuredKbps = std::strstr(bitrate, "kbps measured");
        if (measured != nullptr && readDoubleBefore(bitrate, measured, &value)) {
            got = true;
        }
        else if (measuredKbps != nullptr && readDoubleBefore(bitrate, measuredKbps, &value)) {
            got = true;
            isKbps = true;
        }
        else {
            char unit[16];
            unit[0] = '\0';
            if (std::sscanf(bitrate, "Bitrate: %lf %15s", &value, unit) >= 1) {
                got = true;
                if (std::strncmp(unit, "kbps", 4) == 0 || std::strncmp(unit, "Kbps", 4) == 0) {
                    isKbps = true;
                }
            }
        }
        if (got) {
            out->hasBitrate = true;
            out->bitrateMbps = isKbps ? value / 1000.0 : value;
        }
    }

    const char* latencyKey = "Average network latency:";
    const char* latency = std::strstr(text, latencyKey);
    if (latency != nullptr) {
        const char* value = latency + std::strlen(latencyKey);
        while (*value == ' ' || *value == '\t') {
            ++value;
        }
        if (std::strncmp(value, "N/A", 3) != 0) {
            double ms = 0.0;
            if (std::sscanf(value, "%lf", &ms) == 1) {
                out->hasLatency = true;
                out->latencyMs = ms;
            }
        }
    }

    const char* codec = std::strstr(text, "Codec:");
    if (codec != nullptr) {
        codec += 6;
        const char* end = std::strchr(codec, ')');
        if (end == nullptr) {
            end = std::strchr(codec, '\n');
        }
        if (end == nullptr) {
            end = codec + std::strlen(codec);
        }
        copyTrimmed(out->codec, sizeof(out->codec), codec, end);
    }

    return true;
}

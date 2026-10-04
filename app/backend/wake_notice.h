#pragma once

// Result of NvComputer::wake(). The confirmation text is empty unless a
// Wake-on-LAN datagram was actually written.
enum WakePacketOutcome {
    WakePacketSkipped = 0,
    WakePacketSent = 1,
    WakePacketFailed = 2
};

inline const char* wakePacketNotice(int outcome)
{
    if (outcome == WakePacketSent)
        return "Wake packet sent";
    if (outcome == WakePacketFailed)
        return "Unable to send the wake packet.";
    return "";
}

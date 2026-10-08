#include "mic_wire.h"

#include <cstring>

namespace MicWire {

bool buildPacket(uint16_t sequence, const uint8_t* opus, int opusBytes, Packet& packet)
{
    if (opus == nullptr || opusBytes <= 0 || opusBytes > kMaxOpusBytes) {
        return false;
    }

    packet.type = kPacketType;
    packet.length = kHeaderBytes + opusBytes;
    packet.bytes[0] = (uint8_t)((sequence >> 8) & 0xFF);
    packet.bytes[1] = (uint8_t)(sequence & 0xFF);
    packet.bytes[2] = (uint8_t)kWireChannels;
    packet.bytes[3] = 0;
    std::memcpy(packet.bytes + kHeaderBytes, opus, (size_t)opusBytes);
    return true;
}

} // namespace MicWire

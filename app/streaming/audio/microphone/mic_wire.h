#pragma once

#include <cstdint>

// Client-to-host microphone payload used by Vibelight and the Vibepollo
// builds that pair with it.
//
// The bytes below are the ENet control-stream payload, not the encrypted
// envelope. moonlight-common-c wraps them in packet type kPacketType (0x3003)
// via LiSendRawControlStreamPacket(). Stock Moonlight has no microphone
// path. Stock LizardByte Sunshine does not decode 0x3003. The 0x5510
// moonlight-mic header and the separate-UDP LiSendMicrophoneOpusDataEx
// path are different protocols and are not what this builder emits.
//
// Layout, matching xenstalker02/Vibelight miccapture.cpp:
//   [0..1] sequence, big-endian, first packet is 0
//   [2]    channel count, always 1 (mono)
//   [3]    flags, always 0
//   [4..]  one Opus packet, 48 kHz mono, 20 ms (960 samples).
//          DTX is off in this client so a quiet mic still produces packets.
//          Vibepollo opens the Windows device on the first of those packets.
//
// sendMessageEnet() copies `sizeof(NVCTL_ENET_PACKET_HEADER_V2) + paylen`
// into a 256-byte stack buffer and asserts that sum is strictly less than
// 256. The V2 header is 4 bytes, so paylen <= 251. Our 4-byte header sits
// inside that payload, so the Opus packet itself is at most 247 bytes.
// Vibelight's 248-byte ceiling makes paylen 252, which fails that assert.

namespace MicWire {

constexpr uint16_t kPacketType = 0x3003;
constexpr int kSampleRate = 48000;
constexpr int kFrameSamples = 960;
constexpr int kFrameDurationMs = 20;
constexpr int kWireChannels = 1;
constexpr int kHeaderBytes = 4;
constexpr int kOpusBitrate = 64000;
constexpr int kMaxControlPayload = 251;
constexpr int kMaxOpusBytes = kMaxControlPayload - kHeaderBytes;

static_assert(kSampleRate * kFrameDurationMs / 1000 == kFrameSamples,
              "20 ms at 48 kHz is 960 samples");
static_assert(kHeaderBytes + kMaxOpusBytes == kMaxControlPayload,
              "mic header plus opus must fit the control payload");
static_assert(kMaxOpusBytes == 247, "opus ceiling drifted from the 256-byte control buffer");

struct Packet {
    uint16_t type;
    int length;
    uint8_t bytes[kMaxControlPayload];
};

// Returns false when opus is missing or does not fit in the control buffer.
// On success, packet.length is kHeaderBytes + opusBytes and packet.type is
// kPacketType. sequence is written big-endian and is not incremented here.
bool buildPacket(uint16_t sequence, const uint8_t* opus, int opusBytes, Packet& packet);

} // namespace MicWire

#!/usr/bin/env python3
"""Teach moonlight-common-c to send one raw control-stream packet.

The 7feb0a6 pin (upstream f900dd4 plus PyroWave) still has no microphone
sender. Vibelight sends Opus on the encrypted control stream with
LiSendRawControlStreamPacket(). qmake applies this delta in place. It is
idempotent. Do not roll the submodule back, and do not run the PyroWave
or adaptive-trigger protocol scripts: those packets are already in this pin.

Pass a src directory as argv[1] to test the patch against a copy of the
pinned tree. The default path is the submodule src directory.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "moonlight-common-c" / "moonlight-common-c" / "src"


def ensure(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        print(f"already patched {path.name}")
        return
    if old not in text:
        sys.stderr.write(f"{path}: expected text not found and {marker!r} is absent\n")
        sys.exit(1)
    path.write_text(text.replace(old, new, 1))
    print(f"patched {path.name}")


def main() -> None:
    if not SRC.is_dir():
        sys.stderr.write(f"moonlight-common-c sources not checked out: {SRC}\n")
        sys.exit(1)

    ensure(
        SRC / "Limelight.h",
        """uint32_t LiGetHostFeatureFlags(void);

#ifdef __cplusplus
}
#endif
""",
        """uint32_t LiGetHostFeatureFlags(void);

// Sends one already-framed extension payload on the ENet control stream
// (CTRL_CHANNEL_GENERIC, flags 0). Microphone audio uses packet type 0x3003.
// `length` must be 1..251: sendMessageEnet copies the payload into a 256-byte
// stack buffer behind a 4-byte header and asserts sizeof(header) + length < 256.
// Returns 0 on success, -1 if this connection cannot take the packet.
// Only valid between LiStartConnection() and LiStopConnection().
int LiSendRawControlStreamPacket(uint16_t packetType, const void* data, int length);

// True when control messages are AES-GCM encrypted. Microphone audio is not
// sent when this is false, so voice never rides an unencrypted control stream.
bool LiIsControlStreamEncrypted(void);

#ifdef __cplusplus
}
#endif
""",
        "LiSendRawControlStreamPacket",
    )
    ensure(
        SRC / "ControlStream.c",
        """// Called by the input stream to send a packet for Gen 5+ servers
int sendInputPacketOnControlStream(unsigned char* data, int length, uint8_t channelId, uint32_t flags, bool moreData) {
    LC_ASSERT(AppVersionQuad[0] >= 5);

    // Send the input data (no reply expected)
    if (sendMessageAndForget(packetTypes[IDX_INPUT_DATA], length, data, channelId, flags, moreData) == 0) {
        return -1;
    }

    return 0;
}

// Called by the input stream to flush queued packets before a batching wait
""",
        """// Called by the input stream to send a packet for Gen 5+ servers
int sendInputPacketOnControlStream(unsigned char* data, int length, uint8_t channelId, uint32_t flags, bool moreData) {
    LC_ASSERT(AppVersionQuad[0] >= 5);

    // Send the input data (no reply expected)
    if (sendMessageAndForget(packetTypes[IDX_INPUT_DATA], length, data, channelId, flags, moreData) == 0) {
        return -1;
    }

    return 0;
}

// Twilight microphone extension. See scripts/apply_mic_control_packet.py.
// 251 is the largest payload that satisfies sendMessageEnet's
// `sizeof(NVCTL_ENET_PACKET_HEADER_V2) + paylen < 256` assert.
int LiSendRawControlStreamPacket(uint16_t packetType, const void* data, int length) {
    if (AppVersionQuad[0] < 5 || data == NULL || length <= 0 || length > 251) {
        return -1;
    }
    if (!sendMessageAndForget((short)packetType, (short)length, data, CTRL_CHANNEL_GENERIC, 0, false)) {
        return -1;
    }
    return 0;
}

bool LiIsControlStreamEncrypted(void) {
    return encryptedControlStream;
}

// Called by the input stream to flush queued packets before a batching wait
""",
        "LiSendRawControlStreamPacket",
    )


if __name__ == "__main__":
    main()

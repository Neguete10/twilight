#!/usr/bin/env python3
"""Make AudioDec call Twilight's audio renderer directly.

moonlight-common-c loads AudioCallbacks.decodeAndPlaySample and branches
to it on every packet. That slot lives in a process-lifetime global and is
written once, in LiStartConnection. The v6.1.0-twilight crash
(UUID 10BFCCE9-43FD-37A7-85B5-6B8F15DD1145) is AudioDec executing that
slot after it had become a non-executable address: fault PC
0x7b14d6c300, return image offsets 0x1a2798, 0x1a23d4, and ThreadProc+32.

A direct call's target is in the instruction stream, so a later wild
write into the callback struct is not fetched as code. The symbol is
defined by Twilight on every platform (app/streaming/audio/audio.cpp).

Idempotent. Pass a src directory as argv[1] to test against a copy of
the pinned tree. The default path is the submodule src directory.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "moonlight-common-c" / "moonlight-common-c" / "src"

DECLARATION = """
// Twilight: AudioDec calls this instead of AudioCallbacks.decodeAndPlaySample.
// See scripts/apply_audio_decode_direct.py.
void TwilightAudioDecodeAndPlaySample(char* sampleData, int sampleLength);
"""

CALLS = (
    (
        "AudioCallbacks.decodeAndPlaySample(NULL, 0);",
        "TwilightAudioDecodeAndPlaySample(NULL, 0);",
    ),
    (
        "AudioCallbacks.decodeAndPlaySample((char*)decryptedOpusData, dataLength);",
        "TwilightAudioDecodeAndPlaySample((char*)decryptedOpusData, dataLength);",
    ),
    (
        "AudioCallbacks.decodeAndPlaySample((char*)(rtp + 1), packet->header.size - sizeof(*rtp));",
        "TwilightAudioDecodeAndPlaySample((char*)(rtp + 1), packet->header.size - sizeof(*rtp));",
    ),
)


def main() -> None:
    path = SRC / "AudioStream.c"
    if not path.is_file():
        sys.stderr.write(f"moonlight-common-c sources not checked out: {path}\n")
        sys.exit(1)

    text = path.read_text()
    original = text

    if "void TwilightAudioDecodeAndPlaySample(char* sampleData, int sampleLength);" not in text:
        needle = '#include "Limelight-internal.h"\n'
        if needle not in text:
            sys.stderr.write(f"{path}: expected include not found\n")
            sys.exit(1)
        text = text.replace(needle, needle + DECLARATION, 1)

    for old, new in CALLS:
        if old in text:
            text = text.replace(old, new, 1)
        elif new not in text:
            sys.stderr.write(f"{path}: expected call not found: {old}\n")
            sys.exit(1)

    if "AudioCallbacks.decodeAndPlaySample(" in text:
        sys.stderr.write(f"{path}: decodeAndPlaySample is still called indirectly\n")
        sys.exit(1)

    if text == original:
        print(f"already patched {path.name}")
        return

    path.write_text(text)
    print(f"patched {path.name}")


if __name__ == "__main__":
    main()

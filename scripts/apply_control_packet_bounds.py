#!/usr/bin/env python3
"""Give pre-Sunshine control packet tables a slot at index 12.

moonlight-common-c 7feb0a6 defines IDX_DS_ADAPTIVE_TRIGGERS as 12 and
needsAsyncCallback() reads packetTypes[12] on every async check.
packetTypesGen7Enc has that entry (0x5503). Gen3, Gen4, Gen5, and
unencrypted Gen7 stop at the RGB LED slot, index 11. On a GFE host that
read walks off the array.

The extra entry is -1, which matches no packet type. This repo cannot
publish a commit on andygrundman/moonlight-common-c, so qmake applies
the delta. The script is idempotent.

Pass a src directory as argv[1] to test the patch against a copy of the
pinned tree. The default path is the submodule src directory.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "moonlight-common-c" / "moonlight-common-c" / "src"

UNUSED = "    -1,     // Set RGB LED (unused)\n};"
UNUSED_NEW = "    -1,     // Set RGB LED (unused)\n    -1,     // Adaptive triggers (unused)\n};"
MARKER = "Adaptive triggers (unused)"


def main() -> None:
    path = SRC / "ControlStream.c"
    if not path.is_file():
        sys.stderr.write(f"moonlight-common-c sources not checked out: {path}\n")
        sys.exit(1)

    text = path.read_text()
    if MARKER in text:
        print(f"already patched {path.name}")
        return

    count = text.count(UNUSED)
    if count != 4:
        sys.stderr.write(f"ControlStream.c: expected 4 unused RGB LED entries, found {count}\n")
        sys.exit(1)

    path.write_text(text.replace(UNUSED, UNUSED_NEW))
    print(f"patched {path.name}")


if __name__ == "__main__":
    main()

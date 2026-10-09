#!/usr/bin/env python3
"""Fail if a bundle Mach-O is not safe on macOS 13.

Each Mach-O must have minos <= the floor (default 13.0), an arm64 slice,
and no strong LC_LOAD_DYLIB of a system framework introduced after macOS 13.
Weak loads (LC_LOAD_WEAK_DYLIB) of those frameworks are allowed. The parser
lives in scripts/macos_macho.py. Does not need an Apple SDK or codesign.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from macos_macho import above_floor, parse_macho, scan_path, version_tuple  # noqa: E402


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        raise SystemExit("usage: check-macos-minos.py PATH [--floor 13.0]")
    target = Path(argv[1])
    floor = version_tuple("13.0")
    if "--floor" in argv:
        floor = version_tuple(argv[argv.index("--floor") + 1])
    if not target.exists():
        raise SystemExit("missing %s" % target)
    offenders, macho_count = scan_path(target, floor)
    if macho_count == 0:
        raise SystemExit("%s contains no Mach-O" % target)
    if offenders:
        for path, version in offenders:
            print("%s minos %d.%d.%d is above %d.%d.%d" % (
                path, version[0], version[1], version[2], floor[0], floor[1], floor[2]
            ), file=sys.stderr)
        return 1
    print("%s: %d Mach-O file(s), arm64 present, minos at or below %d.%d.%d, no strong link to a post-13 framework" % (
        target, macho_count, floor[0], floor[1], floor[2]
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

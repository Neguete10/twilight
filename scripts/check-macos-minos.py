#!/usr/bin/env python3
"""Fail if a Twilight.app (or a deps prefix) cannot load on the deployment target.

    scripts/check-macos-minos.py <bundle-or-dir> <max-minos>

TWILIGHT_MINOS_ONLY=1 checks LC_BUILD_VERSION only. Use that on
build/macos-deps before macdeployqt rewrites install names: those
libraries still point at the prefix. The app bundle check also fails
when an LC_RPATH points outside the bundle (/opt/homebrew, /usr/local,
/Users, or any other absolute path) or a strong dependency does not
resolve to a file inside the bundle.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from macos_macho import MachOError, describe_problems


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.stderr.write(f"usage: {argv[0]} <bundle-or-dir> <max-minos>\n")
        return 2
    root = Path(argv[1])
    if not root.exists():
        sys.stderr.write(f"check-macos-minos: not found: {root}\n")
        return 2
    max_minos = argv[2]
    minos_only = os.environ.get("TWILIGHT_MINOS_ONLY", "0") == "1"
    try:
        problems = describe_problems(root, max_minos, minos_only=minos_only)
    except MachOError as exc:
        sys.stderr.write(f"check-macos-minos: {exc}\n")
        return 1
    if problems:
        for line in problems:
            print(line)
        sys.stderr.write(
            f"check-macos-minos: FAILED. Some Mach-O files in {root} need macOS "
            f"> {max_minos}, keep an rpath outside the bundle, or link a library "
            "that is not inside the bundle.\n"
        )
        sys.stderr.write(
            "Rebuild with scripts/build-macos-deps.sh "
            f"(MACOSX_DEPLOYMENT_TARGET={max_minos}).\n"
        )
        return 1
    print(f"check-macos-minos: OK, minos <= {max_minos}"
          + ("" if minos_only else ", bundle rpaths and dependencies resolve"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

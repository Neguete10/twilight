#!/usr/bin/env python3
"""Parser checks for scripts/check-macos-minos.py. No Apple SDK."""

import importlib.util
import struct
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
FAILURES = 0

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_MACOSX = 0x24


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def load_checker():
    path = ROOT / "scripts" / "check-macos-minos.py"
    spec = importlib.util.spec_from_file_location("check_macos_minos", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def packed(major, minor, patch):
    return (major << 16) | (minor << 8) | patch


def thin(minos, command):
    if command == LC_BUILD_VERSION:
        load = struct.pack("<IIIIII", LC_BUILD_VERSION, 24, 1, minos, minos, 0)
    else:
        load = struct.pack("<IIII", LC_VERSION_MIN_MACOSX, 16, minos, minos)
    header = struct.pack("<IIIIIIII", MH_MAGIC_64, 0x0100000C, 0, 2, 1, len(load), 0, 0)
    return header + load


def fat(first, second):
    offset = 8 + 20 * 2
    blob = struct.pack(">II", FAT_MAGIC, 2)
    cursor = offset
    slices = b""
    for chunk in (first, second):
        blob += struct.pack(">IIIII", 0x0100000C, 0, cursor, len(chunk), 3)
        slices += chunk
        cursor += len(chunk)
    return blob + slices


def test_parser():
    checker = load_checker()
    floor = (13, 0, 0)
    ok = checker.parse_macho(thin(packed(13, 0, 0), LC_BUILD_VERSION))
    expect(ok == [(13, 0, 0)], "LC_BUILD_VERSION 13.0.0")
    expect(not checker.above_floor(ok[0], floor), "13.0.0 is allowed")

    newer = checker.parse_macho(thin(packed(14, 0, 0), LC_BUILD_VERSION))
    expect(checker.above_floor(newer[0], floor), "14.0.0 is rejected")

    patch = checker.parse_macho(thin(packed(13, 0, 1), LC_VERSION_MIN_MACOSX))
    expect(patch == [(13, 0, 1)], "LC_VERSION_MIN_MACOSX is read")
    expect(checker.above_floor(patch[0], floor), "13.0.1 is above 13.0")

    both = checker.parse_macho(fat(
        thin(packed(13, 0, 0), LC_BUILD_VERSION),
        thin(packed(14, 2, 0), LC_BUILD_VERSION),
    ))
    expect(both == [(13, 0, 0), (14, 2, 0)], "fat slices are both read")
    expect(any(checker.above_floor(item, floor) for item in both), "one fat slice above the floor fails the file")

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "Twilight").write_bytes(thin(packed(13, 0, 0), LC_BUILD_VERSION))
        offenders, count = checker.scan_path(root, floor)
        expect(count == 1 and offenders == [], "a 13.0 bundle passes")

        (root / "QtCore").write_bytes(thin(packed(14, 0, 0), LC_BUILD_VERSION))
        offenders, count = checker.scan_path(root, floor)
        expect(count == 2 and len(offenders) == 1, "a 14.0 Mach-O fails the bundle")

    empty = tempfile.TemporaryDirectory()
    try:
        try:
            checker.scan_path(empty.name, floor)
            raised = False
        except SystemExit:
            raised = True
        expect(raised, "a directory with no Mach-O fails")
    finally:
        empty.cleanup()


def main():
    test_parser()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

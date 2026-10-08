#!/usr/bin/env python3
"""Fail if any Mach-O in a bundle requires a newer macOS than the floor.

Reads LC_BUILD_VERSION (0x32) and LC_VERSION_MIN_MACOSX (0x24), including
each slice of a fat binary (0xCAFEBABE / 0xCAFEBABF). A directory that
contains no Mach-O fails. Does not need an Apple SDK or codesign.
"""

import struct
import sys
from pathlib import Path

MH_MAGIC = 0xFEEDFACE
MH_CIGAM = 0xCEFAEDFE
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_VERSION_MIN_MACOSX = 0x24
LC_BUILD_VERSION = 0x32

SKIP_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".icns", ".svg", ".plist", ".strings",
    ".txt", ".html", ".qml", ".qrc", ".js", ".css", ".json", ".py", ".md",
    ".nib", ".car", ".metallib", ".pcm", ".h", ".hpp", ".c", ".cpp", ".mm",
}


def version_tuple(text):
    parts = []
    for piece in str(text).split("."):
        if piece == "" or not piece.isdigit():
            raise SystemExit("version must be numeric, got %r" % text)
        parts.append(int(piece))
    if not parts:
        raise SystemExit("empty version")
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def unpack_version(value):
    return ((value >> 16) & 0xFFFF, (value >> 8) & 0xFF, value & 0xFF)


def _u32(data, offset, big):
    fmt = ">I" if big else "<I"
    return struct.unpack_from(fmt, data, offset)[0]


def parse_thin(data, offset, end, sixtyfour, big):
    header_size = 32 if sixtyfour else 28
    if offset + header_size > end:
        raise ValueError("truncated Mach-O header at %d" % offset)
    ncmds = _u32(data, offset + 16, big)
    sizeofcmds = _u32(data, offset + 20, big)
    cursor = offset + header_size
    cmds_end = cursor + sizeofcmds
    if cmds_end > end or cmds_end > len(data):
        raise ValueError("truncated Mach-O load commands at %d" % offset)
    found = []
    for _ in range(ncmds):
        if cursor + 8 > cmds_end:
            raise ValueError("truncated load command")
        cmd = _u32(data, cursor, big)
        cmdsize = _u32(data, cursor + 4, big)
        if cmdsize < 8 or cursor + cmdsize > cmds_end:
            raise ValueError("bad cmdsize")
        if cmd == LC_VERSION_MIN_MACOSX and cmdsize >= 16:
            found.append(unpack_version(_u32(data, cursor + 8, big)))
        elif cmd == LC_BUILD_VERSION and cmdsize >= 24:
            found.append(unpack_version(_u32(data, cursor + 12, big)))
        cursor += cmdsize
    if not found:
        raise ValueError("Mach-O at %d has no macOS minimum version" % offset)
    return found


def parse_fat(data, offset, sixtyfour):
    nfat = struct.unpack_from(">I", data, offset + 4)[0]
    arch_size = 32 if sixtyfour else 20
    found = []
    for index in range(nfat):
        base = offset + 8 + index * arch_size
        if base + arch_size > len(data):
            raise ValueError("truncated fat arch")
        if sixtyfour:
            slice_off, slice_size = struct.unpack_from(">QQ", data, base + 8)
        else:
            slice_off, slice_size = struct.unpack_from(">II", data, base + 8)
        slice_end = slice_off + slice_size
        if slice_end > len(data):
            raise ValueError("fat slice extends past the file")
        found.extend(parse_macho(data, slice_off, slice_end))
    if not found:
        raise ValueError("fat binary has no slices")
    return found


def parse_macho(data, offset=0, end=None):
    """Return minos tuples from one Mach-O, or [] when the bytes are not Mach-O."""
    if end is None:
        end = len(data)
    if offset < 0 or offset + 8 > end or offset + 8 > len(data):
        return []
    little = struct.unpack_from("<I", data, offset)[0]
    big = struct.unpack_from(">I", data, offset)[0]
    if big == FAT_MAGIC:
        return parse_fat(data, offset, sixtyfour=False)
    if big == FAT_MAGIC_64:
        return parse_fat(data, offset, sixtyfour=True)
    if little == MH_MAGIC_64:
        return parse_thin(data, offset, end, sixtyfour=True, big=False)
    if little == MH_CIGAM_64:
        return parse_thin(data, offset, end, sixtyfour=True, big=True)
    if little == MH_MAGIC:
        return parse_thin(data, offset, end, sixtyfour=False, big=False)
    if little == MH_CIGAM:
        return parse_thin(data, offset, end, sixtyfour=False, big=True)
    return []


def above_floor(version, floor):
    return tuple(version) > tuple(floor)


def scan_path(root, floor):
    """Return (offenders, macho_count). offenders are (path, version) above floor."""
    root = Path(root)
    files = [root] if root.is_file() else [path for path in root.rglob("*") if path.is_file()]
    offenders = []
    macho_count = 0
    for path in files:
        if path.suffix.lower() in SKIP_SUFFIXES or path.name.endswith(".dSYM"):
            continue
        try:
            data = path.read_bytes()
        except OSError as exc:
            raise SystemExit("could not read %s: %s" % (path, exc))
        try:
            versions = parse_macho(data)
        except ValueError as exc:
            raise SystemExit("%s: %s" % (path, exc))
        if not versions:
            continue
        macho_count += 1
        for version in versions:
            if above_floor(version, floor):
                offenders.append((path, version))
    if macho_count == 0:
        raise SystemExit("%s contains no Mach-O" % root)
    return offenders, macho_count


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
    print("%s: %d Mach-O file(s) at or below %d.%d.%d" % (
        target, macho_count, floor[0], floor[1], floor[2]
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

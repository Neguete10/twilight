#!/usr/bin/env python3
"""Mach-O facts used to keep Twilight on macOS 13.

Reads LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX, the slice cputype, and
LC_LOAD_DYLIB-family commands. Does not need an Apple SDK or codesign.
scripts/check-macos-minos.py is the bundle entry point.
"""

import struct
from pathlib import Path

MH_MAGIC = 0xFEEDFACE
MH_CIGAM = 0xCEFAEDFE
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_VERSION_MIN_MACOSX = 0x24
LC_BUILD_VERSION = 0x32
LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_LAZY_LOAD_DYLIB = 0x20
LC_REEXPORT_DYLIB = 0x8000001F
LC_LOAD_UPWARD_DYLIB = 0x80000023

# cpu_type_t. ARM64 includes CPU_ARCH_ABI64.
CPU_TYPE_X86_64 = 0x01000007
CPU_TYPE_ARM64 = 0x0100000C

# Strong loads. LC_LOAD_WEAK_DYLIB is optional and is allowed for a
# framework that does not exist on the deployment target.
STRONG_LOADS = {
    LC_LOAD_DYLIB: "LC_LOAD_DYLIB",
    LC_LAZY_LOAD_DYLIB: "LC_LAZY_LOAD_DYLIB",
    LC_REEXPORT_DYLIB: "LC_REEXPORT_DYLIB",
    LC_LOAD_UPWARD_DYLIB: "LC_LOAD_UPWARD_DYLIB",
}
WEAK_LOAD = "LC_LOAD_WEAK_DYLIB"

# System frameworks introduced after macOS 13. A strong LC_LOAD_DYLIB of
# one of these aborts dyld on Ventura. Weak loads stay legal.
# Versions are the OS where the framework first shipped.
POST_13_FRAMEWORKS = {
    "AccessorySetupKit": (15, 0),
    "BrowserEngineKit": (14, 4),
    "Cinematic": (14, 0),
    "CoreHID": (15, 0),
    "DockKit": (14, 0),
    "EnergyKit": (26, 0),
    "FoundationModels": (26, 0),
    "ImagePlayground": (15, 2),
    "JournalingSuggestions": (14, 0),
    "MediaExtension": (14, 0),
    "SensitiveContentAnalysis": (14, 0),
    "TipKit": (14, 0),
    "WiFiAware": (26, 0),
}

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


def above_floor(version, floor):
    return tuple(version) > tuple(floor)


def _u32(data, offset, big):
    fmt = ">I" if big else "<I"
    return struct.unpack_from(fmt, data, offset)[0]


def _cstring(data, start, end):
    if start < 0 or start >= end or start >= len(data):
        raise ValueError("dylib name out of range")
    stop = data.find(b"\x00", start, min(end, len(data)))
    if stop < 0:
        raise ValueError("unterminated dylib name")
    return data[start:stop].decode("utf-8", "replace")


def system_framework_name(path):
    """Return Foo for /System/Library/.../Foo.framework, else None."""
    if "/System/Library/Frameworks/" not in path and "/System/Library/PrivateFrameworks/" not in path:
        return None
    marker = ".framework"
    index = path.find(marker)
    if index < 0:
        return None
    slash = path.rfind("/", 0, index)
    if slash < 0:
        return None
    return path[slash + 1:index]


def parse_thin(data, offset, end, sixtyfour, big):
    header_size = 32 if sixtyfour else 28
    if offset + header_size > end:
        raise ValueError("truncated Mach-O header at %d" % offset)
    cputype = _u32(data, offset + 4, big)
    ncmds = _u32(data, offset + 16, big)
    sizeofcmds = _u32(data, offset + 20, big)
    cursor = offset + header_size
    cmds_end = cursor + sizeofcmds
    if cmds_end > end or cmds_end > len(data):
        raise ValueError("truncated Mach-O load commands at %d" % offset)
    found = []
    loads = []
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
        elif cmd == LC_LOAD_WEAK_DYLIB and cmdsize >= 24:
            name_off = _u32(data, cursor + 8, big)
            loads.append((WEAK_LOAD, _cstring(data, cursor + name_off, cursor + cmdsize)))
        elif cmd in STRONG_LOADS and cmdsize >= 24:
            name_off = _u32(data, cursor + 8, big)
            loads.append((STRONG_LOADS[cmd], _cstring(data, cursor + name_off, cursor + cmdsize)))
        cursor += cmdsize
    if not found:
        raise ValueError("Mach-O at %d has no macOS minimum version" % offset)
    return {"minos": found, "cputype": cputype, "loads": loads}


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
        nested = parse_slices(data, slice_off, slice_end)
        if nested:
            found.extend(nested)
    if not found:
        raise ValueError("fat binary has no slices")
    return found


def parse_slices(data, offset=0, end=None):
    """Return slice dicts, or None when the bytes are not Mach-O."""
    if end is None:
        end = len(data)
    if offset < 0 or offset + 8 > end or offset + 8 > len(data):
        return None
    little = struct.unpack_from("<I", data, offset)[0]
    big = struct.unpack_from(">I", data, offset)[0]
    if big == FAT_MAGIC:
        return parse_fat(data, offset, sixtyfour=False)
    if big == FAT_MAGIC_64:
        return parse_fat(data, offset, sixtyfour=True)
    if little == MH_MAGIC_64:
        return [parse_thin(data, offset, end, sixtyfour=True, big=False)]
    if little == MH_CIGAM_64:
        return [parse_thin(data, offset, end, sixtyfour=True, big=True)]
    if little == MH_MAGIC:
        return [parse_thin(data, offset, end, sixtyfour=False, big=False)]
    if little == MH_CIGAM:
        return [parse_thin(data, offset, end, sixtyfour=False, big=True)]
    return None


def parse_macho(data, offset=0, end=None):
    """Return minos tuples from one Mach-O, or [] when the bytes are not Mach-O."""
    slices = parse_slices(data, offset, end)
    if not slices:
        return []
    found = []
    for item in slices:
        found.extend(item["minos"])
    return found


def _forbid_reason(path, item):
    reasons = []
    for cmd, name in item["loads"]:
        if cmd == WEAK_LOAD:
            continue
        framework = system_framework_name(name)
        if framework in POST_13_FRAMEWORKS:
            introduced = POST_13_FRAMEWORKS[framework]
            reasons.append(
                "%s %s %s.framework (%s), introduced in macOS %d.%d"
                % (path, cmd, framework, name, introduced[0], introduced[1])
            )
    return reasons


def scan_path(root, floor):
    """Return (offenders, macho_count). offenders are (path, version) above floor.

    A Mach-O with no arm64 slice, or a strong link to a system framework
    that macOS 13 does not have, raises SystemExit.
    """
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
            slices = parse_slices(data)
        except ValueError as exc:
            raise SystemExit("%s: %s" % (path, exc))
        if not slices:
            continue
        macho_count += 1
        if not any(item["cputype"] == CPU_TYPE_ARM64 for item in slices):
            raise SystemExit("%s has no arm64 slice" % path)
        for item in slices:
            for version in item["minos"]:
                if above_floor(version, floor):
                    offenders.append((path, version))
            for reason in _forbid_reason(path, item):
                raise SystemExit(reason)
    if macho_count == 0:
        raise SystemExit("%s contains no Mach-O" % root)
    return offenders, macho_count

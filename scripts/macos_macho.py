"""Mach-O minimum-OS, rpath, and dependency checks for Twilight's macOS bundle.

No otool and no Apple SDK. The same parser runs in CI and on the build Mac.
"""

from __future__ import annotations

import struct
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA

LC_LOAD_DYLIB = 0xC
LC_ID_DYLIB = 0xD
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_RPATH = 0x8000001C
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_MACOSX = 0x24

# Strong dependencies. A weak load may be absent; QtPdf is a strong load.
REQUIRED_LOADS = {LC_LOAD_DYLIB, LC_REEXPORT_DYLIB}
LOAD_OR_ID = REQUIRED_LOADS | {LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB}

CPU_NAMES = {
    0x01000007: "x86_64",
    0x0100000C: "arm64",
    7: "i386",
    12: "arm",
}

# LC_RPATH values that pull a second Qt (or any other dylib) from the build Mac.
OUTSIDE_MARKERS = ("/opt/homebrew", "/usr/local", "/Users")


class MachOError(Exception):
    pass


def _version(value: int) -> str:
    return f"{(value >> 16) & 0xFFFF}.{(value >> 8) & 0xFF}.{value & 0xFF}"


def version_tuple(text: str) -> tuple[int, ...]:
    parts = []
    for piece in text.split("."):
        if piece == "" or not piece.isdigit():
            raise MachOError(f"not a version: {text!r}")
        parts.append(int(piece))
    if not parts:
        raise MachOError(f"not a version: {text!r}")
    return tuple(parts)


def version_gt(left: str, right: str) -> bool:
    a = version_tuple(left)
    b = version_tuple(right)
    width = max(len(a), len(b))
    a = a + (0,) * (width - len(a))
    b = b + (0,) * (width - len(b))
    return a > b


def _cstring(data: bytes, start: int, end: int) -> str:
    blob = data[start:end]
    return blob.split(b"\x00", 1)[0].decode("utf-8", "replace")


def _parse_slice(data: bytes, base: int) -> dict | None:
    if base + 32 > len(data):
        return None
    magic = struct.unpack_from("<I", data, base)[0]
    if magic == MH_MAGIC_64:
        endian = "<"
    elif magic == MH_CIGAM_64:
        endian = ">"
    else:
        return None
    cputype, _cpusub, _filetype, ncmds, sizeofcmds, _flags, _reserved = struct.unpack_from(
        endian + "IIIIIII", data, base + 4
    )
    off = base + 32
    end = off + sizeofcmds
    if end > len(data):
        raise MachOError("load commands extend past the slice")
    loads: list[str] = []
    weak_loads: list[str] = []
    rpaths: list[str] = []
    ident = None
    minos: list[str] = []
    for _ in range(ncmds):
        if off + 8 > end:
            raise MachOError("truncated load command")
        cmd, cmdsize = struct.unpack_from(endian + "II", data, off)
        if cmdsize < 8 or off + cmdsize > end:
            raise MachOError("invalid load command size")
        if cmd in LOAD_OR_ID or cmd == LC_RPATH:
            nameoff = struct.unpack_from(endian + "I", data, off + 8)[0]
            if nameoff >= cmdsize:
                raise MachOError("name offset outside the load command")
            name = _cstring(data, off + nameoff, off + cmdsize)
            if cmd == LC_ID_DYLIB:
                ident = name
            elif cmd == LC_LOAD_WEAK_DYLIB:
                weak_loads.append(name)
            elif cmd == LC_RPATH:
                rpaths.append(name)
            else:
                loads.append(name)
        elif cmd == LC_BUILD_VERSION:
            _platform, minv, _sdk, _ntools = struct.unpack_from(endian + "IIII", data, off + 8)
            minos.append(_version(minv))
        elif cmd == LC_VERSION_MIN_MACOSX:
            version, _sdk = struct.unpack_from(endian + "II", data, off + 8)
            minos.append(_version(version))
        off += cmdsize
    return {
        "arch": CPU_NAMES.get(cputype, hex(cputype)),
        "ident": ident,
        "loads": loads,
        "weak_loads": weak_loads,
        "rpaths": rpaths,
        "minos": minos,
    }


def parse_macho(data: bytes) -> list[dict]:
    """Return one record per architecture slice, or an empty list when not Mach-O."""
    if len(data) < 8:
        return []
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic in (FAT_MAGIC, FAT_CIGAM):
        endian = ">" if magic == FAT_MAGIC else "<"
        nfat = struct.unpack_from(endian + "I", data, 4)[0]
        slices = []
        off = 8
        for _ in range(nfat):
            if off + 20 > len(data):
                raise MachOError("truncated fat header")
            _cputype, _cpusub, offset, _size, _align = struct.unpack_from(endian + "IIIII", data, off)
            parsed = _parse_slice(data, offset)
            if parsed is None:
                raise MachOError("fat slice is not a 64-bit Mach-O")
            slices.append(parsed)
            off += 20
        return slices
    parsed = _parse_slice(data, 0)
    if parsed is None:
        return []
    return [parsed]


def read_macho(path: Path) -> list[dict]:
    with path.open("rb") as handle:
        return parse_macho(handle.read())


def is_system_dependency(path: str) -> bool:
    return path.startswith("/usr/lib/") or path.startswith("/System/")


def rpath_outside_bundle(rpath: str, bundle: Path) -> bool:
    """True when an LC_RPATH can load a library from outside the app bundle."""
    if any(marker in rpath for marker in OUTSIDE_MARKERS):
        return True
    if rpath.startswith("@executable_path") or rpath.startswith("@loader_path") or rpath.startswith("@rpath"):
        return False
    if rpath.startswith("/"):
        try:
            Path(rpath).resolve().relative_to(bundle.resolve())
        except ValueError:
            return True
        return False
    return False


def _join_special(base: Path, token: str, prefix: str, relative: str) -> Path | None:
    if not token.startswith(prefix):
        return None
    suffix = token[len(prefix):]
    if suffix.startswith("/"):
        suffix = suffix[1:]
    return (base / suffix / relative).resolve()


def dependency_candidates(dep: str, macho: Path, bundle: Path, rpaths: list[str]) -> list[Path]:
    if dep.startswith("@rpath/"):
        relative = dep[len("@rpath/"):]
        found = []
        executable_dir = bundle / "Contents" / "MacOS"
        for rpath in rpaths:
            if rpath_outside_bundle(rpath, bundle):
                continue
            for base, prefix in (
                (executable_dir, "@executable_path"),
                (macho.parent, "@loader_path"),
            ):
                joined = _join_special(base, rpath, prefix, relative)
                if joined is not None:
                    found.append(joined)
            if rpath.startswith("@rpath"):
                continue
        # The app rpath is @executable_path/../Frameworks even when a plugin
        # forgot to repeat it. Look there too.
        found.append((bundle / "Contents" / "Frameworks" / relative).resolve())
        return found
    if dep.startswith("@executable_path/"):
        relative = dep[len("@executable_path/"):]
        return [((bundle / "Contents" / "MacOS") / relative).resolve()]
    if dep.startswith("@loader_path/"):
        relative = dep[len("@loader_path/"):]
        return [(macho.parent / relative).resolve()]
    if dep.startswith("/"):
        return [Path(dep)]
    return [(macho.parent / dep).resolve()]


def dependency_in_bundle(dep: str, macho: Path, bundle: Path, rpaths: list[str]) -> bool:
    if is_system_dependency(dep):
        return True
    bundle_root = bundle.resolve()
    for candidate in dependency_candidates(dep, macho, bundle, rpaths):
        if not candidate.is_file():
            continue
        try:
            candidate.resolve().relative_to(bundle_root)
        except ValueError:
            continue
        return True
    return False


def is_plugin(relative: str) -> bool:
    text = relative.replace("\\", "/")
    return "/PlugIns/" in f"/{text}" or "/Resources/qml/" in f"/{text}" or text.startswith("PlugIns/")


def iter_macho_files(root: Path):
    if root.is_file():
        yield root
        return
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        yield path


def non_system_deps(path: Path) -> list[str]:
    deps = []
    for image in read_macho(path):
        for dep in image["loads"]:
            if not is_system_dependency(dep) and dep not in deps:
                deps.append(dep)
    return deps


def describe_problems(root: Path, max_minos: str, minos_only: bool = False) -> list[str]:
    """Human-readable failures. Empty means the tree may ship."""
    problems = []
    count = 0
    bundle = root if root.is_dir() else root.parent
    for path in iter_macho_files(root):
        try:
            images = read_macho(path)
        except MachOError as exc:
            problems.append(f"MACHO {exc}  {path}")
            continue
        if not images:
            continue
        count += 1
        try:
            rel = path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            rel = path.name
        for image in images:
            arch = image["arch"]
            if not image["minos"]:
                problems.append(f"MINOS ? (no LC_BUILD_VERSION/LC_VERSION_MIN_MACOSX)  [{arch}]  {rel}")
            for minos in image["minos"]:
                if version_gt(minos, max_minos):
                    problems.append(f"MINOS {minos} > {max_minos}  [{arch}]  {rel}")
            if minos_only:
                continue
            for rpath in image["rpaths"]:
                if rpath_outside_bundle(rpath, bundle):
                    problems.append(f"RPATH {rpath}  [{arch}]  {rel}")
            for dep in image["loads"]:
                if dependency_in_bundle(dep, path, bundle, image["rpaths"]):
                    continue
                problems.append(f"UNRESOLVED {dep}  [{arch}]  {rel}")
    if count == 0:
        problems.append(f"check-macos-minos: no Mach-O files under {root}")
    return problems


def orphan_plugins(root: Path) -> list[tuple[Path, list[str]]]:
    """Plug-ins whose strong dependencies are not inside the bundle.

    Qt PDF plug-ins are the case this is aimed at: macdeployqt copies them
    from a Qt that contains QtPdf, the app does not link QtPdf, and the
    plug-in's rpath then loads a second QtCore from Homebrew.
    """
    if not root.is_dir():
        return []
    found = []
    for path in iter_macho_files(root):
        rel = path.resolve().relative_to(root.resolve()).as_posix()
        if not is_plugin(rel):
            continue
        images = read_macho(path)
        if not images:
            continue
        missing = []
        for image in images:
            for dep in image["loads"]:
                if dependency_in_bundle(dep, path, root, image["rpaths"]):
                    continue
                if dep not in missing:
                    missing.append(dep)
        if missing:
            found.append((path, missing))
    return found


def outside_rpaths(root: Path) -> list[tuple[Path, str]]:
    found = []
    bundle = root if root.is_dir() else root.parent
    for path in iter_macho_files(root):
        for image in read_macho(path):
            for rpath in image["rpaths"]:
                if rpath_outside_bundle(rpath, bundle):
                    found.append((path, rpath))
    return found

#!/usr/bin/env python3
"""Fail on macOS APIs newer than 13 used without an availability guard.

The Mac build also passes -Werror=unguarded-availability-new with
MACOSX_DEPLOYMENT_TARGET=13.0 (globaldefs.pri, app.pro, pyrowave.pro).
This script is the check that runs without an Apple SDK: known symbols
introduced after 13.0 must sit in @available / __builtin_available /
API_AVAILABLE for at least that OS version, and a .pro file must not
strong-link a framework from that set.

Comments and string literals are ignored. #import/#include lines are
ignored. PyroWave's Metal .mm sources live in the submodule; when that
directory is absent this script cannot see them, and the compiler flag
on pyrowave.pro is what fails the Mac build.
"""

import re
import sys
from pathlib import Path

SOURCE_SUFFIXES = {".m", ".mm", ".h", ".hpp", ".hh", ".cpp", ".cc", ".cxx", ".c"}
SKIP_DIRS = {".git", "build", "node_modules", "dist"}

# introduction (major, minor). A guard must be >= this. APIs that exist on
# macOS 13 are not listed: the deployment target already allows them.
SYMBOLS = (
    ("CADisplayLink", (14, 0)),
    ("CAFrameRateRange", (14, 0)),
    ("CAFrameRateRangeMake", (14, 0)),
    ("CMHeadphoneMotionManager", (14, 0)),
    ("CoreHID", (15, 0)),
    ("displayLinkWithTarget", (14, 0)),
    ("kAudioUnitProperty_SpatialMixerAnyInputIsUsingPersonalizedHRTF", (14, 0)),
    ("kAudioUnitProperty_SpatialMixerEnableHeadTracking", (14, 0)),
    ("kAudioUnitProperty_SpatialMixerPersonalizedHRTFMode", (14, 0)),
    ("kSpatialMixerPersonalizedHRTFMode_Auto", (14, 0)),
    ("preferredFrameRateRange", (14, 0)),
)

# Strong-link names that do not exist on macOS 13. Mirrors macos_macho.POST_13_FRAMEWORKS.
POST_13_FRAMEWORKS = {
    "AccessorySetupKit",
    "BrowserEngineKit",
    "Cinematic",
    "CoreHID",
    "DockKit",
    "EnergyKit",
    "FoundationModels",
    "ImagePlayground",
    "JournalingSuggestions",
    "MediaExtension",
    "SensitiveContentAnalysis",
    "TipKit",
    "WiFiAware",
}

FLAG_VARIABLES = (
    "QMAKE_CFLAGS",
    "QMAKE_OBJECTIVE_CFLAGS",
    "QMAKE_CXXFLAGS",
    "QMAKE_OBJCXXFLAGS",
)
WARNING_FLAG = "-Werror=unguarded-availability-new"
FLAG_FILES = (
    "globaldefs.pri",
    "app/app.pro",
    "pyrowave/pyrowave.pro",
)

# @available uses macOS; API_AVAILABLE uses macos.
_MACOS = r"[mM]ac[Oo][Ss]"
AVAILABLE_RE = re.compile(
    r"(?:@available|__builtin_available)\s*\(\s*" + _MACOS + r"\s+([0-9]+(?:\.[0-9]+)*)"
    r"|API_AVAILABLE\s*\(\s*" + _MACOS + r"\s*\(\s*([0-9]+(?:\.[0-9]+)*)"
)
TOKEN_RE = re.compile(
    r"(?:@available|__builtin_available)\s*\(\s*" + _MACOS + r"\s+([0-9]+(?:\.[0-9]+)*)"
    r"|API_AVAILABLE\s*\(\s*" + _MACOS + r"\s*\(\s*([0-9]+(?:\.[0-9]+)*)"
    r"|[{};]"
)
STRONG_FRAMEWORK_RE = re.compile(r"(?<![\w-])(?<!weak_)-framework\s+([A-Za-z0-9_]+)")
CLOBBER_RE = re.compile(
    r"^\s*(QMAKE_CFLAGS|QMAKE_OBJECTIVE_CFLAGS|QMAKE_CXXFLAGS|QMAKE_OBJCXXFLAGS)\s*=(?!=)"
)


def parse_version(text):
    parts = [int(piece) for piece in text.split(".")]
    while len(parts) < 2:
        parts.append(0)
    return (parts[0], parts[1])


def strip_comments_and_strings(text):
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if text.startswith("/*", i):
            out.append(" ")
            out.append(" ")
            i += 2
            while i < n and not text.startswith("*/", i):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append(" ")
                out.append(" ")
                i += 2
            continue
        if text[i] in ("'", '"'):
            quote = text[i]
            out.append(" ")
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    out.append(" ")
                    i += 1
                    if i < n:
                        out.append("\n" if text[i] == "\n" else " ")
                        i += 1
                    continue
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append(" ")
                i += 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def guarded_ranges(text):
    """Half-open spans covered by a macOS availability annotation."""
    ranges = []
    depth = 0
    stack = []
    pending = None
    pending_start = 0
    for match in TOKEN_RE.finditer(text):
        token = match.group(0)
        if token[0] in "{};":
            if pending is not None:
                ranges.append((pending_start, match.start(), pending))
            if token == "{":
                if pending is not None:
                    stack.append((depth, pending, match.end()))
                pending = None
                depth += 1
            elif token == "}":
                depth = max(0, depth - 1)
                while stack and stack[-1][0] >= depth:
                    opened, version, start = stack.pop()
                    ranges.append((start, match.start(), version))
                pending = None
            else:
                pending = None
            continue
        raw = match.group(1) or match.group(2)
        pending = parse_version(raw)
        pending_start = match.end()
    return ranges


def version_covers(have, need):
    return have >= need


def line_bounds(text, index):
    start = text.rfind("\n", 0, index) + 1
    end = text.find("\n", index)
    if end < 0:
        end = len(text)
    return start, end


def unguarded_in_source(text, filename="source.mm"):
    stripped = strip_comments_and_strings(text)
    ranges = guarded_ranges(stripped)
    problems = []
    for name, need in SYMBOLS:
        for match in re.finditer(r"\b" + re.escape(name) + r"\b", stripped):
            start, end = line_bounds(stripped, match.start())
            line = stripped[start:end]
            if re.match(r"\s*#\s*(import|include)\b", line):
                continue
            covered = False
            for ann in AVAILABLE_RE.finditer(line):
                raw = ann.group(1) or ann.group(2)
                if version_covers(parse_version(raw), need):
                    covered = True
                    break
            if not covered:
                for span_start, span_end, version in ranges:
                    if span_start <= match.start() < span_end and version_covers(version, need):
                        covered = True
                        break
            if not covered:
                line_no = stripped.count("\n", 0, match.start()) + 1
                problems.append(
                    "%s:%d: %s needs @available(macOS %d.%d) or newer" % (
                        filename, line_no, name, need[0], need[1]
                    )
                )
    return problems


def pro_framework_problems(text, filename="project.pro"):
    problems = []
    for line_no, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        for match in STRONG_FRAMEWORK_RE.finditer(line):
            name = match.group(1)
            if name in POST_13_FRAMEWORKS:
                problems.append(
                    "%s:%d: -framework %s is not on macOS 13; use -weak_framework and guard every use"
                    % (filename, line_no, name)
                )
    return problems


def warning_flag_problems(text, filename):
    problems = []
    covered = {name: False for name in FLAG_VARIABLES}
    for line_no, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        for name in FLAG_VARIABLES:
            if name in line and WARNING_FLAG in line and "+=" in line:
                covered[name] = True
        clobber = CLOBBER_RE.match(line)
        if clobber and WARNING_FLAG not in line:
            problems.append(
                "%s:%d: %s is assigned with = and drops %s"
                % (filename, line_no, clobber.group(1), WARNING_FLAG)
            )
    for name, ok in covered.items():
        if not ok:
            problems.append("%s: %s is missing %s" % (filename, name, WARNING_FLAG))
    return problems


def _walk_files(root):
    root = Path(root)
    if root.is_file():
        yield root
        return
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        yield path


def scan_tree(root):
    root = Path(root)
    problems = []
    for path in _walk_files(root):
        suffix = path.suffix.lower()
        rel = path.relative_to(root).as_posix() if path.is_absolute() or root in path.parents or path == root else path.as_posix()
        try:
            rel = path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            rel = path.as_posix()
        if suffix in SOURCE_SUFFIXES:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                problems.append("%s: %s" % (rel, exc))
                continue
            problems.extend(unguarded_in_source(text, rel))
        elif suffix in (".pro", ".pri"):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                problems.append("%s: %s" % (rel, exc))
                continue
            problems.extend(pro_framework_problems(text, rel))
            for flag_rel in FLAG_FILES:
                if rel == flag_rel:
                    problems.extend(warning_flag_problems(text, rel))
    if root.is_dir():
        present = set()
        for path in _walk_files(root):
            try:
                present.add(path.resolve().relative_to(root.resolve()).as_posix())
            except ValueError:
                continue
        for flag_rel in FLAG_FILES:
            if flag_rel not in present:
                problems.append("%s: missing, cannot check %s" % (flag_rel, WARNING_FLAG))
    return problems


def main(argv):
    if len(argv) > 1 and argv[1] in ("-h", "--help"):
        raise SystemExit("usage: check-macos-availability.py [ROOT]")
    root = Path(argv[1]) if len(argv) > 1 else Path(".")
    if not root.exists():
        raise SystemExit("missing %s" % root)
    problems = scan_tree(root)
    if problems:
        for item in problems:
            print(item, file=sys.stderr)
        return 1
    print("%s: macOS 13 availability guards passed" % root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

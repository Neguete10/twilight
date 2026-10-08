#!/usr/bin/env python3
"""Write the macOS Info.plist qmake consumes.

Desktop builds keep NSAllowsArbitraryLoads. CONFIG+=twilight-mas swaps that
key for NSAllowsLocalNetworking and never emits both. On macOS 11 and later,
the presence of NSAllowsLocalNetworking causes the system to ignore
NSAllowsArbitraryLoads, which would change desktop pairing behavior.
"""

import sys
from pathlib import Path

USAGE = (
    "usage: prepare-macos-infoplist.py SRC DST VERSION BUNDLE_ID "
    "DISPLAY_NAME desktop|mas"
)

ATS_ARBITRARY = "<key>NSAllowsArbitraryLoads</key>"
ATS_LOCAL = "<key>NSAllowsLocalNetworking</key>"


def prepare(text, version, bundle_id, display_name, mode):
    if mode not in ("desktop", "mas"):
        raise SystemExit("plist mode must be desktop or mas")

    version = version.strip()
    bundle_id = bundle_id.strip()
    display_name = display_name.strip()
    if not version or not bundle_id or not display_name:
        raise SystemExit("version, bundle id, and display name must be non-empty")

    replacements = (
        ("<string>VERSION</string>", "<string>%s</string>" % version, 2),
        ("<string>BUNDLE_ID</string>", "<string>%s</string>" % bundle_id, 1),
        ("<string>DISPLAY_NAME</string>", "<string>%s</string>" % display_name, 1),
    )
    for old, new, expected in replacements:
        found = text.count(old)
        if found != expected:
            raise SystemExit("expected %s x%d, found %d" % (old, expected, found))
        text = text.replace(old, new)

    if ATS_ARBITRARY not in text or ATS_LOCAL in text:
        raise SystemExit("Info.plist template must contain only NSAllowsArbitraryLoads")

    if mode == "mas":
        text = text.replace(ATS_ARBITRARY, ATS_LOCAL, 1)

    arbitrary = text.count(ATS_ARBITRARY)
    local = text.count(ATS_LOCAL)
    if mode == "desktop" and not (arbitrary == 1 and local == 0):
        raise SystemExit("desktop plist must keep NSAllowsArbitraryLoads only")
    if mode == "mas" and not (arbitrary == 0 and local == 1):
        raise SystemExit("MAS plist must set NSAllowsLocalNetworking only")
    if "NSAllowsArbitraryLoads" in text and mode == "mas":
        # The template comment may name the desktop key. The key element must not.
        if ATS_ARBITRARY in text:
            raise SystemExit("MAS plist still has the NSAllowsArbitraryLoads key")
    return text


def main(argv):
    if len(argv) != 7:
        raise SystemExit(USAGE)
    src, dst, version, bundle_id, display_name, mode = argv[1:]
    text = Path(src).read_text(encoding="utf-8")
    prepared = prepare(text, version, bundle_id, display_name, mode)
    Path(dst).write_text(prepared, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""Every v2 QML file imports each C++ module it references.

StreamSegueV2 called SystemProperties.waitForAsyncLoad() and read
StreamingPreferences.uiDisplayMode without importing those modules. QML
reports that as a ReferenceError and the session never starts. This walks
app/gui/ui/v2 against the types registered in app/main.cpp.
"""

import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
V2 = ROOT / "app" / "gui" / "ui" / "v2"
FAILURES = 0

REGISTER_RE = re.compile(
    r'qmlRegister(?:Type|UncreatableType|SingletonType)\s*<[^>]+>\s*\('
    r'\s*"([^"]+)"\s*,\s*\d+\s*,\s*\d+\s*,\s*"([^"]+)"',
    re.S,
)
IMPORT_RE = re.compile(r"(?m)^\s*import\s+([A-Za-z_][\w.]*)\b")


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def code_only(text):
    """Drop comments and string literals so a mention in either is not a use."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                break
            out.append(" ")
            i = end + 2
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            if end < 0:
                break
            out.append("\n")
            i = end + 1
            continue
        if text[i] in "\"'":
            quote = text[i]
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            out.append(" ")
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def imported_modules(text):
    return set(IMPORT_RE.findall(text))


def referenced_types(text, type_names):
    body = re.sub(r"(?m)^\s*import\s+[^\n]*", "", code_only(text))
    found = []
    for name in type_names:
        if re.search(r"\b%s\b" % re.escape(name), body):
            found.append(name)
    return found


def registered_modules(main_text):
    """URI -> type name. QML imports the URI and names the type."""
    found = REGISTER_RE.findall(main_text)
    return found


def missing_imports(text, registrations):
    imported = imported_modules(text)
    missing = []
    for uri, type_name in registrations:
        if type_name in referenced_types(text, [type_name]) and uri not in imported:
            missing.append("%s (%s)" % (type_name, uri))
    return missing


def test_scanner_ignores_comments_and_strings():
    sample = """
import QtQuick 2.9
import StreamingPreferences 1.0
Item {
    Component.onCompleted: SystemProperties.waitForAsyncLoad()
    // ComputerManager.reload()
    property string note: "AutoUpdateChecker"
}
"""
    registrations = [
        ("SystemProperties", "SystemProperties"),
        ("StreamingPreferences", "StreamingPreferences"),
        ("ComputerManager", "ComputerManager"),
        ("AutoUpdateChecker", "AutoUpdateChecker"),
    ]
    missing = missing_imports(sample, registrations)
    expect(missing == ["SystemProperties (SystemProperties)"], "scanner flags only a real missing import, got %s" % missing)


def test_v2_imports():
    main = (ROOT / "app" / "main.cpp").read_text(encoding="utf-8")
    registrations = registered_modules(main)
    expect(len(registrations) >= 8, "main.cpp registers the QML modules")
    names = {type_name for _, type_name in registrations}
    for required in (
        "SystemProperties",
        "StreamingPreferences",
        "ComputerManager",
        "ComputerModel",
        "AppModel",
        "AutoUpdateChecker",
        "SdlGamepadKeyNavigation",
        "StreamHudStats",
        "Session",
    ):
        expect(required in names, "main.cpp registers %s" % required)

    qml_files = sorted(V2.glob("*.qml"))
    expect(len(qml_files) >= 10, "v2 QML directory is present")
    for path in qml_files:
        text = path.read_text(encoding="utf-8")
        missing = missing_imports(text, registrations)
        expect(not missing, "%s references %s without importing it" % (path.name, ", ".join(missing)))


def test_segue_blocks_input():
    segue = (V2 / "StreamSegueV2.qml").read_text(encoding="utf-8")
    mouse_at = segue.find("MouseArea {")
    card_at = segue.find("id: card")
    expect(mouse_at != -1 and card_at != -1 and mouse_at < card_at, "the launch overlay MouseArea sits under the card")
    blocker = segue[mouse_at:card_at]
    expect("anchors.fill: parent" in blocker, "the launch overlay eats the full segue")
    expect("acceptedButtons: Qt.AllButtons" in blocker, "the launch overlay eats every button")
    expect("hoverEnabled: true" in blocker, "the launch overlay eats hover")
    expect("preventStealing: true" in blocker, "the shell cannot steal the overlay grab")
    expect("onWheel:" in blocker and "wheel.accepted = true" in blocker, "the launch overlay eats the wheel")
    expect("SystemProperties.waitForAsyncLoad()" in segue, "the segue still waits for system properties before initialize")


def main():
    test_scanner_ignores_comments_and_strings()
    test_v2_imports()
    test_segue_blocks_input()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

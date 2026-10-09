#!/usr/bin/env python3
"""Source and project checks for macOS 13 availability. No Apple SDK."""

import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
FAILURES = 0


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def load_checker():
    path = ROOT / "scripts" / "check-macos-availability.py"
    spec = importlib.util.spec_from_file_location("check_macos_availability", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_fixtures(checker):
    bare = "void f() { [window displayLinkWithTarget:self selector:@selector(link:)]; }\n"
    expect(checker.unguarded_in_source(bare, "bare.mm"), "unguarded display link fails")

    guarded = (
        "void f() {\n"
        "  if (@available(macOS 14.0, *)) {\n"
        "    [window displayLinkWithTarget:self selector:@selector(link:)];\n"
        "  }\n"
        "}\n"
    )
    expect(not checker.unguarded_in_source(guarded, "guarded.mm"), "14.0 guard passes")

    too_low = (
        "void f() {\n"
        "  if (@available(macOS 13.0, *)) {\n"
        "    [window displayLinkWithTarget:self selector:@selector(link:)];\n"
        "  }\n"
        "}\n"
    )
    expect(checker.unguarded_in_source(too_low, "low.mm"), "a 13.0 guard does not cover a 14.0 API")

    declared = "CADisplayLink* link API_AVAILABLE(macos(14.0));\n"
    expect(not checker.unguarded_in_source(declared, "decl.mm"), "same-line API_AVAILABLE counts")

    commented = "void f() { /* displayLinkWithTarget */ int x = 1; }\n"
    expect(not checker.unguarded_in_source(commented, "comment.mm"), "comments are not uses")

    strong = 'LIBS += -framework CoreHID\n'
    expect(checker.pro_framework_problems(strong, "app.pro"), "strong CoreHID link fails")
    weak = 'LIBS += -weak_framework CoreHID\n'
    expect(not checker.pro_framework_problems(weak, "app.pro"), "weak CoreHID link passes")


def test_tree(checker):
    problems = checker.scan_tree(ROOT)
    expect(problems == [], "tree availability scan: %s" % problems[:3])
    display = (ROOT / "app/streaming/video/ffmpeg-renderers/pacer/displaylink_source.mm").read_text(encoding="utf-8")
    expect("CVDisplayLink" in display, "macOS 13 display link falls back to CVDisplayLink")
    expect("@available(macOS 14.0, *)" in display, "CADisplayLink stays inside a 14.0 check")
    sheet = (ROOT / "app/gui/ui/v2/SettingsSheetV2.qml").read_text(encoding="utf-8")
    expect("Unlimited" not in sheet, "settings has no Unlimited control")
    expect("800 Mb/s" in sheet, "help text names the wired gigabit ceiling")


def main():
    checker = load_checker()
    test_fixtures(checker)
    test_tree(checker)
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Preferences that must not be rewritten by another action.

No Qt. Locks the two load/save bugs found after the V-Sync fix:
ending one stream with "quit the host app" must not store that, and a
custom bitrate must survive a resolution, frame rate, or 4:4:4 change.
"""

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


def _outside_platform_if(load, needle):
    lines = load.splitlines()
    indexes = [i for i, line in enumerate(lines) if needle in line]
    if len(indexes) != 1:
        return False
    depth = 0
    for line in lines[:indexes[0]]:
        stripped = line.strip()
        if stripped.startswith("#if"):
            depth += 1
        elif stripped.startswith("#endif"):
            depth = max(0, depth - 1)
    return depth == 0


def test_quit_host_app_is_not_saved():
    session = (ROOT / "app/streaming/session.cpp").read_text(encoding="utf-8")
    header = (ROOT / "app/streaming/session.h").read_text(encoding="utf-8")
    setter = session.split("void Session::setShouldExit", 1)[1].split("void Session::start", 1)[0]
    expect("m_Preferences->quitAppAfter" not in setter, "setShouldExit does not write the saved switch")
    expect("m_QuitHostApp = true" in setter, "setShouldExit records this stream only")
    expect("m_QuitHostApp" in header, "the session keeps its own quit flag")
    cleanup = session.split("bool shouldQuit =", 1)[1].split(";", 1)[0]
    expect("quitAppAfter" in cleanup and "m_QuitHostApp" in cleanup, "cleanup honors the saved switch or this stream")


def test_custom_bitrate_survives_display_changes():
    sheet = (ROOT / "app/gui/ui/v2/SettingsSheetV2.qml").read_text(encoding="utf-8")
    expect("function applyAutomaticBitrate()" in sheet, "display changes share one bitrate update")
    expect(sheet.count("applyAutomaticBitrate()") >= 4, "resolution, custom resolution, fps, and 4:4:4 use it")
    body = sheet.split("function applyAutomaticBitrate()", 1)[1].split("function commitBitrateKbps", 1)[0]
    expect("if (!StreamingPreferences.autoAdjustBitrate)" in body, "a custom bitrate is not replaced")
    commit = sheet.split("function commitBitrateKbps", 1)[1].split("function commitBitrateText", 1)[0]
    expect("tracksDisplayAfterBitrate(kbps)" in commit, "editing the bitrate decides whether it still tracks")
    prefs = (ROOT / "app/settings/streamingpreferences.cpp").read_text(encoding="utf-8")
    expect("autoAdjustAfterLoad" in prefs, "a stored custom bitrate stops tracking on load")
    expect("tracksDisplayAfterBitrateChoice" in prefs, "the decision uses the tested bitrate rule")
    load = prefs.split("void StreamingPreferences::reload()", 1)[1].split("bool StreamingPreferences::retranslate()", 1)[0]
    expect(load.count("SER_VTMETALFRAMESINFLIGHT") == 1, "frames in flight is loaded once")
    expect(load.count("SER_AUDIO_RENDERER") == 1, "the audio renderer is loaded once")
    for needle in ("SER_VTMETALFRAMESINFLIGHT", "SER_AUDIO_RENDERER"):
        expect(_outside_platform_if(load, needle), needle + " is loaded on every platform")


def main():
    test_quit_host_app_is_not_saved()
    test_custom_bitrate_survives_display_changes()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

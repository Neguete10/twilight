#!/usr/bin/env python3
"""Classic parity: Twilight Settings keeps "Quit app on host PC after ending stream"."""

import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
FAILURES = 0

CLASSIC_TITLE = "Quit app on host PC after ending stream"
CLASSIC_DETAIL = (
    "This will close the app or game you are streaming when you end your stream. "
    "You will lose any unsaved progress!"
)


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def test_settings_toggle():
    qml = (ROOT / "app/gui/ui/v2/SettingsSheetV2.qml").read_text(encoding="utf-8")
    expect(qml.count(CLASSIC_TITLE) >= 1, "Settings shows the Classic quit-after-stream title")
    expect("Quit the app on the host when the stream ends" not in qml, "paraphrase is not a second control")
    expect(CLASSIC_DETAIL in qml, "subtitle matches the Classic warning")
    expect(qml.count("id: quitAfterSwitch") == 1, "one quit-after switch")

    switch = qml.split("id: quitAfterSwitch", 1)[1][:500]
    expect("checked: StreamingPreferences.quitAppAfter" in switch, "switch reads quitAppAfter")
    expect("onToggled: StreamingPreferences.quitAppAfter = next" in switch, "switch writes quitAppAfter")

    advanced = qml.split('visible: sheet.section === "advanced"', 1)[1].split("visible: sheet.section === \"about\"", 1)[0]
    title_at = advanced.find(CLASSIC_TITLE)
    codec_at = advanced.find('qsTr("Video codec")')
    expect(title_at != -1 and codec_at != -1 and title_at < codec_at, "toggle is the first Advanced row")

    chain = qml.split('section === "advanced"', 1)[1].split("else if", 1)[0]
    expect(chain.find('ids.push("quitAfter")') != -1, "gamepad chain includes the toggle")
    expect(chain.find('ids.push("quitAfter")') < chain.find('ids.push("codec")'), "gamepad chain reaches the toggle first")


def test_preference_round_trip():
    header = (ROOT / "app/settings/streamingpreferences.h").read_text(encoding="utf-8")
    source = (ROOT / "app/settings/streamingpreferences.cpp").read_text(encoding="utf-8")
    expect("Q_PROPERTY(bool quitAppAfter" in header, "quitAppAfter is a QML property")
    expect('#define SER_QUITAPPAFTER "quitAppAfter"' in source, "QSettings key is quitAppAfter")
    expect("quitAppAfter = settings.value(SER_QUITAPPAFTER, false).toBool();" in source, "missing key defaults off")
    expect("settings.setValue(SER_QUITAPPAFTER, quitAppAfter);" in source, "save writes quitAppAfter")


def test_session_matches_classic():
    session = (ROOT / "app/streaming/session.cpp").read_text(encoding="utf-8")
    expect("!m_Session->m_UnexpectedTermination" in session, "unexpected disconnect does not quit the host app")
    expect("m_Session->m_Preferences->quitAppAfter" in session, "session reads quitAppAfter")
    expect("http.quitApp();" in session, "enabled preference quits the host app")


def main():
    test_settings_toggle()
    test_preference_round_trip()
    test_session_matches_classic()
    if FAILURES:
        print(FAILURES, "failed")
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

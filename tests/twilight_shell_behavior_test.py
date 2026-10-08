#!/usr/bin/env python3
"""Structural checks for the Twilight shell behavior fixes.

These do not run QML or Qt. They lock the source the Mac build compiles:
Game Mode keys, quit refresh, overlay toggle, the quick menu, and Automatic
codec policy.
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


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def test_game_mode_plist():
    plist = read("app/Info.plist")
    expect("<key>LSSupportsGameMode</key>" in plist, "Info.plist sets LSSupportsGameMode")
    expect("<key>GCSupportsGameMode</key>" in plist, "Info.plist sets GCSupportsGameMode")
    expect("public.app-category.games" in plist, "Info.plist stays in the games category")
    prefs = read("app/settings/streamingpreferences.cpp")
    expect("SER_UIDISPLAYMODE" in prefs and "UI_FULLSCREEN" in prefs, "fresh macOS UI mode can be fullscreen")
    expect("settings.contains(SER_UIDISPLAYMODE)" in prefs, "a saved UI mode is not overwritten")
    expect("settings.contains(SER_STARTWINDOWED)" in prefs, "legacy startwindowed is left alone")
    segue = read("app/gui/ui/v2/StreamSegueV2.qml")
    expect("showFullScreen()" in segue, "the shell returns to native fullscreen after a stream")


def test_quit_refresh():
    shell = read("app/gui/ui/v2/ShellV2.qml")
    expect("Nothing is running on this host." in shell, "the empty-quit toast stays")
    expect(shell.count("var rev = shell.appRevision") >= 2, "desktop Resume and Quit reread appRevision")
    expect("getRunningAppId() === 0" in shell, "confirmQuit rechecks the running app")
    expect("openAppMenu(menuAppIndex)" in shell, "an open app menu refreshes when the app list changes")
    sheet = read("app/gui/ui/v2/HostSheetV2.qml")
    expect("Quit running app" in sheet, "host sheet can quit")
    expect("sheet.online && sheet.paired && sheet.busy" in sheet, "host quit is only offered while a stream is reported")
    model = read("app/gui/appmodel.cpp")
    expect("m_CurrentGameId == app.id" in model, "RunningRole uses the same cache as getRunningAppId")
    expect("m_CurrentGameId = gameId" in model, "the running cache updates before the view is told")
    manager = read("app/backend/computermanager.cpp")
    expect("applyReportedRunningGame" in manager, "session reports the running app without waiting for a poll")
    expect("reportedGameId == 0" in manager, "pendingQuit clears only when the sample says idle")


def test_overlay_and_quick_menu():
    keyboard = read("app/streaming/input/keyboard.cpp")
    expect("toggleEnabledPerformanceOverlays" in keyboard, "the stats shortcut asks which overlays are enabled")
    expect("KeyComboQuickMenu" in keyboard, "Ctrl+Alt+Shift+E opens the quick menu")
    expect("SDLK_ESCAPE" in keyboard, "Escape closes the quick menu")
    gamepad = read("app/streaming/input/gamepad.cpp")
    expect("PLAY_FLAG | BACK_FLAG" in gamepad, "Select+Start is the gamepad quick menu combo")
    expect("toggleEnabledPerformanceOverlays" in gamepad, "the gamepad stats combo uses the same targets")
    hud = read("app/gui/ui/v2/StreamHudV2.qml")
    expect("endStreamFromMenu" in hud, "the quick menu can end the stream")
    expect("quickMenuOpen" in hud, "the quick menu lives on the HUD window")
    pip = read("app/streaming/mac/pip_window.mm")
    expect('@"End Stream"' in pip, "the Window menu has End Stream during a stream")
    mouse = read("app/streaming/input/mouse.cpp")
    expect("m_QuickMenuOpen" in mouse, "a video click does not recapture while the menu is open")


def test_automatic_codec():
    session = read("app/streaming/session.cpp")
    expect("automaticOffersPyroWave()" in session, "Automatic consults the PyroWave policy")
    expect("automaticDeprioritizesAv1(av1Hardware)" in session, "Automatic keeps AV1 in front only for hardware")
    expect("VCC_FORCE_PYROWAVE" in session, "explicit PyroWave remains a selection")
    header = read("app/streaming/video/auto_codec.h")
    expect("return false;" in header, "automaticOffersPyroWave is false")


def main():
    test_game_mode_plist()
    test_quit_refresh()
    test_overlay_and_quick_menu()
    test_automatic_codec()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

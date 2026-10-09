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


def test_cli_host_end_exits():
    segue = read("app/gui/StreamSegue.qml")
    quit_branch = segue.split("if (quitAfter)", 1)[1].split("} else {", 1)[0]
    expect("Qt.exit(1)" in quit_branch, "a command-line stream error exits non-zero")
    expect("console.error(streamSegueErrorDialog.text)" in quit_branch, "the command-line error is logged")
    expect(".open()" not in quit_branch, "the command-line path does not wait on the hidden error dialog")
    gui_branch = segue.split("} else {", 1)[1].split("function sessionReadyForDeletion", 1)[0]
    expect("window.visible = true" in gui_branch, "a GUI stream error shows the window again")
    expect("streamSegueErrorDialog.open()" in gui_branch, "a GUI stream error still opens the dialog")
    main = read("app/main.cpp")
    hint_at = main.find("SDL_HINT_NO_SIGNAL_HANDLERS")
    init_at = main.find("SDL_InitSubSystem(SDL_INIT_TIMER)")
    expect(hint_at != -1 and init_at != -1 and hint_at < init_at, "SDL signal handlers are disabled before the first init")
    expect(main.find("installQuitSignals()") != -1 and main.find("installQuitSignals()") < init_at, "our quit signals are installed before SDL init")
    session = read("app/streaming/session.cpp")
    loop_at = session.find("for (;;)")
    accept_at = session.find("setStreamLoopAcceptsQuit(true)")
    cleanup_at = session.find("DispatchDeferredCleanup:")
    clear_at = session.find("setStreamLoopAcceptsQuit(false)")
    expect(accept_at != -1 and loop_at != -1 and accept_at < loop_at, "the stream loop accepts a graceful signal quit")
    expect(clear_at != -1 and cleanup_at != -1 and cleanup_at < clear_at < cleanup_at + 400, "leaving the stream loop stops accepting signal quits")
    expect("Quit event received" in session, "an SDL quit still logs and tears the stream down")
    expect("restoreDefaultQuitSignals" not in session and "restoreDefaultQuitSignals" not in main, "SIGTERM is not forced to terminate for the whole process")
    expect("_Exit(0)" not in main, "the first SIGTERM does not skip teardown")
    handler = read("app/quit_signals.cpp")
    expect("s_StreamLoopAcceptsQuit" in handler and "SDL_QUIT" in handler and "SDL_PushEvent" in handler, "a live stream posts SDL_QUIT from the signal handler")
    expect("SIG_DFL" in handler and "raise(sig)" in handler, "with no stream loop the signal terminates the process")
    expect("quit_signals.cpp" in read("app/app.pro"), "the quit signal handler is part of the app")


def test_app_grid_follows_pair_state():
    shell = read("app/gui/ui/v2/ShellV2.qml")
    expect("onSelectedPairedChanged" in shell, "becoming paired rebuilds the app grid")
    handler = shell.split("onSelectedPairedChanged", 1)[1].split("Rectangle {", 1)[0]
    expect("selectedPaired && !appModel" in handler and "rebuildApps()" in handler, "the grid is built once the host is paired")
    expect("theme.wash" not in shell, "the main pane has no wash circle")
    expect("color wash" not in read("app/gui/ui/v2/ThemeV2.qml"), "the unused wash color is gone")


def test_automatic_codec():
    session = read("app/streaming/session.cpp")
    auto = session.split("case StreamingPreferences::VCC_AUTO:", 1)[1].split("case StreamingPreferences::", 1)[0]
    expect("PYROWAVE" not in auto, "Automatic never offers PyroWave")
    expect("VCC_FORCE_PYROWAVE" in session and "VIDEO_FORMAT_PYROWAVE" in session, "explicit PyroWave remains a selection")


def main():
    test_game_mode_plist()
    test_quit_refresh()
    test_overlay_and_quick_menu()
    test_cli_host_end_exits()
    test_app_grid_follows_pair_state()
    test_automatic_codec()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

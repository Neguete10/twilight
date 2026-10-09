#!/usr/bin/env python3
"""Stream-quit teardown order, and the two qmake patches that back it.

No Qt and no Apple SDK. The imgui and moonlight-common-c trees are
submodules, so the patches are checked against fixtures.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAILURES = 0


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def test_cleanup_order():
    session = (ROOT / "app/streaming/session.cpp").read_text(encoding="utf-8")
    body = session.split("DispatchDeferredCleanup:", 1)[1].split("void Session::toggleMouseEmulation", 1)[0]
    decoder = body.find("delete m_VideoDecoder")
    handler = body.find("delete m_InputHandler")
    expect(decoder != -1 and handler != -1, "cleanup deletes the decoder and the input handler")
    expect(decoder < handler, "the decoder is deleted before the input handler")
    expect(body.find("SDL_LockMutex(m_DecoderLock)") < decoder, "the decoder delete holds m_DecoderLock")
    expect("SDLGamepadKeyNavigation" in body, "the input handler is still destroyed before the UI resumes")
    expect("FramePacer::deinit()" in body[:handler], "the comment names the render-thread join")
    expect(
        "Host adaptive trigger packet 0x5503" in session,
        "the first 0x5503 packet is logged",
    )
    expect(session.count("Host adaptive trigger packet 0x5503") == 1, "that log is only in one place")


def run_script(script, arg):
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / script), str(arg)],
        capture_output=True,
        text=True,
    )
    expect(result.returncode == 0, f"{script} exits 0 ({result.stderr.strip()})")
    return result


def test_control_bounds():
    unused = "    -1,     // Set RGB LED (unused)\n};"
    fixture = "static const short packetTypesGen3[] = {\n" + (unused * 4)
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp)
        (src / "ControlStream.c").write_text(fixture, encoding="utf-8")
        first = run_script("apply_control_packet_bounds.py", src)
        text = (src / "ControlStream.c").read_text(encoding="utf-8")
        expect(text.count("Adaptive triggers (unused)") == 4, "each short table gains index 12")
        expect(unused not in text, "the short endings are replaced")
        expect("patched ControlStream.c" in first.stdout, "first run patches")
        second = run_script("apply_control_packet_bounds.py", src)
        expect("already patched" in second.stdout, "second run is a no-op")
        expect((src / "ControlStream.c").read_text(encoding="utf-8") == text, "second run does not edit")


def test_imgui_shutdown():
    old = """static void ImGui_ImplSDL2_CloseGamepads()
{
    ImGui_ImplSDL2_Data* bd = ImGui_ImplSDL2_GetBackendData();
    if (bd->GamepadMode != ImGui_ImplSDL2_GamepadMode_Manual)
        for (SDL_GameController* gamepad : bd->Gamepads)
            SDL_GameControllerClose(gamepad);
    bd->Gamepads.resize(0);
}
"""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "imgui_impl_sdl2.cpp"
        path.write_text("preamble\n" + old + "trailer\n", encoding="utf-8")
        first = run_script("apply_imgui_gamepad_shutdown.py", path)
        text = path.read_text(encoding="utf-8")
        expect("SDL_WasInit(SDL_INIT_GAMECONTROLLER)" in text, "shutdown skips a quit subsystem")
        expect(text.startswith("preamble\n") and text.endswith("trailer\n"), "only CloseGamepads changes")
        expect("patched imgui_impl_sdl2.cpp" in first.stdout, "first run patches")
        second = run_script("apply_imgui_gamepad_shutdown.py", path)
        expect("already patched" in second.stdout, "imgui patch is idempotent")
        expect(path.read_text(encoding="utf-8") == text, "second imgui run does not edit")


def test_qmake_wires_the_scripts():
    common = (ROOT / "moonlight-common-c/moonlight-common-c.pro").read_text(encoding="utf-8")
    imgui = (ROOT / "imgui/imgui.pro").read_text(encoding="utf-8")
    expect("apply_control_packet_bounds.py" in common, "common-c qmake applies the bounds patch")
    expect("apply_imgui_gamepad_shutdown.py" in imgui, "imgui qmake applies the shutdown patch")


def main():
    test_cleanup_order()
    test_control_bounds()
    test_imgui_shutdown()
    test_qmake_wires_the_scripts()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        sys.exit(1)
    print("ok")


if __name__ == "__main__":
    main()

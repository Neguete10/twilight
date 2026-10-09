#!/usr/bin/env python3
"""Do not close an SDL gamepad ImGui no longer owns.

imgui docking 5a76f2ad opens its own gamepads in ImGui_ImplSDL2_UpdateGamepads.
ImGui_ImplSDL2_Shutdown closes them. If the stream input handler has already
quit SDL_INIT_GAMECONTROLLER, those handles are freed and SDL_GameControllerClose
crashes. Drop the pointers when the subsystem is already gone.

This repo cannot publish a commit on ocornut/imgui, so qmake applies the
delta. The script is idempotent.

Pass the backend cpp path as argv[1] to test the patch against a copy.
The default path is the submodule backend.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "imgui" / "imgui" / "backends" / "imgui_impl_sdl2.cpp"

OLD = """static void ImGui_ImplSDL2_CloseGamepads()
{
    ImGui_ImplSDL2_Data* bd = ImGui_ImplSDL2_GetBackendData();
    if (bd->GamepadMode != ImGui_ImplSDL2_GamepadMode_Manual)
        for (SDL_GameController* gamepad : bd->Gamepads)
            SDL_GameControllerClose(gamepad);
    bd->Gamepads.resize(0);
}
"""

NEW = """static void ImGui_ImplSDL2_CloseGamepads()
{
    ImGui_ImplSDL2_Data* bd = ImGui_ImplSDL2_GetBackendData();
    // SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER) frees every gamepad,
    // including the ones this backend opened. Closing them again crashes.
    if (bd->GamepadMode != ImGui_ImplSDL2_GamepadMode_Manual &&
        SDL_WasInit(SDL_INIT_GAMECONTROLLER))
        for (SDL_GameController* gamepad : bd->Gamepads)
            SDL_GameControllerClose(gamepad);
    bd->Gamepads.resize(0);
}
"""

MARKER = "SDL_WasInit(SDL_INIT_GAMECONTROLLER)"


def main() -> None:
    if not TARGET.is_file():
        sys.stderr.write(f"imgui SDL2 backend not checked out: {TARGET}\n")
        sys.exit(1)

    text = TARGET.read_text()
    if MARKER in text:
        print(f"already patched {TARGET.name}")
        return
    if OLD not in text:
        sys.stderr.write(f"{TARGET}: expected CloseGamepads body not found\n")
        sys.exit(1)
    TARGET.write_text(text.replace(OLD, NEW, 1))
    print(f"patched {TARGET.name}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Format Limelog arguments before Andy's macOS dispatch_async hop.

moonlight-common-c stays pinned at andygrundman 583754fc. That Platform.h
defines Limelog, on Apple platforms only, as a block passed to
dispatch_async. The format arguments are evaluated when the main queue
runs the block, not when Limelog is called. RtpAudioQueue.c logs
queue->blockHead->fecHeader... for "Unable to recover audio data block"
and then clears blockHead. The main thread then faults in
ListenerCallbacks.logMessage (crash address 0x4a) while SDL pumps events
under Session::execInternal. Other Limelog calls pass the same kind of
pointer. Upstream moonlight-common-c logs directly.

The hop stays: Andy added it so SDL logging does not stall the receive
threads. The line is formatted into a stack buffer on the calling thread
and the block only receives that finished string.

Idempotent. Pass a src directory as argv[1] to test against a copy.
The default path is the submodule src directory. qmake runs this; do not
commit the patched Platform.h. A separate v6.2 rebase of the submodule is
out of scope for this patch.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "moonlight-common-c" / "moonlight-common-c" / "src"

MARKER = "TwilightLimelogEager"

OLD = """\
#if defined(LC_DARWIN)
// Don't give the SDL logger a chance to slow down any threads
# define Limelog(s, ...) \\
    if (ListenerCallbacks.logMessage) { \\
        dispatch_async(dispatch_get_main_queue(), ^{ \\
            ListenerCallbacks.logMessage(s, ##__VA_ARGS__); \\
        }); \\
    }
#else
"""

NEW = """\
#if defined(LC_DARWIN)
// TwilightLimelogEager: format on the calling thread, then hop.
// See scripts/apply_limelog_eager.py. The block copies the heap pointer.
// It must not read the caller's pointers (RtpAudioQueue blockHead and the
// other Limelog arguments) because those are gone by the time the main
// queue runs.
# define Limelog(s, ...) \\
    do { \\
        if (ListenerCallbacks.logMessage) { \\
            char _limelogBuf[4096]; \\
            if (snprintf(_limelogBuf, sizeof(_limelogBuf), s, ##__VA_ARGS__) >= 0) { \\
                char *_limelogCopy = strdup(_limelogBuf); \\
                if (_limelogCopy != NULL) { \\
                    dispatch_async(dispatch_get_main_queue(), ^{ \\
                        if (ListenerCallbacks.logMessage) { \\
                            ListenerCallbacks.logMessage("%s", _limelogCopy); \\
                        } \\
                        free(_limelogCopy); \\
                    }); \\
                } \\
            } \\
        } \\
    } while (0)
#else
"""


def main() -> None:
    path = SRC / "Platform.h"
    if not path.is_file():
        sys.stderr.write(f"moonlight-common-c sources not checked out: {path}\n")
        sys.exit(1)

    text = path.read_text()
    if MARKER in text:
        if "dispatch_async" not in text or 'logMessage("%s"' not in text:
            sys.stderr.write(f"{path}: {MARKER} is present but the macro is not the eager form\n")
            sys.exit(1)
        print(f"already patched {path.name}")
        return

    if OLD not in text:
        sys.stderr.write(f"{path}: expected deferred Limelog macro not found\n")
        sys.exit(1)

    text = text.replace(OLD, NEW, 1)
    if text.count(MARKER) != 1:
        sys.stderr.write(f"{path}: marker was not written once\n")
        sys.exit(1)
    darwin = text.split("#if defined(LC_DARWIN)", 1)[1].split("#else", 1)[0]
    # snprintf may use ##__VA_ARGS__. The block must not.
    if "logMessage(s, ##__VA_ARGS__)" in darwin:
        sys.stderr.write(f"{path}: Darwin Limelog still forwards __VA_ARGS__ into the block\n")
        sys.exit(1)
    if darwin.find("snprintf") < 0 or darwin.find("snprintf") > darwin.find("dispatch_async"):
        sys.stderr.write(f"{path}: Darwin Limelog does not format before dispatch_async\n")
        sys.exit(1)
    path.write_text(text)
    print(f"patched {path.name}")


if __name__ == "__main__":
    main()

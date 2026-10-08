#!/usr/bin/env python3
"""The Limelog patch captures arguments before dispatch_async.

Does not need the moonlight-common-c submodule or an Apple SDK. A copy of
Andy's deferred macro is patched in a temp directory, then the stand-in
queue in tests/limelog_eager_test.c is compiled and run.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
FAILURES = 0

OLD_HEADER = r"""#pragma once
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(LC_DARWIN)
#include <dispatch/dispatch.h>
#endif

#if defined(LC_DARWIN)
// Don't give the SDL logger a chance to slow down any threads
# define Limelog(s, ...) \
    if (ListenerCallbacks.logMessage) { \
        dispatch_async(dispatch_get_main_queue(), ^{ \
            ListenerCallbacks.logMessage(s, ##__VA_ARGS__); \
        }); \
    }
#else
# define Limelog(s, ...) \
    if (ListenerCallbacks.logMessage) \
        ListenerCallbacks.logMessage(s, ##__VA_ARGS__)
#endif
"""


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def run_apply(src):
    return subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "apply_limelog_eager.py"), str(src)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )


def test_patch_is_eager_and_idempotent():
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp)
        header = src / "Platform.h"
        header.write_text(OLD_HEADER, encoding="utf-8")
        first = run_apply(src)
        expect(first.returncode == 0, "first apply exits 0: %s" % first.stderr)
        text = header.read_text(encoding="utf-8")
        expect("TwilightLimelogEager" in text, "marker is written")
        darwin = text.split("#if defined(LC_DARWIN)", 1)[1].split("#else", 1)[0]
        expect("snprintf" in darwin and "strdup" in darwin, "arguments are formatted before the hop")
        expect(darwin.find("snprintf") < darwin.find("dispatch_async"), "snprintf runs before dispatch_async")
        expect("logMessage(s, ##__VA_ARGS__)" not in darwin, "the block does not re-read call arguments")
        expect('logMessage("%s", _limelogCopy)' in darwin, "the block logs the finished line")
        expect("dispatch_async" in darwin, "logging still hops to the main queue")
        expect("logMessage(s, ##__VA_ARGS__)" in text.split("#else", 1)[1], "other platforms still log directly")
        second = run_apply(src)
        expect(second.returncode == 0 and "already patched" in second.stdout, "second apply is a no-op")
        expect(header.read_text(encoding="utf-8") == text, "second apply does not rewrite the header")


def test_missing_macro_fails():
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp)
        (src / "Platform.h").write_text("#pragma once\n", encoding="utf-8")
        result = run_apply(src)
        expect(result.returncode != 0, "a header without the deferred macro is refused")


def test_capture_before_clear():
    source = ROOT / "tests" / "limelog_eager_test.c"
    binary = Path(tempfile.gettempdir()) / "limelog_eager_test"
    compiled = subprocess.run(
        ["gcc", "-std=gnu99", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(binary)],
        capture_output=True,
        text=True,
        check=False,
    )
    expect(compiled.returncode == 0, "limelog stand-in compiles: %s" % compiled.stderr)
    if compiled.returncode != 0:
        return
    ran = subprocess.run([str(binary)], capture_output=True, text=True, check=False)
    expect(ran.returncode == 0, "values survive clearing blockHead: %s" % ran.stderr)


def test_qmake_runs_the_script():
    app = (ROOT / "app" / "app.pro").read_text(encoding="utf-8")
    common = (ROOT / "moonlight-common-c" / "moonlight-common-c.pro").read_text(encoding="utf-8")
    for label, text in (("app.pro", app), ("moonlight-common-c.pro", common)):
        expect("apply_limelog_eager.py" in text, "%s runs the Limelog patch" % label)


def main():
    test_patch_is_eager_and_idempotent()
    test_missing_macro_fails()
    test_capture_before_clear()
    test_qmake_runs_the_script()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

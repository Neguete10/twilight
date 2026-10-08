#!/usr/bin/env python3
"""Qt's shutdown logs must not use a destroyed redaction regex.

The handler is installed for the whole process. Static QRegularExpression
objects are destroyed during exit, and Qt logs again after that. main()
has to drop the handler before it returns, and the patterns themselves are
heap objects with no destructor.
"""

import re
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


def extract_function(text, name):
    match = re.search(r"(?:^|\W)" + re.escape(name) + r"\(", text)
    if match is None:
        return ""
    start = text.rfind("\n", 0, match.start()) + 1
    brace = text.find("{", start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[brace:index + 1]
    return ""


def test_regexes_outlive_static_destruction():
    text = (ROOT / "app" / "main.cpp").read_text(encoding="utf-8")
    expect("static QRegularExpression k_RikeyRegex" not in text, "rikey pattern is not a namespace static")
    expect("static QRegularExpression k_RikeyIdRegex" not in text, "rikeyid pattern is not a namespace static")
    expect(text.count("new QRegularExpression(") == 2, "both patterns are allocated with new")
    expect("delete " not in text[text.find("rikeyRegex"):text.find("void logToLoggerStream")], "the patterns are not freed")
    body = extract_function(text, "logToLoggerStream")
    expect("rikeyRegex()" in body and "rikeyIdRegex()" in body, "the handler uses the heap patterns")


def test_handler_is_removed_on_every_return():
    text = (ROOT / "app" / "main.cpp").read_text(encoding="utf-8")
    finish = extract_function(text, "finishMain")
    expect("qInstallMessageHandler(nullptr)" in finish, "finishMain restores Qt's handler")
    expect("s_LoggerThread.waitForDone" in finish, "queued lines are written before the handler is dropped")
    expect("SDL_LogSetOutputFunction" in finish, "SDL logging stops using the Twilight handler")
    main_body = extract_function(text, "main")
    install_at = main_body.find("qInstallMessageHandler(qtLogToDiskHandler)")
    expect(install_at > 0, "main installs the Qt handler")
    after = main_body[install_at:]
    expect("return -1" not in after, "main does not return -1 while the handler is installed")
    expect(re.search(r"return err\b", after) is None, "main does not return the exec status directly")
    expect(after.count("return finishMain(") == 4, "timer, video, qml, and exec exits drop the handler")


def main():
    test_regexes_outlive_static_destruction()
    test_handler_is_removed_on_every_return()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

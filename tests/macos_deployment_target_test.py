#!/usr/bin/env python3
"""The macOS deployment target is explicit and matches Info.plist.

Does not compile and does not need an Apple SDK. An empty qmake
deployment target lets clang stamp the build Mac's SDK version onto
every Mach-O, which is how a bundle ended up requiring a newer macOS
than this client supports.
"""

import plistlib
import subprocess
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


def version_components(value):
    parts = []
    for piece in value.split("."):
        if piece == "":
            return None
        if not piece.isdigit():
            return None
        parts.append(int(piece))
    return parts


def same_floor(left, right):
    a = version_components(left)
    b = version_components(right)
    if not a or not b:
        return False
    width = max(len(a), len(b))
    a = a + [0] * (width - len(a))
    b = b + [0] * (width - len(b))
    return a == b


def test_floor_matches_plist():
    plist = plistlib.loads((ROOT / "app" / "Info.plist").read_bytes())
    minimum = plist["LSMinimumSystemVersion"]
    script = ROOT / "scripts" / "macos-deployment-target.sh"
    result = subprocess.run(
        ["sh", str(script)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    target = result.stdout.strip()
    expect(result.returncode == 0, "macos-deployment-target.sh exits 0")
    expect(result.stderr == "", "macos-deployment-target.sh is silent on success")
    expect(target == "13.0", "deployment target is 13.0, got %r" % target)
    expect(minimum == "13.0.0", "Info.plist minimum stays 13.0.0, got %r" % minimum)
    expect(same_floor(minimum, target), "deployment target matches LSMinimumSystemVersion")

    pri = (ROOT / "globaldefs.pri").read_text(encoding="utf-8")
    expect("QMAKE_MACOSX_DEPLOYMENT_TARGET = 13.0" in pri, "globaldefs.pri sets the deployment target")
    expect("SDK minos" in pri, "globaldefs.pri refuses an empty deployment target")

    app_pro = (ROOT / "app" / "app.pro").read_text(encoding="utf-8")
    expect("include(../globaldefs.pri)" in app_pro, "app.pro includes globaldefs.pri")
    expect("QMAKE_MACOSX_DEPLOYMENT_TARGET is unset" in app_pro, "app.pro refuses an unset deployment target")
    expect("Twilight macOS deployment target:" in app_pro, "app qmake prints the deployment target")


def test_qmake_projects_include_globaldefs():
    for pro in sorted(ROOT.rglob("*.pro")):
        rel = pro.relative_to(ROOT).as_posix()
        if rel.startswith("config.tests/"):
            continue
        text = pro.read_text(encoding="utf-8")
        if "TEMPLATE = subdirs" in text or "TEMPLATE=subdirs" in text:
            continue
        expect("globaldefs.pri" in text, "%s includes globaldefs.pri" % rel)


def test_pyrowave_and_dmg_scripts():
    dmg = (ROOT / "scripts" / "generate-dmg.sh").read_text(encoding="utf-8")
    pri = (ROOT / "pyrowave" / "build-config.pri").read_text(encoding="utf-8")
    expect("macos-deployment-target.sh" in dmg, "dmg reads the deployment target")
    expect('export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"' in dmg, "dmg exports the deployment target")
    expect('QMAKE_MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"' in dmg, "dmg passes the deployment target to qmake")
    expect("QMAKE_APPLE_DEVICE_ARCHS=\"arm64\"" in dmg or 'DEVICE_ARCHS="arm64"' in dmg, "dmg is arm64 only")
    expect("contains(CONFIG, pyrowave)" in pri, "PyroWave Metal is gated on CONFIG+=pyrowave")
    expect("check-macos-minos.py" in dmg, "dmg rejects a Mach-O above the deployment floor")


def main():
    test_floor_matches_plist()
    test_qmake_projects_include_globaldefs()
    test_pyrowave_and_dmg_scripts()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

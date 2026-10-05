#!/usr/bin/env python3
"""The macOS deployment target is explicit and matches Info.plist.

Does not compile and does not need an Apple SDK. 7.0.0 shipped with
minos equal to the build Mac's SDK (27.0) because qmake and the PyroWave
cmake lines never set a deployment target.
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
    expect(target == "11.0", "deployment target is 11.0, got %r" % target)
    expect(minimum == "11.0.0", "Info.plist minimum stays 11.0.0, got %r" % minimum)
    expect(same_floor(minimum, target), "deployment target matches LSMinimumSystemVersion")

    pri = (ROOT / "globaldefs.pri").read_text(encoding="utf-8")
    expect("QMAKE_MACOSX_DEPLOYMENT_TARGET = 11.0" in pri, "globaldefs.pri sets the deployment target")
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
    metal = (ROOT / "scripts" / "build-pyrowave-metal.sh").read_text(encoding="utf-8")
    shared = (ROOT / "scripts" / "build-pyrowave-shared.sh").read_text(encoding="utf-8")
    dmg = (ROOT / "scripts" / "generate-dmg.sh").read_text(encoding="utf-8")
    for label, text in (
        ("metal", metal),
        ("shared", shared),
        ("dmg", dmg),
    ):
        expect("macos-deployment-target.sh" in text, "%s reads the deployment target" % label)
    expect('-DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"' in metal, "metal cmake sets minos")
    expect('-DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"' in shared, "shared cmake sets minos")
    expect('uname -s' in shared and "Darwin" in shared, "shared cmake minos is macOS-only")
    expect('export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"' in dmg, "dmg exports the deployment target")
    expect('QMAKE_MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"' in dmg, "dmg passes the deployment target to qmake")
    for label, text in (("metal", metal), ("shared", shared)):
        expect("CMakeCache.txt" in text and "rm -rf" in text, "%s drops a stale SDK-default cmake cache" % label)


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

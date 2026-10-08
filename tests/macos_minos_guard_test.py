#!/usr/bin/env python3
"""Bundle guard: minos, outside rpaths, and plug-ins with missing libraries.

Builds tiny Mach-O files in memory. Also reads moonlight-qt-deps v19 when
/tmp/macOS-universal.zip is already on disk. Does not need an Apple SDK.
"""

import hashlib
import importlib.util
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
FAILURES = 0

LC_LOAD_DYLIB = 0xC
LC_ID_DYLIB = 0xD
LC_RPATH = 0x8000001C
LC_BUILD_VERSION = 0x32
MH_MAGIC_64 = 0xFEEDFACF
CPU_ARM64 = 0x0100000C
MH_DYLIB = 6


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def load_macho():
    path = ROOT / "scripts" / "macos_macho.py"
    spec = importlib.util.spec_from_file_location("macos_macho", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def lc_dylib(cmd, name):
    raw = name.encode() + b"\0"
    nameoff = 24
    cmdsize = (nameoff + len(raw) + 7) & ~7
    blob = struct.pack("<IIIIII", cmd, cmdsize, nameoff, 0, 0, 0) + raw
    return blob + b"\0" * (cmdsize - len(blob))


def lc_rpath(path):
    raw = path.encode() + b"\0"
    nameoff = 12
    cmdsize = (nameoff + len(raw) + 7) & ~7
    blob = struct.pack("<III", LC_RPATH, cmdsize, nameoff) + raw
    return blob + b"\0" * (cmdsize - len(blob))


def lc_minos(major, minor=0, patch=0):
    packed = (major << 16) | (minor << 8) | patch
    return struct.pack("<IIIIII", LC_BUILD_VERSION, 24, 1, packed, packed, 0)


def thin_macho(minos, rpaths=(), loads=(), ident="@rpath/fixture.dylib"):
    commands = [lc_minos(*minos), lc_dylib(LC_ID_DYLIB, ident)]
    for rpath in rpaths:
        commands.append(lc_rpath(rpath))
    for load in loads:
        commands.append(lc_dylib(LC_LOAD_DYLIB, load))
    body = b"".join(commands)
    header = struct.pack(
        "<IIIIIIII",
        MH_MAGIC_64,
        CPU_ARM64,
        0,
        MH_DYLIB,
        len(commands),
        len(body),
        0,
        0,
    )
    return header + body


def test_versions(macho):
    expect(not macho.version_gt("13.0", "13.0.0"), "13.0 is not newer than 13.0.0")
    expect(not macho.version_gt("12.0.0", "13.0"), "MoltenVK minos 12 is allowed on a 13 floor")
    expect(macho.version_gt("13.1", "13.0"), "13.1 is newer than 13.0")
    expect(macho.version_gt("27.0", "13.0"), "minos 27 is newer than 13")


def test_bundle_policy(macho):
    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp) / "Twilight.app"
        frameworks = bundle / "Contents" / "Frameworks"
        plugins = bundle / "Contents" / "PlugIns" / "pdf"
        macos = bundle / "Contents" / "MacOS"
        frameworks.mkdir(parents=True)
        plugins.mkdir(parents=True)
        macos.mkdir(parents=True)
        (frameworks / "QtCore").write_bytes(thin_macho((13, 0, 0), ident="@rpath/QtCore"))
        (frameworks / "libplacebo.dylib").write_bytes(
            thin_macho((13, 0, 0), loads=("/usr/lib/libSystem.B.dylib",), ident="@rpath/libplacebo.dylib")
        )
        (macos / "Twilight").write_bytes(
            thin_macho(
                (13, 0, 0),
                rpaths=("@executable_path/../Frameworks",),
                loads=("@rpath/QtCore", "/usr/lib/libSystem.B.dylib"),
                ident="@rpath/Twilight",
            )
        )
        pdf = plugins / "libqpdf.dylib"
        pdf.write_bytes(
            thin_macho(
                (27, 0, 0),
                rpaths=("/opt/homebrew/lib", "@executable_path/../Frameworks"),
                loads=(
                    "@rpath/QtPdf.framework/Versions/A/QtPdf",
                    "@rpath/QtCore",
                    "/usr/lib/libSystem.B.dylib",
                ),
                ident="@rpath/libqpdf.dylib",
            )
        )
        problems = macho.describe_problems(bundle, "13.0")
        expect(any("MINOS 27.0.0 > 13.0" in line and "libqpdf" in line for line in problems), "minos 27 fails")
        expect(any(line.startswith("RPATH /opt/homebrew/lib") for line in problems), "Homebrew rpath fails")
        expect(any("UNRESOLVED @rpath/QtPdf" in line for line in problems), "missing QtPdf fails")
        expect(not any("Twilight" in line and "UNRESOLVED" in line for line in problems), "the executable's QtCore resolves")
        orphans = macho.orphan_plugins(bundle)
        expect(len(orphans) == 1 and orphans[0][0] == pdf, "the PDF plug-in is the orphan")
        expect(not any("QtCore" == path.name for path, _missing in macho.orphan_plugins(bundle)), "frameworks are not dropped")
        bad = subprocess.run(
            ["bash", str(ROOT / "scripts" / "check-macos-minos.sh"), str(bundle), "13.0"],
            capture_output=True,
            text=True,
            check=False,
        )
        expect(bad.returncode == 1 and "MINOS 27.0.0" in bad.stdout, "the shell guard fails the PDF plug-in")
        pdf.unlink()
        good = subprocess.run(
            ["bash", str(ROOT / "scripts" / "check-macos-minos.sh"), str(bundle), "13.0"],
            capture_output=True,
            text=True,
            check=False,
        )
        expect(good.returncode == 0 and "OK" in good.stdout, "the shell guard accepts the rest: %s" % good.stderr)
        outside = macho.outside_rpaths(bundle)
        expect(outside == [], "no outside rpath remains after the plug-in is gone")
        expect(macho.describe_problems(bundle, "13.0") == [], "the rest of the bundle is loadable on macOS 13")


def test_users_rpath_and_absolute_prefix(macho):
    data = thin_macho(
        (13, 0, 0),
        rpaths=("/Users/builder/qt/lib", "/tmp/macos-deps/prefix/lib"),
        loads=("/usr/lib/libSystem.B.dylib",),
    )
    images = macho.parse_macho(data)
    expect(len(images) == 1 and images[0]["minos"] == ["13.0.0"], "thin minos is 13.0.0")
    bundle = Path("/Applications/Twilight.app")
    expect(all(macho.rpath_outside_bundle(rpath, bundle) for rpath in images[0]["rpaths"]), "absolute rpaths are outside")
    expect(not macho.rpath_outside_bundle("@executable_path/../Frameworks", bundle), "bundle rpath is inside")


def test_v19_prebuilts_if_present(macho):
    archive = Path("/tmp/macOS-universal.zip")
    if not archive.is_file():
        print("skip v19 zip")
        return
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    expect(
        digest == "39fab7c95f5d513a6eb3bb19c66f1ae66bbf41dfe4118f82fabe3b46cc502d17",
        "v19 zip sha256",
    )
    with zipfile.ZipFile(archive) as zipped:
        for name in ("lib/libplacebo.dylib", "lib/libMoltenVK.dylib"):
            images = macho.parse_macho(zipped.read(name))
            expect(len(images) == 2, "%s is universal" % name)
            for image in images:
                expect(image["minos"] == ["13.0.0"] or image["minos"] == ["12.0.0"], "%s minos %s" % (name, image["minos"]))
                expect(all(macho.is_system_dependency(dep) for dep in image["loads"]), "%s links only system libraries" % name)
                expect(image["rpaths"] == [], "%s has no LC_RPATH" % name)


def test_scripts_and_floor():
    deps = (ROOT / "scripts" / "build-macos-deps.sh").read_text(encoding="utf-8")
    dmg = (ROOT / "scripts" / "generate-dmg.sh").read_text(encoding="utf-8")
    pri = (ROOT / "globaldefs.pri").read_text(encoding="utf-8")
    plist = (ROOT / "app" / "Info.plist").read_text(encoding="utf-8")
    expect("6.11.2" in deps, "deps script defaults to Qt 6.11.2")
    expect("qtshadertools qtimageformats" in deps, "Qt 6.11 gets shadertools and imageformats")
    expect("-m qtshadertools qtimageformats" in deps and "qtpdf" not in deps.split("-m qtshadertools qtimageformats", 1)[1].split("\n", 1)[0], "the aqt module list does not install QtPdf")
    expect("moonlight-qt-deps" in deps and "v19" in deps, "libplacebo and MoltenVK come from deps v19")
    expect("Vulkan-Loader" in deps, "the Vulkan loader is still built from source")
    expect("shaderc.git" not in deps and "Little-CMS" not in deps and "libplacebo.git" not in deps, "shaderc, lcms, and libplacebo are not source-built")
    expect("MoltenVK.git" not in deps, "MoltenVK is not source-built")
    expect('cd "$DEPS"' in deps, "aqt runs inside the deps tree, not the repo root")
    expect(not (ROOT / "aqtinstall.log").exists(), "aqtinstall.log is not in the tree")
    expect("QMAKE_MACOSX_DEPLOYMENT_TARGET = 13.0" in pri, "globaldefs floor is 13.0")
    expect("<string>13.0.0</string>" in plist, "Info.plist minimum is 13.0.0")
    expect("prepare-macos-bundle.py" in dmg, "generate-dmg strips rpaths and drops orphan plug-ins")
    expect("check-macos-minos.sh" in dmg, "generate-dmg runs the guard")
    expect('"$DMG_ROOT/Twilight.app"' in dmg, "the staged app is checked")
    expect(
        'codesign --force --deep --options runtime --timestamp \\\n      --sign "$SIGNING_IDENTITY" \\\n      $BUILD_FOLDER/app/Twilight.app'
        in dmg,
        "Developer ID signing stays hardened runtime with no entitlements",
    )
    expect("CONFIG+=pyrowave" in dmg, "desktop builds keep PyroWave")
    result = subprocess.run(
        ["bash", "-n", str(ROOT / "scripts" / "build-macos-deps.sh")],
        capture_output=True,
        text=True,
        check=False,
    )
    expect(result.returncode == 0, "build-macos-deps.sh parses: %s" % result.stderr)
    result = subprocess.run(
        ["bash", "-n", str(ROOT / "scripts" / "check-macos-minos.sh")],
        capture_output=True,
        text=True,
        check=False,
    )
    expect(result.returncode == 0, "check-macos-minos.sh parses: %s" % result.stderr)
    result = subprocess.run(
        ["bash", "-n", str(ROOT / "scripts" / "generate-dmg.sh")],
        capture_output=True,
        text=True,
        check=False,
    )
    expect(result.returncode == 0, "generate-dmg.sh parses: %s" % result.stderr)
    usage = subprocess.run(
        ["bash", str(ROOT / "scripts" / "check-macos-minos.sh")],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    expect(usage.returncode == 2, "guard usage exits 2")


def main():
    macho = load_macho()
    test_versions(macho)
    test_bundle_policy(macho)
    test_users_rpath_and_absolute_prefix(macho)
    test_v19_prebuilts_if_present(macho)
    test_scripts_and_floor()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

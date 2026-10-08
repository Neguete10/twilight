#!/usr/bin/env python3
"""Checks the Mac App Store prep that does not need an Apple SDK."""

import importlib.util
import plistlib
import struct
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


def load_prepare():
    path = ROOT / "scripts" / "prepare-macos-infoplist.py"
    spec = importlib.util.spec_from_file_location("prepare_macos_infoplist", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def plist_keys(path):
    return set(plistlib.loads(path.read_bytes()))


def test_plist_rewrite():
    module = load_prepare()
    template = (ROOT / "app" / "Info.plist").read_text(encoding="utf-8")
    desktop = module.prepare(
        template, "6.1.1", "com.moonlight-stream.Moonlight", "Twilight", "desktop"
    )
    mas = module.prepare(
        template, "6.1.1", "com.henrique.twilight", "Twilight", "mas"
    )
    desktop_plist = plistlib.loads(desktop.encode("utf-8"))
    mas_plist = plistlib.loads(mas.encode("utf-8"))
    expect(
        desktop_plist["NSAppTransportSecurity"] == {"NSAllowsArbitraryLoads": True},
        "desktop ATS stays NSAllowsArbitraryLoads",
    )
    expect(
        "NSAllowsLocalNetworking" not in desktop_plist["NSAppTransportSecurity"],
        "desktop ATS does not set NSAllowsLocalNetworking",
    )
    expect(
        mas_plist["NSAppTransportSecurity"] == {"NSAllowsLocalNetworking": True},
        "MAS ATS is NSAllowsLocalNetworking only",
    )
    expect(
        "NSAllowsArbitraryLoads" not in mas_plist["NSAppTransportSecurity"],
        "MAS ATS does not set NSAllowsArbitraryLoads",
    )
    expect(desktop_plist["CFBundleIdentifier"] == "com.moonlight-stream.Moonlight", "desktop bundle id")
    expect(mas_plist["CFBundleIdentifier"] == "com.henrique.twilight", "MAS bundle id")
    expect(desktop_plist["CFBundleShortVersionString"] == "6.1.1", "plist writes the version qmake passes")
    expect(template.count("<string>VERSION</string>") == 2, "Info.plist keeps the qmake version token")
    tree_version = (ROOT / "app" / "version.txt").read_text(encoding="utf-8").strip()
    wired = module.prepare(
        template, tree_version, "com.moonlight-stream.Moonlight", "Twilight", "desktop"
    )
    wired_plist = plistlib.loads(wired.encode("utf-8"))
    expect(wired_plist["CFBundleShortVersionString"] == tree_version, "short version follows version.txt")
    expect(wired_plist["CFBundleVersion"] == tree_version, "bundle version follows version.txt")
    expect("6.1.1" not in template, "Info.plist does not hardcode 6.1.1")
    pro = (ROOT / "app" / "app.pro").read_text(encoding="utf-8")
    expect("$$cat(version.txt)" in pro, "qmake passes version.txt into Info.plist")
    expect(
        "Twilight uses the microphone" in desktop_plist["NSMicrophoneUsageDescription"],
        "microphone usage string",
    )


def test_entitlements():
    base = plistlib.loads((ROOT / "app/deploy/macos/Twilight-MAS.entitlements").read_bytes())
    multi = plistlib.loads((ROOT / "app/deploy/macos/Twilight-MAS-multicast.entitlements").read_bytes())
    required = {
        "com.apple.security.app-sandbox",
        "com.apple.security.device.audio-input",
        "com.apple.security.network.client",
        "com.apple.security.network.server",
        "com.apple.developer.spatial-audio.profile-access",
        "com.apple.developer.coremotion.head-pose",
    }
    forbidden = {
        "com.apple.security.cs.disable-library-validation",
        "com.apple.security.cs.allow-jit",
        "com.apple.security.cs.allow-unsigned-executable-memory",
        "com.apple.developer.networking.multicast",
    }
    expect(required <= set(base), "base MAS entitlements")
    expect(not (forbidden & set(base)), "base MAS file omits jit, library validation, and multicast")
    expect(set(multi) == set(base) | {"com.apple.developer.networking.multicast"}, "multicast file is the base plus one key")
    expect(all(base[key] is True and multi[key] is True for key in required), "entitlement values are true")


def test_privacy_manifest():
    privacy = plistlib.loads((ROOT / "app/deploy/macos/PrivacyInfo.xcprivacy").read_bytes())
    expect(privacy.get("NSPrivacyTracking") is False, "tracking is false")
    expect("NSPrivacyCollectedDataTypes" not in privacy, "no invented collected-data keys")
    reasons = {}
    for entry in privacy["NSPrivacyAccessedAPITypes"]:
        reasons[entry["NSPrivacyAccessedAPIType"]] = entry["NSPrivacyAccessedAPITypeReasons"]
    expect(
        reasons == {
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["8FFB.1"],
        },
        "required-reason APIs match the calls in this tree",
    )


def test_notices():
    notices = (ROOT / "app/licenses/NOTICES.txt").read_text(encoding="utf-8")
    qml = (ROOT / "app/gui/ui/v2/SettingsSheetV2.qml").read_text(encoding="utf-8")
    qrc = (ROOT / "app/qml.qrc").read_text(encoding="utf-8")
    phrases = [
        "modified version of Moonlight Qt",
        "Andy Grundman",
        "ABSOLUTELY NO WARRANTY",
        "WITHOUT ANY WARRANTY",
        "https://github.com/Neguete10/twilight",
        "Nathan Osman",
        "h264bitstream",
        "SDL_GameControllerDB",
        "FFmpeg",
        "OpenSSL",
        "Opus",
        "SDL2",
        "libplacebo",
        "qmdnsengine",
    ]
    for phrase in phrases:
        expect(phrase in notices, "NOTICES.txt contains %s" % phrase)
    expect("https://github.com/Neguete10/twilight" in qml, "About UI links the source")
    expect("language" not in qml.lower(), "About UI has no language picker")
    license_names = [
        "GPL-3.0.txt",
        "qmdnsengine-MIT.txt",
        "h264bitstream-LGPL-2.1.txt",
        "SDL_GameControllerDB-Zlib.txt",
        "FFmpeg-LGPL-2.1.txt",
        "OpenSSL-Apache-2.0.txt",
        "Opus-BSD.txt",
        "SDL2-Zlib.txt",
        "SDL2_ttf-Zlib.txt",
        "libplacebo-LGPL-2.1.txt",
        "NOTICES.txt",
    ]
    for name in license_names:
        path = ROOT / "app" / "licenses" / name
        expect(path.is_file() and path.stat().st_size > 80, "license file %s" % name)
        expect(name in qrc, "qrc ships %s" % name)
        expect(name in qml or name == "NOTICES.txt", "About UI can open %s" % name)
    gpl = (ROOT / "app/licenses/GPL-3.0.txt").read_bytes()
    expect(gpl == (ROOT / "LICENSE").read_bytes(), "GPL-3.0.txt is the repo LICENSE")
    expect(b"GNU LESSER GENERAL PUBLIC LICENSE" in (ROOT / "app/licenses/h264bitstream-LGPL-2.1.txt").read_bytes(), "h264bitstream LGPL text")
    expect(b"Apache License" in (ROOT / "app/licenses/OpenSSL-Apache-2.0.txt").read_bytes(), "OpenSSL Apache text")
    expect(b"Nathan Osman" in (ROOT / "app/licenses/qmdnsengine-MIT.txt").read_bytes(), "qmdnsengine copyright")
    version = (ROOT / "app/version.txt").read_text(encoding="utf-8").strip()
    expect(version == "7.0.2", "version is 7.0.2")


def test_package_script():
    script = ROOT / "scripts" / "generate-dmg.sh"
    text = script.read_text(encoding="utf-8")
    expect("productbuild --component" in text, "MAS path calls productbuild")
    expect("3rd Party Mac Developer Application: Your Name (TEAMID)" in text, "application identity placeholder")
    expect("3rd Party Mac Developer Installer: Your Name (TEAMID)" in text, "installer identity placeholder")
    expect("create-dmg" in text, "desktop path still creates a DMG")
    expect("spatial-audio.entitlements" in text, "desktop signing still uses the spatial entitlements")

    def run(env, config):
        result = subprocess.run(
            ["bash", str(script), config],
            cwd=str(ROOT),
            env=env,
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stderr

    base = {"PATH": "/usr/bin:/bin"}
    code, err = run(dict(base, TWILIGHT_MAS="1"), "Release")
    expect(code != 0 and "SIGNING_IDENTITY" in err and "3rd Party Mac Developer Application" in err, "missing SIGNING_IDENTITY fails clearly")
    code, err = run(dict(base, TWILIGHT_MAS="1", SIGNING_IDENTITY="test-application"), "Release")
    expect(code != 0 and "INSTALLER_SIGNING_IDENTITY" in err and "3rd Party Mac Developer Installer" in err, "missing installer identity fails clearly")
    code, err = run(dict(
        base,
        TWILIGHT_MAS="1",
        SIGNING_IDENTITY="test-application",
        INSTALLER_SIGNING_IDENTITY="test-installer",
    ), "Release")
    expect(code != 0 and "PROVISIONING_PROFILE" in err, "missing provisioning profile fails clearly")
    code, err = run(base, "Nope")
    expect(code != 0 and "Invalid build configuration" in err, "desktop invocation still checks Debug or Release")
    multicast_at = text.find("TWILIGHT_MAS_MULTICAST")
    mas_at = text.find('TWILIGHT_MAS:-}" = "1"')
    expect(multicast_at > mas_at > 0, "multicast entitlement is selected only on the store path")


def png_size(path):
    data = path.read_bytes()
    expect(data[:8] == b"\x89PNG\r\n\x1a\n", "%s is a png" % path.name)
    expect(data[12:16] == b"IHDR", "%s has an IHDR" % path.name)
    return struct.unpack(">II", data[16:24])


def load_dmg_layout():
    values = {}
    for raw in (ROOT / "app/deploy/macos/dmg/layout.env").read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def test_dmg_layout():
    layout = load_dmg_layout()
    width = int(layout["DMG_WINDOW_W"])
    height = int(layout["DMG_WINDOW_H"])
    expect(layout["DMG_VOLNAME"] == "Twilight", "volume name is Twilight")
    expect(int(layout["DMG_APP_X"]) < int(layout["DMG_APPLICATIONS_X"]), "Twilight.app sits left of Applications")
    expect("Applications" in layout["DMG_CAPTION"], "caption tells people to use Applications")
    one = png_size(ROOT / "app/deploy/macos/dmg/background.png")
    two = png_size(ROOT / "app/deploy/macos/dmg/background@2x.png")
    expect(one == (width, height), "background.png matches the Finder window")
    expect(two == (width * 2, height * 2), "retina background is twice the window")

    script = (ROOT / "scripts" / "generate-dmg.sh").read_text(encoding="utf-8")
    expect('. "$SOURCE_ROOT/app/deploy/macos/dmg/layout.env"' in script, "dmg script sources the layout")
    for flag in (
        "--volname",
        "--background",
        "--window-pos",
        "--window-size",
        "--icon-size",
        '--icon "Twilight.app"',
        "--app-drop-link",
    ):
        expect(flag in script, "desktop dmg passes %s" % flag)
    expect("--filesystem" not in script, "Finder window styling stays on the default HFS+ image")
    expect("background@2x.png" in script, "retina background is staged")
    expect('"$DMG_ROOT/Twilight.app"' in script, "staged bundle is Twilight.app")
    expect("ln -s /Applications" not in script, "Applications alias is create-dmg's drop link")
    creating = script.find("echo Creating DMG")
    mas_exit = script.find("exit 0")
    expect(0 < mas_exit < creating, "store package exits before the disk image")
    expect("create-dmg $BUILD_FOLDER/app/Twilight.app" not in script, "bare create-dmg invocation is gone")
    expect("--identity=" not in script, "desktop dmg does not use the npm identity flag")
    expect("Twilight\\ $VERSION.dmg" not in script, "dmg filename is hyphenated")
    expect('"$DMG_PATH"' in script, "notarization uses the hyphenated dmg path")
    generator = (ROOT / "scripts" / "make_dmg_background.py").read_text(encoding="utf-8")
    expect("python3 scripts/make_dmg_background.py" in generator, "background regen command is documented")
    expect("layout.env" in generator, "generator reads the shared layout")


def main():
    test_plist_rewrite()
    test_entitlements()
    test_privacy_manifest()
    test_notices()
    test_package_script()
    test_dmg_layout()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

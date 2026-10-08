#!/usr/bin/env python3
"""Source checks for the Mac rebuild fixes. No Qt and no Apple SDK."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAILURES = 0


def expect(cond, message):
    global FAILURES
    if not cond:
        FAILURES += 1
        print("FAIL:", message)


def text(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_static_decoder_choice():
    session = text("app/streaming/session.cpp")
    header = text("app/streaming/session.h")
    expect("static int s_PyroWaveBackend" in session, "probed backend is a static")
    expect("s_PyroWaveBackend = static_cast<int>(PyroWaveGpuBackend::None)" in session, "constructor clears the probe")
    expect("StreamingPreferences::get()" in session, "static chooser reads the shared preferences")
    expect("m_PyroWaveBackend" not in session and "m_PyroWaveBackend" not in header, "instance backend member is gone")
    # The static method must not touch Session members. The probe block is the PyroWave section.
    start = session.find("if (videoFormat & VIDEO_FORMAT_MASK_PYROWAVE)")
    end = session.find("#ifdef HAVE_SLVIDEO", start)
    block = session[start:end]
    expect("m_Preferences" not in block, "chooseDecoder does not use m_Preferences")


def test_opus_and_stats_and_duplicates():
    expect("#include <opus.h>" in text("app/streaming/audio/microphone/mic_capture_mac.mm"), "v19 opus header")
    expect("opus/opus.h" not in text("app/streaming/audio/microphone/mic_capture_mac.mm"), "no nested opus include")
    stats_h = text("app/streaming/stats.h")
    stats = text("app/streaming/stats.cpp")
    expect("uint64_t receivedVideoBytes;" in stats_h, "VIDEO_STATS has receivedVideoBytes")
    expect("receivedVideoBytes +=" in stats, "shared stats fill receivedVideoBytes")
    pro = text("app/app.pro")
    expect("TWILIGHT_HAS_SF_SYMBOLS" in pro, "macOS hides the SF Symbol fallback")
    sources = pro.split("SOURCES +=", 1)[1].split("\n!macx {", 1)[0]
    non_mac = pro.split("\n!macx {", 1)[1].split("\nmacx {", 1)[0]
    expect("mic_permission.cpp" not in sources, "mic stub is not in the unconditional sources")
    expect("dualsense_hid.cpp" not in sources, "hid stub is not in the unconditional sources")
    expect("mic_permission.cpp" in non_mac and "dualsense_hid.cpp" in non_mac, "stubs compile off macOS")


def test_host_list_and_cli_and_mic_patch():
    init = text("app/gui/computermodel.cpp").split("void ComputerModel::handleComputerStateChanged", 1)[0]
    expect("beginResetModel();" in init and "endResetModel();" in init, "initialize resets the host model")
    cli = text("app/cli/commandlineparser.cpp")
    expect('"pyrowave-backend"' in cli, "CLI exposes --pyrowave-backend")
    expect("PWBC_VULKAN" in cli and "PWBC_METAL" in cli and "PWBC_AUTO" in cli, "backend choices")
    common = text("moonlight-common-c/moonlight-common-c.pro")
    expect("apply_mic_control_packet.py" in common, "common-c applies the mic patch before it compiles")


def test_vulkan_bundle():
    dmg = text("scripts/generate-dmg.sh")
    bundle = text("scripts/bundle-macos-vulkan.sh")
    main = text("app/main.cpp")
    expect("bundle-macos-vulkan.sh" in dmg, "dmg bundles the Vulkan loader")
    expect("libvulkan.1.dylib" in bundle, "loader is libvulkan.1")
    expect("vulkan-sdk-1.4.363.0" in bundle, "loader tag is 1.4.363")
    expect("MoltenVK_icd.json" in bundle, "ICD manifest is written")
    expect('"../../../Frameworks/libMoltenVK.dylib"' in bundle, "ICD path is bundle-relative")
    expect("is_portability_driver" in bundle, "MoltenVK is a portability ICD")
    expect("VK_DRIVER_FILES" in main and "SDL_Vulkan_LoadLibrary" in main, "process loads the bundled loader")
    minos = dmg.find("check-macos-minos.py")
    copy = dmg.find("bundle-macos-vulkan.sh")
    sign = dmg.find("codesign --force")
    expect(0 < copy < minos < sign, "loader is copied before the minos check and signing")


def main():
    test_static_decoder_choice()
    test_opus_and_stats_and_duplicates()
    test_host_list_and_cli_and_mic_patch()
    test_vulkan_bundle()
    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

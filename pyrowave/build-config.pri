# Match qmake's macOS target selection, including native and universal builds.
macx {
    PYROWAVE_TARGET_ARCHS = $$QMAKE_APPLE_DEVICE_ARCHS
    isEmpty(PYROWAVE_TARGET_ARCHS) {
        only_active_arch: PYROWAVE_TARGET_ARCHS = $$system(uname -m)
        else: PYROWAVE_TARGET_ARCHS = $$QT_ARCHS
    }

    # Opt-in only. CONFIG+=pyrowave (or pyrowave-metal) on an arm64 Mac
    # slice builds the Metal decoder and the Vulkan/MoltenVK decoder.
    # Automatic codec selection never advertises PyroWave; that stays a
    # forced codec choice. The Vulkan backend is an explicit settings choice.
    contains(PYROWAVE_TARGET_ARCHS, arm64):contains(CONFIG, pyrowave): CONFIG += pyrowave-metal
}

# Support debug and release builds from command line for CI
CONFIG += debug_and_release

# Ensure symbols are always generated
CONFIG += force_debug_info

# Disable asserts on release builds
CONFIG(release, debug|release) {
    DEFINES += NDEBUG
}

# Enable ASan for Linux or macOS
#CONFIG += sanitizer sanitize_address

# Enable ASan for Windows
#QMAKE_CFLAGS += -fsanitize=address
#QMAKE_CXXFLAGS += -fsanitize=address
#QMAKE_LFLAGS += -incremental:no -wholearchive:clang_rt.asan_dynamic-x86_64.lib -wholearchive:clang_rt.asan_dynamic_runtime_thunk-x86_64.lib

# macOS minos for every qmake target that includes this file: the Twilight
# app and the static libraries linked into it. This is the same floor as
# LSMinimumSystemVersion (13.0.0) in app/Info.plist. scripts/macos-deployment-target.sh
# reads the assignment below and passes it to the PyroWave dylib builds.
# Do not remove it. With no deployment target, clang stamps the SDK version,
# which is why the 7.0.0 binary (minos 27.0) would not launch on Sequoia.
# 13.0 matches upstream Moonlight 6.2.0 and official Qt 6.11.2. The app is
# Apple Silicon only.
macx {
    QMAKE_MACOSX_DEPLOYMENT_TARGET = 13.0
    isEmpty(QMAKE_MACOSX_DEPLOYMENT_TARGET) {
        error("QMAKE_MACOSX_DEPLOYMENT_TARGET is empty. Refusing to build with the SDK minos.")
    }
}

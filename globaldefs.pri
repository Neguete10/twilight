# Support debug and release builds from command line for CI
CONFIG += debug_and_release

# Ensure symbols are always generated
CONFIG += force_debug_info

# Disable asserts on release builds
CONFIG(release, debug|release) {
    DEFINES += NDEBUG
}

# Enable CFG, EHCont, and CET
*-msvc {
    QMAKE_CFLAGS += -guard:cf -guard:ehcont
    QMAKE_CXXFLAGS += -guard:cf -guard:ehcont
    QMAKE_LFLAGS += -guard:cf -guard:ehcont

    contains(QT_ARCH, x86_64) {
        QMAKE_LFLAGS += -cetcompat
    }
}

# Enable ASan for Linux or macOS
#CONFIG += sanitizer sanitize_address

# Enable ASan for Windows
#QMAKE_CFLAGS += -fsanitize=address
#QMAKE_CXXFLAGS += -fsanitize=address
#QMAKE_LFLAGS += -incremental:no

# Propagate environment variable flags
QMAKE_CFLAGS   += $$(CFLAGS)
QMAKE_CXXFLAGS += $$(CXXFLAGS)
QMAKE_LFLAGS   += $$(LDFLAGS)

# Refuse to inherit the SDK minos. An empty QMAKE_MACOSX_DEPLOYMENT_TARGET
# lets clang stamp the build Mac's SDK version onto every Mach-O.
QMAKE_MACOSX_DEPLOYMENT_TARGET = 13.0

macx {
    # Uses -mmacosx-version-min from the deployment target above. A macOS 14+
    # API outside @available / API_AVAILABLE is an error, so it cannot become
    # a strong symbol that dyld aborts on macOS 13.
    QMAKE_CFLAGS += -Werror=unguarded-availability-new
    QMAKE_OBJECTIVE_CFLAGS += -Werror=unguarded-availability-new
    QMAKE_CXXFLAGS += -Werror=unguarded-availability-new
    QMAKE_OBJCXXFLAGS += -Werror=unguarded-availability-new
}

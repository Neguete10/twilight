QT -= core gui

TARGET = imgui
TEMPLATE = lib

# Build a static library
CONFIG += staticlib

# Include global qmake defs
include(../globaldefs.pri)

# The docking pin opens its own SDL gamepads. Shutdown must not close them
# after the stream has quit the gamecontroller subsystem. The script is
# idempotent. This repo cannot publish a commit on the imgui remote.
!system(python3 $$PWD/../scripts/apply_imgui_gamepad_shutdown.py) {
    error("Failed to apply the ImGui gamepad shutdown patch")
}

INCLUDEPATH += \
    $$PWD/imgui \
    $$PWD/imgui/backends \
    $$PWD/implot

SOURCES += \
    $$PWD/imgui/imgui.cpp \
    $$PWD/imgui/imgui_demo.cpp \
    $$PWD/imgui/imgui_draw.cpp \
    $$PWD/imgui/imgui_tables.cpp \
    $$PWD/imgui/imgui_widgets.cpp \
    $$PWD/imgui/backends/imgui_impl_sdl2.cpp \
    $$PWD/implot/implot.cpp \
    $$PWD/implot/implot_items.cpp \
    $$PWD/implot/implot_demo.cpp

HEADERS += \
    $$PWD/imgui/imgui_config.h \
    $$PWD/imgui/imgui.h \
    $$PWD/imgui/imgui_internal.h \
    $$PWD/imgui/backends/imgui_impl_sdl2.h \
    $$PWD/implot/implot.h \
    $$PWD/implot/implot_internal.h

win32 {
    SOURCES += \
        $$PWD/imgui/backends/imgui_impl_dx11.cpp
    HEADERS += \
        $$PWD/imgui/backends/imgui_impl_dx11.h

    contains(QT_ARCH, x86_64) {
        LIBS += -L$$PWD/../libs/windows/lib/x64
        INCLUDEPATH += $$PWD/../libs/windows/include/x64 $$PWD/../libs/windows/include/x64/SDL2
    }
    contains(QT_ARCH, arm64) {
        LIBS += -L$$PWD/../libs/windows/lib/arm64
        INCLUDEPATH += $$PWD/../libs/windows/include/arm64 $$PWD/../libs/windows/include/arm64/SDL2
    }
}

macx:!disable-prebuilts {
    INCLUDEPATH += $$PWD/../libs/mac/include $$PWD/../libs/mac/include/SDL2
    LIBS += -L$$PWD/../libs/mac/lib
}

macx {
    QMAKE_OBJECTIVE_CFLAGS += -fobjc-arc

    OBJECTIVE_SOURCES += \
        $$PWD/imgui/backends/imgui_impl_metal.mm
    HEADERS += \
        $$PWD/imgui/backends/imgui_impl_metal.h
}

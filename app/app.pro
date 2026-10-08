QT += core quick network quickcontrols2 svg
CONFIG += c++11

# Teach moonlight-common-c the PyroWave capability bits, adaptive triggers,
# the microphone control-stream send, a direct audio-decode call, and an
# eager macOS Limelog before either project compiles against Limelight.h.
# Idempotent. See docs/PYROWAVE_MAC.md, docs/DUALSENSE_MAC.md,
# docs/MICROPHONE_MAC.md, and docs/PIP_MAC.md. The common-c pin stays
# 583754fc; these scripts are the delta.
!system(python3 $$PWD/../scripts/apply_pyrowave_protocol.py) {
    error("Failed to apply the PyroWave protocol patch to moonlight-common-c")
}
!system(python3 $$PWD/../scripts/apply_adaptive_triggers_protocol.py) {
    error("Failed to apply the adaptive-trigger protocol patch to moonlight-common-c")
}
!system(python3 $$PWD/../scripts/apply_mic_control_packet.py) {
    error("Failed to apply the microphone control-stream patch to moonlight-common-c")
}
!system(python3 $$PWD/../scripts/apply_audio_decode_direct.py) {
    error("Failed to apply the direct audio-decode patch to moonlight-common-c")
}
!system(python3 $$PWD/../scripts/apply_limelog_eager.py) {
    error("Failed to apply the eager Limelog patch to moonlight-common-c")
}

unix:!macx {
    TARGET = moonlight
} else {
    # Local twilight-local-test: process/executable name is Twilight so crash
    # and quit dialogs say Twilight, not Moonlight. QSettings still uses the
    # hard-coded applicationName "Moonlight" in main.cpp. The .app folder is
    # Twilight.app via QMAKE_APPLICATION_BUNDLE_NAME.
    TARGET = Twilight
}

include(../globaldefs.pri)

macx {
    # globaldefs.pri sets QMAKE_MACOSX_DEPLOYMENT_TARGET for this app and
    # the static libraries. An empty value would let clang use the SDK minos.
    isEmpty(QMAKE_MACOSX_DEPLOYMENT_TARGET) {
        error("QMAKE_MACOSX_DEPLOYMENT_TARGET is unset. See globaldefs.pri. Refusing to build Twilight with the SDK minos.")
    }
    message("Twilight macOS deployment target: $$QMAKE_MACOSX_DEPLOYMENT_TARGET")
}

# Precompile QML files to avoid writing qmlcache on portable versions.
# Since this binds the app against the Qt runtime version, we will only
# do this for Windows and Mac (when disable-prebuilts is not defined),
# since they always ship with the matching build of the Qt runtime.
!disable-prebuilts {
    win32|macx {
        CONFIG(release, debug|release) {
            CONFIG += qtquickcompiler
        }
    }
}

TEMPLATE = app

# The following define makes your compiler emit warnings if you use
# any feature of Qt which has been marked as deprecated (the exact warnings
# depend on your compiler). Please consult the documentation of the
# deprecated API in order to know how to port your code away from it.
DEFINES += QT_DEPRECATED_WARNINGS

# You can also make your code fail to compile if you use deprecated APIs.
# In order to do so, uncomment the following line.
# You can also select to disable deprecated APIs only up to a certain version of Qt.
DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000    # disables all the APIs deprecated before Qt 6.0.0

win32 {
    contains(QT_ARCH, i386) {
        LIBS += -L$$PWD/../libs/windows/lib/x86
        INCLUDEPATH += $$PWD/../libs/windows/include/x86
    }
    contains(QT_ARCH, x86_64) {
        LIBS += -L$$PWD/../libs/windows/lib/x64
        INCLUDEPATH += $$PWD/../libs/windows/include/x64
    }
    contains(QT_ARCH, arm64) {
        LIBS += -L$$PWD/../libs/windows/lib/arm64
        INCLUDEPATH += $$PWD/../libs/windows/include/arm64
    }

    INCLUDEPATH += $$PWD/../libs/windows/include
    LIBS += ws2_32.lib winmm.lib dxva2.lib ole32.lib gdi32.lib user32.lib d3d9.lib dwmapi.lib dbghelp.lib

    # Work around a conflict with math.h inclusion between SDL and Qt 6
    DEFINES += _USE_MATH_DEFINES
}
macx:!disable-prebuilts {
    INCLUDEPATH += $$PWD/../libs/mac/include
    INCLUDEPATH += $$PWD/../libs/mac/Frameworks/SDL2.framework/Versions/A/Headers
    INCLUDEPATH += $$PWD/../libs/mac/Frameworks/SDL2_ttf.framework/Versions/A/Headers
    LIBS += -L$$PWD/../libs/mac/lib -F$$PWD/../libs/mac/Frameworks

    # QMake doesn't handle framework-style includes correctly on its own
    QMAKE_CFLAGS += -F$$PWD/../libs/mac/Frameworks
    QMAKE_CXXFLAGS += -F$$PWD/../libs/mac/Frameworks
    QMAKE_OBJECTIVE_CFLAGS += -F$$PWD/../libs/mac/Frameworks
}

unix:if(!macx|disable-prebuilts) {
    CONFIG += link_pkgconfig
    PKGCONFIG += openssl sdl2 SDL2_ttf

    # We have our own optimized libopus.a for Steam Link
    if(!config_SL|disable-prebuilts) {
        PKGCONFIG += opus
    }

    !disable-ffmpeg {
        packagesExist(libavcodec) {
            PKGCONFIG += libavcodec libavutil libswscale
            CONFIG += ffmpeg

            !disable-libva {
                packagesExist(libva) {
                    !disable-x11 {
                        packagesExist(libva-x11) {
                            CONFIG += libva-x11
                        }
                    }
                    !disable-wayland {
                        packagesExist(libva-wayland) {
                            CONFIG += libva-wayland
                        }
                    }
                    !disable-libdrm {
                        packagesExist(libva-drm) {
                            CONFIG += libva-drm
                        }
                    }
                    CONFIG += libva
                }
            }

            !disable-libvdpau {
                packagesExist(vdpau) {
                    CONFIG += libvdpau
                }
            }

            !disable-mmal {
                packagesExist(mmal) {
                    PKGCONFIG += mmal
                    CONFIG += mmal
                }
            }

            !disable-libdrm {
                packagesExist(libdrm) {
                    PKGCONFIG += libdrm
                    CONFIG += libdrm
                }
            }

            !disable-cuda {
                packagesExist(ffnvcodec) {
                    PKGCONFIG += ffnvcodec
                    CONFIG += cuda
                }
            }

            !disable-libplacebo {
                packagesExist(libplacebo) {
                    PKGCONFIG += libplacebo
                    CONFIG += libplacebo
                }
            }
        }

        !disable-wayland {
            packagesExist(wayland-client) {
                CONFIG += wayland
                PKGCONFIG += wayland-client
            }
        }

        !disable-x11 {
            packagesExist(x11) {
                DEFINES += HAS_X11
                PKGCONFIG += x11
            }
        }
    }
}
win32 {
    LIBS += -llibssl -llibcrypto -lSDL2 -lSDL2_ttf -lavcodec -lavutil -lswscale -lopus -ldxgi -ld3d11 -llibplacebo
    CONFIG += ffmpeg libplacebo
}
win32:!winrt {
    CONFIG += soundio discord-rpc
}
macx {
    !disable-prebuilts {
        LIBS += -lssl.3 -lcrypto.3 -lavcodec.61 -lavutil.59 -lswscale.8 -lopus -framework SDL2 -framework SDL2_ttf
        CONFIG += discord-rpc
    }

    LIBS += -lobjc \
        -framework Accelerate \
        -framework AppKit \
        -framework AudioToolbox \
        -framework AudioUnit \
        -framework AVFoundation \
        -framework CoreAudio \
        -framework CoreVideo \
        -framework CoreGraphics \
        -framework CoreLocation \
        -framework CoreMedia \
        -framework CoreWLAN \
        -framework GameController \
        -framework IOKit \
        -framework Metal \
        -framework QuartzCore \
        -framework VideoToolbox \
        -framework IOKit \
        -framework CoreFoundation

    CONFIG += ffmpeg soundio
}

SOURCES += \
    backend/nvaddress.cpp \
    backend/nvapp.cpp \
    cli/pair.cpp \
    main.cpp \
    backend/computerseeker.cpp \
    backend/identitymanager.cpp \
    backend/nvcomputer.cpp \
    backend/nvhttp.cpp \
    backend/nvpairingmanager.cpp \
    backend/computermanager.cpp \
    backend/boxartmanager.cpp \
    backend/richpresencemanager.cpp \
    cli/commandlineparser.cpp \
    cli/listapps.cpp \
    cli/quitstream.cpp \
    cli/startstream.cpp \
    settings/compatfetcher.cpp \
    settings/mappingfetcher.cpp \
    settings/streamingpreferences.cpp \
    settings/network_profile.cpp \
    settings/network_profile_logic.cpp \
    settings/network_identity.cpp \
    streaming/input/abstouch.cpp \
    streaming/input/dualsense_effects.cpp \
    streaming/input/gamepad.cpp \
    streaming/input/gamepad_overlay.cpp \
    streaming/input/input.cpp \
    streaming/input/keyboard.cpp \
    streaming/input/mouse.cpp \
    streaming/input/reltouch.cpp \
    streaming/session.cpp \
    streaming/audio/audio.cpp \
    streaming/audio/microphone/mic_wire.cpp \
    streaming/audio/renderers/renderer.cpp \
    streaming/audio/renderers/sdlaud.cpp \
    gui/computermodel.cpp \
    gui/appmodel.cpp \
    gui/streamhudparse.cpp \
    gui/streamhudstats.cpp \
    gui/sfsymbolprovider.cpp \
    streaming/streamutils.cpp \
    backend/autoupdatechecker.cpp \
    backend/updateversion.cpp \
    path.cpp \
    settings/mappingmanager.cpp \
    gui/sdlgamepadkeynavigation.cpp \
    streaming/video/overlaymanager.cpp \
    backend/systemproperties.cpp \
    wm.cpp

HEADERS += \
    backend/nvaddress.h \
    backend/nvapp.h \
    cli/pair.h \
    settings/compatfetcher.h \
    settings/mappingfetcher.h \
    utils.h \
    backend/computerseeker.h \
    backend/identitymanager.h \
    backend/nvcomputer.h \
    backend/wake_notice.h \
    backend/nvhttp.h \
    backend/nvpairingmanager.h \
    backend/computermanager.h \
    backend/boxartmanager.h \
    backend/richpresencemanager.h \
    cli/commandlineparser.h \
    cli/listapps.h \
    cli/quitstream.h \
    cli/startstream.h \
    settings/streamingpreferences.h \
    settings/network_profile.h \
    settings/network_profile_logic.h \
    settings/network_identity.h \
    streaming/input/input.h \
    streaming/session.h \
    streaming/audio/microphone/mic_capture.h \
    streaming/audio/microphone/mic_permission.h \
    streaming/audio/microphone/mic_resample.h \
    streaming/audio/microphone/mic_wire.h \
    streaming/audio/renderers/renderer.h \
    streaming/audio/renderers/sdl.h \
    gui/computermodel.h \
    gui/appmodel.h \
    gui/streamhudparse.h \
    gui/streamhudstats.h \
    gui/streamhudplace.h \
    gui/sfsymbolprovider.h \
    streaming/video/decoder.h \
    streaming/streamutils.h \
    backend/autoupdatechecker.h \
    backend/updateversion.h \
    path.h \
    settings/mappingmanager.h \
    gui/sdlgamepadkeynavigation.h \
    streaming/video/overlaymanager.h \
    backend/systemproperties.h

# Platform-specific renderers and decoders
ffmpeg {
    message(FFmpeg decoder selected)

    DEFINES += HAVE_FFMPEG
    SOURCES += \
        streaming/video/ffmpeg.cpp \
        streaming/video/ffmpeg-renderers/genhwaccel.cpp \
        streaming/video/ffmpeg-renderers/sdlvid.cpp \
        streaming/video/ffmpeg-renderers/swframemapper.cpp \
        streaming/video/ffmpeg-renderers/pacer/pacer.cpp

    HEADERS += \
        streaming/video/ffmpeg.h \
        streaming/video/ffmpeg-renderers/renderer.h \
        streaming/video/ffmpeg-renderers/genhwaccel.h \
        streaming/video/ffmpeg-renderers/sdlvid.h \
        streaming/video/ffmpeg-renderers/swframemapper.h \
        streaming/video/ffmpeg-renderers/pacer/pacer.h
}
# PyroWave (intra-only GPU wavelet) decoder. Off by default so the existing
# macOS CoreAudio build does not need the pyrowave submodule or MoltenVK.
# Enable with: qmake CONFIG+=pyrowave
# macOS uses the shared-VkDevice MoltenVK path from andyg.pyrowave-macos
# (6fd162d2). Linux uses the dmabuf path in the same file. See docs/PYROWAVE_MAC.md.
pyrowave {
    message(PyroWave decoder selected)

    DEFINES += HAVE_PYROWAVE

    INCLUDEPATH += $$PWD/../pyrowave
    INCLUDEPATH += $$PWD/../pyrowave/Granite/third_party/khronos/vulkan-headers/include

    SOURCES += \
        streaming/bandwidth.cpp \
        streaming/video/pyrowave.cpp
    HEADERS += \
        streaming/bandwidth.h \
        streaming/video/pyrowave.h \
        streaming/video/pyrowave_backend.h \
        streaming/video/pyrowave_packets.h \
        streaming/video/pyrowave_stats.h

    macx {
        # MoltenVK has no dmabuf. Vulkan entry points come from SDL at runtime.
        # libplacebo is only pulled in for this config; the default macOS link
        # line is unchanged.
        #
        # Metal is a second decoder in this same CONFIG+=pyrowave build. It
        # dlopens libpyrowave-metal and is not linked here: that dylib exports
        # the same C names as libpyrowave-shared (pyrowave_decoder_create, …)
        # with different signatures. Do not bump the pyrowave submodule to the
        # metal/ tree; 263ef100 is the Vulkan API this file calls.
        # libpyrowave-metal comes from the pyrowave-metal submodule (89f7e47).
        # The macOS makefile below builds it and copies it into the bundle.
        DEFINES += HAVE_PYROWAVE_METAL
        SOURCES += streaming/video/pyrowave_metal.mm
        HEADERS += \
            streaming/video/pyrowave_metal.h \
            streaming/video/pyrowave_metal_api.h
        # Release builds point this at scripts/build-macos-deps.sh (v19
        # libplacebo, minos 13). A normal qmake uses it when that prefix
        # is already there, ahead of Homebrew's copy.
        depsLib = $$PWD/../build/macos-deps/prefix/lib
        depsInc = $$PWD/../build/macos-deps/prefix/include
        exists($$depsLib/libplacebo.dylib) {
            INCLUDEPATH = $$depsInc $$INCLUDEPATH
            LIBS += -L$$depsLib
        }
        LIBS += -L$$PWD/../pyrowave/build -lpyrowave-shared -lplacebo
    }
    unix:!macx {
        PKGCONFIG += libdrm libplacebo
        LIBS += -L$$PWD/../pyrowave/build -lpyrowave-shared -lvulkan
    }
    win32 {
        error("CONFIG+=pyrowave is implemented for macOS (Vulkan/MoltenVK and Metal) and Linux (Vulkan) only")
    }
    QMAKE_RPATHDIR += $$PWD/../pyrowave/build
}
libva {
    message(VAAPI renderer selected)

    PKGCONFIG += libva
    DEFINES += HAVE_LIBVA
    SOURCES += streaming/video/ffmpeg-renderers/vaapi.cpp
    HEADERS += streaming/video/ffmpeg-renderers/vaapi.h
}
libva-x11 {
    message(VAAPI X11 support enabled)

    PKGCONFIG += libva-x11
    DEFINES += HAVE_LIBVA_X11
}
libva-wayland {
    message(VAAPI Wayland support enabled)

    PKGCONFIG += libva-wayland
    DEFINES += HAVE_LIBVA_WAYLAND
}
libva-drm {
    message(VAAPI DRM support enabled)

    PKGCONFIG += libva-drm
    DEFINES += HAVE_LIBVA_DRM
}
libvdpau {
    message(VDPAU renderer selected)

    DEFINES += HAVE_LIBVDPAU
    SOURCES += streaming/video/ffmpeg-renderers/vdpau.cpp
    HEADERS += streaming/video/ffmpeg-renderers/vdpau.h
}
mmal {
    message(MMAL renderer selected)

    DEFINES += HAVE_MMAL
    SOURCES += streaming/video/ffmpeg-renderers/mmal.cpp
    HEADERS += streaming/video/ffmpeg-renderers/mmal.h

    # We suppress EGL usage when MMAL is available because MMAL has
    # significantly better performance than EGL on the Pi. Setting
    # this option allows EGL usage even if built with MMAL support.
    #
    # It is highly recommended to also build with 'gpuslow' to avoid
    # EGL being preferred if direct DRM rendering is available.
    allow-egl-with-mmal {
        message(Allowing EGL usage with MMAL enabled)

        DEFINES += ALLOW_EGL_WITH_MMAL
    }
}
libdrm {
    message(DRM renderer selected)

    DEFINES += HAVE_DRM
    SOURCES += streaming/video/ffmpeg-renderers/drm.cpp
    HEADERS += streaming/video/ffmpeg-renderers/drm.h

    linux {
        message(Master hooks enabled)
        SOURCES += masterhook.c masterhook_internal.c
        LIBS += -ldl
    }
}
cuda {
    message(CUDA support enabled)

    DEFINES += HAVE_CUDA
    SOURCES += streaming/video/ffmpeg-renderers/cuda.cpp
    HEADERS += streaming/video/ffmpeg-renderers/cuda.h

    # ffnvcodec uses libdl in cuda_load_functions()/cuda_free_functions()
    LIBS += -ldl
}
libplacebo {
    message(Vulkan support enabled via libplacebo)

    DEFINES += HAVE_LIBPLACEBO_VULKAN
    SOURCES += \
        streaming/video/ffmpeg-renderers/plvk.cpp \
        streaming/video/ffmpeg-renderers/plvk_c.c
    HEADERS += \
        streaming/video/ffmpeg-renderers/plvk.h
}
config_EGL {
    message(EGL renderer selected)

    CONFIG += egl
    DEFINES += HAVE_EGL
    SOURCES += \
        streaming/video/ffmpeg-renderers/eglvid.cpp \
        streaming/video/ffmpeg-renderers/egl_extensions.cpp \
        streaming/video/ffmpeg-renderers/eglimagefactory.cpp
    HEADERS += \
        streaming/video/ffmpeg-renderers/eglvid.h \
        streaming/video/ffmpeg-renderers/eglimagefactory.h
}
config_SL {
    message(Steam Link build configuration selected)

    !disable-prebuilts {
        # Link against our NEON-optimized libopus build
        LIBS += -L$$PWD/../libs/steamlink/lib
        INCLUDEPATH += $$PWD/../libs/steamlink/include
        LIBS += -lopus -larmasm -lNE10
    }

    DEFINES += EMBEDDED_BUILD STEAM_LINK HAVE_SLVIDEO HAVE_SLAUDIO
    LIBS += -lSLVideo -lSLAudio

    SOURCES += \
        streaming/video/slvid.cpp \
        streaming/audio/renderers/slaud.cpp
    HEADERS += \
        streaming/video/slvid.h \
        streaming/audio/renderers/slaud.h
}
win32 {
    HEADERS += streaming/video/ffmpeg-renderers/dxutil.h
}
win32:!winrt {
    message(DXVA2 and D3D11VA renderers selected)

    SOURCES += \
        streaming/video/ffmpeg-renderers/dxva2.cpp \
        streaming/video/ffmpeg-renderers/d3d11va.cpp \
        streaming/video/ffmpeg-renderers/pacer/dxvsyncsource.cpp

    HEADERS += \
        streaming/video/ffmpeg-renderers/dxva2.h \
        streaming/video/ffmpeg-renderers/d3d11va.h \
        streaming/video/ffmpeg-renderers/pacer/dxvsyncsource.h
}
macx: SOURCES += streaming/input/dualsense_hid_mac.mm
!macx: SOURCES += streaming/input/dualsense_hid.cpp

macx {
    message(CoreAudio + VideoToolbox renderers selected)

    DEFINES += HAVE_COREAUDIO TWILIGHT_HAS_SF_SYMBOLS

    SOURCES += \
        gui/sfsymbol_mac.mm \
        gui/streamhud_mac.mm \
        settings/network_identity_mac.mm \
        streaming/audio/microphone/mic_capture_mac.mm \
        streaming/audio/microphone/mic_permission_mac.mm \
        streaming/audio/renderers/coreaudio/au_spatial_renderer.mm \
        streaming/audio/renderers/coreaudio/coreaudio.cpp \
        streaming/audio/renderers/coreaudio/TPCircularBuffer.c \
        streaming/input/corehid_mouse_decoder.cpp \
        streaming/input/corehid_mouse.mm \
        streaming/mac/pip_window.mm \
        streaming/video/ffmpeg-renderers/vt_base.mm \
        streaming/video/ffmpeg-renderers/vt_avsamplelayer.mm \
        streaming/video/ffmpeg-renderers/vt_metal.mm

    HEADERS += \
        streaming/audio/renderers/coreaudio/au_spatial_renderer.h \
        streaming/audio/renderers/coreaudio/coreaudio.h \
        streaming/audio/renderers/coreaudio/coreaudio_helpers.h \
        streaming/audio/renderers/coreaudio/coreaudio_playback.h \
        streaming/audio/renderers/coreaudio/TPCircularBuffer.h \
        streaming/input/corehid_mouse.h \
        streaming/mac/pip_frame.h \
        streaming/mac/pip_window.h \
        streaming/video/ffmpeg-renderers/vt.h
}
!macx {
    SOURCES += \
        streaming/audio/microphone/mic_capture.cpp \
        streaming/audio/microphone/mic_permission.cpp
}
soundio {
    message(libsoundio audio renderer selected)

    DEFINES += HAVE_SOUNDIO SOUNDIO_STATIC_LIBRARY
    SOURCES += streaming/audio/renderers/soundioaudiorenderer.cpp
    HEADERS += streaming/audio/renderers/soundioaudiorenderer.h
}
discord-rpc {
    message(Discord integration enabled)

    LIBS += -ldiscord-rpc
    DEFINES += HAVE_DISCORD
}
embedded {
    message(Embedded build)

    DEFINES += EMBEDDED_BUILD
}
glslow {
    message(GL slow build)

    DEFINES += GL_IS_SLOW
}
vkslow {
    message(Vulkan slow build)

    DEFINES += VULKAN_IS_SLOW
}
gpuslow {
    message(GPU slow build)

    DEFINES += GL_IS_SLOW VULKAN_IS_SLOW
}
wayland {
    message(Wayland extensions enabled)

    DEFINES += HAS_WAYLAND
    SOURCES += streaming/video/ffmpeg-renderers/pacer/waylandvsyncsource.cpp
    HEADERS += streaming/video/ffmpeg-renderers/pacer/waylandvsyncsource.h
}

RESOURCES += \
    resources.qrc \
    qml.qrc

# Additional import path used to resolve QML modules in Qt Creator's code model
QML_IMPORT_PATH =

# Additional import path used to resolve QML modules just for Qt Quick Designer
QML_DESIGNER_IMPORT_PATH =

win32:CONFIG(release, debug|release): LIBS += -L$$OUT_PWD/../moonlight-common-c/release/ -lmoonlight-common-c
else:win32:CONFIG(debug, debug|release): LIBS += -L$$OUT_PWD/../moonlight-common-c/debug/ -lmoonlight-common-c
else:unix: LIBS += -L$$OUT_PWD/../moonlight-common-c/ -lmoonlight-common-c

INCLUDEPATH += $$PWD/../moonlight-common-c/moonlight-common-c/src
DEPENDPATH += $$PWD/../moonlight-common-c/moonlight-common-c/src

win32:CONFIG(release, debug|release): LIBS += -L$$OUT_PWD/../qmdnsengine/release/ -lqmdnsengine
else:win32:CONFIG(debug, debug|release): LIBS += -L$$OUT_PWD/../qmdnsengine/debug/ -lqmdnsengine
else:unix: LIBS += -L$$OUT_PWD/../qmdnsengine/ -lqmdnsengine

INCLUDEPATH += $$PWD/../qmdnsengine/qmdnsengine/src/include $$PWD/../qmdnsengine
DEPENDPATH += $$PWD/../qmdnsengine/qmdnsengine/src/include $$PWD/../qmdnsengine

soundio {
    win32:CONFIG(release, debug|release): LIBS += -L$$OUT_PWD/../soundio/release/ -lsoundio
    else:win32:CONFIG(debug, debug|release): LIBS += -L$$OUT_PWD/../soundio/debug/ -lsoundio
    else:unix: LIBS += -L$$OUT_PWD/../soundio/ -lsoundio

    INCLUDEPATH += $$PWD/../soundio/libsoundio
    DEPENDPATH += $$PWD/../soundio/libsoundio
}

win32:CONFIG(release, debug|release): LIBS += -L$$OUT_PWD/../h264bitstream/release/ -lh264bitstream
else:win32:CONFIG(debug, debug|release): LIBS += -L$$OUT_PWD/../h264bitstream/debug/ -lh264bitstream
else:unix: LIBS += -L$$OUT_PWD/../h264bitstream/ -lh264bitstream

INCLUDEPATH += $$PWD/../h264bitstream/h264bitstream
DEPENDPATH += $$PWD/../h264bitstream/h264bitstream

!winrt {
    win32:CONFIG(release, debug|release): LIBS += -L$$OUT_PWD/../AntiHooking/release/ -lAntiHooking
    else:win32:CONFIG(debug, debug|release): LIBS += -L$$OUT_PWD/../AntiHooking/debug/ -lAntiHooking

    INCLUDEPATH += $$PWD/../AntiHooking
    DEPENDPATH += $$PWD/../AntiHooking
}

unix:!macx: {
    isEmpty(PREFIX) {
        PREFIX = /usr/local
    }
    isEmpty(BINDIR) {
        BINDIR = bin
    }
    isEmpty(DATADIR) {
        DATADIR = share
    }

    target.path = $$PREFIX/$$BINDIR/

    desktop.files = deploy/linux/com.moonlight_stream.Moonlight.desktop
    desktop.path = $$PREFIX/$$DATADIR/applications/

    icons.files = res/moonlight.svg
    icons.path = $$PREFIX/$$DATADIR/icons/hicolor/scalable/apps/

    appstream.files = deploy/linux/com.moonlight_stream.Moonlight.appdata.xml
    appstream.path = $$PREFIX/$$DATADIR/metainfo/

    INSTALLS += target desktop icons appstream
}
win32 {
    RC_ICONS = moonlight.ico
    QMAKE_TARGET_COMPANY = Moonlight Game Streaming Project
    QMAKE_TARGET_DESCRIPTION = Moonlight Game Streaming Client
    QMAKE_TARGET_PRODUCT = Moonlight

    CONFIG -= embed_manifest_exe
    QMAKE_LFLAGS += /MANIFEST:embed /MANIFESTINPUT:$${PWD}/Moonlight.exe.manifest
}
macx {
    # Create Info.plist in object dir with the correct version string.
    # CFBundleName, CFBundleDisplayName, and InfoPlist.strings are Twilight.
    # On a live 387b7f64 build those were already Twilight and Dock hover
    # still said Moonlight, which is the .app folder name. The folder is
    # Twilight.app. CFBundleExecutable and the binary are Twilight (local-test).
    # Bundle id stays com.moonlight-stream.Moonlight unless twilight-mas
    # swaps it. See docs/TWILIGHT_MAS.md.
    # Makefile builds name the folder from this variable and the binary
    # from TARGET. The Xcode generator forces PRODUCT_NAME to TARGET, so
    # leave that path as Moonlight.app rather than pointing the product
    # reference at a different folder than Xcode writes.
    !macx-xcode: QMAKE_APPLICATION_BUNDLE_NAME = Twilight

    # Makefile builds (qmake CONFIG+=pyrowave && make) compile libpyrowave-metal
    # from the pyrowave-metal submodule before linking, then copy the dylib
    # into the app bundle. $$files() further down only sees a dylib that
    # already exists when qmake runs, so a fresh tree still gets the copy
    # here. The dylib is not committed. The Xcode generator is left alone:
    # it names the product Moonlight.app.
    !macx-xcode:pyrowave {
        PYROWAVE_METAL_SRC = $$PWD/../pyrowave-metal/metal
        PYROWAVE_METAL_STAMP = $$PWD/../pyrowave-metal/build/.twilight-built
        !exists($$PYROWAVE_METAL_SRC/CMakeLists.txt) {
            error("pyrowave-metal is not checked out. Run: git submodule update --init pyrowave-metal")
        }
        pyrowave_metal.target = $$PYROWAVE_METAL_STAMP
        pyrowave_metal.depends = $$PYROWAVE_METAL_SRC/CMakeLists.txt \
            $$files($$PYROWAVE_METAL_SRC/*.mm) \
            $$files($$PYROWAVE_METAL_SRC/*.cpp) \
            $$files($$PYROWAVE_METAL_SRC/*.hpp) \
            $$files($$PYROWAVE_METAL_SRC/*.h) \
            $$files($$PYROWAVE_METAL_SRC/shaders/*)
        pyrowave_metal.commands = \"$$PWD/../scripts/build-pyrowave-metal.sh\" build && touch \"$$PYROWAVE_METAL_STAMP\"
        QMAKE_EXTRA_TARGETS += pyrowave_metal
        PRE_TARGETDEPS += $$PYROWAVE_METAL_STAMP
        QMAKE_POST_LINK += \"$$PWD/../scripts/build-pyrowave-metal.sh\" install \"$$OUT_PWD/$${QMAKE_APPLICATION_BUNDLE_NAME}.app/Contents/Frameworks\"
    }
    # Hardened Runtime signing is: codesign --options runtime
    # Info.plist tokens and the ATS dictionary are rewritten by
    # scripts/prepare-macos-infoplist.py. Desktop keeps
    # NSAllowsArbitraryLoads. twilight-mas swaps in NSAllowsLocalNetworking.
    TWILIGHT_BUNDLE_ID = com.moonlight-stream.Moonlight
    TWILIGHT_DISPLAY_NAME = Twilight
    TWILIGHT_PLIST_MODE = desktop
    TWILIGHT_ENTITLEMENTS = $$PWD/deploy/macos/Twilight-MAS.entitlements
    twilight-mas {
        DEFINES += TWILIGHT_MAS
        TWILIGHT_BUNDLE_ID = com.henrique.twilight
        TWILIGHT_DISPLAY_NAME = Twilight
        TWILIGHT_PLIST_MODE = mas
        twilight-mas-multicast {
            TWILIGHT_ENTITLEMENTS = $$PWD/deploy/macos/Twilight-MAS-multicast.entitlements
        }

        # Xcode generator only. Makefile builds sign in scripts/generate-dmg.sh.
        CODE_SIGN_ENTITLEMENTS.name = CODE_SIGN_ENTITLEMENTS
        CODE_SIGN_ENTITLEMENTS.value = $$TWILIGHT_ENTITLEMENTS
        ENABLE_HARDENED_RUNTIME.name = ENABLE_HARDENED_RUNTIME
        ENABLE_HARDENED_RUNTIME.value = YES
        QMAKE_MAC_XCODE_SETTINGS += CODE_SIGN_ENTITLEMENTS ENABLE_HARDENED_RUNTIME

        message("twilight-mas: bundle id $$TWILIGHT_BUNDLE_ID")
        message("twilight-mas: display name $$TWILIGHT_DISPLAY_NAME")
        message("twilight-mas: plist mode $$TWILIGHT_PLIST_MODE")
        message("twilight-mas: entitlements $$TWILIGHT_ENTITLEMENTS")
        message("twilight-mas: codesign --options runtime --timestamp --entitlements $$TWILIGHT_ENTITLEMENTS")
    }
    !system(python3 \"$$PWD/../scripts/prepare-macos-infoplist.py\" \"$$PWD/Info.plist\" \"$$OUT_PWD/Info.plist\" \"$$cat(version.txt)\" \"$$TWILIGHT_BUNDLE_ID\" \"$$TWILIGHT_DISPLAY_NAME\" $$TWILIGHT_PLIST_MODE) {
        error("Failed to prepare Info.plist")
    }

    QMAKE_INFO_PLIST = $$OUT_PWD/Info.plist

    APP_BUNDLE_RESOURCES.files = twilight.icns
    APP_BUNDLE_RESOURCES.path = Contents/Resources

    # Localized names. Dock hover still follows the Twilight.app folder
    # when Launch Services does not substitute these.
    APP_BUNDLE_DISPLAY_NAME.files = deploy/macos/en.lproj/InfoPlist.strings
    APP_BUNDLE_DISPLAY_NAME.path = Contents/Resources/en.lproj

    APP_BUNDLE_PLIST.files = $$OUT_PWD/Info.plist
    APP_BUNDLE_PLIST.path = Contents

    # GPL and third-party license texts. Loose files, not only inside qrc,
    # so a copy of the app bundle contains the notices.
    APP_BUNDLE_LICENSES.files = $$files(licenses/*.txt)
    APP_BUNDLE_LICENSES.path = Contents/Resources/Licenses

    # Required-reason API manifest. Collected-data keys are intentionally absent.
    APP_BUNDLE_PRIVACY.files = deploy/macos/PrivacyInfo.xcprivacy
    APP_BUNDLE_PRIVACY.path = Contents/Resources

    QMAKE_BUNDLE_DATA += APP_BUNDLE_RESOURCES APP_BUNDLE_DISPLAY_NAME APP_BUNDLE_PLIST APP_BUNDLE_LICENSES APP_BUNDLE_PRIVACY

    !disable-prebuilts {
        APP_BUNDLE_FRAMEWORKS.files = $$files(../libs/mac/Frameworks/*.framework, true) $$files(../libs/mac/lib/*.dylib, true)
        pyrowave: APP_BUNDLE_FRAMEWORKS.files += $$files(../pyrowave/build/libpyrowave-shared*.dylib)
        # Present only when the dylib was already built before this qmake.
        # The makefile post-link step copies a dylib produced during make.
        pyrowave: APP_BUNDLE_FRAMEWORKS.files += $$files(../pyrowave-metal/build/libpyrowave-metal*.dylib)
        APP_BUNDLE_FRAMEWORKS.path = Contents/Frameworks

        QMAKE_BUNDLE_DATA += APP_BUNDLE_FRAMEWORKS

        QMAKE_RPATHDIR += @executable_path/../Frameworks
    }
}

VERSION = "$$cat(version.txt)"
DEFINES += VERSION_STR=\\\"$$cat(version.txt)\\\"

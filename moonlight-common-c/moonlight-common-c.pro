#-------------------------------------------------
#
# Project created by QtCreator 2018-05-05T17:41:00
#
#-------------------------------------------------

QT -= core gui

TARGET = moonlight-common-c
TEMPLATE = lib

# Build a static library
CONFIG += staticlib

# Include global qmake defs
include(../globaldefs.pri)

# 7feb0a6 reads packetTypes[IDX_DS_ADAPTIVE_TRIGGERS] (index 12) on every
# async callback check. The four pre-Sunshine tables are one entry short,
# so a GFE host reads past the array. The script is idempotent. This repo
# cannot publish a commit on the submodule remote.
!system(python3 $$PWD/../scripts/apply_control_packet_bounds.py) {
    error("Failed to apply the control-stream packet table bounds patch")
}

win32 {
    contains(QT_ARCH, i386) {
        INCLUDEPATH += $$PWD/../libs/windows/include/x86
    }
    contains(QT_ARCH, x86_64) {
        INCLUDEPATH += $$PWD/../libs/windows/include/x64
    }
    contains(QT_ARCH, arm64) {
        INCLUDEPATH += $$PWD/../libs/windows/include/arm64
    }

    INCLUDEPATH += $$PWD/../libs/windows/include
    DEFINES += HAS_QOS_FLOWID=1 HAS_PQOS_FLOWID=1
}
macx {
    INCLUDEPATH += $$PWD/../libs/mac/include

    # 7feb0a6 (andygrundman/moonlight-common-c) has no LiSendRawControlStreamPacket
    # or LiIsControlStreamEncrypted. This static library is compiled before
    # app.pro, so the patch has to run here or the app links undefined
    # _LiSendRawControlStreamPacket / _LiIsControlStreamEncrypted. The script
    # is idempotent. The functions use file-scope state in ControlStream.c, and
    # this repo cannot publish a commit on that submodule remote.
    !system(python3 $$PWD/../scripts/apply_mic_control_packet.py) {
        error("Failed to apply the microphone control-stream patch")
    }
}
unix:!macx {
    CONFIG += link_pkgconfig
    PKGCONFIG += openssl
    DEFINES += HAVE_CLOCK_GETTIME=1
}

COMMON_C_DIR = $$PWD/moonlight-common-c
ENET_DIR = $$COMMON_C_DIR/enet
SOURCES += \
    $$ENET_DIR/callbacks.c \
    $$ENET_DIR/compress.c \
    $$ENET_DIR/host.c \
    $$ENET_DIR/list.c \
    $$ENET_DIR/packet.c \
    $$ENET_DIR/peer.c \
    $$ENET_DIR/protocol.c \
    $$ENET_DIR/unix.c \
    $$ENET_DIR/win32.c \
    $$COMMON_C_DIR/nanors/deps/obl/oblas_common.c \
    $$COMMON_C_DIR/nanors/deps/obl/oblas_lite.c \
    $$COMMON_C_DIR/nanors/rs.c \
    $$COMMON_C_DIR/src/AudioStream.c \
    $$COMMON_C_DIR/src/ByteBuffer.c \
    $$COMMON_C_DIR/src/Connection.c \
    $$COMMON_C_DIR/src/ConnectionTester.c \
    $$COMMON_C_DIR/src/ControlStream.c \
    $$COMMON_C_DIR/src/FakeCallbacks.c \
    $$COMMON_C_DIR/src/InputStream.c \
    $$COMMON_C_DIR/src/LinkedBlockingQueue.c \
    $$COMMON_C_DIR/src/Misc.c \
    $$COMMON_C_DIR/src/Platform.c \
    $$COMMON_C_DIR/src/PlatformCrypto.c \
    $$COMMON_C_DIR/src/PlatformSockets.c \
    $$COMMON_C_DIR/src/RtpAudioQueue.c \
    $$COMMON_C_DIR/src/RtpVideoQueue.c \
    $$COMMON_C_DIR/src/RtspConnection.c \
    $$COMMON_C_DIR/src/RtspParser.c \
    $$COMMON_C_DIR/src/SdpGenerator.c \
    $$COMMON_C_DIR/src/SimpleStun.c \
    $$COMMON_C_DIR/src/VideoDepacketizer.c \
    $$COMMON_C_DIR/src/VideoStream.c
HEADERS += \
    $$COMMON_C_DIR/src/Limelight.h \
    $$COMMON_C_DIR/src/PyroWaveProtocol.h
INCLUDEPATH += \
    $$ENET_DIR/include \
    $$COMMON_C_DIR/src \
    $$COMMON_C_DIR/nanors \
    $$COMMON_C_DIR/nanors/deps \
    $$COMMON_C_DIR/nanors/deps/obl
DEFINES += HAS_SOCKLEN_T

CONFIG(debug, debug|release) {
    # Enable asserts on debug builds
    DEFINES += LC_DEBUG
}

# Older GCC versions defaulted to GNU89
*-g++ {
    QMAKE_CFLAGS += -std=gnu99
}

# Disable unused parameter warnings on GCC and Clang
*-g++|*-clang* {
    QMAKE_CFLAGS_WARN_ON += -Wno-unused-parameter
}

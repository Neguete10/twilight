include(../globaldefs.pri)

QT += core gui qml quick testlib network
CONFIG += console c++17 testcase warn_on
CONFIG -= app_bundle
TEMPLATE = app
TARGET = twilight_qt_tests

TWILIGHT_ROOT = $$PWD/..
INCLUDEPATH += $$TWILIGHT_ROOT/app \
    $$TWILIGHT_ROOT/app/settings \
    $$TWILIGHT_ROOT/app/backend \
    $$TWILIGHT_ROOT/app/cli \
    $$TWILIGHT_ROOT/app/streaming \
    $$TWILIGHT_ROOT/app/streaming/audio/microphone

VERSION_LINES = $$cat($$TWILIGHT_ROOT/app/version.txt, lines)
DEFINES += VERSION_STR=\\\"$$member(VERSION_LINES, 0)\\\"
DEFINES += TWILIGHT_SOURCE_ROOT=\\\"$$TWILIGHT_ROOT\\\"

SOURCES += twilight_qt_tests.cpp \
    wm_stub.cpp \
    $$TWILIGHT_ROOT/app/settings/streamingpreferences.cpp \
    $$TWILIGHT_ROOT/app/streaming/audio/microphone/mic_permission.cpp \
    $$TWILIGHT_ROOT/app/backend/nvaddress.cpp \
    $$TWILIGHT_ROOT/app/backend/updateversion.cpp \
    $$TWILIGHT_ROOT/app/backend/autoupdatechecker.cpp \
    $$TWILIGHT_ROOT/app/cli/commandlineparser.cpp

HEADERS += $$TWILIGHT_ROOT/app/settings/streamingpreferences.h \
    $$TWILIGHT_ROOT/app/backend/autoupdatechecker.h

RESOURCES += twilight_qt_tests.qrc

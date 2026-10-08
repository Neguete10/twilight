#pragma once

#include <QString>

// While the stream event loop is running, SIGTERM and SIGINT post SDL_QUIT
// so the session can tear down and ask the host to quit. Any other time they
// terminate the process, because nothing is reading that SDL queue.
void installQuitSignals();
void setStreamLoopAcceptsQuit(bool active);

#define THROW_BAD_ALLOC_IF_NULL(x) \
    if ((x) == nullptr) throw std::bad_alloc()

namespace WMUtils {
    bool isRunningX11();
    bool isRunningWayland();
    bool isRunningWindowManager();
    bool isRunningDesktopEnvironment();
    QString getDrmCardOverride();
}

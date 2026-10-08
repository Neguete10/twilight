#pragma once

#include <QString>
#include <QtGlobal>

#if !defined(Q_OS_WIN32)
#include <csignal>
#endif

// SDL's default SIGINT/SIGTERM handler only posts SDL_QUIT. After the stream
// loop has returned to Qt that event is never read, so the process ignores
// the signal. Put the default action back (terminate) whenever SDL may have
// installed its handler.
inline void restoreDefaultQuitSignals()
{
#if !defined(Q_OS_WIN32)
    std::signal(SIGTERM, SIG_DFL);
    std::signal(SIGINT, SIG_DFL);
#endif
}

#define THROW_BAD_ALLOC_IF_NULL(x) \
    if ((x) == nullptr) throw std::bad_alloc()

namespace WMUtils {
    bool isRunningX11();
    bool isRunningWayland();
    bool isRunningWindowManager();
    bool isRunningDesktopEnvironment();
    QString getDrmCardOverride();
}

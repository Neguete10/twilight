#pragma once

#include <QString>

#ifndef Q_OS_WIN32
// SDL installs a SIGINT/SIGTERM handler that only posts SDL_QUIT. After the
// stream loop has returned, that event is never read, so the process ignores
// the signal. SIGTERM must terminate even if a modal dialog is up.
void reinstallUnixSignalHandlers();
#else
inline void reinstallUnixSignalHandlers() {}
#endif

#define THROW_BAD_ALLOC_IF_NULL(x) \
    if ((x) == nullptr) throw std::bad_alloc()

namespace WMUtils {
    bool isRunningX11();
    bool isRunningNvidiaProprietaryDriverX11();
    bool supportsDesktopGLWithEGL();
    bool isRunningWayland();
    bool isRunningWindowManager();
    bool isRunningDesktopEnvironment();
    QString getDrmCardOverride();
    bool isGpuSlow();
}

namespace Utils {
    template <typename T>
    bool getEnvironmentVariableOverride(const char* name, T* value) {
        bool ok;
        *value = (T)qEnvironmentVariableIntValue(name, &ok);
        return ok;
    }
}

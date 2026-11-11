#include "utils.h"

bool WMUtils::isRunningX11() { return false; }
bool WMUtils::isRunningNvidiaProprietaryDriverX11() { return false; }
bool WMUtils::supportsDesktopGLWithEGL() { return false; }
bool WMUtils::isRunningWayland() { return false; }
bool WMUtils::isRunningWindowManager() { return true; }
bool WMUtils::isRunningDesktopEnvironment() { return true; }
QString WMUtils::getDrmCardOverride() { return QString(); }
bool WMUtils::isGpuSlow() { return false; }

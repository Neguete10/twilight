#include "network_identity.h"

// __APPLE__ is the compiler's own macOS marker. Q_OS_MACOS is only visible
// after a Qt header, and this file is also built on macOS where the .mm
// probe is the one that must be linked.
#if !defined(__APPLE__)

SsidProbe probePlatformSsid()
{
    SsidProbe probe;
    probe.note = "SSID detection uses CoreWLAN and is only available on macOS. "
                 "This system matches the fallback interface and subnet instead.";
    return probe;
}

void requestPlatformSsidAccess(const std::function<void(bool granted)>& done)
{
    if (done) {
        done(false);
    }
}

#endif

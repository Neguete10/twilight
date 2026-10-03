#pragma once

#include <functional>
#include <string>

// Platform SSID probe. On macOS this is CoreWLAN. Everywhere else the probe
// reports that the Wi-Fi name is unavailable and the caller uses the IPv4
// fallback in network_profile_logic.

struct SsidProbe {
    std::string ssid;
    std::string bssid;
    std::string interfaceName;
    std::string note;
};

SsidProbe probePlatformSsid();

// Asks macOS for permission to read the Wi-Fi name, then invokes done on the
// thread that started the request. granted is false when Location Services
// will not reveal the SSID. Other platforms invoke done(false) immediately.
void requestPlatformSsidAccess(const std::function<void(bool granted)>& done);

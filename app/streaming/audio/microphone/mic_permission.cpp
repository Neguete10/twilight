#include "mic_permission.h"

// Non-macOS stub. app.pro compiles this file only outside macx.
// mic_permission_mac.mm provides the same functions on macOS.

namespace MacMicrophonePermission {

Status status()
{
    return Status::NotDetermined;
}

void request(std::function<void(bool granted)> callback)
{
    if (callback) {
        callback(false);
    }
}

void openSystemSettings()
{
}

} // namespace MacMicrophonePermission

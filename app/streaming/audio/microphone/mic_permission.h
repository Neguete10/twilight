#pragma once

#include <functional>

// macOS microphone TCC. The Objective-C implementation is compiled only
// into macOS builds. Other platforms report NotDetermined and deny requests
// so the stream never waits on a permission UI that does not exist.

namespace MacMicrophonePermission {

enum class Status {
    NotDetermined,
    Granted,
    Denied,
    Restricted,
    // Signed with the Hardened Runtime but without
    // com.apple.security.device.audio-input. macOS denies the microphone
    // without prompting, so a request is never sent.
    MissingEntitlement
};

Status status();

// Completion runs on an arbitrary queue, including inline when the
// authorization state is already known. granted is false for denied,
// restricted and a missing entitlement.
void request(std::function<void(bool granted)> callback);

// Opens System Settings > Privacy & Security > Microphone. No-op elsewhere.
void openSystemSettings();

} // namespace MacMicrophonePermission

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
    Restricted
};

Status status();

// Completion runs on an arbitrary queue, including inline when the
// authorization state is already known. granted is false for denied
// and restricted.
void request(std::function<void(bool granted)> callback);

} // namespace MacMicrophonePermission

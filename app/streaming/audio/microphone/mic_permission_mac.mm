#include "mic_permission.h"

#import <AVFoundation/AVFoundation.h>

namespace MacMicrophonePermission {

Status status()
{
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
    case AVAuthorizationStatusAuthorized:
        return Status::Granted;
    case AVAuthorizationStatusDenied:
        return Status::Denied;
    case AVAuthorizationStatusRestricted:
        return Status::Restricted;
    case AVAuthorizationStatusNotDetermined:
    default:
        return Status::NotDetermined;
    }
}

void request(std::function<void(bool granted)> callback)
{
    if (!callback) {
        return;
    }

    const AVAuthorizationStatus current = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (current == AVAuthorizationStatusAuthorized) {
        callback(true);
        return;
    }
    if (current == AVAuthorizationStatusDenied || current == AVAuthorizationStatusRestricted) {
        callback(false);
        return;
    }

    // The completion handler may run on a non-Qt queue. The function is
    // heap-allocated because this file is compiled without ARC.
    std::function<void(bool)> *held = new std::function<void(bool)>(std::move(callback));
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        (*held)(granted == YES);
        delete held;
    }];
}

} // namespace MacMicrophonePermission

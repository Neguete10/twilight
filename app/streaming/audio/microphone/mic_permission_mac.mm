#include "mic_permission.h"

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <Security/Security.h>

#include <SDL.h>

namespace MacMicrophonePermission {

namespace {

// True when this process runs under the Hardened Runtime without the
// Audio Input exception. tccd then denies kTCCServiceMicrophone before it
// can show the usage-string prompt, and the app never appears in
// System Settings > Privacy & Security > Microphone.
// Unsigned and ad-hoc development builds without the runtime flag are not
// affected. Public Security.framework API, available on macOS 13.
bool missingAudioInputEntitlement()
{
    static int cached = -1;
    if (cached != -1) {
        return cached == 1;
    }

    bool missing = false;
    SecCodeRef code = nullptr;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess && code != nullptr) {
        SecStaticCodeRef staticCode = nullptr;
        if (SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode) == errSecSuccess && staticCode != nullptr) {
            CFDictionaryRef info = nullptr;
            if (SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &info) == errSecSuccess && info != nullptr) {
                uint32_t flags = 0;
                CFNumberRef flagsNum = (CFNumberRef)CFDictionaryGetValue(info, kSecCodeInfoFlags);
                if (flagsNum != nullptr) {
                    CFNumberGetValue(flagsNum, kCFNumberSInt32Type, &flags);
                }
                if (flags & kSecCodeSignatureRuntime) {
                    bool entitled = false;
                    CFDictionaryRef ents = (CFDictionaryRef)CFDictionaryGetValue(info, kSecCodeInfoEntitlementsDict);
                    if (ents != nullptr) {
                        CFTypeRef value = CFDictionaryGetValue(ents, CFSTR("com.apple.security.device.audio-input"));
                        entitled = value != nullptr && CFGetTypeID(value) == CFBooleanGetTypeID() &&
                                   CFBooleanGetValue((CFBooleanRef)value);
                    }
                    missing = !entitled;
                }
                CFRelease(info);
            }
            CFRelease(staticCode);
        }
        CFRelease(code);
    }

    if (missing) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "This build uses the Hardened Runtime without com.apple.security.device.audio-input. "
                    "macOS will deny the microphone without asking.");
    }
    cached = missing ? 1 : 0;
    return missing;
}

} // namespace

Status status()
{
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
    case AVAuthorizationStatusAuthorized:
        return Status::Granted;
    case AVAuthorizationStatusDenied:
        return missingAudioInputEntitlement() ? Status::MissingEntitlement : Status::Denied;
    case AVAuthorizationStatusRestricted:
        return Status::Restricted;
    case AVAuthorizationStatusNotDetermined:
    default:
        return missingAudioInputEntitlement() ? Status::MissingEntitlement : Status::NotDetermined;
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
    if (current == AVAuthorizationStatusRestricted) {
        callback(false);
        return;
    }
    if (missingAudioInputEntitlement()) {
        callback(false);
        return;
    }
    if (current == AVAuthorizationStatusDenied) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone access was denied earlier. macOS does not ask again; "
                    "enable Twilight in System Settings > Privacy & Security > Microphone.");
        callback(false);
        return;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Requesting microphone access from macOS");

    // The completion handler may run on a non-Qt queue. The function is
    // heap-allocated because this file is compiled without ARC.
    std::function<void(bool)> *held = new std::function<void(bool)>(std::move(callback));
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone access %s", granted ? "granted" : "denied");
        (*held)(granted == YES);
        delete held;
    }];
}

void openSystemSettings()
{
    // Valid on macOS 13 (System Settings) and later.
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

} // namespace MacMicrophonePermission

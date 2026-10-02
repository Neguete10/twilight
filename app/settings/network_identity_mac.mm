#include "network_identity.h"

#import <CoreLocation/CoreLocation.h>
#import <CoreWLAN/CoreWLAN.h>
#import <Foundation/Foundation.h>

#include <string>

namespace {

std::string nsStringToStd(NSString* value)
{
    if (value == nil || value.length == 0) {
        return std::string();
    }
    const char* utf8 = value.UTF8String;
    if (utf8 == NULL) {
        return std::string();
    }
    return std::string(utf8);
}

std::string trimSsid(const std::string& value)
{
    std::size_t begin = 0;
    while (begin < value.size() && (value[begin] == ' ' || value[begin] == '\t')) {
        begin++;
    }
    std::size_t end = value.size();
    while (end > begin && (value[end - 1] == ' ' || value[end - 1] == '\t')) {
        end--;
    }
    return value.substr(begin, end - begin);
}

CWInterface* currentWifiInterface()
{
    CWWiFiClient* client = [CWWiFiClient sharedWiFiClient];
    if (client == nil) {
        return nil;
    }
    CWInterface* iface = client.interface;
    if (iface != nil) {
        return iface;
    }
    NSArray<NSString*>* names = client.interfaceNames;
    for (NSString* name in names) {
        CWInterface* candidate = [client interfaceWithName:name];
        if (candidate != nil) {
            return candidate;
        }
    }
    return nil;
}

} // namespace

SsidProbe probePlatformSsid()
{
    SsidProbe probe;
    @try {
        CWInterface* iface = currentWifiInterface();
        if (iface == nil) {
            probe.note = "CoreWLAN has no Wi-Fi interface. Ethernet and powered-off radios "
                         "have no SSID, so matching uses the fallback interface and subnet.";
            return probe;
        }
        probe.interfaceName = nsStringToStd(iface.interfaceName);
        probe.bssid = nsStringToStd(iface.bssid);
        probe.ssid = trimSsid(nsStringToStd(iface.ssid));
        if (!probe.ssid.empty()) {
            probe.note = "CoreWLAN reported this Wi-Fi name";
            if (!probe.interfaceName.empty()) {
                probe.note += " on ";
                probe.note += probe.interfaceName;
            }
            probe.note += ". Profiles match the name, not the access point, so roaming "
                          "within the same SSID still matches.";
            if (!probe.bssid.empty()) {
                probe.note += " Current BSSID ";
                probe.note += probe.bssid;
                probe.note += " is not stored as the match key.";
            }
            return probe;
        }
        probe.note = "CoreWLAN did not return a Wi-Fi name. macOS hides the SSID until "
                     "Location Services is allowed for this app, the radio is off, or the "
                     "active link is Ethernet.";
    }
    @catch (NSException* exception) {
        probe = SsidProbe();
        probe.note = "CoreWLAN failed while reading the Wi-Fi name. Matching uses the "
                     "fallback interface and subnet, and profiles can still be applied by hand.";
        if (exception.reason != nil) {
            probe.note += " ";
            probe.note += nsStringToStd(exception.reason);
        }
    }
    return probe;
}

namespace {

bool locationGranted(CLAuthorizationStatus status)
{
    // macOS: WhenInUse status enum is API_UNAVAILABLE(macos). Always covers
    // both the modern Always grant and the older Authorized alias.
    return status == kCLAuthorizationStatusAuthorizedAlways;
}

} // namespace

@interface TwilightSsidLocationProbe : NSObject<CLLocationManagerDelegate>
@end

@implementation TwilightSsidLocationProbe {
    CLLocationManager* _manager;
    std::function<void(bool)> _done;
    bool _waiting;
}

- (void)ask:(std::function<void(bool)>)done
{
    _done = std::move(done);
    if (_manager == nil) {
        _manager = [[CLLocationManager alloc] init];
        _manager.delegate = self;
    }
    const CLAuthorizationStatus status = _manager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        _waiting = true;
        [_manager requestWhenInUseAuthorization];
        return;
    }
    _waiting = false;
    if (_done) {
        std::function<void(bool)> callback = std::move(_done);
        callback(locationGranted(status));
    }
}

- (void)finish:(CLAuthorizationStatus)status
{
    if (!_waiting) {
        return;
    }
    _waiting = false;
    if (_done) {
        std::function<void(bool)> callback = std::move(_done);
        callback(locationGranted(status));
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager
{
    [self finish:manager.authorizationStatus];
}

@end

void requestPlatformSsidAccess(const std::function<void(bool granted)>& done)
{
    static TwilightSsidLocationProbe* probe = nil;
    if (probe == nil) {
        probe = [[TwilightSsidLocationProbe alloc] init];
    }
    [probe ask:done];
}

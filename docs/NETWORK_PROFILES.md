# Network profiles

The profile book and `StreamingPreferences::applyNetworkProfileSettings` are
unchanged. Twilight does not show a profile picker. The Classic settings page
that used to call this API was removed with the Classic shell. A profile is
the picture you are about to stream: resolution, frame rate, bitrate, codec,
HDR, YUV 4:4:4, decoder, PyroWave backend, window mode, V-Sync, frame pacing,
and audio (including spatial audio and head tracking). Language, mouse,
gamepad, and host options stay as they are.

Nothing under `app/gui/ui/v2` reads or writes profiles.

## What a tap does

**Display intent** writes a starting picture into the live settings so you can
change it before saving. Custom does not change anything.

| Intent | Picture | Codec | Window | Audio |
| --- | --- | --- | --- | --- |
| Couch TV | 1920×1080 @ 60 | HEVC, HDR on | Borderless fullscreen | 5.1 |
| Desk monitor | 2560×1440 @ 60 | Automatic, HDR off | Windowed | Stereo |
| Battery saver | 1280×720 @ 30 | H.264, HDR off | Windowed | Stereo |

Bitrate for an intent is `StreamingPreferences::getDefaultBitrate` for that
size, frame rate, and YUV 4:4:4 flag (all three intents leave 4:4:4 off).
V-Sync stays on and frame pacing stays off. The PyroWave backend and video
decoder stay on Automatic. After the intent loads, the live settings hold the
new resolution, frame rate, bitrate, and codec.

**Save profile** stores the settings currently shown, plus the intent you picked.
Saving the same name again (ASCII case-insensitive) replaces that profile and
keeps its id. An empty name uses the Wi-Fi name when one is known, otherwise
"New profile". If that generated name is already taken, a numeric suffix is
added so a blank save does not overwrite a profile. Type the existing name to
replace it. "Bind to the current network" is on by default. Turn it off to
keep a preset you apply by hand on every network (a hotspot profile you select
before you leave home, for example).

**Apply** copies that saved picture back onto the live settings and writes it
with the normal `StreamingPreferences::save()` path, under the same `QSettings`
file as the rest of the client. You do not have to be on the bound network.
The next stream uses whatever Apply last wrote. Loading the app does not
apply a profile by itself.

When exactly one saved profile matches the network you are on, the store
publishes that match (`soleMatchName`, `matchingProfileCount`). Several
matches stay in the list, and each matching row is marked. The Twilight shell
does not show those rows.

## How the network is detected

Detection runs when `refreshNetwork()` is called.

1. **SSID, macOS only.** `CWWiFiClient` / `CWInterface` in
   `app/settings/network_identity_mac.mm` reads the Wi-Fi name. The match key
   is `ssid:` plus that name, with leading and trailing spaces removed.
   Comparison is ASCII case-insensitive, so `Home Wi-Fi` and `home wi-fi` are
   the same profile binding. The BSSID is mentioned in the status text and is
   not the key: roaming between access points with the same name still matches.
2. **Permission.** macOS does not return the SSID until Location Services is
   allowed for the app. `Info.plist` carries `NSLocationUsageDescription` and
   `NSLocationWhenInUseUsageDescription` for that prompt. **Allow Wi-Fi name**
   calls `CLLocationManager requestWhenInUseAuthorization` and then reads
   CoreWLAN again. If you deny it, or CoreWLAN throws, or the radio is off,
   detection continues with the fallback below. Apply never depends on the SSID.
3. **Fallback.** When the SSID is empty (Ethernet, permission denied, or any
   build that is not macOS), the key is
   `fallback:<interface>:<network>/<prefix>` for the best up, non-loopback IPv4
   address. Link-local `169.254.0.0/16` and a prefix length outside 1–32 are
   skipped. Private addresses (10/8, 172.16/12, 192.168/16) win over public
   ones, then `en*`, then `eth*`, then `wlan*`, then the name, then the lower
   address. `192.168.1.50/24` on `en0` becomes
   `fallback:en0:192.168.1.0/24`. DHCP can change the host address without
   changing the key. A different subnet does not match.
4. **Nothing up.** The identity is unbound. A new profile saved with binding
   on still has no network key, so it will not light up as a match. Apply
   still works.

A profile saved against the fallback key does not match later, once a Wi-Fi
name is available. Save it again on that network if the SSID should be the key.

Linux and Windows builds compile the non-mac probe, which always takes the
fallback. `CoreWLAN` and `CoreLocation` are linked only on macOS.

The Mac App Store entitlement `com.apple.developer.networking.wifi-info` is
another way to read the SSID. It is not part of this change. Store submission
stays out of scope; the location prompt is the path for a normal macOS build.

## Where profiles are stored

The book is one string in the existing `QSettings` store, key `networkprofiles`.
The first line is `twilight-net-profiles/1`. Each profile is one line of 22
unit-separator fields (id, name, network key, label, binding, intent, then the
picture numbers). Newlines and separators inside a name or SSID are escaped.
A blob that fails to parse is left on disk untouched. The store logs that and
sets `statusMessage`. Nothing in the Twilight shell displays it. At most 32
profiles are kept. Names are limited to 64 characters. Resolution, frame rate,
and bitrate have to sit in the ranges the custom fields already allow
(256–8192, 10–9999 FPS, 500–500000 kbps).

The retired codec value HEVC+HDR (3) is applied as Automatic plus HDR on, the
same way a normal settings reload treats it. Frame pacing is stored, and it is
forced off when V-Sync is off so a saved profile and the live V-Sync flag
agree. A bitrate above 150 Mbps with the unlock flag off is clamped to 150 Mbps
on apply, which is the slider's normal maximum.

## Files

- `app/settings/network_profile_logic.h` — intents, fallback choice, match, serialize
- `app/settings/network_identity_mac.mm` — CoreWLAN and the location prompt
- `app/settings/network_profile.cpp` — `QSettings` and the QML singleton `NetworkProfiles`
- `tests/network_profile_test.cpp` — the rules above, without Qt or a Mac

```bash
c++ -std=c++11 -Wall -Wextra -Werror \
    -Iapp/settings \
    tests/network_profile_test.cpp \
    app/settings/network_profile_logic.cpp \
    -o /tmp/network_profile_test
/tmp/network_profile_test
```

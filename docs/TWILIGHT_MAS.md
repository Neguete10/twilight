# Twilight on the Mac App Store

Twilight is the product name for this fork of Moonlight Qt. This is the checklist for a Mac App Store build of the tree as it is now. It does not submit that build.

**Do not submit a build to App Store review.** Do not upload a binary with Transporter, `altool`, or `notarytool`. Do not create In-App Purchases, subscriptions, or any other paid product.

Canonical corresponding source: <https://github.com/Neguete10/twilight>. Lineage: Andy Grundman's [moonlight-qt](https://github.com/andygrundman/moonlight-qt), itself a fork of [moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt).

The version in `app/version.txt` is `7.0.0`. The store build is English only. There is no language picker.

## What is ready in this tree

| Piece | Where |
| --- | --- |
| Opt-in store config | `CONFIG+=twilight-mas` / `TWILIGHT_MAS=1`. Desktop builds do not pass it. |
| Bundle id and name | Placeholder `com.henrique.twilight` and display name Twilight, only when that flag is on. Desktop stays `com.moonlight-stream.Moonlight`. |
| Sandbox entitlements | `app/deploy/macos/Twilight-MAS.entitlements`. |
| Multicast, gated | `TWILIGHT_MAS_MULTICAST=1` selects `app/deploy/macos/Twilight-MAS-multicast.entitlements`. The default store entitlements omit it. |
| ATS | Desktop keeps `NSAllowsArbitraryLoads`. The store plist sets `NSAllowsLocalNetworking` and does not set the blanket key. `scripts/prepare-macos-infoplist.py`. |
| About / licenses | Twilight settings → About (version and a short notice; full license text behind Licenses). Texts are in `app/licenses/` and `qrc:/licenses/`, and qmake copies them to `Contents/Resources/Licenses`. |
| Microphone prompt path | Usage string plus `com.apple.security.device.audio-input`. |
| Store package | `TWILIGHT_MAS=1 scripts/generate-dmg.sh Release` writes a `productbuild` `.pkg`. It does not write a DMG and does not call `notarytool`. |
| Privacy manifest | `app/deploy/macos/PrivacyInfo.xcprivacy`, copied to `Contents/Resources`. |

`TARGET` and `CFBundleExecutable` stay `Moonlight`, so the binary is `Twilight.app/Contents/MacOS/Moonlight`. `QCoreApplication::applicationName` stays `Moonlight` so QSettings do not move.

CoreAudio spatial audio, the stream-stop audio path, picture-in-picture, and the Metal video renderer are already in this tree. The store script compiles the same qmake sources as the desktop script, plus `CONFIG+=twilight-mas`. PyroWave stays opt-in (`CONFIG+=pyrowave`), the same as a desktop `generate-dmg.sh` run. This checklist does not change those features.

There is no Apple SDK on the machine that prepared this checklist, so the `.app` was not built or launched here. `python3 tests/macos_store_prep_test.py` checks the plist rewrite, entitlements, privacy manifest, license files, and the script's refusal to invent a signing identity.

## Build the package

The script fails before it compiles if a store build is missing an identity or a profile. The names below are the placeholders already used for this team. They are not a certificate this repo creates.

```sh
export SIGNING_IDENTITY="3rd Party Mac Developer Application: Your Name (TEAMID)"
export INSTALLER_SIGNING_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)"
export PROVISIONING_PROFILE="$HOME/Downloads/Twilight_MAS.provisionprofile"
# export TWILIGHT_MAS_MULTICAST=1   # only after Apple grants multicast
TWILIGHT_MAS=1 scripts/generate-dmg.sh Release
```

`SIGNING_IDENTITY` signs `Twilight.app`. `INSTALLER_SIGNING_IDENTITY` is the only identity passed to `productbuild`. `PROVISIONING_PROFILE` is copied to `Contents/embedded.provisionprofile` before `codesign`. Output:

```text
build/installer-Release/Twilight-7.0.0.pkg
```

The package command is:

```sh
productbuild --component Twilight.app /Applications \
  --sign "3rd Party Mac Developer Installer: Your Name (TEAMID)" \
  Twilight.pkg
```

Keep the `.pkg` on disk. Do not upload it.

qmake alone (no package):

```sh
qmake CONFIG+=twilight-mas moonlight-qt.pro
# after the multicast grant:
qmake CONFIG+=twilight-mas CONFIG+=twilight-mas-multicast moonlight-qt.pro
```

A desktop DMG is unchanged: run `scripts/generate-dmg.sh Release` without `TWILIGHT_MAS`. Signed desktop builds still pass `app/deploy/macos/spatial-audio.entitlements`. Unsigned builds embed no entitlements. `create-dmg` is only required for that desktop path.

## Entitlements

`Twilight-MAS.entitlements` is the file a profile can match before Apple grants multicast.

| Key | Why |
| --- | --- |
| `com.apple.security.app-sandbox` | Required for Mac App Store apps. |
| `com.apple.security.device.audio-input` | Sandbox microphone. See below. |
| `com.apple.security.network.client` | Outgoing HTTP(S) pairing and app-list calls, UDP stream sockets, and STUN. |
| `com.apple.security.network.server` | The client `bind()`s UDP and receives host packets. |
| `com.apple.developer.spatial-audio.profile-access` | Personalized HRTF. Restricted. The profile has to carry it. |
| `com.apple.developer.coremotion.head-pose` | Head tracking on the spatial mixer. Restricted the same way. |

`com.apple.developer.audio.spatial-audio` is not a current Apple entitlement key. It is not in the file.

These three are not in the file, on purpose:

- `com.apple.security.cs.disable-library-validation` — a poor fit for the store, and not required by anything traced here.
- `com.apple.security.cs.allow-jit`
- `com.apple.security.cs.allow-unsigned-executable-memory`

### JIT is unproven until a sandboxed run

The app is Qt Quick (`QT += quick`, `app/gui/*.qml`). Release macOS builds also set `CONFIG += qtquickcompiler`, which caches QML as C++ and does not by itself remove the QV4 JavaScript engine. Qt's QV4 JIT on Apple platforms asks for `MAP_JIT`. Hardened Runtime blocks that unless `com.apple.security.cs.allow-jit` is set. Some Qt builds then fall back to the interpreter; others fail to start QML.

This tree does not contain Qt, and the store binary was not launched under the sandbox. Until that run either starts cleanly or logs an executable-memory failure, the JIT entitlement is not added. Do not add `allow-unsigned-executable-memory` as a substitute unless that same run shows the JIT path fails without `MAP_JIT`.

### Multicast

LAN discovery uses qmdnsengine (`ComputerManager` browses `_nvstream._tcp.local.`), which is raw multicast DNS, not the Bonjour API. Inside the sandbox that needs the restricted entitlement `com.apple.developer.networking.multicast`. Apple grants it per team: <https://developer.apple.com/contact/request/networking-multicast>.

The key is not in `Twilight-MAS.entitlements`. A provisioning profile that does not have the grant still matches the spatial-audio, head-pose, sandbox, microphone, and network keys. After the grant is on the App ID and a new profile is downloaded, build with `TWILIGHT_MAS_MULTICAST=1`. That selects `Twilight-MAS-multicast.entitlements`, which is the same dictionary plus the multicast key. Signing with the multicast file before the grant is on the profile will fail. That is the gate.

`NSBonjourServices` is not set. Add it only if discovery is rewritten onto the Bonjour APIs. `NSLocalNetworkUsageDescription` is already set.

Manual add-by-address does not use multicast. `ComputerManager::addNewHostManually` parses the string and calls `addNewHost(..., mdns=false)` on the GameStream HTTP port. That needs `network.client` and `network.server` only. The Add Host field in both shells stays available when discovery returns nothing. Settings can also turn mDNS off (`enableMdns`).

## App Transport Security

`app/Info.plist` in the repo is the desktop dictionary: `NSAllowsArbitraryLoads` is true, and `NSAllowsLocalNetworking` is absent.

`scripts/prepare-macos-infoplist.py` runs from `app/app.pro`. For `twilight-mas` it replaces the key element with `NSAllowsLocalNetworking` and leaves the value true. It refuses to emit both keys.

On macOS 11 and later, if `NSAllowsLocalNetworking` is present, the system ignores `NSAllowsArbitraryLoads`. Putting both keys in the desktop plist would turn off the blanket exception the desktop build has today. The two modes stay separate so a desktop user can still add a PC by a DNS name that contains a dot.

Why pairing needs an exception at all: `NvHTTP` talks to the user's Sunshine or GameStream PC.

- Before the certificate is pinned, and again on a certificate mismatch, `getServerInfo` uses `http://<host>:<port>/serverinfo` (default port 47989). That is cleartext HTTP.
- After pairing, launch and quit use `https://<host>:<https-port>/`. The host certificate is not a public CA. `NvHTTP::handleSslErrors` calls `ignoreSslErrors` only when every `QSslError` certificate equals the pinned `QSslCertificate`.

`NSAllowsLocalNetworking` is Apple's exception for local resources: numeric IP addresses (LAN and public IPs), names ending in `.local`, and single-label hostnames. Those are the addresses mDNS returns and the addresses people type into Add PC. It does not cover a DNS name that contains a dot, such as a dynamic-DNS hostname, when that name presents a private certificate or speaks HTTP. On a store build, add that PC by IP address.

Qt's `QNetworkAccessManager` sends these requests through `QSslSocket`, not through a web view. App Transport Security is enforced by the URL loading system. The plist still has to be narrow because App Review reads the key, and the local-networking exception is what covers those host addresses if the system applies ATS to the request. The pin check in `handleSslErrors` stays either way.

Other HTTPS in the client (update check, gamepad mapping list, compatibility list) uses `moonlight-stream.org`, which has a public certificate.

### Review notes

Paste this into App Review notes. Do not claim the app was submitted from this checklist.

```text
App Transport Security

NSAllowsArbitraryLoads is not set. NSAllowsLocalNetworking is set.

Twilight pairs with the user's own Sunshine or GameStream PC. That PC is not a public certificate authority. Before pairing, the client requests http://<host>:47989/serverinfo. After pairing, it requests https://<host>:<https-port>/ and accepts the TLS certificate only when it matches the certificate pinned at pair time (NvHTTP::handleSslErrors). The app does not load arbitrary web content.

NSAllowsLocalNetworking covers numeric IP addresses, .local names, and single-label hostnames. Those are the addresses LAN discovery and Add PC use. A host entered as a DNS name that contains a dot is still subject to ATS. Add that PC by IP address.

The client's other HTTPS calls go to moonlight-stream.org over the public web and do not use this exception.
```

## Microphone

Confirmed from this tree, not from a sandboxed launch (no Apple SDK here):

- `NSMicrophoneUsageDescription` in `app/Info.plist` says Twilight uses the microphone to send voice to the host PC while streaming. The string is already Twilight for every Mac build.
- `com.apple.security.device.audio-input` is in `Twilight-MAS.entitlements` and in the multicast variant. It is a standard sandbox entitlement, not a restricted capability.
- The settings checkbox calls `StreamingPreferences::setMicrophoneEnabled`. Turning it on calls `MacMicrophonePermission::request`, which calls `[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio]` while the status is `NotDetermined`. That is the system prompt. Denied and restricted states do not prompt again; the label tells the user to open System Settings.
- Without the sandbox entitlement, the App Sandbox denies the input device and capture fails instead of prompting. With the usage string and the entitlement, the sandbox allows TCC to show the prompt.

Capture still starts only when the user checked the box and macOS granted access. Stock Sunshine does not play the audio back. Details are in `docs/MICROPHONE_MAC.md`.

## Privacy manifest

`PrivacyInfo.xcprivacy` is required for a Mac App Store upload that calls Apple's required-reason APIs. This tree calls three of them. The manifest declares those and no others.

| Category | Reason | Call in this tree |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | `QSettings` for this app's own preferences, hosts, and identity. No app group. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | `MappingFetcher` reads the cache file's modification time (`QFileInfo::lastModified`) to send `If-Modified-Since`. In the sandbox that file is inside the app container. |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `8FFB.1` | `vt_avsamplelayer.mm` calls `mach_absolute_time()` to stamp a sample buffer for the on-screen video layer. The timestamp is not sent off the Mac. |

`NSPrivacyTracking` is false. `NSPrivacyCollectedDataTypes` is omitted so this file does not invent a privacy nutrition label. Microphone audio is sent to the user's host. The Wi-Fi name is read locally to match a stream profile (`NSLocationUsageDescription` / `NSLocationWhenInUseUsageDescription`). Those usage strings are already in `Info.plist`. The App Store Connect privacy questionnaire is still filled in by the account holder.

Disk-space and active-keyboard categories are not declared. This tree does not call those APIs. The prebuilt FFmpeg, OpenSSL, Opus, SDL2, and libplacebo binaries are not in this worktree, so no reason code was added for them. Qt frameworks that `macdeployqt` copies may carry their own `PrivacyInfo.xcprivacy` when the Qt build is 6.5 or later. After a real Mac build, open the privacy report in Xcode and add a reason only for a symbol the report actually flags.

## About and licenses

GPL-3.0 section 5 wants a modified interactive program to say that it was modified, name a relevant version, state that there is no warranty, and show where to read the license. The About page does that.

- Settings → About. The page shows the version and a short notice (modified fork, GPL-3.0, no warranty, corresponding source). **Licenses** opens the license texts. They are not dumped on the page until then.

The same files are copied into `Twilight.app/Contents/Resources/Licenses`.

The notice says Twilight is a modified fork of Moonlight Qt (moonlight-stream, via Andy Grundman's CoreAudio work), that there is no warranty, that the terms are GPL-3.0, and that the corresponding source is <https://github.com/Neguete10/twilight>.

| Piece | License file |
| --- | --- |
| Twilight, Moonlight Qt, moonlight-common-c | `GPL-3.0.txt` (the repo `LICENSE`) |
| qmdnsengine, Copyright (c) 2017 Nathan Osman | `qmdnsengine-MIT.txt` |
| h264bitstream, Auroras Entertainment and Avail-TVN | `h264bitstream-LGPL-2.1.txt` |
| SDL_GameControllerDB | `SDL_GameControllerDB-Zlib.txt` |
| FFmpeg `libavcodec.61`, `libavutil.59`, `libswscale.8` | `FFmpeg-LGPL-2.1.txt` |
| OpenSSL 3 `libssl.3`, `libcrypto.3` | `OpenSSL-Apache-2.0.txt` |
| Opus | `Opus-BSD.txt` |
| SDL2 | `SDL2-Zlib.txt` |
| SDL2_ttf | `SDL2_ttf-Zlib.txt` |
| libplacebo (only when `CONFIG+=pyrowave`; the default Mac link line does not include `-lplacebo`) | `libplacebo-LGPL-2.1.txt` |

FFmpeg's own license for those libraries is LGPL 2.1 or later unless the prebuilt was configured with `--enable-gpl`. The configure line is not in this tree. The LGPL text is what is shipped. The sonames are the ones in `app/app.pro` (`-lavcodec.61 -lavutil.59 -lswscale.8`), not the older note that said 62 / 60 / 9.

## Spatial audio is on this tree

`Session::createAudioRenderer` tries `CoreAudioRenderer` before SDL on macOS (`HAVE_COREAUDIO` in `app/app.pro`). Playback is `app/streaming/audio/renderers/coreaudio/`. Headphones can enable `kAudioUnitProperty_SpatialMixerEnableHeadTracking` when `StreamingPreferences::spatialHeadTracking` is true, and they set `kAudioUnitProperty_SpatialMixerPersonalizedHRTFMode` to auto. The settings key is `"headtracking"`, default **false**. Both shells have the checkbox.

Head tracking needs `com.apple.developer.coremotion.head-pose`. Personalized HRTF needs `com.apple.developer.spatial-audio.profile-access`. The property writes are gated on macOS 13 and headphones. Apple documents the capabilities for personalized Spatial Audio on macOS 15 and later. The entitlements are in the store file so the profile can carry them. They do nothing useful until the App ID has the capabilities and the profile is regenerated.

Signed desktop DMGs still use `spatial-audio.entitlements`, which includes the sandbox, the microphone entitlement, the two restricted keys, and `com.apple.security.device.input-monitoring`. That is the existing desktop signing file. `TWILIGHT_MAS` does not change it.

## Apple Developer account

Nothing in this workspace can register an App ID, download a profile, or create the App Store Connect record. Those steps need the paid team.

1. Register an explicit App ID `com.henrique.twilight`.
2. Enable **Spatial Audio Profile** and **Head Pose** on that App ID. If either row is a request, wait until Apple enables it before generating a profile.
3. Request the multicast entitlement at <https://developer.apple.com/contact/request/networking-multicast> if LAN discovery should work inside the sandbox. Until the grant is on the profile, build without `TWILIGHT_MAS_MULTICAST`.
4. Create a Mac App Store Connect distribution profile for that App ID and the Apple Distribution certificate. Decode it with `security cms -D -i Twilight_MAS.provisionprofile` and confirm the keys you actually sign with. Pass that file as `PROVISIONING_PROFILE`.
5. Install the Apple Distribution application certificate and the Mac App Store installer certificate. Pass them as `SIGNING_IDENTITY` and `INSTALLER_SIGNING_IDENTITY`. Do not point `SIGNING_IDENTITY` at a Developer ID certificate. The restricted entitlements will not match.

App Store Connect, record only, left in **Prepare for Submission**:

- Platform: macOS.
- Name: `Twilight`, or another free name if that one is taken.
- Primary language: English (U.S.).
- Bundle ID: `com.henrique.twilight`.
- SKU: `twilight-macos`.
- Price: leave it empty, or **Free** if the page will not save otherwise.

Do not upload a build, do not submit for review, and do not add a paid product.

## GPL-3.0 and the Mac App Store terms

Moonlight Qt is GPL-3.0. The About page and the license files carry the modification notice, the no-warranty notice, the license text, and the corresponding-source URL. That is the in-app part of sections 4, 5, and 6.

Sections 6 and 10 forbid additional restrictions on the rights the GPL grants. The Mac App Store license terms restrict redistribution, installation, and modification in ways GPL-3.0 does not allow. Shipping Twilight on the store needs the copyright holders of Moonlight Qt, moonlight-common-c, and the CoreAudio modifications to agree to those terms, or an equivalent permission. This repository cannot grant that. Do not treat a successful `productbuild` as clearance to submit.

## Still not a submission

Leave the App Store Connect version in **Prepare for Submission**. The `.pkg` this script writes stays on disk.

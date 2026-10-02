# Twilight on the Mac App Store — scaffolding only

Twilight is the product name for this fork of Moonlight Qt. This document is the Mac App Store (MAS) checklist that matches the files added in this branch.

**Do not submit a build to App Store review.** Do not upload a binary with Transporter, `altool`, or `notarytool` for the store. Do not create In-App Purchases, subscriptions, or any other paid product. The steps below stop at a placeholder app record and local signing config.

Canonical fork (corresponding-source remote once that GitHub repo is the one you push): <https://github.com/Neguete10/twilight>. Lineage: Andy Grundman's [moonlight-qt](https://github.com/andygrundman/moonlight-qt), itself a fork of [moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt).

## What was added

| File | Role |
| --- | --- |
| `app/deploy/macos/Twilight-MAS.entitlements` | App Sandbox, network client/server, Spatial Audio Profile, Head Pose. Used only by the opt-in MAS config. |
| `app/app.pro` (`CONFIG+=twilight-mas`) | Rewrites the bundle id and display name, and points the Xcode generator at those entitlements plus Hardened Runtime. |
| `app/Info.plist` | `BUNDLE_ID` and `DISPLAY_NAME` tokens. qmake substitutes them. Default values stay `com.moonlight-stream.Moonlight` and `Moonlight`. |
| `scripts/generate-dmg.sh` | `TWILIGHT_MAS=1` passes `CONFIG+=twilight-mas` and `codesign --options runtime --entitlements ...`. Unset, the script is the existing Developer ID / DMG path. |

The executable name and `TARGET` stay `Moonlight`, so `scripts/generate-dmg.sh` still looks for `app/Moonlight.app`. Finder uses `CFBundleDisplayName` (`Twilight` only in the MAS config). Shipping desktop builds do not pick up the Twilight bundle id.

## Enable the MAS config

Makefile / DMG script (does not upload):

```sh
export SIGNING_IDENTITY="3rd Party Mac Developer Application: Your Name (TEAMID)"
TWILIGHT_MAS=1 scripts/generate-dmg.sh Release
```

qmake directly:

```sh
qmake CONFIG+=twilight-mas moonlight-qt.pro
```

qmake prints the bundle id, the entitlements path, and the codesign shape:

```text
codesign --force --options runtime --timestamp \
  --entitlements app/deploy/macos/Twilight-MAS.entitlements \
  --sign "IDENTITY" Moonlight.app
```

`--options runtime` is Hardened Runtime. The default DMG invocation already uses it and does **not** pass an entitlements file, so App Sandbox stays off for Developer ID builds.

Xcode (qmake `-spec macx-xcode`, or a wrapper project), only if `CONFIG+=twilight-mas` was set when the Xcode project was generated:

1. Target → Signing & Capabilities → set the team and a Mac App Store provisioning profile for `com.henrique.twilight`.
2. Confirm Code Signing Entitlements is `app/deploy/macos/Twilight-MAS.entitlements`.
3. Confirm Hardened Runtime is on (`ENABLE_HARDENED_RUNTIME`).
4. The same two restricted capabilities must be turned on for the App ID in the developer portal (next section) or the profile will not match the entitlements file.

Placeholder bundle id behind that flag: `com.henrique.twilight`. It is a suggestion until you register it. It is not applied unless `twilight-mas` is on.

## Entitlements in the file

| Key | Why it is in the file |
| --- | --- |
| `com.apple.security.app-sandbox` | Required for Mac App Store apps. |
| `com.apple.security.network.client` | Outgoing connections: HTTPS pairing and app-list calls to Sunshine / GameStream (`app/backend/nvhttp.cpp`), UDP stream sockets, and STUN (`LiFindExternalAddressIP4("stun.moonlight-stream.org", 3478, ...)` in `app/backend/computermanager.cpp`). |
| `com.apple.security.network.server` | The client `bind()`s UDP and receives host packets (video, audio, control). qmdnsengine also listens for mDNS replies. Sandbox treats that as incoming connections. |
| `com.apple.developer.spatial-audio.profile-access` | Spatial Audio Profile capability. Personalized HRTF on the spatial-mixer branch. Restricted: the provisioning profile has to carry it. |
| `com.apple.developer.coremotion.head-pose` | Head Pose capability. Required together with `kAudioUnitProperty_SpatialMixerEnableHeadTracking`. Restricted in the same way. |

`com.apple.developer.audio.spatial-audio` is not a current Apple entitlement key. Do not add it.

### Sandbox network keys that are not in the file yet

`com.apple.developer.networking.multicast` is the restricted entitlement for custom IP multicast. qmdnsengine (submodule `qmdnsengine/qmdnsengine`, used from `app/backend/computermanager.cpp`) discovers hosts with multicast DNS, which is not the high-level Bonjour API. LAN discovery inside the sandbox needs this key, and Apple grants it per team (request: <https://developer.apple.com/contact/request/networking-multicast>). It is omitted from `Twilight-MAS.entitlements` so a profile that does not have the grant yet can still match the other keys. After the grant, add:

```xml
<key>com.apple.developer.networking.multicast</key>
<true/>
```

Also add the service types you browse to `NSBonjourServices` in Info.plist if you switch discovery to the Bonjour APIs. `NSLocalNetworkUsageDescription` is already set (the MAS config rewrites the leading "Moonlight" to "Twilight").

Manual "Add PC" by address uses ordinary client/server UDP and TCP and does not need the multicast entitlement.

## Apple Developer portal (human, paid program)

`profile-access` and `head-pose` are not free-form entitlements. A free Apple ID, a Developer ID profile, or an entitlements file alone will not authorize them. You need:

- Apple Developer Program membership for the team that will ship Twilight
- An explicit App ID
- Those capabilities enabled on that App ID
- A Mac App Store distribution provisioning profile generated after the capabilities are on
- The matching Apple Distribution certificate (`3rd Party Mac Developer Application` / Apple Distribution) and installer certificate if you build a `.pkg`

Register the App ID:

1. Sign in at <https://developer.apple.com/account> as an Account Holder or Admin.
2. Open **Certificates, Identifiers & Profiles**.
3. **Identifiers** → **+**.
4. Choose **App IDs** → **App** → Continue.
5. Description: `Twilight`.
6. Bundle ID: **Explicit**, `com.henrique.twilight`.
7. Enable **Spatial Audio Profile** (`com.apple.developer.spatial-audio.profile-access`) and **Head Pose** (`com.apple.developer.coremotion.head-pose`).
8. If either row is missing or shows a request action, use that request (or Apple Developer Support). Wait until the capability is actually enabled before generating a profile. Checking a box that the team is not approved for will not put the key in the profile.
9. Register.

Create the profile:

1. **Profiles** → **+**.
2. Distribution → **Mac App Store Connect** (the Mac App Store distribution profile).
3. App ID: `com.henrique.twilight`.
4. The Apple Distribution certificate for this team.
5. Name it (for example `Twilight MAS`), generate, and download.
6. Confirm the profile lists sandbox, network client, network server, spatial-audio profile-access, and head-pose. Decode with:

```sh
security cms -D -i Twilight_MAS.provisionprofile
```

There is no credential in this workspace that can create the App ID, the profile, or the App Store Connect record. Those clicks are yours.

## App Store Connect placeholder (human)

Create the record only. Leave it in **Prepare for Submission**.

1. Sign in at <https://appstoreconnect.apple.com> with the same team.
2. Open **Apps** (My Apps).
3. Click **+** next to Apps and choose **New App**.
4. In the dialog:
   - **Platforms:** macOS only.
   - **Name:** `Twilight`. If that name is already taken on the Mac App Store, pick another placeholder such as `Twilight Stream`. The name can be edited later; the SKU cannot.
   - **Primary language:** English (U.S.), or whichever you will localize first.
   - **Bundle ID:** `com.henrique.twilight`. The menu only lists App IDs registered on this team. If it is absent, finish the Identifier step above on the same team and reload.
   - **SKU:** `twilight-macos`. Any unique string is fine. Customers never see it. It cannot be changed after you click Create.
   - **User Access:** Full Access.
5. Click **Create**.
6. You should land on version **1.0** in state **Prepare for Submission**. Stop.

Do not:

- upload a build or click **Add for Review** / **Submit for Review**
- add In-App Purchases, subscriptions, or a paid product
- set a price tier other than leaving the schedule empty (if the page forces a price before it will save anything else, choose **Free** and stop)

Creating this record does not submit the app.

A store package, when you eventually build one locally, is a signed installer, not the DMG:

```sh
productbuild --component Moonlight.app /Applications \
  --sign "3rd Party Mac Developer Installer: Your Name (TEAMID)" \
  Twilight.pkg
```

Keep that `.pkg` on disk. Do not upload it.

## GPL-3.0 attribution

Moonlight Qt is GPL-3.0. The full license is `LICENSE` at the repo root (GNU General Public License version 3, 29 June 2007, copyright the Free Software Foundation). The Windows installer copy is `wix/MoonlightSetup/license.rtf`. There is no `THIRD-PARTY` or `NOTICE` file in this tree.

Practical obligations for an MAS binary (this is a map of the license text, not legal advice; the copyright holders still have to be okay with store terms):

- **Notices stay on the work.** GPL-3.0 section 4 requires the copyright notice, the license text, and the absence-of-warranty notice on every copy. Section 5 requires a modified version (Twilight) to carry prominent notices that it was modified, a relevant date, and that the whole work is under GPL-3.0. Keep Moonlight and Andy Grundman attribution. Do not present Twilight as the upstream Moonlight project.
- **Corresponding Source.** Section 6 requires the MAS object code to be accompanied by the Corresponding Source (this repo, submodules, and build scripts) or a written offer / network server that provides it at no charge. Put the source URL in the App Store description and in the app. A store listing that only ships the binary does not satisfy that by itself.
- **Interactive notices.** Section 0's "Appropriate Legal Notices" and section 5(d) expect an interactive UI to show a copyright notice, say there is no warranty, and tell the user they can redistribute under GPL-3.0 and where to read the license.
- **No extra restrictions.** Section 6 and section 10 mean you cannot add terms that restrict what the GPL already allows. Mac App Store usage rules are a known tension with GPL-3.0. Resolve that with the copyright holders before any submission. This scaffolding does not submit.

### Notices that exist in the repo today

| Piece | License | Where the notice lives |
| --- | --- | --- |
| Twilight / Moonlight Qt | GPL-3.0 | `LICENSE`, `wix/MoonlightSetup/license.rtf` |
| `moonlight-common-c` submodule | GPL-3.0 | upstream `LICENSE.txt` in `moonlight-stream/moonlight-common-c` (submodule; not checked out in every worktree) |
| qmdnsengine | MIT, Copyright (c) 2017 Nathan Osman | `qmdnsengine/qmdnsengine_export.h` (permission notice must stay with the library) |
| h264bitstream submodule | LGPL-2.1 | upstream `LICENSE` in `aizvorski/h264bitstream` |
| SDL_GameControllerDB submodule | Zlib | upstream `LICENSE` |
| macOS prebuilts | upstream licenses of each library | `setup-deps.py` downloads `moonlight-stream/moonlight-qt-deps` tag `v8`, asset `macos-universal.zip`. `app/app.pro` links `ssl.3`, `crypto.3`, `avcodec.62`, `avutil.60`, `swscale.9`, `opus.0`, `SDL2`, `SDL2_ttf`, `placebo` (FFmpeg, OpenSSL, Opus, SDL2, libplacebo). Ship those projects' copyright and license texts inside the app bundle. |

### About / Licenses UI

The current UI does not meet the GPL interactive-notice bar. `app/gui/main.qml` shows `Version %1` on the settings toolbar (`versionLabel`) and links Help and Discord at the Moonlight sites. There is no About or Licenses page. Add one before any submission, including:

- Twilight is a modified fork of Moonlight Qt (moonlight-stream, via Andy Grundman's CoreAudio work)
- copyright notices and "no warranty"
- GPL-3.0, with a way to read `LICENSE`
- the corresponding-source URL
- the MIT / LGPL-2.1 / Zlib notices above, plus the prebuilt-library notices

## Spatial audio and head tracking in this fork

`master` does not contain the CoreAudio spatial mixer. Playback on master is `SdlAudioRenderer` (`app/streaming/audio/renderers/sdlaud.cpp`), selected from `Session::createAudioRenderer` in `app/streaming/audio/audio.cpp`.

The implementation lives on branch `andyg.coreaudio-spatial-mixer` (the earlier `andyg.coreaudio` branch has the same renderer without the later sync):

| Location | What it does |
| --- | --- |
| `app/streaming/audio/renderers/coreaudio/coreaudio.cpp` | `CoreAudioRenderer`. Chooses passthrough vs spatial output (`getSpatialMixerOutputType`). |
| `app/streaming/audio/renderers/coreaudio/au_spatial_renderer.mm` | `kAudioUnitSubType_SpatialMixer`. Headphones call `kAudioUnitProperty_SpatialMixerEnableHeadTracking` when `StreamingPreferences::spatialHeadTracking` is true, and `kAudioUnitProperty_SpatialMixerPersonalizedHRTFMode` (`kSpatialMixerPersonalizedHRTFMode_Auto`). |
| `app/streaming/audio/audio.cpp` | Selects `CoreAudioRenderer` on that branch. |
| `app/app.pro` | Links `-framework CoreAudio` on that branch. |
| `app/settings/streamingpreferences.cpp` | Property `spatialHeadTracking`, settings key `"headtracking"`, default **false**. |
| `app/gui/SettingsView.qml` | Checkbox text "Enable head-tracking" (`id: spatialHeadTracking`). |
| `app/deploy/macos/spatial-audio.entitlements` | On that branch only: sandbox + the two developer keys, and `scripts/generate-dmg.sh` there passes that file into the **DMG** codesign. This PR does not do that. Keep sandbox off the Developer ID path; use `TWILIGHT_MAS=1`. |
| `app/streaming/audio/renderers/coreaudio/README.coreaudio` | Design notes for passthrough vs `AUSpatialMixer`. |

Head tracking needs both the AudioUnit property and `com.apple.developer.coremotion.head-pose`. Personalized HRTF needs `com.apple.developer.spatial-audio.profile-access`. Apple documents those capabilities for personalized Spatial Audio and head tracking on macOS 15 and later. The branch's `@available` check around the property writes is macOS 13.0, and the head-tracking write runs only for `kSpatialMixerOutputType_Headphones`.

That branch is not merged here. Turning on `TWILIGHT_MAS` on master signs the SDL build with the entitlements so the profile and sandbox can be exercised; the spatial calls start working once the CoreAudio renderer is merged.

## Known MAS blockers for this Qt GameStream client

These are open. None of them are fixed by this scaffolding.

- **Sandbox vs discovery and sockets.** Raw sockets are not used in the checked-out tree; STUN is UDP. The sandbox still blocks `SOCK_RAW` if a later path needs it. Multicast mDNS needs the entitlement described above. Until then, discovery of Sunshine hosts on the LAN will fail inside the sandbox; manual address entry is the fallback.
- **Microphone.** Capture and the `0x3003` control-stream send are documented in `docs/MICROPHONE_MAC.md`. `NSMicrophoneUsageDescription` is in `app/Info.plist`. Sandboxed builds also need `com.apple.security.device.audio-input` (a standard sandbox entitlement, already listed in `Twilight-MAS.entitlements` and `spatial-audio.entitlements`). Do not submit a build. Stock Sunshine still does not play the audio back.
- **Accessibility.** No `AXIsProcessTrusted` or event tap. `app/main.cpp` only forces Qt tab focus so keyboard and gamepad navigation work. A global hotkey hook would need the Accessibility TCC permission, which sandboxed MAS apps do not get in a useful way.
- **`NSAllowsArbitraryLoads`.** `app/Info.plist` sets it true under `NSAppTransportSecurity`. Sunshine and GameStream pairing talk to hosts that are not public CAs. App Review commonly rejects blanket ATS exceptions. Replacing this needs a real exception design (pinned certificates are already part of pairing) and review notes. Left as-is so desktop builds keep current behavior.
- **Qt deployment.** `scripts/generate-dmg.sh` already runs `macdeployqt -appstore-compliant`. MAS distribution is still a `productbuild` `.pkg` signed with the installer certificate, not a DMG. Hardened Runtime plus sandbox can trip Qt's QML JIT; add `com.apple.security.cs.allow-jit` or `com.apple.security.cs.allow-unsigned-executable-memory` only if a sandboxed run proves you need it. `com.apple.security.cs.disable-library-validation` is a poor fit for the store.
- **Bundle id.** Upstream `com.moonlight-stream.Moonlight` cannot be registered by this team. The MAS id is `com.henrique.twilight` and only applies with `CONFIG+=twilight-mas`.
- **Game Mode.** Already present in `app/Info.plist`: `GCSupportsGameMode` and `LSSupportsGameMode` (both true), plus `GCSupportedGameControllers` / `ExtendedGamepad`. No change in this PR.
- **Bundle file name.** The `.app` and `CFBundleExecutable` remain `Moonlight` so the DMG script stays valid. The user-visible display name becomes Twilight only in the MAS config.
- **GPL UI and source offer.** Missing About/Licenses page, described above.
- **Restricted entitlements without a profile.** Signing `TWILIGHT_MAS=1` with a Developer ID certificate will fail or yield an unusable signature for the two `com.apple.developer.*` keys. Use the Mac App Store profile after the capabilities are approved.
- **Spatial mixer not on master.** Head tracking cannot be tested end to end until `andyg.coreaudio-spatial-mixer` is merged.

## Do not submit

This branch is local signing and documentation. Leave the App Store Connect version in **Prepare for Submission**. Do not upload a build, do not click **Submit for Review**, and do not create paid products.

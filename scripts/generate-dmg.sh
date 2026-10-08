#!/bin/bash
# Desktop DMGs require the create-dmg shell script:
# https://github.com/create-dmg/create-dmg
# Install it with: brew install create-dmg
# The npm package named create-dmg does not accept a window layout or background.
# TWILIGHT_MAS=1 does not create a DMG. It writes a productbuild .pkg.
BUILD_CONFIG=$1

fail()
{
	echo "$1" 1>&2
	exit 1
}

if [ "$BUILD_CONFIG" != "Debug" ] && [ "$BUILD_CONFIG" != "Release" ]; then
  fail "Invalid build configuration - expected 'Debug' or 'Release'"
fi

BUILD_ROOT=$PWD/build
SOURCE_ROOT=$PWD
BUILD_FOLDER=$BUILD_ROOT/build-$BUILD_CONFIG
INSTALLER_FOLDER=$BUILD_ROOT/installer-$BUILD_CONFIG
VERSION=`cat $SOURCE_ROOT/app/version.txt`

if [ "$SIGNING_PROVIDER_SHORTNAME" == "" ]; then
  SIGNING_PROVIDER_SHORTNAME=$SIGNING_IDENTITY
fi
if [ "$SIGNING_IDENTITY" == "" ]; then
  SIGNING_IDENTITY=$SIGNING_PROVIDER_SHORTNAME
fi

# Check store identities before the clean-tree rule so a missing certificate
# name fails here, including on a dirty worktree.
if [ "${TWILIGHT_MAS:-}" = "1" ]; then
  if [ "$SIGNING_IDENTITY" == "" ]; then
    fail "TWILIGHT_MAS=1 requires SIGNING_IDENTITY, the Mac App Store application certificate. Example: export SIGNING_IDENTITY=\"3rd Party Mac Developer Application: Your Name (TEAMID)\". This script does not invent a signing identity."
  fi
  if [ "${INSTALLER_SIGNING_IDENTITY:-}" == "" ]; then
    fail "TWILIGHT_MAS=1 requires INSTALLER_SIGNING_IDENTITY for productbuild. Example: export INSTALLER_SIGNING_IDENTITY=\"3rd Party Mac Developer Installer: Your Name (TEAMID)\". This script does not invent a signing identity."
  fi
  if [ "${PROVISIONING_PROFILE:-}" == "" ] || [ ! -f "${PROVISIONING_PROFILE}" ]; then
    fail "TWILIGHT_MAS=1 requires PROVISIONING_PROFILE set to a downloaded Mac App Store distribution profile (.provisionprofile) for com.henrique.twilight. This script does not create one."
  fi
fi

[ "$SIGNING_IDENTITY" == "" ] || git diff-index --quiet HEAD -- || fail "Signed release builds must not have unstaged changes!"

echo Cleaning output directories
rm -rf $BUILD_FOLDER
rm -rf $INSTALLER_FOLDER
mkdir $BUILD_ROOT
mkdir $BUILD_FOLDER
mkdir $INSTALLER_FOLDER

# Desktop DMG is the default. Signed Developer ID desktop builds use
# empty entitlements (no app-sandbox). Do not pass spatial-audio.entitlements
# here: its com.apple.developer.* keys require Apple grants and cause
# launchd spawn failure (POSIX 163) without them. Matches shipping 7.0.0.
# Unsigned builds embed no entitlements.
# TWILIGHT_MAS=1 selects CONFIG+=twilight-mas and writes a productbuild
# .pkg. It does not upload, notarize, or submit a build.
# TWILIGHT_MAS_MULTICAST=1 also selects the multicast entitlement. Leave
# it unset until the provisioning profile contains Apple's grant.
QMAKE_CONFIG_ARGS=
MAS_ENTITLEMENTS="$SOURCE_ROOT/app/deploy/macos/Twilight-MAS.entitlements"
# Desktop ships PyroWave (Vulkan/Metal). generate-dmg used to leave
# CONFIG+=pyrowave off; 7.0.1 without it hid Settings→Video→PyroWave and
# omitted the decoder + libpyrowave dylibs. Desktop builds are Apple
# Silicon only (macOS 13). v19's libplacebo is universal; the app is arm64.
DEVICE_ARCHS="arm64"
if [ "${TWILIGHT_MAS:-}" = "1" ]; then
  QMAKE_CONFIG_ARGS="CONFIG+=twilight-mas"
  if [ "${TWILIGHT_MAS_MULTICAST:-}" = "1" ]; then
    QMAKE_CONFIG_ARGS="$QMAKE_CONFIG_ARGS CONFIG+=twilight-mas-multicast"
    MAS_ENTITLEMENTS="$SOURCE_ROOT/app/deploy/macos/Twilight-MAS-multicast.entitlements"
    echo "TWILIGHT_MAS_MULTICAST=1: com.apple.developer.networking.multicast"
    echo "The provisioning profile must include that grant or signing will fail."
  fi
  echo "TWILIGHT_MAS=1: $QMAKE_CONFIG_ARGS"
  echo "Hardened Runtime: codesign --options runtime"
  echo "Entitlements: $MAS_ENTITLEMENTS"
  echo "Installer identity is used only for productbuild. Nothing is uploaded."
else
  # TWILIGHT_PYROWAVE=0 skips the decoder for a codec-free desktop DMG.
  if [ "${TWILIGHT_PYROWAVE:-1}" != "0" ]; then
    QMAKE_CONFIG_ARGS="CONFIG+=pyrowave"
    DEVICE_ARCHS="arm64"
    echo "Desktop PyroWave: CONFIG+=pyrowave, arch $DEVICE_ARCHS"
  fi
fi
MACOS_DEPLOYMENT_TARGET=$(sh "$SOURCE_ROOT/scripts/macos-deployment-target.sh") || fail "macOS deployment target is not set"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
echo "macOS deployment target: $MACOS_DEPLOYMENT_TARGET"

# Third-party libraries for the deployment target:
# scripts/build-macos-deps.sh (official Qt 6.11.2, moonlight-qt-deps v19
# libplacebo and MoltenVK, and a Vulkan loader built from source). 7.0.1
# bundled Homebrew's copies, which carry the build Mac's OS as minos.
# Desktop builds refuse to fall back to Homebrew. TWILIGHT_ALLOW_HOMEBREW_DEPS=1
# is for local unsigned experiments only.
MACOS_DEPS_ENV="${TWILIGHT_MACOS_DEPS:-$BUILD_ROOT/macos-deps}/env.sh"
QMAKE_DEPS_ARGS=()
if [ -f "$MACOS_DEPS_ENV" ]; then
  # shellcheck disable=SC1090
  . "$MACOS_DEPS_ENV"
  [ "$TWILIGHT_DEPS_TARGET" = "$MACOS_DEPLOYMENT_TARGET" ] || fail "$MACOS_DEPS_ENV was built for $TWILIGHT_DEPS_TARGET, not $MACOS_DEPLOYMENT_TARGET. Re-run scripts/build-macos-deps.sh"
  echo "Using macOS deps from $TWILIGHT_DEPS_PREFIX and Qt from $TWILIGHT_QT_DIR"
  unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH || true
  QMAKE_DEPS_ARGS=(
    "QMAKE_CFLAGS+=-I$TWILIGHT_DEPS_PREFIX/include"
    "QMAKE_CXXFLAGS+=-I$TWILIGHT_DEPS_PREFIX/include"
    "QMAKE_OBJECTIVE_CFLAGS+=-I$TWILIGHT_DEPS_PREFIX/include"
    "QMAKE_LFLAGS+=-L$TWILIGHT_DEPS_PREFIX/lib"
  )
elif [ "${TWILIGHT_MAS:-}" != "1" ]; then
  if [ "${TWILIGHT_ALLOW_HOMEBREW_DEPS:-}" = "1" ] && [ "$SIGNING_IDENTITY" == "" ]; then
    echo "WARNING: $MACOS_DEPS_ENV missing; using Homebrew libraries. The bundle check below will likely fail."
  else
    fail "Missing $MACOS_DEPS_ENV. Run scripts/build-macos-deps.sh first so the bundle does not ship Homebrew libraries built for this Mac's OS."
  fi
fi
case "$(command -v qmake)" in
  /opt/homebrew/*|/usr/local/*)
    [ "${TWILIGHT_ALLOW_HOMEBREW_DEPS:-}" = "1" ] || fail "qmake on PATH is Homebrew's ($(command -v qmake)). Its Qt is built for this Mac's OS. Use the Qt from scripts/build-macos-deps.sh." ;;
esac
if command -v qmake >/dev/null 2>&1; then
  echo "qmake: $(command -v qmake) ($(qmake -query QT_VERSION))"
fi

echo Configuring the project
pushd $BUILD_FOLDER
qmake $SOURCE_ROOT/moonlight-qt.pro \
  QMAKE_APPLE_DEVICE_ARCHS="$DEVICE_ARCHS" \
  QMAKE_MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
  "${QMAKE_DEPS_ARGS[@]}" \
  $QMAKE_CONFIG_ARGS || fail "Qmake failed!"
popd

echo Compiling Moonlight in $BUILD_CONFIG configuration
pushd $BUILD_FOLDER
make -j$(sysctl -n hw.logicalcpu) $(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]') || fail "Make failed!"
popd

echo Saving dSYM file
pushd $BUILD_FOLDER
dsymutil app/Twilight.app/Contents/MacOS/Twilight -o Twilight-$VERSION.dsym || fail "dSYM creation failed!"
cp -R Twilight-$VERSION.dsym $INSTALLER_FOLDER || fail "dSYM copy failed!"
popd

echo Creating app bundle
EXTRA_ARGS=
if [ "$BUILD_CONFIG" == "Debug" ]; then EXTRA_ARGS="$EXTRA_ARGS -use-debug-libs"; fi
echo Extra deployment arguments: $EXTRA_ARGS
macdeployqt $BUILD_FOLDER/app/Twilight.app $EXTRA_ARGS -qmldir=$SOURCE_ROOT/app/gui -appstore-compliant || fail "macdeployqt failed!"

echo Removing dSYM files from app bundle
find $BUILD_FOLDER/app/Twilight.app/ -name '*.dSYM' | xargs rm -rf

# PyroWave's Vulkan backend loads libvulkan, and the loader finds MoltenVK
# through Contents/Resources/vulkan/icd.d. v19's libplacebo is linked, so
# macdeployqt copies it; the loader and MoltenVK are not linked.
if [ -n "${TWILIGHT_DEPS_PREFIX:-}" ] && [[ "$QMAKE_CONFIG_ARGS" == *pyrowave* ]]; then
  [ -f "$TWILIGHT_DEPS_PREFIX/lib/libMoltenVK.dylib" ] || fail "Missing $TWILIGHT_DEPS_PREFIX/lib/libMoltenVK.dylib. Run scripts/build-macos-deps.sh prebuilts"
  [ -e "$TWILIGHT_DEPS_PREFIX/lib/libvulkan.1.dylib" ] || fail "Missing $TWILIGHT_DEPS_PREFIX/lib/libvulkan.1.dylib. Run scripts/build-macos-deps.sh vulkan"
  [ -f "$TWILIGHT_DEPS_PREFIX/share/vulkan/icd.d/MoltenVK_icd.json" ] || fail "Missing MoltenVK ICD json. Run scripts/build-macos-deps.sh prebuilts"
  echo Bundling MoltenVK and the Vulkan loader
  FRAMEWORKS="$BUILD_FOLDER/app/Twilight.app/Contents/Frameworks"
  mkdir -p "$FRAMEWORKS"
  cp -a "$TWILIGHT_DEPS_PREFIX/lib/libMoltenVK.dylib" "$FRAMEWORKS/libMoltenVK.dylib" || fail "MoltenVK copy failed!"
  cp -a "$TWILIGHT_DEPS_PREFIX/lib"/libvulkan*.dylib "$FRAMEWORKS/" || fail "Vulkan loader copy failed!"
  if [ ! -f "$FRAMEWORKS/libplacebo.dylib" ]; then
    cp -a "$TWILIGHT_DEPS_PREFIX/lib/libplacebo.dylib" "$FRAMEWORKS/libplacebo.dylib" || fail "libplacebo copy failed!"
  fi
  mkdir -p "$BUILD_FOLDER/app/Twilight.app/Contents/Resources/vulkan/icd.d"
  cp "$TWILIGHT_DEPS_PREFIX/share/vulkan/icd.d/MoltenVK_icd.json" "$BUILD_FOLDER/app/Twilight.app/Contents/Resources/vulkan/icd.d/" || fail "MoltenVK ICD copy failed!"
fi

# Drop Qt PDF plug-ins (they need QtPdf, which this app does not ship) and
# strip LC_RPATH entries that point at Homebrew or another absolute prefix.
# Do this before signing. Developer ID signing below is unchanged:
# hardened runtime, no entitlements plist.
python3 "$SOURCE_ROOT/scripts/prepare-macos-bundle.py" "$BUILD_FOLDER/app/Twilight.app" || fail "Could not strip outside rpaths or drop orphan plug-ins"

echo "Checking bundle minos <= $MACOS_DEPLOYMENT_TARGET"
"$SOURCE_ROOT/scripts/check-macos-minos.sh" "$BUILD_FOLDER/app/Twilight.app" "$MACOS_DEPLOYMENT_TARGET" || fail "Bundle has Mach-O files newer than macOS $MACOS_DEPLOYMENT_TARGET or links outside the bundle"

if [ "$SIGNING_IDENTITY" != "" ]; then
  echo Signing app bundle
  if [ "${TWILIGHT_MAS:-}" = "1" ]; then
    # The profile has to be inside the bundle before the signature is sealed.
    echo "Embedding provisioning profile"
    cp "$PROVISIONING_PROFILE" "$BUILD_FOLDER/app/Twilight.app/Contents/embedded.provisionprofile" \
      || fail "Could not embed the provisioning profile"
    # Hardened Runtime plus the Mac App Store entitlements.
    codesign --force --deep --options runtime --timestamp \
      --entitlements "$MAS_ENTITLEMENTS" \
      --sign "$SIGNING_IDENTITY" \
      $BUILD_FOLDER/app/Twilight.app || fail "Signing failed!"
  else
    # Developer ID desktop: hardened runtime, no entitlements plist.
    # spatial-audio.entitlements is MAS-oriented (app-sandbox + restricted
    # com.apple.developer.*). Embedding it on Developer ID breaks open.
    codesign --force --deep --options runtime --timestamp \
      --sign "$SIGNING_IDENTITY" \
      $BUILD_FOLDER/app/Twilight.app || fail "Signing failed!"
  fi
  echo "App signature:"
  codesign -d --entitlements - -vvv $BUILD_FOLDER/app/Twilight.app
fi

# A store package is a signed installer, not a DMG. Skip create-dmg and
# Developer ID notarization on this path.
if [ "${TWILIGHT_MAS:-}" = "1" ]; then
  echo "Creating Mac App Store installer package"
  productbuild --component "$BUILD_FOLDER/app/Twilight.app" /Applications \
    --sign "$INSTALLER_SIGNING_IDENTITY" \
    "$INSTALLER_FOLDER/Twilight-$VERSION.pkg" || fail "productbuild failed!"
  echo "Mac App Store package: $INSTALLER_FOLDER/Twilight-$VERSION.pkg"
  echo "This script does not upload or submit the package."
  echo Build successful
  exit 0
fi

echo Creating DMG
# The drag-and-drop window is the desktop path only. TWILIGHT_MAS already
# exited above with a productbuild package.
# create-dmg from https://github.com/create-dmg/create-dmg places
# Twilight.app and an Applications symlink, then tells Finder the window
# size and icon positions. The npm package of the same name cannot.
if ! create-dmg --help 2>&1 | grep -q -- '--app-drop-link'; then
  fail "Desktop DMGs need create-dmg from https://github.com/create-dmg/create-dmg (brew install create-dmg). It accepts --app-drop-link and --background. The npm package named create-dmg does not, and it leaves a bare disk image."
fi

# Window size, icon positions, and the caption live in one file so the
# background arrow stays lined up with the icons.
. "$SOURCE_ROOT/app/deploy/macos/dmg/layout.env"
[ -n "$DMG_VOLNAME" ] && [ -n "$DMG_WINDOW_W" ] && [ -n "$DMG_WINDOW_H" ] && [ -n "$DMG_APP_X" ] && [ -n "$DMG_APPLICATIONS_X" ] || fail "app/deploy/macos/dmg/layout.env is incomplete"
DMG_BACKGROUND="$SOURCE_ROOT/app/deploy/macos/dmg/background.png"
DMG_BACKGROUND_2X="$SOURCE_ROOT/app/deploy/macos/dmg/background@2x.png"
[ -f "$DMG_BACKGROUND" ] || fail "Missing $DMG_BACKGROUND. Regenerate with: python3 scripts/make_dmg_background.py"
[ -f "$DMG_BACKGROUND_2X" ] || fail "Missing $DMG_BACKGROUND_2X. Regenerate with: python3 scripts/make_dmg_background.py"
[ -f "$SOURCE_ROOT/app/twilight.icns" ] || fail "Missing $SOURCE_ROOT/app/twilight.icns"

# HFS+ is create-dmg's default. Finder stores this window's icon positions
# and background on that filesystem, so the image stays on that default.
# Stage only the app. create-dmg adds the Applications symlink itself.
# Both background resolutions go in .background. create-dmg copies the 1x
# file again and points Finder at it. Finder then loads background@2x.png
# from that same folder on a retina display.
DMG_ROOT="$INSTALLER_FOLDER/dmg-root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT/.background"
ditto "$BUILD_FOLDER/app/Twilight.app" "$DMG_ROOT/Twilight.app" || fail "Could not stage Twilight.app"
"$SOURCE_ROOT/scripts/check-macos-minos.sh" "$DMG_ROOT/Twilight.app" "$MACOS_DEPLOYMENT_TARGET" || fail "Staged Twilight.app has Mach-O files newer than macOS $MACOS_DEPLOYMENT_TARGET or links outside the bundle"
cp "$DMG_BACKGROUND" "$DMG_ROOT/.background/background.png"
cp "$DMG_BACKGROUND_2X" "$DMG_ROOT/.background/background@2x.png"

DMG_PATH="$INSTALLER_FOLDER/Twilight-$VERSION.dmg"
if [ "$SIGNING_IDENTITY" != "" ]; then
  create-dmg \
    --volname "$DMG_VOLNAME" \
    --volicon "$SOURCE_ROOT/app/twilight.icns" \
    --background "$DMG_BACKGROUND" \
    --window-pos "$DMG_WINDOW_X" "$DMG_WINDOW_Y" \
    --window-size "$DMG_WINDOW_W" "$DMG_WINDOW_H" \
    --icon-size "$DMG_ICON_SIZE" \
    --text-size "$DMG_TEXT_SIZE" \
    --icon "Twilight.app" "$DMG_APP_X" "$DMG_APP_Y" \
    --app-drop-link "$DMG_APPLICATIONS_X" "$DMG_APPLICATIONS_Y" \
    --codesign "$SIGNING_IDENTITY" \
    "$DMG_PATH" \
    "$DMG_ROOT" || fail "create-dmg failed!"
else
  create-dmg \
    --volname "$DMG_VOLNAME" \
    --volicon "$SOURCE_ROOT/app/twilight.icns" \
    --background "$DMG_BACKGROUND" \
    --window-pos "$DMG_WINDOW_X" "$DMG_WINDOW_Y" \
    --window-size "$DMG_WINDOW_W" "$DMG_WINDOW_H" \
    --icon-size "$DMG_ICON_SIZE" \
    --text-size "$DMG_TEXT_SIZE" \
    --icon "Twilight.app" "$DMG_APP_X" "$DMG_APP_Y" \
    --app-drop-link "$DMG_APPLICATIONS_X" "$DMG_APPLICATIONS_Y" \
    "$DMG_PATH" \
    "$DMG_ROOT" || fail "create-dmg failed!"
fi

# Developer ID notarization of the DMG. Skip it for TWILIGHT_MAS so a
# sandbox-signed bundle is not sent through the notary service from this script.
# Notarization is not App Store review, and this script never submits for review.
if [ "$NOTARY_KEYCHAIN_PROFILE" != "" ] && [ "${TWILIGHT_MAS:-}" != "1" ]; then
  echo Uploading to App Notary service
  xcrun notarytool submit --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait "$DMG_PATH" || fail "Notary submission failed"

  echo Stapling notary ticket to DMG
  xcrun stapler staple -v "$DMG_PATH" || fail "Notary ticket stapling failed!"
fi

echo Build successful

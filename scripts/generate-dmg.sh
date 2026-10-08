#!/usr/bin/env bash

# Desktop DMGs require the create-dmg shell script:
# https://github.com/create-dmg/create-dmg
# Install it with: brew install create-dmg
# The npm package named create-dmg does not accept a window layout or background.
# TWILIGHT_MAS=1 does not create a DMG. It writes a productbuild .pkg.
#
# Developer ID signing is off unless TWILIGHT_SIGN=1. Notarization is off
# unless TWILIGHT_NOTARIZE=1. The notary keychain profile is twilight-notary
# and the team is TAV97BM6HV. This script does not sign or notarize on its own.
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
APP_BUNDLE="$BUILD_FOLDER/app/Twilight.app"

if [ -n "$CI_VERSION" ]; then
  VERSION=$CI_VERSION
else
  VERSION=`cat $SOURCE_ROOT/app/version.txt`
fi

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
    fail "TWILIGHT_MAS=1 requires PROVISIONING_PROFILE set to a downloaded Mac App Store distribution profile (.provisionprofile) for io.github.neguete10.twilight. This script does not create one."
  fi
fi

if [ "${TWILIGHT_SIGN:-}" = "1" ] && [ "$SIGNING_IDENTITY" == "" ]; then
  fail "TWILIGHT_SIGN=1 requires SIGNING_IDENTITY (Developer ID Application, team TAV97BM6HV)."
fi
if [ "${TWILIGHT_NOTARIZE:-}" = "1" ] && [ "${TWILIGHT_SIGN:-}" != "1" ]; then
  fail "TWILIGHT_NOTARIZE=1 requires TWILIGHT_SIGN=1. Notary profile name is twilight-notary."
fi

if [ "${TWILIGHT_SIGN:-}" = "1" ] || [ "${TWILIGHT_MAS:-}" = "1" ]; then
  git diff-index --quiet HEAD -- || fail "Signed release builds must not have unstaged changes!"
fi

echo Updating dependencies
python3 $SOURCE_ROOT/setup-deps.py || fail "setup-deps.py failed"

echo Cleaning output directories
rm -rf $BUILD_FOLDER
rm -rf $INSTALLER_FOLDER
mkdir $BUILD_ROOT
mkdir $BUILD_FOLDER
mkdir $INSTALLER_FOLDER

# Apple Silicon only. Official Qt 6.11.2 and moonlight-qt-deps v19 (via
# setup-deps.py) are the intended toolchain. Homebrew libraries are not
# copied into the bundle.
# PyroWave is opt-in on Metal and Vulkan. CONFIG+=pyrowave is on unless
# TWILIGHT_PYROWAVE=0. Automatic codec selection never advertises it.
# Vulkan is used only when the PyroWave GPU backend is set to Vulkan.
QMAKE_CONFIG_ARGS=
DEVICE_ARCHS="arm64"
if [ "${TWILIGHT_PYROWAVE:-1}" != "0" ]; then
  QMAKE_CONFIG_ARGS="CONFIG+=pyrowave"
  echo "PyroWave Metal and Vulkan: CONFIG+=pyrowave, arch $DEVICE_ARCHS"
fi
DEVELOPER_ID_ENTITLEMENTS="$SOURCE_ROOT/app/deploy/macos/Twilight-DeveloperID.entitlements"
MAS_ENTITLEMENTS="$SOURCE_ROOT/app/deploy/macos/Twilight-MAS.entitlements"
if [ "${TWILIGHT_MAS:-}" = "1" ]; then
  QMAKE_CONFIG_ARGS="$QMAKE_CONFIG_ARGS CONFIG+=twilight-mas"
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
fi

MACOS_DEPLOYMENT_TARGET=$(sh "$SOURCE_ROOT/scripts/macos-deployment-target.sh") || fail "macOS deployment target is not set"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
echo "macOS deployment target: $MACOS_DEPLOYMENT_TARGET"

# Enable LTO for official builds
export CFLAGS=-flto=thin
export CXXFLAGS=-flto=thin
export LDFLAGS=-flto=thin

echo Configuring the project
pushd $BUILD_FOLDER
qmake $SOURCE_ROOT/moonlight-qt.pro \
  QMAKE_APPLE_DEVICE_ARCHS="$DEVICE_ARCHS" \
  QMAKE_MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
  $QMAKE_CONFIG_ARGS || fail "Qmake failed!"
popd

echo Compiling Twilight in $BUILD_CONFIG configuration
pushd $BUILD_FOLDER
make -j$(sysctl -n hw.logicalcpu) $(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]') || fail "Make failed!"
popd

echo Saving dSYM file
pushd $BUILD_FOLDER
dsymutil "$APP_BUNDLE/Contents/MacOS/Twilight" -o Twilight-$VERSION.dsym || fail "dSYM creation failed!"
cp -R Twilight-$VERSION.dsym $INSTALLER_FOLDER || fail "dSYM copy failed!"
popd

echo Hiding libmimer
if [ -d "$QTDIR" ]; then
  mv "$QTDIR/macos/plugins/sqldrivers/libqsqlmimer.dylib" "$QTDIR/macos/plugins/sqldrivers/libqsqlmimer.dylib.hide"
fi

echo Creating app bundle
EXTRA_ARGS=
if [ "$BUILD_CONFIG" == "Debug" ]; then EXTRA_ARGS="$EXTRA_ARGS -use-debug-libs"; fi
echo Extra deployment arguments: $EXTRA_ARGS
# Sign after deployment so Developer ID gets the empty entitlements plist
# explicitly. App Sandbox entitlements broke launch in 7.0.1.
macdeployqt "$APP_BUNDLE" $EXTRA_ARGS -qmldir=$SOURCE_ROOT/app/gui -no-codesign || fail "macdeployqt failed!"

if [ -d "$QTDIR" ]; then
  mv "$QTDIR/macos/plugins/sqldrivers/libqsqlmimer.dylib.hide" "$QTDIR/macos/plugins/sqldrivers/libqsqlmimer.dylib"
fi

echo Removing unused Qt cruft
for plugin in geometryloaders multimedia sqldrivers; do
  if [ -d "$APP_BUNDLE/Contents/PlugIns/$plugin" ]; then
    rm -rf "$APP_BUNDLE/Contents/PlugIns/$plugin"
    echo "Removed Qt plugin: $plugin"
  fi
done

for framework in Qt3D* QtMultimedia QtShaderTools QtSql QtVirtualKeyboard QtVirtualKeyboardQml QtVirtualKeyboardSettings; do
  if [ -d "$APP_BUNDLE/Contents/Frameworks/$framework.framework" ]; then
    rm -rf "$APP_BUNDLE/Contents/Frameworks/$framework.framework"
    echo "Removed Qt framework: $framework"
  fi
done
rm -rf "$APP_BUNDLE/Contents/Frameworks/Qt3D*"

echo Removing dSYM files from app bundle
find "$APP_BUNDLE/" -name '*.dSYM' | xargs rm -rf

# v19 ships libMoltenVK and libplacebo, not the Vulkan loader or an ICD manifest.
# Without libvulkan.1.dylib and Contents/Resources/vulkan/icd.d/MoltenVK_icd.json,
# SDL opens MoltenVK directly: the decoder reports ready and then decodes nothing.
if [ "${TWILIGHT_PYROWAVE:-1}" != "0" ]; then
  sh "$SOURCE_ROOT/scripts/bundle-macos-vulkan.sh" "$APP_BUNDLE" || fail "Vulkan loader bundling failed"
fi

python3 "$SOURCE_ROOT/scripts/check-macos-minos.py" "$APP_BUNDLE" || fail "A Mach-O in the bundle requires a newer macOS than 13.0"

if [ "${TWILIGHT_MAS:-}" = "1" ]; then
  echo Signing app bundle
  echo "Embedding provisioning profile"
  cp "$PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile" \
    || fail "Could not embed the provisioning profile"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$MAS_ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE" || fail "Signing failed!"
  echo "App signature:"
  codesign -d --entitlements - -vvv "$APP_BUNDLE"
elif [ "${TWILIGHT_SIGN:-}" = "1" ]; then
  echo Signing app bundle
  # Empty dict. Do not substitute the App Sandbox or a restricted entitlement file.
  codesign --force --deep --verify --verbose --options runtime --timestamp \
    --entitlements "$DEVELOPER_ID_ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE" || fail "Signing failed!"
  echo "App signature:"
  codesign -d --entitlements - -vvv "$APP_BUNDLE"
fi

# A store package is a signed installer, not a DMG.
if [ "${TWILIGHT_MAS:-}" = "1" ]; then
  echo "Creating Mac App Store installer package"
  productbuild --component "$APP_BUNDLE" /Applications \
    --sign "$INSTALLER_SIGNING_IDENTITY" \
    "$INSTALLER_FOLDER/Twilight-$VERSION.pkg" || fail "productbuild failed!"
  echo "Mac App Store package: $INSTALLER_FOLDER/Twilight-$VERSION.pkg"
  echo "This script does not upload or submit the package."
  echo Build successful
  exit 0
fi

echo Creating DMG
# create-dmg from https://github.com/create-dmg/create-dmg places
# Twilight.app and an Applications symlink, then tells Finder the window
# size and icon positions. The npm package of the same name cannot.
if ! create-dmg --help 2>&1 | grep -q -- '--app-drop-link'; then
  fail "Desktop DMGs need create-dmg from https://github.com/create-dmg/create-dmg (brew install create-dmg). It accepts --app-drop-link and --background. The npm package named create-dmg does not, and it leaves a bare disk image."
fi

. "$SOURCE_ROOT/app/deploy/macos/dmg/layout.env"
[ -n "$DMG_VOLNAME" ] && [ -n "$DMG_WINDOW_W" ] && [ -n "$DMG_WINDOW_H" ] && [ -n "$DMG_APP_X" ] && [ -n "$DMG_APPLICATIONS_X" ] || fail "app/deploy/macos/dmg/layout.env is incomplete"
DMG_BACKGROUND="$SOURCE_ROOT/app/deploy/macos/dmg/background.png"
DMG_BACKGROUND_2X="$SOURCE_ROOT/app/deploy/macos/dmg/background@2x.png"
[ -f "$DMG_BACKGROUND" ] || fail "Missing $DMG_BACKGROUND. Regenerate with: python3 scripts/make_dmg_background.py"
[ -f "$DMG_BACKGROUND_2X" ] || fail "Missing $DMG_BACKGROUND_2X. Regenerate with: python3 scripts/make_dmg_background.py"
[ -f "$SOURCE_ROOT/app/twilight.icns" ] || fail "Missing $SOURCE_ROOT/app/twilight.icns"

DMG_ROOT="$INSTALLER_FOLDER/dmg-root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT/.background"
ditto "$APP_BUNDLE" "$DMG_ROOT/Twilight.app" || fail "Could not stage Twilight.app"
cp "$DMG_BACKGROUND" "$DMG_ROOT/.background/background.png"
cp "$DMG_BACKGROUND_2X" "$DMG_ROOT/.background/background@2x.png"

DMG_PATH="$INSTALLER_FOLDER/Twilight-$VERSION.dmg"
if [ "${TWILIGHT_SIGN:-}" = "1" ]; then
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

if [ "${TWILIGHT_NOTARIZE:-}" = "1" ]; then
  echo Uploading to App Notary service
  xcrun notarytool submit --keychain-profile "twilight-notary" --team-id TAV97BM6HV --wait "$DMG_PATH" || fail "Notary submission failed"
  echo Stapling notary ticket to DMG
  xcrun stapler staple -v "$DMG_PATH" || fail "Notary ticket stapling failed!"
fi

echo Build successful

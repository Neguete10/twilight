# Desktop DMGs require create-dmg: https://github.com/sindresorhus/create-dmg
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

# Desktop DMG is the default. Signed desktop builds use
# spatial-audio.entitlements. Unsigned builds embed no entitlements.
# TWILIGHT_MAS=1 selects CONFIG+=twilight-mas and writes a productbuild
# .pkg. It does not upload, notarize, or submit a build.
# TWILIGHT_MAS_MULTICAST=1 also selects the multicast entitlement. Leave
# it unset until the provisioning profile contains Apple's grant.
QMAKE_CONFIG_ARGS=
MAS_ENTITLEMENTS="$SOURCE_ROOT/app/deploy/macos/Twilight-MAS.entitlements"
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
fi
echo Configuring the project
pushd $BUILD_FOLDER
qmake $SOURCE_ROOT/moonlight-qt.pro QMAKE_APPLE_DEVICE_ARCHS="x86_64 arm64" $QMAKE_CONFIG_ARGS || fail "Qmake failed!"
popd

echo Compiling Moonlight in $BUILD_CONFIG configuration
pushd $BUILD_FOLDER
make -j$(sysctl -n hw.logicalcpu) $(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]') || fail "Make failed!"
popd

echo Saving dSYM file
pushd $BUILD_FOLDER
dsymutil app/Twilight.app/Contents/MacOS/Moonlight -o Moonlight-$VERSION.dsym || fail "dSYM creation failed!"
cp -R Moonlight-$VERSION.dsym $INSTALLER_FOLDER || fail "dSYM copy failed!"
popd

echo Creating app bundle
EXTRA_ARGS=
if [ "$BUILD_CONFIG" == "Debug" ]; then EXTRA_ARGS="$EXTRA_ARGS -use-debug-libs"; fi
echo Extra deployment arguments: $EXTRA_ARGS
macdeployqt $BUILD_FOLDER/app/Twilight.app $EXTRA_ARGS -qmldir=$SOURCE_ROOT/app/gui -appstore-compliant || fail "macdeployqt failed!"

echo Removing dSYM files from app bundle
find $BUILD_FOLDER/app/Twilight.app/ -name '*.dSYM' | xargs rm -rf

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
    # Preserve the CoreAudio/spatial-audio signing entitlements for desktop builds.
    codesign --force --deep --options runtime --timestamp \
      --entitlements $SOURCE_ROOT/app/deploy/macos/spatial-audio.entitlements \
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
if [ "$SIGNING_IDENTITY" != "" ]; then
  create-dmg $BUILD_FOLDER/app/Twilight.app $INSTALLER_FOLDER --identity="$SIGNING_IDENTITY" || fail "create-dmg failed!"
else
  create-dmg $BUILD_FOLDER/app/Twilight.app $INSTALLER_FOLDER
  case $? in
    0) ;;
    2) ;;
    *) fail "create-dmg failed!";;
  esac
fi

# Developer ID notarization of the DMG. Skip it for TWILIGHT_MAS so a
# sandbox-signed bundle is not sent through the notary service from this script.
# Notarization is not App Store review, and this script never submits for review.
if [ "$NOTARY_KEYCHAIN_PROFILE" != "" ] && [ "${TWILIGHT_MAS:-}" != "1" ]; then
  echo Uploading to App Notary service
  xcrun notarytool submit --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait $INSTALLER_FOLDER/Twilight\ $VERSION.dmg || fail "Notary submission failed"

  echo Stapling notary ticket to DMG
  xcrun stapler staple -v $INSTALLER_FOLDER/Twilight\ $VERSION.dmg || fail "Notary ticket stapling failed!"
fi

mv $INSTALLER_FOLDER/Twilight\ $VERSION.dmg $INSTALLER_FOLDER/Twilight-$VERSION.dmg
echo Build successful

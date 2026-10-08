#!/bin/bash
# Third-party macOS libraries for the desktop DMG, into build/macos-deps.
#
#   scripts/build-macos-deps.sh                 # Qt, v19 prebuilts, Vulkan headers, loader
#   scripts/build-macos-deps.sh qt              # one step (qt prebuilts headers vulkan)
#
# 7.0.1 bundled Homebrew Qt 6.11 and Homebrew libplacebo, libvulkan,
# libshaderc, glib, icu, harfbuzz, ... stamped with the build Mac's OS as
# minos (up to 27.0). dyld refused those libraries on macOS 15.
#
# This tree is Apple Silicon only and the floor is macOS 13 (Ventura), the
# same floor as upstream Moonlight 6.2.0 with Qt 6.11.2.
#
# What is not built from source:
#   libplacebo and MoltenVK come from moonlight-stream/moonlight-qt-deps v19
#   (https://github.com/moonlight-stream/moonlight-qt-deps/releases/tag/v19).
#   libplacebo there is minos 13.0 and links only libSystem and libc++.
#   shaderc and glslang are already inside that dylib. It does not link
#   lcms (PL_HAVE_LCMS is unset). MoltenVK is minos 12.0, which still loads
#   on macOS 13. PyroWave's shared library turns Granite's runtime shader
#   compiler off, so it does not need a separate libshaderc either.
#   The v19 zip has no Vulkan loader and its headers have no
#   VulkanHeadersConfig.cmake. Vulkan-Headers v1.4.363 (the same commit as
#   vulkan-sdk-1.4.363.0) is installed for that CMake package, then the
#   loader is the only library compiled here.
# FFmpeg, SDL2, OpenSSL, and Opus stay on the existing libs/ submodule pin.
# v19 also contains newer sonames of those; switching them is a separate
# change from the macOS 13 packaging fix.
#
# Qt is the official qt.io build (aqtinstall), not Homebrew. The clang_64
# package for 6.11.2 contains qtbase, qtdeclarative, qtsvg, and qttools.
# qtshadertools is the extra module Qt Quick needs. qtimageformats supplies
# the icns/webp/tiff plug-ins Homebrew Qt used to ship. QtPdf is not
# installed: macdeployqt was copying its plug-ins and then loading a second
# QtCore from Homebrew.
#
# Build-only tools (not bundled): git cmake ninja python3 curl unzip.
# generate-dmg.sh sources build/macos-deps/env.sh when it exists.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TARGET=${MACOSX_DEPLOYMENT_TARGET:-$(sh "$ROOT/scripts/macos-deployment-target.sh")}
export MACOSX_DEPLOYMENT_TARGET=$TARGET
ARCH=${TWILIGHT_DEPS_ARCH:-arm64}
DEPS=${TWILIGHT_MACOS_DEPS:-$ROOT/build/macos-deps}
SRC=$DEPS/src
PREFIX=$DEPS/prefix
QT_VERSION=${TWILIGHT_QT_VERSION:-6.11.2}
# PyPI aqtinstall stopped at 3.3.0 (June 2025). Moonlight's 6.11.2 CI job
# uses this later commit, which understands the qt6_6112 repository layout.
AQT_SPEC=${TWILIGHT_AQT_SPEC:-git+https://github.com/miurahr/aqtinstall.git@073e34d7c2ab4ae6961ed7cca690b3abd5ba5a7e}
QT_DEPS_TAG=${TWILIGHT_QT_DEPS_TAG:-v19}
QT_DEPS_SHA256=${TWILIGHT_QT_DEPS_SHA256:-39fab7c95f5d513a6eb3bb19c66f1ae66bbf41dfe4118f82fabe3b46cc502d17}
VULKAN_TAG=${VULKAN_TAG:-vulkan-sdk-1.4.363.0}
# Loader known_good.json pins Vulkan-Headers at v1.4.363. That tag and
# vulkan-sdk-1.4.363.0 are the same commit. v19's include/vulkan tree has
# the headers but not the CMake package the loader's find_package requires.
VULKAN_HEADERS_TAG=${VULKAN_HEADERS_TAG:-v1.4.363}

JOBS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)
mkdir -p "$SRC" "$PREFIX"

# Keep Homebrew's libraries and headers out of every compile and link.
# Homebrew tools (cmake, ninja) may still come from PATH.
export CFLAGS="-arch $ARCH -mmacosx-version-min=$TARGET"
export CXXFLAGS="$CFLAGS"
export OBJCFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mmacosx-version-min=$TARGET -Wl,-headerpad_max_install_names"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH || true
CMAKE_COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" -DCMAKE_OSX_ARCHITECTURES="$ARCH"
  -DCMAKE_FIND_FRAMEWORK=LAST -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local"
  -DCMAKE_INSTALL_NAME_DIR="@rpath" -DCMAKE_SKIP_RPATH=TRUE)

fetch() { # url tag dir
  local url=$1 tag=$2 dir=$SRC/$3
  if [ ! -d "$dir/.git" ]; then
    git clone --depth 1 --branch "$tag" "$url" "$dir"
  else
    echo "reusing $dir"
  fi
}

resolve_qt_dir() {
  local candidate
  for candidate in "$DEPS/qt/$QT_VERSION/macos" "$DEPS/qt/$QT_VERSION/clang_64"; do
    if [ -x "$candidate/bin/qmake" ]; then
      QT_DIR=$candidate
      return 0
    fi
  done
  return 1
}

step_qt() {
  if resolve_qt_dir; then
    echo "Qt $QT_VERSION already at $QT_DIR"
    return
  fi
  python3 -m venv "$DEPS/venv"
  "$DEPS/venv/bin/pip" install -q "$AQT_SPEC"
  # Run inside the deps tree so aqt does not drop aqtinstall.log in the repo.
  (
    cd "$DEPS"
    "$DEPS/venv/bin/aqt" install-qt mac desktop "$QT_VERSION" clang_64 \
      -m qtshadertools qtimageformats -O "$DEPS/qt"
  )
  resolve_qt_dir || {
    echo "qmake not found under $DEPS/qt after installing Qt $QT_VERSION" >&2
    find "$DEPS/qt" -name qmake -maxdepth 5 >&2 || true
    exit 1
  }
}

step_prebuilts() {
  local zip=$SRC/macOS-universal.zip
  local url="https://github.com/moonlight-stream/moonlight-qt-deps/releases/download/${QT_DEPS_TAG}/macOS-universal.zip"
  if [ ! -f "$zip" ] || ! python3 -c 'import hashlib,sys; p,e=sys.argv[1:]
d=hashlib.sha256(open(p,"rb").read()).hexdigest(); sys.exit(0 if d==e else 1)' "$zip" "$QT_DEPS_SHA256"; then
    curl -fsSL -o "$zip.partial" "$url"
    mv "$zip.partial" "$zip"
  fi
  python3 -c 'import hashlib,sys; p,e=sys.argv[1:]
d=hashlib.sha256(open(p,"rb").read()).hexdigest()
print(d)
sys.exit(0 if d==e else 1)' "$zip" "$QT_DEPS_SHA256" >/dev/null \
    || { echo "sha256 mismatch for $url" >&2; exit 1; }
  rm -rf "$SRC/qt-deps"
  unzip -q "$zip" -d "$SRC/qt-deps"
  mkdir -p "$PREFIX/lib" "$PREFIX/include" "$PREFIX/share/vulkan/icd.d"
  rm -rf "$PREFIX/include/libplacebo" "$PREFIX/include/vulkan" "$PREFIX/include/vk_video"
  cp -R "$SRC/qt-deps/include/libplacebo" "$PREFIX/include/libplacebo"
  cp -R "$SRC/qt-deps/include/vulkan" "$PREFIX/include/vulkan"
  cp -R "$SRC/qt-deps/include/vk_video" "$PREFIX/include/vk_video"
  cp -f "$SRC/qt-deps/lib/libplacebo.dylib" "$PREFIX/lib/libplacebo.dylib"
  cp -f "$SRC/qt-deps/lib/libMoltenVK.dylib" "$PREFIX/lib/libMoltenVK.dylib"
  # Relative to Contents/Resources/vulkan/icd.d inside Twilight.app.
  # v19 does not ship an ICD manifest. The loader looks in that directory.
  cat > "$PREFIX/share/vulkan/icd.d/MoltenVK_icd.json" <<JSON
{
    "file_format_version": "1.0.1",
    "ICD": {
        "library_path": "../../../Frameworks/libMoltenVK.dylib",
        "api_version": "1.4.0",
        "is_portability_driver": true
    }
}
JSON
  python3 - <<PY
import sys
sys.path.insert(0, "$ROOT/scripts")
from macos_macho import non_system_deps
for name in ("libplacebo.dylib", "libMoltenVK.dylib"):
    deps = non_system_deps("$PREFIX/lib/" + name)
    if deps:
        sys.stderr.write("%s from moonlight-qt-deps %s is not self-contained: %s\n" % (name, "$QT_DEPS_TAG", ", ".join(deps)))
        sys.stderr.write("Source-build the missing library before packaging. shaderc was only required while libplacebo was built here.\n")
        sys.exit(1)
print("v19 libplacebo and MoltenVK link only system libraries")
PY
}

step_headers() {
  # v19's vulkan/ headers are the 1.4.363 API, but Vulkan-Loader's
  # find_package(VulkanHeaders CONFIG) needs VulkanHeadersConfig.cmake.
  local config="$PREFIX/share/cmake/VulkanHeaders/VulkanHeadersConfig.cmake"
  if [ -f "$config" ] && [ -f "$PREFIX/include/vulkan/vulkan.h" ]; then
    echo "Vulkan-Headers already at $config"
    return
  fi
  fetch https://github.com/KhronosGroup/Vulkan-Headers.git "$VULKAN_HEADERS_TAG" Vulkan-Headers
  cmake -S "$SRC/Vulkan-Headers" -B "$SRC/Vulkan-Headers/build" "${CMAKE_COMMON[@]}" \
    -DVULKAN_HEADERS_ENABLE_MODULE=OFF -DVULKAN_HEADERS_ENABLE_TESTS=OFF
  cmake --build "$SRC/Vulkan-Headers/build" -j "$JOBS" --target install
  [ -f "$config" ] || { echo "VulkanHeadersConfig.cmake was not installed" >&2; exit 1; }
  [ -f "$PREFIX/include/vulkan/vulkan.h" ] || { echo "vulkan.h was not installed" >&2; exit 1; }
}

step_vulkan() {
  # PyroWave and SDL load libvulkan at runtime; v19 does not include it.
  step_headers
  [ -f "$PREFIX/include/vulkan/vulkan.h" ] || {
    echo "Vulkan headers missing. Run: scripts/build-macos-deps.sh headers" >&2
    exit 1
  }
  local real="" candidate
  for candidate in "$PREFIX/lib"/libvulkan.1*.dylib; do
    if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
      real=$candidate
      break
    fi
  done
  if [ -n "$real" ]; then
    echo "Vulkan loader already at $real"
    return
  fi
  fetch https://github.com/KhronosGroup/Vulkan-Loader.git "$VULKAN_TAG" Vulkan-Loader
  cmake -S "$SRC/Vulkan-Loader" -B "$SRC/Vulkan-Loader/build" "${CMAKE_COMMON[@]}" \
    -DVulkanHeaders_DIR="$PREFIX/share/cmake/VulkanHeaders" \
    -DVULKAN_HEADERS_INSTALL_DIR="$PREFIX" -DBUILD_TESTS=OFF -DBUILD_WSI_XCB_SUPPORT=OFF \
    -DBUILD_WSI_XLIB_SUPPORT=OFF -DBUILD_WSI_WAYLAND_SUPPORT=OFF
  cmake --build "$SRC/Vulkan-Loader/build" -j "$JOBS" --target install
  real=""
  for candidate in "$PREFIX/lib"/libvulkan.1*.dylib; do
    if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
      real=$candidate
      break
    fi
  done
  [ -n "$real" ] || { echo "libvulkan was not installed" >&2; exit 1; }
  install_name_tool -id @rpath/libvulkan.1.dylib "$real"
  if [ "$(basename "$real")" != "libvulkan.1.dylib" ]; then
    ln -sfn "$(basename "$real")" "$PREFIX/lib/libvulkan.1.dylib"
  fi
  ln -sfn libvulkan.1.dylib "$PREFIX/lib/libvulkan.dylib"
}

write_env() {
  resolve_qt_dir || { echo "Qt $QT_VERSION is not installed. Run the qt step." >&2; exit 1; }
  cat > "$DEPS/env.sh" <<ENV
# Generated by scripts/build-macos-deps.sh. Sourced by scripts/generate-dmg.sh.
export TWILIGHT_DEPS_PREFIX="$PREFIX"
export TWILIGHT_QT_DIR="$QT_DIR"
export TWILIGHT_DEPS_TARGET="$TARGET"
export PATH="$QT_DIR/bin:\$PATH"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
ENV
  echo "wrote $DEPS/env.sh (Qt $QT_DIR, minos $TARGET)"
}

steps=${*:-qt prebuilts headers vulkan}
for s in $steps; do
  echo "=== $s (minos $TARGET, $ARCH)"
  "step_$s"
done
write_env
if [ -x "$ROOT/scripts/check-macos-minos.sh" ]; then
  # Prefix libraries may still name each other by absolute path until
  # macdeployqt rewrites them. Only the minos half applies here.
  if find "$PREFIX/lib" -name '*.dylib' -type f ! -type l | grep -q .; then
    TWILIGHT_MINOS_ONLY=1 "$ROOT/scripts/check-macos-minos.sh" "$PREFIX/lib" "$TARGET"
  fi
  if resolve_qt_dir; then
    TWILIGHT_MINOS_ONLY=1 "$ROOT/scripts/check-macos-minos.sh" "$QT_DIR/lib" "$TARGET"
  fi
fi

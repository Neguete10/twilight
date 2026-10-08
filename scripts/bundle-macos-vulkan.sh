#!/bin/sh
# Put the Vulkan loader and a MoltenVK ICD manifest into Twilight.app.
#
# moonlight-qt-deps v19 has libMoltenVK and libplacebo, and no libvulkan.
# PyroWave's probe and SDL both need the Khronos loader. The loader reads
# Contents/Resources/vulkan/icd.d and opens MoltenVK from Frameworks.
# Loading libMoltenVK directly skips that manifest: the decoder can report
# ready and then decode zero frames.
#
# The loader is Vulkan-Loader tag vulkan-sdk-1.4.363.0 (libvulkan.1.4.363),
# built for this tree's macOS deployment target. MoltenVK itself stays the
# v19 binary already copied into the bundle.
set -eu

fail() {
    echo "$1" >&2
    exit 1
}

if [ "$(uname -s)" != "Darwin" ]; then
    fail "bundle-macos-vulkan.sh runs on macOS, from scripts/generate-dmg.sh"
fi

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    fail "usage: bundle-macos-vulkan.sh Twilight.app"
fi

APP=$1
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FRAMEWORKS="$APP/Contents/Frameworks"
ICD_DIR="$APP/Contents/Resources/vulkan/icd.d"
deployment_target=$(sh "$ROOT/scripts/macos-deployment-target.sh") || fail "macOS deployment target is not set"

molten=""
for candidate in "$FRAMEWORKS/libMoltenVK.dylib" "$ROOT/libs/mac/lib/libMoltenVK.dylib"; do
    if [ -f "$candidate" ]; then
        molten=$candidate
        break
    fi
done
if [ -z "$molten" ]; then
    fail "libMoltenVK.dylib is not in the bundle or libs/mac/lib. Run python3 setup-deps.py (moonlight-qt-deps v19) before packaging."
fi

PREFIX="$ROOT/build/vulkan-sdk-1.4.363"
LOADER_TAG=vulkan-sdk-1.4.363.0
HEADERS_TAG=v1.4.363
SRC="$PREFIX/src"

find_real_loader() {
    real=""
    for candidate in "$PREFIX/lib"/libvulkan.1*.dylib; do
        if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
            real=$candidate
            break
        fi
    done
    printf '%s\n' "$real"
}

if [ -z "$(find_real_loader)" ]; then
    command -v cmake >/dev/null 2>&1 || fail "cmake is required to build the Vulkan loader"
    command -v git >/dev/null 2>&1 || fail "git is required to fetch the Vulkan loader"
    mkdir -p "$SRC"
    if [ ! -d "$SRC/Vulkan-Headers/.git" ]; then
        git clone --depth 1 --branch "$HEADERS_TAG" https://github.com/KhronosGroup/Vulkan-Headers.git "$SRC/Vulkan-Headers"
    fi
    if [ ! -d "$SRC/Vulkan-Loader/.git" ]; then
        git clone --depth 1 --branch "$LOADER_TAG" https://github.com/KhronosGroup/Vulkan-Loader.git "$SRC/Vulkan-Loader"
    fi
    cmake -S "$SRC/Vulkan-Headers" -B "$SRC/Vulkan-Headers/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DVULKAN_HEADERS_ENABLE_MODULE=OFF \
        -DVULKAN_HEADERS_ENABLE_TESTS=OFF
    cmake --build "$SRC/Vulkan-Headers/build" --target install
    cmake -S "$SRC/Vulkan-Loader" -B "$SRC/Vulkan-Loader/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DVulkanHeaders_DIR="$PREFIX/share/cmake/VulkanHeaders" \
        -DVULKAN_HEADERS_INSTALL_DIR="$PREFIX" \
        -DBUILD_TESTS=OFF \
        -DBUILD_WSI_XCB_SUPPORT=OFF \
        -DBUILD_WSI_XLIB_SUPPORT=OFF \
        -DBUILD_WSI_WAYLAND_SUPPORT=OFF
    cmake --build "$SRC/Vulkan-Loader/build" --target install
fi

real=$(find_real_loader)
[ -n "$real" ] || fail "Vulkan-Loader $LOADER_TAG did not install a libvulkan.1 dylib"

install_name_tool -id @rpath/libvulkan.1.dylib "$real"
if [ "$(basename "$real")" != "libvulkan.1.dylib" ]; then
    ln -sfn "$(basename "$real")" "$PREFIX/lib/libvulkan.1.dylib"
fi
ln -sfn libvulkan.1.dylib "$PREFIX/lib/libvulkan.dylib"

mkdir -p "$FRAMEWORKS" "$ICD_DIR"
if [ ! -f "$FRAMEWORKS/libMoltenVK.dylib" ]; then
    cp -a "$molten" "$FRAMEWORKS/libMoltenVK.dylib"
fi
cp -a "$PREFIX/lib"/libvulkan*.dylib "$FRAMEWORKS/" || fail "Vulkan loader copy failed"
# cp -a keeps the prefix symlinks. Point them at the copy that lives here.
if [ -L "$FRAMEWORKS/libvulkan.1.dylib" ] || [ ! -f "$FRAMEWORKS/libvulkan.1.dylib" ]; then
    rm -f "$FRAMEWORKS/libvulkan.1.dylib"
    ln -s "$(basename "$real")" "$FRAMEWORKS/libvulkan.1.dylib"
fi
rm -f "$FRAMEWORKS/libvulkan.dylib"
ln -s libvulkan.1.dylib "$FRAMEWORKS/libvulkan.dylib"

# Relative to Contents/Resources/vulkan/icd.d.
cat > "$ICD_DIR/MoltenVK_icd.json" <<JSON
{
    "file_format_version": "1.0.1",
    "ICD": {
        "library_path": "../../../Frameworks/libMoltenVK.dylib",
        "api_version": "1.4.0",
        "is_portability_driver": true
    }
}
JSON

add_rpath() {
    lib=$1
    [ -f "$lib" ] || return 0
    [ -L "$lib" ] && return 0
    install_name_tool -add_rpath @loader_path "$lib" 2>/dev/null || true
}

for lib in "$FRAMEWORKS"/libpyrowave-shared*.dylib "$FRAMEWORKS"/libtwilight-pyrowave-vkshim.dylib; do
    add_rpath "$lib"
done

echo "Bundled $(basename "$real") and MoltenVK_icd.json (minos $deployment_target)"

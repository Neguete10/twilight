#!/bin/sh
# Build libpyrowave-shared (pin 263ef100) and the symbol shim.
# The Metal static library exports the same C names with a different ABI.
# The shim is the only binary that links libpyrowave-shared.
# macOS minos matches scripts/macos-deployment-target.sh.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/pyrowave-vulkan"
BUILD="$SRC/build"
SHIM_SRC="$ROOT/app/streaming/video/pyrowave_vulkan_shim.cpp"

fail() {
    echo "$1" >&2
    exit 1
}

if [ "$(uname -s)" != "Darwin" ]; then
    fail "The Vulkan PyroWave library is built on macOS. CONFIG+=pyrowave enables it for arm64 Mac builds."
fi

PIN=263ef100a9f4a6a21fe952944043d6744e09dc9c
if [ ! -d "$SRC/.git" ] && [ ! -f "$SRC/.git" ]; then
    fail "pyrowave-vulkan is not checked out. From the repo root run: git submodule update --init pyrowave-vulkan"
fi
# 263ef100 is the Vulkan C API. It is not on the submodule's default branch
# (that tip is the Metal tree), so a plain clone does not contain it.
head_sha=$(git -C "$SRC" rev-parse HEAD)
if [ "$head_sha" != "$PIN" ]; then
    git -C "$SRC" fetch origin "$PIN" || fail "Could not fetch pyrowave $PIN"
    git -C "$SRC" checkout --detach "$PIN" || fail "Could not check out pyrowave $PIN"
fi
if [ ! -f "$SRC/CMakeLists.txt" ]; then
    fail "pyrowave-vulkan pin $PIN has no CMakeLists.txt"
fi

if [ ! -f "$SRC/Granite/CMakeLists.txt" ]; then
    (cd "$SRC" && sh checkout_granite.sh) || fail "checkout_granite.sh failed"
fi

deployment_target=$(sh "$ROOT/scripts/macos-deployment-target.sh") || fail "macOS deployment target is not set"
export MACOSX_DEPLOYMENT_TARGET="$deployment_target"

cache="$BUILD/CMakeCache.txt"
if [ -f "$cache" ]; then
    cached=$(sed -n 's/^CMAKE_OSX_DEPLOYMENT_TARGET:STRING=//p' "$cache" | head -n 1)
    if [ "$cached" != "$deployment_target" ]; then
        echo "Resetting $BUILD (deployment target ${cached:-unset}, want $deployment_target)"
        rm -rf "$BUILD"
    fi
fi

cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DCMAKE_OSX_ARCHITECTURES=arm64

cmake --build "$BUILD" --target pyrowave-shared

vulkan_inc="$SRC/Granite/third_party/khronos/vulkan-headers/include"
if [ ! -f "$vulkan_inc/vulkan/vulkan.h" ]; then
    fail "Vulkan headers were not checked out under $vulkan_inc"
fi

clang++ -std=c++14 -dynamiclib \
    -arch arm64 \
    -mmacosx-version-min="$deployment_target" \
    -I "$SRC" \
    -I "$vulkan_inc" \
    -L "$BUILD" -lpyrowave-shared \
    -Wl,-rpath,@loader_path \
    -install_name @rpath/libtwilight-pyrowave-vkshim.dylib \
    -o "$BUILD/libtwilight-pyrowave-vkshim.dylib" \
    "$SHIM_SRC"

# Granite dlopens libvulkan from this dylib. @loader_path finds the loader
# once both sit in Twilight.app/Contents/Frameworks.
for lib in "$BUILD"/libpyrowave-shared*.dylib; do
    [ -f "$lib" ] || continue
    [ -L "$lib" ] && continue
    install_name_tool -add_rpath @loader_path "$lib" 2>/dev/null || true
done

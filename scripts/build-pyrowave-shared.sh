#!/bin/sh
# Build libpyrowave-shared from the pyrowave submodule (commit 263ef100).
# On macOS the dylib's minos matches QMAKE_MACOSX_DEPLOYMENT_TARGET.
# The built library is not committed. Run checkout_granite.sh in the
# submodule before this script. See docs/PYROWAVE_MAC.md.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/pyrowave"
BUILD="$ROOT/pyrowave/build"

fail() {
    echo "$1" >&2
    exit 1
}

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    fail "pyrowave is not checked out. From the repo root run: git submodule update --init pyrowave"
fi

if [ "$(uname -s)" = "Darwin" ]; then
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
    # PYROWAVE_SHARED is unused at pin 263ef100; the shared target is built
    # because this directory is the top-level project. Kept so the configure
    # line stays the one docs used before this script existed.
    cmake -S "$SRC" -B "$BUILD" \
        -DPYROWAVE_SHARED=ON \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
else
    cmake -S "$SRC" -B "$BUILD" -DPYROWAVE_SHARED=ON
fi

cmake --build "$BUILD" --target pyrowave-shared

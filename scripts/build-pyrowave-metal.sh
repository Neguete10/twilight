#!/bin/sh
# Build libpyrowave-metal from the pyrowave-metal submodule (API 0.5.0,
# commit 89f7e47) and optionally copy the dylibs into an app bundle.
# The built library is not committed. Invoked from app/app.pro when
# qmake is run with CONFIG+=pyrowave on macOS.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/pyrowave-metal/metal"
BUILD="$ROOT/pyrowave-metal/build"

fail() {
    echo "$1" >&2
    exit 1
}

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    fail "pyrowave-metal is not checked out. From the repo root run: git submodule update --init pyrowave-metal"
fi

build_metal() {
    # Same floor as QMAKE_MACOSX_DEPLOYMENT_TARGET. A stale cmake cache
    # from an SDK-default configure would keep minos at the SDK version.
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
    cmake -S "$SRC" -B "$BUILD" -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
    cmake --build "$BUILD"
}

copy_metal() {
    dest=$1
    mkdir -p "$dest"
    found=0
    for lib in "$BUILD"/libpyrowave-metal*.dylib; do
        if [ -e "$lib" ]; then
            cp -f "$lib" "$dest/"
            found=1
        fi
    done
    if [ "$found" -ne 1 ]; then
        fail "cmake did not produce libpyrowave-metal*.dylib in $BUILD"
    fi
}

case "${1:-}" in
    build)
        build_metal
        ;;
    install)
        if [ $# -ne 2 ]; then
            fail "usage: build-pyrowave-metal.sh install Contents/Frameworks"
        fi
        build_metal
        copy_metal "$2"
        ;;
    *)
        fail "usage: build-pyrowave-metal.sh build | install Contents/Frameworks"
        ;;
esac

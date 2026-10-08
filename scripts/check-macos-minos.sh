#!/bin/bash
# Fail if any Mach-O inside a bundle declares a minimum macOS above the
# allowed floor, keeps an LC_RPATH outside the bundle, or links a library
# that is not inside the bundle.
#
#   scripts/check-macos-minos.sh <Twilight.app|dir> [max-minos]
#
# max-minos defaults to TWILIGHT_MAX_MINOS, then to the deployment target in
# globaldefs.pri. TWILIGHT_MINOS_ONLY=1 skips the rpath and dependency checks
# so a deps prefix can be checked before macdeployqt rewrites install names.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TARGET_DIR=${1:-}
if [ -z "$TARGET_DIR" ] || [ ! -e "$TARGET_DIR" ]; then
    echo "usage: $0 <bundle-or-dir> [max-minos]" >&2
    exit 2
fi
if [ -n "${2:-}" ]; then
    MAX=$2
elif [ -n "${TWILIGHT_MAX_MINOS:-}" ]; then
    MAX=$TWILIGHT_MAX_MINOS
else
    MAX=$(sh "$ROOT/scripts/macos-deployment-target.sh")
fi

exec python3 "$ROOT/scripts/check-macos-minos.py" "$TARGET_DIR" "$MAX"

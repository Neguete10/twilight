#!/bin/sh
# Print the macOS deployment target declared for Twilight's own binaries.
# Fails if globaldefs.pri does not set one, so a cmake or qmake wrapper
# cannot fall through to the SDK version.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PRI="$ROOT/globaldefs.pri"

target=$(sed -n 's/^[[:space:]]*QMAKE_MACOSX_DEPLOYMENT_TARGET[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\)[[:space:]]*$/\1/p' "$PRI")
if [ -z "$target" ]; then
    echo "globaldefs.pri must set QMAKE_MACOSX_DEPLOYMENT_TARGET (for example 13.0). An empty value lets clang stamp the SDK version as minos." >&2
    exit 1
fi

count=$(printf '%s\n' "$target" | wc -l | tr -d ' ')
if [ "$count" != "1" ]; then
    echo "globaldefs.pri must set QMAKE_MACOSX_DEPLOYMENT_TARGET exactly once (found $count)" >&2
    exit 1
fi

printf '%s\n' "$target"

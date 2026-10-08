#!/usr/bin/env python3
"""After macdeployqt: strip outside rpaths and drop plug-ins we do not ship.

macdeployqt copies every Qt plug-in it finds, including Qt PDF, even when
the app does not link QtPdf. Those plug-ins keep an LC_RPATH into Homebrew,
so dyld loads a second QtCore. It also copies PlugIns/sqldrivers when QtSql
is in the deploy set. libqsqlmimer.dylib wants /usr/local/lib/libmimerapi.dylib.
Twilight does not use SQL, so the whole sqldrivers directory is removed
before the orphan scan. Delete any remaining plug-in whose strong dependency
is not in the bundle, and delete rpaths that point at /opt/homebrew,
/usr/local, /Users, or any other absolute path outside the bundle.
Developer ID signing happens after this script.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from macos_macho import orphan_plugins, outside_rpaths


def _run(command: list[str]) -> None:
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.stderr.write(result.stdout)
        raise SystemExit(f"command failed ({result.returncode}): {' '.join(command)}")


def strip_outside_rpaths(bundle: Path) -> int:
    stripped = 0
    # Group by file so each binary is unsigned once.
    by_file: dict[Path, list[str]] = {}
    for path, rpath in outside_rpaths(bundle):
        by_file.setdefault(path, [])
        if rpath not in by_file[path]:
            by_file[path].append(rpath)
    for path, rpaths in by_file.items():
        if shutil.which("install_name_tool") is None:
            raise SystemExit(
                "install_name_tool is required to strip LC_RPATH "
                f"{rpaths[0]} from {path}"
            )
        # macdeployqt may have ad-hoc signed the file. install_name_tool
        # refuses a signed Mach-O. The Developer ID signature is applied later.
        if shutil.which("codesign") is not None:
            subprocess.run(
                ["codesign", "--remove-signature", str(path)],
                check=False,
                capture_output=True,
                text=True,
            )
        for rpath in rpaths:
            print(f"strip rpath {rpath}  {path}")
            _run(["install_name_tool", "-delete_rpath", rpath, str(path)])
            stripped += 1
    return stripped


# macdeployqt deploys these when a Qt module is present. Twilight does not
# load them, and some of them link libraries that exist only on the build Mac.
UNUSED_PLUGIN_DIRS = ("sqldrivers",)


def drop_unused_plugin_dirs(bundle: Path) -> int:
    plugins = bundle / "Contents" / "PlugIns"
    dropped = 0
    for name in UNUSED_PLUGIN_DIRS:
        path = plugins / name
        if not path.exists():
            continue
        print(f"drop unused plugin directory {path}")
        shutil.rmtree(path)
        dropped += 1
    return dropped


def drop_orphan_plugins(bundle: Path) -> int:
    dropped = 0
    for path, missing in orphan_plugins(bundle):
        detail = ", ".join(missing)
        print(f"drop orphan plugin {path}  missing {detail}")
        path.unlink()
        dropped += 1
        parent = path.parent
        while parent != bundle and parent.is_dir():
            try:
                parent.rmdir()
            except OSError:
                break
            parent = parent.parent
    return dropped


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        sys.stderr.write(f"usage: {argv[0]} <Twilight.app>\n")
        return 2
    bundle = Path(argv[1])
    if not bundle.is_dir():
        sys.stderr.write(f"prepare-macos-bundle: not a directory: {bundle}\n")
        return 2
    unused = drop_unused_plugin_dirs(bundle)
    dropped = drop_orphan_plugins(bundle)
    stripped = strip_outside_rpaths(bundle)
    print(
        f"prepare-macos-bundle: removed {unused} unused plugin dir(s), "
        f"dropped {dropped} orphan plugin(s), stripped {stripped} rpath(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

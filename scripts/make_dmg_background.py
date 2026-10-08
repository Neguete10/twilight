#!/usr/bin/env python3
"""Draw the Twilight disk-image window background.

The desktop disk image (scripts/generate-dmg.sh, without TWILIGHT_MAS)
opens on a fixed Finder window: Twilight.app on the left, an Applications
folder alias on the right, and this picture behind them. The arrow sits
in the gap between those two icons. The caption sits below their labels.

Regenerate both files from the repo root:

    python3 scripts/make_dmg_background.py

Pillow is required. The script uses the first font it finds: Inter,
Liberation Sans, DejaVu Sans, or Arial. Commit the PNGs it writes:

    app/deploy/macos/dmg/background.png      (window size, in points)
    app/deploy/macos/dmg/background@2x.png   (twice that, for retina)

Icon positions and the window size live in app/deploy/macos/dmg/layout.env.
generate-dmg.sh reads that same file. Finder loads background@2x.png from
the disk image's .background folder when the window is on a retina display.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
LAYOUT_PATH = ROOT / "app" / "deploy" / "macos" / "dmg" / "layout.env"
OUT_DIR = LAYOUT_PATH.parent

BG = (246, 247, 251)
ARROW = (70, 84, 112)
CAPTION = (55, 64, 84)

FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/macos/Inter-Regular.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/Library/Fonts/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
)


def load_layout(path):
    values = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    required = (
        "DMG_WINDOW_W",
        "DMG_WINDOW_H",
        "DMG_ICON_SIZE",
        "DMG_APP_X",
        "DMG_APP_Y",
        "DMG_APPLICATIONS_X",
        "DMG_APPLICATIONS_Y",
        "DMG_CAPTION",
    )
    missing = [key for key in required if key not in values]
    if missing:
        raise SystemExit("layout.env is missing %s" % ", ".join(missing))
    return values


def find_font():
    for candidate in FONT_CANDIDATES:
        if Path(candidate).is_file():
            return candidate
    raise SystemExit(
        "No font found for the DMG caption. Install Inter, Liberation Sans, "
        "or DejaVu Sans, or run this on a Mac that has Arial."
    )


def draw_background(layout, scale, font_path):
    width = int(layout["DMG_WINDOW_W"]) * scale
    height = int(layout["DMG_WINDOW_H"]) * scale
    icon = int(layout["DMG_ICON_SIZE"]) * scale
    app_x = int(layout["DMG_APP_X"]) * scale
    app_y = int(layout["DMG_APP_Y"]) * scale
    applications_x = int(layout["DMG_APPLICATIONS_X"]) * scale
    image = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(image)

    # create-dmg's icon position is the center of the icon. Keep the arrow
    # in the open gap so it is not covered by Twilight.app or Applications.
    gap_left = app_x + icon // 2 + 18 * scale
    gap_right = applications_x - icon // 2 - 22 * scale
    head = 22 * scale
    shaft_right = gap_right - head
    thickness = 8 * scale
    y = app_y
    draw.rounded_rectangle(
        [gap_left, y - thickness // 2, shaft_right, y + thickness // 2],
        radius=thickness // 2,
        fill=ARROW,
    )
    draw.polygon(
        [
            (shaft_right - 2 * scale, y - head),
            (gap_right, y),
            (shaft_right - 2 * scale, y + head),
        ],
        fill=ARROW,
    )

    font = ImageFont.truetype(font_path, 16 * scale)
    caption_y = int(layout["DMG_WINDOW_H"]) * scale - 52 * scale
    draw.text(
        (width / 2, caption_y),
        layout["DMG_CAPTION"],
        font=font,
        fill=CAPTION,
        anchor="mm",
    )
    return image


def main():
    layout = load_layout(LAYOUT_PATH)
    font_path = find_font()
    one = draw_background(layout, 1, font_path)
    two = draw_background(layout, 2, font_path)
    one_path = OUT_DIR / "background.png"
    two_path = OUT_DIR / "background@2x.png"
    one.save(one_path, format="PNG", optimize=True)
    two.save(two_path, format="PNG", optimize=True)
    print("wrote %s (%dx%d)" % (one_path, one.width, one.height))
    print("wrote %s (%dx%d)" % (two_path, two.width, two.height))
    print("font %s" % font_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())

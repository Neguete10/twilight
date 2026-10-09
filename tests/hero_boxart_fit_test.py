#!/usr/bin/env python3
"""The Desktop hero fits box art. The square tiles stay cropped.

Sunshine's default desktop.png is 600×800. Its monitor is the bright
region, about y=166–499, so it sits above the middle of the file. A
centered cover crop into the hero's 220×148 frame keeps roughly
y=198–602 and cuts the top of that monitor. A 180×180 tile crop keeps
roughly y=100–700, which still contains it.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "app" / "gui" / "ui" / "v2" / "ShellV2.qml"

HERO_W, HERO_H = 220, 148
TILE = 180
# Measured from LizardByte Sunshine src_assets desktop.png (600×800).
SUNSHINE_W, SUNSHINE_H = 600, 800
MONITOR_TOP, MONITOR_BOTTOM = 166, 499

FAILURES = 0


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def contain(src_w, src_h, dst_w, dst_h):
    """PreserveAspectFit, centered. Returns x, y, w, h in the frame."""
    scale = min(dst_w / src_w, dst_h / src_h)
    width = src_w * scale
    height = src_h * scale
    return (dst_w - width) / 2, (dst_h - height) / 2, width, height


def cover_window(src_w, src_h, dst_w, dst_h):
    """Source rows a centered PreserveAspectCrop keeps. Returns y0, y1."""
    scale = max(dst_w / src_w, dst_h / src_h)
    shown = dst_h / scale
    top = (src_h - shown) / 2
    return top, top + shown


def image_block(text, anchor):
    """The Image element whose body contains anchor."""
    for match in re.finditer(r"\n( +)Image \{", text):
        start = match.start() + 1
        indent = len(match.group(1))
        end = text.find("\n" + (" " * indent) + "}", start)
        block = text[start:end]
        if anchor in block:
            return block
    raise AssertionError("no Image block containing %r" % anchor)


def main():
    text = SHELL.read_text()
    hero = image_block(text, "width: 220")
    tile = image_block(text, "source: model.boxart")

    expect("fillMode: Image.PreserveAspectFit" in hero, "hero fits")
    expect("fillMode: Image.PreserveAspectCrop" not in hero, "hero does not crop")
    expect("horizontalAlignment: Image.AlignHCenter" in hero, "hero centered horizontally")
    expect("verticalAlignment: Image.AlignVCenter" in hero, "hero centered vertically")
    expect("fillMode: Image.PreserveAspectCrop" in tile, "tiles stay cropped")
    expect("anchors.fill: parent" in tile, "tile image fills its square")

    x, y, w, h = contain(SUNSHINE_W, SUNSHINE_H, HERO_W, HERO_H)
    expect(abs(h - HERO_H) < 0.01, "default art fills the hero height")
    expect(w < HERO_W, "default art letterboxes on the sides")
    expect(abs(x - (HERO_W - w) / 2) < 0.01 and abs(y) < 0.01, "default art is centered")
    expect(0 <= x and x + w <= HERO_W + 0.01, "fitted width stays inside the frame")
    expect(0 <= y and y + h <= HERO_H + 0.01, "fitted height stays inside the frame")

    crop_top, crop_bottom = cover_window(SUNSHINE_W, SUNSHINE_H, HERO_W, HERO_H)
    expect(crop_top > MONITOR_TOP, "centered hero crop cuts the top of the monitor")
    expect(crop_bottom > MONITOR_BOTTOM, "that crop also keeps empty space under the monitor")

    tile_top, tile_bottom = cover_window(SUNSHINE_W, SUNSHINE_H, TILE, TILE)
    expect(tile_top < MONITOR_TOP and tile_bottom > MONITOR_BOTTOM,
           "the square crop still contains the monitor")

    # A 16:9 host poster width-fills the hero and is centered vertically.
    x, y, w, h = contain(1920, 1080, HERO_W, HERO_H)
    expect(abs(w - HERO_W) < 0.01 and h < HERO_H, "16:9 art fills the hero width")
    expect(abs(y - (HERO_H - h) / 2) < 0.01 and y > 0, "16:9 art is centered vertically")

    # A taller host poster height-fills and is centered horizontally.
    x, y, w, h = contain(600, 900, HERO_W, HERO_H)
    expect(abs(h - HERO_H) < 0.01 and w < HERO_W, "600×900 art fills the hero height")
    expect(abs(x - (HERO_W - w) / 2) < 0.01 and x > 0, "600×900 art is centered horizontally")

    # Art already at the hero's aspect fills the frame.
    x, y, w, h = contain(HERO_W * 4, HERO_H * 4, HERO_W, HERO_H)
    expect(abs(w - HERO_W) < 0.01 and abs(h - HERO_H) < 0.01, "matching aspect fills the frame")
    expect(abs(x) < 0.01 and abs(y) < 0.01, "matching aspect has no letterbox")

    if FAILURES:
        print("%d failed" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

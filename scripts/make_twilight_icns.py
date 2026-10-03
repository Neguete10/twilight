#!/usr/bin/env python3
"""Draw the Twilight dock icon and pack it as app/twilight.icns.

The V2 shell mark is the moon.stars symbol (accent #9EBEFF on the dark
shell). There is no bitmap in qrc, so this recreates that mark: a crescent
cut the same way as twilightDrawFallbackSymbol(), plus two stars.
"""

import io
import math
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app" / "twilight.icns"

ACCENT = (158, 190, 255, 255)
STAR = (214, 228, 255, 255)
BG = (14, 16, 22, 255)


def star_polygon(cx, cy, outer, inner):
    points = []
    for i in range(10):
        ang = -3.14159265 / 2.0 + i * 3.14159265 / 5.0
        mag = outer if i % 2 == 0 else inner
        points.append((cx + math.cos(ang) * mag, cy + math.sin(ang) * mag))
    return points


def draw_icon(size):
    image = Image.new("RGBA", (size, size), BG)
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    # Soft accent wash behind the mark, inside the squircle the OS will mask.
    wash = size * 0.34
    draw.ellipse(
        [size / 2 - wash, size / 2 - wash, size / 2 + wash, size / 2 + wash],
        fill=(158, 190, 255, 36),
    )
    image.alpha_composite(overlay)

    cx = size * 0.44
    cy = size * 0.54
    radius = size * 0.24
    body = Image.new("L", (size, size), 0)
    ImageDraw.Draw(body).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], fill=255
    )
    cut = Image.new("L", (size, size), 0)
    shift_x = radius * 0.42
    shift_y = -radius * 0.08
    ImageDraw.Draw(cut).ellipse(
        [
            cx - radius + shift_x,
            cy - radius + shift_y,
            cx + radius + shift_x,
            cy + radius + shift_y,
        ],
        fill=255,
    )
    crescent = ImageChops.subtract(body, cut)
    moon = Image.new("RGBA", (size, size), ACCENT)
    moon.putalpha(crescent)
    image.alpha_composite(moon)

    marks = ImageDraw.Draw(image)
    dot = size * 0.045
    marks.ellipse(
        [
            size * 0.70 - dot,
            size * 0.30 - dot,
            size * 0.70 + dot,
            size * 0.30 + dot,
        ],
        fill=ACCENT,
    )
    marks.polygon(
        star_polygon(size * 0.74, size * 0.38, size * 0.055, size * 0.022),
        fill=STAR,
    )
    marks.polygon(
        star_polygon(size * 0.62, size * 0.24, size * 0.032, size * 0.013),
        fill=ACCENT,
    )
    return image


def png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def icns_entry(tag, image):
    payload = png_bytes(image)
    return tag + struct.pack(">I", 8 + len(payload)) + payload


def main():
    master = draw_icon(1024)
    # Apple icon types that store a PNG. @2x types reuse a larger bitmap.
    specs = [
        (b"icp4", 16),
        (b"icp5", 32),
        (b"ic11", 32),
        (b"icp6", 64),
        (b"ic12", 64),
        (b"ic07", 128),
        (b"ic08", 256),
        (b"ic13", 256),
        (b"ic09", 512),
        (b"ic14", 512),
        (b"ic10", 1024),
    ]
    body = b""
    for tag, side in specs:
        bitmap = master if side == 1024 else master.resize((side, side), Image.Resampling.LANCZOS)
        body += icns_entry(tag, bitmap)
    blob = b"icns" + struct.pack(">I", 8 + len(body)) + body
    OUT.write_bytes(blob)
    print(f"wrote {OUT} ({len(blob)} bytes)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Draw the Twilight dock icon on Apple's macOS icon grid and pack app/twilight.icns.

macOS does not mask AppKit icons. A full-bleed square is taller than the
rounded tiles beside it, so the mark reads high in the Dock. The plate is the
measured system-icon grid: an 824px rounded rect centered on a 1024 canvas
(100px margin, 185.4px corner radius), with the same shadow those icons bake
in. The moon and stars are recentered on that plate at every icns size.
"""

import io
import math
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app" / "twilight.icns"

ACCENT = (158, 190, 255, 255)
STAR = (214, 228, 255, 255)
BG = (14, 16, 22, 255)

# Apple's macOS app-icon grid, in 1024-canvas units. The 824 plate is what
# Calculator, Mail, Notes, and the rest actually occupy; the radius is
# 185.4 / 824. The shadow is the shallow one those icons bake in, because
# the Dock draws the file as-is and a tile with no shadow sits flat.
GRID = 1024
ART = 824
RADIUS = 185.4
SHADOW_ALPHA = 0.26
SHADOW_BLUR = 16.0
SHADOW_DY = 6.0

# Modern icns types that store a PNG. @2x entries share the larger bitmap.
SPECS = [
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


def star_polygon(cx, cy, outer, inner):
    points = []
    for i in range(10):
        ang = -math.pi / 2.0 + i * math.pi / 5.0
        mag = outer if i % 2 == 0 else inner
        points.append((cx + math.cos(ang) * mag, cy + math.sin(ang) * mag))
    return points


def draw_mark(size):
    """Moon and stars on a transparent square, fractions of `size`.

    The crescent matches the old full-bleed drawing. Callers center the
    opaque pixels; this function does not place them on the canvas.
    """
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
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


def opaque_bbox(image, minimum_alpha):
    pixels = image.load()
    width, height = image.size
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] >= minimum_alpha:
                if x < min_x:
                    min_x = x
                if y < min_y:
                    min_y = y
                if x > max_x:
                    max_x = x
                if y > max_y:
                    max_y = y
    if max_x < 0:
        return None
    return (min_x, min_y, max_x, max_y)


def recenter_mark(mark):
    """Move the opaque moon and stars so their box is centered. The wash is faint and moves with them."""
    bbox = opaque_bbox(mark, 200)
    if bbox is None:
        return mark
    cx = (bbox[0] + bbox[2]) / 2.0
    cy = (bbox[1] + bbox[3]) / 2.0
    dx = int(round(mark.size[0] / 2.0 - cx))
    dy = int(round(mark.size[1] / 2.0 - cy))
    if dx == 0 and dy == 0:
        return mark
    shifted = Image.new("RGBA", mark.size, (0, 0, 0, 0))
    shifted.paste(mark, (dx, dy))
    return shifted


def working_scale(canvas):
    """Supersample until the plate and its margin land on whole pixels."""
    scale = 1
    while True:
        work = canvas * scale
        art = ART * work / GRID
        inset = (work - art) / 2.0
        if art.is_integer() and inset.is_integer() and work >= 256:
            return scale, work, int(art), int(inset)
        scale *= 2


def plate_mask(work, art, inset, radius):
    sample = 4
    big = Image.new("L", (work * sample, work * sample), 0)
    draw = ImageDraw.Draw(big)
    left = inset * sample
    top = inset * sample
    right = left + art * sample - 1
    bottom = top + art * sample - 1
    draw.rounded_rectangle([left, top, right, bottom], radius=radius * sample, fill=255)
    return big.resize((work, work), Image.Resampling.BOX)


def shift_down(mask, dy):
    if dy <= 0:
        return mask
    shifted = Image.new("L", mask.size, 0)
    if dy < mask.size[1]:
        shifted.paste(mask.crop((0, 0, mask.size[0], mask.size[1] - dy)), (0, dy))
    return shifted


def render_icon(canvas):
    scale, work, art, inset = working_scale(canvas)
    radius = RADIUS * art / ART
    mask = plate_mask(work, art, inset, radius)

    blur = max(0.3, SHADOW_BLUR * work / GRID)
    shadow_alpha = mask.filter(ImageFilter.GaussianBlur(blur))
    shadow_alpha = shadow_alpha.point(lambda value: int(value * SHADOW_ALPHA))
    shadow_alpha = shift_down(shadow_alpha, int(round(SHADOW_DY * work / GRID)))
    shadow = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    shadow.putalpha(shadow_alpha)

    plate = Image.new("RGBA", (work, work), BG)
    plate.putalpha(mask)

    mark = recenter_mark(draw_mark(art))
    layer = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    layer.paste(mark, (inset, inset))
    red, green, blue, alpha = layer.split()
    layer = Image.merge("RGBA", (red, green, blue, ImageChops.multiply(alpha, mask)))

    image = Image.alpha_composite(shadow, plate)
    image = Image.alpha_composite(image, layer)
    if scale != 1:
        image = image.resize((canvas, canvas), Image.Resampling.LANCZOS)
    return image


def png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def icns_entry(tag, image):
    payload = png_bytes(image)
    return tag + struct.pack(">I", 8 + len(payload)) + payload


def pack_icns():
    cache = {}
    body = b""
    for tag, side in SPECS:
        if side not in cache:
            cache[side] = render_icon(side)
        body += icns_entry(tag, cache[side])
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def main():
    blob = pack_icns()
    OUT.write_bytes(blob)
    print(f"wrote {OUT} ({len(blob)} bytes)")


if __name__ == "__main__":
    main()

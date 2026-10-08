#!/usr/bin/env python3
"""The packed Twilight icon sits on Apple's macOS icon grid at every size."""

import importlib.util
import io
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "make_twilight_icns", ROOT / "scripts" / "make_twilight_icns.py"
)
icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icon)

FAILURES = 0


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def bbox(image, predicate):
    pixels = image.load()
    width, height = image.size
    min_x, min_y, max_x, max_y = width, height, -1, -1
    count = 0
    for y in range(height):
        for x in range(width):
            if predicate(pixels[x, y]):
                count += 1
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if count == 0:
        return None
    return (min_x, min_y, max_x, max_y, count)


def center(box):
    return ((box[0] + box[2]) / 2.0, (box[1] + box[3]) / 2.0)


def near(value, target, slack, label):
    expect(abs(value - target) <= slack, f"{label}: {value:.2f} vs {target:.2f}")


def is_plate(pixel):
    red, green, blue, alpha = pixel
    if alpha < 180:
        return False
    return abs(red - 14) < 18 and abs(green - 16) < 18 and abs(blue - 22) < 18


def is_mark(pixel):
    red, green, blue, alpha = pixel
    if alpha < 140:
        return False
    distance = ((red - 14) ** 2 + (green - 16) ** 2 + (blue - 22) ** 2) ** 0.5
    return distance >= 50


def check_image(image, canvas, label):
    expect(image.size == (canvas, canvas), f"{label} size")
    corner = image.getpixel((0, 0))
    expect(corner[3] < 16, f"{label} corner is outside the plate")
    plate = bbox(image, is_plate)
    mark = bbox(image, is_mark)
    expect(plate is not None, f"{label} has a plate")
    expect(mark is not None, f"{label} has a mark")
    if plate is None or mark is None:
        return
    plate_center = center(plate)
    mark_center = center(mark)
    near(plate_center[0], (canvas - 1) / 2.0, 1.25, f"{label} plate x")
    near(plate_center[1], (canvas - 1) / 2.0, 1.25, f"{label} plate y")
    near(mark_center[0], (canvas - 1) / 2.0, 1.25, f"{label} mark x")
    near(mark_center[1], (canvas - 1) / 2.0, 1.25, f"{label} mark y")
    # Inclusive pixel bounds, so a centered 824px plate on 1024 spans 100..923.
    expected = icon.ART * canvas / icon.GRID
    width = plate[2] - plate[0] + 1
    height = plate[3] - plate[1] + 1
    near(width, expected, 2.0, f"{label} plate width")
    near(height, expected, 2.0, f"{label} plate height")
    expect(mark[1] >= plate[1] and mark[3] <= plate[3], f"{label} mark stays inside the plate")


def load_icns(path):
    data = path.read_bytes()
    expect(data[:4] == b"icns", "icns magic")
    images = {}
    offset = 8
    while offset + 8 <= len(data):
        tag = data[offset:offset + 4]
        size = struct.unpack(">I", data[offset + 4:offset + 8])[0]
        payload = data[offset + 8:offset + size]
        if payload[:8] == b"\x89PNG\r\n\x1a\n":
            images[tag] = Image.open(io.BytesIO(payload)).convert("RGBA")
        offset += size
    return images


def main():
    seen = {}
    for _tag, side in icon.SPECS:
        if side not in seen:
            seen[side] = icon.render_icon(side)
        check_image(seen[side], side, f"render {side}")

    packed = load_icns(icon.OUT)
    expect(len(packed) == len(icon.SPECS), "every icns entry is present")
    for tag, side in icon.SPECS:
        image = packed.get(tag)
        expect(image is not None, f"{tag.decode()} present")
        if image is None:
            continue
        check_image(image, side, f"icns {tag.decode()} {side}")
        expect(image.tobytes() == seen[side].tobytes(), f"{tag.decode()} matches the generator")

    if FAILURES:
        print(f"{FAILURES} failed")
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Writes assets/palette.png (and a labelled preview, docs/art/palette_preview.png) from palette.py."""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def main():
    img = Image.new("RGB", (P.WIDTH, P.HEIGHT))
    draw = ImageDraw.Draw(img)
    for name, (c, r) in P.INDEX.items():
        rgb = tuple(round(v * 255) for v in P.COLORS[name])
        draw.rectangle([c * P.SWATCH, r * P.SWATCH, (c + 1) * P.SWATCH - 1, (r + 1) * P.SWATCH - 1], fill=rgb)
    out = os.path.join(ROOT, "assets", "palette.png")
    img.save(out)
    # A big labelled copy for humans.
    cell = 110
    prev = Image.new("RGB", (P.COLS * cell, P.ROW_COUNT * cell), (30, 30, 30))
    d = ImageDraw.Draw(prev)
    for name, (c, r) in P.INDEX.items():
        rgb = tuple(round(v * 255) for v in P.COLORS[name])
        x, y = c * cell, r * cell
        d.rectangle([x + 4, y + 4, x + cell - 5, y + cell - 26], fill=rgb)
        d.text((x + 6, y + cell - 22), name, fill=(235, 235, 235))
    os.makedirs(os.path.join(ROOT, "docs", "art"), exist_ok=True)
    prev.save(os.path.join(ROOT, "docs", "art", "palette_preview.png"))
    print("wrote", out, "(%dx%d, %d colours)" % (P.WIDTH, P.HEIGHT, len(P.COLORS)))


if __name__ == "__main__":
    main()

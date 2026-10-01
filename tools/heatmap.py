#!/usr/bin/env python3
"""Draws playtest position samples over the plant layout plan (M5 playtest instrumentation).

The server writes user://heatmap_<date-time>.csv during every match (server/heatmap_recorder.gd):
one row per player every 2 s with t, peer, name, role, x, y, z, area. On Linux, user:// of a
debug run is ~/.local/share/godot/app_userdata/HomerSim/ (the server log prints the full path).

Usage:
  python3 tools/heatmap.py FILE.csv [MORE.csv ...] [--role rat|supervisor] [--out heatmap.png]

Rats are drawn in green, supervisors in yellow (or just one role with --role). Brighter = more
time spent there. Samples above 3 m (catwalks, vent roof) are drawn with a white outline. The
script also prints the time each role spent per area. Needs Pillow and NumPy
(pip install pillow numpy).
"""
import argparse
import csv
import json
import os
import sys
from collections import defaultdict

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit("heatmap.py needs Pillow and NumPy: pip install pillow numpy")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PLAN = os.path.join(ROOT, "docs", "map", "plant_layout_v1.json")
COLORS = {"rat": (90, 255, 120), "supervisor": (255, 215, 60)}
SAMPLE_S = 2.0  # the recorder's interval


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("csv", nargs="+", help="heatmap CSV file(s) from the server")
    parser.add_argument("--role", choices=sorted(COLORS), help="only this role")
    parser.add_argument("--out", default="heatmap.png", help="output image (default: heatmap.png)")
    args = parser.parse_args()

    with open(PLAN) as f:
        plan = json.load(f)
    base = Image.open(os.path.join(os.path.dirname(PLAN), plan["image"])).convert("RGB")
    px = plan["px_per_m"]
    x0, z0 = plan["world_min"]
    x1, z1 = plan["world_max"]
    width, height = int((x1 - x0) * px), int((z1 - z0) * px)

    rows = []
    for path in args.csv:
        with open(path, newline="") as f:
            rows += [r for r in csv.DictReader(f) if r["role"] in COLORS and (not args.role or r["role"] == args.role)]
    if not rows:
        sys.exit("no samples for that role in %s" % ", ".join(args.csv))

    # One density layer per role: a dot per sample, blurred, then normalised.
    out = base.copy()
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    for role, color in COLORS.items():
        samples = [r for r in rows if r["role"] == role]
        if not samples:
            continue
        density = np.zeros((height, width), dtype=np.float32)
        for r in samples:
            u, v = int((float(r["x"]) - x0) * px), int((float(r["z"]) - z0) * px)
            if 0 <= u < width and 0 <= v < height:
                density[v, u] += 1.0
        img = Image.fromarray(np.uint8(np.clip(density * 255.0, 0, 255)), "L")
        img = img.filter(ImageFilter.GaussianBlur(radius=px * 1.5))
        arr = np.asarray(img, dtype=np.float32)
        if arr.max() > 0:
            arr = np.sqrt(arr / arr.max())  # square root: rarely visited places stay visible
        alpha = Image.fromarray(np.uint8(arr * 200), "L")
        layer = Image.new("RGBA", (width, height), color + (0,))
        layer.putalpha(alpha)
        canvas = Image.new("RGBA", base.size, (0, 0, 0, 0))
        canvas.paste(layer, (0, 0))
        overlay = Image.alpha_composite(overlay, canvas)
    out = Image.alpha_composite(out.convert("RGBA"), overlay)
    draw = ImageDraw.Draw(out)
    for r in rows:
        if float(r["y"]) > 3.0:
            u, v = (float(r["x"]) - x0) * px, (float(r["z"]) - z0) * px
            draw.ellipse([u - 3, v - 3, u + 3, v + 3], outline=(255, 255, 255))
    out.convert("RGB").save(args.out)
    print("wrote %s (%d samples)" % (args.out, len(rows)))

    # Time per area and role.
    seconds = defaultdict(float)
    for r in rows:
        seconds[(r["role"], r["area"] or "outside")] += SAMPLE_S
    for role in sorted({k[0] for k in seconds}):
        total = sum(v for k, v in seconds.items() if k[0] == role)
        print("\n%s (%d s sampled):" % (role, total))
        for (rl, area), s in sorted(seconds.items(), key=lambda kv: -kv[1]):
            if rl == role:
                print("  %-16s %5.0f s  %4.0f%%" % (area, s, 100.0 * s / total))


if __name__ == "__main__":
    main()

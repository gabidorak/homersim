"""Wooden crate with corner battens (a 1 m cube by default; the level scales it to its box).

    blender -b -P tools/blender/crate.py -- [--size X Y Z] [--color wood] [--out PATH]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

ASSETS = [("crate", {})]


def build(size=(1.0, 1.0, 1.0), color="wood", trim="brown", name="Crate"):
    sx, sy, sz = size
    b = C.Builder(name)
    b.box((sx - 0.08, sy - 0.08, sz - 0.08), (0, 0, 0.04), color, base=True, bevel=0.02)
    t = 0.09  # batten thickness
    # Vertical battens on the corners, horizontal ones top and bottom.
    for x in (-1, 1):
        for y in (-1, 1):
            b.box((t, t, sz), (x * (sx / 2 - t / 2), y * (sy / 2 - t / 2), 0), trim, base=True, bevel=0.012)
    for z in (t / 2, sz - t / 2):
        for y in (-1, 1):
            b.box((sx - 2 * t, t, t), (0, y * (sy / 2 - t / 2), z), trim, bevel=0.012)
        for x in (-1, 1):
            b.box((t, sy - 2 * t, t), (x * (sx / 2 - t / 2), 0, z), trim, bevel=0.012)
    # A diagonal brace on the two big faces.
    d = math.degrees(math.atan2(sz - 2 * t, sx - 2 * t))
    length = math.hypot(sx - 2 * t, sz - 2 * t)
    for y in (-1, 1):
        b.box((length, t * 0.8, t * 0.8), (0, y * (sy / 2 - t * 0.4), sz / 2), trim, rot=(0, -d * y, 0), bevel=0.01)
    return b.finish()


if __name__ == "__main__":
    a = C.args("crate", lambda p: (p.add_argument("--size", type=float, nargs=3, default=[1.0, 1.0, 1.0]),
                                   p.add_argument("--color", default="wood")))
    C.reset()
    obj = build(tuple(a.size), a.color)
    C.export(a.out, [obj])

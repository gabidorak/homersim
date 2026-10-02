"""The supervisor's broom (third person): a chunky push-broom / witch-broom hybrid.

    blender -b -P tools/blender/broom.py -- [--handle 1.2] [--out PATH]

Origin = the GRIP (where the right hand holds it), `grip` m below the top end of the handle. The
handle runs along +Z (top end up), the bristles are at the bottom (-Z). Attach it to the
supervisor's right hand with a BoneAttachment3D. fp_arms.py reuses build() for the first-person broom.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

ASSETS = [("broom", {})]


def build(handle=1.2, grip=0.35, radius=0.025, name="Broom", parent=None):
    """handle: length of the wooden stick (m); the bristle head hangs below its bottom end."""
    b = C.Builder(name)
    top, bottom = grip, grip - handle
    b.cylinder(radius, handle, (0, 0, bottom), "wood", segments=8, base=True)
    # A red knob on the top end and a wooden collar where the stick enters the bristles.
    b.cylinder(radius * 1.5, 0.05, (0, 0, top - 0.01), "alarm_red", segments=8, base=True, bevel=0.01)
    b.cylinder(radius * 1.7, 0.07, (0, 0, bottom - 0.02), "brown", segments=8, base=True, bevel=0.008)
    # The bristle bundle: a flared, flattened trapezoid (wide like a push broom, tapered like a
    # witch broom), drawn in XZ and extruded along Y.
    h, w_top, w_bot, d = 0.36, 0.08, 0.19, 0.12
    z0 = bottom - 0.02  # top of the bundle (hidden inside the collar)
    pts = [(-w_bot, -h), (w_bot, -h), (w_top, 0.0), (-w_top, 0.0)]
    b.prism(pts, d, (0, d / 2, z0), "safety_yellow", rot=(90, 0, 0), bevel=0.02)
    # Darker strands down the faces so the bundle reads as bristles.
    for i, fx in enumerate((-0.55, 0.0, 0.55)):
        length = h * (0.58 + 0.14 * (i % 2))
        zc = z0 - h + 0.01 + length / 2  # strands hang from near the band to the tips
        width = w_top + (w_bot - w_top) * (z0 - zc) / h
        for y in (-1, 1):
            b.box((0.026, 0.012, length), (fx * width, y * (d / 2 + 0.002), zc), "yellow_dark")
    # The red band tying the bundle near its top.
    zb = z0 - 0.07
    wb = w_top + (w_bot - w_top) * (0.07 / h)
    b.box((2 * wb + 0.03, d + 0.03, 0.06), (0, 0, zb), "tie_red", bevel=0.012)
    return b.finish(parent=parent)


if __name__ == "__main__":
    a = C.args("broom", lambda p: p.add_argument("--handle", type=float, default=1.2))
    C.reset()
    obj = build(handle=a.handle)
    C.export(a.out, [obj])

"""A supervisor skin: the Soviet general. The same Kenney body, rig, clips and size as supervisor.py
(it reuses its import, scale and clips), dressed as a cartoon general: olive tunic over a khaki shirt,
gold shoulder boards and cuffs, a chest full of medals, a leather belt, dark blue breeches with the
generals' double red stripes, black jackboots, a huge peaked cap, bushy grey eyebrows and a walrus
moustache.

    blender -b -P tools/blender/supervisor_general.py -- [--out PATH]

Not in the game yet: preview it with tests/helpers/SkinPreview.tscn (open it in the editor).
Meshes, like the supervisor's: "Supervisor" (body + head, skinned) and "HardHat" (the cap, rigid on
the head bone; it keeps the hard hat's name so the game's code finds it).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import machines as M  # noqa: E402
import rat as R  # noqa: E402  (rig helpers)
import supervisor as S  # noqa: E402

ASSETS = [("supervisor_general", {})]
ANIMATED = True

GOLD, GOLD_LIGHT = "yellow_dark", "safety_yellow"
RIBBONS = [  # the ribbon bars on his left breast, top row first: (colour, stripe)
    [("alarm_red", "safety_yellow"), ("blue", "white"), ("rat_green", "alarm_red")],
    [("orange", "black"), ("sky", "alarm_red"), ("white", "blue")],
    [("safety_yellow", "red_dark"), ("purple", "white"), ("alarm_red", "rat_green")],
]


# --- Recolouring (on top of the supervisor's rules) -------------------------------------------------------

def body_rule(rgb, c):
    name = S.body_rule(rgb, c)
    if name in ("off_white", "silver"):  # the shirt under the jacket, and the cuffs
        return GOLD if abs(c.x) > 0.2 else "khaki"
    return {"shirt_white": "olive", "tie_red": "olive_dark", "alarm_red": "olive_dark",
            "boot_brown": "black"}.get(name, name)


def head_rule(rgb, c):
    name = S.head_rule(rgb, c)
    return "grey_light" if name == "brown" else name  # grey hair


# --- Measuring Kenney's body (unscaled units, model facing -Y, +X = his left) -----------------------------

def extent(obj, group, axis, lo, hi):
    """Bounds ((min x, y, z), (max x, y, z)) of the vertices of `group` whose coordinate on `axis` is
    within [lo, hi]."""
    gi = obj.vertex_groups[group].index
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices
           if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    pts = [p for p in pts if lo <= p[axis] <= hi]
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


def star(radius, inner=0.42):
    """A five-pointed star's outline (x, y), point up, counter-clockwise."""
    return [((radius if i % 2 == 0 else radius * inner) * math.cos(math.pi / 2 + i * math.pi / 5),
             (radius if i % 2 == 0 else radius * inner) * math.sin(math.pi / 2 + i * math.pi / 5)) for i in range(10)]


# --- The cap ----------------------------------------------------------------------------------------------

def peaked_cap(head_top):
    """The generals' peaked cap, exaggerated: a red band round the head, a wide olive crown rising at
    the front (with red piping round its edge), a black visor, a gold chin cord and a gold cockade
    with a red star."""
    b = C.Builder("HardHat")
    zb = head_top - 0.12  # the band's bottom edge, just above the eyebrows
    band, edge, cy = 0.25, 0.3, 0.002  # radii; the head bone's y
    seg = 20
    loc = (0, cy, 0)
    M.lathe(b, [(band, zb), (band, zb + 0.07)], "tie_red", seg=seg, loc=loc)
    before = set(b.bm.verts)
    M.lathe(b, [(band, zb + 0.07), (0.272, zb + 0.11), (0.29, zb + 0.14), (edge - 0.004, zb + 0.158)], "olive",
            seg=seg, loc=loc)
    M.lathe(b, [(edge - 0.004, zb + 0.158), (edge + 0.006, zb + 0.168), (edge - 0.004, zb + 0.18)], "tie_red",
            seg=seg, loc=loc)
    M.lathe(b, [(edge - 0.004, zb + 0.18), (0.26, zb + 0.196), (0.15, zb + 0.207), (0.0, zb + 0.21)], "olive",
            seg=seg, loc=loc)
    # The crown: oval, and rising towards the front (the more, the higher up).
    for v in b.bm.verts:
        if v in before:
            t = min(1.0, max(0.0, (v.co.z - zb - 0.07) / 0.14))
            front = min(1.0, max(0.0, -(v.co.y - cy) / edge))
            v.co.y = cy + (v.co.y - cy) * (1.0 + 0.06 * t)
            v.co.z += 0.11 * t * front ** 1.2
    # The visor: a crescent hinged on the band's front edge, tipped down a little.
    out_pts, in_pts = [], []
    for i in range(13):
        a = math.radians(205 + 130 * i / 12)
        r = band - 0.006 + 0.1 * math.sin(math.pi * i / 12) ** 0.7
        out_pts.append((r * math.cos(a), r * math.sin(a) + band))
        in_pts.append((0.21 * math.cos(a), 0.21 * math.sin(a) + band))
    b.prism(out_pts + in_pts[::-1], 0.016, loc=(0, cy - band, zb + 0.002), color="black", rot=(10, 0, 0))
    # Chin cord: two gold strands across the band's front, a button at each end.
    for dz in (0.014, 0.028):
        path = [((band + 0.008) * math.cos(math.radians(a)), cy + (band + 0.008) * math.sin(math.radians(a)), zb + dz)
                for a in range(222, 320, 8)]
        b.tube(path, 0.0065, GOLD, segments=5)
    for side in (-1, 1):
        a = math.radians(270 + side * 50)
        b.sphere(0.014, ((band + 0.006) * math.cos(a), cy + (band + 0.006) * math.sin(a), zb + 0.021), GOLD,
                 segments=8, rings=5)
    # Cockade: a gold oval with a red star, in a gold wreath of leaves.
    zc = zb + 0.042
    b.sphere(0.036, (0, cy - band - 0.004, zc), GOLD, scale=(1.0, 0.3, 0.95), segments=10, rings=5)
    b.prism(star(0.027), 0.01, loc=(0, cy - band - 0.012, zc), color="alarm_red", rot=(90, 0, 0))
    for side in (-1, 1):
        for k in range(5):
            a = math.radians(-80 + 34 * k)  # from under the cockade up its side
            x, z = side * 0.056 * math.cos(a), zc + 0.05 * math.sin(a)
            y = cy - math.sqrt(max(0.0, band * band - x * x)) - 0.006
            b.sphere(0.016, (x, y, z), GOLD_LIGHT, scale=(0.55, 0.4, 1.0), rot=(0, side * (34 * k - 80 + 90), 0),
                     segments=6, rings=4)
    return b.finish()


# --- The face ---------------------------------------------------------------------------------------------

def whiskers():
    """A drooping walrus moustache over the mouth and bushy eyebrows frowning over the eyes, both
    grey (rigid on the head)."""
    b = C.Builder("Whiskers")
    y = -0.16  # the face
    b.sphere(0.05, (0, y - 0.008, 0.43), "silver", scale=(1.0, 0.5, 0.55), segments=12, rings=6)
    for side in (-1, 1):
        b.sphere(0.05, (side * 0.055, y - 0.006, 0.42), "silver", scale=(1.15, 0.5, 0.62), rot=(0, side * 18, 0),
                 segments=12, rings=6)
        b.sphere(0.03, (side * 0.11, y - 0.002, 0.392), "silver", scale=(0.9, 0.6, 1.0), rot=(0, side * 35, 0),
                 segments=10, rings=5)
        b.box((0.09, 0.034, 0.034), (side * 0.072, y - 0.01, 0.537), "silver", rot=(0, -side * 14, 0), bevel=0.01)
        b.box((0.04, 0.03, 0.026), (side * 0.113, y - 0.008, 0.55), "silver", rot=(0, -side * 30, 0), bevel=0.008)
    return b.finish()


# --- The uniform ------------------------------------------------------------------------------------------

def chest(body):
    """Medals (rows of ribbon bars and a gold star on his left breast, the Order of the Red Star and a
    medal on his right) and the belt with its gold buckle (rigid on the torso)."""
    b = C.Builder("Medals")
    lo, hi = extent(body, "torso", 2, 0.195, 0.23)
    y = -0.091  # just in front of the lapels
    for row, bars in enumerate(RIBBONS):
        z = 0.302 - row * 0.017
        for k, (col, stripe) in enumerate(bars):
            x = 0.058 + k * 0.024 - row * 0.004
            b.box((0.022, 0.008, 0.014), (x, y, z), col)
            b.box((0.006, 0.0095, 0.0145), (x, y - 0.001, z), stripe)
    b.prism(star(0.017), 0.007, loc=(0.084, y - 0.002, 0.326), color=GOLD_LIGHT, rot=(90, 0, 0))
    b.box((0.012, 0.006, 0.01), (0.084, y + 0.001, 0.342), "alarm_red")
    # Order of the Red Star, and a round medal on a ribbon below it.
    b.prism(star(0.03), 0.009, loc=(-0.078, y, 0.296), color="alarm_red", rot=(90, 0, 0))
    b.cylinder(0.011, 0.006, (-0.078, y - 0.011, 0.296), "silver", rot=(90, 0, 0), segments=10)
    b.box((0.024, 0.006, 0.018), (-0.074, y + 0.001, 0.262), "blue")
    b.box((0.008, 0.007, 0.0185), (-0.074, y, 0.262), "safety_yellow")
    b.cylinder(0.015, 0.006, (-0.074, y - 0.002, 0.24), GOLD, rot=(90, 0, 0), segments=12)
    # Belt round the waist, buckle with a star.
    zc = 0.207
    b.box((hi.x - lo.x + 0.016, hi.y - lo.y + 0.016, 0.026), (0, (lo.y + hi.y) / 2, zc), "brown_dark", bevel=0.005)
    b.box((0.056, 0.012, 0.036), (0, lo.y - 0.012, zc), GOLD, bevel=0.004)
    b.prism(star(0.013), 0.005, loc=(0, lo.y - 0.018, zc), color="alarm_red", rot=(90, 0, 0))
    return b.finish()


def shoulder_board(body, side):
    """A gold shoulder board with red piping and two red stars, on top of the sleeve (rigid on the arm)."""
    b = C.Builder("Board")
    x0, x1 = 0.13, 0.25
    lo, hi = extent(body, "arm-" + ("left" if side > 0 else "right"), 0, -x1 if side < 0 else x0, -x0 if side < 0 else x1)
    z, yc, x = hi.z, (lo.y + hi.y) / 2, side * (x0 + x1) / 2
    b.box((x1 - x0 + 0.01, 0.09, 0.01), (x, yc, z + 0.003), "tie_red", bevel=0.003)
    b.box((x1 - x0, 0.08, 0.014), (x, yc, z + 0.009), GOLD, bevel=0.004)
    for k in (-1, 1):
        b.prism(star(0.016), 0.006, loc=(x + k * 0.028, yc, z + 0.015), color="alarm_red", rot=(0, 0, -side * 90))
    return b.finish()


def breeches(body, side):
    """The generals' double red stripes down the outer seam, and a jackboot shaft over the calf (rigid on
    the leg)."""
    b = C.Builder("Leg")
    group = "leg-" + ("left" if side > 0 else "right")
    lo, hi = extent(body, group, 2, 0.07, 0.17)
    out, yc = (hi.x if side > 0 else lo.x), (lo.y + hi.y) / 2
    for dy in (-0.012, 0.012):
        b.box((0.008, 0.009, 0.085), (out + side * 0.001, yc + dy, 0.142), "tie_red")
    lo, hi = extent(body, group, 2, 0.08, 0.12)
    b.box((hi.x - lo.x + 0.014, hi.y - lo.y + 0.014, 0.06), ((lo.x + hi.x) / 2, yc, 0.065), "black", bevel=0.008)
    b.box((hi.x - lo.x + 0.022, hi.y - lo.y + 0.022, 0.012), ((lo.x + hi.x) / 2, yc, 0.096), "charcoal", bevel=0.005)
    return b.finish()


def build():
    arm, body, head, img = S.load_source()
    print("recolour body:")
    S.recolour(body, img, body_rule)
    print("recolour head:")
    S.recolour(head, img, head_rule)
    head_top = S.top(head)
    # Scaled exactly like the supervisor (measured on his hard hat), so both bodies are the same size.
    ref = S.hard_hat(head_top, 0.235)
    s = S.HEIGHT / S.top(ref)
    mesh = ref.data
    bpy.data.objects.remove(ref)
    bpy.data.meshes.remove(mesh)
    cap = peaked_cap(head_top)
    R.skin_rigid(cap, arm, "head")
    parts = [R.skin_rigid(whiskers(), arm, "head"), R.skin_rigid(chest(body), arm, "torso")]
    for side in (1, -1):
        parts.append(R.skin_rigid(shoulder_board(body, side), arm, "arm-left" if side > 0 else "arm-right"))
        parts.append(R.skin_rigid(breeches(body, side), arm, "leg-left" if side > 0 else "leg-right"))
    R.join([body] + parts + [head], "Supervisor")
    S.finish(arm, s)
    return [arm]


if __name__ == "__main__":
    a = C.args("supervisor_general")
    C.reset()
    C.export(a.out, build(), animations=True)

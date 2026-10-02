"""Small set dressing (ASSETS §1, §7: clutter ≤ 300 tris where possible): drums, junk heaps, trash
bags, the rat bed, cones, signs, tools, wall bits. Most have no collision in game.

    blender -b -P tools/blender/dressing.py -- [--only barrel_blue,traffic_cone]

Wall-mounted pieces (fire_extinguisher, wall_clock, warning_sign_*, wall_pipe_bundle) have their
origin at the centre of their back face (the wall), the rest at the base centre. Front = −Y.

The module also holds the small helpers the other furniture scripts share (decals wrapped on a
cylinder, the radiation trefoil, a lightning bolt, 7-segment digits, lumpy spheres, mugs, papers).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import common as C  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

E, GL = C.MAT_EMISSIVE, C.MAT_GLASS


# --- Helpers shared by furniture.py / console.py / donut.py ----------------------------------------

def finish_at(b, origin=(0, 0, 0)):
    """Finishes a root object whose origin is `origin` (in build space) and puts it at the world
    origin (common.Builder.finish keeps the object where it was built)."""
    obj = b.finish(pivot=origin)
    obj.location = (0, 0, 0)
    return obj


def rot_to(direction, spin=0.0):
    """Euler (degrees) turning local +Z onto `direction`, then `spin` degrees about it."""
    d = Vector(direction).normalized()
    q = Vector((0, 0, 1)).rotation_difference(d)
    m = q.to_matrix() @ Matrix.Rotation(math.radians(spin), 3, "Z")
    return tuple(math.degrees(a) for a in m.to_euler("XYZ"))


def ccw(points):
    area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]))
    return list(points) if area > 0 else list(reversed(points))


def circle(r, n=12, centre=(0, 0), a0=0.0):
    cx, cy = centre
    return [(cx + r * math.cos(a0 + 2 * math.pi * i / n), cy + r * math.sin(a0 + 2 * math.pi * i / n)) for i in range(n)]


def sector(r1, r2, a0, a1, n=5):
    """Annular sector between radii r1 < r2 and angles a0 < a1 (degrees), CCW."""
    a0, a1 = math.radians(a0), math.radians(a1)
    outer = [(r2 * math.cos(a0 + (a1 - a0) * i / n), r2 * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
    inner = [(r1 * math.cos(a1 - (a1 - a0) * i / n), r1 * math.sin(a1 - (a1 - a0) * i / n)) for i in range(n + 1)]
    return outer + inner


def trefoil(size, n=4):
    """The radiation symbol as polygons (centre disc + 3 blades), `size` = outer radius."""
    u = size / 5.0
    shapes = [circle(u, 2 * n)]
    for a in (270, 30, 150):
        shapes.append(sector(1.5 * u, 5 * u, a - 30, a + 30, n))
    return shapes


def bolt(h):
    """A lightning bolt polygon `h` tall, centred."""
    pts = [(0.22, 0.5), (0.0, 0.5), (-0.17, -0.03), (0.02, -0.03), (-0.13, -0.5), (0.22, 0.09), (0.03, 0.09)]
    return ccw([(x * h, y * h) for x, y in pts])


def exclaim(h):
    """'!' as two polygons (bar + dot), `h` tall, centred."""
    w = h * 0.16
    bar = [(-w / 2, -0.2 * h), (w / 2, -0.2 * h), (w * 0.62, 0.5 * h), (-w * 0.62, 0.5 * h)]
    dot = [(-w / 2, -0.5 * h), (w / 2, -0.5 * h), (w / 2, -0.33 * h), (-w / 2, -0.33 * h)]
    return [bar, dot]


SEG7 = {0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd", 6: "afgedc", 7: "abc", 8: "abcdefg",
        9: "abcdfg"}


def seg7(digit, w, h, t):
    """Boxes (cx, cy, sx, sy) of a 7-segment digit `w` × `h` with stroke `t`, centred. Adjacent
    vertical segments merge into one bar."""
    s = SEG7[digit]
    out = []
    for name, y in (("a", h / 2 - t / 2), ("g", 0.0), ("d", -h / 2 + t / 2)):
        if name in s:
            out.append((0, y, w, t))
    for top, bottom, x in (("f", "e", -w / 2 + t / 2), ("b", "c", w / 2 - t / 2)):
        if top in s and bottom in s:
            out.append((x, 0, t, h))
        elif top in s:
            out.append((x, h / 4, t, h / 2))
        elif bottom in s:
            out.append((x, -h / 4, t, h / 2))
    return out


def wall_shape(b, pts, depth, loc, color, material=C.MAT_PALETTE, bevel=0.0):
    """A flat shape on a wall: `pts` (x, z) around `loc`, from y = loc.y forward (−Y) by `depth`."""
    b.prism(ccw(pts), depth, loc=loc, rot=(90, 0, 0), color=color, material=material, bevel=bevel)


def _densify(pts, step):
    out = []
    for p, q in zip(pts, pts[1:] + pts[:1]):
        n = max(1, int(math.dist(p, q) / step + 0.999))
        out += [(p[0] + (q[0] - p[0]) * i / n, p[1] + (q[1] - p[1]) * i / n) for i in range(n)]
    return out


def wrap_shape(b, pts, radius, depth, theta, z, color, centre=(0, 0), material=C.MAT_PALETTE, step=0.06):
    """A decal on a vertical cylinder of `radius` (axis through `centre`): `pts` (u, v) in metres on
    the unrolled surface around angle `theta` (degrees; −90 = facing −Y) and height `z`. It sticks
    out `depth` (and sinks the same inside)."""
    pts = _densify(ccw(pts), step)
    t0 = math.radians(theta)

    def at(u, v, r):
        a = t0 + u / radius
        return Vector((centre[0] + r * math.cos(a), centre[1] + r * math.sin(a), z + v))
    b._begin()
    outer = [b.bm.verts.new(at(u, v, radius + depth)) for u, v in pts]
    inner = [b.bm.verts.new(at(u, v, radius - depth)) for u, v in pts]
    b.bm.faces.new(outer)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        b.bm.faces.new((inner[i], inner[j], outer[j], outer[i]))
    b._finish_prim(color, material, False)


def lumpy(b, fn, amount, rng, *args, **kwargs):
    """Calls `fn(*args, **kwargs)` (a Builder primitive) then jitters its new vertices."""
    before = set(b.bm.verts)
    fn(*args, **kwargs)
    for v in b.bm.verts:
        if v not in before:
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * amount
    return b


def cut_below(b, before, z=0.0):
    """Removes the geometry created since `before` (a set of verts) that lies below height `z`."""
    verts = [v for v in b.bm.verts if v not in before]
    vs = set(verts)
    edges = list({e for v in verts for e in v.link_edges if e.verts[0] in vs and e.verts[1] in vs})
    faces = list({f for v in verts for f in v.link_faces if all(w in vs for w in f.verts)})
    bmesh.ops.bisect_plane(b.bm, geom=verts + edges + faces, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_inner=True)


def dome(b, radius, loc, color, scale=(1, 1, 1), rng=None, jitter=0.0, segments=10, rings=6, z=0.0):
    """A (lumpy) sphere cut flat at height `z`."""
    before = set(b.bm.verts)
    if rng is not None and jitter:
        lumpy(b, b.sphere, jitter, rng, radius, loc, color, scale=scale, segments=segments, rings=rings)
    else:
        b.sphere(radius, loc, color, scale=scale, segments=segments, rings=rings)
    cut_below(b, before, z)


def mug(b, loc, color="white", r=0.045, h=0.1, coffee=True, yaw=0.0, seg=10):
    """A chunky mug standing at `loc`, handle towards +X turned by `yaw`."""
    x, y, z = loc
    b.cylinder(r, h, (x, y, z), color, base=True, segments=seg)
    if coffee:
        b.cylinder(r * 0.8, 0.004, (x, y, z + h - 0.012), "coffee", base=True, segments=seg)
    a = math.radians(yaw)
    hx, hy = x + math.cos(a) * (r + 0.012), y + math.sin(a) * (r + 0.012)
    b.torus(h * 0.27, 0.011, (hx, hy, z + h * 0.52), color, rot=(90, 0, yaw), segments=8, sides=4)


def papers(b, loc, rng=None, count=4, spread=(0.6, 0.4), colors=("white", "off_white", "white", "beige_light"),
           yaw=0.0):
    """`count` (≤ 4) A4 sheets scattered flat over about `spread` (12 tris each)."""
    x, y, z = loc
    sx, sy = spread[0] / 0.6, spread[1] / 0.4
    a = math.radians(yaw)
    spots = [(-0.17, 0.02, 14), (0.17, -0.015, -9), (0.02, 0.03, -28), (-0.03, -0.035, 6)]
    for i, (px, py, r) in enumerate(spots[:count]):
        px, py = px * sx, py * sy
        b.box((0.21, 0.297, 0.003), (x + px * math.cos(a) - py * math.sin(a), y + px * math.sin(a) + py * math.cos(a),
                                     z + 0.0015 + i * 0.0025), colors[i % len(colors)], rot=(0, 0, r + yaw))


def keyboard(b, loc, yaw=0.0, color="beige_light", keys="beige_dark", w=0.46, d=0.17):
    """Chunky keyboard: a wedge with three key strips and a space bar."""
    x, y, z = loc
    a = math.radians(yaw)
    rot = Matrix.Rotation(a, 3, "Z")

    def p(dx, dy, dz=0.0):
        v = rot @ Vector((dx, dy, dz))
        return (x + v.x, y + v.y, z + v.z)
    b.prism(ccw([(-d / 2, 0.0), (d / 2, 0.0), (d / 2, 0.045), (-d / 2, 0.022)]), w, loc=p(-w / 2, 0, 0),
            rot=(90, 0, -90 + yaw), color=color, bevel=0.006)
    for i in range(3):
        t = (i + 0.5) / 3.5
        dy = d / 2 - 0.02 - t * (d - 0.06)
        b.box((w - 0.06, 0.03, 0.012), p(-0.0, dy, 0.022 + 0.023 * (dy + d / 2) / d + 0.004), keys,
              rot=(0, 0, yaw))
    b.box((w * 0.45, 0.026, 0.012), p(0, -d / 2 + 0.03, 0.027), keys, rot=(0, 0, yaw))


def phone(b, loc, yaw=0.0, color="charcoal"):
    """An old desk phone: body wedge, handset on the cradle, keypad."""
    x, y, z = loc
    rz = Matrix.Rotation(math.radians(yaw), 3, "Z")

    def p(dx, dy, dz):
        v = rz @ Vector((dx, dy, dz))
        return (x + v.x, y + v.y, z + v.z)
    b.prism(ccw([(-0.11, 0.0), (0.11, 0.0), (0.09, 0.07), (-0.11, 0.05)]), 0.22, loc=p(-0.11, 0, 0),
            rot=(90, 0, -90 + yaw), color=color, bevel=0.012)
    # handset: two ear cups and the bar, across the top
    b.box((0.24, 0.055, 0.03), p(0, 0.04, 0.09), color, rot=(0, 0, yaw), bevel=0.012)
    for s in (-1, 1):
        b.box((0.06, 0.065, 0.04), p(s * 0.1, 0.04, 0.08), color, rot=(0, 0, yaw), bevel=0.012)
    for i in range(3):
        for j in range(3):
            b.box((0.026, 0.022, 0.012), p(-0.035 + j * 0.035, -0.07 + i * 0.03, 0.035 + i * 0.008), "off_white",
                  rot=(math.degrees(math.atan2(0.02, 0.22)) * 0 - 10, 0, yaw))
    b.tube([p(0.12, 0.04, 0.07), p(0.15, 0.02, 0.04), p(0.13, -0.01, 0.015), p(0.115, -0.04, 0.03)], 0.007,
           color, segments=4)


def can(b, loc, label="alarm_red", r=0.05, h=0.12, rot=(0, 0, 0), seg=8):
    """A tin can: label body and silver ends. `loc` is the centre of the can."""
    b.cylinder(r, h * 0.8, loc, label, rot=rot, segments=seg)
    b.cylinder(r * 0.96, h, loc, "silver", rot=rot, segments=seg)


# --- Drums -------------------------------------------------------------------------------------

def drum(b, loc=(0, 0, 0), color="blue", r=0.3, h=0.9, seg=16, yaw=0.0, mark=None, both_sides=True):
    """An oil drum standing at `loc`: body, rims, two ribs, lid with bungs. `mark`: None, "trefoil",
    "label" (a white hazmat diamond with a '!')."""
    x, y, z = loc
    dark = {"blue": "blue_dark", "safety_yellow": "yellow_dark", "alarm_red": "red_dark",
            "steel_light": "steel", "pipe_green": "teal_dark"}.get(color, "grey_dark")
    b.cylinder(r, h - 0.04, (x, y, z + 0.02), color, base=True, segments=seg)
    for zz in (0.0, h - 0.04):
        b.cylinder(r + 0.012, 0.04, (x, y, z + zz), dark, base=True, segments=seg)
    for f in (0.34, 0.66):
        b.cylinder(r + 0.01, 0.03, (x, y, z + h * f - 0.015), color, base=True, segments=seg)
    b.cylinder(r - 0.035, 0.008, (x, y, z + h), color, base=True, segments=seg)
    a = math.radians(yaw)
    for k, (rr, br) in enumerate(((r * 0.55, 0.035), (r * 0.6, 0.025))):
        ang = a + (0.6 if k == 0 else math.pi + 0.3)
        b.cylinder(br, 0.02, (x + rr * math.cos(ang), y + rr * math.sin(ang), z + h + 0.006), "grey_dark", base=True,
                   segments=6)
    if mark == "trefoil":
        for side in ((-90 + yaw, 90 + yaw) if both_sides else (-90 + yaw,)):
            wrap_shape(b, circle(r * 0.47, 12), r, 0.003, side, z + h / 2, "off_white", (x, y), step=0.2)
            for shape in trefoil(r * 0.4, 3 if seg < 16 else 4):
                wrap_shape(b, shape, r, 0.006, side, z + h / 2, "black", (x, y))
    elif mark == "label":
        s = r * 0.42
        wrap_shape(b, [(0, -s), (s, 0), (0, s), (-s, 0)], r, 0.004, -90 + yaw, z + h / 2, "white", (x, y))
        for shape in exclaim(s * 0.9):
            wrap_shape(b, shape, r, 0.007, -90 + yaw, z + h / 2, "black", (x, y))


def build_barrel(color="blue", mark=None, name="Barrel"):
    b = C.Builder(name)
    drum(b, color=color, mark=mark, yaw=15)
    return b.finish()


def build_barrels_cluster(name="Barrels"):
    b = C.Builder(name)
    rng = random.Random(4)
    spots = [(-0.43, -0.43, "blue", None, 0.9), (0.43, -0.42, "safety_yellow", "trefoil", 0.9),
             (-0.42, 0.43, "alarm_red", "label", 0.9), (0.44, 0.44, "blue", None, 0.72)]
    for x, y, col, mark, h in spots:
        drum(b, (x, y, 0), col, r=0.29, h=h, seg=12, yaw=rng.uniform(-40, 40), mark=mark, both_sides=False)
    return b.finish()


# --- Junk ----------------------------------------------------------------------------------------

def tire(b, loc, rot=(0, 0, 0), major=0.21, minor=0.085):
    b.torus(major, minor, loc, "charcoal", rot=rot, segments=12, sides=6, scale=(1, 1, 1.15))


def sock(b, loc, yaw=0.0, color="off_white", accent="blue", s=1.0, lift=0.0):
    x, y, z = loc
    rz = Matrix.Rotation(math.radians(yaw), 3, "Z")
    pts = [(0, -0.2, 0.045 + lift), (0, -0.07, 0.04 + lift * 0.6), (0.02, 0.02, 0.035), (0.08, 0.07, 0.03), (0.17, 0.08, 0.03)]
    path = [tuple(Vector((x, y, z)) + rz @ (Vector(p) * s)) for p in pts]
    b.tube(path, 0.035 * s, color, segments=6)
    b.sphere(0.035 * s, path[-1], accent, segments=6, rings=4)
    b.sphere(0.034 * s, path[0], color, segments=6, rings=4, scale=(1, 0.5, 1))
    b.tube([path[0], tuple(Vector(path[0]) + rz @ Vector((0, 0.025 * s, 0.0)))], 0.038 * s, accent, segments=6)


def cheese_wedge(b, loc, yaw=0.0, size=0.12, color="cheese"):
    x, y, z = loc
    b.prism([(0, 0), (size, -size * 0.35), (size, size * 0.35)], size * 0.55, loc=(x, y, z), rot=(0, 0, yaw),
            color=color, bevel=0.006)
    # holes
    a = math.radians(yaw)
    for f, dz in ((0.55, 0.3), (0.8, 0.12)):
        b.cylinder(0.012, 0.012, (x + math.cos(a) * size * f, y + math.sin(a) * size * f, z + size * 0.55),
                   "yellow_dark", segments=6)


def broken_crate(b, loc, size=0.45, yaw=0.0, tilt=(0, 0), rng=None):
    """An open-topped crate of planks with a plank missing and one sticking out."""
    x, y, z = loc
    rx, ry = tilt
    m = Matrix.Translation(Vector(loc)) @ Euler((math.radians(rx), math.radians(ry), math.radians(yaw)), "XYZ").to_matrix().to_4x4()
    rot = tuple(math.degrees(v) for v in m.to_euler("XYZ"))

    def at(px, py, pz):
        return tuple(m @ Vector((px, py, pz)))
    s = size
    t = 0.03
    b.box((s, s, t), at(0, 0, t / 2), "brown", rot=rot)
    pl = s / 3
    for k in range(3):
        zc = t + pl * (k + 0.5)
        for side in (-1, 1):
            b.box((s, t, pl - 0.012), at(0, side * (s / 2 - t / 2), zc), "wood" if k != 1 else "wood_light", rot=rot)
            if not (side == 1 and k == 2):
                b.box((t, s - 2 * t, pl - 0.012), at(side * (s / 2 - t / 2), 0, zc), "wood", rot=rot)
    for cx in (-1, 1):
        for cy in (-1, 1):
            b.box((0.05, 0.05, s), at(cx * (s / 2 - 0.02), cy * (s / 2 - 0.02), s / 2 + t / 2), "brown", rot=rot)
    # the loose plank leaning out
    r2 = m.to_3x3() @ Euler((0, math.radians(-35), 0)).to_matrix()
    b.box((s * 0.9, t, pl - 0.012), at(s / 2 + 0.1, s / 2 - 0.05, s * 0.35), "wood_light",
          rot=tuple(math.degrees(v) for v in r2.to_euler("XYZ")))


def junk_heap(b, rng, tall=False):
    """A rat-nest rubbish heap inside 1.5 × 2.0 (0.8 or 1.2 tall)."""
    # the heap: lumps of rubbish bags and dirt
    lumps = [(0.0, 0.05, 0.5, 0.62, 0.42, "charcoal"), (-0.3, 0.55, 0.38, 0.4, 0.32, "grey_dark"),
             (0.3, -0.5, 0.38, 0.42, 0.3, "brown_dark"), (0.35, 0.45, 0.3, 0.32, 0.26, "teal_dark"),
             (-0.35, -0.45, 0.3, 0.36, 0.22, "grey_dark")]
    for x, y, sx, sy, sz, col in lumps:
        dome(b, 1.0, (x, y, 0.0), col, scale=(sx, sy, sz), rng=rng, jitter=0.03, segments=8, rings=6)
    # flat rubbish: cardboard, newspaper, a plank
    b.box((0.45, 0.32, 0.012), (-0.38, -0.68, 0.1), "cardboard", rot=(10, -14, 25))
    b.box((0.38, 0.28, 0.008), (0.42, 0.72, 0.1), "off_white", rot=(-10, 12, -20))
    b.box((0.11, 0.9, 0.03), (0.52, -0.1, 0.22), "wood", rot=(8, -25, 8))
    cheese_wedge(b, (0.3, -0.62, 0.22), yaw=-100, size=0.16)
    can(b, (-0.5, 0.0, 0.14), "blue", rot=(0, 0, 0), r=0.06, h=0.14)
    can(b, (0.15, 0.82, 0.08), "orange", rot=(90, 0, -60), r=0.06, h=0.14)
    if not tall:
        broken_crate(b, (-0.22, 0.38, 0.12), 0.42, yaw=20, tilt=(0, -10))
        tire(b, (0.22, -0.18, 0.47), rot=(24, 30, 0))
        b.box((0.32, 0.26, 0.26), (0.05, -0.55, 0.15), "cardboard", rot=(8, 12, -18), bevel=0.01)
        b.box((0.33, 0.04, 0.27), (0.05, -0.55, 0.15), "beige_dark", rot=(8, 12, -18))
        can(b, (-0.12, 0.05, 0.46), "alarm_red", rot=(80, 0, 40), r=0.06, h=0.14)
        can(b, (0.2, 0.42, 0.33), "pipe_green", rot=(70, 10, 10), r=0.055, h=0.13)
        cheese_wedge(b, (-0.25, -0.12, 0.42), yaw=40, size=0.18)
        sock(b, (0.05, 0.1, 0.4), yaw=200, s=1.6, lift=0.06)
    else:
        broken_crate(b, (-0.22, 0.3, 0.14), 0.5, yaw=10, tilt=(0, -5))
        broken_crate(b, (-0.12, 0.3, 0.68), 0.38, yaw=-25, tilt=(8, 6))
        tire(b, (0.36, -0.3, 0.42), rot=(80, 0, 20), major=0.23, minor=0.09)
        tire(b, (0.2, 0.2, 0.42), rot=(10, 15, 0))
        b.box((0.32, 0.26, 0.26), (-0.2, -0.45, 0.22), "cardboard", rot=(8, 12, -18), bevel=0.01)
        b.box((0.33, 0.04, 0.27), (-0.2, -0.45, 0.22), "beige_dark", rot=(8, 12, -18))
        can(b, (0.2, 0.2, 0.55), "orange", r=0.06, h=0.14)
        can(b, (-0.08, -0.15, 0.48), "alarm_red", rot=(60, 0, 20), r=0.06, h=0.14)
        can(b, (0.15, -0.65, 0.2), "silver", rot=(75, 0, -20), r=0.06, h=0.14)
        cheese_wedge(b, (0.35, -0.05, 0.3), yaw=70, size=0.18)
        sock(b, (-0.1, -0.15, 0.38), yaw=160, s=1.6, lift=0.08)
        # a broken broom handle sticking out of the heap
        b.cylinder(0.02, 0.85, (0.32, 0.6, 0.15), "wood", base=True, rot=(-30, 20, 0), segments=6)


def build_junk_pile(tall=False, name="JunkPile"):
    b = C.Builder(name)
    junk_heap(b, random.Random(7 if tall else 3), tall)
    return b.finish()


def build_trash_bags(name="TrashBags"):
    b = C.Builder(name)
    rng = random.Random(11)
    for x, y, r, h, col, yaw in ((-0.2, -0.15, 0.3, 0.55, "black", 0), (0.25, 0.1, 0.27, 0.48, "teal_dark", 40),
                                 (-0.12, 0.3, 0.2, 0.36, "charcoal", -30)):
        dome(b, r, (x, y, h * 0.42), col, scale=(1, 0.9, h * 0.5 / r), rng=rng, jitter=0.022, segments=10, rings=6)
        top = h * 0.42 + h * 0.5 - 0.02
        b.sphere(0.05, (x, y, top + 0.02), col, scale=(1, 1, 0.8), segments=6, rings=4)
        for s in (-1, 1):
            a = math.radians(yaw)
            b.sphere(0.045, (x + s * math.cos(a) * 0.05, y + s * math.sin(a) * 0.05, top + 0.07), col,
                     scale=(1.0, 0.45, 0.6), rot=(0, s * 30, yaw), segments=6, rings=4)
    return b.finish()


def build_rat_bed(name="RatBed"):
    """A sardine tin bed (with its rolled-back lid) under a sock blanket, a cotton-ball pillow and
    a bottle-cap table on a thread spool."""
    b = C.Builder(name)
    L, W, H = 0.42, 0.26, 0.07
    x0 = -0.08
    # tin: rounded tray
    b.box((L, W, H), (x0, 0, 0), "silver", base=True, bevel=0.03)
    b.box((L - 0.03, W - 0.03, 0.01), (x0, 0, H - 0.004), "grey_light", bevel=0.01)
    # rolled lid at the head end, with the key
    b.cylinder(0.035, W - 0.02, (x0 + L / 2 + 0.005, 0, H + 0.03), "silver", rot=(90, 0, 0), segments=8)
    b.box((0.07, 0.018, 0.01), (x0 + L / 2 + 0.06, -W / 2 + 0.03, H + 0.03), "grey", rot=(0, 0, 0))
    b.torus(0.02, 0.006, (x0 + L / 2 + 0.105, -W / 2 + 0.03, H + 0.03), "grey", segments=8, sides=4)
    # label band on the side
    b.box((L * 0.6, 0.004, H * 0.55), (x0 - 0.02, -W / 2 - 0.002, H * 0.5), "blue")
    b.box((L * 0.18, 0.006, H * 0.3), (x0 - 0.06, -W / 2 - 0.003, H * 0.5), "sky")
    # mattress: a folded sock blanket, bumpy, hanging over the foot end
    rng = random.Random(5)
    lumpy(b, b.box, 0.006, rng, (L * 0.78, W * 0.92, 0.045), (x0 - 0.035, 0, H + 0.01), "alarm_red", bevel=0.02)
    for i in range(3):
        b.box((0.03, W * 0.94, 0.046), (x0 - 0.15 + i * 0.09, 0, H + 0.0105), "off_white")
    b.box((0.05, W * 0.85, 0.08), (x0 - L / 2 + 0.01, 0, H - 0.01), "alarm_red", rot=(0, -20, 0), bevel=0.015)
    # pillow: cotton ball
    lumpy(b, b.sphere, 0.006, rng, 0.06, (x0 + L / 2 - 0.08, 0, H + 0.04), "white", scale=(0.8, 1.2, 0.55),
          segments=8, rings=5)
    # bottle-cap table on a thread spool, a crumb of cheese on it
    tx, ty = x0 + L / 2 + 0.11, 0.06
    b.cylinder(0.035, 0.012, (tx, ty, 0), "wood", base=True, segments=8)
    b.cylinder(0.022, 0.07, (tx, ty, 0.012), "sky", base=True, segments=8)
    b.cylinder(0.035, 0.012, (tx, ty, 0.082), "wood", base=True, segments=8)
    b.cylinder(0.06, 0.018, (tx, ty, 0.094), "alarm_red", base=True, segments=12)
    b.cylinder(0.052, 0.004, (tx, ty, 0.112), "silver", base=True, segments=12)
    b.prism([(0, 0), (0.035, -0.012), (0.035, 0.012)], 0.02, loc=(tx - 0.015, ty, 0.116), color="cheese")
    return b.finish()


# --- Safety and maintenance ---------------------------------------------------------------------

def build_traffic_cone(name="TrafficCone"):
    b = C.Builder(name)
    b.box((0.36, 0.36, 0.035), (0, 0, 0), "orange_dark", base=True, bevel=0.012)
    b.cylinder(0.14, 0.45, (0, 0, 0.035), "orange", base=True, radius_top=0.025, segments=12)
    # white band (a slightly fatter slice of the cone)
    r = lambda z: 0.14 + (0.025 - 0.14) * (z - 0.035) / 0.45  # noqa: E731
    b.cylinder(r(0.21) + 0.006, 0.09, (0, 0, 0.21), "white", base=True, radius_top=r(0.30) + 0.006, segments=12)
    b.cylinder(0.03, 0.02, (0, 0, 0.48), "orange", base=True, radius_top=0.018, segments=8)
    return b.finish()


def frame_rot(x_axis, y_axis):
    """Euler (degrees) of the frame with local X, Y along the given axes (Z = X × Y)."""
    x, y = Vector(x_axis).normalized(), Vector(y_axis).normalized()
    m = Matrix((x, y, x.cross(y))).transposed()
    return tuple(math.degrees(a) for a in m.to_euler("XYZ"))


def build_wet_floor_sign(name="WetFloorSign"):
    """Yellow A-frame: two panels with a black header band and a '!' warning triangle."""
    b = C.Builder(name)
    h, w, t = 0.6, 0.32, 0.018
    a = math.radians(13.0)
    ln = h / math.cos(a)
    for side in (-1, 1):
        X = Vector((-side, 0, 0))
        Y = Vector((0, -side * math.sin(a), math.cos(a)))  # up along the panel
        Z = X.cross(Y)  # outward
        rot = frame_rot(X, Y)
        top = Vector((0, 0, h))

        def at(u, v, out=0.0):
            """Point on the outer face: u across, v down from the ridge."""
            return tuple(top + X * u - Y * v + Z * (t + out))
        b.box((w, ln, t), tuple(top - Y * (ln / 2) + Z * (t / 2)), "safety_yellow", rot=rot, bevel=0.008)
        b.box((w * 0.8, 0.055, 0.004), at(0, 0.1, 0.002), "black", rot=rot)
        b.box((w * 0.55, 0.022, 0.004), at(0, 0.16, 0.002), "black", rot=rot)
        loc = at(0, 0.36)
        b.prism([(-0.105, -0.09), (0.105, -0.09), (0.0, 0.095)], 0.003, loc=loc, rot=rot, color="black")
        b.prism([(-0.072, -0.07), (0.072, -0.07), (0.0, 0.058)], 0.005, loc=loc, rot=rot, color="safety_yellow")
        for shape in exclaim(0.09):
            b.prism([(x, y * 0.85 - 0.016) for x, y in shape], 0.007, loc=loc, rot=rot, color="black")
    # ridge grip
    b.box((w * 0.55, 0.06, 0.04), (0, 0, h), "yellow_dark", bevel=0.012)
    b.box((w * 0.3, 0.04, 0.05), (0, 0, h + 0.03), "yellow_dark", bevel=0.012)
    return b.finish()


def build_mop_bucket(name="MopBucket"):
    b = C.Builder(name)
    top = 0.4
    # bucket: square tapered tub full of water, a lip around, four castors
    b.cylinder(0.27, top - 0.07, (0, 0, 0.07), "safety_yellow", base=True, radius_top=0.31, segments=4, rot=(0, 0, 45),
               bevel=0.025, smooth=False)
    b.box((0.4, 0.4, 0.004), (0, 0, top), "sky", base=True)
    for s in (-1, 1):
        b.box((0.46, 0.035, 0.04), (0, s * 0.21, top - 0.01), "yellow_dark", base=True, bevel=0.01)
        b.box((0.035, 0.46, 0.04), (s * 0.21, 0, top - 0.01), "yellow_dark", base=True, bevel=0.01)
    for x in (-0.15, 0.15):
        for y in (-0.15, 0.15):
            b.box((0.05, 0.05, 0.04), (x, y, 0.045), "grey_dark", base=True)
            b.cylinder(0.035, 0.03, (x, y, 0.035), "charcoal", rot=(0, 90, 0), segments=8)
    # wringer on the back half
    b.box((0.36, 0.16, 0.1), (0, 0.12, top + 0.02), "grey", base=True, bevel=0.015)
    b.box((0.3, 0.1, 0.04), (0, 0.12, top + 0.1), "grey_dark", base=True, bevel=0.01)
    b.tube([(0.16, 0.16, top + 0.08), (0.2, 0.26, top + 0.24), (0.2, 0.28, top + 0.5)], 0.015, "grey_dark", segments=6)
    b.cylinder(0.022, 0.12, (0.2, 0.28, top + 0.52), "black", segments=6)
    # push handle
    b.tube([(-0.2, 0.2, top), (-0.2, 0.26, top + 0.35), (0.0, 0.28, top + 0.42), (0.2, 0.26, top + 0.35),
            (0.2, 0.2, top)], 0.014, "grey", segments=6)
    # the mop: head soaking at the front, strands over the rim, handle leaning back
    hx, hy, hz = -0.04, -0.09, top + 0.01
    for i in range(10):
        a = 2 * math.pi * (i + 0.3) / 10
        d = Vector((math.cos(a), math.sin(a), -0.25 if math.sin(a) > -0.3 else -1.4)).normalized()
        b.cylinder(0.026, 0.2, (hx + math.cos(a) * 0.04, hy + math.sin(a) * 0.04, hz + 0.02), "off_white",
                   rot=rot_to(d), segments=5, base=True)
    dome(b, 0.085, (hx, hy, hz), "off_white", scale=(1, 1, 0.7), rng=random.Random(2), jitter=0.01, segments=8,
         rings=6, z=hz)
    b.cylinder(0.03, 0.06, (hx, hy, hz + 0.05), "grey", base=True, segments=6)
    b.cylinder(0.02, 1.1, (hx, hy, hz + 0.08), "wood", base=True, rot=(-16, -9, 0), segments=6)
    return b.finish()


def build_fire_extinguisher(name="FireExtinguisher"):
    """Wall-mounted extinguisher; origin at the centre of the back face."""
    b = C.Builder(name)
    R = 0.085
    yc = -0.02 - R
    z0 = -0.32
    # wall plate and bracket
    b.box((0.13, 0.012, 0.42), (0, -0.006, -0.06), "grey_dark", bevel=0.004)
    b.box((0.05, 0.03, 0.04), (0, -0.02, 0.1), "grey", bevel=0.006)
    # body
    b.cylinder(R, 0.44, (0, yc, z0), "alarm_red", base=True, segments=12)
    b.sphere(R, (0, yc, z0 + 0.44), "alarm_red", scale=(1, 1, 0.55), segments=12, rings=6)
    b.cylinder(R + 0.006, 0.025, (0, yc, z0 + 0.25), "grey_light", base=True, segments=12)
    b.cylinder(R + 0.004, 0.02, (0, yc, z0), "red_dark", base=True, segments=12)
    wrap_shape(b, [(-0.05, -0.07), (0.05, -0.07), (0.05, 0.07), (-0.05, 0.07)], R, 0.003, -90, z0 + 0.13, "white",
               (0, yc))
    wrap_shape(b, [(-0.035, -0.012), (0.035, -0.012), (0.035, 0.012), (-0.035, 0.012)], R, 0.005, -90, z0 + 0.17,
               "black", (0, yc))
    # valve head, handles, gauge
    top = z0 + 0.44 + R * 0.55
    b.cylinder(0.028, 0.05, (0, yc, top - 0.01), "grey_dark", base=True, segments=8)
    b.box((0.05, 0.05, 0.04), (0, yc, top + 0.06), "black", bevel=0.01)
    b.box((0.16, 0.03, 0.018), (0.04, yc, top + 0.09), "black", rot=(0, -12, 0), bevel=0.006)
    b.box((0.14, 0.03, 0.018), (0.035, yc, top + 0.05), "black", rot=(0, 6, 0), bevel=0.006)
    b.cylinder(0.025, 0.012, (0, yc - 0.032, top + 0.06), "white", rot=(90, 0, 0), segments=8)
    b.box((0.004, 0.003, 0.018), (0.004, yc - 0.04, top + 0.065), "alarm_red", rot=(0, -30, 0))
    # hose down the side into its clip
    b.tube([(-0.02, yc, top + 0.06), (-0.075, yc, top + 0.05), (-0.11, yc - 0.01, top - 0.03), (-0.115, yc - 0.02, z0 + 0.25),
            (-0.105, yc - 0.03, z0 + 0.12)], 0.013, "black", segments=6)
    b.cylinder(0.02, 0.07, (-0.105, yc - 0.03, z0 + 0.06), "black", radius_top=0.012, segments=6)
    return b.finish()


def build_toolbox(name="Toolbox"):
    b = C.Builder(name)
    b.box((0.5, 0.2, 0.15), (0, 0, 0), "alarm_red", base=True, bevel=0.015)
    b.box((0.5, 0.2, 0.05), (0, 0, 0.15), "alarm_red", base=True, bevel=0.015)
    b.box((0.505, 0.205, 0.012), (0, 0, 0.144), "red_dark", base=True)
    for x in (-0.17, 0.17):
        b.box((0.04, 0.012, 0.05), (x, -0.104, 0.13), "silver", base=True, bevel=0.004)
        b.box((0.03, 0.03, 0.04), (x * 0.95, 0, 0.2), "grey_dark", base=True)
    b.box((0.34, 0.035, 0.025), (0, 0, 0.225), "grey_dark", base=True, bevel=0.01)
    return b.finish()


def build_cable_spool(name="CableSpool"):
    """Wooden cable drum on its rim, axle along X."""
    b = C.Builder(name)
    R, W = 0.5, 0.6
    for x in (-W / 2 + 0.03, W / 2 - 0.03):
        b.cylinder(R, 0.06, (x, 0, R), "wood", rot=(0, 90, 0), segments=16, bevel=0.012)
        b.cylinder(0.08, 0.07, (x, 0, R), "brown", rot=(0, 90, 0), segments=8)
        for i in range(4):
            a = math.pi / 4 + i * math.pi / 2
            b.box((0.065, 0.04, 0.04), (x, math.cos(a) * 0.3, R + math.sin(a) * 0.3), "brown_dark")
        b.box((0.064, R * 1.9, 0.02), (x, 0, R), "brown", rot=(25, 0, 0))
    b.cylinder(0.4, W - 0.12, (0, 0, R), "charcoal", rot=(0, 90, 0), segments=14)
    for i in range(4):
        b.cylinder(0.405, 0.01, (-0.18 + i * 0.12, 0, R), "black", rot=(0, 90, 0), segments=14)
    # loose cable end down to the floor
    b.tube([(0.12, -0.33, R + 0.23), (0.14, -0.43, R + 0.05), (0.16, -0.45, 0.2), (0.2, -0.5, 0.03), (0.32, -0.55, 0.02)],
           0.025, "charcoal", segments=6)
    return b.finish()


def build_papers(name="Papers"):
    b = C.Builder(name)
    papers(b, (0, 0, 0))
    return b.finish(smooth_angle=0)


def build_clipboard(name="Clipboard"):
    b = C.Builder(name)
    b.box((0.23, 0.32, 0.006), (0, 0, 0), "brown", base=True, bevel=0.003)
    b.box((0.2, 0.27, 0.003), (0, -0.015, 0.006), "white", base=True)
    for i in range(4):
        b.box((0.14 if i % 2 else 0.12, 0.012, 0.002), (-0.01 * (i % 2), 0.05 - i * 0.045, 0.009), "grey", base=True)
    b.box((0.1, 0.035, 0.012), (0, 0.13, 0.006), "silver", base=True, bevel=0.004)
    b.cylinder(0.006, 0.08, (0, 0.11, 0.016), "grey", rot=(0, 90, 0), segments=6)
    return b.finish()


def build_wall_clock(name="WallClock"):
    """Office wall clock; origin at the centre of its back."""
    b = C.Builder(name)
    R = 0.18
    b.cylinder(R, 0.05, (0, -0.025, 0), "black", rot=(90, 0, 0), segments=16, bevel=0.01)
    b.cylinder(R - 0.025, 0.004, (0, -0.051, 0), "off_white", rot=(90, 0, 0), segments=16)
    for i in range(12):
        a = math.pi / 2 - i * math.pi / 6
        big = i % 3 == 0
        b.box((0.012 if big else 0.008, 0.004, 0.03 if big else 0.016),
              (math.cos(a) * (R - 0.045), -0.054, math.sin(a) * (R - 0.045)), "black", rot=(0, -math.degrees(a) + 90, 0))
    for ln, wd, ang, col in ((0.075, 0.016, 60, "black"), (0.115, 0.011, -40, "black"), (0.12, 0.004, 160, "alarm_red")):
        a = math.radians(90 - ang)
        b.box((wd, 0.004, ln), (math.cos(a) * ln * 0.4, -0.058 - (0.002 if col != "black" else 0), math.sin(a) * ln * 0.4),
              col, rot=(0, ang, 0))
    b.cylinder(0.012, 0.012, (0, -0.06, 0), "alarm_red", rot=(90, 0, 0), segments=8)
    return b.finish()


def sign_plate(b, w=0.5, h=0.5, plate="safety_yellow", border="black"):
    """A wall sign plate (back at y = 0, centred on z = 0) with a border and corner screws."""
    b.box((w, 0.015, h), (0, -0.0075, 0), border, bevel=0.006)
    b.box((w - 0.05, 0.004, h - 0.05), (0, -0.016, 0), plate)
    for x in (-1, 1):
        for z in (-1, 1):
            b.cylinder(0.011, 0.006, (x * (w / 2 - 0.012), -0.016, z * (h / 2 - 0.012)), "silver", rot=(90, 0, 0),
                       segments=6)


def build_warning_sign_radiation(name="RadiationSign"):
    b = C.Builder(name)
    sign_plate(b)
    for shape in trefoil(0.19):
        wall_shape(b, shape, 0.006, (0, -0.016, 0.0), "black")
    return b.finish()


def build_warning_sign_high_voltage(name="HighVoltageSign"):
    b = C.Builder(name)
    sign_plate(b, plate="off_white")
    wall_shape(b, [(-0.21, -0.17), (0.21, -0.17), (0.0, 0.2)], 0.004, (0, -0.017, 0.0), "black")
    wall_shape(b, [(-0.165, -0.145), (0.165, -0.145), (0.0, 0.145)], 0.006, (0, -0.017, 0.0), "safety_yellow")
    wall_shape(b, bolt(0.22), 0.009, (0, -0.017, -0.025), "black")
    return b.finish()


def stripes(b, length, width, z, stripe=0.05, color="black", base="safety_yellow", thick=0.004, slant=45):
    """A hazard stripe strip along X centred on the origin (base box + slanted black bands)."""
    b.box((length, width, thick), (0, 0, z), base, base=True)
    off = width * math.tan(math.radians(slant))
    x = -length / 2 - off
    while x < length / 2:
        poly = [(x, -width / 2), (x + stripe, -width / 2), (x + stripe + off, width / 2), (x + off, width / 2)]
        poly = _clip_x(poly, -length / 2, length / 2)
        if len(poly) >= 3:
            b.prism(poly, 0.001, loc=(0, 0, z + thick), color=color)
        x += 2 * stripe


def _clip_x(poly, x0, x1):
    def clip(pts, keep, inter):
        out = []
        for p, q in zip(pts, pts[1:] + pts[:1]):
            if keep(p):
                out.append(p)
            if keep(p) != keep(q):
                out.append(inter(p, q))
        return out

    def ix(xc):
        return lambda p, q: (xc, p[1] + (q[1] - p[1]) * (xc - p[0]) / (q[0] - p[0]))
    poly = clip(poly, lambda p: p[0] >= x0, ix(x0))
    poly = clip(poly, lambda p: p[0] <= x1, ix(x1)) if poly else poly
    # drop near-duplicate points
    out = []
    for p in poly:
        if not out or math.dist(p, out[-1]) > 1e-5:
            out.append(p)
    if len(out) > 1 and math.dist(out[0], out[-1]) < 1e-5:
        out.pop()
    return out


def build_hazard_floor_tape(name="HazardTape"):
    b = C.Builder(name)
    stripes(b, 1.0, 0.1, 0.0, stripe=0.05, thick=0.004)
    return b.finish(smooth_angle=0)


def build_wall_pipe_bundle(name="WallPipes"):
    """Three pipes along X on two wall brackets; origin at the back centre."""
    b = C.Builder(name)
    L = 2.0
    pipes = [(0.12, 0.055, "pipe_green"), (0.0, 0.045, "teal"), (-0.12, 0.04, "steel_light")]
    for z, r, col in pipes:
        y = -0.03 - 0.06
        b.cylinder(r, L, (0, y, z), col, rot=(0, 90, 0), segments=10)
        for x in (-L / 2 + 0.04, L / 2 - 0.04):
            b.cylinder(r + 0.014, 0.035, (x, y, z), "steel" if col != "steel" else "steel_dark", rot=(0, 90, 0),
                       segments=10)
    for x in (-0.55, 0.55):
        b.box((0.06, 0.02, 0.4), (x, -0.01, 0), "grey_dark", bevel=0.005)
        for z, r, col in pipes:
            b.cylinder(r + 0.01, 0.04, (x, -0.09, z), "grey", rot=(0, 90, 0), segments=10)
            b.box((0.04, 0.05, 0.02), (x, -0.045, z), "grey_dark")
    b.box((0.08, 0.004, 0.03), (0.0, -0.09 - 0.055, 0.12), "white", rot=(0, 0, 0))
    return b.finish()


def build_radiation_vial_crate(name="VialCrate"):
    """A lead-lined crate of glowing vials, 0.6 × 0.4, vials poking out to 0.3."""
    b = C.Builder(name)
    W, D, H = 0.6, 0.4, 0.2
    t = 0.025
    b.box((W, D, 0.03), (0, 0, 0), "steel_dark", base=True, bevel=0.008)
    for s in (-1, 1):
        b.box((W, t, H), (0, s * (D / 2 - t / 2), 0), "steel", base=True, bevel=0.008)
        b.box((t, D - 2 * t, H), (s * (W / 2 - t / 2), 0, 0), "steel", base=True, bevel=0.008)
    # hazard band and trefoil on the front
    b.box((W - 0.06, 0.006, 0.05), (0, -D / 2 - 0.002, 0.12), "safety_yellow")
    b.box((0.13, 0.008, 0.13), (0, -D / 2 - 0.003, 0.1), "safety_yellow", bevel=0.004)
    for shape in trefoil(0.055):
        wall_shape(b, shape, 0.004, (0, -D / 2 - 0.007, 0.1), "black")
    # dividers and handles
    b.box((W - 2 * t, 0.012, H * 0.7), (0, 0, 0.03), "grey_dark", base=True)
    for x in (-0.1, 0.1):
        b.box((0.012, D - 2 * t, H * 0.7), (x, 0, 0.03), "grey_dark", base=True)
    for s in (-1, 1):
        b.box((0.03, 0.12, 0.025), (s * (W / 2 + 0.012), 0, H - 0.04), "grey_dark", bevel=0.008)
    # vials: 3 × 2 cells, two vials each
    for i, x in enumerate((-0.2, 0.0, 0.2)):
        for j, y in enumerate((-0.09, 0.09)):
            for k, dx in enumerate((-0.04, 0.04)):
                if (i, j, k) in ((2, 1, 1), (0, 0, 0)):
                    continue  # two empty slots
                h = 0.21 + 0.03 * ((i + j + k) % 2)
                b.cylinder(0.026, h, (x + dx, y, 0.03), "rad_green", base=True, segments=8, material=E)
                b.cylinder(0.03, 0.035, (x + dx, y, 0.03 + h), "grey_light", base=True, segments=8)
    return b.finish()


# --- Module contract -------------------------------------------------------------------------------

BUILDERS = {
    "barrel": build_barrel, "barrels_cluster": build_barrels_cluster, "junk_pile": build_junk_pile,
    "trash_bags": build_trash_bags, "rat_bed": build_rat_bed, "traffic_cone": build_traffic_cone,
    "wet_floor_sign": build_wet_floor_sign, "mop_bucket": build_mop_bucket,
    "fire_extinguisher": build_fire_extinguisher, "toolbox": build_toolbox, "cable_spool": build_cable_spool,
    "papers": build_papers, "clipboard": build_clipboard, "wall_clock": build_wall_clock,
    "warning_sign_radiation": build_warning_sign_radiation,
    "warning_sign_high_voltage": build_warning_sign_high_voltage, "hazard_floor_tape": build_hazard_floor_tape,
    "wall_pipe_bundle": build_wall_pipe_bundle, "radiation_vial_crate": build_radiation_vial_crate,
}

ASSETS = [
    ("barrel_blue", {"kind": "barrel", "color": "blue", "name": "BarrelBlue"}),
    ("barrel_yellow", {"kind": "barrel", "color": "safety_yellow", "mark": "trefoil", "name": "BarrelYellow"}),
    ("barrel_red", {"kind": "barrel", "color": "alarm_red", "mark": "label", "name": "BarrelRed"}),
    ("barrels_cluster", {"kind": "barrels_cluster"}),
    ("junk_pile", {"kind": "junk_pile"}),
    ("junk_pile_tall", {"kind": "junk_pile", "tall": True, "name": "JunkPileTall"}),
    ("trash_bags", {"kind": "trash_bags"}),
    ("rat_bed", {"kind": "rat_bed"}),
    ("traffic_cone", {"kind": "traffic_cone"}),
    ("wet_floor_sign", {"kind": "wet_floor_sign"}),
    ("mop_bucket", {"kind": "mop_bucket"}),
    ("fire_extinguisher", {"kind": "fire_extinguisher"}),
    ("toolbox", {"kind": "toolbox"}),
    ("cable_spool", {"kind": "cable_spool"}),
    ("papers", {"kind": "papers"}),
    ("clipboard", {"kind": "clipboard"}),
    ("wall_clock", {"kind": "wall_clock"}),
    ("warning_sign_radiation", {"kind": "warning_sign_radiation"}),
    ("warning_sign_high_voltage", {"kind": "warning_sign_high_voltage"}),
    ("hazard_floor_tape", {"kind": "hazard_floor_tape"}),
    ("wall_pipe_bundle", {"kind": "wall_pipe_bundle"}),
    ("radiation_vial_crate", {"kind": "radiation_vial_crate"}),
]


def build(kind, **kwargs):
    return BUILDERS[kind](**kwargs)


def main(module_name, assets, build_fn):
    """Shared __main__: builds every ASSETS entry (or --only a,b) into assets/generated/."""
    a = C.args(module_name, lambda p: p.add_argument("--only", default=""))
    names = a.only.split(",") if a.only else [n for n, _ in assets]
    for out_name, kwargs in assets:
        if out_name not in names:
            continue
        C.reset()
        roots = build_fn(**kwargs)
        roots = roots if isinstance(roots, (list, tuple)) else [roots]
        out = a.out if len(names) == 1 and not a.out.endswith(module_name + ".glb") else \
            os.path.join(C.GENERATED, out_name + ".glb")
        C.export(out, roots)


if __name__ == "__main__":
    main("dressing", ASSETS, build)

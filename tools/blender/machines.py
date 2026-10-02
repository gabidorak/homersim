"""Plant machines: the six subsystem station machines plus the generator, pump and transformer props.
Also the shared helpers the other plant scripts import (hazard stripes, bolts, flanges, rounded
pipes, hollow tubes, valve wheels, gauges, lamps, icons).

    blender -b -P tools/blender/machines.py -- --kind rods [--out PATH]
    kinds: rods pumps valves turbine grid ventilation generator pump transformer

Station machines (machine_<kind>) fit a 2 x 2 m footprint, front at y = -1. Two areas stay flat for
the interactables Godot mounts on them:
  - front: x -0.42..0.42, z 0.7..1.3 is a flat plate whose face is at y = -1.0 (repair panel);
  - sides: x = +-1.0, y -0.3..0.3, z 0.1..0.56 are flat plates (sabotage junction boxes).
Animated children: machine_valves "Wheel1"/"Wheel2" (spin about X), machine_grid "Switch1".."Switch8"
(hinge, flip about X), machine_ventilation "Fan" (spins about Y).
"""
import math
import os
import sys

import bmesh
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

KINDS = ["rods", "pumps", "valves", "turbine", "grid", "ventilation", "generator", "pump", "transformer"]
ASSETS = [("machine_" + k, {"kind": k}) for k in KINDS[:6]] + [(k, {"kind": k}) for k in KINDS[6:]]


# --- Shared helpers (imported by the other plant scripts) -----------------------------------------

# Rotations that map a primitive's local frame onto a face: local X = the face's "right" (seen from
# outside), local Y = its "up", local Z = its outward normal.
FACE = {"front": (90, 0, 0), "back": (90, 0, 180), "right": (90, 0, 90), "left": (90, 0, -90),
        "top": (0, 0, 0), "bottom": (180, 0, 0)}


def _rot(rot):
    return FACE[rot] if isinstance(rot, str) else tuple(rot)


class Frame:
    """A local frame (loc + XYZ Euler in degrees, or a FACE name) to place parts on a face or a
    rotated part: p() maps local points, r() composes local rotations."""

    def __init__(self, loc=(0, 0, 0), rot=(0, 0, 0)):
        self.m = C._matrix(loc, _rot(rot))

    def p(self, x=0.0, y=0.0, z=0.0):
        return tuple(self.m @ Vector((x, y, z)))

    def r(self, rx=0.0, ry=0.0, rz=0.0):
        m = self.m.to_3x3() @ Euler([math.radians(a) for a in (rx, ry, rz)], "XYZ").to_matrix()
        return tuple(math.degrees(a) for a in m.to_euler("XYZ"))

    def sub(self, loc=(0, 0, 0), rot=(0, 0, 0)):
        f = Frame()
        f.m = self.m @ C._matrix(loc, _rot(rot))
        return f


def cyl(b, r, depth, loc=(0, 0, 0), color="grey", rot=(0, 0, 0), seg=12, bevel=0.0, base=False, r_top=None,
        material=C.MAT_PALETTE, smooth=True, caps=True):
    """Builder.cylinder, but `bevel` only chamfers the two cap rims (cheaper and cleaner than also
    bevelling the side edges). Along local Z of `rot`; `base` puts the bottom cap on `loc`."""
    b._begin()
    m = C._matrix(loc, _rot(rot)) @ Matrix.Translation((0, 0, depth / 2 if base else 0))
    res = bmesh.ops.create_cone(b.bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r,
                                radius2=r if r_top is None else r_top, depth=depth, matrix=m)
    if bevel > 0 and caps:
        axis = (m.to_3x3() @ Vector((0, 0, 1))).normalized()
        faces = {f for v in res["verts"] for f in v.link_faces}
        edges = set()
        for f in faces:
            f.normal_update()
            if abs(f.normal.dot(axis)) > 0.999:
                edges.update(f.edges)
        verts = {v for e in edges for v in e.verts}
        bmesh.ops.bevel(b.bm, geom=list(verts) + list(edges), offset=bevel, offset_type="OFFSET", segments=1,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    b._finish_prim(color, material, smooth)
    return b


def hollow(b, r_out, r_in, depth, loc=(0, 0, 0), color="grey", rot=(0, 0, 0), seg=16, base=False,
           inner=None, r_out_top=None, r_in_top=None, smooth=True, material=C.MAT_PALETTE):
    """A thick-walled open tube along local Z (outer wall, inner wall facing in, both rims). The inner
    wall can have its own colour (a dark inside reads as depth)."""
    m = C._matrix(loc, _rot(rot)) @ Matrix.Translation((0, 0, 0 if base else -depth / 2))
    rot_ = r_out if r_out_top is None else r_out_top
    rit = r_in if r_in_top is None else r_in_top
    angles = [2 * math.pi * i / seg for i in range(seg)]

    def ring(r, z):
        return [b.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), z))) for a in angles]

    b._begin()
    ob, ot, ib, it = ring(r_out, 0), ring(rot_, depth), ring(r_in, 0), ring(rit, depth)
    for i in range(seg):
        j = (i + 1) % seg
        b.bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        b.bm.faces.new((ot[i], ot[j], it[j], it[i]))
        b.bm.faces.new((ob[j], ob[i], ib[i], ib[j]))
    b._finish_prim(color, material, smooth)
    b._begin()
    for i in range(seg):
        j = (i + 1) % seg
        b.bm.faces.new((ib[j], ib[i], it[i], it[j]))
    b._finish_prim(inner or color, material, smooth)
    return b


def lathe(b, profile, color="grey", seg=24, loc=(0, 0, 0), rot=(0, 0, 0), inside=False, smooth=True,
          material=C.MAT_PALETTE):
    """A surface of revolution about local Z through the (radius, z) points of `profile` (bottom to
    top), facing out (or in with `inside`). No caps."""
    m = C._matrix(loc, _rot(rot))
    angles = [2 * math.pi * i / seg for i in range(seg)]
    b._begin()
    rings = [[b.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), z))) for a in angles] for r, z in profile]
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            q = (r0[i], r0[j], r1[j], r1[i])
            b.bm.faces.new(tuple(reversed(q)) if inside else q)
    b._finish_prim(color, material, smooth)
    return b


def round_path(points, radius, steps=4):
    """Replaces each corner of a polyline by a smooth bend of about `radius`."""
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    for k in range(1, len(pts) - 1):
        a, p, c = pts[k - 1], pts[k], pts[k + 1]
        d1, d2 = (p - a), (c - p)
        l1, l2 = d1.length, d2.length
        d1.normalize()
        d2.normalize()
        turn = math.acos(max(-1.0, min(1.0, d1.dot(d2))))
        if turn < 1e-3:
            out.append(p)
            continue
        t = min(radius * math.tan(turn / 2), l1 * 0.5, l2 * 0.5)
        s, e = p - d1 * t, p + d2 * t
        for i in range(steps + 1):
            u = i / steps
            out.append(s * (1 - u) ** 2 + p * (2 * u * (1 - u)) + e * (u * u))
    out.append(pts[-1])
    return out


def tube(b, path, r, color="grey", seg=12, bend=None, steps=4, caps=False, smooth=True, material=C.MAT_PALETTE):
    """A pipe through `path` with rounded corners (`bend` radius) and parallel-transported rings, so it
    never twists or pinches (unlike Builder.tube at sharp corners)."""
    pts = round_path(path, bend, steps) if bend else [Vector(p) for p in path]
    pts = [p for k, p in enumerate(pts) if k == 0 or (p - pts[k - 1]).length > 1e-5]
    n = len(pts)
    tangents = [(pts[min(k + 1, n - 1)] - pts[max(k - 1, 0)]).normalized() for k in range(n)]
    t0 = tangents[0]
    u = t0.cross(Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))).normalized()
    angles = [2 * math.pi * i / seg for i in range(seg)]
    b._begin()
    rings, prev = [], t0
    for p, t in zip(pts, tangents):
        u = prev.rotation_difference(t) @ u
        u = (u - t * u.dot(t)).normalized()
        v = t.cross(u)
        prev = t
        rings.append([b.bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * r) for a in angles])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            b.bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    if caps:
        b.bm.faces.new(list(reversed(rings[0])))
        b.bm.faces.new(rings[-1])
    b._finish_prim(color, material, smooth)
    return b


def _area(poly):
    return 0.5 * sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]))


def _clip(poly, x0, x1, y0, y1):
    """Sutherland-Hodgman clip of a convex polygon to an axis-aligned rectangle."""
    def edge(pts, inside, cut):
        out = []
        for i, cur in enumerate(pts):
            prev = pts[i - 1]
            if inside(cur):
                if not inside(prev):
                    out.append(cut(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(cut(prev, cur))
        return out

    def at_x(xc):
        return lambda p, q: (xc, p[1] + (q[1] - p[1]) * (xc - p[0]) / (q[0] - p[0]))

    def at_y(yc):
        return lambda p, q: (p[0] + (q[0] - p[0]) * (yc - p[1]) / (q[1] - p[1]), yc)

    for inside, cut in ((lambda p: p[0] >= x0, at_x(x0)), (lambda p: p[0] <= x1, at_x(x1)),
                        (lambda p: p[1] >= y0, at_y(y0)), (lambda p: p[1] <= y1, at_y(y1))):
        if len(poly) < 3:
            return []
        poly = edge(poly, inside, cut)
    return poly


def hazard(b, length, height, loc, face="front", depth=0.02, stripe=None, colors=("safety_yellow", "black"),
           bevel=0.004, base=True):
    """A hazard-striped plate: its back face centred on `loc` in the plane of `face` (a FACE name or a
    rotation), `length` along the face's horizontal axis, `height` along its vertical axis, 45 degree
    stripes. base=False skips the dark backing plate (stripes over an existing dark surface)."""
    F = Frame(loc, face)
    if base:
        b.box((length, height, depth), F.p(0, 0, depth / 2), colors[1], rot=F.r(), bevel=bevel)
    w = stripe or max(min(height * 0.9, length / 5), 0.015)
    e = bevel + 0.002
    u = -length / 2 - height
    while u < length / 2:
        poly = [(u, -height / 2), (u + w, -height / 2), (u + w + height, height / 2), (u + height, height / 2)]
        poly = _clip(poly, -length / 2 + e, length / 2 - e, -height / 2 + e, height / 2 - e)
        if len(poly) >= 3 and _area(poly) > 1e-6:
            b.prism(poly, 0.004, F.p(0, 0, (depth if base else 0) - 0.001), colors[0], rot=F.r())
        u += 2 * w
    return b


def striped_band(b, radius, z0, height, loc=(0, 0, 0), rot=(0, 0, 0), n=16, thick=0.02, slant=None,
                 colors=("safety_yellow", "black")):
    """A hazard-striped ring around a cylinder of `radius` (local Z axis), from z0 up `height`."""
    m = C._matrix(loc, _rot(rot))
    sl = (2 * math.pi / n) * 0.8 if slant is None else slant
    ro, ri = radius + thick, radius - 0.01
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n

        def v(r, a, z):
            return b.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), z)))
        b._begin()
        z1 = z0 + height
        ob0, ob1, ot1, ot0 = v(ro, a0, z0), v(ro, a1, z0), v(ro, a1 + sl, z1), v(ro, a0 + sl, z1)
        ib0, ib1, it1, it0 = v(ri, a0, z0), v(ri, a1, z0), v(ri, a1 + sl, z1), v(ri, a0 + sl, z1)
        b.bm.faces.new((ob0, ob1, ot1, ot0))
        b.bm.faces.new((ot0, ot1, it1, it0))
        b.bm.faces.new((ob1, ob0, ib0, ib1))
        b._finish_prim(colors[i % 2], C.MAT_PALETTE, False)
    return b


def bolt_ring(b, n, ring_r, loc, rot=(0, 0, 0), r=0.03, h=0.025, color="steel_dark", phase=0.5, seg=6):
    """n hex bolt heads on a circle in the local XY plane, sticking out along local +Z."""
    F = Frame(loc, rot)
    for i in range(n):
        a = 2 * math.pi * (i + phase) / n
        cyl(b, r, h, F.p(ring_r * math.cos(a), ring_r * math.sin(a), 0), color, rot=F.r(), seg=seg, base=True,
            smooth=False)
    return b


def bolts_grid(b, points, loc, face="front", r=0.022, h=0.018, color="steel_dark"):
    """Hex bolt heads at the local (x, y) `points` of a face."""
    F = Frame(loc, face)
    for x, y in points:
        cyl(b, r, h, F.p(x, y, 0), color, rot=F.r(), seg=6, base=True, smooth=False)
    return b


def corners(w, h, inset):
    return [(sx * (w / 2 - inset), sy * (h / 2 - inset)) for sx in (-1, 1) for sy in (-1, 1)]


def flange(b, r, thick, loc, rot=(0, 0, 0), color="steel", nbolts=6, bolt_color="steel_dark", seg=16, side=1):
    """A bolted flange disc along local Z; the bolt heads stand on its +Z (side=1) or -Z face."""
    F = Frame(loc, rot)
    cyl(b, r, thick, F.p(), color, rot=F.r(), seg=seg, bevel=min(0.015, thick * 0.3))
    if nbolts:
        bolt_ring(b, nbolts, r * 0.78, F.p(0, 0, side * thick / 2), F.r() if side > 0 else F.r(180, 0, 0),
                  r=max(0.015, r * 0.1), h=max(0.012, thick * 0.45), color=bolt_color)
    return b


def valve_wheel(name, radius, loc, rot=(0, 0, 0), parent=None, color="alarm_red", spokes=4, tube_r=None,
                hub="red_dark", knob=True):
    """A hand wheel as its own object, pivot at its centre, spinning about its local Z (= `rot`'s Z)."""
    w = C.Builder(name)
    F = Frame(loc, rot)
    t = tube_r or max(0.018, radius * 0.11)
    w.torus(radius, t, F.p(), color, rot=F.r(), segments=14, sides=6)
    cyl(w, radius * 0.22, t * 2.8, F.p(), hub, rot=F.r(), seg=10, bevel=0.008)
    for i in range(spokes):
        a = 360.0 * i / spokes + 45
        ra = math.radians(a)
        w.box((radius, t * 1.2, t * 1.2), F.p(math.cos(ra) * radius / 2, math.sin(ra) * radius / 2, 0), color,
              rot=F.r(0, 0, a))
    if knob:  # a spinner handle on the rim
        cyl(w, t * 0.9, t * 2.4, F.p(radius * 0.7071, radius * 0.7071, t * 0.6), "black", rot=F.r(), seg=8,
            base=True, bevel=0.005)
    return w.finish(pivot=loc, parent=parent)


def gauge(b, r, loc, face="front", angle=-35, rim="steel_dark", dial="off_white", needle="black"):
    """A round dial with a red zone and a needle (angle in degrees, 0 = up, positive = anticlockwise)."""
    F = Frame(loc, face)
    cyl(b, r, 0.05, F.p(), rim, rot=F.r(), seg=14, base=True, bevel=min(0.012, r * 0.1))
    cyl(b, r * 0.8, 0.012, F.p(0, 0, 0.044), dial, rot=F.r(), seg=14, base=True)
    b.box((r * 0.34, r * 0.13, 0.006), F.p(r * 0.44, r * 0.44, 0.058), "alarm_red", rot=F.r(0, 0, -45))
    a = math.radians(angle)
    b.box((r * 0.1, r * 0.72, 0.01), F.p(-math.sin(a) * r * 0.28, math.cos(a) * r * 0.28, 0.062), needle,
          rot=F.r(0, 0, angle))
    cyl(b, r * 0.12, 0.02, F.p(0, 0, 0.056), needle, rot=F.r(), seg=8, base=True)
    return b


def lamp(b, r, loc, face="front", color="rad_green", housing="steel_dark"):
    """A small emissive indicator dome on a dark bezel."""
    F = Frame(loc, face)
    cyl(b, r * 1.35, 0.02, F.p(), housing, rot=F.r(), seg=10, base=True)
    b.sphere(r, F.p(0, 0, 0.018), color, scale=(1, 1, 0.65), rot=F.r(), segments=10, rings=5,
             material=C.MAT_EMISSIVE)
    return b


def icon(b, points, depth, loc, face="front", color="black", scale=1.0, spin=0.0, offset=(0, 0),
         material=C.MAT_PALETTE):
    """A flat relief shape: polygon `points` (any winding, may be concave) scaled, turned by `spin`
    degrees and moved by `offset` in the face plane, standing `depth` out of the face."""
    s, c = math.sin(math.radians(spin)), math.cos(math.radians(spin))
    pts = [(offset[0] + (x * c - y * s) * scale, offset[1] + (x * s + y * c) * scale) for x, y in points]
    if _area(pts) < 0:
        pts.reverse()
    F = Frame(loc, face)
    b.prism(pts, depth, F.p(), color, rot=F.r(), material=material)
    return b


# Icon shapes, in a unit box centred on the origin.
BOLT = [(-0.05, 0.5), (0.3, 0.5), (0.07, 0.08), (0.28, 0.08), (-0.22, -0.5), (-0.03, -0.05), (-0.26, -0.05)]


def trefoil_blade(i, r_in=0.18, r_out=0.5, steps=4):
    a = math.radians(90 + 120 * i)
    outer = [(r_out * math.cos(a - math.radians(30) + math.radians(60) * k / steps),
              r_out * math.sin(a - math.radians(30) + math.radians(60) * k / steps)) for k in range(steps + 1)]
    inner = [(r_in * math.cos(a + math.radians(30) - math.radians(60) * k / 2),
              r_in * math.sin(a + math.radians(30) - math.radians(60) * k / 2)) for k in range(3)]
    return outer + inner


def trefoil(b, size, loc, face="front", color="black", plate="safety_yellow", depth=0.008):
    """The radiation sign: a square plate with the three-bladed trefoil."""
    F = Frame(loc, face)
    b.box((size, size, depth), F.p(0, 0, depth / 2), plate, rot=F.r(), bevel=depth * 0.4)
    for i in range(3):
        icon(b, trefoil_blade(i), 0.004, F.p(0, 0, depth), F.r(), color, scale=size * 0.9)
    cyl(b, size * 0.09, 0.004, F.p(0, 0, depth), color, rot=F.r(), seg=10, base=True, smooth=False)
    return b


def danger_sign(b, size, loc, face="front", depth=0.01):
    """A yellow warning triangle with a black lightning bolt, on a black edge."""
    F = Frame(loc, face)
    tri = [(-0.5, -0.43), (0.5, -0.43), (0.0, 0.45)]
    icon(b, tri, depth, F.p(), F.r(), "black", scale=size)
    icon(b, tri, 0.004, F.p(0, 0, depth), F.r(), "safety_yellow", scale=size * 0.8, offset=(0, -size * 0.02))
    icon(b, BOLT, 0.004, F.p(0, 0, depth + 0.004), F.r(), "black", scale=size * 0.45, offset=(0, -size * 0.07))
    return b


def louvre(b, w, h, loc, face="front", n=4, color="steel_dark", frame="grey_dark", depth=0.03):
    """A vent panel: a frame with n slanted slats."""
    F = Frame(loc, face)
    b.box((w, h, depth * 0.5), F.p(0, 0, depth * 0.25), "black", rot=F.r())
    t = min(0.04, h * 0.12)
    for sx in (-1, 1):
        b.box((t, h, depth), F.p(sx * (w - t) / 2, 0, depth / 2), frame, rot=F.r(), bevel=0.006)
    for sy in (-1, 1):
        b.box((w - 2 * t, t, depth), F.p(0, sy * (h - t) / 2, depth / 2), frame, rot=F.r(), bevel=0.006)
    pitch = (h - 2 * t) / n
    for i in range(n):
        y = -h / 2 + t + pitch * (i + 0.5)
        b.box((w - 2 * t, pitch * 0.9, 0.012), F.p(0, y, depth * 0.55), color, rot=F.r(-35, 0, 0))
    return b


def station_mounts(b, front_y=-0.96, side_x=0.95, plate="steel_dark", side_z=(0.1, 0.56)):
    """The flat plates of a station machine: the repair panel plate on the front (face at y = -1.0)
    with a frame, and the junction-box plates on both sides (faces at x = +-1.0)."""
    d = -1.0 - front_y
    b.box((0.84, -d, 0.6), (0, (front_y - 1.0) / 2, 1.0), plate, bevel=0.008)
    for sx in (-1, 1):
        b.box((0.035, 0.035 - d, 0.66), (sx * 0.4375, front_y - 0.0175 + d / 2, 1.0), "grey_dark", bevel=0.006)
    for sz in (-1, 1):
        b.box((0.91, 0.035 - d, 0.035), (0, front_y - 0.0175 + d / 2, 1.0 + sz * 0.3125), "grey_dark", bevel=0.006)
    z0, z1 = side_z
    dx = 1.0 - side_x
    for sx in (-1, 1):
        b.box((dx, 0.6, z1 - z0), (sx * (side_x + dx / 2), 0, (z0 + z1) / 2), plate, bevel=0.006)
        bolts_grid(b, corners(0.6, z1 - z0, 0.035), (sx * 1.0, 0, (z0 + z1) / 2), "right" if sx > 0 else "left",
                   r=0.016, h=0.008)
    return b


# --- Station machines --------------------------------------------------------------------------------

def _machine_rods():
    b = C.Builder("MachineRods")
    # Plinth with hazard stripes all round.
    b.box((1.96, 1.96, 0.12), (0, 0, 0), "black", base=True, bevel=0.015)
    for face, loc in (("front", (0, -0.98, 0.06)), ("back", (0, 0.98, 0.06)),
                      ("left", (-0.98, 0, 0.06)), ("right", (0.98, 0, 0.06))):
        hazard(b, 1.9, 0.09, loc, face, depth=0.012, stripe=0.08)
    # Cabinet, corner trims and lid.
    b.box((1.9, 1.84, 1.36), (0, -0.04, 0.12), "steel", base=True, bevel=0.035)
    for sx in (-1, 1):
        for y in (-0.94, 0.86):
            b.box((0.1, 0.1, 1.36), (sx * 0.93, y, 0.12), "steel_dark", base=True, bevel=0.02)
    b.box((1.98, 1.94, 0.09), (0, -0.04, 1.48), "steel_light", base=True, bevel=0.03)
    station_mounts(b, side_z=(0.13, 0.56))
    # Front: two gauges, a row of indicator lamps, vents, the radiation sign.
    gauge(b, 0.17, (-0.66, -0.96, 1.12), angle=40)
    gauge(b, 0.17, (0.66, -0.96, 1.12), angle=-20)
    for i, col in enumerate(("rad_green", "safety_yellow", "alarm_red", "rad_green")):
        lamp(b, 0.03, (-0.27 + 0.18 * i, -0.96, 1.39), color=col)
    for sx in (-1, 1):
        louvre(b, 0.56, 0.34, (sx * 0.6, -0.96, 0.42), n=4)
    trefoil(b, 0.24, (0, -0.96, 0.42))
    # Sides: stiffener ribs.
    for sx in (-1, 1):
        for y in (-0.5, 0.0, 0.5):
            b.box((0.05, 0.08, 0.78), (sx * 0.96, y, 0.64), "steel_dark", base=True, bevel=0.012)
    # Top: the rod-position tubes (emissive columns at different levels in glass).
    b.box((1.84, 0.46, 0.1), (0, 0.12, 1.57), "steel_dark", base=True, bevel=0.025)
    levels = (0.30, 0.12, 0.22, 0.34, 0.08, 0.26)
    for i, lv in enumerate(levels):
        x = -0.75 + 0.3 * i
        cyl(b, 0.115, 0.06, (x, 0.12, 1.67), "steel_light", seg=12, base=True, bevel=0.012)
        cyl(b, 0.085, 0.36, (x, 0.12, 1.73), "glass", seg=12, base=True, material=C.MAT_GLASS)
        cyl(b, 0.06, lv, (x, 0.12, 1.73), "rad_green", seg=10, base=True, material=C.MAT_EMISSIVE)
        cyl(b, 0.105, 0.06, (x, 0.12, 2.09), "steel_light", seg=12, base=True, bevel=0.012)
        cyl(b, 0.04, 0.05, (x, 0.12, 2.15), "steel_dark", seg=8, base=True)
    # Cable conduits out of the back.
    for x in (-0.45, 0.45):
        C_ = (x, 0.88, 0.9)
        tube(b, [C_, (x, 0.96, 0.9), (x, 0.96, 0.0)], 0.05, "grey_dark", seg=8, bend=0.1)
    return b.finish()


def _machine_pumps():
    b = C.Builder("MachinePumps")
    # Skid frame and the two end plates that carry the side mounts.
    b.box((1.96, 1.9, 0.16), (0, 0.02, 0), "steel_dark", base=True, bevel=0.02)
    for x in (-0.6, 0.0, 0.6):
        b.box((0.08, 1.9, 0.04), (x, 0.02, 0.16), "grey_dark", base=True)
    for sx in (-1, 1):
        b.box((0.06, 0.8, 0.62), (sx * 0.95, 0.05, 0.0), "steel", base=True, bevel=0.012)
        hazard(b, 0.06, 0.6, (sx * 0.95, -0.35, 0.31), "front", depth=0.01, stripe=0.05)
    # Motor (teal, axis along X) with cooling fins, end bell and feet.
    my, mz = 0.32, 0.86
    cyl(b, 0.44, 1.0, (-0.36, my, mz), "teal", rot=(0, 90, 0), seg=18, bevel=0.03)
    for i in range(5):
        cyl(b, 0.47, 0.05, (-0.76 + 0.18 * i, my, mz), "teal_dark", rot=(0, 90, 0), seg=18)
    b.sphere(0.4, (-0.86, my, mz), "teal_dark", scale=(0.35, 1, 1), segments=14, rings=7)
    for x in (-0.7, -0.05):
        b.box((0.16, 0.7, 0.32), (x, my, 0.16), "steel_dark", base=True, bevel=0.015)
    b.box((0.36, 0.3, 0.2), (-0.4, my, mz + 0.43), "teal_dark", base=True, bevel=0.02)
    tube(b, [(-0.22, my, mz + 0.53), (-0.1, my, mz + 0.53), (-0.1, 0.9, mz + 0.53), (-0.1, 0.9, 0.16)], 0.035,
         "grey_dark", seg=8, bend=0.08)
    # Coupling guard and the pump volute (blue) with its pipes out of the back.
    b.box((0.24, 0.5, 0.52), (0.24, my, mz - 0.26), "orange", base=True, bevel=0.03)
    vx = 0.6
    cyl(b, 0.5, 0.42, (vx, my - 0.05, 0.72), "blue", rot=(0, 90, 0), seg=18, bevel=0.04)
    cyl(b, 0.3, 0.1, (vx + 0.24, my - 0.05, 0.72), "blue_dark", rot=(0, 90, 0), seg=14, bevel=0.015)
    bolt_ring(b, 8, 0.42, (vx + 0.21, my - 0.05, 0.72), (0, 90, 0), r=0.025, h=0.02)
    b.box((0.3, 0.6, 0.28), (vx, my - 0.05, 0.16), "steel_dark", base=True, bevel=0.015)
    # Discharge: up from the volute top then back; suction: in low from the back.
    tube(b, [(vx, my, 1.1), (vx, my, 1.6), (vx, 0.96, 1.6)], 0.16, "pipe_green", seg=14, bend=0.25)
    flange(b, 0.23, 0.05, (vx, 0.95, 1.6), (90, 0, 0), "pipe_green_light", nbolts=6, side=1)
    flange(b, 0.23, 0.05, (vx, my, 1.12), (0, 0, 0), "pipe_green_light", nbolts=6)
    tube(b, [(vx, 0.6, 0.52), (vx, 0.97, 0.52)], 0.14, "pipe_green", seg=14)
    flange(b, 0.21, 0.05, (vx, 0.95, 0.52), (90, 0, 0), "pipe_green_light", nbolts=6, side=1)
    gauge(b, 0.1, (vx - 0.17, 0.62, 1.6), "left", angle=25)
    # Front control box with the repair panel plate.
    b.box((0.92, 0.3, 1.36), (0, -0.81, 0.0), "steel", base=True, bevel=0.03)
    b.box((0.98, 0.34, 0.06), (0, -0.8, 1.36), "steel_dark", base=True, bevel=0.02)
    station_mounts(b, side_z=(0.1, 0.56))
    for i, col in enumerate(("rat_green", "alarm_red")):
        lamp(b, 0.035, (-0.12 + 0.24 * i, -0.96, 1.36 - 0.0), "front", color=col)
    louvre(b, 0.6, 0.36, (0, -0.96, 0.38), n=4)
    return b.finish()


def _machine_valves():
    b = C.Builder("MachineValves")
    b.box((2.0, 1.9, 0.1), (0, 0.0, 0), "steel_dark", base=True, bevel=0.015)
    # Wide base (carries the side mounts), the manifold block on it, a top deck.
    b.box((1.92, 1.8, 0.52), (0, 0.0, 0.1), "grey_dark", base=True, bevel=0.03)
    b.box((1.6, 1.6, 0.72), (0, -0.16, 0.62), "pipe_green", base=True, bevel=0.04)
    b.box((1.66, 1.66, 0.06), (0, -0.16, 1.34), "pipe_green_light", base=True, bevel=0.02)
    station_mounts(b, front_y=-0.96, side_x=0.96, side_z=(0.12, 0.56))
    hazard(b, 1.5, 0.08, (0, -0.9, 0.5), "front", depth=0.01, stripe=0.07)
    # Header pipe across the top between two valve bodies; the wheels face +-X.
    hz, hy = 1.62, 0.12
    cyl(b, 0.2, 0.9, (0, hy, hz), "pipe_green", rot=(0, 90, 0), seg=16)
    for sx in (-1, 1):
        flange(b, 0.27, 0.06, (sx * 0.42, hy, hz), (0, 90, 0), "pipe_green_light", nbolts=6, side=-sx)
        b.sphere(0.26, (sx * 0.6, hy, hz), "steel", scale=(0.85, 1, 1.05), segments=14, rings=7)
        cyl(b, 0.12, 0.12, (sx * 0.8, hy, hz), "steel_dark", rot=(0, 90, 0), seg=12, bevel=0.015)
        cyl(b, 0.03, 0.16, (sx * 0.88, hy, hz), "silver", rot=(0, 90, 0), seg=8)
        # Downcomer from each valve body into the deck.
        cyl(b, 0.15, 0.32, (sx * 0.6, hy, 1.34), "pipe_green", seg=14, base=True)
        flange(b, 0.21, 0.05, (sx * 0.6, hy, 1.42), (0, 0, 0), "pipe_green_light", nbolts=6)
    # Gauge on a stem at the header centre, flow arrows.
    cyl(b, 0.025, 0.2, (0, hy, hz + 0.18), "silver", seg=8, base=True)
    gauge(b, 0.13, (0, hy - 0.05, hz + 0.42), "front", angle=-30)
    b.box((0.1, 0.1, 0.1), (0, hy, hz + 0.33), "steel_dark", bevel=0.01)
    # Pipes out of the back into the floor.
    for x in (-0.45, 0.45):
        tube(b, [(x, 0.6, 1.0), (x, 0.93, 1.0), (x, 0.93, 0.1)], 0.13, "pipe_green", seg=14, bend=0.22)
        flange(b, 0.19, 0.05, (x, 0.66, 1.0), (90, 0, 180), "pipe_green_light", nbolts=6, side=1)
    # Front lamp row above the panel.
    for i, col in enumerate(("rat_green", "safety_yellow", "alarm_red")):
        lamp(b, 0.03, (-0.18 + 0.18 * i, -0.96, 1.42 - 0.08), "front", color=col)
    root = b.finish()
    valve_wheel("Wheel1", 0.3, (-0.9, hy, hz), (0, -90, 0), root, tube_r=0.034)
    valve_wheel("Wheel2", 0.3, (0.9, hy, hz), (0, 90, 0), root, tube_r=0.034)
    return root


def _machine_turbine():
    b = C.Builder("MachineTurbine")
    b.box((2.0, 1.9, 0.1), (0, 0.0, 0), "charcoal", base=True, bevel=0.015)
    b.box((1.9, 1.8, 1.72), (0, -0.06, 0.1), "orange", base=True, bevel=0.045)
    for sx in (-1, 1):
        for y in (-0.94, 0.82):
            b.box((0.09, 0.09, 1.72), (sx * 0.93, y, 0.1), "orange_dark", base=True, bevel=0.02)
    b.box((1.98, 1.9, 0.08), (0, -0.06, 1.82), "orange_dark", base=True, bevel=0.03)
    station_mounts(b, side_z=(0.12, 0.56))
    # Big dial above the panel.
    b.box((0.78, 0.04, 0.5), (0, -0.98, 1.57), "orange_dark", bevel=0.015)
    gauge(b, 0.22, (0, -1.0, 1.57), angle=-50, rim="black")
    # Two small levers on the upper right in a slotted plate.
    b.box((0.36, 0.04, 0.42), (0.68, -0.98, 1.36), "charcoal", bevel=0.012)
    for i, x in enumerate((0.6, 0.76)):
        b.box((0.035, 0.03, 0.3), (x, -1.0, 1.36), "black")
        tilt = 25 if i == 0 else -15
        F = Frame((x, -1.0, 1.36 - 0.02 * i), (tilt, 0, 0))
        b.box((0.03, 0.03, 0.2), F.p(0, 0, 0.1), "steel_light", rot=F.r())
        b.sphere(0.045, F.p(0, 0, 0.22), "alarm_red" if i == 0 else "black", segments=10, rings=5)
    # Left: a speed readout with lamps.
    b.box((0.36, 0.04, 0.42), (-0.68, -0.98, 1.36), "charcoal", bevel=0.012)
    b.box((0.26, 0.02, 0.12), (-0.68, -1.0, 1.46), "screen_green", material=C.MAT_EMISSIVE)
    for i, col in enumerate(("rat_green", "safety_yellow", "alarm_red")):
        lamp(b, 0.028, (-0.78 + 0.1 * i, -1.0, 1.26), color=col)
    for sx in (-1, 1):
        louvre(b, 0.52, 0.4, (sx * 0.62, -0.96, 0.42), n=4, color="orange_dark", frame="charcoal")
    # Flyball governor on the lid.
    gx, gy = 0.0, 0.25
    cyl(b, 0.2, 0.08, (gx, gy, 1.9), "charcoal", seg=14, base=True, bevel=0.015)
    cyl(b, 0.03, 0.3, (gx, gy, 1.98), "silver", seg=8, base=True)
    cyl(b, 0.07, 0.05, (gx, gy, 2.12), "steel_dark", seg=10, base=True)
    cyl(b, 0.05, 0.04, (gx, gy, 2.26), "steel_dark", seg=10, base=True)
    for sx in (-1, 1):
        F = Frame((gx, gy, 2.27), (0, sx * 125, 0))
        b.box((0.025, 0.025, 0.2), F.p(0, 0, 0.1), "silver", rot=F.r())
        b.sphere(0.07, F.p(0, 0, 0.21), "steel_light", segments=10, rings=6)
    # Back: a gearbox with a big gear disc.
    cyl(b, 0.42, 0.12, (0.0, 0.84, 1.15), "orange_dark", rot=(90, 0, 0), seg=16, bevel=0.02)
    for i in range(12):
        a = 360.0 * i / 12
        F = Frame((0.0, 0.84, 1.15), (90, 0, 0))
        ra = math.radians(a)
        b.box((0.09, 0.1, 0.1), F.p(math.cos(ra) * 0.45, math.sin(ra) * 0.45, 0), "orange_dark", rot=F.r(0, 0, a))
    cyl(b, 0.12, 0.2, (0.0, 0.84, 1.15), "steel_dark", rot=(90, 0, 0), seg=10)
    return b.finish()


def _breaker_housing(b, loc):
    """A breaker's housing on the cabinet face (front at -Y), part of the cabinet mesh."""
    x, y, z = loc
    b.box((0.13, 0.05, 0.2), (x, y - 0.025, z), "grey_dark", bevel=0.012)
    b.box((0.04, 0.012, 0.13), (x, y - 0.054, z), "black")


def _breaker(name, loc, parent, handle="black", knob="alarm_red"):
    """A breaker's toggle: its own child object, hinge on X (housing: _breaker_housing)."""
    x, y, z = loc
    s = C.Builder(name)
    py = y - 0.07
    cyl(s, 0.022, 0.08, (x, py, z), "steel_dark", rot=(0, 90, 0), seg=8)
    s.box((0.035, 0.03, 0.13), (x, py, z + 0.065), handle, bevel=0.006)
    s.box((0.06, 0.045, 0.04), (x, py, z + 0.13), knob, bevel=0.01)
    return s.finish(pivot=(x, py, z), parent=parent)


def _machine_grid():
    b = C.Builder("MachineGrid")
    b.box((2.0, 1.9, 0.1), (0, 0.0, 0), "black", base=True, bevel=0.015)
    b.box((1.9, 1.7, 1.86), (0, -0.11, 0.1), "grey", base=True, bevel=0.04)
    b.box((1.98, 1.8, 0.08), (0, -0.11, 1.96), "steel", base=True, bevel=0.03)
    for sx in (-1, 1):
        for y in (-0.92, 0.7):
            b.box((0.08, 0.08, 1.86), (sx * 0.93, y, 0.1), "steel_dark", base=True, bevel=0.02)
    station_mounts(b, side_z=(0.12, 0.56))
    # Door seam and hinges (kept off the panel area).
    for z0, z1 in ((0.12, 0.66), (1.34, 1.94)):
        b.box((0.012, 0.012, z1 - z0), (0, -0.962, (z0 + z1) / 2), "grey_dark")
    for sx in (-1, 1):
        for z in (0.4, 1.7):
            b.box((0.03, 0.04, 0.14), (sx * 0.86, -0.97, z), "steel_dark", bevel=0.008)
    # Lightning bolt badge above the panel.
    cyl(b, 0.24, 0.02, (0, -0.96, 1.66), "black", rot=FACE["front"], seg=16, base=True, bevel=0.006)
    icon(b, BOLT, 0.012, (0, -0.98, 1.66), "front", "safety_yellow", scale=0.36)
    # Kick plate hazard stripe.
    hazard(b, 1.86, 0.1, (0, -0.96, 0.16), "front", depth=0.01, stripe=0.08)
    louvre(b, 0.6, 0.3, (-0.6, -0.96, 0.42), n=3)
    louvre(b, 0.6, 0.3, (0.6, -0.96, 0.42), n=3)
    # Side vents high up.
    for sx in (-1, 1):
        louvre(b, 0.8, 0.4, (sx * 0.95, -0.1, 1.45), "right" if sx > 0 else "left", n=4)
    # Insulators and a bus bar on the roof.
    for x in (-0.55, 0.0, 0.55):
        cyl(b, 0.1, 0.06, (x, 0.15, 2.04), "steel_dark", seg=10, base=True)
        for k in range(2):
            cyl(b, 0.085, 0.035, (x, 0.15, 2.1 + 0.045 * k), "off_white", seg=10, base=True, bevel=0.008)
        cyl(b, 0.04, 0.04, (x, 0.15, 2.18), "steel_light", seg=8, base=True)
    b.box((1.3, 0.05, 0.03), (0, 0.15, 2.2), "orange_dark")
    # 2 rows x 4 breakers, two per row on each side of the panel area.
    spots = [(x, -0.96, z) for z in (1.5, 1.2) for x in (-0.82, -0.6, 0.6, 0.82)]
    for loc in spots:
        _breaker_housing(b, loc)
    root = b.finish()
    for n, loc in enumerate(spots):
        _breaker("Switch%d" % (n + 1), loc, root)
    return root


def _fan_blades(name, radius, loc, rot, parent, n=5, color="sky", hub="steel_dark", pitch=25):
    """Fan blades as their own object, pivot at the hub, spinning about local Z of `rot`."""
    f = C.Builder(name)
    F = Frame(loc, rot)
    cyl(f, radius * 0.22, radius * 0.28, F.p(), hub, rot=F.r(), seg=12, bevel=0.015)
    f.sphere(radius * 0.2, F.p(0, 0, radius * 0.14), hub, scale=(1, 1, 0.7), rot=F.r(), segments=12, rings=5)
    for i in range(n):
        a = 360.0 * i / n
        ra = math.radians(a)
        blade = [(radius * 0.18, -radius * 0.12), (radius * 0.95, -radius * 0.2), (radius * 0.98, radius * 0.16),
                 (radius * 0.18, radius * 0.1)]
        G = F.sub((0, 0, 0), (0, 0, a)).sub((0, 0, -0.008), (pitch, 0, 0))
        f.prism(blade, 0.016, G.p(), color, rot=G.r(), bevel=0.004)
    return f.finish(pivot=loc, parent=parent)


def _machine_ventilation():
    b = C.Builder("MachineVentilation")
    b.box((2.0, 1.9, 0.1), (0, 0.0, 0), "steel_dark", base=True, bevel=0.015)
    b.box((1.9, 1.7, 2.0), (0, -0.11, 0.1), "sky", base=True, bevel=0.05)
    b.box((1.98, 1.78, 0.08), (0, -0.11, 2.1), "blue_dark", base=True, bevel=0.03)
    for sx in (-1, 1):
        for y in (-0.92, 0.7):
            b.box((0.09, 0.09, 2.0), (sx * 0.93, y, 0.1), "blue_dark", base=True, bevel=0.02)
    station_mounts(b, side_z=(0.12, 0.56))
    # Round fan opening on the front upper half: a dark well, a shroud ring, a grille.
    fz, fr = 1.72, 0.33
    F = Frame((0, -0.96, fz), "front")
    hollow(b, fr + 0.08, fr + 0.01, 0.14, F.p(0, 0, -0.1), "blue_dark", rot=F.r(), seg=20, base=True, inner="charcoal")
    cyl(b, fr + 0.02, 0.02, F.p(0, 0, -0.09), "black", rot=F.r(), seg=20, base=True)
    cyl(b, 0.06, 0.07, F.p(0, 0, -0.08), "steel_dark", rot=F.r(), seg=10, base=True)
    b.torus(fr * 0.62, 0.012, F.p(0, 0, 0.035), "silver", rot=F.r(), segments=16, sides=4, smooth=False)
    b.torus(fr + 0.02, 0.014, F.p(0, 0, 0.035), "silver", rot=F.r(), segments=20, sides=4, smooth=False)
    for a in (0, 90):
        b.box((2 * fr + 0.04, 0.02, 0.02), F.p(0, 0, 0.035), "silver", rot=F.r(0, 0, a))
    # Louvres on the sides and the lower front, a duct stub on the roof.
    for sx in (-1, 1):
        louvre(b, 1.0, 0.6, (sx * 0.95, -0.11, 1.35), "right" if sx > 0 else "left", n=5, color="blue_dark",
               frame="steel_dark")
        louvre(b, 0.5, 0.36, (sx * 0.62, -0.96, 0.42), n=4, color="blue_dark", frame="steel_dark")
    b.box((0.8, 0.8, 0.12), (0, 0.25, 2.18), "steel", base=True, bevel=0.02)
    b.box((0.7, 0.7, 0.02), (0, 0.25, 2.3), "black", base=True)
    # Air flow arrow decals and a filter warning stripe.
    for sx in (-1, 1):
        icon(b, [(-0.08, -0.05), (0.02, -0.05), (0.02, -0.11), (0.12, 0.0), (0.02, 0.11), (0.02, 0.05),
                 (-0.08, 0.05)], 0.006, (sx * 0.62, -0.96, 1.12), "front", "off_white", scale=1.4,
             spin=90)
    root = b.finish()
    _fan_blades("Fan", fr * 0.92, F.p(0, 0, -0.03), F.r(), root, n=5, color="steel_light")
    return root


# --- Plant props -------------------------------------------------------------------------------------

def _generator():
    """3 x 3 x 2.0: a stator drum along X on a skid, exciter at +X, shaft coupling at -X."""
    b = C.Builder("Generator")
    b.box((3.0, 2.6, 0.22), (0, 0, 0), "steel_dark", base=True, bevel=0.03)
    hazard(b, 2.9, 0.1, (0, -1.3, 0.11), "front", depth=0.012, stripe=0.1)
    hazard(b, 2.9, 0.1, (0, 1.3, 0.11), "back", depth=0.012, stripe=0.1)
    ax, az = 0.0, 1.05
    cyl(b, 0.85, 2.0, (-0.15, 0, az), "blue", rot=(0, 90, 0), seg=24, bevel=0.05)
    for x in (-1.0, -0.4, 0.2, 0.7):
        cyl(b, 0.89, 0.1, (x, 0, az), "blue_dark", rot=(0, 90, 0), seg=24, bevel=0.02)
    for sx in (-1, 1):  # end bells
        cyl(b, 0.75, 0.16, (-0.15 + sx * 1.06, 0, az), "steel", rot=(0, 90, 0), seg=24, bevel=0.04)
        b.box((0.3, 2.2, 0.62), (-0.15 + sx * 0.8, 0, 0.22), "steel_dark", base=True, bevel=0.03)
    # Exciter at +X, coupling at -X.
    cyl(b, 0.45, 0.36, (1.15, 0, az), "blue_dark", rot=(0, 90, 0), seg=18, bevel=0.03)
    cyl(b, 0.3, 0.12, (1.38, 0, az), "steel_light", rot=(0, 90, 0), seg=16, bevel=0.02)
    cyl(b, 0.16, 0.28, (-1.35, 0, az), "silver", rot=(0, 90, 0), seg=12)
    flange(b, 0.42, 0.1, (-1.44, 0, az), (0, -90, 0), "steel_light", nbolts=8)
    # Terminal box with conduits and a danger sign on top.
    b.box((0.9, 0.7, 0.24), (-0.1, 0, 1.76), "blue_dark", base=True, bevel=0.03)
    for x in (-0.35, -0.1, 0.15):
        cyl(b, 0.06, 0.08, (x, -0.2, 1.72), "steel_dark", seg=10, base=True)
    danger_sign(b, 0.2, (-0.1, -0.35, 1.88), "front")
    for sx in (-1, 1):
        tube(b, [(-0.1 + sx * 0.3, 0.2, 1.9), (-0.1 + sx * 0.3, 0.2, 1.98), (-0.1 + sx * 0.3, 1.25, 1.98),
                 (-0.1 + sx * 0.3, 1.25, 0.22)], 0.05, "grey_dark", seg=8, bend=0.15)
    # Name plate and lamps on the front of the drum.
    b.box((0.6, 0.04, 0.24), (-0.15, -0.84, 0.85), "steel_light", rot=(14, 0, 0), bevel=0.01)
    icon(b, BOLT, 0.01, (-0.15, -0.86, 0.845), (104, 0, 0), "safety_yellow", scale=0.2)
    return b.finish()


def _pump():
    """2.5 x 2.5 x 1.6: a vertical inline pump, volute low, motor on top, pipes to +-X."""
    b = C.Builder("Pump")
    b.box((2.0, 1.6, 0.16), (0, 0, 0), "grey_dark", base=True, bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((0.2, 0.2, 0.05), (sx * 0.85, sy * 0.65, 0.16), "steel_dark", base=True, bevel=0.01)
    # Pipes along X to the footprint edges, flanged.
    pz = 0.45
    tube(b, [(-1.24, 0, pz), (1.24, 0, pz)], 0.2, "pipe_green", seg=16)
    for sx in (-1, 1):
        flange(b, 0.3, 0.07, (sx * 1.2, 0, pz), (0, 90, 0), "pipe_green_light", nbolts=6, side=-sx)
        flange(b, 0.28, 0.06, (sx * 0.62, 0, pz), (0, 90, 0), "pipe_green_light", nbolts=6, side=sx)
        b.box((0.2, 0.36, pz - 0.16 - 0.18), (sx * 0.95, 0, 0.16), "steel_dark", base=True, bevel=0.015)
    # Volute (blue), lantern with an orange coupling guard, vertical teal motor with fins and fan cap.
    cyl(b, 0.52, 0.5, (0, 0, 0.2), "blue", seg=20, base=True, bevel=0.05)
    bolt_ring(b, 10, 0.44, (0, 0, 0.7), r=0.028, h=0.022)
    cyl(b, 0.28, 0.2, (0, 0, 0.7), "steel", seg=14, base=True, bevel=0.02)
    b.box((0.34, 0.5, 0.18), (0, -0.05, 0.71), "orange", base=True, bevel=0.025)
    cyl(b, 0.44, 0.08, (0, 0, 0.88), "teal_dark", seg=20, base=True, bevel=0.02)
    cyl(b, 0.4, 0.5, (0, 0, 0.96), "teal", seg=20, base=True, bevel=0.03)
    for i in range(10):
        a = 360.0 * i / 10
        ra = math.radians(a)
        b.box((0.06, 0.03, 0.46), (math.cos(ra) * 0.42, math.sin(ra) * 0.42, 1.21), "teal_dark", rot=(0, 0, a))
    cyl(b, 0.42, 0.1, (0, 0, 1.46), "teal_dark", seg=20, base=True, bevel=0.03)
    b.sphere(0.36, (0, 0, 1.53), "teal_dark", scale=(1, 1, 0.2), segments=16, rings=5)
    # Terminal box and a gauge on the outlet.
    b.box((0.26, 0.2, 0.26), (0, -0.5, 1.08), "teal_dark", base=True, bevel=0.02)
    tube(b, [(0, -0.6, 1.2), (0, -0.66, 1.2), (0, -0.66, 0.16)], 0.035, "grey_dark", seg=8, bend=0.06)
    cyl(b, 0.025, 0.22, (0.9, 0, pz + 0.18), "silver", seg=8, base=True)
    gauge(b, 0.1, (0.9, -0.05, pz + 0.44), "front", angle=20)
    danger_sign(b, 0.2, (0, -0.535, 0.45), "front")
    return b.finish()


def _transformer():
    """2.4 x 2.4 x 1.8 tank with radiator fins, three bushings on top (to 2.3)."""
    b = C.Builder("Transformer")
    b.box((2.0, 2.0, 0.16), (0, 0, 0), "steel_dark", base=True, bevel=0.03)
    hazard(b, 1.95, 0.1, (0, -1.0, 0.08), "front", depth=0.012, stripe=0.1)
    b.box((1.4, 1.5, 1.42), (0, 0, 0.16), "grey_light", base=True, bevel=0.05)
    b.box((1.5, 1.6, 0.1), (0, 0, 1.58), "grey", base=True, bevel=0.03)
    for z in (0.5, 1.1):
        b.box((1.44, 1.54, 0.05), (0, 0, z), "grey", bevel=0.015)
    # Radiator banks on both sides: headers and thin fins.
    for sx in (-1, 1):
        for z in (0.35, 1.4):
            cyl(b, 0.06, 1.2, (sx * 0.95, 0, z), "grey", rot=(90, 0, 0), seg=10)
        for i in range(8):
            y = -0.52 + 0.149 * i
            b.box((0.42, 0.03, 1.12), (sx * 0.92, y, 0.32), "grey_light", base=True, bevel=0.008)
        for z in (0.35, 1.4):
            for y in (-0.45, 0.45):
                b.box((0.2, 0.1, 0.1), (sx * 0.8, y, z), "grey", bevel=0.01)
    # Bushings: steel collar, ceramic sheds, terminal.
    for x in (-0.45, 0.0, 0.45):
        cyl(b, 0.12, 0.08, (x, -0.15, 1.68), "steel_dark", seg=12, base=True, bevel=0.015)
        for k in range(5):
            cyl(b, 0.1 - 0.008 * k, 0.05, (x, -0.15, 1.78 + 0.085 * k), "off_white", seg=12, base=True, bevel=0.012)
        cyl(b, 0.05, 0.4, (x, -0.15, 1.76), "white", seg=10, base=True)
        cyl(b, 0.05, 0.08, (x, -0.15, 2.16), "steel_light", seg=10, base=True, bevel=0.01)
        cyl(b, 0.02, 0.05, (x, -0.15, 2.24), "orange_dark", seg=8, base=True)
    # Cable box at the back and a danger sign on the front.
    b.box((0.9, 0.3, 0.1), (0, 0.5, 1.68), "grey", base=True, bevel=0.02)
    danger_sign(b, 0.42, (0, -0.75, 0.86), "front")
    gauge(b, 0.09, (0.5, -0.75, 1.3), "front", angle=10)
    return b.finish()


BUILDERS = {"rods": _machine_rods, "pumps": _machine_pumps, "valves": _machine_valves,
            "turbine": _machine_turbine, "grid": _machine_grid, "ventilation": _machine_ventilation,
            "generator": _generator, "pump": _pump, "transformer": _transformer}


def build(kind="rods"):
    return BUILDERS[kind]()


if __name__ == "__main__":
    a = C.args("machine", lambda p: p.add_argument("--kind", default="rods", choices=KINDS))
    C.reset()
    out = a.out if "--out" in sys.argv else os.path.join(C.GENERATED, dict((v["kind"], n) for n, v in ASSETS)[a.kind] + ".glb")
    C.export(out, [build(a.kind)])

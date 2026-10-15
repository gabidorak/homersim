"""Grandma's kitchen, for the end-of-match cinematics (client/outro/): the 1950s chrome toaster and its
slices, the breakfast things, the furniture, the wall pieces, and the town and the plant seen through
the window.

    blender -b -P tools/blender/kitchen.py -- [--only toaster,toast]

Origins at the base centre, front = -Y (Godot +Z), except the wall pieces (photo_frame, cat_clock,
calendar: origin where they hang, see each) and the ceiling lamp (origin at the ceiling).
Parts and markers the cinematic looks up by name:
  toaster       "Lever" (slides down along Z, pivot = its knob's centre in the up position), "Glow"
                (the heating elements, emissive), "Body" (chrome); empties "Slot1" (front) and "Slot2"
                (back) at the top centre of each slot
  toast_limp    "Middle" and "Top" (hinges along X, so the slice can fold over a slot's rim), under
                "Bottom"
  plate         empty "Surface" at the centre of its flat top
  butter_dish   "Butter" and "ButterBitten" (one shows)
  teacup        empty "Steam" over the tea
  photo_frame   (origin = the nail) empty "Picture": the photo's centre (the picture itself is a
                texture the cinematic renders)
  cat_clock     "Tail" (swings about Y), "Pupils" (slide along X), "HourHand", "MinuteHand" (turn
                about Y)
  ceiling_lamp  "Bulb" (emissive)
  match         "Flame" (emissive), the head at the top
  house, plant_building   "Windows" (emissive)
The dimensions the cinematic's physics depends on are constants here (TOASTER_*, TOAST_*, PLATE_*):
grandma.py imports them for her hand targets, and client/outro/ reads the markers.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import dressing as D  # noqa: E402
import machines as M  # noqa: E402

E, GL = C.MAT_EMISSIVE, C.MAT_GLASS

# --- Dimensions (m) ---------------------------------------------------------------------------------------

TOASTER_L, TOASTER_D, TOASTER_H = 0.28, 0.17, 0.185  # body: along X (the slots), Y, Z
TOASTER_FOOT = 0.012  # the body stands on four feet this tall
TOASTER_TOP = TOASTER_FOOT + TOASTER_H  # 0.197
SLOT_L, SLOT_W, SLOT_Y, SLOT_FLOOR = 0.15, 0.026, 0.034, 0.035  # slot length, width, centre |y|, floor z
LEVER_X = TOASTER_L / 2 + 0.04  # the knob's centre, out from the +X end (towards grandma's right hand: her
# palm presses it square without touching the toaster)...
LEVER_Y = 0.06  # ...towards the back (her side): she reaches it without leaning, her forearm behind the toaster
LEVER_UP = 0.15  # the knob's centre with the lever up
KNOB = (0.03, 0.05, 0.022)  # lever knob size (x out from the end, y, z)
TOAST_W, TOAST_H, TOAST_T = 0.104, 0.118, 0.014  # a slice: width (X), height (Z), thickness (Y)
TOAST_UP = 0.12  # a slice's bottom with the lever up (it sticks out of its slot)...
TOAST_DOWN = SLOT_FLOOR + 0.012  # ...and down (toasting: all in)
LEVER_TRAVEL = TOAST_UP - TOAST_DOWN  # the lever moves the slices' carriage
TOAST_LIMP_UP = 0.172  # the pale slices' bottom when they've crept up (the rats' ending): barely in
# The limp slice's hinges (heights on the slice): on its front face at the slot's rim, then just past
# the toaster's front face, so it folds flat over the top between the front slot and the front edge
# and hangs down in front (client/outro/outro.gd folds it 90 degrees at each).
LIMP_HINGES = (TOASTER_TOP - TOAST_LIMP_UP, TOASTER_TOP - TOAST_LIMP_UP + TOASTER_D / 2 - SLOT_Y - TOAST_T / 2 + 0.002)
PLATE_R, PLATE_SURFACE = 0.12, 0.01  # radius; the flat centre's height (the toast lands there)


def rbox(b, size, loc, color, radius, segments=3, rot=(0, 0, 0), material=C.MAT_PALETTE):
    """A box with rounded edges, smooth shaded."""
    b._begin()
    res = bmesh.ops.create_cube(b.bm, size=1.0, matrix=C._matrix(loc, rot, size))
    b._bevel(res["verts"], radius, segments)
    b._finish_prim(color, material, True)
    return b


def _apply_boolean(obj, cutter, operation="DIFFERENCE"):
    """Cuts `cutter` out of `obj` (exact solver; the new faces keep the cutter's colours) and deletes
    the cutter."""
    mod = obj.modifiers.new("cut", "BOOLEAN")
    mod.operation = operation
    mod.object = cutter
    mod.solver = "EXACT"
    if hasattr(mod, "material_mode"):
        mod.material_mode = "TRANSFER"
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj],
                                   selected_editable_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter)
    C.store_outline_normals(obj)
    return obj


# --- The toaster -------------------------------------------------------------------------------------------

def _toaster_body(b):
    """The chrome loaf: well rounded corners seen from above, a softer top edge (the slots' rims are
    flat, a limp slice lies on them)."""
    b._begin()
    size = (TOASTER_L, TOASTER_D, TOASTER_H)
    res = bmesh.ops.create_cube(b.bm, size=1.0, matrix=C._matrix((0, 0, TOASTER_FOOT + TOASTER_H / 2), (0, 0, 0), size))
    verts = res["verts"]
    vertical = [e for e in b.bm.edges if e.verts[0] in verts and e.verts[1] in verts
                and abs(e.verts[0].co.z - e.verts[1].co.z) > 0.01]
    bmesh.ops.bevel(b.bm, geom=vertical + list({v for e in vertical for v in e.verts}), offset=0.06,
                    offset_type="OFFSET", segments=5, profile=0.5, affect="EDGES", clamp_overlap=True)
    b._collect()
    for f in b.bm.faces:
        f.normal_update()
    new_verts = {v for f in b._new_faces for v in f.verts}
    flat = [e for e in b.bm.edges if e.verts[0] in new_verts and e.verts[1] in new_verts
            and abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-5 and len(e.link_faces) == 2
            and any(abs(f.normal.z) > 0.99 for f in e.link_faces)]
    bmesh.ops.bevel(b.bm, geom=flat + list({v for e in flat for v in e.verts}), offset=0.02, offset_type="OFFSET",
                    segments=3, profile=0.5, affect="EDGES", clamp_overlap=True)
    b._collect()
    b._new_faces = [f for f in b.bm.faces if f not in b._before]
    b._paint("silver", C.MAT_PALETTE, True)


def build_toaster(name="Toaster"):
    root_b = C.Builder(name)
    # Bakelite feet.
    for sx in (-1, 1):
        for sy in (-1, 1):
            root_b.cylinder(0.016, TOASTER_FOOT + 0.004, (sx * 0.1, sy * 0.055, 0), "black", base=True, segments=10)
    root = root_b.finish()
    # The chrome body, slots cut in it (dark inside), the lever's groove in the -X end.
    body_b = C.Builder("Body")
    _toaster_body(body_b)
    # Chrome trim: three "speed lines" along the front, a badge, the browning dial.
    for k in range(3):
        rbox(body_b, (0.16, 0.006, 0.006), (0.03, -TOASTER_D / 2 - 0.001, 0.05 + k * 0.016), "white", 0.002,
             segments=1)
    body = body_b.finish()
    body.parent = root
    cut_b = C.Builder("Cut")
    for sy in (-1, 1):
        cut_b.box((SLOT_L, SLOT_W, TOASTER_TOP - SLOT_FLOOR + 0.05), (0, sy * SLOT_Y, SLOT_FLOOR), "charcoal", base=True)
    cut_b.box((0.016, 0.012, LEVER_TRAVEL + 0.03), (TOASTER_L / 2 - 0.004, LEVER_Y, LEVER_UP - LEVER_TRAVEL - 0.015),
              "black",
              base=True)
    _apply_boolean(body, cut_b.finish())
    # The browning dial on the front, left (the lever is on the right end).
    dial = C.Builder("Dial")
    M.cyl(dial, 0.022, 0.016, (-0.095, -TOASTER_D / 2 - 0.004, 0.11), "brown_dark", rot=M.FACE["front"], seg=14,
          bevel=0.004, base=True)
    dial.box((0.004, 0.006, 0.018), (-0.095, -TOASTER_D / 2 - 0.02, 0.116), "cream")
    dial.finish().parent = root
    # The heating elements glowing inside each slot (orange when on: Art.set_glow).
    glow = C.Builder("Glow")
    for sy in (-1, 1):
        for side in (-1, 1):
            y = sy * SLOT_Y + side * (SLOT_W / 2 - 0.002)
            for k in range(5):
                z = SLOT_FLOOR + 0.02 + k * 0.027
                glow.box((SLOT_L - 0.012, 0.003, 0.004), (0, y, z), "orange", material=E)
        glow.box((SLOT_L - 0.01, SLOT_W - 0.004, 0.003), (0, sy * SLOT_Y, SLOT_FLOOR + 0.002), "orange_dark", material=E)
    glow.finish().parent = root
    # The lever: a bakelite knob on a stem in the groove (its own part, pivot at the knob's centre).
    lever = C.Builder("Lever")
    rbox(lever, KNOB, (LEVER_X, LEVER_Y, LEVER_UP), "black", 0.008)
    stem = LEVER_X - TOASTER_L / 2 + 0.008  # from inside the groove out to the knob
    lever.box((stem, 0.008, 0.008), (LEVER_X - stem / 2, LEVER_Y, LEVER_UP), "steel_dark")
    lever.finish(pivot=(LEVER_X, LEVER_Y, LEVER_UP), parent=root)
    for k, sy in enumerate((-1, 1)):
        C.empty("Slot%d" % (k + 1), (0, sy * SLOT_Y, TOASTER_TOP), root)
    return root


# --- Toast ---------------------------------------------------------------------------------------------------

def toast_outline(w=TOAST_W, h=TOAST_H):
    """A slice of bread seen face on (x, z), bottom centre at the origin: square below, a crown of two
    rounded lobes that overhang the sides a little, a soft dip between them. Counter-clockwise."""
    half = [(0.43, 0.0), (0.43, 0.48), (0.455, 0.58), (0.5, 0.67), (0.505, 0.77), (0.48, 0.86), (0.42, 0.93),
            (0.32, 0.985), (0.2, 1.0), (0.09, 0.975), (0.0, 0.955)]
    ring = half + [(-x, z) for x, z in reversed(half[1:-1])] + [(-0.43, 0.0)]
    ring = chaikin(ring, lambda p: p[1] < 0.01)  # round the corners, the bottom ones stay square
    pts = []
    for x, z in ring:  # (a point straight after its twin would make a degenerate edge)
        p = (x * w, z * h)
        if not pts or math.hypot(p[0] - pts[-1][0], p[1] - pts[-1][1]) > 1e-5:
            pts.append(p)
    return pts


def chaikin(ring, keep, iterations=2):
    """Rounds a closed polyline by corner cutting; points where keep(p) stay sharp corners."""
    for _ in range(iterations):
        out = []
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            out.append(a if keep(a) else (0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            if not keep(b):
                out.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        ring = out
    return ring


def _bitten(pts, centre, r, teeth=5):
    """The outline with a bite out of it: points inside the circle are replaced by a scalloped arc."""
    cx, cz = centre
    out = []
    n = len(pts)
    inside = [math.hypot(x - cx, z - cz) < r for x, z in pts]
    for i in range(n):
        if inside[i]:
            continue
        out.append(pts[i])
        j = (i + 1) % n
        if inside[j]:
            # Entering the bite: walk round the circle until the outline comes out again.
            k = j
            while inside[k]:
                k = (k + 1) % n
            a0 = math.atan2(pts[i][1] - cz, pts[i][0] - cx)
            a1 = math.atan2(pts[k][1] - cz, pts[k][0] - cx)
            while a1 > a0:
                a1 -= 2 * math.pi
            for m in range(1, teeth * 3):
                u = m / (teeth * 3)
                a = a0 + (a1 - a0) * u
                rr = r * (1.0 - 0.12 * abs(math.sin(math.pi * teeth * u)))
                out.append((cx + rr * math.cos(a), cz + rr * math.sin(a)))
    return out


def _slice(b, pts, face, crust, loc=(0, 0, 0), band=None):
    """A slice from its outline: the crust a prism along Y, the two faces a hair proud of it (inset
    from the crust). `band` (lo, hi): only that height range of it (a part of the limp slice)."""
    inset = [(x * 0.9, z * 0.9 + TOAST_H * 0.035) for x, z in pts]
    if band is not None:
        pts, inset = _clip_z(pts, *band), _clip_z(inset, *band)
    x0, y0, z0 = loc
    b.prism(pts, TOAST_T, (x0, y0 + TOAST_T / 2, z0), crust, rot=(90, 0, 0))
    if len(inset) >= 3:
        b.prism(inset, TOAST_T + 0.0012, (x0, y0 + TOAST_T / 2 + 0.0006, z0), face, rot=(90, 0, 0))


def build_toast(kind="golden", name="Toast"):
    b = C.Builder(name)
    pts = toast_outline()
    if kind == "bitten":
        pts = _bitten(pts, (-TOAST_W * 0.32, TOAST_H * 0.95), 0.042)  # (her right: she holds it by its left half)
    face, crust = ("bread", "crust_pale") if kind == "pale" else ("toast", "toast_dark")
    _slice(b, pts, face, crust)
    return b.finish()


def build_toast_limp(name="ToastLimp"):
    """An untoasted slice, floppy: three parts hinged along X so it can fold over a slot's rim.
    "Bottom" (to LIMP_HINGES[0] high), "Middle" (pivot on the slice's front face at that height),
    "Top" (pivot at LIMP_HINGES[1]). Each part is its slice of the outline."""
    pts = toast_outline()
    root = None
    parent = None
    bounds = [0.0] + list(LIMP_HINGES) + [TOAST_H + 0.01]
    for k, part in enumerate(("Bottom", "Middle", "Top")):
        lo, hi = bounds[k], bounds[k + 1]
        b = C.Builder(part if k else name)
        _slice(b, pts, "bread", "crust_pale", band=(lo, hi))
        pivot = (0, -TOAST_T / 2, lo) if k else (0, 0, 0)
        obj = b.finish(pivot=pivot, parent=parent)
        if root is None:
            root = obj
        parent = obj
    return root


def _clip_z(pts, lo, hi):
    """Sutherland-Hodgman clip of the outline to lo <= z <= hi."""
    def clip(poly, keep, inter):
        out = []
        for i in range(len(poly)):
            a, b = poly[i - 1], poly[i]
            if keep(b):
                if not keep(a):
                    out.append(inter(a, b))
                out.append(b)
            elif keep(a):
                out.append(inter(a, b))
        return out

    def at(z):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]), z)
    poly = clip(pts, lambda p: p[1] >= lo, at(lo))
    return clip(poly, lambda p: p[1] <= hi, at(hi))


# --- The plate ------------------------------------------------------------------------------------------------

def build_plate(name="Plate"):
    """A dinner plate: a flat centre (PLATE_SURFACE high) and a sloping rim with a blue band."""
    b = C.Builder(name)
    r_in = 0.085
    # (a lathe's faces look out where the profile climbs: these run outward along a top, so they flip)
    M.lathe(b, [(0.0, PLATE_SURFACE), (r_in, PLATE_SURFACE), (0.1, 0.014), (PLATE_R, 0.02), (PLATE_R + 0.003, 0.017)],
            "white", seg=32, inside=True)
    M.lathe(b, [(PLATE_R + 0.003, 0.017), (0.11, 0.006), (0.065, 0.004), (0.06, 0.0), (0.0, 0.0)], "off_white", seg=32,
            inside=True)
    M.lathe(b, [(0.103, 0.0153), (0.109, 0.0173)], "pastel_blue", seg=32, inside=True)
    root = b.finish()
    C.empty("Surface", (0, 0, PLATE_SURFACE), root)
    return root


# --- Breakfast things -----------------------------------------------------------------------------------

def build_butter_dish(name="ButterDish"):
    """A little china dish, a pat of butter (or the same pat with a rat's bite out of a corner) and a
    knife resting on the rim."""
    b = C.Builder(name)
    rbox(b, (0.17, 0.115, 0.012), (0, 0, 0.006), "white", 0.006, segments=2)
    rbox(b, (0.178, 0.123, 0.006), (0, 0, 0.0115), "pastel_blue", 0.004, segments=1)
    rbox(b, (0.15, 0.095, 0.004), (0, 0, 0.014), "white", 0.002, segments=1)
    M.tube(b, [(0.1, -0.035, 0.022), (0.03, -0.03, 0.03), (-0.05, -0.025, 0.035)], 0.0045, "cream", seg=6, caps=True)
    b.box((0.06, 0.016, 0.003), (-0.08, -0.022, 0.036), "silver", rot=(0, 8, -4), bevel=0.001)
    root = b.finish()
    full = C.Builder("Butter")
    rbox(full, (0.09, 0.05, 0.036), (0, 0, 0.016 + 0.018), "butter_pat", 0.008, segments=2)
    full.sphere(0.012, (0.01, 0.0, 0.054), "butter_pat", scale=(1.6, 0.8, 0.5), segments=10, rings=5)  # a curl
    full.finish().parent = root
    bitten = C.Builder("ButterBitten")
    rect = [(-0.045, -0.025), (0.045, -0.025), (0.045, 0.025), (-0.045, 0.025)]
    dense = []
    for (x0, y0), (x1, y1) in zip(rect, rect[1:] + rect[:1]):
        for k in range(8):
            dense.append((x0 + (x1 - x0) * k / 8, y0 + (y1 - y0) * k / 8))
    bitten.prism(_bitten(dense, (0.045, -0.025), 0.024, teeth=3), 0.036, (0, 0, 0.016), "butter_pat", bevel=0.004)
    bitten.finish().parent = root
    return root


def build_teacup(name="Teacup"):
    """A pink china teacup with a gold rim on its saucer, tea in it, a tea bag's tag hanging over the
    side; "Steam" marks where the steam rises."""
    b = C.Builder(name)
    M.lathe(b, [(0.0, 0.006), (0.05, 0.006), (0.07, 0.011), (0.078, 0.014)], "white", seg=24, inside=True)
    M.lathe(b, [(0.078, 0.014), (0.07, 0.006), (0.04, 0.0), (0.0, 0.0)], "pastel_blue", seg=24, inside=True)
    M.lathe(b, [(0.028, 0.008), (0.032, 0.012), (0.042, 0.03), (0.048, 0.05), (0.05, 0.062)], "pastel_pink", seg=20)
    M.lathe(b, [(0.05, 0.062), (0.047, 0.064)], "safety_yellow", seg=20)
    M.lathe(b, [(0.047, 0.064), (0.044, 0.05), (0.035, 0.03), (0.0, 0.028)], "white", seg=20)
    b.cylinder(0.0445, 0.002, (0, 0, 0.053), "tea", segments=20)
    b.torus(0.017, 0.006, (0.058, 0.0, 0.038), "pastel_pink", rot=(90, 0, 0), segments=12, sides=5)
    # The tea bag: a string over the rim, a tag hanging outside.
    M.tube(b, [(0.0, -0.01, 0.054), (0.0, -0.045, 0.066), (0.0, -0.052, 0.062), (0.0, -0.053, 0.035)], 0.0012, "white",
           seg=4)
    b.box((0.016, 0.003, 0.02), (0.0, -0.054, 0.026), "safety_yellow", bevel=0.001)
    root = b.finish()
    C.empty("Steam", (0, 0, 0.07), root)
    return root


# --- Wall pieces -------------------------------------------------------------------------------------------

PHOTO_W, PHOTO_H = 0.15, 0.2  # the picture inside the frame (the cinematic renders it)
PHOTO_CENTRE = (0.0, -0.022, -0.2)  # from the nail


def build_photo_frame(name="PhotoFrame"):
    """Grandma's favourite photo: a wooden frame with a cream mat and gilt corners, hanging by its wire
    from a brass nail. Origin = the nail (it tilts about it); the wall is the plane y = 0."""
    b = C.Builder(name)
    b.cylinder(0.006, 0.014, (0, -0.007, 0), "yellow_dark", rot=(90, 0, 0), segments=8)  # the nail
    cx, cy, cz = PHOTO_CENTRE
    w, h = PHOTO_W + 0.08, PHOTO_H + 0.08
    top = cz + h / 2
    for s in (-1, 1):
        M.tube(b, [(0, -0.008, -0.004), (s * 0.075, -0.008, top - 0.005)], 0.0012, "grey_dark", seg=4)
    rbox(b, (w, 0.022, h), (cx, -0.013, cz), "wood", 0.01, segments=2)
    rbox(b, (w - 0.035, 0.008, h - 0.035), (cx, -0.024, cz), "cream", 0.003, segments=1)
    for s in (-1, 1):  # gilt corners
        for t in (-1, 1):
            b.sphere(0.013, (cx + s * (w / 2 - 0.012), -0.026, cz + t * (h / 2 - 0.012)), "yellow_dark",
                     scale=(1, 0.5, 1), segments=8, rings=5)
    root = b.finish()
    C.empty("Picture", (cx, cy - 0.007, cz), root)
    return root


def build_cat_clock(name="CatClock"):
    """The cat clock: a black cat with the clock on its belly, eyes that look side to side and a tail
    that swings with the seconds. Origin at the centre of its back (the wall is the plane y = 0), at
    the height of the clock face's centre."""
    b = C.Builder(name)
    rbox(b, (0.125, 0.05, 0.21), (0, -0.025, -0.01), "black", 0.03)  # body
    b.cylinder(0.05, 0.006, (0, -0.052, 0.0), "white", rot=(90, 0, 0), segments=24)  # the clock face
    for k in range(12):
        a = math.radians(90 - 30 * k)
        big = k % 3 == 0
        b.box((0.006 if big else 0.004, 0.003, 0.012 if big else 0.007), (math.cos(a) * 0.04, -0.056, math.sin(a) * 0.04),
              "black", rot=(0, 90 - math.degrees(a), 0))
    for s in (-1, 1):  # white paws holding the clock
        b.sphere(0.02, (s * 0.06, -0.05, -0.05), "white", scale=(0.9, 0.7, 1.1), segments=10, rings=6)
    # Head: ears, big white eyes, a muzzle, a grin, whiskers; a gingham bow tie.
    rbox(b, (0.17, 0.06, 0.13), (0, -0.03, 0.16), "black", 0.04)
    for s in (-1, 1):
        b.prism([(-0.035, 0), (0.035, 0), (0.0, 0.06)], 0.04, (s * 0.055, -0.01, 0.2), "black", rot=(90, 0, s * -12))
        b.prism([(-0.02, 0.005), (0.02, 0.005), (0.0, 0.04)], 0.005, (s * 0.055, -0.052, 0.205), "rat_pink",
                rot=(90, 0, s * -12))
        b.sphere(0.03, (s * 0.04, -0.058, 0.172), "white", scale=(0.85, 0.35, 1.1), segments=12, rings=7)
        for k in (-1, 1):
            b.box((0.06, 0.003, 0.003), (s * 0.07, -0.064, 0.125 + k * 0.008), "white", rot=(0, s * k * -10, 0))
    b.sphere(0.03, (0, -0.06, 0.122), "white", scale=(1.4, 0.4, 0.8), segments=12, rings=6)
    b.sphere(0.009, (0, -0.072, 0.134), "rat_pink", segments=8, rings=5)
    M.tube(b, [(-0.026, -0.072, 0.118), (-0.012, -0.074, 0.11), (0.0, -0.074, 0.112), (0.012, -0.074, 0.11),
               (0.026, -0.072, 0.118)], 0.0025, "black", seg=4)
    for s in (-1, 1):
        b.prism([(0, 0), (0.035, -0.018), (0.035, 0.018)], 0.012, (0, -0.052, 0.088), "gingham", rot=(90, 0, 90 - 90 * s))
    b.sphere(0.009, (0, -0.064, 0.088), "gingham", segments=8, rings=5)
    root = b.finish()
    pupils = C.Builder("Pupils")
    for s in (-1, 1):
        pupils.sphere(0.012, (s * 0.04, -0.068, 0.168), "black", scale=(0.8, 0.4, 1.3), segments=10, rings=6)
    pupils.finish(pivot=(0, -0.068, 0.168), parent=root)
    for hand, length, width, angle, col in (("HourHand", 0.026, 0.006, 180, "black"),
                                            ("MinuteHand", 0.038, 0.004, 0, "black"),
                                            ("SecondHand", 0.042, 0.002, 30, "alarm_red")):
        h = C.Builder(hand)
        a = math.radians(angle)
        h.box((width, 0.002, length), (math.sin(a) * length / 2, -0.058, math.cos(a) * length / 2), col, rot=(0, angle, 0))
        if hand == "SecondHand":
            h.cylinder(0.005, 0.004, (0, -0.06, 0), "alarm_red", rot=(90, 0, 0), segments=8)
        h.finish(pivot=(0, -0.058, 0), parent=root)
    tail = C.Builder("Tail")
    pts = [(0.0, -0.02, -0.11), (0.0, -0.022, -0.16), (0.012, -0.022, -0.21), (0.03, -0.022, -0.25), (0.02, -0.022, -0.28)]
    M.tube(tail, pts, 0.01, "black", seg=8, bend=0.03, caps=True)
    tail.sphere(0.013, pts[-1], "black", segments=8, rings=5)
    tail.finish(pivot=(0, -0.02, -0.11), parent=root)
    return root


def build_calendar(name="Calendar"):
    """A kitchen calendar on its nail: a picture of a sunny hill on top, the days below, one of them
    circled in red. Origin = the nail; the wall is y = 0."""
    b = C.Builder(name)
    b.cylinder(0.005, 0.012, (0, -0.006, 0), "grey_dark", rot=(90, 0, 0), segments=6)
    w, h = 0.22, 0.32
    top = -0.012
    b.box((w, 0.004, h), (0, -0.004, top - h / 2), "white")
    b.box((w, 0.006, 0.02), (0, -0.005, top - 0.012), "gingham")  # the binding
    b.box((w - 0.02, 0.003, 0.12), (0, -0.0075, top - 0.09), "sky")  # the picture: sky, a hill, the sun
    b.sphere(0.07, (0.02, -0.008, top - 0.19), "pipe_green_light", scale=(1.4, 0.05, 0.8), segments=16, rings=8)
    b.sphere(0.022, (-0.05, -0.0085, top - 0.07), "safety_yellow", scale=(1, 0.1, 1), segments=12, rings=6)
    b.box((w - 0.02, 0.004, 0.012), (0, -0.0072, top - 0.155), "white")
    gx0, gz0, cw, ch = -0.09, top - 0.175, 0.18 / 7, 0.12 / 5  # the days
    for r in range(6):
        b.box((0.18, 0.002, 0.0015), (0, -0.0065, gz0 - r * ch), "grey_light")
    for c in range(8):
        b.box((0.0015, 0.002, 0.12), (gx0 + c * cw, -0.0065, gz0 - 0.06), "grey_light")
    b.torus(0.011, 0.0018, (gx0 + 4.5 * cw, -0.008, gz0 - 2.5 * ch), "alarm_red", rot=(90, 0, 0), segments=12, sides=4)
    return b.finish()


# --- Lights, appliances, furniture --------------------------------------------------------------------------

def build_ceiling_lamp(name="CeilingLamp", drop=0.5):
    """A 1950s pendant: an enamel dome on a cord. Origin at the ceiling; "Bulb" glows."""
    b = C.Builder(name)
    b.cylinder(0.05, 0.02, (0, 0, -0.02), "cream", base=True, segments=14)
    b.cylinder(0.005, drop, (0, 0, -drop - 0.01), "grey_dark", base=True, segments=6)
    z = -drop - 0.01
    prof = [(0.025, z), (0.05, z - 0.025), (0.12, z - 0.09), (0.19, z - 0.15), (0.21, z - 0.165)]
    M.lathe(b, [(0.0, z + 0.01)] + prof, "mint_dark", seg=24, inside=True)
    M.lathe(b, [(r - 0.004, h - 0.003) for r, h in prof], "white", seg=24)
    M.lathe(b, [(0.21, z - 0.165), (0.215, z - 0.172)], "silver", seg=24, inside=True)
    root = b.finish()
    bulb = C.Builder("Bulb")
    bulb.sphere(0.045, (0, 0, z - 0.1), "cream", scale=(1, 1, 1.15), segments=14, rings=9, material=E)
    bulb.finish(pivot=(0, 0, z - 0.1), parent=root)
    return root


def _heart():
    pts = []
    for k in range(24):
        t = 2 * math.pi * k / 24
        pts.append((16 * math.sin(t) ** 3 / 16,
                    (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16))
    return D.ccw(pts)


def build_fridge(name="Fridge"):
    """A rounded 1950s fridge in cream: a big chrome handle, a chrome badge, magnets holding a child's
    drawing (a sun over a green hill) and a list."""
    b = C.Builder(name)
    W, Dp, H = 0.64, 0.6, 1.45
    rbox(b, (W, Dp, H - 0.08), (0, 0, 0.08 + (H - 0.08) / 2), "cream", 0.07, segments=4)
    b.box((W - 0.06, Dp - 0.08, 0.08), (0, 0.02, 0.0), "charcoal", base=True)
    for k in range(5):  # the grille in the kick plate
        b.box((W - 0.16, 0.004, 0.006), (0, -Dp / 2 + 0.035, 0.018 + k * 0.012), "grey_dark")
    b.box((W - 0.03, 0.006, 0.006), (0, -Dp / 2 - 0.001, 0.32), "grey_light")  # the door's seam
    rbox(b, (0.28, 0.012, 0.03), (0.0, -Dp / 2 - 0.004, H - 0.2), "silver", 0.006, segments=2)  # badge
    b.sphere(0.018, (0.0, -Dp / 2 - 0.01, H - 0.2), "gingham", scale=(1, 0.5, 1), segments=10, rings=6)
    rbox(b, (0.05, 0.05, 0.36), (W / 2 - 0.07, -Dp / 2 - 0.035, 0.9), "silver", 0.02)  # the handle
    for z in (0.76, 1.04):
        b.box((0.03, 0.04, 0.03), (W / 2 - 0.07, -Dp / 2 - 0.012, z), "silver", bevel=0.008)
    fy = -Dp / 2 - 0.002
    b.box((0.16, 0.003, 0.12), (-0.12, fy - 0.0015, 1.05), "white")
    b.box((0.14, 0.003, 0.05), (-0.12, fy - 0.003, 1.0), "pipe_green_light")
    b.sphere(0.018, (-0.08, fy - 0.004, 1.08), "safety_yellow", scale=(1, 0.2, 1), segments=10, rings=5)
    b.box((0.07, 0.003, 0.025), (-0.15, fy - 0.0035, 1.055), "sky")
    b.box((0.1, 0.003, 0.14), (0.12, fy - 0.0015, 0.62), "off_white")
    for k in range(5):
        b.box((0.07, 0.003, 0.004), (0.115, fy - 0.003, 0.67 - k * 0.022), "grey")
    for x, z, col in ((-0.12, 1.11, "alarm_red"), (0.12, 0.69, "sky")):
        b.sphere(0.016, (x, fy - 0.008, z), col, scale=(1, 0.45, 1), segments=10, rings=6)
    D.wall_shape(b, [(x * 0.032, z * 0.032) for x, z in _heart()], 0.008, (-0.05, fy, 0.8), "alarm_red")
    for k in range(5):
        a = 2 * math.pi * k / 5
        b.sphere(0.012, (0.1 + 0.014 * math.cos(a), fy - 0.006, 1.2 + 0.014 * math.sin(a)), "butter",
                 scale=(1, 0.4, 1), segments=8, rings=5)
    b.sphere(0.008, (0.1, fy - 0.009, 1.2), "orange", segments=8, rings=5)
    return b.finish()


COUNTER_H = 0.65  # counter tops (grandma.py: her hands rest and tap there)
ISLAND_OVERHANG = 0.11  # the island's top over grandma's knees (her round dress, her folded hands)


def _counter(b, length, depth, doors, color="mint", top="cream", overhang=0.0):
    """A run of base cabinets with a formica top and a chrome edge: `doors` doors on the front, each
    with a chrome pull and a drawer above it, a dark toe kick. The top overhangs the cabinets at the
    back by `overhang` (a breakfast bar: room for someone's knees)."""
    H = COUNTER_H
    t = 0.035
    b.box((length - 0.06, depth - 0.08 - overhang, 0.07), (0, 0.02 - overhang / 2, 0.0), "charcoal", base=True)
    b.box((length - 0.02, depth - 0.04 - overhang, H - t - 0.07), (0, -overhang / 2, 0.07), color, base=True,
          bevel=0.008)
    b.box((length, depth, t), (0, 0, H - t), top, base=True, bevel=0.004)
    for sy in (-1, 1):  # the chrome edge band
        b.box((length + 0.004, 0.006, t * 0.8), (0, sy * (depth / 2 + 0.001), H - t * 0.9), "silver", base=True)
    for sx in (-1, 1):
        b.box((0.006, depth + 0.004, t * 0.8), (sx * (length / 2 + 0.001), 0, H - t * 0.9), "silver", base=True)
    fy = -(depth - 0.04) / 2
    dw = (length - 0.06) / doors
    door_h = H - t - 0.07 - 0.17
    for k in range(doors):
        x = -(length - 0.06) / 2 + dw * (k + 0.5)
        rbox(b, (dw - 0.025, 0.012, door_h), (x, fy - 0.004, 0.08 + door_h / 2 + 0.005), color, 0.006, segments=1)
        rbox(b, (dw - 0.07, 0.006, door_h - 0.05), (x, fy - 0.011, 0.08 + door_h / 2 + 0.005),
             "mint_dark" if color == "mint" else "cream", 0.004, segments=1)
        rbox(b, (dw - 0.025, 0.012, 0.1), (x, fy - 0.004, H - t - 0.065), color, 0.006, segments=1)  # drawer
        rbox(b, (0.07, 0.022, 0.016), (x, fy - 0.016, H - t - 0.065), "silver", 0.006, segments=2)
        rbox(b, (0.016, 0.022, 0.07), (x + (dw / 2 - 0.05) * (1 if k % 2 else -1), fy - 0.016, 0.33), "silver", 0.006,
             segments=2)


def _gingham(b, at, nu, nv, colors=("white", "pastel_pink", "gingham")):
    """A cloth surface (at(u, v) -> a point, u and v in 0..1) checked like gingham: where a red row
    crosses a red column it's darkest. Both sides are drawn."""
    cells = {0: [], 1: [], 2: []}
    for i in range(nu):
        for j in range(nv):
            cells[(i % 2) + (j % 2)].append((i, j))
    for tone, cs in cells.items():
        b._begin()
        for i, j in cs:
            corners = [Vector(at(u, v)) for u, v in ((i / nu, j / nv), ((i + 1) / nu, j / nv),
                                                     ((i + 1) / nu, (j + 1) / nv), (i / nu, (j + 1) / nv))]
            n = (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized() * 0.0015
            b.bm.faces.new([b.bm.verts.new(c) for c in corners])
            b.bm.faces.new([b.bm.verts.new(c - n) for c in reversed(corners)])
        b._finish_prim(colors[tone], C.MAT_PALETTE, False)


def build_island(name="Island", length=1.6, depth=0.55):
    """The counter grandma makes her toast at: three doors towards the room, a gingham dish towel
    hanging from a drawer pull; on her side the top overhangs the cabinets (she stands close)."""
    b = C.Builder(name)
    _counter(b, length, depth, 3, overhang=ISLAND_OVERHANG)
    fy = -(depth - 0.04) / 2
    _gingham(b, lambda u, v: (0.06 + 0.13 * u, fy - 0.03 - 0.012 * math.sin(u * math.pi) - 0.01 * v,
                              COUNTER_H - 0.1 - 0.24 * v), 6, 9)
    return b.finish()


def build_sink_counter(name="SinkCounter", length=2.4, depth=0.5):
    """The counter under the window: cabinets, a steel sink and a chrome gooseneck tap, a teapot in its
    knitted cosy, canisters and a cookie jar."""
    b = C.Builder(name)
    _counter(b, length, depth, 4)
    H = COUNTER_H
    sx = 0.25
    b.box((0.5, 0.34, 0.006), (sx, 0.0, H + 0.0005), "steel_light", base=True)
    b.box((0.44, 0.28, 0.004), (sx, 0.0, H + 0.003), "steel", base=True)
    M.tube(b, [(sx, 0.2, H), (sx, 0.2, H + 0.25), (sx, 0.12, H + 0.3), (sx, 0.06, H + 0.24)], 0.016, "silver", seg=10,
           bend=0.05, caps=True)
    for s in (-1, 1):
        b.cylinder(0.022, 0.03, (sx + s * 0.08, 0.2, H), "silver", base=True, segments=10)
        b.cylinder(0.026, 0.012, (sx + s * 0.08, 0.2, H + 0.03), "white", base=True, segments=6)
    tx = -0.6  # the teapot in a knitted cosy: lilac and pink rings, a pompom; the spout pokes out
    dome = 0.19
    for k in range(6):  # a knitted dome, in rings
        z0, z1 = dome * k / 6, dome * (k + 1) / 6
        ring = [(0.11 * math.sqrt(max(0.0, 1 - (z / dome) ** 2)) + (0.004 if k % 2 else 0.0), H + z)
                for z in (z0, (z0 + z1) / 2, z1)]
        M.lathe(b, ring, "lilac" if k % 2 else "pastel_pink", seg=18, loc=(tx, 0, 0))
    b.sphere(0.034, (tx, 0, H + dome + 0.02), "white", segments=10, rings=6)
    M.tube(b, [(tx + 0.1, -0.02, H + 0.05), (tx + 0.16, -0.03, H + 0.1), (tx + 0.18, -0.03, H + 0.12)], 0.014, "white",
           seg=8, caps=True)
    for k, (r, h) in enumerate(((0.07, 0.2), (0.06, 0.16), (0.05, 0.12))):  # canisters: no words, gingham lids
        x = 0.75 + k * 0.17
        b.cylinder(r, h, (x, 0.04, H), "cream", base=True, segments=16)
        b.cylinder(r + 0.004, 0.025, (x, 0.04, H + h), "gingham", base=True, segments=16)
        b.cylinder(0.012, 0.015, (x, 0.04, H + h + 0.025), "cream", base=True, segments=8)
        b.sphere(r * 0.45, (x, 0.04 - r + 0.002, H + h * 0.55), "gingham", scale=(1, 0.2, 1), segments=10, rings=5)
    cx = -0.95  # the cookie jar
    M.lathe(b, [(0.06, H), (0.085, H + 0.05), (0.08, H + 0.14), (0.06, H + 0.16)], "pastel_blue", seg=18, loc=(cx, 0, 0))
    b.cylinder(0.065, 0.02, (cx, 0, H + 0.16), "pastel_blue", base=True, segments=18)
    b.sphere(0.02, (cx, 0, H + 0.19), "cream", segments=8, rings=5)
    return b.finish()


WINDOW_W, WINDOW_H = 1.0, 1.05  # the opening the cinematic's back wall leaves


def build_window(name="Window"):
    """The kitchen window's dressing (the opening itself is in the wall): a white frame with a cross,
    a deep sill with a pot of red geraniums, gingham curtains tied back and a ruffled valance.
    Origin at the bottom centre of the opening, on the wall's face (y = 0)."""
    b = C.Builder(name)
    W, H = WINDOW_W, WINDOW_H
    f = 0.055
    for x in (-W / 2 - f / 2, W / 2 + f / 2):
        b.box((f, 0.05, H + 2 * f), (x, 0.0, H / 2), "white", bevel=0.006)
    b.box((0.035, 0.035, H), (0, 0.02, H / 2), "white", bevel=0.005)
    for z in (-f / 2, H + f / 2):
        b.box((W + 2 * f, 0.05, f), (0, 0.0, z), "white", bevel=0.006)
    b.box((W, 0.035, 0.03), (0, 0.02, H * 0.55), "white", bevel=0.005)
    b.box((W + 0.2, 0.16, 0.03), (0, -0.07, -0.045), "white", bevel=0.006)  # the sill
    px, py = 0.3, -0.08  # geraniums in a clay pot on the sill
    M.lathe(b, [(0.045, -0.03), (0.06, 0.06), (0.066, 0.075), (0.066, 0.09)], "orange_dark", seg=14, loc=(px, py, 0))
    b.cylinder(0.058, 0.01, (px, py, 0.07), "brown_dark", base=True, segments=14)
    rng = random.Random(8)
    for _ in range(9):
        a, r = rng.uniform(0, 6.28), rng.uniform(0.0, 0.07)
        D.lumpy(b, b.sphere, 0.004, rng, 0.03, (px + math.cos(a) * r, py + math.sin(a) * r * 0.6, 0.12 + rng.uniform(0, 0.05)),
                "pipe_green", segments=8, rings=5)
    for _ in range(6):
        a, r = rng.uniform(0, 6.28), rng.uniform(0.0, 0.06)
        D.lumpy(b, b.sphere, 0.003, rng, 0.022,
                (px + math.cos(a) * r, py + math.sin(a) * r * 0.6 - 0.02, 0.17 + rng.uniform(0, 0.05)),
                rng.choice(["gingham", "alarm_red"]), segments=8, rings=5)
    for s in (-1, 1):  # curtains: gathered panels, tied back at half height
        x0 = s * (W / 2 + 0.06)

        def at(u, v, s=s, x0=x0):
            tie = 1.0 - 0.75 * math.exp(-((v - 0.55) / 0.12) ** 2)
            width = 0.2 * (0.6 + 0.4 * tie) * (1.0 + 0.4 * max(0.0, v - 0.55))
            return (x0 - s * u * width, -0.04 - 0.02 * math.sin(u * math.pi * 3) ** 2 - 0.02 * v, H + 0.12 - (H + 0.05) * v)
        _gingham(b, at, 6, 14)
        b.torus(0.03, 0.008, (x0 - s * 0.07, -0.06, H + 0.12 - (H + 0.05) * 0.55), "gingham", rot=(90, 0, 0), segments=10,
                sides=4, scale=(1.4, 1, 1))
    _gingham(b, lambda u, v: (-W / 2 - 0.12 + (W + 0.24) * u, -0.06 - 0.015 * math.sin(u * math.pi * 14) ** 2,
                              H + 0.17 - 0.1 * v), 22, 3)
    b.cylinder(0.008, W + 0.4, (0, -0.05, H + 0.17), "silver", rot=(0, 90, 0), segments=6)
    return b.finish()


# --- Little props ---------------------------------------------------------------------------------------------

def build_match(name="Match"):
    """A match (bigger than life, so it reads), held at the bottom (the origin); "Flame" sits on its
    head, two tones, emissive."""
    b = C.Builder(name)
    b.box((0.006, 0.006, 0.075), (0, 0, 0), "wood_light", base=True)
    b.sphere(0.008, (0, 0, 0.078), "alarm_red", scale=(1, 1, 1.25), segments=10, rings=6)
    root = b.finish()
    flame = C.Builder("Flame")
    flame.sphere(0.014, (0, 0, 0.098), "orange", scale=(1, 1, 1.9), segments=12, rings=8, material=E)
    flame.sphere(0.008, (0, -0.004, 0.092), "butter", scale=(1, 1, 1.6), segments=10, rings=6, material=E)
    flame.finish(pivot=(0, 0, 0.082), parent=root)
    return root


def build_matchbox(name="Matchbox"):
    """A matchbox: a red sleeve with a yellow label (a little flame on it), striking strips."""
    b = C.Builder(name)
    rbox(b, (0.075, 0.048, 0.02), (0, 0, 0.01), "gingham", 0.003, segments=1)
    b.box((0.05, 0.003, 0.014), (0, -0.0245, 0.01), "safety_yellow")
    b.sphere(0.005, (0.0, -0.027, 0.009), "orange", scale=(1, 0.3, 1.6), segments=8, rings=5)
    for sx in (-1, 1):
        b.box((0.002, 0.04, 0.014), (sx * 0.0375, 0, 0.01), "brown_dark")
    return b.finish()


# --- The view: the town, the plant on its hill ------------------------------------------------------------------

def build_house(name="House", wall="pastel_blue", roof="red_dark"):
    """A little 1950s house (real size; the cinematic shrinks it): a gable roof, a chimney, a door,
    windows that light up ("Windows")."""
    b = C.Builder(name)
    W, Dp, H = 8.0, 6.0, 3.0
    b.box((W, Dp, H), (0, 0, 0), wall, base=True)
    b.prism([(-W / 2 - 0.4, 0), (W / 2 + 0.4, 0), (0, 2.4)], Dp + 0.6, (0, Dp / 2 + 0.3, H), roof, rot=(90, 0, 0))
    b.box((0.9, 0.9, 2.0), (2.2, 0.8, H + 0.8), "brown", base=True)
    b.box((1.0, 0.1, 2.0), (-1.5, -Dp / 2 - 0.02, 0), "white", base=True)
    root = b.finish()
    win = C.Builder("Windows")
    for x in (1.0, 2.8, -3.2):
        win.box((1.2, 0.12, 1.0), (x, -Dp / 2 - 0.03, 1.2), "butter", base=True, material=E)
    win.box((0.9, 0.12, 0.6), (0, -Dp / 2 - 0.03, H + 0.5), "butter", base=True, material=E)
    win.finish().parent = root
    return root


def build_plant_building(name="PlantBuilding"):
    """Sunny Acres as the town sees it: the long turbine hall and the reactor's dome, rows of lit
    windows ("Windows"). Real size (about 60 m long)."""
    b = C.Builder(name)
    b.box((60, 22, 16), (0, 0, 0), "beige_light", base=True)
    b.box((61, 23, 1.2), (0, 0, 16), "teal", base=True)
    b.sphere(14, (-14, 4, 16), "off_white", scale=(1, 1, 0.75), segments=20, rings=10)
    root = b.finish()
    win = C.Builder("Windows")
    for row in range(3):
        for k in range(12):
            win.box((2.6, 0.4, 1.6), (-26 + k * 4.6, -11.1, 3 + row * 4.2), "butter", base=True, material=E)
    win.finish().parent = root
    return root


def build_power_pole(name="PowerPole"):
    b = C.Builder(name)
    b.cylinder(0.14, 9.0, (0, 0, 0), "brown", base=True, segments=8)
    b.box((2.4, 0.16, 0.16), (0, 0, 8.4), "brown", base=True)
    for x in (-1.0, 0.0, 1.0):
        b.cylinder(0.08, 0.3, (x, 0, 8.56 if x else 9.0), "pastel_blue", base=True, segments=8)
    return b.finish()


def build_tree(name="Tree"):
    b = C.Builder(name)
    b.cylinder(0.25, 3.0, (0, 0, 0), "brown", base=True, segments=8, radius_top=0.18)
    D.lumpy(b, b.sphere, 0.35, random.Random(2), 2.2, (0, 0, 4.4), "pipe_green", scale=(1, 1, 1.1), segments=12, rings=8)
    return b.finish()


BUILDERS = {"toaster": build_toaster, "toast": build_toast, "toast_limp": build_toast_limp, "plate": build_plate,
            "butter_dish": build_butter_dish, "teacup": build_teacup, "photo_frame": build_photo_frame,
            "cat_clock": build_cat_clock, "calendar": build_calendar, "ceiling_lamp": build_ceiling_lamp,
            "fridge": build_fridge, "island": build_island, "sink_counter": build_sink_counter, "window": build_window,
            "match": build_match, "matchbox": build_matchbox, "house": build_house,
            "plant_building": build_plant_building, "power_pole": build_power_pole, "tree": build_tree}

ASSETS = [
    ("toaster", {"kind": "toaster"}),
    ("toast", {"kind": "toast"}),
    ("toast_pale", {"kind": "toast", "toast": "pale", "name": "ToastPale"}),
    ("toast_bitten", {"kind": "toast", "toast": "bitten", "name": "ToastBitten"}),
    ("toast_limp", {"kind": "toast_limp"}),
    ("plate", {"kind": "plate"}),
    ("butter_dish", {"kind": "butter_dish"}),
    ("teacup", {"kind": "teacup"}),
    ("photo_frame", {"kind": "photo_frame"}),
    ("cat_clock", {"kind": "cat_clock"}),
    ("calendar", {"kind": "calendar"}),
    ("ceiling_lamp", {"kind": "ceiling_lamp"}),
    ("fridge", {"kind": "fridge"}),
    ("kitchen_island", {"kind": "island"}),
    ("sink_counter", {"kind": "sink_counter"}),
    ("kitchen_window", {"kind": "window"}),
    ("match", {"kind": "match"}),
    ("matchbox", {"kind": "matchbox"}),
    ("house_blue", {"kind": "house", "name": "HouseBlue"}),
    ("house_yellow", {"kind": "house", "wall": "butter", "roof": "brown_dark", "name": "HouseYellow"}),
    ("house_pink", {"kind": "house", "wall": "pastel_pink", "roof": "grey_dark", "name": "HousePink"}),
    ("plant_building", {"kind": "plant_building"}),
    ("power_pole", {"kind": "power_pole"}),
    ("tree_round", {"kind": "tree"}),
]


def build(kind, **kwargs):
    if "toast" in kwargs:
        kwargs["kind"] = kwargs.pop("toast")
    return BUILDERS[kind](**kwargs)


if __name__ == "__main__":
    D.main("kitchen", ASSETS, build)

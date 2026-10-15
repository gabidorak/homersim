"""Grandma, the star of the end-of-match cinematics (client/outro/): a short, round grandma in the
Kenney mini-characters style of rat.py, rigged and animated the same way.

    blender -b -P tools/blender/grandma.py -- [--out PATH]

Standing, facing -Y (Godot +Z), slippers on the origin, about 1.36 m to the top of her bun: a big
rounded head (silver curls, a bun with two knitting needles, round plum glasses, rosy cheeks, pearl
earrings), a lilac cardigan over a rose dress and a white apron, pink fluffy slippers. One skinned
mesh, every part weighted 100 % to one bone (rat.py's rig helpers and pose convention), plus:

  Face bones, so expressions are poses like any other (client/outro/ never edits the mesh):
    brow_l/r      raise and tilt the eyebrows
    eye_l/r       the eyes (scale: wide open; 0 = hidden, for the happy arcs)
    lid_l/r       eyelids, hanging from the top of each eye: scale z 0 = open .. 1 = closed
    eyes_happy    the "^ ^" closed happy eyes (scale 0 = hidden)
    glasses       the glasses (they slide down her nose when she's shocked)
    mouth_*       one mesh per mouth shape, shown by scale 1 and hidden by scale 0 (one at a time):
                  smile, grin (open, with her dentures), o, pout, flat, wavy, blow
    cheek_l/r     the blush (puffs up when she chews)
    bun           her bun (follow-through: a spring in the clips)
  Arms in two parts (upper arm, forearm) plus the hand and its thumb, so a two-bone IK can put a
  hand exactly on a prop (the lever, a toast): see `ik_arm`.

Marks (empties under "Marks", in her own space): where the cinematic's props go relative to her,
so her performance and the set (client/outro/outro_kitchen.gd puts the props on these) can't drift
apart. Their contact points come from kitchen.py's dimensions.

Clips: idle (loop) and her two performances, written frame by frame to the cinematic's clock
(PERF_FPS frames per second; the times mirror client/outro/outro.gd): outro_supervisors (the
golden toast) and outro_rats (the power cut).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import kitchen as K  # noqa: E402  (the props' dimensions: her hands find them)
import machines as M  # noqa: E402
import rat as R  # noqa: E402  (rig helpers)
from rat import P  # noqa: E402

ASSETS = [("grandma", {})]
ANIMATED = True

# --- Proportions (m) -------------------------------------------------------------------------------

HEAD = Vector((0.0, -0.005, 0.985))  # head box centre
HEAD_SIZE = (0.42, 0.38, 0.4)
FACE_Y = HEAD.y - HEAD_SIZE[1] / 2  # the front of the face
EYE_Z = 0.995
EYE_X = 0.083
MOUTH = Vector((0.0, FACE_Y, 0.872))
INSIDE = FACE_Y + 0.035  # the face shapes scale about points this deep in the head: hidden, they vanish there
SHOULDER = Vector((0.212, 0.0, 0.762))
ELBOW = Vector((0.235, 0.0, 0.612))
WRIST = Vector((0.25, 0.0, 0.47))
PALM = Vector((0.0, 0.0, -0.042))  # the hand's centre, from the wrist (rest pose)
HAND_R = 0.042  # roughly: the hand is a rounded 0.085 box

BONES = [
    ("root", None, (0, 0, 0)),
    ("hips", "root", (0, 0, 0.42)),
    ("torso", "hips", (0, 0, 0.5)),
    ("head", "torso", (0, 0, 0.8)),
    ("bun", "head", (0, 0.04, 1.2)),
    ("glasses", "head", (0, FACE_Y - 0.02, EYE_Z)),
    ("brow_l", "head", (EYE_X + 0.004, FACE_Y - 0.006, EYE_Z + 0.072)),
    ("brow_r", "head", (-EYE_X - 0.004, FACE_Y - 0.006, EYE_Z + 0.072)),
    ("eye_l", "head", (EYE_X, INSIDE, EYE_Z)),
    ("eye_r", "head", (-EYE_X, INSIDE, EYE_Z)),
    ("lid_l", "head", (EYE_X, FACE_Y, EYE_Z + 0.04)),
    ("lid_r", "head", (-EYE_X, FACE_Y, EYE_Z + 0.04)),
    ("eyes_happy", "head", (0, INSIDE, EYE_Z)),
    ("cheek_l", "head", (0.125, FACE_Y, 0.912)),
    ("cheek_r", "head", (-0.125, FACE_Y, 0.912)),
    ("mouth_smile", "head", (0, INSIDE, MOUTH.z)),
    ("mouth_grin", "head", (0, INSIDE, MOUTH.z)),
    ("mouth_o", "head", (0, INSIDE, MOUTH.z)),
    ("mouth_pout", "head", (0, INSIDE, MOUTH.z)),
    ("mouth_flat", "head", (0, INSIDE, MOUTH.z)),
    ("mouth_wavy", "head", (0, INSIDE, MOUTH.z)),
    ("mouth_blow", "head", (0, INSIDE, MOUTH.z)),
    ("arm_l", "torso", tuple(SHOULDER)),
    ("forearm_l", "arm_l", tuple(ELBOW)),
    ("hand_l", "forearm_l", tuple(WRIST)),
    ("thumb_l", "hand_l", (WRIST.x - 0.028, -0.03, WRIST.z - 0.03)),
    ("arm_r", "torso", (-SHOULDER.x, SHOULDER.y, SHOULDER.z)),
    ("forearm_r", "arm_r", (-ELBOW.x, ELBOW.y, ELBOW.z)),
    ("hand_r", "forearm_r", (-WRIST.x, WRIST.y, WRIST.z)),
    ("thumb_r", "hand_r", (-WRIST.x + 0.028, -0.03, WRIST.z - 0.03)),
    ("leg_l", "root", (0.088, 0.0, 0.2)),
    ("leg_r", "root", (-0.088, 0.0, 0.2)),
]
BONE_HEAD = {n: Vector(h) for n, _, h in BONES}
PARENT = {n: p for n, p, _ in BONES}
MOUTHS = ["smile", "grin", "o", "pout", "flat", "wavy", "blow"]
SCALED = {"root", "eye_l", "eye_r", "lid_l", "lid_r", "eyes_happy", "cheek_l", "cheek_r", "bun"} \
    | {"mouth_" + m for m in MOUTHS}


# --- Modelling helpers --------------------------------------------------------------------------------

def rbox(b, size, loc, color, radius, segments=3, rot=(0, 0, 0), material=C.MAT_PALETTE):
    """A box with rounded edges (`segments` bevel steps of `radius`), smooth shaded."""
    b._begin()
    res = bmesh.ops.create_cube(b.bm, size=1.0, matrix=C._matrix(loc, rot, size))
    b._bevel(res["verts"], radius, segments)
    b._finish_prim(color, material, True)
    return b


def arc(b, centre, width, sag, radius, color, plane_y, n=9, tilt=0.0):
    """A tube along a curve in the face's plane (x, z at y = plane_y): from -width/2 to +width/2,
    dipping by `sag` in the middle (negative: an arch), tilted by `tilt` degrees."""
    pts = []
    a = math.radians(tilt)
    for i in range(n):
        u = i / (n - 1) * 2 - 1
        x, z = u * width / 2, -sag * (1 - u * u)
        x, z = x * math.cos(a) - z * math.sin(a), x * math.sin(a) + z * math.cos(a)
        pts.append((centre[0] + x, plane_y, centre[2] + z))
    M.tube(b, pts, radius, color, seg=6, caps=True)
    return b


def wave_line(b, centre, width, amp, radius, color, plane_y, waves=1.5, n=13):
    pts = [(centre[0] + (i / (n - 1) - 0.5) * width, plane_y,
            centre[2] + amp * math.sin(2 * math.pi * waves * i / (n - 1))) for i in range(n)]
    M.tube(b, pts, radius, color, seg=6, caps=True)
    return b


# --- The parts (each a mesh weighted to one bone) -----------------------------------------------------

def _head():
    b = C.Builder("head")
    w, d, h = HEAD_SIZE
    rbox(b, (w, d, h), HEAD, "skin_light", 0.085)
    # The nose, a round button the glasses rest on; rosy cheeks are their own bones (they puff).
    b.sphere(0.033, (0, FACE_Y - 0.012, 0.935), "blush", scale=(1.05, 0.8, 0.9), segments=14, rings=9)
    # Ears with pearl earrings.
    for s in (-1, 1):
        rbox(b, (0.05, 0.075, 0.1), (s * (w / 2 + 0.008), 0.015, 0.95), "skin_light", 0.022)
        b.sphere(0.014, (s * (w / 2 + 0.012), 0.0, 0.885), "white", segments=8, rings=6)
    # Silver hair: a cap over the top and the back, soft curls along the hairline and over the ears.
    rbox(b, (w + 0.035, d + 0.005, 0.16), (0, HEAD.y + 0.02, HEAD.z + h / 2 - 0.025), "hair_silver", 0.075)
    b.sphere(0.2, (0, HEAD.y + 0.03, HEAD.z + h / 2 + 0.005), "hair_silver", scale=(1.08, 0.98, 0.32), segments=18,
             rings=10)
    rbox(b, (w + 0.035, 0.13, 0.34), (0, HEAD.y + d / 2 - 0.035, HEAD.z + 0.03), "hair_silver", 0.06)
    for k in range(7):
        x = -0.18 + k * 0.06
        b.sphere(0.045, (x, FACE_Y + 0.04, HEAD.z + h / 2 - 0.03 - 0.009 * abs(k - 3)), "hair_silver",
                 scale=(1.0, 0.78, 0.82), segments=12, rings=8)
    for s in (-1, 1):
        for k, (y, z) in enumerate(((-0.075, 1.065), (0.0, 1.085), (0.075, 1.065), (0.065, 0.985))):
            b.sphere(0.056, (s * (w / 2 + 0.006), HEAD.y + y, z), "hair_silver", scale=(0.7, 1.0, 0.95),
                     segments=12, rings=8)
    # A few grey waves in the silver.
    for s in (-1, 1):
        arc(b, (s * 0.1, 0, HEAD.z + h / 2 + 0.015), 0.11, -0.012, 0.006, "hair_grey", FACE_Y + 0.07, tilt=s * 8)
    return b.finish()


def _bun():
    b = C.Builder("bun")
    c = Vector((0, 0.045, 1.265))
    b.sphere(0.098, c, "hair_silver", scale=(1.0, 0.95, 0.88), segments=16, rings=10)
    b.torus(0.066, 0.013, c + Vector((0, 0, 0.018)), "hair_grey", rot=(0, 0, 0), segments=16, sides=5)
    b.torus(0.034, 0.011, c + Vector((0, 0, 0.068)), "hair_grey", rot=(0, 0, 0), segments=12, sides=5)
    # Two knitting needles through it, with knobs.
    for s in (-1, 1):
        p0 = c + Vector((-0.13 * s, 0.03, -0.035 + 0.02 * s))
        p1 = c + Vector((0.13 * s, -0.02, 0.06 - 0.01 * s))
        R.rod(b, p0, p1, 0.0065, 0.0065, "pastel_pink" if s > 0 else "pastel_blue", segments=6)
        b.sphere(0.016, p0, "alarm_red" if s > 0 else "blue", segments=8, rings=5)
    return b.finish()


def _glasses():
    b = C.Builder("glasses")
    y = FACE_Y - 0.022
    for s in (-1, 1):
        x = s * EYE_X
        b.torus(0.05, 0.0075, (x, y, EYE_Z), "purple_dark", rot=(90, 0, 0), segments=18, sides=6)
        # No lens (it would wash the eyes out): a shine mark says "glass".
        arc(b, (x - 0.026, 0, EYE_Z + 0.028), 0.016, -0.004, 0.0028, "white", y - 0.002, n=5, tilt=-45)
        # The arms, back to the ears.
        b.box((0.008, 0.2, 0.01), (s * (HEAD_SIZE[0] / 2 + 0.006), y + 0.1, EYE_Z + 0.01), "purple_dark",
              rot=(4, 0, 0))
        b.box((0.03, 0.01, 0.01), (s * (EYE_X + 0.058), y + 0.002, EYE_Z + 0.012), "purple_dark")
    M.tube(b, [(-EYE_X + 0.047, y, EYE_Z + 0.004), (-0.02, y - 0.004, EYE_Z + 0.02), (0.02, y - 0.004, EYE_Z + 0.02),
               (EYE_X - 0.047, y, EYE_Z + 0.004)], 0.0055, "purple_dark", seg=6)
    return b.finish()


def _eye(s):
    b = C.Builder("eye_" + ("l" if s > 0 else "r"))
    x = s * EYE_X
    b.sphere(0.033, (x, FACE_Y - 0.003, EYE_Z), "eye_black", scale=(0.8, 0.45, 1.12), segments=14, rings=9)
    b.sphere(0.0105, (x - 0.01, FACE_Y - 0.018, EYE_Z + 0.016), "eye_shine", segments=8, rings=5)
    b.sphere(0.005, (x + 0.009, FACE_Y - 0.017, EYE_Z - 0.013), "eye_shine", segments=6, rings=4)
    return b.finish()


def _lid(s):
    """An eyelid: skin over the eye, hanging from the bone at the top of the eye (scale z: closes),
    with a lash line along its lower edge."""
    b = C.Builder("lid_" + ("l" if s > 0 else "r"))
    x = s * EYE_X
    top = EYE_Z + 0.04
    b.sphere(0.036, (x, FACE_Y - 0.012, top - 0.04), "skin_light", scale=(0.95, 0.47, 1.14), segments=12, rings=8)
    arc(b, (x, 0, top - 0.064), 0.058, 0.016, 0.0045, "eye_black", FACE_Y - 0.016, n=7)
    return b.finish()


def _eyes_happy():
    b = C.Builder("eyes_happy")
    for s in (-1, 1):
        arc(b, (s * EYE_X, 0, EYE_Z - 0.004), 0.058, -0.022, 0.0065, "eye_black", FACE_Y - 0.004, n=9)
    return b.finish()


def _brow(s):
    b = C.Builder("brow_" + ("l" if s > 0 else "r"))
    h = BONE_HEAD["brow_l"]
    arc(b, (s * h.x, 0, h.z), 0.066, -0.01, 0.0085, "hair_grey", FACE_Y - 0.008, n=7, tilt=s * -6)
    return b.finish()


def _cheek(s):
    b = C.Builder("cheek_" + ("l" if s > 0 else "r"))
    h = BONE_HEAD["cheek_l"]
    b.sphere(0.03, (s * h.x, FACE_Y + 0.004, h.z), "blush", scale=(1.25, 0.32, 0.78), segments=12, rings=6)
    return b.finish()


def _mouth(shape):
    b = C.Builder("mouth_" + shape)
    m = MOUTH
    y = FACE_Y - 0.004
    if shape == "smile":
        arc(b, m, 0.085, 0.022, 0.0075, "red_dark", y, n=11)
    elif shape == "grin":
        # An open smile: a D (flat top), dark inside, her dentures on top, a tongue at the bottom.
        pts = [(0.048 * math.cos(math.pi + math.pi * k / 10), -0.04 * math.sin(math.pi * k / 10)) for k in range(11)]
        b.prism(pts, 0.012, (m.x, y + 0.006, m.z + 0.012), "red_dark", rot=(90, 0, 0))
        b.box((0.07, 0.01, 0.012), (m.x, y - 0.004, m.z + 0.005), "white", bevel=0.003)
        b.sphere(0.022, (m.x, y - 0.002, m.z - 0.02), "rat_pink", scale=(1.2, 0.35, 0.55), segments=10, rings=5)
        arc(b, (m.x, 0, m.z + 0.012), 0.098, 0.0, 0.0055, "lips", y - 0.002, n=5)
        arc(b, (m.x, 0, m.z + 0.012), 0.096, 0.042, 0.0055, "lips", y - 0.002, n=11)
    elif shape == "o":
        b.sphere(0.024, (m.x, y + 0.004, m.z - 0.004), "red_dark", scale=(0.95, 0.35, 1.25), segments=12, rings=6)
        b.torus(0.024, 0.0065, (m.x, y - 0.003, m.z - 0.004), "lips", rot=(90, 0, 0), segments=14, sides=5,
                scale=(0.95, 1.25, 1.0))
    elif shape == "pout":
        arc(b, (m.x, 0, m.z - 0.006), 0.06, -0.016, 0.0075, "red_dark", y, n=9)
        b.sphere(0.02, (m.x, y - 0.008, m.z - 0.016), "lips", scale=(1.3, 0.7, 0.62), segments=10, rings=6)
    elif shape == "flat":
        arc(b, m, 0.06, 0.0, 0.0072, "red_dark", y, n=5)
    elif shape == "wavy":
        wave_line(b, m, 0.07, 0.008, 0.0068, "red_dark", y)
    elif shape == "blow":
        b.sphere(0.014, (m.x, y - 0.002, m.z - 0.006), "red_dark", scale=(1.0, 0.4, 1.1), segments=10, rings=5)
        b.torus(0.016, 0.008, (m.x, y - 0.01, m.z - 0.006), "lips", rot=(90, 0, 0), segments=12, sides=5)
    return b.finish()


def _torso():
    b = C.Builder("torso")
    before = set(b.bm.verts)
    # A round egg of a body, wider at the hips, flattened top and bottom.
    b.sphere(0.21, (0, 0.01, 0.625), "lilac", scale=(1.17, 0.92, 1.0), segments=24, rings=14)
    R.taper(b, before, 2, 0.43, 0.83, (1.04, 1.04, 1), (0.84, 0.88, 1))
    for v in b.bm.verts:
        if v not in before:
            v.co.z = 0.625 + max(min(v.co.z - 0.625, 0.19), -0.19)
    # The blouse in the cardigan's V and a lace collar.
    b.prism([(0.075, 0.0), (-0.075, 0.0), (0.0, -0.11)], 0.01, (0, -0.172, 0.8), "cream", rot=(90, 0, 0))
    for s in (-1, 1):
        b.sphere(0.055, (s * 0.05, -0.16, 0.792), "white", scale=(1.15, 0.45, 0.62), rot=(0, s * -25, 0),
                 segments=12, rings=6)
    # The cardigan's front edges, buttons, pockets (a tissue poking out of one), a brooch.
    for s in (-1, 1):
        b.box((0.024, 0.012, 0.25), (s * 0.022, -0.174, 0.585), "lilac_dark", rot=(0, s * -4, 0), bevel=0.004)
    for k in range(3):
        b.sphere(0.0145, (0.034, -0.184, 0.7 - k * 0.075), "cream", scale=(1, 0.6, 1), segments=8, rings=5)
    for s in (-1, 1):
        rbox(b, (0.1, 0.02, 0.085), (s * 0.12, -0.18, 0.53), "lilac_dark", 0.008, segments=1)
    b.sphere(0.022, (0.12, -0.188, 0.578), "white", scale=(1.1, 0.7, 0.8), segments=8, rings=5)
    b.sphere(0.017, (0.105, -0.186, 0.586), "white", scale=(0.9, 0.7, 0.9), segments=7, rings=4)
    for k in range(5):
        a = 2 * math.pi * k / 5
        b.sphere(0.0085, (-0.11 + 0.011 * math.cos(a), -0.18, 0.73 + 0.011 * math.sin(a)), "alarm_red",
                 scale=(1, 0.5, 1), segments=6, rings=4)
    b.sphere(0.007, (-0.11, -0.186, 0.73), "safety_yellow", segments=6, rings=4)
    return b.finish()


DRESS = [(0.215, 0.165), (0.235, 0.2), (0.225, 0.3), (0.21, 0.4), (0.19, 0.47)]  # (radius, z), the bell


def _dress_r(z):
    for (r0, z0), (r1, z1) in zip(DRESS, DRESS[1:]):
        if z <= z1:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return DRESS[-1][0]


def _apron(b):
    """The apron wraps round the front of the dress, a little off it: white, a pink frill at the hem."""
    half, z0, z1, rows, cols = math.radians(52), 0.2, 0.46, 6, 12
    b._begin()
    grid = []
    for i in range(rows + 1):
        z = z0 + (z1 - z0) * i / rows
        r = _dress_r(z) + 0.012
        w = half * (1.0 - 0.28 * i / rows)  # narrower at the waist
        grid.append([b.bm.verts.new((math.sin(a) * r, -math.cos(a) * r, z))
                     for a in [-w + 2 * w * j / cols for j in range(cols + 1)]])
    for i in range(rows):
        for j in range(cols):
            b.bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    b._finish_prim("white", C.MAT_PALETTE, True)
    for j in range(9):  # the frilly hem
        a = -half + 2 * half * j / 8
        r = _dress_r(z0) + 0.016
        b.sphere(0.022, (math.sin(a) * r, -math.cos(a) * r, z0), "pastel_pink", scale=(1.1, 0.55, 0.62),
                 rot=(0, 0, math.degrees(a)), segments=8, rings=5)


def _hips():
    b = C.Builder("hips")
    # The dress: a bell, and the apron over its front.
    M.lathe(b, DRESS + [(0.05, 0.48)], "rose", seg=24)
    M.lathe(b, [(0.0, 0.17), (0.215, 0.165)], "rose", seg=24)
    M.lathe(b, [(0.218, 0.16), (0.24, 0.19)], "rat_pink_dark", seg=24)
    for k in range(9):  # polka dots
        a = math.radians(-60 + k * 30 + (8 if k % 2 else 0))
        z = 0.25 + 0.1 * (k % 2)
        r = 0.232 - 0.014 * (z - 0.25) / 0.1
        b.sphere(0.012, (math.sin(a) * r, -math.cos(a) * r, z), "cream", scale=(1, 0.4, 1), segments=6, rings=4)
    _apron(b)
    b.torus(0.205, 0.012, (0, 0.0, 0.465), "white", segments=24, sides=5, scale=(1.0, 0.9, 1.0))
    for s in (-1, 1):  # the bow at the back
        b.sphere(0.035, (s * 0.04, 0.19, 0.46), "white", scale=(1.3, 0.5, 0.8), rot=(0, s * 25, 0), segments=8, rings=5)
    return b.finish()


def _upper_arm(s):
    b = C.Builder("arm_" + ("l" if s > 0 else "r"))
    sh = Vector((s * SHOULDER.x, SHOULDER.y, SHOULDER.z))
    el = Vector((s * ELBOW.x, ELBOW.y, ELBOW.z))
    mid = (sh + el) / 2
    d = el - sh
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler("XYZ")
    rbox(b, (0.105, 0.105, d.length + 0.05), mid, "lilac", 0.045, rot=[math.degrees(a) for a in rot])
    b.sphere(0.06, sh + Vector((0, 0, -0.015)), "lilac", scale=(1, 1, 0.9), segments=12, rings=8)
    return b.finish()


def _forearm(s):
    b = C.Builder("forearm_" + ("l" if s > 0 else "r"))
    el = Vector((s * ELBOW.x, ELBOW.y, ELBOW.z))
    wr = Vector((s * WRIST.x, WRIST.y, WRIST.z))
    mid = (el + wr) / 2
    d = wr - el
    rot = [math.degrees(a) for a in Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler("XYZ")]
    rbox(b, (0.1, 0.1, d.length + 0.03), mid, "lilac", 0.042, rot=rot)
    rbox(b, (0.11, 0.11, 0.03), wr + Vector((0, 0, 0.022)), "lilac_dark", 0.012, rot=rot, segments=2)
    return b.finish()


def _hand(s):
    b = C.Builder("hand_" + ("l" if s > 0 else "r"))
    wr = Vector((s * WRIST.x, WRIST.y, WRIST.z))
    rbox(b, (0.072, 0.088, 0.09), wr + PALM, "skin_light", 0.03)
    return b.finish()


def _thumb(s):
    b = C.Builder("thumb_" + ("l" if s > 0 else "r"))
    h = BONE_HEAD["thumb_l"]
    base = Vector((s * h.x, h.y, h.z))
    rbox(b, (0.04, 0.04, 0.072), base + Vector((0, -0.016, -0.018)), "skin_light", 0.018, rot=(-40, 0, 0))
    return b.finish()


def _leg(s):
    b = C.Builder("leg_" + ("l" if s > 0 else "r"))
    x = s * 0.088
    b.cylinder(0.041, 0.17, (x, 0.0, 0.05), "stocking", base=True, segments=12)
    rbox(b, (0.115, 0.19, 0.075), (x + s * 0.004, -0.035, 0.0375), "pastel_pink", 0.034)
    b.torus(0.05, 0.016, (x, 0.0, 0.074), "white", segments=12, sides=5)
    b.sphere(0.03, (x + s * 0.004, -0.1, 0.075), "white", segments=10, rings=6)
    return b.finish()


def build_model():
    arm = R.make_armature("Armature", BONES, length=0.03)
    parts = [(_head(), "head"), (_bun(), "bun"), (_glasses(), "glasses"), (_torso(), "torso"), (_hips(), "hips"),
             (_eyes_happy(), "eyes_happy")]
    for s, side in ((1, "l"), (-1, "r")):
        parts += [(_eye(s), "eye_" + side), (_lid(s), "lid_" + side), (_brow(s), "brow_" + side),
                  (_cheek(s), "cheek_" + side), (_upper_arm(s), "arm_" + side), (_forearm(s), "forearm_" + side),
                  (_hand(s), "hand_" + side), (_thumb(s), "thumb_" + side), (_leg(s), "leg_" + side)]
    parts += [(_mouth(m), "mouth_" + m) for m in MOUTHS]
    for obj, bone in parts:
        R.skin_rigid(obj, arm, bone)
    R.join([o for o, _ in parts], "Grandma")
    return arm


# --- Clips ---------------------------------------------------------------------------------------------

class Animator(R.Animator):
    """rat.py's Animator, plus scale keys for the bones in SCALED: a pose entry may carry three more
    floats, a scale along the model axes (X left, Y back, Z up). Clips are sampled at `fps`."""

    def __init__(self, arm, fps=30):
        super().__init__(arm)
        self.fps = fps

    def clip(self, name, frames, pose_fn, loop=False):
        arm = self.arm
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        samples = {b: [] for b in self.rest}
        for f in range(frames + 1):
            pose = pose_fn(0 if (loop and f == frames) else f)
            for b, r in self.rest.items():
                v = pose.get(b, [0.0] * 6)
                qw = Euler([math.radians(a) for a in v[:3]], "XYZ").to_quaternion()
                ql = r.inverted() @ qw @ r
                prev = samples[b][-1][0] if samples[b] else None
                if prev is not None and prev.dot(ql) < 0:
                    ql.negate()
                s = v[6:9] if len(v) >= 9 else (1.0, 1.0, 1.0)
                # Bone-local axes of an axis-aligned bone pointing +Z: x = X, y = Z, z = -Y.
                samples[b].append((ql, r.inverted() @ Vector(v[3:6]), (s[0], s[2], s[1])))
        props = (("rotation_quaternion", 4, 0), ("location", 3, 1), ("scale", 3, 2))
        for b, keys in samples.items():
            for prop, size, k in props:
                if prop == "scale" and b not in SCALED:
                    continue
                for i in range(size):
                    fc = act.fcurve_ensure_for_datablock(arm, 'pose.bones["%s"].%s' % (b, prop), index=i,
                                                         group_name=b)
                    co = []
                    for f, key in enumerate(keys):
                        co += [f, key[k][i]]
                    fc.keyframe_points.add(len(keys))
                    fc.keyframe_points.foreach_set("co", co)
                    for kp in fc.keyframe_points:
                        kp.interpolation = "LINEAR"
                    fc.update()
        act.use_frame_range = True
        act.frame_start, act.frame_end = 0, frames
        act.use_cyclic = loop
        arm.animation_data.action = None
        self.clips.append((name, frames, loop))
        return act

    def finish(self):
        super().finish()
        for pb in self.arm.pose.bones:
            pb.scale = Vector((1, 1, 1))


def idle_pose(f):
    """Standing behind the counter, hands folded on her apron, breathing, a slow head tilt."""
    breath = R.wave(f, 75)
    return dict(face(lid=0.0), **{
        "hips": P((1.5 * breath, 0, 0)), "torso": P((1.0 * breath, 0, 0)),
        "head": P((-2 * breath, 0, 4 * R.wave(f, 150))),
        "arm_l": P((-30, 0, -14)), "forearm_l": P((-62, 0, -22)), "hand_l": P((0, 0, -10)),
        "arm_r": P((-30, 0, 14)), "forearm_r": P((-62, 0, 22)), "hand_r": P((0, 0, 10)),
        "bun": P((1.5 * R.wave(f, 75, 0.15), 0, 0)) + [1, 1, 1], "root": P() + [1, 1, 1]})


# --- Her marks ------------------------------------------------------------------------------------------
# Where the cinematic's props stand, in her own space (Blender axes: X her left, -Y in front of her, Z
# up). The counter (kitchen.py's island) runs in front of her at kitchen.COUNTER_H; the photo hangs on
# the back wall behind her right shoulder. client/outro/outro_kitchen.gd puts the props on these.

MARKS = {
    "MarkIsland": (-0.05, -0.515, 0.0),  # the counter's base centre: its top's edge clear of her tummy
    # At her right, the lever end towards her middle: her right hand presses it with hardly a lean (her
    # arms are short, her tummy round), and her head stays clear of the slices.
    "MarkToaster": (-0.33, -0.34, K.COUNTER_H),
    "MarkPlate": (0.25, -0.38, K.COUNTER_H),  # at her left, in reach
    "MarkTeacup": (0.53, -0.33, K.COUNTER_H),
    "MarkButter": (0.5, -0.56, K.COUNTER_H),
    "MarkPhoto": (-0.62, 0.8, 1.56),  # the photo's nail, on the back wall
}


def add_marks(arm):
    for name, loc in MARKS.items():
        C.empty(name, loc, arm)


def face(mouth="smile", lid=0.0, wide=1.0, happy=0.0, brow=0.0, brow_tilt=0.0, blush=1.0, lid_l=None,
         brow_l=None, brow_tilt_l=None, mouths=None, gaze=(0.0, 0.0)):
    """The face bones for an expression. mouth: a MOUTHS shape (or `mouths`, shape -> weight, while one
    swaps for another); lid: 0 open .. 1 closed; wide: the eyes' size; happy: 1 = the "^ ^" eyes
    instead; brow: raise (m, negative = frown down); brow_tilt: degrees, positive = the inner ends up
    (sad, worried), negative = down (cross). `*_l` override the left side (an asymmetric, puzzled
    face)."""
    pose = {}
    weights = mouths if mouths is not None else {mouth: 1.0}
    for m in MOUTHS:
        k = weights.get(m, 0.0)
        pose["mouth_" + m] = P() + [k, k, k]
    e = wide * (1.0 - happy)
    for side, s in (("l", 1), ("r", -1)):
        lid_k = lid_l if side == "l" and lid_l is not None else lid
        raise_k = brow_l if side == "l" and brow_l is not None else brow
        tilt_k = brow_tilt_l if side == "l" and brow_tilt_l is not None else brow_tilt
        pose["eye_" + side] = P((0, 0, 0), (gaze[0], 0, gaze[1])) + [e, 1.0 if e > 0.01 else 0.0, e]
        pose["lid_" + side] = P() + [1.0, 1.0, min(max(lid_k, 0.0), 1.0) * (1.0 - happy)]
        pose["brow_" + side] = P((0, s * tilt_k, 0), (0, 0, raise_k))
        pose["cheek_" + side] = P() + [blush, blush, blush]
    pose["eyes_happy"] = P() + [happy, happy, happy]
    return pose


# --- Forward kinematics and IK: her hands go exactly where the props are ---------------------------------

def q_of(rot):
    """Degrees (XYZ Euler, model axes) -> Quaternion."""
    return Euler([math.radians(a) for a in rot], "XYZ").to_quaternion()


def euler_of(q):
    return [math.degrees(a) for a in q.to_euler("XYZ")]


def fk(pose):
    """Every bone's posed rotation and head position in her space: {bone: (Quaternion, Vector)} (the
    Animator's convention: a child's offset and rotation are in its parent's frame; scales left out,
    hands are placed while she isn't squashing)."""
    out = {}
    for name, parent, head in BONES:
        v = pose.get(name, [0.0] * 6)
        q = q_of(v[:3])
        loc = Vector(v[3:6])
        if parent is None:
            out[name] = (q, Vector(head) + loc)
        else:
            qp, pp = out[parent]
            out[name] = (qp @ q, pp + qp @ (Vector(head) - BONE_HEAD[parent] + loc))
    return out


def head_point(point, lean=0.0, turn=0.0, nod=0.0, look=0.0, tilt=0.0):
    """Where `point` (of her head, at rest) is when she leans, turns, nods... so (her space; as pose_at
    spreads them over her hips, body and head)."""
    pose = {"hips": P((lean * 0.35, 0, turn * 0.3)), "torso": P((lean * 0.65, 0, turn * 0.7)),
            "head": P((nod, tilt, look))}
    q, at = fk(pose)["head"]
    return at + q @ (Vector(point) - BONE_HEAD["head"])


HAND_HALF = Vector((0.036, 0.044, 0.045))  # the hand box's half size (rest axes)
HAND_ROUND = 0.03  # its rounding (_hand's rbox)


def hand_reach(hand_rot, direction):
    """How far the hand (a rounded box) reaches from its centre along `direction` (unit, her space)
    when turned `hand_rot` (degrees): a palm laid on a surface has its centre this far above it."""
    m = q_of(hand_rot).to_matrix()
    d = Vector(direction)
    return sum(abs(d.dot(m.col[k])) * (HAND_HALF[k] - HAND_ROUND) for k in range(3)) + HAND_ROUND


THUMB_HALF = Vector((0.02, 0.02, 0.036))  # the thumb box's half size (_thumb: its turn, rounding)
THUMB_TURN = (-40, 0, 0)
THUMB_ROUND = 0.018


def grip_reach(hand_rot, direction, side="l"):
    """How far the hand or its thumb (whichever goes further) reaches from the palm's centre along
    `direction` when the hand is turned `hand_rot`: a hand gripping something has its palm's centre
    this far above it."""
    q = q_of(hand_rot)
    d = Vector(direction)
    s = 1 if side == "l" else -1
    h = BONE_HEAD["thumb_l"]
    palm = Vector((s * WRIST.x, WRIST.y, WRIST.z)) + PALM
    centre = Vector((s * h.x, h.y, h.z)) + Vector((0, -0.016, -0.018)) - palm
    m = (q @ q_of(THUMB_TURN)).to_matrix()
    thumb = (q @ centre).dot(d) + sum(abs(d.dot(m.col[k])) * (THUMB_HALF[k] - THUMB_ROUND) for k in range(3)) \
        + THUMB_ROUND
    return max(hand_reach(hand_rot, direction), thumb)


def ik_arm(pose, side, palm, hand_rot, pole):
    """Sets `side`'s arm in `pose` so the hand's centre is at `palm` (her space), the hand turned
    `hand_rot` (degrees, her axes) and the elbow out towards `pole` (a direction). Two-bone IK by the
    law of cosines; each segment turns the shortest way from its rest direction."""
    arm, fore, hand = "arm_" + side, "forearm_" + side, "hand_" + side
    for bone in (arm, fore, hand):
        pose[bone] = P()
    w = fk(pose)
    q_torso = w["torso"][0]
    shoulder = w[arm][1]
    hq = q_of(hand_rot)
    wrist_target = Vector(palm) - hq @ PALM
    sh, el, wr = BONE_HEAD[arm], BONE_HEAD[fore], BONE_HEAD[hand]
    a, b = (el - sh).length, (wr - el).length
    d = wrist_target - shoulder
    dist = max(abs(a - b) + 1e-4, min(d.length, a + b - 1e-4))
    dn = d.normalized()
    pole = Vector(pole)
    n = (pole - dn * pole.dot(dn)).normalized()
    cos_a = (a * a + dist * dist - b * b) / (2 * a * dist)
    elbow = shoulder + (dn * cos_a + n * math.sqrt(max(0.0, 1 - cos_a * cos_a))) * a
    wrist = shoulder + dn * dist
    q_upper = (el - sh).normalized().rotation_difference((elbow - shoulder).normalized())
    f_rest = q_upper @ (wr - el).normalized()
    q_fore = f_rest.rotation_difference((wrist - elbow).normalized()) @ q_upper
    pose[arm] = P(euler_of(q_torso.inverted() @ q_upper))
    pose[fore] = P(euler_of(q_upper.inverted() @ q_fore))
    pose[hand] = P(euler_of(q_fore.inverted() @ hq))
    return (wrist - wrist_target).length  # how far it falls short (0 when in reach)


# --- Her performances ---------------------------------------------------------------------------------------
# Written to the cinematic's clock (s): client/outro/outro.gd fires its cues at the same times and the
# score (tools/audio/music.py, outro_*) hits them. Move one, move it there too.

PERF_FPS = 60  # (her hit points land on frames: a hand meets the lever or the slice on the frame it should)
A_LENGTH, B_LENGTH = 8.3, 9.3
A_CLICK = 0.9  # the lever latches down (on a frame: her palm is all the way down there)
A_DING = 3.8
A_JOY = 5.05
A_GRAB = 6.55  # her left hand takes the top slice
A_BITE = 6.95
B_CLICK = 0.9
B_TAPS = (3.08, 3.32)
B_PWOMP = 3.8
B_SHOCK = 4.6
B_BLACKOUT = 5.8
B_STRIKE = 7.85
B_BLOW = 8.8

EASES = {
    "lin": lambda u: u,
    "in": lambda u: u * u,
    "out": lambda u: 1 - (1 - u) ** 2,
    "io": lambda u: u * u * (3 - 2 * u),
    "back": lambda u: 1 + 2.70158 * (u - 1) ** 3 + 1.70158 * (u - 1) ** 2,  # overshoots, then settles
    "step": lambda u: 1.0 if u >= 1.0 else 0.0,
}


class Performance:
    """A performance as keyed controls: each key sets some controls at a time, easing into them from
    their previous value (`ease`); a control a key doesn't name keeps its value. So a control eases
    from its own last key, however long ago: a quick move starts with a key holding the control
    where it is (hold, or the control in the key before). The mouth and the happy eyes swap in SWAP s
    around their keys."""

    SWAP = 0.08
    DEFAULTS = {"hop": 0.0, "squash": 0.0, "lean": 0.0, "turn": 0.0, "roll": 0.0, "nod": 0.0, "look": 0.0, "tilt": 0.0,
                "lid": 0.0, "lid_l": None, "wide": 1.0, "brow": 0.0, "brow_l": None, "brow_tilt": 0.0,
                "brow_tilt_l": None, "blush": 1.0, "glasses": 0.0, "thumb_r": 0.0, "thumb_l": 0.0,
                "chew": 0.0, "shift": 0.0, "gaze_x": 0.0, "gaze_z": 0.0, "droop": 0.0}

    def __init__(self, length, hands):
        self.length = length
        self.tracks = {}  # control -> [(time, value, ease)]
        self.switches = {"mouth": [(0.0, "smile")], "happy": [(0.0, 0.0)]}
        for name, value in self.DEFAULTS.items():
            self.tracks[name] = [(0.0, value, "lin")]
        for side, (palm, rot, pole) in hands.items():
            self.tracks["palm_" + side] = [(0.0, tuple(palm), "lin")]
            self.tracks["rot_" + side] = [(0.0, tuple(rot), "lin")]
            self.tracks["pole_" + side] = [(0.0, tuple(pole), "lin")]

    def key(self, time, ease="io", **controls):
        for name, value in controls.items():
            if name in self.switches:
                self.switches[name].append((time, value))
            elif name in ("r", "l"):
                palm, rot, pole = value
                for part, v in (("palm_", palm), ("rot_", rot), ("pole_", pole)):
                    if v is not None:
                        self.tracks[part + name].append((time, tuple(v), ease))
            else:
                self.tracks[name].append((time, value, ease))
        return self

    def hold(self, time, *names):
        """Keys `names` at `time` where they are then: the next key moves them from there (call it
        before that key)."""
        for name in names:
            self.tracks[name].append((time, self.value(name, time), "step"))
        return self

    def value(self, name, t):
        keys = sorted(self.tracks[name], key=lambda k: k[0])
        if keys[0][1] is None and all(k[1] is None for k in keys):
            return None
        prev = keys[0]
        for k in keys[1:]:
            if t < k[0]:
                u = (t - prev[0]) / max(k[0] - prev[0], 1e-6)
                e = EASES[k[2]](min(max(u, 0.0), 1.0))
                if name.startswith("rot_"):  # the shortest way round
                    return tuple(euler_of(q_of(prev[1]).slerp(q_of(k[1]), e)))
                return _mix(prev[1], k[1], e)
            prev = k
        return prev[1]

    def switch(self, name, t):
        """[(value, weight)] for a switched control at t (two while one swaps for the other)."""
        keys = sorted(self.switches[name], key=lambda k: k[0])
        current = [(keys[0][1], 1.0)]
        for i in range(1, len(keys)):
            at, value = keys[i]
            if t < at - self.SWAP / 2:
                break
            if t < at + self.SWAP / 2:
                u = (t - (at - self.SWAP / 2)) / self.SWAP
                return [(keys[i - 1][1], 1.0 - u), (value, u)]
            current = [(value, 1.0)]
        return current


def _mix(a, b, e):
    if a is None:
        return b if e >= 1.0 else None
    if b is None:
        return a if e < 1.0 else None
    if isinstance(a, tuple):
        return tuple(x + (y - x) * e for x, y in zip(a, b))
    return a + (b - a) * e


def pose_at(perf, t, bun=(0.0, 0.0), short=None):
    """Her pose at `t` s of `perf`: the body, the face, both hands by IK, the bun's lag (pitch, roll).
    `short` (a dict) collects how far each hand falls short of its target (side -> [(t, m)])."""
    v = lambda name: perf.value(name, t)  # noqa: E731
    pose = {}
    squash = v("squash")  # + squashed (wider, lower), - stretched
    pose["root"] = P((0, 0, 0), (v("shift"), 0, v("hop"))) + [1 + 0.6 * squash, 1 + 0.6 * squash, 1 - squash]
    lean, turn = v("lean"), v("turn")
    pose["hips"] = P((lean * 0.35, v("roll") * 0.4, turn * 0.3))
    pose["torso"] = P((lean * 0.65, v("roll") * 0.6, turn * 0.7))
    pose["head"] = P((v("nod"), v("tilt"), v("look")))
    mouths = {}
    for shape, weight in perf.switch("mouth", t):
        mouths[shape] = mouths.get(shape, 0.0) + weight
    happy = sum(value * weight for value, weight in perf.switch("happy", t))
    pose.update(face(mouths=mouths, lid=v("lid"), lid_l=v("lid_l"), wide=v("wide"), happy=happy, brow=v("brow"),
                     brow_l=v("brow_l"), brow_tilt=v("brow_tilt"), brow_tilt_l=v("brow_tilt_l"), blush=v("blush"),
                     gaze=(v("gaze_x"), v("gaze_z"))))
    chew = v("chew")
    if chew:
        c = abs(math.sin(t * 2 * math.pi * 2.6)) * chew
        for side in ("l", "r"):
            pose["cheek_" + side] = P() + [1 + 0.35 * c, 1 + 0.2 * c, 1 + 0.35 * c]
        pose["head"][0] += 3 * c
    slide = v("glasses")
    pose["glasses"] = P((-12 * slide / 0.03, 0, 0), (0, -0.25 * slide, -slide))
    pose["bun"] = P((bun[0] - v("droop"), bun[1], 0)) + [1, 1, 1]
    # She breathes: a slow rise and fall of the shoulders under everything else.
    breath = math.sin(t * 2 * math.pi / 2.6)
    pose["torso"][0] += 1.2 * breath
    pose["head"][0] -= 0.8 * breath
    for side in ("l", "r"):
        miss = ik_arm(pose, side, v("palm_" + side), v("rot_" + side), v("pole_" + side))
        if short is not None and miss > 0.002:
            short.setdefault(side, []).append((t, miss))
        pose["thumb_" + side] = P((v("thumb_" + side), 0, 0))
    return pose


def bun_spring(perf, frames):
    """The bun's follow-through: a damped spring (pitch, roll, degrees) driven by the head's
    acceleration, simulated over the whole performance (so each frame's lag is baked in the clip)."""
    dt = 1.0 / PERF_FPS
    heads = []
    for f in range(frames + 1):
        w = fk(pose_at(perf, f * dt))
        heads.append(w["bun"][1])
    pitch = roll = vp = vr = 0.0
    out = []
    k, c = 380.0, 11.0  # stiffness, damping (1/s²... a lively, quickly settling bob)
    for f in range(frames + 1):
        a = Vector()
        if 0 < f < frames:
            a = (heads[f + 1] - 2 * heads[f] + heads[f - 1]) / (dt * dt)
        for _ in range(4):  # substeps
            h = dt / 4
            ap = -k * pitch - c * vp - a.z * 9.0  # up-down jolts nod it, left-right ones swing it
            ar = -k * roll - c * vr + a.x * 7.0
            vp += ap * h
            vr += ar * h
            pitch += vp * h
            roll += vr * h
        out.append((max(-25.0, min(25.0, pitch)), max(-20.0, min(20.0, roll))))
    return out


def clip_of(anim, name, perf):
    frames = int(round(perf.length * PERF_FPS))
    bun = bun_spring(perf, frames)
    short = {}
    anim.clip(name, frames, lambda f: pose_at(perf, f / PERF_FPS, bun[f], short))
    for side, misses in short.items():  # an arm that can't reach its target: restage
        spans = []  # [start, end, worst, at]
        for t, miss in misses:
            if spans and t - spans[-1][1] < 1.5 / PERF_FPS:
                spans[-1][1] = t
                if miss > spans[-1][2]:
                    spans[-1][2:] = [miss, t]
            else:
                spans.append([t, t, miss, t])
        print("grandma %s: her %s hand falls short: %s" % (name, "left" if side == "l" else "right", ", ".join(
            "%.2f-%.2f s (%.1f cm at %.2f)" % (a, b, w * 100, at) for a, b, w, at in spans)))


# --- Where her hands go (her space; Blender axes: X her left, -Y forward, Z up) -------------------------------

def _mark(name):
    return Vector(MARKS[name])


LEVER_KNOB = _mark("MarkToaster") + Vector((K.LEVER_X, K.LEVER_Y, K.LEVER_UP + K.KNOB[2] / 2))  # its top, lever up
PRESS_AT = LEVER_KNOB + Vector((0.0, 0.012, 0.0))  # her palm on its near half: her wrist clears the toaster
# The top's flat end by the lever (no slot there), its near half: where she raps it.
TOASTER_TOP_END = _mark("MarkToaster") + Vector((K.TOASTER_L / 2 - 0.045, 0.045, K.TOASTER_TOP))
PLATE_TOP = _mark("MarkPlate") + Vector((0.0, 0.0, K.PLATE_SURFACE))
DOWN = Vector((0, 0, -1))
POLE_R = (-0.8, 0.45, -0.5)  # elbows out, back and down
POLE_L = (0.8, 0.45, -0.5)
PRESS_ROT = (-30, 0, 0)  # the right fist down and a little forward: it presses with its wrist above it
# Her elbows are about the counter's height: resting, her hands are clasped before her tummy just
# above its edge (lower, her forearms would go through it); reaching onto it, her elbows go out to the
# side, up off the counter (POLE_OUT); pressing the lever (at the back of the toaster's end, her side)
# her elbow comes from behind and below it (POLE_PRESS).
REST_R = ((-0.06, -0.2, 0.715), (-75, 0, 30), POLE_R)
REST_L = ((0.06, -0.2, 0.715), (-75, 0, -30), POLE_L)
POLE_OUT_R = (-0.9, 0.3, 0.3)
POLE_OUT_L = (0.9, 0.3, 0.3)
POLE_UP_L = (0.7, 0.2, 0.7)  # her left elbow high: reaching down onto the plate, her forearm clears its rim
POLE_PRESS = (0.15, 0.5, 0.85)  # up and back: her forearm comes down onto her fist from above
POLE_KNOCK = (-0.3, 0.2, 0.95)  # up: her forearm comes down onto the toaster's top


def on_top(point, hand_rot, gap=0.0):
    """The palm centre for a hand laid on a surface at `point` (the hand's lowest point there)."""
    return tuple(Vector(point) + Vector((0, 0, hand_reach(hand_rot, DOWN) + gap)))


def grip_on(point, hand_rot, side="l"):
    """The palm centre for a hand taking something at `point` (its top): the hand or its thumb on it."""
    return tuple(Vector(point) + Vector((0, 0, grip_reach(hand_rot, DOWN, side))))


def look_rot(fist, thumb):
    """A hand turned so its fist points along `fist` and its thumb's side along `thumb` (her space),
    as degrees (XYZ): the hand's rest frame has the fist down its -Z and the thumb out of its -Y."""
    f = Vector(fist).normalized()
    u = Vector(thumb)
    u = (u - f * u.dot(f)).normalized()
    z = -f
    y = -u
    x = y.cross(z)
    return euler_of(Matrix((x, y, z)).transposed().to_quaternion())


TOAST_THICK = 0.0152  # a slice's mesh, crust and all (a little over K.TOAST_T)
# The grab: her left hand comes down on the top slice (it lies on the other, its crust's top away from
# her) a little left of its middle (BITE_SIDE), fingers forward and down: her wrist and forearm stay
# up off it.
BITE_SIDE = 0.03
GRAB_ROT = look_rot((0.0, -1.0, -0.6), (-1.0, 0.0, 0.0))
GRAB_AT = PLATE_TOP + Vector((BITE_SIDE, -0.012, 2 * TOAST_THICK))  # where her hand comes down on it (past its
# middle: less of it under her wrist)
# The bite: she turns the slice up (BITE_ROT: fingers up and tipped towards her, the palm away, the
# slice beyond it) and brings its top to her lips, right of its middle (where the bitten slice,
# kitchen.py, has its bite). Her palm goes where that point of the slice, held as at the grab, meets
# her lips (as she stands at the bite, BITE_POSE).
BITE_ROT = look_rot(Vector((0.0, 0.5, 1.0)).normalized(), (-1.0, 0.0, 0.0))
BITE_POSE = {"lean": 6.0, "turn": -10.0, "nod": 7.0, "look": 4.0}
BITE_LIPS = head_point(MOUTH + Vector((0.0, -0.004, 0.004)), **BITE_POSE)
_SLICE = PLATE_TOP + Vector((0.0, 0.0, 1.5 * TOAST_THICK))  # the top slice's middle, on the plate
_BITE_ON_SLICE = _SLICE + Vector((-K.TOAST_W * 0.32, -0.485 * K.TOAST_H, TOAST_THICK / 2))  # its top, upper face
_IN_HAND = q_of(GRAB_ROT).inverted() @ (_BITE_ON_SLICE - Vector(grip_on(GRAB_AT, GRAB_ROT)))
BITE_PALM = BITE_LIPS - q_of(BITE_ROT) @ _IN_HAND


def supervisors():
    """The golden toast (A): click, a glance at us, drumming fingers, a nose-up sniff, DING, the slices
    flip onto her plate (she follows them up and down), a hop of joy, a winking thumbs up to her
    grandson's photo, CRUNCH, bliss."""
    p = Performance(A_LENGTH, {"r": REST_R, "l": REST_L})
    knob = PRESS_AT
    # 0.42: she reaches for the lever (anticipation: the hand rises above it, she leans in, eyes on it)...
    p.key(0.25, "io", r=((-0.08, -0.2, 0.87), (-72, 0, 15), POLE_PRESS))
    p.key(0.42, "io", lean=3.0, turn=-2.0, nod=8.0, look=-14.0, gaze_x=-0.008, gaze_z=-0.007, brow=0.004,
          r=(on_top(knob + Vector((0, 0.0, 0.06)), PRESS_ROT), PRESS_ROT, None))
    p.key(0.62, "io", lean=4.0, turn=-3.0, r=(on_top(knob + Vector((0, 0, 0.035)), PRESS_ROT), None, None),
          mouth="flat", brow=-0.003)
    # ...0.78 the palm meets the knob, 0.88 it's down: CLICK.
    p.key(A_CLICK - 0.1, "in", lean=5.0, r=(on_top(knob, PRESS_ROT), PRESS_ROT, None))
    p.key(A_CLICK, "in", lean=6.0, nod=11.0, r=(on_top(knob - Vector((0, 0, K.LEVER_TRAVEL - 0.0015)), PRESS_ROT), PRESS_ROT,
                                                None))
    p.hold(A_CLICK + 0.04, "palm_r", "lean")
    p.key(1.06, "out", lean=5.0, r=(on_top(knob - Vector((0, 0, K.LEVER_TRAVEL)) + Vector((0, 0, 0.012)), PRESS_ROT),
                                    PRESS_ROT, None), mouth="smile", brow=0.006)
    p.key(1.22, "io", r=(on_top(knob + Vector((0, 0.02, 0.04)), PRESS_ROT), None, None))
    p.hold(1.22, "pole_r")
    # 1.4: straight up again, a pleased little look at us (any minute now...).
    tap_spot = Vector((-0.06, -0.255, K.COUNTER_H))
    p.key(1.4, "io", lean=4.0, turn=-2.0, nod=0.0, look=0.0, gaze_x=0.0, gaze_z=0.0, brow=0.01,
          r=(on_top(tap_spot + Vector((0, 0, 0.03)), PRESS_ROT), PRESS_ROT, (-0.8, 0.2, 0.55)))
    p.hold(1.4, "tilt", "lid", "brow_tilt")
    # 1.5 - 2.3: drumming her fingers on the counter, swaying, eyes back on the toaster.
    for k, at in enumerate((1.6, 1.85, 2.1)):
        p.key(at - 0.09, "out", r=(on_top(tap_spot + Vector((0, 0, 0.025)), PRESS_ROT), None, None))
        p.key(at, "in", r=(on_top(tap_spot, PRESS_ROT), None, None), tilt=(5.0 if k % 2 else -5.0), lid=0.2,
              look=-8.0, gaze_x=-0.007, gaze_z=-0.004, brow=0.004)
    p.key(2.3, "io", r=REST_R, tilt=0.0, lid=0.0, lean=2.0)
    p.hold(2.3, "brow_tilt")
    # 2.55 - 3.2: she leans towards the toaster, nose in the air, eyes shut, and sniffs (mmm...).
    p.key(2.6, "io", lean=10.0, turn=-12.0, nod=-12.0, look=-14.0, lid=1.0, brow=0.013, brow_tilt=6.0, mouth="o",
          gaze_x=0.0, gaze_z=0.0, blush=1.25)
    p.key(2.75, "out", nod=-15.0)
    p.key(2.85, "in", nod=-9.0)
    p.key(2.98, "out", nod=-15.0)
    # 3.3: back up, hands together at her chin, eager.
    eager_r = ((-0.035, -0.2, 0.8), (-110, 0, 50), POLE_R)
    eager_l = ((0.035, -0.2, 0.8), (-110, 0, -50), POLE_L)
    p.hold(2.95, "palm_l", "rot_l")
    p.key(3.3, "io", lean=4.0, turn=-4.0, nod=2.0, look=-8.0, lid=0.0, brow=0.008, brow_tilt=0.0, mouth="smile",
          gaze_x=-0.006, gaze_z=-0.004, r=eager_r, l=eager_l)
    # 3.8 DING: a start (up on her toes, eyes wide), her head snaps up after the first slice...
    p.key(A_DING, "step", wide=1.0)
    p.hold(A_DING, "hop", "squash")
    p.key(3.88, "out", hop=0.012, squash=-0.04, wide=1.3, brow=0.02, nod=-10.0, look=-4.0, mouth="o",
          gaze_x=0.0, gaze_z=0.009)
    p.key(4.15, "io", hop=0.0, squash=0.0, nod=-18.0, look=4.0, gaze_z=0.011)
    # ...and follows it down onto the plate (on her left).
    p.key(4.55, "io", nod=6.0, look=16.0, wide=1.15, gaze_x=0.008, gaze_z=-0.007)
    p.key(4.95, "io", nod=7.0, look=17.0)
    # 5.05: joy! She clasps her hands, crouches (anticipation), hops, lands, the bun bobbing.
    clasp_r = ((-0.035, -0.175, 0.8), (-100, 0, 55), POLE_R)
    clasp_l = ((0.035, -0.175, 0.8), (-100, 0, -55), POLE_L)
    p.hold(A_JOY, "squash", "hop", "lean", "tilt")
    p.key(A_JOY, "io", mouth="grin", happy=1.0, blush=1.4, brow=0.016, nod=0.0, look=4.0, gaze_x=0.0, gaze_z=0.0,
          r=clasp_r, l=clasp_l)
    p.key(5.17, "out", squash=0.1, hop=0.0, lean=0.0)
    p.key(5.3, "out", squash=-0.1, hop=0.07, lean=-6.0, tilt=6.0)
    p.key(5.42, "in", squash=0.1, hop=0.0, lean=-1.0, tilt=0.0)
    p.key(5.56, "back", squash=0.0, lean=0.0)
    # 5.65 - 6.4: she turns to her grandson's photo, beaming, winks, and gives it a big thumbs up.
    thumbs = look_rot((-0.75, 0.5, 0.2), (0.0, 0.0, 1.0))
    p.hold(5.5, "turn")
    p.key(5.8, "io", turn=-18.0, look=-72.0, nod=-12.0, tilt=-5.0, happy=0.0, mouth="smile", brow=0.012, blush=1.25,
          gaze_x=-0.008, gaze_z=0.006, l=((0.08, -0.17, 0.78), (-90, 0, -40), POLE_L),
          r=((-0.4, 0.02, 0.95), thumbs, (-0.6, 0.4, -0.5)))
    p.hold(5.8, "thumb_r")
    p.key(5.92, "back", thumb_r=-50.0, lid_l=1.0, r=((-0.42, 0.03, 0.99), None, None))
    p.key(6.25, "io", nod=-8.0, r=((-0.415, 0.03, 0.98), None, None))
    # 6.4 - 6.55: back to the plate; her left hand comes down on the top slice...
    flat_l = GRAB_ROT
    on_slice = GRAB_AT
    p.key(6.42, "io", lean=5.0, turn=-10.0, look=14.0, nod=6.0, tilt=0.0, thumb_r=0.0, lid_l=None, r=REST_R,
          gaze_x=0.006, gaze_z=-0.007, l=(grip_on(on_slice + Vector((0, 0.01, 0.05)), flat_l), flat_l, POLE_UP_L))
    p.key(A_GRAB, "in", lean=5.0, turn=-11.0, look=14.0, nod=10.0, l=(grip_on(on_slice, flat_l), flat_l, None))
    # ...lifts it, turns it up to her mouth, opens wide, and CRUNCH on its top.
    p.key(6.66, "out", lean=5.0, look=8.0, nod=6.0, l=(grip_on(on_slice + Vector((0.0, 0.0, 0.1)), flat_l), flat_l,
                                                      None))
    p.key(6.76, "io", l=((0.13, -0.3, 0.87), None, None))
    p.key(6.85, "io", lean=5.0, turn=-8.0, look=4.0, nod=3.0, mouth="grin", gaze_x=0.0, gaze_z=-0.004,
          l=(BITE_PALM + Vector((0.0, -0.022, 0.015)), BITE_ROT, POLE_UP_L))
    p.key(A_BITE, "in", l=(BITE_PALM, BITE_ROT, POLE_UP_L), **BITE_POSE)
    p.hold(A_BITE, "chew", "blush")
    p.key(7.05, "out", lean=2.0, turn=-3.0, nod=-4.0, mouth="smile", happy=1.0,
          l=((0.09, -0.2, 0.75), look_rot((0.0, -0.15, 1.0), (-1.0, 0.0, 0.0)), POLE_UP_L), chew=1.0, blush=1.45,
          gaze_z=0.0)
    # 7.05 - 8.3: bliss: chewing, eyes closed, a little sway.
    p.key(7.45, "io", l=(None, None, POLE_L))
    p.key(7.6, "io", tilt=6.0, nod=-6.0)
    p.key(8.1, "io", tilt=-3.0, nod=-4.0)
    return p


def rats():
    """The power cut (B): the lamp flickers, a feeble click, a nose-up sniff... nothing. Two raps on the
    toaster, pwomp, a limp slice: shock, a pout, a glance at the photo; the lights go out; in the dark
    she finds her matches, strikes one, looks round, baffled, and blows it out."""
    p = Performance(B_LENGTH, {"r": REST_R, "l": REST_L})
    knob = PRESS_AT
    p.key(0.3, "io", lid=0.15)
    # 0.4: the lamp flickers: a glance up at it.
    p.key(0.5, "io", nod=-14.0, look=6.0, gaze_z=0.01, brow=0.008, lid=0.0,
          r=((-0.08, -0.2, 0.87), (-72, 0, 15), POLE_PRESS))
    p.key(0.7, "io", nod=7.0, look=-14.0, gaze_x=-0.008, gaze_z=-0.007, brow=0.0, lean=4.0, turn=-3.0,
          r=(on_top(knob + Vector((0, 0, 0.035)), PRESS_ROT), PRESS_ROT, None))
    p.key(B_CLICK - 0.1, "in", lean=5.0, r=(on_top(knob, PRESS_ROT), PRESS_ROT, None), mouth="flat")
    p.key(B_CLICK, "in", lean=6.0, nod=11.0, r=(on_top(knob - Vector((0, 0, K.LEVER_TRAVEL - 0.0015)), PRESS_ROT), PRESS_ROT,
                                                None))
    p.hold(B_CLICK + 0.04, "palm_r", "lean")
    p.key(1.06, "out", lean=5.0, r=(on_top(knob - Vector((0, 0, K.LEVER_TRAVEL)) + Vector((0, 0, 0.012)), PRESS_ROT),
                                    PRESS_ROT, None))
    p.key(1.22, "io", r=(on_top(knob + Vector((0, 0.02, 0.04)), PRESS_ROT), None, None))
    p.hold(1.22, "pole_r")
    p.key(1.45, "io", lean=3.0, turn=-3.0, nod=2.0, look=-8.0, r=REST_R, mouth="smile", brow=0.004, gaze_x=-0.006,
          gaze_z=-0.005)
    # 2.0 - 2.6: she leans in, nose up, sniffs... nothing. A head tilt: hm?
    p.hold(1.85, "lid", "tilt")
    p.key(2.05, "io", lean=6.0, turn=-12.0, nod=-12.0, look=-14.0, lid=1.0, brow=0.01, mouth="o", gaze_x=0.0,
          gaze_z=0.0)
    p.key(2.2, "out", nod=-15.0)
    p.key(2.32, "in", nod=-9.0)
    p.key(2.45, "out", nod=-15.0)
    p.key(2.65, "io", lean=8.0, nod=2.0, lid=0.0, tilt=12.0, brow=0.012, brow_l=-0.004, mouth="flat", gaze_x=-0.007,
          gaze_z=-0.005)
    p.hold(2.6, "palm_r", "rot_r", "brow_tilt")
    # 2.75 - 3.4: a frown, and two raps on the toaster with her knuckles.
    knock_rot = (-35, 0, 10)  # a fist, its knuckles down: her wrist above it, clear of the toaster
    knock = TOASTER_TOP_END
    p.key(2.72, "io", r=(knock + Vector((0.02, 0.09, 0.14)), knock_rot, POLE_KNOCK))
    p.key(2.85, "io", tilt=0.0, brow=-0.006, brow_l=None, brow_tilt=-8.0, lean=8.0, turn=4.0, mouth="pout",
          r=(on_top(knock + Vector((0, 0, 0.06)), knock_rot), knock_rot, POLE_KNOCK))
    for at in B_TAPS:
        p.key(at, "in", r=(on_top(knock, knock_rot), None, None))
        p.key(at + 0.11, "out", r=(on_top(knock + Vector((0, 0, 0.045)), knock_rot), None, None))
    p.key(3.45, "io", r=(on_top(knock + Vector((0, 0.02, 0.07)), knock_rot), None, None))
    p.key(3.58, "io", r=(knock + Vector((0.02, 0.09, 0.14)), None, None))
    p.key(3.7, "io", lean=4.0, turn=-4.0, r=REST_R, brow=0.0, brow_tilt=0.0, mouth="flat")
    # 3.8 pwomp: the slices creep up; she leans in to see, hopeful...
    p.key(4.25, "io", lean=4.0, nod=6.0, look=-14.0, brow=0.008, gaze_x=-0.008, gaze_z=-0.006)
    # 4.6: the limp slice flops over: shock! Brows up, glasses down her nose, "O".
    p.hold(B_SHOCK - 0.06, "hop", "squash", "glasses", "wide", "lid", "lean", "nod")
    p.key(B_SHOCK, "out", lean=-4.0, nod=-6.0, wide=1.35, brow=0.03, glasses=0.028, mouth="o", hop=0.008, squash=-0.05,
          gaze_x=0.0, gaze_z=0.0, lid=0.0)
    p.key(4.75, "io", hop=0.0, squash=0.0)
    p.hold(4.75, "droop", "blush", "lid", "brow_tilt")
    # 5.1: a disappointed pout, eyes half shut, the bun drooping.
    p.key(5.1, "io", lean=4.0, nod=8.0, wide=1.0, brow=-0.004, brow_tilt=12.0, lid=0.45, mouth="pout", blush=0.8,
          droop=14.0, gaze_z=-0.004)
    # 5.35: a glance at her grandson's photo (it tilts), and back.
    p.hold(5.3, "turn", "look", "gaze_x", "gaze_z")
    p.key(5.5, "io", turn=-20.0, look=-58.0, nod=-10.0, gaze_x=-0.008, gaze_z=0.006, lid=0.3)
    p.key(5.74, "io", turn=-6.0, look=-10.0, nod=4.0, gaze_x=0.0, gaze_z=-0.004, lid=0.45)
    # 5.8: the lights go out. A small start, wide eyes in the dark.
    p.hold(B_BLACKOUT, "hop", "wide", "droop")
    p.key(B_BLACKOUT + 0.05, "out", wide=1.25, lid=0.0, brow=0.02, brow_tilt=4.0, mouth="flat", hop=0.006, droop=0.0)
    p.key(B_BLACKOUT + 0.2, "io", hop=0.0)
    # 7.0 - 7.8: in the dark she fishes her matches out of her apron and gets ready to strike.
    p.hold(6.85, "palm_r", "rot_r", "lean", "nod")
    p.hold(7.1, "palm_l", "rot_l")
    box_l = ((0.06, -0.24, 0.82), (-90, 0, -70), POLE_L)
    p.key(7.1, "io", r=((-0.19, -0.1, 0.56), (-60, 0, 20), POLE_R), lean=4.0, nod=6.0)
    p.key(7.55, "io", l=box_l, r=((-0.03, -0.25, 0.86), (-90, 0, 60), POLE_R), nod=4.0)
    # 7.85 scritch: the match strikes along the box. 7.9 the flame: her baffled face.
    p.key(B_STRIKE - 0.04, "in", r=((0.02, -0.26, 0.82), None, None))
    p.key(B_STRIKE + 0.05, "out", r=((-0.06, -0.26, 0.9), (-75, 0, 30), None), lean=4.0, nod=0.0, wide=1.25,
          brow=0.018, brow_l=0.005, brow_tilt=0.0, brow_tilt_l=-10.0, mouth="wavy", l=((0.08, -0.2, 0.74), None, None))
    # 8.0 the toaster (empty), 8.25 her plate (crumbs), 8.45 the tail slipping over the edge.
    p.hold(7.8, "turn", "look", "gaze_x", "gaze_z", "lid")
    p.key(8.0, "io", look=-22.0, nod=8.0, turn=-5.0, gaze_x=-0.008, gaze_z=-0.006)
    p.key(8.25, "io", look=16.0, nod=9.0, turn=4.0, gaze_x=0.008, gaze_z=-0.007)
    p.key(8.45, "io", look=4.0, nod=10.0, wide=1.4, brow=0.026, brow_l=0.012, gaze_x=0.002, gaze_z=-0.01)
    # 8.72: the match to her lips, and fft.
    p.key(8.72, "io", look=0.0, nod=2.0, r=((-0.03, -0.28, 0.86), None, None), mouth="blow", wide=1.0, brow=0.008,
          brow_l=None, gaze_x=0.0, gaze_z=-0.006)
    p.key(B_BLOW + 0.1, "out", mouth="flat", lid=0.2)
    return p


def build():
    bpy.context.scene.render.fps = PERF_FPS  # her clips are baked at PERF_FPS
    arm = build_model()
    add_marks(arm)
    anim = Animator(arm)
    k = PERF_FPS // 30
    anim.clip("idle", 150 * k, lambda f: idle_pose(f / k), loop=True)
    clip_of(anim, "outro_supervisors", supervisors())
    clip_of(anim, "outro_rats", rats())
    anim.finish()
    return [arm]


if __name__ == "__main__":
    a = C.args("grandma")
    C.reset()
    C.export(a.out, build(), animations=True)

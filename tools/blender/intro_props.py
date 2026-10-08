"""Props of the intro cinematic (client/intro/): the supervisors' desk, the hamster cages, the yellow
bottle of radioactive goo, the "days without an incident" board, and the little effect meshes
(hearts, goo blobs and puddles, a "!" mark).

    blender -b -P tools/blender/intro_props.py -- [--only hamster_cage,rad_bottle]

Origins at the base centre, front = -Y (Godot +Z), except the wall-mounted incident_board (origin at
the centre of its back face) and the effect meshes (origin at their centre). Animated children
(Godot code finds them by name):
  hamster_cage, hamster_cage_house  "Door" (hinge on its left edge, swings about Z), "Roof" (pivot
                                    at its back edge, flips about X); hamster_cage "Wheel" (spins
                                    about X, the axle)
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import dressing as D  # noqa: E402
import machines as M  # noqa: E402
import rat as R  # noqa: E402  (taper)
from mathutils import Vector  # noqa: E402

E, GL = C.MAT_EMISSIVE, C.MAT_GLASS

# --- Hamster cages ----------------------------------------------------------------------------------

CAGE_W, CAGE_D, TRAY_H, WIRE_H = 0.66, 0.44, 0.08, 0.4
DOOR_W, DOOR_H = 0.2, 0.22  # the door opening in the front, centred
BAR_R = 0.0042


def _rod(b, p0, p1, r, color):
    """A thin wire from p0 to p1 (4 sides, no caps: they read as wires once outlined)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler("XYZ")
    b.cylinder(r, d.length, (p0 + p1) / 2, color, rot=[math.degrees(a) for a in rot], segments=4, smooth=False,
               caps=False)


def _cage_wires(b, skip_door=True):
    """The wire box on top of the tray: corner posts, rails, bars on the four sides (none where the
    door is)."""
    w, d = CAGE_W / 2 - 0.015, CAGE_D / 2 - 0.015
    z0, z1 = TRAY_H, TRAY_H + WIRE_H
    for sx in (-1, 1):
        for sy in (-1, 1):
            _rod(b, (sx * w, sy * d, z0), (sx * w, sy * d, z1), 0.008, "silver")
    for z in (z0 + 0.012, z0 + WIRE_H * 0.55, z1):
        for sy in (-1, 1):
            _rod(b, (-w, sy * d, z), (w, sy * d, z), 0.006, "silver")
        for sx in (-1, 1):
            _rod(b, (sx * w, -d, z), (sx * w, d, z), 0.006, "silver")
    n = 12
    for k in range(1, n):
        x = -w + 2 * w * k / n
        _rod(b, (x, d, z0), (x, d, z1), BAR_R, "silver")  # back
        if not (skip_door and abs(x) < DOOR_W / 2 + 0.01):
            _rod(b, (x, -d, z0), (x, -d, z1), BAR_R, "silver")  # front
        elif skip_door:  # above the door opening
            _rod(b, (x, -d, z0 + DOOR_H + 0.03), (x, -d, z1), BAR_R, "silver")
    for k in range(1, 8):
        y = -d + 2 * d * k / 8
        for sx in (-1, 1):
            _rod(b, (sx * w, y, z0), (sx * w, y, z1), BAR_R, "silver")
    # the door frame
    _rod(b, (-DOOR_W / 2, -d, z0 + DOOR_H + 0.03), (DOOR_W / 2, -d, z0 + DOOR_H + 0.03), 0.006, "silver")


def _cage_tray(b, plastic, accent):
    """The plastic base: a tub with rounded corners and a darker rim, bedding inside."""
    b.box((CAGE_W, CAGE_D, TRAY_H), (0, 0, 0), plastic, base=True, bevel=0.025)
    b.box((CAGE_W + 0.012, CAGE_D + 0.012, 0.018), (0, 0, TRAY_H - 0.018), accent, base=True, bevel=0.008)
    for sx in (-1, 1):  # little clips holding the wire top
        for sy in (-1, 1):
            b.box((0.04, 0.03, 0.03), (sx * (CAGE_W / 2 - 0.06), sy * (CAGE_D / 2 + 0.004), TRAY_H - 0.005), accent,
                  bevel=0.006)
    # Wood shavings: a lumpy layer with a few curls.
    rng = random.Random(5)
    D.lumpy(b, b.box, 0.004, rng, (CAGE_W - 0.04, CAGE_D - 0.04, 0.02), (0, 0, TRAY_H - 0.03), "wood_light",
            base=True)
    for _ in range(14):
        x, y = rng.uniform(-0.28, 0.28), rng.uniform(-0.18, 0.18)
        b.box((0.03, 0.012, 0.008), (x, y, TRAY_H - 0.01), rng.choice(["wood_light", "cardboard", "wood"]),
              rot=(rng.uniform(-20, 20), 0, rng.uniform(0, 180)))


def _water_bottle(b, x, y):
    """A drinking bottle clipped to the outside of a side wall, nozzle poking in."""
    z = TRAY_H + 0.12
    b.cylinder(0.03, 0.17, (x, y, z), "glass", base=True, segments=10, material=GL)
    b.cylinder(0.026, 0.12, (x, y, z + 0.005), "sky", base=True, segments=10)
    b.cylinder(0.032, 0.03, (x, y, z + 0.17), "alarm_red", base=True, segments=10)
    b.cylinder(0.032, 0.025, (x, y, z - 0.02), "alarm_red", base=True, segments=10)
    _rod(b, (x, y, z - 0.02), (x - math.copysign(0.05, x), y, z - 0.07), 0.007, "steel_light")


def _food_bowl(b, x, y):
    b.cylinder(0.05, 0.03, (x, y, TRAY_H - 0.012), "orange", base=True, segments=12, radius_top=0.056, bevel=0.004)
    rng = random.Random(9)
    for _ in range(9):
        a, r = rng.uniform(0, 6.28), rng.uniform(0, 0.035)
        b.sphere(0.008, (x + math.cos(a) * r, y + math.sin(a) * r, TRAY_H + 0.02), rng.choice(["dough", "wood", "cheese"]),
                 scale=(1.4, 1, 0.7), segments=5, rings=3)


def _door(root, plastic):
    door = C.Builder("Door")
    d = CAGE_D / 2 - 0.015
    x0, z0 = -DOOR_W / 2, TRAY_H + 0.008
    for k in range(5):
        x = x0 + 0.02 + (DOOR_W - 0.04) * k / 4
        _rod(door, (x, -d - 0.006, z0), (x, -d - 0.006, z0 + DOOR_H), BAR_R, "silver")
    for z in (z0, z0 + DOOR_H):
        _rod(door, (x0, -d - 0.006, z), (x0 + DOOR_W, -d - 0.006, z), 0.006, "silver")
    door.box((0.03, 0.02, 0.05), (x0 + DOOR_W - 0.02, -d - 0.02, z0 + DOOR_H * 0.5), plastic, bevel=0.006)  # latch
    door.finish(pivot=(x0, -d, 0), parent=root)


def _roof(root):
    roof = C.Builder("Roof")
    w, d = CAGE_W / 2 - 0.015, CAGE_D / 2 - 0.015
    z = TRAY_H + WIRE_H + 0.008
    for k in range(1, 12):
        x = -w + 2 * w * k / 12
        _rod(roof, (x, -d, z), (x, d, z), BAR_R, "silver")
    for sy in (-1, 1):
        _rod(roof, (-w, sy * d, z), (w, sy * d, z), 0.006, "silver")
    # The carrying handle.
    roof.tube([(-0.09, 0, z), (-0.08, 0, z + 0.05), (0.08, 0, z + 0.05), (0.09, 0, z)], 0.008, "grey_dark", segments=6)
    roof.finish(pivot=(0, d, z), parent=root)


def _wheel(root, x, y):
    """The exercise wheel on its stand: the stand stays, the "Wheel" spins about X."""
    b = C.Builder("WheelStand")
    r, width = 0.15, 0.19
    cz = TRAY_H + r + 0.02
    sx = x + width / 2 + 0.02
    _rod(b, (sx, y - 0.07, TRAY_H - 0.01), (sx, y, cz), 0.009, "steel_light")
    _rod(b, (sx, y + 0.07, TRAY_H - 0.01), (sx, y, cz), 0.009, "steel_light")
    b.cylinder(0.02, 0.03, (sx - 0.012, y, cz), "grey_dark", rot=(0, 90, 0), segments=8)
    stand = b.finish()
    stand.parent = root
    w = C.Builder("Wheel")
    for s in (-1, 1):
        w.torus(r, 0.01, (x + s * width / 2, y, cz), "icing_pink", rot=(0, 90, 0), segments=18, sides=4)
    for k in range(18):  # the running rungs
        a = 2 * math.pi * k / 18
        p = (y + math.cos(a) * r, cz + math.sin(a) * r)
        _rod(w, (x - width / 2, p[0], p[1]), (x + width / 2, p[0], p[1]), 0.0045, "silver")
    for k in range(5):  # spokes on the open side
        a = 2 * math.pi * k / 5
        _rod(w, (x + width / 2, y, cz), (x + width / 2, y + math.cos(a) * r, cz + math.sin(a) * r), 0.006, "icing_pink")
    w.cylinder(0.022, 0.02, (x + width / 2, y, cz), "icing_pink", rot=(0, 90, 0), segments=8)
    w.finish(pivot=(x, y, cz), parent=root)


def _house(b, x, y):
    """A little wooden hide-out with a round doorway and a pitched roof."""
    z = TRAY_H - 0.01
    b.box((0.17, 0.14, 0.11), (x, y, z), "wood", base=True, bevel=0.01)
    b.cylinder(0.04, 0.012, (x, y - 0.07, z + 0.045), "brown_dark", rot=(90, 0, 0), segments=12)
    for s in (-1, 1):
        b.box((0.11, 0.19, 0.016), (x + s * 0.045, y, z + 0.14), "brown", rot=(0, s * 35, 0), bevel=0.004)
    b.box((0.04, 0.03, 0.03), (x - 0.03, y - 0.075, z + 0.09), "dough", bevel=0.005)  # a treat on the sill


def _tube(b, x, y):
    """A cardboard tunnel lying in the bedding."""
    M.hollow(b, 0.045, 0.038, 0.16, (x, y, TRAY_H + 0.03), "cardboard", rot=(90, 0, 75), inner="brown_dark", seg=12)


def build_hamster_cage(house=False, name="HamsterCage"):
    b = C.Builder(name)
    plastic, accent = ("icing_pink", "red_dark") if house else ("sky", "blue")
    _cage_tray(b, plastic, accent)
    _cage_wires(b)
    _food_bowl(b, -0.2, 0.08)
    if house:
        _house(b, 0.16, 0.06)
        _tube(b, -0.12, -0.08)
        _water_bottle(b, -CAGE_W / 2 - 0.02, 0.1)
    else:
        _water_bottle(b, CAGE_W / 2 + 0.02, 0.1)
    root = b.finish()
    _door(root, plastic)
    _roof(root)
    if not house:
        _wheel(root, 0.12, 0.02)
    return root


# --- The bottle -----------------------------------------------------------------------------------

def build_rad_bottle(name="RadBottle"):
    """A chunky yellow jug of glowing green goo: trefoil label, a window showing the level, the cap
    off and dangling on its strap, goo dribbling from the neck. 0.2 x 0.14 x 0.34."""
    b = C.Builder(name)
    W, Dp, H = 0.2, 0.14, 0.24
    b.box((W, Dp, H), (0, 0, 0), "safety_yellow", base=True, bevel=0.035)
    b.box((W - 0.03, Dp - 0.03, 0.05), (0, 0, H - 0.01), "safety_yellow", base=True, bevel=0.022)  # shoulder
    b.box((W + 0.006, Dp + 0.006, 0.02), (0, 0, 0.03), "yellow_dark", base=True, bevel=0.006)  # base ridge
    # Neck, offset forward like a jerrycan's; the handle behind it.
    nx, ny, nz = 0.0, -0.025, H + 0.035
    M.hollow(b, 0.034, 0.026, 0.055, (nx, ny, nz), "yellow_dark", base=True, inner="rad_green", seg=12)
    b.cylinder(0.027, 0.01, (nx, ny, nz + 0.045), "rad_green", base=True, segments=12, material=E)  # goo surface
    b.tube([(-0.06, 0.035, H + 0.02), (-0.05, 0.04, H + 0.085), (0.05, 0.04, H + 0.085), (0.06, 0.035, H + 0.02)],
           0.014, "yellow_dark", segments=6)
    # Goo welling over the lip and dribbling down the shoulder and the front.
    rng = random.Random(3)
    D.lumpy(b, b.torus, 0.002, rng, 0.03, 0.009, (nx, ny, nz + 0.055), "rad_green", segments=12, sides=5,
            material=E)
    for k, (dx, z0, length) in enumerate(((0.018, nz + 0.05, 0.05), (-0.012, nz + 0.045, 0.035))):
        b.sphere(0.011, (nx + dx, ny - 0.034, z0 - length / 2), "rad_green", scale=(1, 0.7, length / 0.022),
                 segments=8, rings=5, material=E)
    b.sphere(0.014, (nx + 0.02, -Dp / 2 + 0.004, H + 0.005), "rad_green", scale=(1.2, 0.7, 0.8), segments=8, rings=5,
             material=E)
    b.sphere(0.012, (nx + 0.022, -Dp / 2 - 0.004, H - 0.035), "rad_green", scale=(1, 0.6, 2.2), segments=8, rings=5,
             material=E)
    # The cap, hanging by its strap on the side.
    b.tube([(nx + 0.034, ny, nz + 0.02), (W / 2 + 0.01, ny, nz - 0.02), (W / 2 + 0.02, ny, H - 0.09)], 0.004,
           "red_dark", segments=4)
    b.cylinder(0.036, 0.03, (W / 2 + 0.025, ny, H - 0.11), "alarm_red", rot=(0, 75, 0), segments=12, bevel=0.005)
    # Front label: black-edged, with the trefoil; a level window on the side.
    M.trefoil(b, 0.11, (0, -Dp / 2, 0.12), "front", plate="safety_yellow")
    b.box((0.13, 0.004, 0.13), (0, -Dp / 2 - 0.0005, 0.12), "black")
    b.box((0.06, 0.004, 0.012), (0, -Dp / 2 - 0.004, 0.035), "black")
    for s in (-1, 1):
        b.box((0.004, 0.04, 0.17), (s * (W / 2 + 0.001), 0, 0.045), "charcoal", base=True)
        b.box((0.004, 0.028, 0.15), (s * (W / 2 + 0.002), 0, 0.05), "rad_green", base=True, material=E)
    return b.finish()


# --- The incident board ------------------------------------------------------------------------------

def build_incident_board(name="IncidentBoard"):
    """The "DAYS WITHOUT AN INCIDENT" board (wall mounted, origin at the back centre, 1.1 x 0.74).
    The words and the number are Label3Ds placed by client/intro/intro_set.gd: a green header band
    (white text) and a black counter window (lit digits) under it, a first-aid cross beside it."""
    b = C.Builder(name)
    W, H, T = 1.1, 0.74, 0.03
    b.box((W, T, H), (0, -T / 2, 0), "off_white", bevel=0.01)
    b.box((W + 0.04, T * 0.6, H + 0.04), (0, -T * 0.3 + 0.002, 0), "teal_dark", bevel=0.012)  # frame
    b.box((W - 0.06, 0.006, 0.22), (0, -T - 0.003, H / 2 - 0.15), "pipe_green")  # header band
    b.box((0.52, 0.01, 0.26), (-0.12, -T - 0.005, -0.14), "black", bevel=0.004)  # counter window
    b.box((0.54, 0.006, 0.28), (-0.12, -T - 0.001, -0.14), "grey_dark")
    for k in range(1, 3):  # dividers between the three digit cards
        b.box((0.006, 0.012, 0.24), (-0.12 - 0.26 + 0.52 * k / 3, -T - 0.009, -0.14), "charcoal")
    # First-aid cross on a green square.
    b.box((0.2, 0.008, 0.2), (0.33, -T - 0.004, -0.14), "pipe_green", bevel=0.004)
    b.box((0.13, 0.012, 0.042), (0.33, -T - 0.009, -0.14), "white")
    b.box((0.042, 0.012, 0.13), (0.33, -T - 0.009, -0.14), "white")
    for sx in (-1, 1):  # screws
        for sz in (-1, 1):
            M.cyl(b, 0.012, 0.01, (sx * (W / 2 - 0.03), -T, sz * (H / 2 - 0.03)), "steel_light", rot=M.FACE["front"],
                  seg=6, base=True)
    return b.finish()


# --- The desk -----------------------------------------------------------------------------------------

def build_supervisor_desk(name="SupervisorDesk"):
    """The supervisors' long desk: 3.0 x 0.85, 0.76 high, drawer pedestals at both ends, a modesty
    panel, a phone and a pencil pot (the rest of the clutter is placed by code)."""
    b = C.Builder(name)
    L, Dp, H = 3.0, 0.85, 0.76
    b.box((L, Dp, 0.05), (0, 0, H - 0.05), "wood_light", base=True, bevel=0.015)
    b.box((L - 0.04, Dp - 0.04, 0.012), (0, 0, H - 0.062), "wood", base=True)
    for sx in (-1, 1):
        x = sx * (L / 2 - 0.25)
        b.box((0.45, Dp - 0.1, H - 0.08), (x, 0.02, 0.02), "steel_light", base=True, bevel=0.012)
        for k in range(3):
            z = 0.1 + k * 0.22
            b.box((0.41, 0.012, 0.19), (x, -Dp / 2 + 0.065, z), "steel", base=True, bevel=0.005)
            b.box((0.12, 0.025, 0.02), (x, -Dp / 2 + 0.05, z + 0.15), "grey_dark", bevel=0.005)
        b.box((0.45, Dp - 0.1, 0.02), (x, 0.02, 0.0), "steel_dark", base=True)
    b.box((L - 1.0, 0.025, 0.42), (0, 0.3, 0.28), "steel", base=True, bevel=0.006)  # modesty panel
    D.phone(b, (1.2, 0.22, H), yaw=-15)
    M.cyl(b, 0.035, 0.1, (-1.25, 0.25, H), "teal", seg=10, base=True)  # pencil pot
    for k, col in enumerate(("alarm_red", "blue", "safety_yellow")):
        b.cylinder(0.006, 0.15, (-1.25 + (k - 1) * 0.012, 0.25 + (k % 2) * 0.01, H + 0.05), col,
                   rot=((k - 1) * 8, (1 - k) * 6, 0), segments=5)
    return b.finish()


# --- Effect meshes (origin at the centre) --------------------------------------------------------------

def build_heart(name="Heart"):
    """A chunky cartoon heart, 0.12 wide, facing -Y (glows a little, so it reads in any light)."""
    b = C.Builder(name)
    for s in (-1, 1):
        b.sphere(0.034, (s * 0.027, 0, 0.018), "icing_pink", scale=(1, 0.55, 1), segments=12, rings=7, material=E)
    # The point: a cone under the lobes, flattened to their depth.
    before = set(b.bm.verts)
    b.cylinder(0.003, 0.074, (0, 0, -0.033), "icing_pink", radius_top=0.056, segments=14, material=E)
    R.taper(b, before, 2, -1.0, 1.0, (1, 0.55, 1), (1, 0.55, 1))
    b.sphere(0.008, (-0.03, -0.017, 0.032), "white", segments=5, rings=3, material=E)  # shine
    return b.finish()


def build_goo_blob(name="GooBlob"):
    """A lumpy blob of glowing goo, 0.1 across (scaled by code: droplets, gobs on fur)."""
    b = C.Builder(name)
    D.lumpy(b, b.sphere, 0.008, random.Random(4), 0.05, (0, 0, 0), "rad_green", segments=10, rings=7, material=E)
    b.sphere(0.007, (-0.02, -0.042, 0.024), "white", segments=5, rings=3, material=E)  # wet shine
    return b.finish()


def build_goo_puddle(name="GooPuddle"):
    """A splat of goo lying flat, about 0.5 across with droplets around it (origin at its centre)."""
    b = C.Builder(name)
    rng = random.Random(7)
    pts = []
    for k in range(18):
        a = 2 * math.pi * k / 18
        r = 0.2 * (1.0 + 0.25 * math.sin(3 * a + 0.5) + rng.uniform(-0.08, 0.12))
        pts.append((math.cos(a) * r, math.sin(a) * r))
    b.prism(pts, 0.012, (0, 0, 0), "rad_green", material=E)
    for _ in range(7):
        a, r = rng.uniform(0, 6.28), rng.uniform(0.27, 0.36)
        b.cylinder(rng.uniform(0.015, 0.035), 0.01, (math.cos(a) * r, math.sin(a) * r, 0), "rad_green", base=True,
                   segments=8, material=E)
    for _ in range(3):  # bubbles
        a, r = rng.uniform(0, 6.28), rng.uniform(0.0, 0.12)
        b.sphere(rng.uniform(0.015, 0.025), (math.cos(a) * r, math.sin(a) * r, 0.012), "rad_green",
                 scale=(1, 1, 0.6), segments=8, rings=4, material=E)
    return b.finish()


def build_exclaim(name="Exclaim"):
    """A red "!" (0.24 tall, origin at its base), popped over startled heads."""
    b = C.Builder(name)
    for shape in D.exclaim(0.24):
        pts = [(x, y + 0.12) for x, y in shape]
        b.prism(pts, 0.04, (0, 0.02, 0), "alarm_red", rot=(90, 0, 0), material=E, bevel=0.006)
    return b.finish()


BUILDERS = {
    "hamster_cage": build_hamster_cage, "rad_bottle": build_rad_bottle, "incident_board": build_incident_board,
    "supervisor_desk": build_supervisor_desk, "heart": build_heart,
    "goo_blob": build_goo_blob, "goo_puddle": build_goo_puddle, "exclaim": build_exclaim,
}

ASSETS = [
    ("hamster_cage", {"kind": "hamster_cage"}),
    ("hamster_cage_house", {"kind": "hamster_cage", "house": True, "name": "HamsterCageHouse"}),
    ("rad_bottle", {"kind": "rad_bottle"}),
    ("incident_board", {"kind": "incident_board"}),
    ("supervisor_desk", {"kind": "supervisor_desk"}),
    ("heart", {"kind": "heart"}),
    ("goo_blob", {"kind": "goo_blob"}),
    ("goo_puddle", {"kind": "goo_puddle"}),
    ("exclaim", {"kind": "exclaim"}),
]


def build(kind, **kwargs):
    return BUILDERS[kind](**kwargs)


if __name__ == "__main__":
    D.main("intro_props", ASSETS, build)

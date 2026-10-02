"""Big plant props: the reactor core and the turbine (hero machines), tanks, pipes, the valve rack,
rooftop fans, the cooling tower, ladders and floodlights.

    blender -b -P tools/blender/plant.py -- --kind reactor_core [--out PATH]

Sizes match the level's collision boxes (tools/map/gen_plant.py). Animated children:
reactor_core "Rod1".."Rod6" (slide along Z), turbine "Shaft" (spins about X), valve_rack_4m
"Wheel1".."Wheel4" (spin about X), roof_fan "Fan" (spins about Z).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import machines as M  # noqa: E402

KINDS = ["reactor_core", "turbine", "tank_horizontal", "tank_vertical", "pipe_2m", "pipe_elbow", "valve_rack_4m",
         "insulator_post", "roof_fan", "exhaust_stack", "vent_grille", "cooling_tower", "ladder_7m", "floodlight"]
ASSETS = [(k, {"kind": k}) for k in KINDS]


def radial_bolts(b, n, radius, z, r=0.035, h=0.03, color="steel_dark", phase=0.5):
    """Bolt heads around a vertical cylinder of `radius`, pointing outward, at height z."""
    for i in range(n):
        a = 360.0 * (i + phase) / n
        ra = math.radians(a)
        M.cyl(b, r, h, (math.cos(ra) * radius, math.sin(ra) * radius, z), color, rot=(0, 90, a), seg=6, base=True,
              smooth=False)
    return b


def _reactor_core():
    """Radius 1.8, 7 m tall from its base (the pool surface)."""
    b = C.Builder("ReactorCore")
    r = 1.8
    M.cyl(b, r, 5.4, (0, 0, 0), "steel", seg=24, base=True)
    # Glowing windows between the bands.
    for k in range(8):
        a = 360.0 * k / 8 + 22.5
        F = M.Frame((0, 0, 0), (0, 0, a))
        for z in (1.4, 3.4):
            b.box((0.06, 0.5, 1.0), F.p(r + 0.0, 0, z), "rad_green", rot=F.r(), material=C.MAT_EMISSIVE)
            b.box((0.05, 0.64, 1.14), F.p(r - 0.01, 0, z), "steel_dark", rot=F.r(), bevel=0.02)
    for z in (0.15, 2.4, 4.45, 5.3):  # bolted bands
        M.cyl(b, r + 0.08, 0.22, (0, 0, z), "steel_dark", seg=24, base=True, bevel=0.03)
        radial_bolts(b, 16, r + 0.08, z + 0.11)
    M.striped_band(b, r + 0.02, 0.4, 0.3, n=24)
    # Dome cap and the rod drive housings.
    M.lathe(b, [(r + 0.05, 5.4), (r, 5.7), (1.6, 6.1), (1.1, 6.45), (0.5, 6.6), (0.01, 6.62)], "steel_light", seg=24)
    rods = []
    for k in range(6):
        a = math.radians(60 * k + 30)
        x, y = math.cos(a) * 0.9, math.sin(a) * 0.9
        M.cyl(b, 0.16, 0.5, (x, y, 6.15), "grey_dark", seg=10, base=True, bevel=0.02)
        rods.append((x, y))
    M.cyl(b, 0.35, 0.5, (0, 0, 6.5), "safety_yellow", seg=12, base=True, bevel=0.03)
    M.trefoil(b, 0.5, (0, -r - 0.09, 4.0), "front")
    root = b.finish()
    for k, (x, y) in enumerate(rods):
        rod = C.Builder("Rod%d" % (k + 1))
        M.cyl(rod, 0.07, 0.55, (x, y, 6.6), "rad_green", seg=8, base=True, material=C.MAT_EMISSIVE)
        M.cyl(rod, 0.1, 0.08, (x, y, 7.15), "steel_dark", seg=8, base=True, bevel=0.01)
        rod.finish(pivot=(x, y, 6.6), parent=root)
    return root


def _turbine():
    """24 m along X, 4 m deep: a 3 m skid with a drum casing (radius 2, axis at z = 3)."""
    b = C.Builder("Turbine")
    b.box((24.0, 4.0, 0.3), (0, 0, 0), "steel_dark", base=True, bevel=0.04)
    b.box((23.0, 3.4, 2.0), (0, 0, 0.3), "orange_dark", base=True, bevel=0.06)
    M.hazard(b, 22.6, 0.25, (0, -1.7, 0.45), "front", stripe=0.25)
    M.hazard(b, 22.6, 0.25, (0, 1.7, 0.45), "back", stripe=0.25)
    for x in range(-10, 11, 4):  # pedestals under the drum
        b.box((1.0, 3.0, 0.8), (x, 0, 2.2), "steel", base=True, bevel=0.05)
    # The drum: a big casing tapering toward the generator end, with flanges.
    profile = [(1.4, -11.0), (1.75, -10.4), (2.0, -9.0), (2.0, 4.0), (1.85, 6.0), (1.6, 9.5), (1.3, 11.0)]
    M.lathe(b, profile, "orange", seg=20, loc=(0, 0, 3.0), rot=(0, 90, 0))
    for x in (-10.4, -6.0, -2.0, 2.0, 6.0, 9.5):
        M.flange(b, 2.08 if abs(x) < 7 else 1.8, 0.2, (x, 0, 3.0), (0, 90, 0), "orange_dark", nbolts=12)
    M.cyl(b, 1.4, 0.1, (-11.05, 0, 3.0), "steel_dark", rot=(0, 90, 0), seg=20)
    M.cyl(b, 1.3, 0.1, (11.05, 0, 3.0), "steel_dark", rot=(0, 90, 0), seg=20)
    # Steam inlet pipes over the top and a gauge cluster.
    for x in (-7.0, -3.0):
        M.tube(b, [(x, -2.6, 0.3), (x, -2.6, 3.0), (x, -1.2, 4.6), (x, 0, 4.9)], 0.28, "pipe_green", seg=10, bend=0.6)
        M.flange(b, 0.38, 0.1, (x, -2.6, 1.0), (0, 0, 0), "steel")
    M.gauge(b, 0.3, (0, -2.0, 3.3), "front", angle=40)
    M.gauge(b, 0.22, (0.8, -1.95, 3.1), "front", angle=-60)
    M.danger_sign(b, 0.6, (4.0, -1.71, 1.3), "front")
    # A maintenance step along the front.
    b.box((3.0, 0.6, 0.25), (-1.0, -2.3, 0.0), "steel_light", base=True, bevel=0.02)
    root = b.finish()
    shaft = C.Builder("Shaft")
    M.cyl(shaft, 0.35, 1.0, (11.6, 0, 3.0), "steel_light", rot=(0, 90, 0), seg=12)
    M.flange(shaft, 0.7, 0.18, (12.0, 0, 3.0), (0, 90, 0), "safety_yellow", nbolts=6)
    for k in range(3):  # spokes so the spin reads
        a = 60 * k
        shaft.box((0.06, 1.2, 0.12), (12.1, 0, 3.0), "black", rot=(a, 0, 0))
    shaft.finish(pivot=(11.6, 0, 3.0), parent=root)
    return root


def _tank_horizontal():
    """2 m (x) by 3 m (y), 2.5 m tall: a capsule tank on two saddles."""
    b = C.Builder("TankHorizontal")
    r = 0.95
    zc = 2.5 - r
    M.cyl(b, r, 2.2, (0, 0, zc), "pipe_green", rot=(90, 0, 0), seg=18)
    for sy in (-1, 1):
        b.sphere(r, (0, sy * 1.1, zc), "pipe_green", scale=(1, 0.42, 1), segments=18, rings=8)
        b.box((1.6, 0.3, zc), (0, sy * 0.8, 0), "steel_dark", base=True, bevel=0.03)
    for y in (-0.6, 0.0, 0.6):
        M.cyl(b, r + 0.03, 0.12, (0, y, zc), "steel_dark", rot=(90, 0, 0), seg=18)
    M.striped_band(b, r + 0.01, -0.3, 0.25, (0, 0.35, zc), (90, 0, 0), n=18)
    M.cyl(b, 0.18, 0.3, (0, -0.5, zc + r - 0.05), "steel", seg=10, base=True, bevel=0.02)
    M.gauge(b, 0.15, (0, -1.45, zc + 0.3), "front")
    return b.finish()


def _tank_vertical():
    b = C.Builder("TankVertical")
    M.cyl(b, 1.0, 2.4, (0, 0, 0.2), "teal", seg=18, base=True)
    M.lathe(b, [(1.0, 2.6), (0.8, 2.85), (0.4, 2.98), (0.01, 3.0)], "teal_light", seg=18)
    for z in (0.0, 1.3, 2.5):
        M.cyl(b, 1.04, 0.14, (0, 0, z), "steel_dark", seg=18, base=True)
    M.striped_band(b, 1.01, 0.4, 0.25, n=18)
    M.trefoil(b, 0.5, (0, -1.02, 1.8), "front")
    return b.finish()


def _pipe_2m():
    """Along X from -1 to +1, radius 0.25, origin on the axis."""
    b = C.Builder("Pipe")
    M.cyl(b, 0.25, 2.0, (0, 0, 0), "pipe_green", rot=(0, 90, 0), seg=12)
    for x in (-0.94, 0.94):
        M.flange(b, 0.33, 0.1, (x, 0, 0), (0, 90, 0), "pipe_green_light" if x < 0 else "steel", nbolts=6, seg=12)
    M.striped_band(b, 0.255, -0.06, 0.12, (0.3, 0, 0), (0, 90, 0), n=10, thick=0.012)
    return b.finish()


def _pipe_elbow():
    b = C.Builder("PipeElbow")
    M.tube(b, [(-0.6, 0, 0), (0, 0, 0), (0, 0.6, 0)], 0.25, "pipe_green", seg=12, bend=0.4, steps=6)
    M.flange(b, 0.33, 0.1, (-0.6, 0, 0), (0, 90, 0), "steel")
    M.flange(b, 0.33, 0.1, (0, 0.6, 0), (90, 0, 0), "steel")
    return b.finish()


def _valve_rack():
    """2 (x) by 4 (y) by 2.2 m: a frame of pipes with two hand wheels on each long side."""
    b = C.Builder("ValveRack")
    b.box((2.0, 4.0, 0.15), (0, 0, 0), "steel_dark", base=True, bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((0.12, 0.12, 2.05), (sx * 0.9, sy * 1.9, 0.15), "steel", base=True, bevel=0.02)
        b.box((0.12, 3.9, 0.12), (sx * 0.9, 0, 2.14), "steel", bevel=0.02)
    for z, col in ((0.7, "pipe_green"), (1.35, "blue"), (1.85, "pipe_green_light")):
        for sx in (-0.45, 0.45):
            M.cyl(b, 0.14, 4.0, (sx, 0, z), col, rot=(90, 0, 0), seg=10)
            M.flange(b, 0.2, 0.08, (sx, -1.0, z), (90, 0, 0), "steel", nbolts=4, seg=10)
            M.flange(b, 0.2, 0.08, (sx, 1.0, z), (90, 0, 0), "steel", nbolts=4, seg=10)
    wheels = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            loc = (sx * 0.98, sy * 1.0, 1.3)
            M.cyl(b, 0.2, 0.5, (sx * 0.72, sy * 1.0, 1.3), "steel_dark", rot=(0, 90, 0), seg=10, bevel=0.02)
            wheels.append(loc)
    M.hazard(b, 1.9, 0.1, (0, -2.0, 0.07), "front", depth=0.01, base=False)
    root = b.finish()
    for k, loc in enumerate(wheels):
        M.valve_wheel("Wheel%d" % (k + 1), 0.26, loc, (0, 90, 0), root)
    return root


def _insulator_post():
    b = C.Builder("InsulatorPost")
    b.box((1.0, 1.0, 0.2), (0, 0, 0), "grey", base=True, bevel=0.03)
    b.box((0.25, 0.25, 1.6), (0, 0, 0.2), "steel_dark", base=True, bevel=0.02)
    b.box((0.9, 0.12, 0.12), (0, 0, 1.75), "steel_dark", bevel=0.02)
    for x in (-0.38, 0.0, 0.38):
        for k in range(4):
            M.cyl(b, 0.09 - 0.008 * (k % 2), 0.09, (x, 0, 1.82 + 0.1 * k), "off_white", seg=10, base=True, bevel=0.01)
        M.cyl(b, 0.03, 0.2, (x, 0, 2.22), "steel_light", seg=8, base=True)
    M.danger_sign(b, 0.3, (0, -0.13, 1.1), "front")
    return b.finish()


def _roof_fan():
    b = C.Builder("RoofFan")
    b.box((2.5, 2.5, 0.25), (0, 0, 0), "steel_dark", base=True, bevel=0.04)
    M.hollow(b, 1.1, 1.0, 0.75, (0, 0, 0.25), "steel", seg=20, base=True, inner="grey_dark")
    M.cyl(b, 1.0, 0.05, (0, 0, 0.3), "black", seg=20, base=True)
    for k in range(4):  # grille bars across the top
        a = 45 * k
        b.box((2.1, 0.05, 0.05), (0, 0, 0.97), "grey_dark", rot=(0, 0, a))
    M.hazard(b, 2.4, 0.12, (0, -1.25, 0.12), "front", depth=0.01, base=False)
    root = b.finish()
    M._fan_blades("Fan", 0.9, (0, 0, 0.6), (0, 0, 0), root, n=5, color="steel_light")
    return root


def _exhaust_stack():
    b = C.Builder("ExhaustStack")
    b.box((1.2, 1.2, 0.3), (0, 0, 0), "steel_dark", base=True, bevel=0.03)
    M.cyl(b, 0.42, 2.4, (0, 0, 0.3), "grey_light", seg=14, base=True)
    for z in (0.8, 1.6, 2.4):
        M.cyl(b, 0.46, 0.1, (0, 0, z), "steel_dark", seg=14, base=True)
    M.striped_band(b, 0.43, 2.45, 0.2, n=14, colors=("alarm_red", "white"))
    M.lathe(b, [(0.6, 2.85), (0.3, 3.0), (0.01, 3.02)], "steel", seg=14)
    for k in range(4):
        a = math.radians(90 * k + 45)
        b.box((0.05, 0.05, 0.25), (math.cos(a) * 0.4, math.sin(a) * 0.4, 2.7), "steel_dark", base=True)
    return b.finish()


def _vent_grille():
    """Frame for a 0.7 x 0.6 m wall opening, bottom centre at the origin, nothing in the middle."""
    b = C.Builder("VentGrille")
    t = 0.05
    for sx in (-1, 1):
        b.box((t, 0.1, 0.6 + 2 * t), (sx * (0.35 + t / 2), 0, 0.3), "steel_dark", bevel=0.01)
    b.box((0.7 + 2 * t, 0.1, t), (0, 0, 0.6 + t / 2), "steel_dark", bevel=0.01)
    for x in (-0.3, 0.3):
        b.box((0.02, 0.06, 0.6), (x, -0.02, 0.3), "grey_dark")
    return b.finish()


def _cooling_tower():
    b = C.Builder("CoolingTower")
    prof = []
    for k in range(13):
        z = 22.0 * k / 12
        u = z / 22.0
        r = 3.6 + 2.4 * ((u - 0.7) / 0.7) ** 2 if u < 0.7 else 3.6 + 0.6 * ((u - 0.7) / 0.3) ** 2
        prof.append((r, z))
    M.lathe(b, prof, "beige_light", seg=28)
    M.lathe(b, [(p[0] - 0.3, p[1]) for p in reversed(prof)], "grey_dark", seg=28, inside=False)
    for z0, col in ((18.5, "alarm_red"), (19.5, "white"), (20.5, "alarm_red")):
        u0 = z0 / 22.0
        r0 = 3.6 + 0.6 * ((u0 - 0.7) / 0.3) ** 2
        M.lathe(b, [(r0 + 0.04, z0), (r0 + 0.08, z0 + 1.0)], col, seg=28)
    for k in range(14):  # supporting legs at the base
        a = math.radians(360 * k / 14)
        b.box((0.4, 0.4, 1.6), (math.cos(a) * 5.9, math.sin(a) * 5.9, 0), "beige", base=True)
    return b.finish()


def _ladder():
    b = C.Builder("LadderRails")
    for sx in (-1, 1):
        b.box((0.07, 0.07, 7.0), (sx * 0.42, 0, 0), "safety_yellow", base=True, bevel=0.012)
    z = 0.35
    while z < 6.9:
        M.cyl(b, 0.025, 0.84, (0, 0, z), "yellow_dark", rot=(0, 90, 0), seg=6, smooth=False)
        z += 0.35
    for z in (0.5, 3.5, 6.5):
        for sx in (-1, 1):
            b.box((0.05, 0.18, 0.05), (sx * 0.42, 0.1, z), "steel_dark")
    return b.finish()


def _floodlight():
    b = C.Builder("Floodlight")
    b.box((0.5, 0.5, 0.15), (0, 0, 0), "grey_dark", base=True, bevel=0.02)
    M.cyl(b, 0.07, 5.0, (0, 0, 0.15), "steel", seg=8, base=True)
    b.box((0.9, 0.08, 0.08), (0, 0, 4.9), "steel_dark")
    for sx in (-1, 1):
        b.box((0.36, 0.25, 0.26), (sx * 0.32, -0.08, 4.75), "grey_dark", rot=(-25, 0, 0), bevel=0.03)
        b.box((0.3, 0.02, 0.2), (sx * 0.32, -0.2, 4.69), "off_white", rot=(-25, 0, 0), material=C.MAT_EMISSIVE)
    return b.finish()


BUILDERS = {"reactor_core": _reactor_core, "turbine": _turbine, "tank_horizontal": _tank_horizontal,
            "tank_vertical": _tank_vertical, "pipe_2m": _pipe_2m, "pipe_elbow": _pipe_elbow,
            "valve_rack_4m": _valve_rack, "insulator_post": _insulator_post, "roof_fan": _roof_fan,
            "exhaust_stack": _exhaust_stack, "vent_grille": _vent_grille, "cooling_tower": _cooling_tower,
            "ladder_7m": _ladder, "floodlight": _floodlight}


def build(kind="reactor_core"):
    return BUILDERS[kind]()


if __name__ == "__main__":
    a = C.args("reactor_core", lambda p: p.add_argument("--kind", default="reactor_core", choices=KINDS))
    C.reset()
    C.export(a.out, [build(a.kind)])

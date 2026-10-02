"""Furniture and room props: control-room desks, break-room tables and machines, lockers, shelves,
the donut counter, donuts.

    blender -b -P tools/blender/furniture.py -- --kind lockers_6m [--out PATH]

Each fits the collision box the level gives it (tools/map/gen_plant.py NOMINAL sizes); the front
(where people stand) faces -Y.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import machines as M  # noqa: E402

KINDS = ["control_desk_6m", "cctv_desk_8m", "table_breakroom", "chair", "bench", "lockers_6m", "vending_machine",
         "coffee_station", "donut_counter", "shelf_2m_a", "shelf_2m_b", "pallet_flat", "water_cooler", "whiteboard",
         "desk_office", "donut", "donut_box"]
ASSETS = [(k, {"kind": k}) for k in KINDS]


def donut(b, loc, icing="icing_pink", r=0.1, seed=0, sprinkles=True, low=False):
    """A chunky donut lying flat at `loc` (bottom), outer radius r (`low`: fewer polygons, for rows)."""
    x, y, z = loc
    t = r * 0.38
    seg, sides = (8, 4) if low else (12, 6)
    b.torus(r - t, t, (x, y, z + t), "dough", segments=seg, sides=sides, scale=(1, 1, 0.8))
    b.torus(r - t, t * 0.85, (x, y, z + t * 1.25), icing, segments=seg, sides=sides, scale=(1, 1, 0.55))
    if sprinkles:
        rng = random.Random(seed)
        for k in range(7):
            a = 2 * math.pi * k / 7 + rng.random()
            rr = r - t + rng.uniform(-t * 0.4, t * 0.4)
            b.box((r * 0.18, r * 0.05, r * 0.04), (x + math.cos(a) * rr, y + math.sin(a) * rr, z + t * 1.75),
                  rng.choice(["sprinkle_blue", "sprinkle_yellow", "white", "rat_green"]), rot=(0, 0, rng.uniform(0, 180)))


def _console_top(b, x0, x1, depth, height, screens, seed):
    """A desk 'console' strip: a slanted top with buttons and small screens."""
    rng = random.Random(seed)
    w = x1 - x0
    cx = (x0 + x1) / 2
    F = M.Frame((cx, 0.15, height + 0.12), (-25, 0, 0))
    b.box((w, depth * 0.5, 0.24), (cx, 0.15, height), "grey_dark", base=True, bevel=0.02)
    b.box((w, 0.5, 0.06), F.p(), "steel", rot=F.r(), bevel=0.02)
    for k in range(int(w / 0.12)):
        u = -w / 2 + 0.08 + k * 0.12
        col = rng.choice(["safety_yellow", "alarm_red", "blue", "rat_green", "white"])
        M.cyl(b, 0.025, 0.03, F.p(u, rng.choice([-0.12, -0.05]), 0.03), col, rot=F.r(), seg=8, base=True)
        if rng.random() < 0.4:
            b.box((0.02, 0.02, 0.05), F.p(u, 0.1, 0.03), "black", rot=F.r(rng.uniform(-30, 30), 0, 0))
    for sx in screens:
        G = M.Frame((sx, 0.3, height + 0.2), (-10, 0, 0))
        b.box((0.55, 0.12, 0.4), G.p(0, 0, 0.2), "grey_dark", rot=G.r(), bevel=0.03, base=False)
        b.box((0.45, 0.02, 0.3), G.p(0, -0.065, 0.2), rng.choice(["screen_green", "screen_blue"]), rot=G.r(),
              material=C.MAT_EMISSIVE)


def _control_desk(length=6.0, depth=1.0, panels=(-2.0, 1.0), cctv=False):
    b = C.Builder("ControlDesk")
    h = 0.8
    b.box((length, depth, 0.06), (0, 0, h - 0.06), "beige", base=True, bevel=0.02)
    b.box((length - 0.1, depth - 0.25, h - 0.06), (0, 0.1, 0), "steel", base=True, bevel=0.03)
    b.box((length - 0.14, 0.03, 0.12), (0, -depth / 2 + 0.135, 0.02), "black", base=True)  # kick plate
    for k in range(int(length / 1.0)):
        x = -length / 2 + 0.5 + k
        if cctv or all(abs(x - p) > 0.6 for p in panels):
            b.box((0.7, 0.012, 0.45), (x, -depth / 2 + 0.11, 0.18), "steel_light", base=True, bevel=0.006)
            b.box((0.12, 0.02, 0.025), (x, -depth / 2 + 0.105, 0.55), "grey_dark")
    if cctv:
        rng = random.Random(3)
        for x in (-3.0, -1.0, 1.0, 3.0):  # keyboards
            b.box((0.5, 0.18, 0.03), (x, -0.1, h), "grey_dark", base=True, bevel=0.008)
        b.box((0.09, 0.09, 0.11), (2.0, 0.1, h), "white", base=True, bevel=0.01)  # a mug
        M.cyl(b, 0.04, 0.01, (2.0, 0.1, h + 0.1), "coffee", seg=8, base=True)
        b.box((0.3, 0.22, 0.01), (-2.2, 0.15, h), "off_white", rot=(0, 0, 12), base=True)  # papers
        b.box((0.3, 0.22, 0.01), (-2.1, 0.1, h + 0.01), "white", rot=(0, 0, -6), base=True)
        b.box((0.2, 0.16, 0.08), (0.0, 0.25, h), "alarm_red", base=True, bevel=0.02)  # the phone
        b.box((0.2, 0.05, 0.05), (0.0, 0.25, h + 0.09), "alarm_red", bevel=0.02)
    else:
        # Console strips between the clear panel spots, with screens.
        spans, edge = [], -length / 2 + 0.1
        for p in sorted(panels):
            spans.append((edge, p - 0.5))
            edge = p + 0.5
        spans.append((edge, length / 2 - 0.1))
        for i, (x0, x1) in enumerate(spans):
            if x1 - x0 > 0.4:
                n = max(1, int((x1 - x0) / 1.2))
                _console_top(b, x0, x1, depth, h, [x0 + (x1 - x0) * (k + 0.5) / n for k in range(n)], i)
    return b.finish()


def _table():
    b = C.Builder("Table")
    b.box((3.0, 2.0, 0.08), (0, 0, 0.67), "off_white", base=True, bevel=0.03)
    b.box((2.9, 1.9, 0.03), (0, 0, 0.64), "alarm_red", base=True)
    for sx in (-1, 1):
        for sy in (-1, 1):
            M.cyl(b, 0.05, 0.64, (sx * 1.3, sy * 0.8, 0), "steel_light", seg=8, base=True)
            M.cyl(b, 0.09, 0.02, (sx * 1.3, sy * 0.8, 0), "steel_dark", seg=8, base=True)
    b.box((0.5, 0.5, 0.012), (0.4, 0.2, 0.75), "white", base=True, rot=(0, 0, 20))  # a napkin
    return b.finish()


def _chair():
    b = C.Builder("Chair")
    b.box((0.45, 0.45, 0.06), (0, 0, 0.42), "alarm_red", base=True, bevel=0.02)
    b.box((0.45, 0.06, 0.42), (0, 0.2, 0.5), "alarm_red", base=True, bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            M.cyl(b, 0.02, 0.42, (sx * 0.19, sy * 0.19, 0), "steel_light", seg=6, base=True)
    return b.finish()


def _bench():
    b = C.Builder("Bench")
    for k in range(3):
        b.box((4.0, 0.12, 0.05), (0, -0.13 + k * 0.13, 0.4), "wood", base=True, bevel=0.012)
    for x in (-1.7, 0.0, 1.7):
        b.box((0.08, 0.36, 0.4), (x, 0, 0), "steel_dark", base=True, bevel=0.01)
    return b.finish()


def _lockers():
    b = C.Builder("Lockers")
    n = 12
    w = 6.0 / n
    b.box((6.0, 0.6, 0.1), (0, 0, 0), "steel_dark", base=True)
    b.box((6.0, 0.6, 0.06), (0, 0, 1.94), "teal_dark", base=True, bevel=0.01)
    rng = random.Random(7)
    for k in range(n):
        x = -3.0 + w * (k + 0.5)
        col = "teal_light" if k % 2 == 0 else "teal"
        b.box((w - 0.02, 0.56, 1.84), (x, 0.0, 0.1), col, base=True, bevel=0.012)
        for z in (1.6, 1.68, 1.76, 0.3, 0.38):  # vent slots
            b.box((w * 0.5, 0.012, 0.025), (x, -0.285, z), "teal_dark")
        b.box((0.03, 0.03, 0.16), (x + w * 0.32, -0.29, 1.0), "steel_light", base=True, bevel=0.006)
        b.box((0.12, 0.008, 0.06), (x, -0.284, 1.35), "white")  # name tag
        if rng.random() < 0.3:
            b.box((0.1, 0.01, 0.13), (x - 0.05, -0.286, 1.15), rng.choice(["icing_pink", "sky", "sprinkle_yellow"]),
                  rot=(0, rng.uniform(-10, 10), 0))  # a sticker
    return b.finish()


def _vending():
    b = C.Builder("Vending")
    b.box((1.0, 0.9, 2.0), (0, 0.05, 0), "alarm_red", base=True, bevel=0.04)
    b.box((0.6, 0.02, 1.25), (-0.12, -0.41, 0.55), "glass", base=True, material=C.MAT_GLASS)
    b.box((0.64, 0.02, 1.3), (-0.12, -0.395, 0.53), "black", base=True)
    rng = random.Random(11)
    for row in range(5):
        for col in range(4):
            z = 0.6 + row * 0.24
            x = -0.36 + col * 0.16
            b.box((0.1, 0.1, 0.14), (x, -0.32, z), rng.choice(["sprinkle_yellow", "blue", "rat_green", "orange",
                                                                 "icing_pink", "cheese"]), base=True, bevel=0.01)
        b.box((0.6, 0.3, 0.02), (-0.12, -0.25, 0.58 + row * 0.24), "steel_light", base=True)
    b.box((0.2, 0.03, 0.5), (0.36, -0.41, 0.9), "grey_dark", base=True, bevel=0.01)  # keypad
    for k in range(9):
        b.box((0.04, 0.012, 0.03), (0.31 + (k % 3) * 0.05, -0.43, 1.25 - (k // 3) * 0.06), "silver")
    b.box((0.5, 0.04, 0.16), (-0.12, -0.41, 0.25), "black", base=True, bevel=0.01)  # flap
    b.box((0.9, 0.04, 0.22), (0, -0.41, 1.83), "sprinkle_yellow", base=True, bevel=0.02, material=C.MAT_EMISSIVE)
    return b.finish()


def _coffee():
    b = C.Builder("Coffee")
    b.box((1.75, 1.75, 0.9), (0, 0, 0), "wood", base=True, bevel=0.03)
    b.box((1.8, 1.8, 0.05), (0, 0, 0.9), "beige_light", base=True, bevel=0.015)
    b.box((0.6, 0.5, 0.45), (0.0, 0.3, 0.95), "grey_dark", base=True, bevel=0.04)  # the machine
    b.box((0.6, 0.5, 0.08), (0.0, 0.3, 1.32), "steel", base=True, bevel=0.03)
    b.box((0.3, 0.05, 0.12), (0.0, 0.03, 1.2), "steel_light", bevel=0.01)
    M.cyl(b, 0.12, 0.2, (0.0, -0.05, 0.96), "glass", seg=10, base=True, material=C.MAT_GLASS)  # the pot
    M.cyl(b, 0.11, 0.12, (0.0, -0.05, 0.96), "coffee", seg=10, base=True)
    b.sphere(0.02, (0.22, 0.03, 1.25), "alarm_red", segments=6, rings=3, material=C.MAT_EMISSIVE)
    for k, x in enumerate((-0.6, -0.45, 0.5)):
        b.box((0.08, 0.08, 0.1), (x, -0.4, 0.95), ["white", "safety_yellow", "sky"][k], base=True, bevel=0.01)
    return b.finish()


def _donut_counter():
    """4.0 wide, 1.75 deep, 0.9 tall; glass display at the front (-Y)."""
    b = C.Builder("DonutCounter")
    b.box((4.0, 1.75, 0.8), (0, 0.0, 0), "icing_pink", base=True, bevel=0.03)
    b.box((4.0, 0.06, 0.8), (0, -0.85, 0), "white", base=True)
    for k in range(9):  # vertical stripes, diner style
        b.box((0.18, 0.02, 0.6), (-1.8 + k * 0.45, -0.885, 0.1), "white" if k % 2 else "icing_pink", base=True)
    b.box((4.05, 1.8, 0.06), (0, 0, 0.8), "off_white", base=True, bevel=0.02)
    # The glass display case on top, toward the back, with donut rows.
    b.box((3.6, 0.7, 0.04), (0, 0.4, 0.86), "steel_light", base=True)
    b.box((3.6, 0.02, 0.32), (0, 0.06, 0.86), "glass", base=True, material=C.MAT_GLASS)
    b.box((3.6, 0.7, 0.02), (0, 0.4, 1.18), "glass", base=True, material=C.MAT_GLASS)
    for sx in (-1, 1):
        b.box((0.03, 0.7, 0.34), (sx * 1.8, 0.4, 0.86), "steel_light", base=True)
    icings = ["icing_pink", "coffee", "dough", "sky", "icing_pink", "sprinkle_yellow"]
    for k in range(10):
        for row in range(2):
            donut(b, (-1.5 + k * 0.33, 0.25 + row * 0.3, 0.9), icings[(k + row) % 6], r=0.1, seed=k * 3 + row,
                  sprinkles=False, low=True)
    return b.finish()


def _shelf(seed=0):
    """2.0 (x) by 1.0 (y) by 2.4: metal shelving with stock on four levels."""
    b = C.Builder("Shelf")
    rng = random.Random(seed)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((0.06, 0.06, 2.4), (sx * 0.97, sy * 0.47, 0), "orange", base=True, bevel=0.01)
    for z in (0.1, 0.7, 1.3, 1.9, 2.36):
        b.box((2.0, 1.0, 0.04), (0, 0, z), "steel", base=True)
        b.box((2.0, 0.05, 0.06), (0, -0.48, z - 0.02), "orange_dark", base=True)
    for z in (0.14, 0.74, 1.34, 1.94):
        x = -0.92
        while x < 0.85:
            kind = rng.random()
            if kind < 0.45:
                w, d, h = rng.uniform(0.3, 0.5), rng.uniform(0.4, 0.8), rng.uniform(0.25, 0.45)
                b.box((w, d, h), (x + w / 2, rng.uniform(-0.1, 0.1), z), "cardboard", base=True, bevel=0.01)
                b.box((w + 0.005, 0.05, 0.005), (x + w / 2, 0, z + h), "brown", base=True)
                x += w + 0.04
            elif kind < 0.7:
                for k in range(3):
                    M.cyl(b, 0.06, 0.18, (x + 0.07 + k * 0.13, -0.25, z), rng.choice(["sky", "safety_yellow", "steel_light"]),
                          seg=8, base=True)
                x += 0.42
            elif kind < 0.85 and z < 1.0 and x < 0.4:
                M.cyl(b, 0.25, 0.5, (x + 0.27, 0, z), rng.choice(["blue", "safety_yellow", "alarm_red"]), seg=12,
                      base=True)
                x += 0.58
            else:
                x += 0.25
    return b.finish()


def _pallet():
    b = C.Builder("Pallet")
    for x in (-0.3, 0.0, 0.3):
        b.box((0.12, 2.0, 0.09), (x, 0, 0), "wood", base=True, bevel=0.008)
    for k in range(7):
        b.box((0.75, 0.2, 0.025), (0, -0.9 + k * 0.3, 0.09), "wood_light", base=True, bevel=0.005)
    b.box((0.75, 2.0, 0.02), (0, 0, 0.115), "steel_light", base=True)  # a metal sheet: items stand on it
    return b.finish()


def _water_cooler():
    b = C.Builder("WaterCooler")
    b.box((0.4, 0.4, 0.95), (0, 0, 0), "off_white", base=True, bevel=0.03)
    b.box((0.2, 0.05, 0.08), (0, -0.21, 0.75), "steel_dark", base=True)
    M.cyl(b, 0.15, 0.35, (0, 0, 0.95), "glass", seg=12, base=True, material=C.MAT_GLASS)
    M.cyl(b, 0.14, 0.3, (0, 0, 0.95), "sky", seg=12, base=True)
    return b.finish()


def _whiteboard():
    """Wall mounted: origin at its back face centre."""
    b = C.Builder("Whiteboard")
    b.box((2.0, 0.04, 1.2), (0, -0.02, 0), "silver", bevel=0.01)
    b.box((1.9, 0.01, 1.1), (0, -0.045, 0), "white")
    F = M.Frame((0, -0.05, 0), "front")
    # A cartoon rat with an X over it, and a "reactor" diagram.
    b.sphere(0.12, F.p(-0.55, 0.05, 0), "grey_dark", scale=(1.2, 1, 0.1), rot=F.r(), segments=8, rings=4)
    for sx in (-1, 1):
        b.sphere(0.06, F.p(-0.55 + sx * 0.1, 0.17, 0), "grey_dark", scale=(1, 1, 0.1), rot=F.r(), segments=8, rings=4)
    for a in (40, -40):
        b.box((0.5, 0.03, 0.006), F.p(-0.55, 0.05, 0.005), "alarm_red", rot=F.r(0, 0, a))
    b.box((0.3, 0.02, 0.006), F.p(0.45, 0.25, 0.005), "blue", rot=F.r())
    for k in range(4):
        b.box((0.02, 0.4, 0.006), F.p(0.3 + k * 0.1, -0.05, 0.005), "blue", rot=F.r())
    b.box((0.6, 0.02, 0.006), F.p(0.45, -0.3, 0.005), "rat_green", rot=F.r(0, 0, 10))
    b.box((1.9, 0.05, 0.04), (0, -0.05, -0.6), "grey", bevel=0.005)  # marker tray
    return b.finish()


def _desk_office():
    b = C.Builder("DeskOffice")
    b.box((1.4, 0.7, 0.05), (0, 0, 0.7), "wood_light", base=True, bevel=0.015)
    for sx in (-1, 1):
        b.box((0.05, 0.6, 0.7), (sx * 0.65, 0, 0), "steel", base=True)
    b.box((0.4, 0.6, 0.6), (0.45, 0, 0.05), "steel_light", base=True, bevel=0.015)
    b.box((0.45, 0.42, 0.38), (-0.15, 0.1, 0.75), "beige_light", base=True, bevel=0.04)  # a chunky CRT
    b.box((0.36, 0.02, 0.28), (-0.15, -0.115, 0.8), "screen_green", base=True, material=C.MAT_EMISSIVE)
    b.box((0.45, 0.16, 0.025), (-0.15, -0.22, 0.75), "beige", base=True, bevel=0.006)
    return b.finish()


def _donut():
    b = C.Builder("Donut")
    donut(b, (0, 0, 0), "icing_pink", r=0.1, seed=1)
    return b.finish()


def _donut_box():
    b = C.Builder("DonutBox")
    b.box((0.5, 0.5, 0.08), (0, 0, 0), "white", base=True, bevel=0.01)
    b.box((0.46, 0.46, 0.01), (0, 0, 0.07), "icing_pink", base=True)
    b.box((0.5, 0.02, 0.45), (0, 0.25, 0.08), "white", rot=(-15, 0, 0), base=True, bevel=0.008)  # the lid
    b.box((0.3, 0.025, 0.1), (0, 0.27, 0.32), "icing_pink", rot=(-15, 0, 0), bevel=0.005)
    icings = ["icing_pink", "coffee", "dough", "icing_pink", "sky", "coffee"]
    for k in range(6):
        donut(b, (-0.15 + (k % 3) * 0.15, -0.08 + (k // 3) * 0.16, 0.08), icings[k], r=0.07, seed=k,
              sprinkles=k % 2 == 0, low=k % 2 == 1)
    return b.finish()


BUILDERS = {
    "control_desk_6m": _control_desk, "cctv_desk_8m": lambda: _control_desk(8.0, 0.8, (), cctv=True),
    "table_breakroom": _table, "chair": _chair, "bench": _bench, "lockers_6m": _lockers, "vending_machine": _vending,
    "coffee_station": _coffee, "donut_counter": _donut_counter, "shelf_2m_a": lambda: _shelf(1),
    "shelf_2m_b": lambda: _shelf(2), "pallet_flat": _pallet, "water_cooler": _water_cooler, "whiteboard": _whiteboard,
    "desk_office": _desk_office, "donut": _donut, "donut_box": _donut_box,
}


def build(kind="lockers_6m"):
    return BUILDERS[kind]()


if __name__ == "__main__":
    a = C.args("lockers_6m", lambda p: p.add_argument("--kind", default="lockers_6m", choices=KINDS))
    C.reset()
    C.export(a.out, [build(a.kind)])

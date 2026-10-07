"""Models for the interactables and pickups (they replace the scenes' placeholder meshes).

    blender -b -P tools/blender/interactables.py -- --kind lever [--out PATH]

Wall-mounted ones have their origin at the middle of their BACK face and stick out toward -Y (the
front, Godot +Z). Animated children (Godot code finds them by name):
  sabotage_box "Lamp", repair_panel "Lamp", keycard_reader "Lamp", cctv_head "Lamp"  (tinted / glow)
  lever "Handle"          pivot at the top of the post, pulled about X toward -Y
  cage "Door"             hinge on its left edge, swings about Z
  alarm_beacon "Reflector" spins about Z
  snap_trap "Bar"         pivot on the board's X axis, snaps 180 degrees about X
  console_* "Button"      pushes down along -Z; console_scram "Cover" opens about X on its back edge
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import machines as M  # noqa: E402

KINDS = ["sabotage_box", "sabotage_box_broken", "repair_panel", "lever", "cage", "door_panel", "door_panel_keycard",
         "keycard_reader", "cctv_box", "cctv_conduit", "cctv_head", "cctv_head_broken", "cctv_chair", "alarm_beacon",
         "snap_trap", "cheese_lure", "trap_refill", "cheese_box", "keycard", "console_coolant", "console_scram"]
ASSETS = [(k, {"kind": k}) for k in KINDS]


def _sabotage_box(broken=False):
    b = C.Builder("SabotageBox")
    w, d, h = 0.36, 0.14, 0.3
    b.box((w, d - 0.02, h), (0, -d / 2 + 0.01, 0), "grey_dark", bevel=0.015)
    M.hazard(b, w - 0.02, 0.05, (0, -d + 0.005, h / 2 - 0.04), "front", depth=0.006, stripe=0.04)
    if broken:  # the cover hangs open, wires chewed
        b.box((w - 0.04, 0.015, h - 0.08), (0, -d - 0.12, -0.06), "steel", rot=(70, 0, 0), bevel=0.005)
        b.box((w - 0.08, 0.01, h - 0.12), (0, -d + 0.008, -0.03), "black")
        for x, col in ((-0.08, "alarm_red"), (0.0, "blue"), (0.08, "safety_yellow")):
            M.tube(b, [(x, -d + 0.03, 0.0), (x + 0.03, -d - 0.05, -0.05), (x - 0.02, -d - 0.08, -0.12)], 0.012, col,
                   seg=6, caps=True)
            b.box((0.006, 0.006, 0.04), (x - 0.02, -d - 0.08, -0.14), "orange", rot=(0, 25, 0))
        return b.finish()
    b.box((w - 0.04, 0.012, h - 0.09), (0, -d, -0.025), "steel", bevel=0.004)
    M.danger_sign(b, 0.09, (0.1, -d - 0.004, -0.05), "front", depth=0.005)
    for x, col in ((-0.07, "alarm_red"), (0.07, "blue")):  # wires looping out of the bottom
        M.tube(b, [(x, -0.06, -h / 2 + 0.01), (x, -0.08, -h / 2 - 0.07), (x * 0.4, -0.06, -h / 2 - 0.12),
                   (x * 0.2, -0.02, -h / 2 - 0.05)], 0.013, col, seg=6, bend=0.03)
    root = b.finish()
    lamp = C.Builder("Lamp")
    lamp.sphere(0.025, (-0.11, -d - 0.006, 0.07), "rat_green", scale=(1, 0.6, 1), segments=8, rings=4,
                material=C.MAT_EMISSIVE)
    lamp.finish(pivot=(-0.11, -d, 0.07), parent=root)
    return root


def _repair_panel():
    b = C.Builder("RepairPanel")
    w, d, h = 0.6, 0.08, 0.4
    b.box((w, d, h), (0, -d / 2, 0), "safety_yellow", bevel=0.02)
    b.box((w - 0.1, 0.012, h - 0.1), (0, -d - 0.004, 0), "steel_dark", bevel=0.004)
    # Wrench and bolt icon.
    F = M.Frame((-0.05, -d - 0.012, 0), "front")
    b.box((0.24, 0.035, 0.012), F.p(0, 0, 0.006), "safety_yellow", rot=F.r(0, 0, 35))
    M.cyl(b, 0.045, 0.012, F.p(-0.1, -0.07, 0), "safety_yellow", rot=F.r(), seg=6, base=True, smooth=False)
    M.cyl(b, 0.045, 0.012, F.p(0.1, 0.07, 0), "safety_yellow", rot=F.r(), seg=8, base=True)
    M.cyl(b, 0.02, 0.016, F.p(0.1, 0.07, 0), "steel_dark", rot=F.r(), seg=8, base=True)
    M.bolts_grid(b, M.corners(w, h, 0.035), (0, -d, 0), "front", r=0.014, h=0.008)
    root = b.finish()
    lamp = C.Builder("Lamp")
    M.cyl(lamp, 0.035, 0.03, (0.2, -d - 0.004, 0.08), "off_white", rot=M.FACE["front"], seg=10, base=True,
          material=C.MAT_EMISSIVE)
    lamp.finish(pivot=(0.2, -d, 0.08), parent=root)
    return root


def _lever():
    b = C.Builder("Lever")
    b.box((0.9, 0.9, 0.02), (0, 0, 0), "black", base=True)
    M.hazard(b, 0.86, 0.86, (0, 0, 0.02), "top", depth=0.004, stripe=0.09, base=False)
    b.box((0.3, 0.3, 0.9), (0, 0.2, 0.02), "steel", base=True, bevel=0.03)
    b.box((0.34, 0.34, 0.06), (0, 0.2, 0.02), "steel_dark", base=True, bevel=0.015)
    b.box((0.12, 0.04, 0.45), (0, 0.04, 0.42), "black", base=True)  # the slot the handle moves in
    M.lamp(b, 0.03, (0, 0.04, 0.85), "front", "rat_green")
    root = b.finish()
    h = C.Builder("Handle")
    pivot = (0, 0.02, 0.7)
    M.cyl(h, 0.05, 0.12, pivot, "steel_dark", rot=(0, 90, 0), seg=10, bevel=0.01)
    h.box((0.05, 0.05, 0.5), (0, 0.0, 0.7), "steel_light", base=True, bevel=0.01)
    h.sphere(0.07, (0, 0.0, 1.22), "alarm_red", segments=10, rings=6)
    h.finish(pivot=pivot, parent=root)
    return root


def _cage():
    b = C.Builder("Cage")
    W, H = 1.5, 1.3
    b.box((W + 0.06, W + 0.06, 0.08), (0, 0, 0), "steel_dark", base=True, bevel=0.02)
    b.box((W - 0.1, W - 0.1, 0.02), (0, 0, 0.08), "beige_dark", base=True)  # the tray
    b.box((W + 0.06, W + 0.06, 0.06), (0, 0, H - 0.06), "steel_dark", base=True, bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((0.06, 0.06, H), (sx * W / 2, sy * W / 2, 0), "steel", base=True, bevel=0.012)
    n = 9
    for k in range(1, n):
        u = -W / 2 + W * k / n
        for sx in (-1, 1):  # sides
            M.cyl(b, 0.012, H - 0.12, (sx * W / 2, u, 0.08), "steel_light", seg=5, base=True, smooth=False)
        M.cyl(b, 0.012, H - 0.12, (u, W / 2, 0.08), "steel_light", seg=5, base=True, smooth=False)  # back
        b.box((0.025, W, 0.02), (u, 0, H - 0.04), "steel_light")  # roof bars
    for sx in (-1, 1):
        for z in (0.45, 0.85):
            b.box((0.03, W, 0.03), (sx * W / 2, 0, z), "steel")
    b.box((W, 0.03, 0.03), (0, W / 2, 0.65), "steel")
    root = b.finish()
    door = C.Builder("Door")
    hinge = (-W / 2 + 0.03, -W / 2, 0)
    for k in range(1, n):
        u = -W / 2 + W * k / n
        M.cyl(door, 0.012, H - 0.16, (u, -W / 2, 0.1), "steel_light", seg=5, base=True, smooth=False)
    for z in (0.1, 0.65, H - 0.1):
        door.box((W - 0.08, 0.035, 0.035), (0, -W / 2, z), "steel")
    door.box((0.12, 0.05, 0.14), (W / 2 - 0.15, -W / 2 - 0.04, 0.62), "safety_yellow", bevel=0.01)  # padlock
    door.torus(0.04, 0.012, (W / 2 - 0.15, -W / 2 - 0.04, 0.71), "steel_light", rot=(90, 0, 0), segments=8, sides=4)
    door.finish(pivot=hinge, parent=root)
    return root


def _door_panel(keycard=False):
    b = C.Builder("DoorPanel")
    W, H, T = 2.0, 2.6, 0.2
    body, trim = ("blue_dark", "blue") if keycard else ("teal", "teal_light")
    b.box((W, T, H), (0, 0, 0), body, bevel=0.03)
    for sy in (-1, 1):
        y = sy * T / 2
        F = "front" if sy < 0 else "back"
        b.box((W - 0.2, 0.012, H - 0.3), (0, y + sy * 0.004, 0.05), trim, bevel=0.01)
        M.hazard(b, W - 0.04, 0.22, (0, y, -H / 2 + 0.13), F, depth=0.012, stripe=0.14)
        M.cyl(b, 0.2, 0.02, (0, y, 0.55), "steel_dark", rot=M.FACE[F], seg=14, base=True, bevel=0.006)
        M.cyl(b, 0.16, 0.012, (0, y + sy * 0.02, 0.55), "glass", rot=M.FACE[F], seg=14, base=True,
              material=C.MAT_GLASS)
        b.box((0.08, 0.02, 0.5), (0.8, y + sy * 0.012, -0.05), "steel_dark", bevel=0.008)  # handle recess
        if keycard:
            b.box((W - 0.04, 0.012, 0.14), (0, y + sy * 0.006, 0.05), "safety_yellow")
            b.box((0.24, 0.016, 0.16), (-0.55, y + sy * 0.012, -0.25), "safety_yellow", bevel=0.01)
            b.box((0.16, 0.02, 0.025), (-0.55, y + sy * 0.016, -0.22), "black")
    return b.finish()


def _keycard_reader():
    b = C.Builder("KeycardReader")
    b.box((0.2, 0.06, 0.25), (0, -0.03, 0), "grey_dark", bevel=0.012)
    b.box((0.12, 0.012, 0.012), (0, -0.064, -0.06), "black")
    b.box((0.14, 0.008, 0.06), (0, -0.062, 0.02), "screen_blue", material=C.MAT_EMISSIVE)
    root = b.finish()
    lamp = C.Builder("Lamp")
    lamp.sphere(0.018, (0, -0.062, 0.09), "off_white", scale=(1, 0.6, 1), segments=8, rings=4, material=C.MAT_EMISSIVE)
    lamp.finish(pivot=(0, -0.06, 0.09), parent=root)
    return root


def _cctv_box():
    b = C.Builder("CctvBox")
    b.box((0.4, 0.15, 0.5), (0, -0.075, 0), "steel", bevel=0.02)
    b.box((0.34, 0.012, 0.42), (0, -0.152, 0), "grey_light", bevel=0.006)
    M.danger_sign(b, 0.12, (0, -0.158, 0.1), "front", depth=0.005)
    M.louvre(b, 0.2, 0.1, (0, -0.158, -0.12), "front", n=3, depth=0.015)
    M.cyl(b, 0.035, 0.1, (0, -0.06, 0.25), "steel_dark", seg=8, base=True)
    return b.finish()


def _cctv_conduit():
    """1 m of conduit along +Z (code stretches it up to the camera head)."""
    b = C.Builder("Conduit")
    M.cyl(b, 0.025, 1.0, (0, 0, 0), "steel_dark", seg=8, base=True)
    return b.finish()


def _cctv_head(broken=False):
    b = C.Builder("CctvHead")
    b.box((0.16, 0.04, 0.2), (0, -0.02, 0), "steel_dark", bevel=0.01)  # wall plate
    b.box((0.05, 0.22, 0.05), (0, -0.13, 0.0), "steel", bevel=0.01)  # arm
    if broken:
        b.box((0.22, 0.4, 0.18), (0.05, -0.38, -0.2), "off_white", rot=(-55, 20, 10), bevel=0.03)
        M.cyl(b, 0.07, 0.06, (0.08, -0.45, -0.38), "black", rot=(-145, 20, 10), seg=10)
        M.tube(b, [(0, -0.22, 0.0), (0.02, -0.28, -0.1), (0.05, -0.3, -0.12)], 0.01, "alarm_red", seg=5)
        return b.finish()
    b.box((0.22, 0.4, 0.18), (0, -0.4, 0.04), "off_white", bevel=0.03)
    b.box((0.26, 0.42, 0.03), (0, -0.4, 0.14), "grey", bevel=0.01)  # sun hood
    M.cyl(b, 0.075, 0.06, (0, -0.62, 0.04), "black", rot=M.FACE["front"], seg=12, base=True, bevel=0.01)
    M.cyl(b, 0.05, 0.01, (0, -0.68, 0.04), "glass", rot=M.FACE["front"], seg=12, base=True, material=C.MAT_GLASS)
    root = b.finish()
    lamp = C.Builder("Lamp")
    lamp.sphere(0.016, (0.08, -0.6, 0.1), "alarm_red", segments=8, rings=4, material=C.MAT_EMISSIVE)
    lamp.finish(pivot=(0.08, -0.6, 0.1), parent=root)
    return root


def _cctv_chair():
    b = C.Builder("CctvChair")
    for k in range(5):  # star base on casters
        a = math.radians(72 * k)
        b.box((0.32, 0.05, 0.04), (math.cos(a) * 0.16, math.sin(a) * 0.16, 0.06), "black", rot=(0, 0, 72 * k))
        b.sphere(0.035, (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.035), "grey_dark", segments=8, rings=4)
    M.cyl(b, 0.035, 0.36, (0, 0, 0.08), "steel_light", seg=8, base=True)
    b.box((0.55, 0.52, 0.1), (0, 0, 0.42), "safety_yellow", base=True, bevel=0.04)
    b.box((0.5, 0.1, 0.55), (0, 0.24, 0.6), "safety_yellow", base=True, bevel=0.04)
    b.box((0.06, 0.06, 0.22), (0, 0.27, 0.48), "black", base=True)
    for sx in (-1, 1):
        b.box((0.05, 0.32, 0.04), (sx * 0.3, 0.0, 0.66), "black", bevel=0.01)
        b.box((0.03, 0.03, 0.14), (sx * 0.3, 0.0, 0.52), "black", base=True)
    return b.finish()


def _alarm_beacon():
    """Ceiling mounted: origin at the top centre, hangs down to about z = -0.35."""
    b = C.Builder("AlarmBeacon")
    M.cyl(b, 0.16, 0.05, (0, 0, -0.05), "steel_dark", seg=12, base=True, bevel=0.01)
    M.cyl(b, 0.14, 0.08, (0, 0, -0.13), "grey_dark", seg=12, base=True)
    b.sphere(0.13, (0, 0, -0.16), "alarm_red", scale=(1, 1, 1.25), segments=12, rings=6)
    root = b.finish()
    r = C.Builder("Reflector")
    r.box((0.04, 0.16, 0.16), (0, 0.0, -0.25), "alarm_red", bevel=0.01, material=C.MAT_EMISSIVE)
    r.box((0.2, 0.02, 0.16), (0, 0.06, -0.25), "silver")
    r.finish(pivot=(0, 0, -0.25), parent=root)
    return root


def _snap_trap():
    b = C.Builder("SnapTrap")
    b.box((0.4, 0.25, 0.04), (0, 0, 0), "wood_light", base=True, bevel=0.008)
    b.box((0.38, 0.23, 0.004), (0, 0, 0.04), "wood", base=True)
    M.cyl(b, 0.025, 0.16, (0, 0.0, 0.065), "silver", rot=(0, 90, 0), seg=8)  # spring
    b.box((0.08, 0.06, 0.008), (0, -0.07, 0.044), "silver", base=True)  # bait plate
    b.box((0.06, 0.05, 0.035), (0, -0.07, 0.052), "cheese", base=True, bevel=0.006)
    root = b.finish()
    bar = C.Builder("Bar")
    bar.box((0.32, 0.012, 0.012), (0, 0.11, 0.05), "silver")
    for sx in (-1, 1):
        bar.box((0.012, 0.11, 0.012), (sx * 0.155, 0.055, 0.05), "silver")
    bar.finish(pivot=(0, 0.0, 0.05), parent=root)
    return root


def _cheese_lure():
    b = C.Builder("Cheese")
    tri = [(-0.15, -0.09), (0.15, -0.09), (-0.15, 0.11)]
    b.prism(tri, 0.18, (0, 0, 0), "cheese", rot=(0, 0, 0), bevel=0.012)
    for x, y, z, r in ((-0.06, -0.09, 0.08, 0.03), (0.04, -0.09, 0.12, 0.02), (-0.15, 0.02, 0.06, 0.025)):
        b.sphere(r, (x, y, z), "yellow_dark", scale=(1, 0.4, 1), segments=8, rings=4)
    return b.finish()


def _trap_refill():
    b = C.Builder("TrapRefill")
    b.box((0.5, 0.4, 0.3), (0, 0, 0), "cardboard", base=True, bevel=0.015)
    b.box((0.52, 0.06, 0.02), (0, 0, 0.3), "brown", base=True)  # tape
    for F, y in (("front", -0.2), ("back", 0.2)):
        b.box((0.2, 0.004, 0.1), (0, y, 0.15), "black", rot=(0, 0, 0))
        b.box((0.16, 0.006, 0.02), (0, y * 1.01, 0.18), "off_white")
    return b.finish()


def _cheese_box():
    """Storage: cheese lures to refill. An open crate of cheese wedges, so it doesn't look like the
    taped box of snap traps next to it."""
    b = C.Builder("CheeseBox")
    w, d, h, t = 0.5, 0.36, 0.16, 0.02
    b.box((w, d, t), (0, 0, 0), "cardboard", base=True)  # floor
    for y in (-d / 2 + t / 2, d / 2 - t / 2):
        b.box((w, t, h), (0, y, 0), "cardboard", base=True, bevel=0.004)
    for x in (-w / 2 + t / 2, w / 2 - t / 2):
        b.box((t, d - 2 * t, h), (x, 0, 0), "cardboard", base=True, bevel=0.004)
    # Wedges heaped inside, their tops above the rim.
    tri = [(-0.08, -0.05), (0.08, -0.05), (-0.08, 0.06)]
    for x, y, z, rx, rz in ((-0.12, -0.07, 0.07, 8, 15), (0.09, -0.06, 0.08, -10, 160), (-0.1, 0.07, 0.08, 12, -70),
                            (0.12, 0.08, 0.06, -6, 110), (0.0, 0.0, 0.11, 14, 40)):
        b.prism(tri, 0.09, (x, y, z), "cheese", rot=(rx, 0, rz), bevel=0.008)
    for x, y, z in ((-0.15, -0.08, 0.165), (0.07, -0.05, 0.175), (0.0, 0.02, 0.205), (-0.12, 0.09, 0.175)):
        b.sphere(0.012, (x, y, z), "yellow_dark", scale=(1, 1, 0.4), segments=8, rings=4)
    # A label on the front: a yellow wedge on a dark card.
    b.box((0.2, 0.004, 0.09), (0, -d / 2 - 0.002, 0.035), "black", base=True)
    b.prism([(-0.06, 0.0), (0.06, 0.0), (-0.06, 0.06)], 0.004, (0.0, -d / 2 - 0.004, 0.05), "cheese", rot=(90, 0, 0))
    return b.finish()


def _keycard():
    b = C.Builder("Keycard")
    b.box((0.12, 0.08, 0.008), (0, 0, 0), "safety_yellow", base=True, bevel=0.002)
    b.box((0.12, 0.02, 0.009), (0, -0.02, 0), "blue", base=True)
    b.box((0.03, 0.025, 0.010), (0.035, 0.015, 0), "silver", base=True)
    b.torus(0.05, 0.004, (-0.1, 0, 0.004), "alarm_red", segments=12, sides=4, scale=(1.4, 0.6, 1))
    return b.finish()


def _console(scram=False):
    """A slanted desk panel 0.9 x 0.6, 0.12 thick, front edge low (toward -Y)."""
    b = C.Builder("Console")
    b.box((0.9, 0.6, 0.12), (0, 0, 0), "grey_dark", rot=(-12, 0, 0), bevel=0.02)
    F = M.Frame((0, 0, 0.065), (-12, 0, 0))
    b.box((0.8, 0.5, 0.01), F.p(), "steel_dark", rot=F.r())
    if scram:
        M.hazard(b, 0.42, 0.42, F.p(0, 0.02, 0.0), F.r(), depth=0.006, stripe=0.06)
        b.box((0.3, 0.06, 0.012), F.p(0, -0.22, 0.004), "alarm_red", rot=F.r())
    else:
        b.box((0.3, 0.06, 0.012), F.p(0, -0.22, 0.004), "blue", rot=F.r())
        for k in range(3):  # a snowflake-ish star
            b.box((0.2, 0.025, 0.006), F.p(0.26, 0.12, 0.006), "sky", rot=F.r(0, 0, 60 * k))
    root = b.finish()
    btn = C.Builder("Button")
    big = 0.13 if scram else 0.09
    M.cyl(btn, big * 1.25, 0.03, F.p(0, 0.02, 0.006), "steel", rot=F.r(), seg=14, base=True)
    M.cyl(btn, big, 0.06, F.p(0, 0.02, 0.03), "alarm_red" if scram else "blue", rot=F.r(), seg=14, base=True,
          bevel=0.015)
    btn.finish(pivot=F.p(0, 0.02, 0.006), parent=root)
    if scram:
        cover = C.Builder("Cover")
        G = F.sub((0, 0.2, 0.1), (0, 0, 0))
        cover.box((0.38, 0.38, 0.012), G.p(0, -0.18, 0), "glass", rot=G.r(), material=C.MAT_GLASS)
        cover.box((0.4, 0.03, 0.03), G.p(0, 0.0, 0), "alarm_red", rot=G.r())
        cover.finish(pivot=G.p(0, 0, 0), parent=root)
    return root


BUILDERS = {
    "sabotage_box": _sabotage_box, "sabotage_box_broken": lambda: _sabotage_box(True), "repair_panel": _repair_panel,
    "lever": _lever, "cage": _cage, "door_panel": _door_panel, "door_panel_keycard": lambda: _door_panel(True),
    "keycard_reader": _keycard_reader, "cctv_box": _cctv_box, "cctv_conduit": _cctv_conduit, "cctv_head": _cctv_head,
    "cctv_head_broken": lambda: _cctv_head(True), "cctv_chair": _cctv_chair, "alarm_beacon": _alarm_beacon,
    "snap_trap": _snap_trap, "cheese_lure": _cheese_lure, "trap_refill": _trap_refill, "cheese_box": _cheese_box,
    "keycard": _keycard,
    "console_coolant": _console, "console_scram": lambda: _console(True),
}


def build(kind="lever"):
    return BUILDERS[kind]()


if __name__ == "__main__":
    a = C.args("lever", lambda p: p.add_argument("--kind", default="lever", choices=KINDS))
    C.reset()
    C.export(a.out, [build(a.kind)])

#!/usr/bin/env python3
"""Generates the graybox "Sunny Acres" plant (M5) from the layout data in this file.

Writes:
  levels/plant/Plant.tscn              root: environment, POI instances, out-of-bounds volumes
  levels/plant/pois/*.tscn             one scene per POI (geometry, props, lights, interactables)
  levels/plant/materials/*.tres        colour-coded prototype materials
  docs/map/plant_layout_v1.png         the top-down plan (2 m grid), also used by tools/heatmap.py
  docs/map/plant_layout_v1.json        how to map world metres onto that image

Usage:  python3 tools/map/gen_plant.py [--force] [--png-only]

This file is the source of truth for the layout while it is still a graybox: change a number here,
run the script, and the level and the plan image move together. It refuses to overwrite the scenes
unless you pass --force, because hand edits made in the Godot editor would be lost. Once you start
editing rooms in the editor instead, stop using it (or keep --png-only for the plan).

Conventions: 1 unit = 1 m, +X = east, +Z = south (north is up on the plan), the ground floor is
y = 0. A room is the rectangle between wall centre lines; walls are 0.5 m thick and centred on
those lines, so neighbouring rooms share one wall (owned by the taller room, or the first one in
ROOMS). Doors are 2.0 x 2.6 m (the M4 Door scenes), vents 0.7 x 0.6 m (supervisors are 1.8 m tall).
"""
import json
import math
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LEVEL_DIR = os.path.join(ROOT, "levels", "plant")
POI_DIR = os.path.join(LEVEL_DIR, "pois")
MAT_DIR = os.path.join(LEVEL_DIR, "materials")
DOC_DIR = os.path.join(ROOT, "docs", "map")

WALL_T = 0.5
DOOR_W, DOOR_H = 2.0, 2.6
VENT_W, VENT_H = 0.7, 0.6       # wall openings and duct insides
DUCT_SHELL = 0.15               # duct outer = inner + 2 * shell
EXIT_H = 0.75                   # the shaft's exit onto the roof (a climbing rat needs a little more room)
CEIL_T = 0.3
ROOF_Y = 6.0                    # the vent roof deck
CATWALK_W = 1.5

# --- Layout -----------------------------------------------------------------------------------
# id, POI scene, display name, x0, z0, x1, z1, height, colour
ROOMS = [
    ("CR", "ControlRoom", "Control Room", -14, 0, 10, 20, 4, (0.95, 0.85, 0.5)),
    ("BR", "BreakRoom", "Break Room", -38, 6, -14, 20, 4, (0.92, 0.66, 0.72)),
    ("LR", "LockerRoom", "Locker Room", 10, 6, 34, 20, 4, (0.6, 0.76, 0.82)),
    ("PH", "PumpHouse", "Pump House", -52, -20, -38, -6, 4, (0.45, 0.76, 0.74)),
    ("VC", "ValveCorridor", "Valve Corridor", -52, -6, -38, 26, 4, (0.52, 0.62, 0.88)),
    ("ST", "Storage", "Storage", 34, -20, 52, -6, 4, (0.78, 0.64, 0.48)),
    ("CG", "CageRoom", "Cage Room", 34, -6, 52, 20, 4, (0.72, 0.62, 0.82)),
    ("MHW", "Corridors", "Main Hall West", -38, 0, -14, 6, 4, (0.82, 0.8, 0.72)),
    ("MHE", "Corridors", "Main Hall East", 10, 0, 34, 6, 4, (0.82, 0.8, 0.72)),
    ("CS", "Corridors", "South Corridor", -38, 20, 52, 26, 4, (0.82, 0.8, 0.72)),
    ("RH", "ReactorHall", "Reactor Hall", -38, -20, -10, 0, 10, (0.56, 0.8, 0.5)),
    ("TH", "TurbineHall", "Turbine Hall", -10, -20, 34, 0, 8, (0.92, 0.72, 0.46)),
    ("NEST", "RatNest", "Rat Nest", -36, 30, -24, 40, 3, (0.48, 0.52, 0.36)),
    ("YARD", "Yard", "Yard", -52, -38, 24, -20, 3, (0.6, 0.6, 0.64)),
]
OUTDOOR = {"YARD"}
SKIP_SIDES = {"YARD": {"E"}}  # the vent roof block is the yard's east side
BLOCK = (23.75, -38.25, 52.25, -19.75)  # the solid vent-roof block (outer faces), top at ROOF_Y

# Openings in room walls: (axis, line, centre, kind, width, sill, height). axis "z" = a wall along X
# at z = line (centre is an x), axis "x" = a wall along Z at x = line (centre is a z).
# kinds: door / keycard (a Door scene in the opening), arch, window, vent.
def door(axis, line, c): return (axis, line, c, "door", DOOR_W, 0.0, DOOR_H)
def keycard(axis, line, c): return (axis, line, c, "keycard", DOOR_W, 0.0, DOOR_H)
def arch(axis, line, c, w=3.0, h=3.0): return (axis, line, c, "arch", w, 0.0, h)
def window(axis, line, c, w): return (axis, line, c, "window", w, 1.0, 1.6)
def vent(axis, line, c, sill=0.0, h=VENT_H): return (axis, line, c, "vent", VENT_W, sill, h)

OPENINGS = [
    door("z", -20, -24), door("z", -20, 16),                 # Reactor / Turbine Hall -> yard
    arch("x", -38, -13), arch("z", -6, -45),                  # Pump House -> Reactor Hall, Valve Corridor
    arch("x", -10, -10),                                      # Reactor Hall <-> Turbine Hall
    arch("z", 0, -26, 4.0), arch("z", 0, 22, 4.0),            # halls -> main halls
    arch("x", -38, 3, 4.0), keycard("x", -38, 13), arch("x", -38, 23, 4.0),  # Valve Corridor east side
    door("x", -14, 3), door("x", 10, 3),                      # Control Room west / east doors
    arch("z", 6, -20), arch("z", 20, -26),                    # Break Room north / south
    arch("x", 34, -8), arch("z", -6, 43),                     # Storage -> Turbine Hall, Cage Room
    arch("x", 34, 3, 4.0), arch("z", 6, 22), keycard("z", 20, 22), arch("x", 34, 13), arch("z", 20, 43, 4.0),
    window("z", 0, -12, 3.0), window("z", 0, -4, 4.0), window("z", 0, 4, 4.0),  # Control Room windows
    # Vent holes (see VENTS below)
    vent("x", -52, -30), vent("x", -52, -19.25), vent("x", -52, -12), vent("x", -52, 2), vent("x", -52, 20),
    vent("x", -38, -19.25),
    vent("x", 52, -19.25), vent("x", 52, -12), vent("x", 52, -2), vent("x", 52, 14),
    vent("x", 34, -19.25),
    vent("z", 26, -30), vent("z", 26, 6), vent("z", 26, 40), vent("z", 30, -30),
    vent("z", 26, -2, 2.8), vent("z", 20, -2, 2.8),
]

# Free-standing walls that aren't a room side: (scene, axis, line, start, end, base_y, height, openings)
EXTRA_WALLS = [
    ("Substation", "x", -30, -38, -24, 0.0, 3.0, [("gate", -31, 3.0, 0.0, 2.6)]),
    ("Substation", "z", -24, -52, -30, 0.0, 3.0, [("gate", -41, 3.0, 0.0, 2.6)]),
    ("VentRoof", "z", -38, 24, 52, ROOF_Y, 2.5, []),
    ("VentRoof", "x", 52, -38, -20, ROOF_Y, 2.5, [("vent", -30.5, VENT_W, 0.0, EXIT_H)]),
    ("VentRoof", "z", -20, 34, 52, ROOF_Y, 2.5, []),
]

# Ducts (all in VentNetwork.tscn): horizontal runs along X or Z between two (x, z) points at floor
# height y. Ends: "closed", "open" (inner pokes out: an opening), "flush" (inner ends there, outer
# stops `flush_outer` earlier, for a duct passing through a wall into a room), "corner"/"joint"
# (overlap the next piece).
DUCTS = [
    # name, (x0, z0), (x1, z1), y, end0, end1
    ("SouthLine", (-52.75, 26.75), (52.75, 26.75), 0.0, "corner", "corner"),
    ("WestLine", (-52.75, 26.75), (-52.75, -30.5), 0.0, "corner", "closed"),
    ("EastLine", (52.75, 26.75), (52.75, -30.5), 0.0, "corner", "corner"),
    ("NestExit", (-30, 30.25), (-30, 25.75), 0.0, "flush", "flush"),
    ("PumpBranch", (-52.75, -19.25), (-33.0, -19.25), 0.0, "corner", "open"),
    ("StorageBranch", (52.75, -19.25), (19.0, -19.25), 0.0, "corner", "open"),
    ("RiserFoot", (8.35, 27.75), (7.0, 27.75), 0.0, "closed", "joint"),
    ("RiserTop", (1.4, 27.75), (-2.0, 27.75), 2.8, "joint", "corner"),
    ("ControlDrop", (-2.0, 27.75), (-2.0, 19.75), 2.8, "corner", "drop"),
]
DUCT_FLUSH_OUTER = {"NestExit": (29.75, 26.25)}  # outer box z range (between the two walls)
RAMPS = [("RiserRamp", (7.0, 0.0), (1.4, 2.8), 27.75)]  # along X: (x, y) floor line, at z
SHAFT = (52.75, -30.5)  # climbable shaft from the east line up to the roof, exit to the west
# Side openings from a duct into the wall hole next to it: (axis, line_through_duct_side, centre)
DUCT_GRILLES = [
    ("x", -52.4, -30), ("x", -52.4, -12), ("x", -52.4, 2), ("x", -52.4, 20),
    ("x", 52.4, -12), ("x", 52.4, -2), ("x", 52.4, 14),
    ("z", 26.4, 6), ("z", 26.4, 40),
    ("z", 27.25, 8.0),  # the riser's foot joins the south line here
]

# Plant stations (subsystem, POI scene, node name, x, y, z, yaw_deg, critical)
STATIONS = [
    ("rods", "ReactorHall", "ControlRods", -24, 0, -4, 0, True),
    ("pumps", "PumpHouse", "CoolantPumps", -45, 0, -12, 0, False),
    ("valves", "ValveCorridor", "CoolantValves", -45, 0, 0, 180, False),
    ("turbine", "TurbineHall", "Turbine", 10, 0, -15, 180, True),
    ("grid", "Substation", "PowerGrid", -41, 0, -30, 0, False),
    ("ventilation", "VentRoof", "Ventilation", 38, ROOF_Y, -29, -90, False),
]

# CCTV cameras: number, POI scene, label, junction box (x, y, z), facing yaw (deg, +Z into the room),
# lens height above the box, pitch down (deg), yaw offset (deg)
CAMERAS = [
    (1, "ReactorHall", "Reactor Hall", (-10.6, 0.4, -16.0), -90, 6.0, 30, 20),
    (2, "TurbineHall", "Turbine Hall", (33.6, 0.4, -11.0), -90, 6.0, 20, -10),
    (3, "PumpHouse", "Pump House", (-40.0, 0.4, -6.6), 180, 3.0, 30, 40),
    (4, "ValveCorridor", "Valve Corridor", (-41.0, 0.4, -5.4), 0, 3.0, 18, -30),
    (5, "Substation", "Substation", (-33.0, 0.4, -37.4), 0, 2.4, 25, -45),
    (6, "VentRoof", "Vent Roof", (40.0, ROOF_Y + 0.4, -37.4), 0, 2.0, 20, 0),
    (7, "CageRoom", "Cage Room", (48.0, 0.4, -5.4), 0, 3.0, 28, -25),
    (8, "Corridors", "Main Hall West", (-32.0, 0.4, 5.4), 180, 3.0, 20, -35),
]

LADDER_YARD = (23.75, -29.0)  # on the block's west face, climbing east


# --- Small helpers ------------------------------------------------------------------------------

def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        s = ("%.4f" % v).rstrip("0").rstrip(".")
        return "0" if s in ("-0", "", "-") else s
    if isinstance(v, str):
        return '"%s"' % v.replace('"', '\\"')
    if isinstance(v, Raw):
        return v.text
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(fmt(x) for x in v) + "]"
    raise TypeError(v)


class Raw:
    def __init__(self, text): self.text = text


def V3(x, y, z): return Raw("Vector3(%s, %s, %s)" % (fmt(x), fmt(y), fmt(z)))
def V2(x, y): return Raw("Vector2(%s, %s)" % (fmt(x), fmt(y)))
def Col(r, g, b, a=1.0): return Raw("Color(%s, %s, %s, %s)" % (fmt(r), fmt(g), fmt(b), fmt(a)))
def SN(s): return Raw('&"%s"' % s)
def NP(s): return Raw('NodePath("%s")' % s)
def AABBs(boxes):
    return Raw("Array[AABB]([%s])" % ", ".join(
        "AABB(%s)" % ", ".join(fmt(v) for v in b) for b in boxes))
def Ints(values): return Raw("Array[int]([%s])" % ", ".join(str(v) for v in values))
def deg(d): return math.radians(d)


class Scene:
    """A tiny .tscn writer: ext/sub resources and nodes, written in Godot's text format."""

    def __init__(self, root_name, root_type="Node3D", script=None, props=None):
        self.ext = []  # (type, path, id)
        self.subs = []  # (type, id, props)
        self.nodes = []
        self.children = {}  # parent path -> set of names
        root_props = dict(props or {})
        if script:
            root_props = {"script": self.ext_res("Script", script), **root_props}
        self.nodes.append((root_name, root_type, None, None, root_props, None))

    def ext_res(self, type_, path):
        for t, p, i in self.ext:
            if p == path:
                return Raw('ExtResource("%s")' % i)
        i = "%d_%s" % (len(self.ext) + 1, os.path.splitext(os.path.basename(path))[0].lower()[:12])
        self.ext.append((type_, path, i))
        return Raw('ExtResource("%s")' % i)

    def sub_res(self, type_, props):
        i = "%s_%d" % (type_, len(self.subs) + 1)
        self.subs.append((type_, i, props))
        return Raw('SubResource("%s")' % i)

    def node(self, name, type_=None, parent=".", props=None, script=None, instance=None, groups=None):
        names = self.children.setdefault(parent, set())
        base, n = name, 2
        while name in names:
            name = "%s%d" % (base, n)
            n += 1
        names.add(name)
        props = dict(props or {})
        if script:
            props = {"script": self.ext_res("Script", script), **props}
        inst = self.ext_res("PackedScene", instance) if instance else None
        self.nodes.append((name, None if instance else type_, parent, inst, props, groups))
        return name if parent == "." else "%s/%s" % (parent, name)

    def write(self, path):
        out = ["[gd_scene load_steps=%d format=3]" % (len(self.ext) + len(self.subs) + 1), ""]
        for t, p, i in self.ext:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, i))
        if self.ext:
            out.append("")
        for t, i, props in self.subs:
            out.append('[sub_resource type="%s" id="%s"]' % (t, i))
            out.extend("%s = %s" % (k, fmt(v)) for k, v in props.items())
            out.append("")
        for name, type_, parent, inst, props, groups in self.nodes:
            head = '[node name="%s"' % name
            if type_:
                head += ' type="%s"' % type_
            if parent is not None:
                head += ' parent="%s"' % parent
            if inst:
                head += " instance=%s" % inst.text
            if groups:
                head += " groups=[%s]" % ", ".join('"%s"' % g for g in groups)
            out.append(head + "]")
            out.extend("%s = %s" % (k, fmt(v)) for k, v in props.items())
            out.append("")
        with open(path, "w") as f:
            f.write("\n".join(out))


# --- Materials ----------------------------------------------------------------------------------

TEX = "res://assets/third_party/kenney_prototype/%s.png"
MATERIALS = {}  # name -> (texture or None, colour, extra lines)


def material(name, texture, color, extra=None):
    MATERIALS[name] = (texture, color, extra or {})
    return "res://levels/plant/materials/%s.tres" % name


def write_materials():
    os.makedirs(MAT_DIR, exist_ok=True)
    for name, (texture, color, extra) in MATERIALS.items():
        lines = []
        if texture:
            lines += ['[gd_resource type="StandardMaterial3D" load_steps=2 format=3]', "",
                      '[ext_resource type="Texture2D" path="%s" id="1_tex"]' % (TEX % texture), "",
                      "[resource]", "albedo_texture = ExtResource(\"1_tex\")",
                      "uv1_scale = Vector3(0.5, 0.5, 0.5)", "uv1_triplanar = true",
                      "uv1_world_triplanar = true"]
        else:
            lines += ['[gd_resource type="StandardMaterial3D" format=3]', "", "[resource]"]
        lines.append("albedo_color = %s" % Col(*color).text)
        lines += ["%s = %s" % (k, fmt(v)) for k, v in extra.items()]
        with open(os.path.join(MAT_DIR, name + ".tres"), "w") as f:
            f.write("\n".join(lines) + "\n")


def tint(c, k):
    return tuple(min(1.0, v * k) for v in c[:3])


ROOM_BY_ID = {r[0]: r for r in ROOMS}
SCENE_COLOR = {}
for r in ROOMS:
    SCENE_COLOR.setdefault(r[1], r[8])
SCENE_COLOR.update({"Substation": (0.62, 0.66, 0.56), "VentRoof": (0.55, 0.6, 0.7), "VentNetwork": (0.6, 0.45, 0.8)})


def wall_mat(scene):
    return material("wall_" + scene.lower(), "light_01", SCENE_COLOR[scene])


def floor_mat(scene):
    return material("floor_" + scene.lower(), "dark_01", tint(SCENE_COLOR[scene], 1.0))


M_PROP = material("prop_crate", "orange_01", (1, 1, 1))
M_MACHINE = material("prop_machine", "purple_01", (1, 1, 1))
M_PIPE = material("prop_pipe", "green_01", (0.85, 0.95, 0.85))
M_METAL = material("prop_metal", "light_01", (0.55, 0.58, 0.62))
M_DUCT = material("duct", "purple_01", (0.9, 0.85, 1.0))
M_GLASS = material("glass", None, (0.6, 0.85, 1.0, 0.18), {"transparency": 1, "cull_mode": 2, "metallic": 0.4, "roughness": 0.1})
M_GLOW = material("reactor_glow", None, (0.6, 1.0, 0.18), {"emission_enabled": True, "emission": Col(0.61, 1.0, 0.18), "emission_energy_multiplier": 2.5})
M_WATER = material("sewer_water", None, (0.3, 0.42, 0.18, 0.85), {"transparency": 1, "emission_enabled": True, "emission": Col(0.25, 0.4, 0.1), "emission_energy_multiplier": 0.6})
M_LADDER = material("ladder", None, (1.0, 0.79, 0.24))
M_TOWER = material("cooling_tower", "light_01", (0.75, 0.75, 0.72))


# --- Wall runs ----------------------------------------------------------------------------------

def room_sides(r):
    rid, scene, _, x0, z0, x1, z1, h, _ = r
    sides = {"N": ("z", z0, x0, x1), "S": ("z", z1, x0, x1), "W": ("x", x0, z0, z1), "E": ("x", x1, z0, z1)}
    return {k: v for k, v in sides.items() if k not in SKIP_SIDES.get(rid, set())}


def wall_runs():
    """[(axis, line, a, b, height, owner_room)] with shared walls emitted once."""
    lines = {}
    for idx, r in enumerate(ROOMS):
        for side, (axis, line, a, b) in room_sides(r).items():
            lines.setdefault((axis, line), []).append((a, b, idx))
    runs = []
    for (axis, line), segs in lines.items():
        cuts = sorted({v for a, b, _ in segs for v in (a, b)})
        pieces = []
        for a, b in zip(cuts, cuts[1:]):
            covering = [i for s, e, i in segs if s <= a and e >= b]
            if not covering:
                continue
            owner = max(covering, key=lambda i: (ROOMS[i][7], -i))
            pieces.append([a, b, owner])
        merged = []
        for p in pieces:
            if merged and merged[-1][2] == p[2] and abs(merged[-1][1] - p[0]) < 1e-6:
                merged[-1][1] = p[1]
            else:
                merged.append(p)
        for a, b, owner in merged:
            runs.append((axis, line, a, b, ROOMS[owner][7], ROOMS[owner]))
    return runs


def cut_run(a, b, height, openings, extend_ends=True):
    """Splits a wall run around openings: [(a, b, y0, y1)] solid pieces (along-axis range, heights)."""
    pieces = []
    cursor = a
    for c, w, sill, oh in sorted(openings):
        l, r = c - w / 2, c + w / 2
        if l > cursor + 1e-6:
            pieces.append((cursor, l, 0.0, height))
        if sill > 1e-6:
            pieces.append((l, r, 0.0, sill))
        if sill + oh < height - 1e-6:
            pieces.append((l, r, sill + oh, height))
        cursor = r
    if cursor < b - 1e-6:
        pieces.append((cursor, b, 0.0, height))
    if extend_ends and pieces:
        out = []
        for (pa, pb, y0, y1) in pieces:
            if abs(pa - a) < 1e-6:
                pa -= WALL_T / 2
            if abs(pb - b) < 1e-6:
                pb += WALL_T / 2
            out.append((pa, pb, y0, y1))
        pieces = out
    return pieces


def floor_at(x, z):
    """True if a room floor (or the vent roof block) is under (x, z)."""
    for r in ROOMS:
        if r[3] < x < r[5] and r[4] < z < r[6]:
            return True
    return BLOCK[0] < x < BLOCK[2] and BLOCK[1] < z < BLOCK[3]


def openings_on(axis, line, a, b):
    return [o for o in OPENINGS if o[0] == axis and abs(o[1] - line) < 1e-6 and a - 1e-6 <= o[2] <= b + 1e-6]


# --- POI scene building ---------------------------------------------------------------------------

class Poi:
    """One POI scene under construction: a root Poi node, a CSG shell, and children."""

    def __init__(self, scene_name, display_name, bounds, area_names=None):
        self.name = scene_name
        props = {"display_name": display_name, "bounds": AABBs(bounds)}
        if area_names:
            props["area_names"] = Raw("PackedStringArray(%s)" % ", ".join(fmt(n) for n in area_names))
        self.s = Scene(scene_name, "Node3D", "res://levels/poi.gd", props)
        self.shell = self.s.node("Shell", "CSGCombiner3D", props={"use_collision": True})
        self.occluders = None
        self.lights = None
        self.wall_mat = self.s.ext_res("Material", wall_mat(scene_name))
        self.floor_mat = self.s.ext_res("Material", floor_mat(scene_name))

    def mat(self, path):
        return self.s.ext_res("Material", path)

    def box(self, name, x0, y0, z0, x1, y1, z1, mat=None, parent=None, collide_alone=False):
        """An axis-aligned box from min to max corner. In the shell unless `parent` is given."""
        props = {"position": V3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
                 "size": V3(x1 - x0, y1 - y0, z1 - z0),
                 "material": mat if mat is not None else self.wall_mat}
        if collide_alone:
            props["use_collision"] = True
        return self.s.node(name, "CSGBox3D", parent or self.shell, props)

    def rotated_box(self, name, center, size, rot, mat, parent=None, collide_alone=False):
        props = {"position": V3(*center), "rotation": V3(*rot), "size": V3(*size), "material": mat}
        if collide_alone:
            props["use_collision"] = True
        return self.s.node(name, "CSGBox3D", parent or self.shell, props)

    def occluder(self, x0, y0, z0, x1, y1, z1):
        if self.occluders is None:
            self.occluders = self.s.node("Occluders", "Node3D")
        shape = self.s.sub_res("BoxOccluder3D", {"size": V3(x1 - x0, y1 - y0, z1 - z0)})
        self.s.node("Occluder", "OccluderInstance3D", self.occluders,
                    {"position": V3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), "occluder": shape})

    def light(self, x, y, z, rng=10.0, energy=1.0, color=(1.0, 0.93, 0.82)):
        if self.lights is None:
            self.lights = self.s.node("Lights", "Node3D")
        self.s.node("Light", "OmniLight3D", self.lights,
                    {"position": V3(x, y, z), "light_color": Col(*color), "light_energy": energy,
                     "omni_range": rng, "omni_attenuation": 0.8})

    def label(self, text, x, y, z, size=96):
        self.s.node("Sign", "Label3D", ".", {"position": V3(x, y, z), "billboard": 1, "text": text,
                                             "font_size": size, "outline_size": 18})


POIS = {}


def poi(scene):
    return POIS[scene]


def build_rooms():
    # Floors, ceilings, room lights.
    for rid, scene, name, x0, z0, x1, z1, h, color in ROOMS:
        p = POIS[scene]
        p.box("Floor" + rid, x0, -0.5, z0, x1, 0.0, z1, p.floor_mat)
        if rid not in OUTDOOR:
            p.box("Ceiling" + rid, x0, h, z0, x1, h + CEIL_T, z1)
        # Lights on a grid, about one per 10 m.
        if rid == "YARD":
            continue
        nx, nz = max(1, round((x1 - x0) / 10)), max(1, round((z1 - z0) / 10))
        rng = max(8.0, min(14.0, h * 2.2))
        for i in range(nx):
            for j in range(nz):
                lx = x0 + (i + 0.5) * (x1 - x0) / nx
                lz = z0 + (j + 0.5) * (z1 - z0) / nz
                p.light(lx, h - 0.6, lz, rng, 1.1 if h > 4 else 0.9)
    # Walls with their openings.
    for axis, line, a, b, h, owner in wall_runs():
        p = POIS[owner[1]]
        ops = openings_on(axis, line, a, b)
        for pa, pb, y0, y1 in cut_run(a, b, h, [(o[2], o[4], o[5], o[6]) for o in ops]):
            if axis == "z":
                p.box("Wall", pa, y0, line - WALL_T / 2, pb, y1, line + WALL_T / 2)
                if pb - pa >= 3 and y0 == 0 and y1 >= 3:
                    p.occluder(pa, 0, line - 0.12, pb, y1, line + 0.12)
            else:
                p.box("Wall", line - WALL_T / 2, y0, pa, line + WALL_T / 2, y1, pb)
                if pb - pa >= 3 and y0 == 0 and y1 >= 3:
                    p.occluder(line - 0.12, 0, pa, line + 0.12, y1, pb)
        for o in ops:
            _, _, c, kind, w, sill, oh = o
            x, z = (c, line) if axis == "z" else (line, c)
            yaw = 0.0 if axis == "z" else deg(90)
            if kind == "vent" and sill < 0.01:
                # Room floors stop at the wall's centre line: give the hole a floor on a side without a room.
                for side in (-1, 1):
                    probe = line + side * 0.15
                    px, pz = (c, probe) if axis == "z" else (probe, c)
                    if not floor_at(px, pz):
                        lo, hi = sorted((line, line + side * WALL_T / 2))
                        if axis == "z":
                            p.box("VentSill", c - w / 2, -0.5, lo, c + w / 2, 0.0, hi, p.floor_mat)
                        else:
                            p.box("VentSill", lo, -0.5, c - w / 2, hi, 0.0, c + w / 2, p.floor_mat)
            if kind in ("door", "keycard"):
                scn = "res://interactables/door/%s.tscn" % ("Door" if kind == "door" else "KeycardDoor")
                p.s.node("KeycardDoor" if kind == "keycard" else "Door", None, ".",
                         {"position": V3(x, 0, z), "rotation": V3(0, yaw, 0)}, instance=scn)
            elif kind == "window":
                size = (w, oh, 0.06) if axis == "z" else (0.06, oh, w)
                p.s.node("Window", "CSGBox3D", ".", {"position": V3(x, sill + oh / 2, z), "size": V3(*size),
                                                     "material": p.mat(M_GLASS), "use_collision": True})
    for scene, axis, line, a, b, base, h, ops in EXTRA_WALLS:
        p = POIS[scene]
        for pa, pb, y0, y1 in cut_run(a, b, h, [(c, w, s, oh) for _, c, w, s, oh in ops]):
            if axis == "z":
                p.box("Fence", pa, base + y0, line - WALL_T / 2, pb, base + y1, line + WALL_T / 2)
            else:
                p.box("Fence", line - WALL_T / 2, base + y0, pa, line + WALL_T / 2, base + y1, pb)


# --- Interactables and markers -------------------------------------------------------------------

SCN_SABOTAGE = "res://interactables/sabotage_point/SabotagePoint.tscn"
SCN_REPAIR = "res://interactables/repair_point/RepairPoint.tscn"
SCN_LEVER = "res://interactables/critical_lever/CriticalLever.tscn"
SCN_CAGE = "res://interactables/cage/Cage.tscn"
SCN_CAMERA = "res://interactables/cctv/CctvCamera.tscn"
SCN_CONSOLE = "res://interactables/cctv/CctvConsole.tscn"
SCN_BEACON = "res://levels/plant/props/AlarmBeacon.tscn"


def build_stations():
    for sid, scene, node, x, y, z, yaw, critical in STATIONS:
        p = POIS[scene]
        s = p.s
        st = s.node(node, "Node3D", ".", {"position": V3(x, y, z), "rotation": V3(0, deg(yaw), 0)})
        s.node("Machine", "CSGBox3D", st, {"position": V3(0, 0.8, 0), "size": V3(2, 1.6, 2),
                                           "material": p.mat(M_MACHINE), "use_collision": True})
        s.node("Label", "Label3D", st, {"position": V3(0, 2.3, 0), "billboard": 1, "font_size": 56,
                                        "outline_size": 12, "text": sid,
                                        "script": s.ext_res("Script", "res://levels/station_label.gd"),
                                        "subsystem_id": SN(sid)})
        s.node("RepairPoint", None, st, {"position": V3(0, 1, 1.3), "subsystem_id": SN(sid)}, instance=SCN_REPAIR)
        if critical:
            s.node("LeverA", None, st, {"position": V3(-3, 0.3, 0.4), "subsystem_id": SN(sid),
                                        "partner_path": NP("../LeverB")}, instance=SCN_LEVER)
            s.node("LeverB", None, st, {"position": V3(3, 0.3, 0.4), "subsystem_id": SN(sid)}, instance=SCN_LEVER)
        else:
            s.node("SabotageA", None, st, {"position": V3(-1.3, 0.3, 0), "rotation": V3(0, deg(-90), 0),
                                           "subsystem_id": SN(sid)}, instance=SCN_SABOTAGE)
            s.node("SabotageB", None, st, {"position": V3(1.3, 0.3, 0), "rotation": V3(0, deg(90), 0),
                                           "subsystem_id": SN(sid)}, instance=SCN_SABOTAGE)


def build_cameras():
    for number, scene, label, (x, y, z), yaw, lens_h, pitch, yaw_off in CAMERAS:
        p = POIS[scene]
        p.s.node("Camera%d" % number, None, ".", {
            "position": V3(x, y, z), "rotation": V3(0, deg(yaw), 0), "number": number, "label": label,
            "lens_height": lens_h, "lens_pitch_deg": float(pitch), "lens_yaw_deg": float(yaw_off)},
            instance=SCN_CAMERA)


def spawn(p, name, role, x, y, z, yaw):
    p.s.node(name, "Marker3D", ".", {"position": V3(x, y, z), "rotation": V3(0, deg(yaw), 0),
                                     "script": p.s.ext_res("Script", "res://levels/spawn_point.gd"),
                                     "role": role})


def pickup(p, name, item, x, y, z, yaw):
    p.s.node(name, "Area3D", ".", {"position": V3(x, y, z), "rotation": V3(0, deg(yaw), 0),
                                   "script": p.s.ext_res("Script", "res://interactables/pickup/pickup.gd"),
                                   "item": item})


def beacon(p, x, y, z):
    p.s.node("AlarmBeacon", None, ".", {"position": V3(x, y, z)}, instance=SCN_BEACON)


def _ramp(p, name, along, low, high, y_low, y_high, w0, w1, mat):
    """A walkable slab whose top runs from (low, y_low) to (high, y_high) along X or Z (graybox stairs)."""
    d, dy = high - low, y_high - y_low
    length = math.hypot(d, dy)
    ux, uy = d / length, dy / length
    if ux < 0:  # keep the slab's local +Y pointing up
        ux, uy = -ux, -uy
    t = 0.25
    if along == "x":  # rotation about Z maps local +X to (cos a, sin a)
        a = math.atan2(uy, ux)
        nx, ny = -math.sin(a), math.cos(a)
        c = ((low + high) / 2 - nx * t / 2, (y_low + y_high) / 2 - ny * t / 2, (w0 + w1) / 2)
        p.rotated_box(name, c, (length + 0.1, t, w1 - w0), (0, 0, a), mat)
    else:  # rotation about X maps local +Z to (y = -sin a, z = cos a)
        a = math.atan2(-uy, ux)
        nz, ny = math.sin(a), math.cos(a)
        c = ((w0 + w1) / 2, (y_low + y_high) / 2 - ny * t / 2, (low + high) / 2 - nz * t / 2)
        p.rotated_box(name, c, (w1 - w0, t, length + 0.1), (a, 0, 0), mat)


def ramp_x(p, name, x_low, x_high, y_low, y_high, z0, z1, mat):
    _ramp(p, name, "x", x_low, x_high, y_low, y_high, z0, z1, mat)


def ramp_z(p, name, z_low, z_high, y_low, y_high, x0, x1, mat):
    _ramp(p, name, "z", z_low, z_high, y_low, y_high, x0, x1, mat)


def build_props():
    # --- Reactor Hall: pool + core, L-shaped catwalk (north and west walls) at 4 m, stairs along the south wall.
    p = poi("ReactorHall")
    p.box("PoolRim", -27.5, 0, -14.5, -20.5, 1.2, -7.5, p.mat(M_METAL))
    p.box("PoolWater", -27.2, 1.2, -14.2, -20.8, 1.25, -7.8, p.mat(M_GLOW))
    p.s.node("Core", "CSGCylinder3D", p.shell, {"position": V3(-24, 4.7, -11), "radius": 1.8, "height": 7.0,
                                                "sides": 16, "material": p.mat(M_GLOW)})
    p.box("CatwalkNorth", -37.75, 3.8, -19.75, -10.25, 4.0, -19.75 + CATWALK_W, p.mat(M_METAL))
    p.box("CatwalkWest", -37.75, 3.8, -19.75, -37.75 + CATWALK_W, 4.0, -0.25, p.mat(M_METAL))
    ramp_x(p, "Stairs", -29.4, -36.25, 0.0, 4.0, -1.75, -0.25, p.mat(M_METAL))
    p.box("Crate", -14.5, 0, -18.5, -13.0, 1.2, -17.0, p.mat(M_PROP))
    p.box("Crate", -12.5, 0, -18.5, -11.0, 2.4, -17.0, p.mat(M_PROP))
    p.box("Tank", -36.5, 0, -10.0, -34.5, 2.5, -7.0, p.mat(M_PIPE))
    p.light(-24, 3.0, -11, 9.0, 1.6, (0.6, 1.0, 0.3))
    beacon(p, -24, 9.6, -2)
    p.label("REACTOR HALL", -24, 8.2, -11, 140)

    # --- Turbine Hall: turbine body, north catwalk at 3.5 m with stairs at both ends, crates up for rats.
    p = poi("TurbineHall")
    p.box("TurbineBody", -2, 0, -12, 22, 3.0, -8, p.mat(M_MACHINE))
    p.s.node("TurbineDrum", "CSGCylinder3D", p.shell, {"position": V3(10, 3.0, -10), "rotation": V3(0, 0, deg(90)),
                                                       "radius": 2.0, "height": 22.0, "sides": 16, "material": p.mat(M_METAL)})
    p.box("Catwalk", -9.75, 3.3, -19.75, 33.75, 3.5, -19.75 + CATWALK_W, p.mat(M_METAL))
    ramp_z(p, "StairsWest", -12.0, -18.25, 0.0, 3.5, -9.75, -8.25, p.mat(M_METAL))
    ramp_z(p, "StairsEast", -12.0, -18.25, 0.0, 3.5, 32.25, 33.75, p.mat(M_METAL))
    p.box("Crate", 3.0, 0, -16.0, 4.5, 1.2, -14.5, p.mat(M_PROP))
    p.box("Crate", 3.0, 0, -18.0, 4.5, 2.4, -16.5, p.mat(M_PROP))
    p.box("Generator", 25.0, 0, -14.0, 28.0, 2.0, -11.0, p.mat(M_PIPE))
    p.box("Crate", -6.0, 0, -6.0, -4.5, 1.2, -4.5, p.mat(M_PROP))
    beacon(p, 10, 7.6, -1)
    p.label("TURBINE HALL", 10, 6.6, -15, 140)

    # --- Pump House: pumps, a high pipe run rats can reach from a crate.
    p = poi("PumpHouse")
    p.box("Pump", -51.0, 0, -16.5, -48.5, 1.6, -14.0, p.mat(M_PIPE))
    p.box("Pump", -51.0, 0, -11.0, -48.5, 1.6, -8.5, p.mat(M_PIPE))
    p.box("PipeHigh", -40.5, 1.9, -18.0, -39.9, 2.5, -7.5, p.mat(M_PIPE))
    p.box("PipeHigh", -51.0, 1.9, -7.4, -40.5, 2.5, -6.8, p.mat(M_PIPE))
    p.box("Crate", -41.6, 0, -9.5, -40.4, 1.0, -8.3, p.mat(M_PROP))
    beacon(p, -45, 3.7, -7)
    p.label("PUMP HOUSE", -45, 3.2, -14, 90)

    # --- Valve Corridor: a central valve rack splitting it into two lanes.
    p = poi("ValveCorridor")
    p.box("ValveRack", -46.0, 0, 4.0, -44.0, 2.2, 16.0, p.mat(M_PIPE))
    for vz in (6.0, 10.0, 14.0):
        for vx, rot in ((-46.15, 90), (-43.85, 90)):
            p.s.node("ValveWheel", "CSGCylinder3D", ".", {"position": V3(vx, 1.3, vz), "rotation": V3(0, 0, deg(rot)),
                                                         "radius": 0.35, "height": 0.08, "material": p.mat(M_PROP)})
    p.box("PipeHigh", -51.6, 2.6, -5.5, -51.0, 3.2, 25.5, p.mat(M_PIPE))
    p.box("Crate", -40.5, 0, 17.5, -39.0, 1.0, 19.0, p.mat(M_PROP))
    beacon(p, -45, 3.7, 20)
    p.label("VALVE CORRIDOR", -45, 3.2, 10, 90)

    # --- Storage: shelves (crates next to them let rats hop up), trap refill, spare keycard.
    p = poi("Storage")
    for sz in (-16.0, -11.0):
        p.box("Shelf", 39.0, 0, sz - 0.5, 45.0, 2.4, sz + 0.5, p.mat(M_METAL))
        p.box("Shelf", 46.5, 0, sz - 0.5, 50.5, 2.4, sz + 0.5, p.mat(M_METAL))
        p.box("Crate", 45.2, 0, sz - 0.6, 46.3, 1.2, sz + 0.6, p.mat(M_PROP))
    pickup(p, "TrapRefill", "trap_refill", 35.0, 0.2, -16.5, 90)
    pickup(p, "SpareKeycard", "spare_keycard", 35.0, 0.45, -13.5, 90)
    p.box("PickupTable", 34.25, 0, -18.0, 35.0, 0.25, -12.0, p.mat(M_PROP))
    p.label("STORAGE", 43, 3.2, -8.5, 90)

    # --- Cage Room: two cages, crates for cover.
    p = poi("CageRoom")
    p.s.node("CageA", None, ".", {"position": V3(38.0, 0.5, 2.0), "rotation": V3(0, deg(90), 0)}, instance=SCN_CAGE)
    p.s.node("CageB", None, ".", {"position": V3(48.0, 0.5, 10.0), "rotation": V3(0, deg(-90), 0)}, instance=SCN_CAGE)
    p.box("Crate", 43.0, 0, 5.0, 44.5, 1.2, 6.5, p.mat(M_PROP))
    p.box("Crate", 40.0, 0, 15.0, 42.0, 1.0, 16.5, p.mat(M_PROP))
    p.box("Crate", 47.0, 0, -2.0, 48.5, 1.2, -0.5, p.mat(M_PROP))
    beacon(p, 43, 3.7, 7)
    p.label("CAGE ROOM", 43, 3.2, 6, 90)

    # --- Control Room: desks (M6 consoles), CCTV chair facing the wall screens, the status board.
    p = poi("ControlRoom")
    p.box("Desk", -9.0, 0, 5.5, -3.0, 0.8, 6.5, p.mat(M_METAL))
    p.box("Desk", 1.0, 0, 5.5, 7.0, 0.8, 6.5, p.mat(M_METAL))
    p.box("CctvDesk", -5.0, 0, 16.8, 3.0, 0.8, 17.6, p.mat(M_METAL))
    p.s.node("CctvConsole", None, ".", {"position": V3(-1.0, 0, 15.6), "rotation": V3(0, deg(180), 0)},
             instance=SCN_CONSOLE)
    for i, (sx, cams) in enumerate(((-5.0, [1, 2, 3, 4]), (3.0, [5, 6, 7, 8]))):
        p.s.node("CctvScreen%d" % (i + 1), "Node3D", ".", {
            "position": V3(sx, 2.0, 19.7), "rotation": V3(0, deg(180), 0),
            "script": p.s.ext_res("Script", "res://levels/plant/props/cctv_screen.gd"),
            "cameras": Ints(cams), "size": V2(2.6, 1.46)})
    p.s.node("StatusBoard", "Node3D", ".", {
        "position": V3(-13.7, 2.1, 12.0), "rotation": V3(0, deg(90), 0),
        "script": p.s.ext_res("Script", "res://levels/plant/props/status_board.gd"), "size": V2(4.8, 2.7)})
    p.s.node("ConsolesM6", "Marker3D", ".", {"position": V3(-2, 0, 6.5)})  # emergency coolant / SCRAM go here (M6)
    beacon(p, -2, 3.7, 1.0)
    beacon(p, -2, 3.7, 18.5)
    p.label("CONTROL ROOM", -2, 3.3, 10, 90)

    # --- Break Room: supervisor spawn, donut counter, tables, coffee and vending machines.
    p = poi("BreakRoom")
    p.box("DonutCounter", -16.0, 0, 12.0, -14.25, 0.9, 16.0, p.mat(M_PROP))
    pickup(p, "Donuts", "donut", -15.2, 1.0, 14.0, -90)
    p.box("Table", -32.0, 0, 9.0, -29.0, 0.75, 11.0, p.mat(M_METAL))
    p.box("Table", -32.0, 0, 15.0, -29.0, 0.75, 17.0, p.mat(M_METAL))
    p.box("Vending", -37.75, 0, 7.0, -36.75, 2.0, 8.5, p.mat(M_MACHINE))
    p.box("Coffee", -16.0, 0, 18.0, -14.25, 1.4, 19.75, p.mat(M_MACHINE))
    spawn(p, "Supervisor1", 1, -24.0, 0, 12.0, 0)
    spawn(p, "Supervisor2", 1, -28.0, 0, 12.0, 0)
    p.label("BREAK ROOM", -26, 3.2, 13, 90)

    # --- Locker Room: rows of lockers to hide between; a clear lane between the two doors.
    p = poi("LockerRoom")
    for lx0, lx1 in ((13.0, 19.0), (25.0, 31.0)):
        for lz in (10.0, 16.0):
            p.box("Lockers", lx0, 0, lz - 0.3, lx1, 2.0, lz + 0.3, p.mat(M_METAL))
            p.box("Bench", lx0 + 1, 0, lz + 1.2, lx1 - 1, 0.45, lz + 1.6, p.mat(M_PROP))
    p.label("LOCKER ROOM", 22, 3.2, 13, 90)

    # --- Corridors: a few obstacles, nothing in the door lanes.
    p = poi("Corridors")
    p.box("Crate", -36.5, 0, 24.0, -35.0, 1.0, 25.5, p.mat(M_PROP))
    p.box("Crate", 30.0, 0, 21.0, 31.2, 1.2, 22.2, p.mat(M_PROP))
    p.box("PipeHigh", -37.5, 3.0, 24.9, 51.5, 3.5, 25.4, p.mat(M_PIPE))
    beacon(p, -26, 3.7, 3)
    beacon(p, 22, 3.7, 3)
    beacon(p, 7, 3.7, 23)

    # --- Rat Nest: sealed sewer room (the only way out is the vent in the north wall).
    p = poi("RatNest")
    p.box("Sludge", -35.75, 0.0, 35.0, -24.25, 0.05, 39.75, p.mat(M_WATER))
    p.box("Junk", -35.5, 0, 31.0, -34.0, 0.8, 33.0, p.mat(M_PROP))
    p.box("Junk", -26.0, 0, 37.0, -24.5, 1.2, 39.0, p.mat(M_PROP))
    for i, (x, z) in enumerate(((-32, 34), (-28, 34), (-32, 37), (-28, 37))):
        spawn(p, "Rat%d" % (i + 1), 2, x, 0, z, 0)
    p.light(-30, 2.4, 35, 9.0, 1.2, (0.5, 1.0, 0.4))
    p.label("RAT NEST", -30, 2.4, 36, 72)

    # --- Yard: cooling tower (landmark), floodlights, crates, lobby spawns.
    p = poi("Yard")
    p.s.node("CoolingTower", "CSGCylinder3D", p.shell, {"position": V3(-2, 11, -32), "radius": 6.0, "height": 22.0,
                                                       "sides": 24, "material": p.mat(M_TOWER)})
    p.box("Crate", -20.0, 0, -36.5, -18.5, 1.2, -35.0, p.mat(M_PROP))
    p.box("Crate", 8.0, 0, -37.0, 10.0, 1.0, -35.5, p.mat(M_PROP))
    p.box("Barrels", -24.0, 0, -31.0, -22.5, 1.0, -29.5, p.mat(M_PIPE))
    for x, z in ((-40, -22), (-14, -24), (10, -24), (16, -34)):
        p.light(x, 5.0, z, 18.0, 1.4, (0.75, 0.85, 1.0))
    for i, (x, z) in enumerate(((18, -22), (18, -25), (18, -28), (14, -22), (14, -25), (14, -28))):
        spawn(p, "Spawn%d" % (i + 1), 0, x, 0, z, 90)
    # Ladder up the block's west face to the vent roof (supervisors and rats).
    lx, lz = LADDER_YARD
    for dz in (-0.45, 0.45):
        p.box("LadderRail", lx - 0.12, 0, lz + dz - 0.04, lx - 0.04, ROOF_Y + 1.0, lz + dz + 0.04, p.mat(M_LADDER),
              parent=".")
    for i in range(1, int(ROOF_Y / 0.35)):
        p.box("LadderRung", lx - 0.1, i * 0.35, lz - 0.45, lx - 0.06, i * 0.35 + 0.04, lz + 0.45, p.mat(M_LADDER),
              parent=".")
    lad = p.s.node("Ladder", "Area3D", ".", {"position": V3(lx - 0.375, 0, lz), "rotation": V3(0, deg(-90), 0),
                                             "script": p.s.ext_res("Script", "res://interactables/ladder/ladder.gd")})
    p.s.node("Shape", "CollisionShape3D", lad, {"position": V3(0, (ROOF_Y + 1.0) / 2, 0),
                                               "shape": p.s.sub_res("BoxShape3D", {"size": V3(1.0, ROOF_Y + 1.0, 0.75)})})
    p.s.node("NavLink", "NavigationLink3D", ".", {"start_position": V3(lx - 1.2, 0, lz), "end_position": V3(lx + 1.0, ROOF_Y, lz),
                                                  "navigation_layers": 3})
    p.label("YARD", -30, 4.0, -22, 90)

    # --- Substation: transformers inside the fenced enclosure (puddles come in M6).
    p = poi("Substation")
    for x0, z0 in ((-50.0, -36.5), (-50.0, -28.0), (-36.0, -36.5)):
        p.box("Transformer", x0, 0, z0, x0 + 2.4, 1.8, z0 + 2.4, p.mat(M_MACHINE))
    p.box("Pylon", -34.5, 0, -27.5, -33.5, 1.0, -26.5, p.mat(M_METAL))
    beacon(p, -41, 3.0, -24.5)
    p.label("SUBSTATION", -41, 4.0, -33, 90)

    # --- Vent Roof: the block, fans, parapets (EXTRA_WALLS), the ventilation station.
    p = poi("VentRoof")
    bx0, bz0, bx1, bz1 = BLOCK
    p.box("Block", bx0, -0.5, bz0, bx1, ROOF_Y, bz1, p.floor_mat)
    p.occluder(bx0 + 0.2, 0, bz0 + 0.2, bx1 - 0.2, ROOF_Y - 0.2, bz1 - 0.2)
    p.box("Fan", 28.0, ROOF_Y, -36.0, 30.5, ROOF_Y + 1.0, -33.5, p.mat(M_METAL))
    p.box("Fan", 44.0, ROOF_Y, -25.0, 46.5, ROOF_Y + 1.0, -22.5, p.mat(M_METAL))
    p.box("Stack", 47.0, ROOF_Y, -35.0, 48.2, ROOF_Y + 3.0, -33.8, p.mat(M_PIPE))
    p.light(38, ROOF_Y + 4.0, -29, 16.0, 1.2, (0.75, 0.85, 1.0))
    beacon(p, 38, ROOF_Y + 2.6, -21)
    p.label("VENT ROOF", 38, ROOF_Y + 3.5, -32, 90)


# --- Vent network ----------------------------------------------------------------------------------

def duct_boxes(x0, z0, x1, z1, y, end0, end1, name):
    """Outer and inner (min, max) boxes of a straight duct and its VentVolume box."""
    iw, ow = VENT_W / 2, VENT_W / 2 + DUCT_SHELL
    along_x = abs(z1 - z0) < 1e-6
    a, b = (x0, x1) if along_x else (z0, z1)
    sign = 1 if b >= a else -1

    def ext(end, which):
        return {"closed": (ow, iw), "corner": (ow, iw), "joint": (0.3, 0.0), "seam": (0.05, 0.05),
                "open": (0.0, 0.3), "flush": (0.0, 0.0), "drop": (0.0, 0.25)}[end][which]
    oa, ob = a - sign * ext(end0, 0), b + sign * ext(end1, 0)
    ia, ib = a - sign * ext(end0, 1), b + sign * ext(end1, 1)
    if name in DUCT_FLUSH_OUTER:
        oa, ob = DUCT_FLUSH_OUTER[name]
    # The vent volume stops short of open ends, so a supervisor at the mouth isn't "inside".
    shrink = {"open": 0.4, "flush": 0.7, "drop": 0.35, "closed": 0.0, "corner": 0.0, "joint": 0.0, "seam": 0.0}
    va, vb = ia + sign * shrink[end0], ib - sign * shrink[end1]
    lo_o, hi_o = sorted((oa, ob))
    lo_i, hi_i = sorted((ia, ib))
    lo_v, hi_v = sorted((va, vb))
    oy0, oy1 = y - DUCT_SHELL, y + VENT_H + DUCT_SHELL
    iy0, iy1 = y, y + VENT_H
    if along_x:
        c = z0
        return ((lo_o, oy0, c - ow, hi_o, oy1, c + ow), (lo_i, iy0, c - iw, hi_i, iy1, c + iw),
                (lo_v, iy0, c - iw, hi_v, iy1, c + iw))
    c = x0
    return ((c - ow, oy0, lo_o, c + ow, oy1, hi_o), (c - iw, iy0, lo_i, c + iw, iy1, hi_i),
            (c - iw, iy0, lo_v, c + iw, iy1, hi_v))


MAX_DUCT_PIECE = 8.0  # long boxes give long sliver triangles that the navmesh baker rasterizes with holes


def split_ducts():
    """DUCTS with long runs cut into pieces of at most MAX_DUCT_PIECE, joined by small overlaps."""
    out = []
    for name, (x0, z0), (x1, z1), y, e0, e1 in DUCTS:
        length = math.hypot(x1 - x0, z1 - z0)
        n = max(1, math.ceil(length / MAX_DUCT_PIECE))
        for k in range(n):
            a, b = k / n, (k + 1) / n
            p0 = (x0 + (x1 - x0) * a, z0 + (z1 - z0) * a)
            p1 = (x0 + (x1 - x0) * b, z0 + (z1 - z0) * b)
            out.append((name if n == 1 else "%s%d" % (name, k + 1), p0, p1, y, e0 if k == 0 else "seam",
                        e1 if k == n - 1 else "seam"))
    return out


def build_vents():
    p = Poi("VentNetwork", "Vents", [])
    POIS["VentNetwork"] = p
    s = p.s
    duct_mat = p.mat(M_DUCT)
    outers, inners, volumes = [], [], []
    for name, (x0, z0), (x1, z1), y, e0, e1 in split_ducts():
        o, i, v = duct_boxes(x0, z0, x1, z1, y, e0, e1, name)
        outers.append((name, o))
        inners.append((name, i))
        volumes.append((name, v, None))
    # Shaft: from the east line's end up to the roof, exit to the west.
    sx, sz = SHAFT
    iw, ow = VENT_W / 2, VENT_W / 2 + DUCT_SHELL
    outers.append(("Shaft", (sx - ow, -DUCT_SHELL, sz - ow, sx + ow, ROOF_Y + EXIT_H + DUCT_SHELL, sz + ow)))
    inners.append(("Shaft", (sx - iw, 0.0, sz - iw, sx + iw, ROOF_Y + EXIT_H, sz + iw)))
    inners.append(("ShaftExit", (sx - iw - 0.9, ROOF_Y, sz - iw, sx - iw + 0.05, ROOF_Y + EXIT_H, sz + iw)))
    volumes.append(("Shaft", (sx - iw, 0.0, sz - iw, sx + iw, ROOF_Y + EXIT_H, sz + iw), None))
    # Outer shells first (union), then every inside (subtraction).
    for name, (a, b, c, d, e, f) in outers:
        p.box(name, a, b, c, d, e, f, duct_mat)
    rots = []
    for name, (xl, yl), (xh, yh), z in RAMPS:
        dx, dy = xh - xl, yh - yl
        length = math.hypot(dx, dy)
        if dx < 0:  # measure the angle along +X so the box's local +Y (the normal) points up
            dx, dy = -dx, -dy
        ang = math.atan2(dy, dx)
        nx, ny = -math.sin(ang), math.cos(ang)
        mx, my = (xl + xh) / 2, (yl + yh) / 2
        ci = (mx + nx * VENT_H / 2, my + ny * VENT_H / 2, z)
        p.rotated_box(name, ci, (length + 0.3, VENT_H + 2 * DUCT_SHELL, VENT_W + 2 * DUCT_SHELL), (0, 0, ang), duct_mat)
        rots.append((name + "Inside", ci, (length + 0.5, VENT_H, VENT_W), (0, 0, ang)))
        volumes.append((name, None, (ci, (length, VENT_H, VENT_W), (0, 0, ang))))
    for name, (a, b, c, d, e, f) in inners:
        n = p.box(name + "Inside", a, b, c, d, e, f, duct_mat)
        s.nodes[-1][4]["operation"] = 2
    for name, ci, size, rot in rots:
        p.rotated_box(name, ci, size, rot, duct_mat)
        s.nodes[-1][4]["operation"] = 2
    for axis, line, c in DUCT_GRILLES:
        if axis == "x":
            p.box("Grille", line - 0.25, 0.0, c - VENT_W / 2, line + 0.25, VENT_H, c + VENT_W / 2, duct_mat)
        else:
            p.box("Grille", c - VENT_W / 2, 0.0, line - 0.25, c + VENT_W / 2, VENT_H, line + 0.25, duct_mat)
        s.nodes[-1][4]["operation"] = 2
    # Vent exits (where a rat comes out into a room): for the map check and, later, bots.
    exits = s.node("VentExits", "Node3D")
    for o in OPENINGS:
        axis, line, c, kind, w, sill, oh = o
        if kind != "vent" or sill > 0.01:
            continue
        sides = [side for side in (-1, 1) if floor_at(*((c, line + side * 0.15) if axis == "z" else (line + side * 0.15, c)))]
        if len(sides) != 1 or (axis == "z" and line == 30):
            continue  # a duct passing through between two rooms, or the nest's own exit
        d = line + sides[0] * 0.8
        x, z = (c, d) if axis == "z" else (d, c)
        s.node("VentExit", "Marker3D", exits, {"position": V3(x, 0, z)}, groups=["vent_exits"])
    for name, (x0, z0), (x1, z1), y, e0, e1 in DUCTS:
        if e1 in ("open", "drop"):
            dx, dz = x1 - x0, z1 - z0
            n = math.hypot(dx, dz)
            ex, ez = x1 + dx / n * 1.0, z1 + dz / n * 1.0
            s.node("VentExit", "Marker3D", exits, {"position": V3(ex, 0, ez)}, groups=["vent_exits"])
    s.node("VentExit", "Marker3D", exits, {"position": V3(SHAFT[0] - 1.6, ROOF_Y, SHAFT[1])}, groups=["vent_exits"])
    # Vent volumes: rat-only space for the validator and the rat camera.
    vols = s.node("VentVolumes", "Node3D")
    for name, box, rotated in volumes:
        if box:
            a, b, c, d, e, f = box
            props = {"position": V3((a + d) / 2, (b + e) / 2, (c + f) / 2)}
            size = (d - a, e - b, f - c)
        else:
            ci, size, rot = rotated
            props = {"position": V3(*ci), "rotation": V3(*rot)}
        vv = s.node(name, "Area3D", vols, {**props, "script": s.ext_res("Script", "res://interactables/vent/vent_volume.gd")})
        s.node("Shape", "CollisionShape3D", vv, {"shape": s.sub_res("BoxShape3D", {"size": V3(*size)})})
    # The shaft is climbable (Ladder), exit to the west at the top.
    lad = s.node("ShaftLadder", "Area3D", ".", {"position": V3(sx, 0, sz), "rotation": V3(0, deg(90), 0),
                                                "script": s.ext_res("Script", "res://interactables/ladder/ladder.gd")})
    s.node("Shape", "CollisionShape3D", lad, {"position": V3(0, (ROOF_Y + 0.5) / 2, 0),
                                             "shape": s.sub_res("BoxShape3D", {"size": V3(VENT_W, ROOF_Y + 0.5, VENT_W)})})
    # Navigation links for the map check (and later bots): layer 2 = rats.
    s.node("ShaftLink", "NavigationLink3D", ".", {"start_position": V3(sx, 0, sz + 1.0),
                                                  "end_position": V3(sx - 1.6, ROOF_Y, sz), "navigation_layers": 2})
    s.node("DropLink", "NavigationLink3D", ".", {"start_position": V3(-2.0, 2.8, 20.6),
                                                 "end_position": V3(-2.0, 0, 18.4), "bidirectional": False,
                                                 "navigation_layers": 2})


# --- Plant root ------------------------------------------------------------------------------------

POI_ORDER = ["Yard", "Substation", "VentRoof", "PumpHouse", "ValveCorridor", "ReactorHall", "TurbineHall",
             "Storage", "CageRoom", "ControlRoom", "BreakRoom", "LockerRoom", "Corridors", "RatNest", "VentNetwork"]


def build_plant_root():
    s = Scene("Plant")
    sky_mat = s.sub_res("ProceduralSkyMaterial", {
        "sky_top_color": Col(0.02, 0.03, 0.08), "sky_horizon_color": Col(0.1, 0.12, 0.2),
        "ground_bottom_color": Col(0.02, 0.02, 0.03), "ground_horizon_color": Col(0.1, 0.12, 0.2),
        "sun_angle_max": 1.0})
    sky = s.sub_res("Sky", {"sky_material": sky_mat})
    env = s.sub_res("Environment", {"background_mode": 2, "sky": sky, "ambient_light_source": 2,
                                    "ambient_light_color": Col(0.55, 0.6, 0.75), "ambient_light_energy": 0.45,
                                    "tonemap_mode": 2, "glow_enabled": True, "glow_bloom": 0.1})
    s.node("WorldEnvironment", "WorldEnvironment", ".", {"environment": env})
    s.node("Moon", "DirectionalLight3D", ".", {"rotation": V3(deg(-50), deg(30), 0), "light_color": Col(0.6, 0.7, 1.0),
                                               "light_energy": 0.25, "sky_mode": 1})
    pois = s.node("POIs", "Node3D")
    for name in POI_ORDER:
        s.node(name, None, pois, instance="res://levels/plant/pois/%s.tscn" % name)
    # Out of bounds: under everything, around the yard, and on every roof.
    oob = s.node("OutOfBounds", "Node3D")

    def kill(name, x0, y0, z0, x1, y1, z1):
        n = s.node(name, "Area3D", oob, {"position": V3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
                                         "script": s.ext_res("Script", "res://levels/out_of_bounds.gd")})
        s.node("Shape", "CollisionShape3D", n, {"shape": s.sub_res("BoxShape3D", {"size": V3(x1 - x0, y1 - y0, z1 - z0)})})

    kill("Below", -150, -60, -150, 150, -8, 150)
    kill("BeyondYardNorth", -80, -5, -70, 26, 40, -38.3)
    kill("BeyondYardWest", -80, -5, -38.3, -53.3, 40, -20)
    for rid, scene, name, x0, z0, x1, z1, h, _ in ROOMS:
        if rid in OUTDOOR:
            continue
        kill("Roof" + rid, x0, h + CEIL_T + 0.05, z0, x1, h + 12, z1)
    # Where the camera looks from when this client has no body (OverviewCamera, SpectatorCam).
    eye, target = (6.0, 48.0, 62.0), (0.0, 0.0, -2.0)
    dx, dy, dz = target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]
    yaw = math.atan2(-dx, -dz)
    pitch = math.atan2(dy, math.hypot(dx, dz))
    s.node("OverviewPoint", "Marker3D", ".", {"position": V3(*eye), "rotation": V3(pitch, yaw, 0)},
           groups=["overview_point"])
    s.write(os.path.join(LEVEL_DIR, "Plant.tscn"))


def build_pois():
    bounds = {}
    for rid, scene, name, x0, z0, x1, z1, h, _ in ROOMS:
        bounds.setdefault(scene, []).append((name, (x0, -1.0, z0, x1 - x0, h + 1.0, z1 - z0)))
    bounds["Substation"] = [("Substation", (-52, -1, -38, 22, 5, 14))]
    bounds["VentRoof"] = [("Vent Roof", (24, ROOF_Y - 0.5, -38, 28, 4.5, 18))]
    for scene, entries in bounds.items():
        if scene == "Corridors":
            p = Poi(scene, "Corridors", [b for _, b in entries], [n for n, _ in entries])
        else:
            p = Poi(scene, entries[0][0], [b for _, b in entries])
        POIS[scene] = p
    build_vents()


def write_pois():
    os.makedirs(POI_DIR, exist_ok=True)
    for name, p in POIS.items():
        p.s.write(os.path.join(POI_DIR, name + ".tscn"))


# --- The plan image ----------------------------------------------------------------------------------

PX = 10  # pixels per metre
VIEW = (-58, -42, 58, 44)  # x0, z0, x1, z1 in metres


def draw_plan():
    from PIL import Image, ImageDraw, ImageFont
    margin_r = 300
    w = int((VIEW[2] - VIEW[0]) * PX) + margin_r
    h = int((VIEW[3] - VIEW[1]) * PX)
    img = Image.new("RGB", (w, h), (24, 26, 32))
    d = ImageDraw.Draw(img, "RGBA")
    font = ImageFont.load_default(size=13)
    small = ImageFont.load_default(size=10)
    big = ImageFont.load_default(size=18)

    def P(x, z):
        return ((x - VIEW[0]) * PX, (z - VIEW[1]) * PX)

    def rect(x0, z0, x1, z1, **kw):
        a, b = P(x0, z0)
        c, e = P(x1, z1)
        d.rectangle([min(a, c), min(b, e), max(a, c), max(b, e)], **kw)

    # Grid: 2 m faint, 10 m stronger.
    for gx in range(VIEW[0], VIEW[2] + 1, 2):
        d.line([P(gx, VIEW[1]), P(gx, VIEW[3])], fill=(255, 255, 255, 34 if gx % 10 else 70))
    for gz in range(VIEW[1], VIEW[3] + 1, 2):
        d.line([P(VIEW[0], gz), P(VIEW[2], gz)], fill=(255, 255, 255, 34 if gz % 10 else 70))
    # Rooms.
    for rid, scene, name, x0, z0, x1, z1, hh, color in ROOMS:
        rgb = tuple(int(c * 255) for c in color)
        rect(x0, z0, x1, z1, fill=rgb + (170,))
    bx0, bz0, bx1, bz1 = BLOCK
    rect(bx0, bz0, bx1, bz1, fill=(110, 120, 145, 220))
    # Substation enclosure tint.
    rect(-52, -38, -30, -24, fill=(150, 170, 120, 80))
    # Elevated floors: catwalks and the vent roof (hatched).
    for x0, z0, x1, z1 in ((-38, -20, -10, -18.5), (-38, -20, -36.5, 0), (-10, -20, 34, -18.5)):
        a, b = P(x0, z0)
        c, e = P(x1, z1)
        for k in range(int(min(a, c)), int(max(a, c)), 6):
            d.line([(k, min(b, e)), (min(k + (max(b, e) - min(b, e)), max(a, c)), max(b, e))], fill=(30, 30, 30, 150))
    a, b = P(bx0, bz0)
    c, e = P(bx1, bz1)
    for k in range(int(a), int(c), 10):
        d.line([(k, b), (k, e)], fill=(255, 255, 255, 25))
    # Cooling tower.
    cx, cz = P(-2, -32)
    d.ellipse([cx - 6 * PX, cz - 6 * PX, cx + 6 * PX, cz + 6 * PX], fill=(190, 190, 185, 255), outline=(60, 60, 60))
    d.text((cx, cz), "COOLING\nTOWER", fill=(40, 40, 40), font=font, anchor="mm", align="center")
    # Walls (ground-level pieces) with openings drawn by kind.
    door_colors = {"door": (200, 140, 70), "keycard": (80, 130, 255), "window": (150, 220, 255)}
    for axis, line, a0, b0, hh, owner in wall_runs():
        ops = openings_on(axis, line, a0, b0)
        for pa, pb, y0, y1 in cut_run(a0, b0, hh, [(o[2], o[4], o[5], o[6]) for o in ops], extend_ends=False):
            if y0 > 0.01:
                continue
            seg = (P(pa, line), P(pb, line)) if axis == "z" else (P(line, pa), P(line, pb))
            d.line(seg, fill=(15, 15, 18), width=5)
        for o in ops:
            _, _, c, kind, ow_, sill, oh = o
            l, r = c - ow_ / 2, c + ow_ / 2
            seg = (P(l, line), P(r, line)) if axis == "z" else (P(line, l), P(line, r))
            if kind in door_colors:
                d.line(seg, fill=door_colors[kind], width=4 if kind != "window" else 3)
            elif kind == "vent" and sill < 0.01:
                d.line(seg, fill=(190, 110, 255), width=6)
    for scene, axis, line, a0, b0, base, hh, ops in EXTRA_WALLS:
        for pa, pb, y0, y1 in cut_run(a0, b0, hh, [(c, ww, s, oh) for _, c, ww, s, oh in ops], extend_ends=False):
            if y0 > 0.01:
                continue
            seg = (P(pa, line), P(pb, line)) if axis == "z" else (P(line, pa), P(line, pb))
            d.line(seg, fill=(15, 15, 18) if base < 1 else (60, 60, 80), width=3 if base < 1 else 4)
    # Ducts.
    for name, (x0, z0), (x1, z1), y, e0, e1 in DUCTS:
        col = (190, 110, 255, 255) if y < 0.5 else (240, 170, 255, 255)
        seg = [P(x0, z0), P(x1, z1)]
        if y < 0.5:
            d.line(seg, fill=col, width=4)
        else:
            n = 14
            for k in range(n):
                if k % 2 == 0:
                    t0, t1 = k / n, (k + 1) / n
                    d.line([(seg[0][0] + (seg[1][0] - seg[0][0]) * t0, seg[0][1] + (seg[1][1] - seg[0][1]) * t0),
                            (seg[0][0] + (seg[1][0] - seg[0][0]) * t1, seg[0][1] + (seg[1][1] - seg[0][1]) * t1)],
                           fill=col, width=4)
    for name, (xl, yl), (xh, yh), z in RAMPS:
        d.line([P(xl, z), P(xh, z)], fill=(240, 170, 255), width=4)
    sx, sz = SHAFT
    a, b = P(sx, sz)
    d.rectangle([a - 6, b - 6, a + 6, b + 6], outline=(240, 170, 255), width=3)
    d.text((a + 8, b - 18), "shaft\n(climb)", fill=(240, 170, 255), font=small)
    a, b = P(-2, 19.75)
    d.polygon([(a - 7, b - 9), (a + 7, b - 9), (a, b + 2)], fill=(240, 170, 255))
    d.text((a + 9, b - 12), "drop (one-way)", fill=(240, 170, 255), font=small)
    # Ladders.
    for (lx, lz) in (LADDER_YARD,):
        a, b = P(lx - 0.4, lz)
        d.rectangle([a - 5, b - 9, a + 3, b + 9], outline=(255, 200, 60), width=2)
        d.text((a - 52, b - 6), "ladder", fill=(255, 200, 60), font=small)
    # Stations.
    for sid, scene, node, x, y, z, yaw, critical in STATIONS:
        a, b = P(x, z)
        r = 9
        pts = []
        for k in range(10):
            ang = -math.pi / 2 + k * math.pi / 5
            rr = r if k % 2 == 0 else r * 0.45
            pts.append((a + rr * math.cos(ang), b + rr * math.sin(ang)))
        d.polygon(pts, fill=(255, 80, 90) if critical else (255, 200, 60), outline=(20, 20, 20))
        d.text((a, b + 12), sid + (" (2 levers)" if critical else ""), fill=(255, 255, 255), font=font, anchor="ma",
               stroke_width=2, stroke_fill=(0, 0, 0))
    # Cameras: a dot and the view direction.
    for number, scene, label, (x, y, z), yaw, lens_h, pitch, yaw_off in CAMERAS:
        a, b = P(x, z)
        face = math.radians(yaw + yaw_off)
        fx, fz = math.sin(face), math.cos(face)
        length = 9.0 * PX
        for spread in (-0.45, 0.45):
            ang = math.atan2(fz, fx) + spread
            d.line([(a, b), (a + math.cos(ang) * length, b + math.sin(ang) * length)], fill=(120, 230, 255, 110), width=1)
        d.ellipse([a - 5, b - 5, a + 5, b + 5], fill=(120, 230, 255), outline=(10, 10, 10))
        d.text((a + 6, b + 4), str(number), fill=(120, 230, 255), font=font, stroke_width=2, stroke_fill=(0, 0, 0))
    # Spawns, cages, pickups, console.
    marks = [((-24, 12), "S"), ((-28, 12), "S")] + [((x, z), "R") for x, z in ((-32, 34), (-28, 34), (-32, 37), (-28, 37))] \
        + [((x, z), "L") for x, z in ((18, -22), (18, -25), (18, -28), (14, -22), (14, -25), (14, -28))]
    mark_col = {"S": (255, 220, 80), "R": (120, 255, 120), "L": (230, 230, 230)}
    for (x, z), t in marks:
        a, b = P(x, z)
        d.ellipse([a - 6, b - 6, a + 6, b + 6], fill=mark_col[t], outline=(0, 0, 0))
        d.text((a, b), t, fill=(0, 0, 0), font=small, anchor="mm")
    for (x, z), t in (((37.2, 2.0), "CAGE"), ((47.2, 10.0), "CAGE"), ((35.0, -15.0), "traps +\nkeycard"),
                      ((-15.2, 14.0), "donuts"), ((-1.0, 15.6), "CCTV\nchair"), ((-13.7, 12.0), "status\nboard")):
        a, b = P(x, z)
        d.rectangle([a - 4, b - 4, a + 4, b + 4], fill=(255, 255, 255))
        d.text((a + 6, b - 6), t, fill=(255, 255, 255), font=small, stroke_width=2, stroke_fill=(0, 0, 0))
    # Room names.
    for rid, scene, name, x0, z0, x1, z1, hh, color in ROOMS:
        corridor = rid in ("MHW", "MHE", "CS")
        a, b = P((x0 + x1) / 2, (z0 + z1) / 2 if corridor else z0 + 2.6)
        label = name.upper() + (" (%d m high)" % hh if hh > 4 else "")
        d.text((a, b), label, fill=(255, 255, 255), font=font if corridor else big, anchor="mm", align="center",
               stroke_width=3, stroke_fill=(0, 0, 0))
    a, b = P(38, -33)
    d.text((a, b), "VENT ROOF\n(6 m, ladder / shaft)", fill=(255, 255, 255), font=font, anchor="mm", align="center",
           stroke_width=3, stroke_fill=(0, 0, 0))
    a, b = P(-41, -36.5)
    d.text((a, b), "SUBSTATION", fill=(255, 255, 255), font=font, anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0))
    # Legend.
    lx = int((VIEW[2] - VIEW[0]) * PX) + 16
    y = 16
    d.text((lx, y), "Sunny Acres plant, layout v1", fill=(255, 255, 255), font=big)
    y += 26
    d.text((lx, y), "grid: 2 m (bold: 10 m), north up", fill=(200, 200, 200), font=font)
    y += 26
    legend = [
        ((15, 15, 18), "wall"), ((200, 140, 70), "door (opens for anyone)"), ((80, 130, 255), "keycard door"),
        ((150, 220, 255), "window"), ((190, 110, 255), "vent duct / opening (rats)"),
        ((240, 170, 255), "raised duct (dashed), ramp, shaft"), ((255, 200, 60), "station (subsystem)"),
        ((255, 80, 90), "critical station (2 levers)"), ((120, 230, 255), "CCTV camera + view"),
        ((255, 220, 80), "S supervisor spawn"), ((120, 255, 120), "R rat spawn"), ((230, 230, 230), "L lobby spawn"),
    ]
    for col, text in legend:
        d.rectangle([lx, y + 2, lx + 18, y + 12], fill=col)
        d.text((lx + 26, y), text, fill=(230, 230, 230), font=font)
        y += 20
    y += 8
    d.text((lx, y), "hatched: catwalks (3.5-4 m)\nbars: vent roof block (6 m)", fill=(200, 200, 200), font=font)
    y += 44
    # Scale bar.
    d.line([(lx, y + 10), (lx + 10 * PX, y + 10)], fill=(255, 255, 255), width=3)
    d.text((lx, y + 14), "10 m", fill=(255, 255, 255), font=font)
    os.makedirs(DOC_DIR, exist_ok=True)
    img.save(os.path.join(DOC_DIR, "plant_layout_v1.png"))
    meta = {"image": "plant_layout_v1.png", "px_per_m": PX, "world_min": [VIEW[0], VIEW[1]],
            "world_max": [VIEW[2], VIEW[3]],
            "note": "pixel = (x - world_min[0], z - world_min[1]) * px_per_m; +x right, +z down (north up)"}
    with open(os.path.join(DOC_DIR, "plant_layout_v1.json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")


# --- Main -------------------------------------------------------------------------------------------

def main():
    force = "--force" in sys.argv
    png_only = "--png-only" in sys.argv
    if not png_only:
        if os.path.exists(os.path.join(LEVEL_DIR, "Plant.tscn")) and not force:
            sys.exit("levels/plant/Plant.tscn exists: pass --force to overwrite the generated scenes "
                     "(hand edits in levels/plant/ are lost), or --png-only for just the plan image.")
        build_pois()
        build_rooms()
        build_stations()
        build_cameras()
        build_props()
        write_materials()
        write_pois()
        build_plant_root()
        print("wrote %d POI scenes, %d materials and Plant.tscn" % (len(POIS), len(MATERIALS)))
    draw_plan()
    print("wrote docs/map/plant_layout_v1.png (+ .json)")


if __name__ == "__main__":
    main()

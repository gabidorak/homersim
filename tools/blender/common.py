"""Shared helpers for the prop scripts (ASSETS §4). Run the scripts with Blender 4.2+ headless:

    blender -b -P tools/blender/crate.py -- [--out assets/generated/crate.glb] [script options]
    blender -b -P tools/blender/export_all.py

A prop is built with `Builder`: primitives (boxes, cylinders, spheres...) go into one mesh, each
painted with a palette colour by name (tools/art/palette.py). Each face's UVs all sit at the centre
of its colour's swatch in assets/palette.png, so one shared material (Godot:
shaders/materials/toon_palette.tres) draws every prop. Faces can be emissive (the palette colour
glows) or glass; the import script (tools/godot/toon_import.gd) maps the material names
"palette", "palette_emissive" and "glass" onto the shared Godot materials.

Conventions: 1 unit = 1 m, Blender +Z up, origin at the base centre, models face -Y (Front view),
which becomes +Z in Godot. Animatable parts (a valve wheel, a lever, a door) are separate child
objects with their pivot as origin, named in CamelCase: Godot code finds them by name.

Every mesh stores smoothed normals in its vertex colour (rgb = n * 0.5 + 0.5, alpha 0): the outline
shader grows the hull along them, so it doesn't tear apart at hard edges.
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
import palette as P  # noqa: E402

GENERATED = os.path.join(ROOT, "assets", "generated")
PALETTE_PNG = os.path.join(ROOT, "assets", "palette.png")
MAT_PALETTE, MAT_EMISSIVE, MAT_GLASS = 0, 1, 2
MATERIAL_NAMES = ["palette", "palette_emissive", "glass"]


# --- Command line -------------------------------------------------------------------------------

def args(defaults_name, extra=None):
    """Parses the options after `--`. `extra(parser)` may add script options. Returns the namespace;
    `out` defaults to assets/generated/<defaults_name>.glb."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog=defaults_name)
    parser.add_argument("--out", default=os.path.join(GENERATED, defaults_name + ".glb"))
    if extra:
        extra(parser)
    ns, _ = parser.parse_known_args(argv)
    return ns


# --- Scene --------------------------------------------------------------------------------------

def reset():
    """An empty scene in metric units (keeps the script independent of the user's startup file)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30


def materials():
    """The three shared materials (created once per file). The palette image is embedded in the
    .glb so the file previews correctly anywhere; Godot swaps in the shared material on import."""
    if "palette" in bpy.data.materials:
        return [bpy.data.materials[n] for n in MATERIAL_NAMES]
    img = bpy.data.images.load(PALETTE_PNG, check_existing=True)
    result = []
    for name in MATERIAL_NAMES:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = 1.0
        if name == "glass":
            bsdf.inputs["Base Color"].default_value = (0.75, 0.89, 0.95, 1.0)
            bsdf.inputs["Alpha"].default_value = 0.25
            mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else None
        else:
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = img
            tex.interpolation = "Closest"
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            if name == "palette_emissive":
                mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
                bsdf.inputs["Emission Strength"].default_value = 2.0
        result.append(mat)
    return result


# --- Building meshes --------------------------------------------------------------------------------

def _matrix(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """loc in m, rot in degrees (XYZ Euler), scale per axis."""
    return (Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
            @ Matrix.Diagonal(Vector((*scale, 1.0))))


class Builder:
    """Accumulates painted primitives into one mesh. All positions are in the object's local space
    (its origin is the pivot given to finish())."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.pal = self.bm.faces.layers.int.new("pal")
        self.flags = self.bm.faces.layers.int.new("flags")  # bit 0 smooth

    # Each primitive: build into the shared bmesh, bevel, then paint the faces still unpainted.
    def _paint(self, color, material, smooth):
        if color not in P.COLORS:
            raise KeyError("unknown palette colour '%s'" % color)
        idx = list(P.COLORS).index(color)
        for f in self._new_faces:
            f[self.pal] = idx
            f.material_index = material
            f[self.flags] = 1 if smooth else 0
        self._new_faces = []

    def _begin(self):
        self._before = set(self.bm.faces)

    def _collect(self):
        self.bm.faces.ensure_lookup_table()
        self._new_faces = [f for f in self.bm.faces if f not in self._before]

    def _bevel(self, verts, width, segments=1):
        if width <= 0:
            return
        vs = set(verts)
        edges = [e for e in self.bm.edges if e.verts[0] in vs and e.verts[1] in vs]
        bmesh.ops.bevel(self.bm, geom=list(vs) + edges, offset=width, offset_type="OFFSET",
                        segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)

    def _finish_prim(self, color, material, smooth):
        self._collect()
        self._paint(color, material, smooth)

    def box(self, size, loc=(0, 0, 0), color="grey", rot=(0, 0, 0), bevel=0.0, material=MAT_PALETTE,
            base=False):
        """A box of `size` (x, y, z) centred at `loc` (or standing on it if `base`)."""
        self._begin()
        loc = Vector(loc) + (Vector((0, 0, size[2] / 2)) if base else Vector())
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=_matrix(loc, rot, size))
        self._bevel(res["verts"], bevel)
        self._finish_prim(color, material, False)
        return self

    def cylinder(self, radius, depth, loc=(0, 0, 0), color="grey", rot=(0, 0, 0), segments=12, bevel=0.0,
                 radius_top=None, material=MAT_PALETTE, smooth=True, base=False, caps=True):
        """A cylinder (or cone/frustum with `radius_top`) along local Z, centred on `loc` (or with its
        bottom cap on `loc` if `base`; `rot` turns it about that point)."""
        self._begin()
        r2 = radius if radius_top is None else radius_top
        m = _matrix(loc, rot) @ Matrix.Translation((0, 0, depth / 2 if base else 0))
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segments,
                                    radius1=radius, radius2=r2, depth=depth, matrix=m)
        self._bevel(res["verts"], bevel)
        self._finish_prim(color, material, smooth)
        return self

    def sphere(self, radius, loc=(0, 0, 0), color="grey", scale=(1, 1, 1), rot=(0, 0, 0), segments=10, rings=6,
               material=MAT_PALETTE, smooth=True):
        self._begin()
        bmesh.ops.create_uvsphere(self.bm, u_segments=segments, v_segments=rings, radius=radius,
                                  matrix=_matrix(loc, rot, scale))
        self._finish_prim(color, material, smooth)
        return self

    def torus(self, major, minor, loc=(0, 0, 0), color="grey", rot=(0, 0, 0), segments=16, sides=6,
              material=MAT_PALETTE, smooth=True, scale=(1, 1, 1)):
        """A ring around local Z."""
        self._begin()
        verts = []
        m = _matrix(loc, rot, scale)
        for i in range(segments):
            a = 2 * math.pi * i / segments
            for j in range(sides):
                b = 2 * math.pi * j / sides
                r = major + minor * math.cos(b)
                verts.append(self.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), minor * math.sin(b)))))
        for i in range(segments):
            for j in range(sides):
                a = verts[i * sides + j]
                b = verts[((i + 1) % segments) * sides + j]
                c = verts[((i + 1) % segments) * sides + (j + 1) % sides]
                d = verts[i * sides + (j + 1) % sides]
                self.bm.faces.new((a, b, c, d))
        self._finish_prim(color, material, smooth)
        return self

    def prism(self, points, depth, loc=(0, 0, 0), color="grey", rot=(0, 0, 0), bevel=0.0, material=MAT_PALETTE):
        """An extruded polygon: `points` (x, y) counter-clockwise in the XY plane, extruded `depth`
        along +Z from z = 0, then moved by loc/rot."""
        self._begin()
        m = _matrix(loc, rot)
        bottom = [self.bm.verts.new(m @ Vector((x, y, 0))) for x, y in points]
        top = [self.bm.verts.new(m @ Vector((x, y, depth))) for x, y in points]
        self.bm.faces.new(list(reversed(bottom)))
        self.bm.faces.new(top)
        n = len(points)
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
        self._bevel(bottom + top, bevel)
        self._finish_prim(color, material, False)
        return self

    def tube(self, path, radius, color="grey", segments=8, smooth=True, material=MAT_PALETTE):
        """A pipe through the 3D points of `path` (open ends)."""
        self._begin()
        rings = []
        for k, p in enumerate(path):
            p = Vector(p)
            d = (Vector(path[min(k + 1, len(path) - 1)]) - Vector(path[max(k - 1, 0)])).normalized()
            up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            u = d.cross(up).normalized()
            v = d.cross(u).normalized()
            rings.append([self.bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * radius)
                          for a in [2 * math.pi * i / segments for i in range(segments)]])
        for r0, r1 in zip(rings, rings[1:]):
            for i in range(segments):
                j = (i + 1) % segments
                self.bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
        self._finish_prim(color, material, smooth)
        return self

    def finish(self, pivot=(0, 0, 0), parent=None, smooth_angle=35.0):
        """Creates the object. Geometry was built in parent space; `pivot` becomes the object's
        origin (geometry is shifted so it doesn't move)."""
        bm = self.bm
        bmesh.ops.translate(bm, verts=bm.verts, vec=-Vector(pivot))
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        uv = bm.loops.layers.uv.new("UVMap")
        names = list(P.COLORS)
        for f in bm.faces:
            u, v = P.uv(names[f[self.pal]])
            for loop in f.loops:
                loop[uv].uv = (u, 1.0 - v)
            f.smooth = bool(f[self.flags] & 1)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        for layer in ("pal", "flags"):
            if layer in me.attributes:
                me.attributes.remove(me.attributes[layer])
        for mat in materials():
            me.materials.append(mat)
        if smooth_angle:
            # Smooth faces keep hard edges above the angle; flat faces stay flat.
            flat = [not p.use_smooth for p in me.polygons]
            me.set_sharp_from_angle(angle=math.radians(smooth_angle))
            for p, f in zip(me.polygons, flat):
                p.use_smooth = not f
        _store_outline_normals(me)
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent
            obj.location = Vector(pivot) - _world_pivot(parent)
        else:
            obj.location = Vector(pivot)
        _drop_unused_materials(obj)
        return obj


def _world_pivot(obj):
    p = Vector()
    while obj is not None:
        p += obj.location
        obj = obj.parent
    return p


def _drop_unused_materials(obj):
    """Keeps slot order but empties slots no face uses (the exporter then skips them)."""
    me = obj.data
    used = {p.material_index for p in me.polygons}
    for i in range(len(me.materials)):
        if i not in used:
            me.materials[i] = None


def _store_outline_normals(me):
    """Smoothed (vertex) normals into a float colour attribute, alpha 0 = "outline normal" marker."""
    name = "OutlineNormal"
    if name in me.color_attributes:
        me.color_attributes.remove(me.color_attributes[name])
    attr = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    for v in me.vertices:
        n = v.normal
        attr.data[v.index].color = (n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 0.0)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.find(name)


def store_outline_normals(obj):
    """Public version for imported meshes (recoloured third-party models)."""
    _store_outline_normals(obj.data)


def empty(name, loc=(0, 0, 0), parent=None):
    """A named marker node (a socket or pivot Godot code looks up by name)."""
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.empty_display_size = 0.1
    obj.location = Vector(loc) - (_world_pivot(parent) if parent else Vector())
    obj.parent = parent
    return obj


# --- Export ---------------------------------------------------------------------------------------

def export(path, objects=None, animations=False):
    """Writes the scene (or `objects` and their children) to `path` as .glb."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    sel = objects if objects is not None else list(bpy.context.scene.objects)
    for o in sel:
        for d in [o] + list(o.children_recursive):
            d.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_normals=True,
        export_texcoords=True, export_animations=animations, export_skins=animations,
        export_morph=False, export_image_format="NONE", export_extras=False)
    print("exported", os.path.relpath(path, ROOT), _stats(sel))


def _stats(objects):
    tris = 0
    for o in objects:
        for d in [o] + list(o.children_recursive):
            if d.type == "MESH":
                d.data.calc_loop_triangles()
                tris += len(d.data.loop_triangles)
    return "(%d tris)" % tris


def tris_of(objects):
    return int(_stats(objects).strip("( tris)"))

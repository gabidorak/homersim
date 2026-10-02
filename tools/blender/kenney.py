"""Brings CC0 Kenney models (assets/third_party/kenney_*/models/) onto the game's palette and scale.

    blender -b -P tools/blender/kenney.py -- --kind k_mug [--out PATH]

For each face, the source colour (the material's base colour, times its colormap texture sampled at
the face's UV centre when it has one) is mapped to the nearest palette swatch (with per-model
overrides), the UVs move to that swatch, and the shared "palette" material replaces the original.
Then the model is joined into one mesh, scaled to a real-world height, set on the floor at the
origin, given outline normals, and exported as assets/generated/k_<name>.glb.
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
sys.path.insert(0, os.path.join(C.ROOT, "tools", "art"))
import palette as PAL  # noqa: E402

TP = os.path.join(C.ROOT, "assets", "third_party")
# out name -> (pack, model, height in m (negative: the longest side instead), palette overrides
# {nearest -> wanted})
MODELS = {
    "k_chair_desk": ("furniture-kit", "chairDesk", 0.95, {}),
    "k_computer_screen": ("furniture-kit", "computerScreen", 0.45, {}),
    "k_keyboard": ("furniture-kit", "computerKeyboard", 0.03, {}),
    "k_fridge": ("furniture-kit", "kitchenFridge", 1.9, {}),
    "k_microwave": ("furniture-kit", "kitchenMicrowave", 0.32, {}),
    "k_trashcan": ("furniture-kit", "trashcan", 0.7, {}),
    "k_plant_small": ("furniture-kit", "plantSmall1", 0.45, {}),
    "k_potted_plant": ("furniture-kit", "pottedPlant", 1.2, {}),
    "k_books": ("furniture-kit", "books", 0.25, {}),
    "k_coat_rack": ("furniture-kit", "coatRackStanding", 1.8, {}),
    "k_ceiling_lamp": ("furniture-kit", "lampSquareCeiling", 0.35, {}),
    "k_radio": ("furniture-kit", "radio", 0.22, {}),
    "k_box_closed": ("furniture-kit", "cardboardBoxClosed", 0.45, {}),
    "k_box_open": ("furniture-kit", "cardboardBoxOpen", 0.45, {}),
    "k_side_table": ("furniture-kit", "sideTable", 0.55, {}),
    "k_sofa": ("furniture-kit", "loungeSofa", 0.85, {}),
    "k_tv": ("furniture-kit", "televisionVintage", 0.6, {}),
    "k_mug": ("food-kit", "mug", 0.11, {}),
    "k_coffee_cup": ("food-kit", "cup-coffee", 0.13, {}),
    "k_pizza_box": ("food-kit", "pizza-box", -0.42, {}),
    "k_donut_sprinkles": ("food-kit", "donut-sprinkles", 0.06, {}),
    "k_soda_can": ("food-kit", "soda-can", 0.13, {}),
    "k_cheese": ("food-kit", "cheese", 0.12, {}),
    "k_box_small": ("factory-kit", "box-small", 0.5, {}),
    "k_box_large": ("factory-kit", "box-large", 0.9, {}),
    "k_cone": ("factory-kit", "cone", 0.5, {}),
    "k_warning_post": ("factory-kit", "warning-orange", 1.0, {}),
    "k_lever": ("factory-kit", "lever-single", 0.6, {}),
    "k_screen_small": ("factory-kit", "screen-small", 0.6, {}),
    "k_barrel": ("survival-kit", "barrel", 0.9, {}),
    "k_crate": ("survival-kit", "box", 0.7, {}),
    "k_bucket": ("survival-kit", "bucket", 0.35, {}),
    "k_hammer": ("survival-kit", "tool-hammer", -0.32, {}),
}
ASSETS = [(name, {"name": name}) for name in MODELS]


def _pixels(img):
    return (list(img.pixels), img.size[0], img.size[1]) if img is not None else None


def _material_info(mat, cache):
    """(base colour rgb, (pixels, w, h) or None, emissive) for a material."""
    if mat is None:
        return (0.8, 0.8, 0.8), None, False
    if mat.name in cache:
        return cache[mat.name]
    base, tex, emissive = (0.8, 0.8, 0.8), None, False
    if mat.use_nodes:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is not None:
            base = tuple(bsdf.inputs["Base Color"].default_value[:3])
            if "Emission Strength" in bsdf.inputs and bsdf.inputs["Emission Strength"].default_value > 0.01 \
                    and max(bsdf.inputs["Emission Color"].default_value[:3]) > 0.01:
                emissive = True
        node = next((n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), None)
        if node is not None:
            tex = _pixels(node.image)
    cache[mat.name] = (base, tex, emissive)
    return cache[mat.name]


def _linear_to_srgb(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def convert(obj, overrides, cache):
    me = obj.data
    uv_layer = me.uv_layers.active
    uv = uv_layer.data if uv_layer else None
    if uv is None:
        uv_layer = me.uv_layers.new(name="UVMap")
        uv = uv_layer.data
        have_uv = False
    else:
        have_uv = True
    emissive_faces = []
    for p in me.polygons:
        mat = me.materials[p.material_index] if me.materials else None
        base, tex, emissive = _material_info(mat, cache)
        rgb = [_linear_to_srgb(c) for c in base]  # material colours are linear, the palette is sRGB
        if tex is not None and have_uv:
            px, w, h = tex
            u = sum((uv[li].uv for li in p.loop_indices), Vector((0, 0))) / p.loop_total
            x = min(w - 1, max(0, int(u.x % 1.0 * w)))
            y = min(h - 1, max(0, int(u.y % 1.0 * h)))
            i = (y * w + x) * 4
            rgb = [px[i], px[i + 1], px[i + 2]]  # colormaps are sRGB, read as stored
        name = PAL.nearest(tuple(rgb))
        name = overrides.get(name, name)
        su, sv = PAL.uv(name)
        for li in p.loop_indices:
            uv[li].uv = (su, 1.0 - sv)
        if emissive:
            emissive_faces.append(p.index)
    mats = C.materials()
    me.materials.clear()
    me.materials.append(mats[0])
    me.materials.append(mats[1])
    for p in me.polygons:
        p.material_index = 1 if p.index in emissive_faces else 0


def build(name="k_mug"):
    pack, model, height, overrides = MODELS[name]
    path = os.path.join(TP, "kenney_" + pack, "models", model + ".glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH" and not o.name.startswith("Icosphere")]
    cache = {}
    for o in meshes:
        convert(o, overrides, cache)
    # Bake transforms, join, clean up.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    for o in meshes:
        world = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    others = [o.name for o in new if o not in meshes]
    if len(meshes) > 1:
        with bpy.context.temp_override(active_object=meshes[0], selected_editable_objects=meshes, selected_objects=meshes):
            bpy.ops.object.join()
    obj = meshes[0]
    for n in others:  # empties and armature-less roots of the import
        if n in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[n])
    obj.name = obj.data.name = "".join(part.capitalize() for part in name[2:].split("_"))
    # Scale to height, base centre on the origin.
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = hi - lo
    s = height / max(size.z, 1e-4) if height > 0 else -height / max(size.x, size.y, size.z, 1e-4)
    for v in obj.data.vertices:
        v.co = (v.co - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))) * s
    obj.location = (0, 0, 0)
    obj.data.update()
    # Drop the empty material slot if nothing glows.
    if all(p.material_index == 0 for p in obj.data.polygons):
        obj.data.materials.pop(index=1)
    C.store_outline_normals(obj)
    return obj


if __name__ == "__main__":
    a = C.args("k_mug", lambda p: p.add_argument("--kind", default="k_mug", choices=sorted(MODELS)))
    C.reset()
    C.export(a.out, [build(a.kind)])

"""Renders a script's models to a PNG for a quick look (no Godot needed). Run from the repo root:

    blender -b -P tools/blender/preview.py -- crate valve --out /tmp/preview.png
        [--anim NAME --frame N] [--yaw DEG] [--pitch DEG] [--size W H]

Builds every ASSETS entry of the named scripts, lines them up along X (labelled in the console),
and renders with the Workbench engine in flat texture colours plus a cavity outline. With --anim,
each armature plays that action at --frame. This is only a modelling aid: the real look (toon
shading, outlines) is checked in Godot with tests/helpers/ArtGallery.tscn.
"""
import argparse
import importlib
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for d in [o] + list(o.children_recursive):
            if d.type != "MESH":
                continue
            for c in d.bound_box:
                w = d.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    return lo, hi


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("scripts", nargs="+")
    ap.add_argument("--out", default="/tmp/preview.png")
    ap.add_argument("--anim")
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--yaw", type=float, default=-30)
    ap.add_argument("--pitch", type=float, default=20)
    ap.add_argument("--size", type=int, nargs=2, default=[1600, 900])
    ap.add_argument("--only", help="comma-separated ASSETS names to include")
    a = ap.parse_args(argv)
    C.reset()
    x = 0.0
    lo_all, hi_all = None, None
    for name in a.scripts:
        mod = importlib.import_module(name)
        for out_name, kwargs in mod.ASSETS:
            if a.only and out_name not in a.only.split(","):
                continue
            before = set(bpy.data.objects)
            roots = mod.build(**kwargs)
            new = [o for o in bpy.data.objects if o not in before]
            roots = [o for o in new if o.parent is None]
            bpy.context.view_layer.update()
            lo, hi = bounds(roots)
            for r in roots:
                r.location.x += x - lo.x
            bpy.context.view_layer.update()
            lo, hi = bounds(roots)
            print("preview: %-28s x %.2f..%.2f  size %.2f x %.2f x %.2f  %d tris" % (
                out_name, lo.x, hi.x, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, C.tris_of(roots)))
            lo_all = lo if lo_all is None else Vector(map(min, lo_all, lo))
            hi_all = hi if hi_all is None else Vector(map(max, hi_all, hi))
            x = hi.x + 0.5
            if a.anim:
                for o in new:
                    if o.type == "ARMATURE" and a.anim in bpy.data.actions:
                        o.animation_data_create()
                        o.animation_data.action = bpy.data.actions[a.anim]
                        if hasattr(o.animation_data, "action_slot") and bpy.data.actions[a.anim].slots:
                            o.animation_data.action_slot = bpy.data.actions[a.anim].slots[0]
    scene = bpy.context.scene
    scene.frame_set(a.frame)
    centre = (lo_all + hi_all) / 2
    size = (hi_all - lo_all).length
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    yaw, pitch = math.radians(a.yaw), math.radians(a.pitch)
    dist = size * 1.5 + 1.0
    cam.location = centre + Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * dist
    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.view_settings.view_transform = "Standard"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    shading.show_object_outline = True
    scene.render.resolution_x, scene.render.resolution_y = a.size
    scene.render.filepath = a.out
    bpy.ops.render.render(write_still=True)
    print("preview written to", a.out)


if __name__ == "__main__":
    main()

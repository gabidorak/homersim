"""First-person arms and broom for the local supervisor (only they see it, in front of the camera).

    blender -b -P tools/blender/fp_arms.py -- [--out PATH] [--render DIR]

The origin is the camera; it looks along +Y (Godot -Z) with +Z up, at an 80 degree vertical field
of view. Chunky Kenney-style forearms (white shirt cuffs, skin hands) and the broom in the right
hand. Bones: root, arm_r (elbow pivot, lower right), arm_l (elbow pivot, lower left), broom (child
of arm_r, at the grip). Clips: idle (loop), swing, interact (loop), carry (loop), eat, place.
--render DIR also renders each clip's key frames from the camera (framing check).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import rat as R  # noqa: E402

ASSETS = [("fp_arms", {})]
ANIMATED = True

ELBOW_R = (0.46, 0.18, -0.6)
GRIP = (0.36, 0.5, -0.42)
ELBOW_L = (-0.46, 0.16, -0.66)
HAND_L = (-0.34, 0.44, -0.6)
BONES = [("root", None, (0, 0, 0)), ("arm_r", "root", ELBOW_R), ("arm_l", "root", ELBOW_L),
         ("broom", "arm_r", GRIP)]


def _forearm(name, elbow, hand, side):
    b = C.Builder(name)
    R.rod(b, elbow, hand, 0.075, 0.07, "shirt_white", segments=8)
    d = (Vector(hand) - Vector(elbow)).normalized()
    cuff = Vector(hand) - d * 0.08
    R.rod(b, cuff - d * 0.03, cuff + d * 0.03, 0.082, 0.082, "off_white", segments=8)
    rot = Vector((0, 0, 1)).rotation_difference(d).to_euler("XYZ")
    rot = [math.degrees(a) for a in rot]
    b.box((0.12, 0.11, 0.13), tuple(Vector(hand) + d * 0.03), "skin", rot=rot, bevel=0.025)  # the fist
    b.box((0.05, 0.05, 0.07), tuple(Vector(hand) + d * 0.03 + Vector((-side * 0.07, 0, 0.02))), "skin", rot=rot,
          bevel=0.015)  # thumb
    return b.finish()


def _broom():
    b = C.Builder("Broom")
    grip = Vector(GRIP)
    up = Vector((0.55, 0.95, 0.75)).normalized()  # the handle runs up, right and away from the grip
    bottom = grip - up * 0.22
    top = grip + up * 0.85
    R.rod(b, bottom, top, 0.022, 0.022, "wood", segments=8)
    R.rod(b, bottom - up * 0.03, bottom, 0.026, 0.026, "alarm_red", segments=8)
    # Bristle head at the top end, flat across the view.
    rot = [math.degrees(a) for a in Vector((0, 0, 1)).rotation_difference(up).to_euler("XYZ")]
    b.box((0.06, 0.06, 0.08), tuple(top + up * 0.03), "brown_dark", rot=rot, bevel=0.01)
    b.box((0.3, 0.08, 0.06), tuple(top + up * 0.09), "alarm_red", rot=rot, bevel=0.01)
    b.box((0.34, 0.07, 0.2), tuple(top + up * 0.21), "safety_yellow", rot=rot, bevel=0.02)
    return b.finish()


def add_clips(anim):
    P = R.P

    def idle(f):
        w = R.wave(f, 90)
        return {"arm_r": P((1.5 * w, 0, 0.8 * w)), "arm_l": P((1.2 * R.wave(f, 90, 0.3), 0, 0)),
                "root": P((0, 0, 0), (0, 0, 0.004 * w))}
    anim.clip("idle", 90, idle, loop=True)

    wind = {"arm_r": P((38, 0, -18)), "broom": P((12, 0, 0))}
    hit = {"arm_r": P((-38, 0, 42)), "broom": P((-30, 0, 15)), "arm_l": P((-6, 0, 0))}
    anim.clip("swing", 11, R.keyed([(0, {}), (3, wind, "out"), (6, hit, "in"), (11, {}, "io")]))

    def interact(f):
        t = R.wave(f, 24)
        return {"arm_r": P((-14 + 4 * t, 0, 14), (0.0, 0.0, 0.03)), "broom": P((-40, 0, 0)),
                "arm_l": P((26 - 4 * t, 0, -22 + 10 * t), (0.08, 0.06, 0.12))}
    anim.clip("interact", 24, interact, loop=True)

    def carry(f):
        t = R.wave(f, 40)
        return {"arm_r": P((-24, 0, 6)), "broom": P((-20, 0, 0)),
                "arm_l": P((30 + 2 * t, 0, -40), (0.18, 0.12, 0.26 + 0.01 * t))}
    anim.clip("carry", 40, carry, loop=True)

    up = {"arm_l": P((22, 0, -42), (0.12, 0.14, 0.2)), "arm_r": P((-10, 0, 0))}
    bite = {"arm_l": P((26, 0, -42), (0.12, 0.1, 0.25)), "arm_r": P((-10, 0, 0))}
    anim.clip("eat", 36, R.keyed([(0, {}), (8, up, "out"), (13, bite), (18, up), (23, bite), (28, up),
                                  (36, {}, "io")]))
    reach = {"arm_r": P((-55, 0, -10), (0, 0.15, -0.1)), "broom": P((-20, 0, 0))}
    anim.clip("place", 18, R.keyed([(0, {}), (7, reach, "out"), (11, reach), (18, {}, "io")]))


def build():
    arm = R.make_armature("FpArms", BONES)
    right = _forearm("ArmR", ELBOW_R, GRIP, 1)
    left = _forearm("ArmL", ELBOW_L, HAND_L, -1)
    broom = _broom()
    R.skin_rigid(right, arm, "arm_r")
    R.skin_rigid(left, arm, "arm_l")
    R.skin_rigid(broom, arm, "broom")
    R.join([right, left, broom], "FpArms")
    anim = R.Animator(arm)
    add_clips(anim)
    anim.finish()
    return [arm]


def render_check(out_dir):
    """Renders the rest pose and key frames from the camera (vertical FOV 80 degrees, 16:9)."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("Eye")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(80)
    cam_data.clip_start = 0.05
    cam = bpy.data.objects.new("Eye", cam_data)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "TEXTURE"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = 640, 360
    arm = bpy.data.objects["FpArms"]
    shots = [("rest", None, 0), ("idle", "idle", 45), ("swing_wind", "swing", 3), ("swing_hit", "swing", 6),
             ("interact", "interact", 6), ("carry", "carry", 10), ("eat", "eat", 13), ("place", "place", 9)]
    for label, clip, frame in shots:
        arm.animation_data.action = bpy.data.actions[clip] if clip else None
        if clip and bpy.data.actions[clip].slots:
            arm.animation_data.action_slot = bpy.data.actions[clip].slots[0]
        if not clip:
            for pb in arm.pose.bones:
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.location = (0, 0, 0)
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out_dir, "fp_%s.png" % label)
        bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None


if __name__ == "__main__":
    a = C.args("fp_arms", lambda p: p.add_argument("--render"))
    C.reset()
    roots = build()
    if a.render:
        render_check(a.render)
    else:
        C.export(a.out, roots, animations=True)

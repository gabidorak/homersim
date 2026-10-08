"""First-person arms and broom for the local supervisor (only they see it, in front of the camera).

    blender -b -P tools/blender/fp_arms.py -- [--out PATH] [--render DIR]

The origin is the camera; it looks along +Y (Godot -Z) with +Z up, at an 80 degree vertical field
of view. Chunky Kenney-style forearms (white shirt cuffs, skin hands) and the broom in the right
hand. Bones: root, arm_r (elbow pivot, lower right), arm_l (elbow pivot, lower left), broom (child
of arm_r, at the grip), tablet (child of arm_l, at the CCTV tablet's centre). Clips: idle (loop),
swing, interact (loop), carry (loop), eat, place, and the CCTV tablet: tablet_out (both arms drop,
then the left hand brings the tablet up), tablet (loop, held up) and tablet_away.
The tablet is modelled where it is held up (camera space) as two separate meshes skinned to its bone,
so Godot can hide it while it is put away: Tablet (chunky grey frame, palette) and TabletScreen (a
quad with 0..1 UVs and its own "tablet_screen" material, which the game replaces with the camera
feed). Its bone carries the inverse of the left arm's hold pose, so it sits exactly at its modelled
place while held, and follows the hand rigidly on the way up and down.
--render DIR also renders each clip's key frames from the camera (framing check).
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import rat as R  # noqa: E402

ASSETS = [("fp_arms", {})]
ANIMATED = True

ELBOW_R = (0.46, 0.18, -0.6)
GRIP = (0.36, 0.5, -0.42)
ELBOW_L = (-0.46, 0.16, -0.66)
HAND_L = (-0.34, 0.44, -0.6)
# The CCTV tablet, held up: its centre, size (x wide, y deep, z tall), frame around the screen, and
# where the left fist ends up gripping its left edge, turned by HOLD_ROT_L (degrees, about the elbow).
TABLET = (0.03, 0.56, -0.07)
TABLET_SIZE = (0.86, 0.055, 0.65)
TABLET_CORNER = 0.08
TABLET_FRAME = 0.065
HOLD_GRIP_L = (-0.42, 0.5, -0.16)
HOLD_ROT_L = (38, 0, -22)
BONES = [("root", None, (0, 0, 0)), ("arm_r", "root", ELBOW_R), ("arm_l", "root", ELBOW_L),
         ("broom", "arm_r", GRIP), ("tablet", "arm_l", TABLET)]


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


def _rounded_rect(w, h, r, segments=6):
    """Counter-clockwise points of a w x h rectangle with corners of radius r, centred on 0."""
    pts = []
    for c, (sx, sy) in enumerate([(1, 1), (-1, 1), (-1, -1), (1, -1)]):
        cx, cy = sx * (w / 2 - r), sy * (h / 2 - r)
        for i in range(segments + 1):
            a = (c + i / segments) * math.pi / 2
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def _tablet():
    """The chunky cartoon tablet: a light grey rounded slab, a grey back, a black rim around the screen."""
    b = C.Builder("Tablet")
    w, d, h = TABLET_SIZE
    c = Vector(TABLET)
    # prism() extrudes along +Z from z = 0; turned +90 degrees about X, that runs towards -Y (the camera).
    b.prism(_rounded_rect(w, h, TABLET_CORNER), d, (c.x, c.y + d / 2, c.z), "grey_light", rot=(90, 0, 0))
    b.prism(_rounded_rect(w - 0.05, h - 0.05, TABLET_CORNER * 0.8), 0.02, (c.x, c.y + d / 2 + 0.015, c.z),
            "grey", rot=(90, 0, 0))
    sw, sh = w - 2 * TABLET_FRAME, h - 2 * TABLET_FRAME
    b.box((sw + 0.02, 0.006, sh + 0.02), (c.x, c.y - d / 2 - 0.002, c.z), "black")
    return b.finish()


def _tablet_screen():
    """The screen: one quad just in front of the black rim, UVs 0..1 (Blender's v = 1 at the top)."""
    w, d, h = TABLET_SIZE
    c = Vector(TABLET)
    sw, sh = w - 2 * TABLET_FRAME, h - 2 * TABLET_FRAME
    y = c.y - d / 2 - 0.0055
    me = bpy.data.meshes.new("TabletScreen")
    me.from_pydata([(c.x - sw / 2, y, c.z - sh / 2), (c.x + sw / 2, y, c.z - sh / 2),
                    (c.x + sw / 2, y, c.z + sh / 2), (c.x - sw / 2, y, c.z + sh / 2)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for loop, co in zip(me.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[loop.index].uv = co
    mat = bpy.data.materials.new("tablet_screen")
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.05, 0.08, 0.06, 1.0)
    me.materials.append(mat)
    obj = bpy.data.objects.new("TabletScreen", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _hold_poses():
    """The left arm's hold pose (fist on the tablet's left edge) and the tablet bone's pose that
    cancels it, so the tablet stays where it was modelled: with the arm turning q about its elbow E
    and moving by t, the tablet (head T) needs rotation q^-1 and location q^-1 (T - E - t) - (T - E)."""
    q = Euler([math.radians(a) for a in HOLD_ROT_L], "XYZ").to_quaternion()
    elbow, hand, centre = Vector(ELBOW_L), Vector(HAND_L), Vector(TABLET)
    t = Vector(HOLD_GRIP_L) - (elbow + q @ (hand - elbow))
    qi = q.inverted()
    u = qi @ (centre - elbow - t) - (centre - elbow)
    counter = R.P([math.degrees(a) for a in qi.to_euler("XYZ")], tuple(u))
    return R.P(HOLD_ROT_L, tuple(t)), counter


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

    # The CCTV tablet. The broom arm drops out of view; the left hand goes down and comes back up
    # with the tablet (Godot shows it from frame 3 of tablet_out and hides it from frame 4 of
    # tablet_away, while it is below the view).
    hold, counter = _hold_poses()
    rot, loc = hold[:3], hold[3:]
    broom_down = {"arm_r": P((-35, 0, 15), (0.12, -0.05, -0.8)), "broom": P((-25, 0, 0))}
    low = {"arm_l": P((rot[0] - 70, rot[1], rot[2] + 25), (loc[0] - 0.12, loc[1] - 0.1, loc[2] - 0.75)),
           "tablet": counter, **broom_down}
    over = {"arm_l": P((rot[0] + 5, rot[1], rot[2]), (loc[0], loc[1], loc[2] + 0.025)), "tablet": counter,
            **broom_down}
    held = {"arm_l": hold, "tablet": counter, **broom_down}
    anim.clip("tablet_out", 9, R.keyed([(0, {}), (3, low, "in"), (7, over, "out"), (9, held, "io")]))

    def tablet(f):
        w = R.wave(f, 60)
        return {"arm_l": P((rot[0] + 0.8 * w, rot[1], rot[2]), (loc[0], loc[1], loc[2] + 0.004 * w)),
                "tablet": counter, **broom_down}
    anim.clip("tablet", 60, tablet, loop=True)
    anim.clip("tablet_away", 9, R.keyed([(0, held), (4, low, "in"), (9, {}, "out")]))


def build():
    arm = R.make_armature("FpArms", BONES)
    right = _forearm("ArmR", ELBOW_R, GRIP, 1)
    left = _forearm("ArmL", ELBOW_L, HAND_L, -1)
    broom = _broom()
    R.skin_rigid(right, arm, "arm_r")
    R.skin_rigid(left, arm, "arm_l")
    R.skin_rigid(broom, arm, "broom")
    R.join([right, left, broom], "FpArms")
    R.skin_rigid(_tablet(), arm, "tablet")  # separate meshes: Godot hides them while put away
    R.skin_rigid(_tablet_screen(), arm, "tablet")
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
             ("interact", "interact", 6), ("carry", "carry", 10), ("eat", "eat", 13), ("place", "place", 9),
             ("tablet_out_3", "tablet_out", 3), ("tablet_out_6", "tablet_out", 6), ("tablet", "tablet", 0),
             ("tablet_away_6", "tablet_away", 6)]
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

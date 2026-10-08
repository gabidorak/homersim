"""The supervisor: Kenney's CC0 Mini Character "male-d" (suit and tie) recoloured onto the palette as
a plant shift supervisor (white shirt, red tie, navy trousers, boots, a yellow hard hat), scaled to
1.85 m, with his clips renamed to the game's names plus two new ones (get_up, eat).

    blender -b -P tools/blender/supervisor.py -- [--out PATH]

Source: assets/third_party/kenney_mini-characters/models/character-male-d.glb (CC0, see CREDITS.md).
Bones (Kenney's names): root, leg-left, leg-right, torso, arm-left, arm-right, head.
Meshes: "Supervisor" (body + head, skinned) and "HardHat" (rigid on the head bone, separate so the
lobby can tint it per player).
Clips: idle, walk, run, jump, fall (loops: idle walk run fall interact carry_idle sit), swing,
carry_idle, place, interact, knocked, get_up, eat, sit, emote, emote_no. For the intro cinematic
(client/intro/, add_intro_clips): carry_walk, trip, faceplant, cheer, startle, cower, ouch, chase, point.
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import rat as R  # noqa: E402  (rig helpers)
sys.path.insert(0, os.path.join(C.ROOT, "tools", "art"))
import palette as PAL  # noqa: E402

ASSETS = [("supervisor", {})]
ANIMATED = True

SOURCE = os.path.join(C.ROOT, "assets", "third_party", "kenney_mini-characters", "models", "character-male-d.glb")
HEIGHT = 1.85  # m, top of the hard hat
# Kenney clip -> game clip
RENAME = {"idle": "idle", "walk": "walk", "sprint": "run", "jump": "jump", "fall": "fall",
          "attack-melee-right": "swing", "holding-both": "carry_idle", "pick-up": "place", "interact-right": "interact",
          "die": "knocked", "sit": "sit", "emote-yes": "emote", "emote-no": "emote_no"}


# --- Blender 4.4+/5.0 slotted actions ---------------------------------------------------------------

def fcurves(act):
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


# --- Recolouring ------------------------------------------------------------------------------------------

def _sample(img, uv):
    w, h = img.size
    x = min(w - 1, max(0, int(uv[0] % 1.0 * w)))
    y = min(h - 1, max(0, int(uv[1] % 1.0 * h)))
    i = (y * w + x) * 4
    return tuple(img.pixels[i:i + 3])


def recolour(obj, img, rule):
    """Moves every face's UVs to the centre of its palette swatch and switches to the palette material.
    `rule(rgb, centre) -> name` picks the swatch (rgb = the source colour, centre = face centre, model
    space)."""
    me = obj.data
    uv = me.uv_layers.active.data
    counts = {}
    for p in me.polygons:
        u = sum((uv[li].uv for li in p.loop_indices), Vector((0, 0))) / p.loop_total
        rgb = _sample(img, u)
        name = rule(rgb, obj.matrix_world @ p.center)
        counts[(tuple(round(c, 2) for c in rgb), name)] = counts.get((tuple(round(c, 2) for c in rgb), name), 0) + 1
        su, sv = PAL.uv(name)
        for li in p.loop_indices:
            uv[li].uv = (su, 1.0 - sv)
        p.material_index = 0
    me.materials.clear()
    me.materials.append(C.materials()[0])
    for (rgb, name), n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print("  %-14s %-20s %d faces" % (name, rgb, n))


def body_rule(rgb, c):
    lum = 0.3 * rgb[0] + 0.59 * rgb[1] + 0.11 * rgb[2]
    r, g, b = rgb
    if r > 0.5 and g < 0.3 and b < 0.3:
        return "tie_red"
    if lum < 0.32:  # the dark suit: jacket and sleeves -> shirt, trousers -> navy, shoes -> boots
        if c.z < 0.07:
            return "boot_brown"
        if c.z < 0.19:
            return "pants_navy"
        return "shirt_white"
    if lum > 0.8:
        return "off_white"  # the shirt collar under the jacket
    near = PAL.nearest(rgb)
    return {"skin_dark": "skin", "brown": "skin", "wood": "skin", "beige_dark": "skin", "cardboard": "skin",
            "wood_light": "skin_light", "orange": "tie_red"}.get(near, near)


def head_rule(rgb, c):
    lum = 0.3 * rgb[0] + 0.59 * rgb[1] + 0.11 * rgb[2]
    if lum < 0.32:
        return "eye_black"
    near = PAL.nearest(rgb)
    if near in ("orange_dark", "brown", "orange", "wood", "cardboard", "dough"):
        return "brown" if c.z > 0.66 else "skin"  # hair on top, skin below
    return {"skin_dark": "skin", "beige_dark": "skin", "wood_light": "skin_light"}.get(near, near)


# --- Extra parts ------------------------------------------------------------------------------------------

def hard_hat(head_top, half):
    """A chunky hard hat over Kenney's cube head (unscaled units): a dome sitting on the brow line, a
    rim, a short peak at the front and a ridge on top."""
    import machines as M
    b = C.Builder("HardHat")
    r = half * 1.12
    z = head_top - 0.12  # the rim, just above the eyes
    M.lathe(b, [(r, 0.0), (r * 0.97, 0.07), (r * 0.86, 0.14), (r * 0.64, 0.2), (r * 0.34, 0.235), (0.01, 0.24)],
            "hardhat", seg=16, loc=(0, 0, z))
    b.torus(r, 0.016, (0, 0, z + 0.008), "yellow_dark", segments=16, sides=4)
    b.box((r * 1.1, r * 0.42, 0.018), (0, -r * 1.05, z + 0.01), "hardhat", rot=(-10, 0, 0), bevel=0.006)
    b.box((r * 0.26, r * 1.9, 0.04), (0, 0, z + 0.235), "yellow_dark", rot=(0, 0, 0), bevel=0.012)  # ridge
    b.box((0.07, 0.012, 0.045), (0, -r * 0.93, z + 0.1), "alarm_red", rot=(-35, 0, 0), bevel=0.004)  # badge
    return b.finish()


def chest_badge(torso_z):
    b = C.Builder("Badge")
    b.box((0.05, 0.012, 0.035), (0.06, -0.142, torso_z), "safety_yellow", bevel=0.003)
    b.box((0.035, 0.012, 0.05), (-0.065, -0.142, torso_z - 0.01), "sky", bevel=0.003)  # pocket protector
    b.box((0.006, 0.014, 0.03), (-0.072, -0.144, torso_z + 0.01), "alarm_red")
    b.box((0.006, 0.014, 0.03), (-0.058, -0.144, torso_z + 0.01), "blue")
    return b.finish()


# --- Clips ------------------------------------------------------------------------------------------------

def reversed_clip(src, name, stretch=1.0, hold=0):
    """A copy of `src` played backwards (and `stretch` times slower, after `hold` frames still)."""
    act = src.copy()
    act.name = name
    f0, f1 = src.frame_range
    for fc in fcurves(act):
        for kp in fc.keyframe_points:
            t = hold + (f1 - kp.co.x) * stretch
            kp.co.x = t
            kp.handle_left.x = t
            kp.handle_right.x = t
            kp.interpolation = "BEZIER"
        pts = sorted([(kp.co.x, kp.co.y) for kp in fc.keyframe_points])
        for kp, (x, y) in zip(fc.keyframe_points, pts):
            kp.co = (x, y)
            kp.handle_left = (x - 0.5, y)
            kp.handle_right = (x + 0.5, y)
        fc.update()
    act.frame_range = (0, hold + (f1 - f0) * stretch)
    act.use_fake_user = True
    return act


def to_mouth(t):
    """Right arm pose (model-axis Euler, degrees) bringing the hand from the side (t=0) to the mouth (1)."""
    down = Euler((0, math.radians(-45), 0), "XYZ").to_quaternion()
    mouth = (Euler((math.radians(-62), 0, 0), "XYZ").to_quaternion()
             @ Euler((0, 0, math.radians(96)), "XYZ").to_quaternion())
    q = down.slerp(mouth, t)
    return [math.degrees(a) for a in q.to_euler("XYZ")]


def add_clips(arm):
    anim = R.Animator(arm)
    idle_arms = {"arm-left": R.P((0, 45, 0)), "arm-right": R.P((0, -45, 0))}

    def eat(f):
        t = R.smooth(f / 8) if f < 8 else (1.0 if f < 28 else 1.0 - R.smooth((f - 28) / 8))
        chew = 0.35 * max(0.0, math.sin(math.pi * (f - 8) / 10)) if 8 <= f < 28 else 0.0
        pose = dict(idle_arms)
        pose["arm-right"] = R.P(to_mouth(max(0.0, t - chew)))
        pose["head"] = R.P((-6 * t + 4 * chew, 0, 0))
        return pose
    anim.clip("eat", 36, eat)
    add_intro_clips(anim, idle_arms)
    anim.finish()


def arms(rot, loc=(0, 0, 0)):
    """Both arms: the left one with this pose, the right one mirrored."""
    return {"arm-left": R.P(rot, loc), "arm-right": R.P((rot[0], -rot[1], -rot[2]), (-loc[0], loc[1], loc[2]))}


def add_intro_clips(anim, idle_arms):
    """The intro cinematic's clips (client/intro/): the old days, the spill, the chase. Arms rest
    straight out to the sides: +Y lowers the left arm, -Z swings it forward (mirrored on the right)."""
    # carry_walk: a jaunty stroll, holding something in front of the belly with both hands (0.8 s).
    def carry_walk(f):
        ph, step = R.wave(f, 24), abs(R.wave(f, 24, 0.25))
        return {"root": R.P(loc=(0, 0, 0.035 * step)),
                "leg-left": R.P((26 * ph, 0, 0)), "leg-right": R.P((-26 * ph, 0, 0)),
                "torso": R.P((-3, 3 * ph, 2 * ph)), "head": R.P((-2 + 3 * R.wave(f, 12), 0, 5 * R.wave(f, 24, 0.1))),
                **arms((0, 15 + 4 * step, -62))}
    anim.clip("carry_walk", 24, carry_walk, loop=True)

    # trip: the toe catches, he flies forward, arms flung out (whatever he held is gone), and lands
    # flat on his belly (1.2 s); faceplant then holds that, legs twitching.
    down = {"root": R.P((90, 0, 0), (0, -0.5, 0.2)), "torso": R.P(), "head": R.P((-15, 0, 0)),
            "leg-left": R.P((30, 0, 0)), "leg-right": R.P((20, 0, 0)), **arms((0, -95, -10))}
    trip = R.keyed([
        (0, dict(carry_walk(6)), "lin"),
        (5, {"root": R.P((25, 0, 0), (0, -0.12, 0.05)), "torso": R.P((10, 0, 0)), "head": R.P((-20, 0, 0)),
             "leg-left": R.P((55, 0, 0)), "leg-right": R.P((-35, 0, 0)), **arms((0, -35, -85))}, "out"),
        (11, {"root": R.P((70, 0, 0), (0, -0.32, 0.42)), "torso": R.P((5, 0, 0)), "head": R.P((-35, 0, 0)),
              "leg-left": R.P((35, 0, 0)), "leg-right": R.P((50, 0, 0)), **arms((0, -75, -60))}, "out"),
        (17, {"root": R.P((90, 0, 0), (0, -0.46, 0.2)), "head": R.P((-20, 0, 0)), "leg-left": R.P((70, 0, 0)),
              "leg-right": R.P((55, 0, 0)), **arms((0, -95, -10))}, "in"),
        (21, {"root": R.P((86, 0, 0), (0, -0.5, 0.27)), "head": R.P((-28, 0, 0)), "leg-left": R.P((80, 0, 0)),
              "leg-right": R.P((75, 0, 0)), **arms((0, -100, -15))}, "out"),
        (27, dict(down, head=R.P((-22, 0, 0)), **{"leg-left": R.P((40, 0, 0))}), "in"),
        (36, down, "io")])
    anim.clip("trip", 36, trip)

    def faceplant(f):
        kick = R.bump(f, 6, 18) + 0.6 * R.bump(f, 24, 34)
        return dict(down, head=R.P((-15 + 6 * R.bump(f, 14, 40), 0, 8 * R.wave(f, 40))),
                    **{"leg-left": R.P((30 + 40 * kick, 0, 0)), "leg-right": R.P((20 + 25 * R.bump(f, 12, 26), 0, 0))})
    anim.clip("faceplant", 40, faceplant, loop=True)

    # cheer: arms up, bouncing with laughter (upper body: the intro plays it over sit) (0.67 s).
    def cheer(f):
        w = R.wave(f, 10)
        return {"torso": R.P((-6 + 4 * w, 0, 3 * R.wave(f, 20))), "head": R.P((-14 + 6 * w, 0, 6 * R.wave(f, 20, 0.3))),
                **arms((0, -62 + 14 * R.wave(f, 10, 0.25), -18))}
    anim.clip("cheer", 20, cheer, loop=True)

    # startle: jump back with the arms flung up, then cower (0.53 s); cower trembles there.
    cower_pose = {"root": R.P((-6, 0, 0), (0, 0.18, -0.05)), "torso": R.P((10, 0, 0)), "head": R.P((12, 0, 0)),
                  "leg-left": R.P((-12, 0, 0)), "leg-right": R.P((10, 0, 0)), **arms((0, -45, -70))}
    startle = R.keyed([
        (0, dict(idle_arms)),
        (3, {"root": R.P(loc=(0, 0, -0.06)), "torso": R.P((12, 0, 0)), "head": R.P((8, 0, 0)),
             "leg-left": R.P((-15, 0, 0)), "leg-right": R.P((-15, 0, 0)), **arms((0, 60, -10))}, "out"),
        (8, {"root": R.P((-14, 0, 0), (0, 0.12, 0.2)), "torso": R.P((-10, 0, 0)), "head": R.P((-18, 0, 0)),
             "leg-left": R.P((-30, 0, 0)), "leg-right": R.P((25, 0, 0)), **arms((0, -95, 15))}, "out"),
        (16, cower_pose, "io")])
    anim.clip("startle", 16, startle)

    def cower(f):
        j = R.wave(f, 4)
        p = dict(cower_pose)
        p.update(arms((0, -45 + 3 * j, -70 + 4 * R.wave(f, 4, 0.25))))
        p["root"] = R.P((-6, 0, 0), (0.008 * j, 0.18, -0.05))
        p["head"] = R.P((12 + 3 * R.wave(f, 8), 3 * j, 0))
        return p
    anim.clip("cower", 8, cower, loop=True)

    # ouch: bitten! Hopping on one leg, shaking the hand (0.6 s).
    def ouch(f):
        hop = abs(R.wave(f, 18))
        return {"root": R.P((0, 0, 8 * R.wave(f, 18, 0.25)), (0, 0, 0.08 * hop)),
                "leg-left": R.P((-10 * hop, 0, 0)), "leg-right": R.P((55, 0, 0)),
                "torso": R.P((-6, 4 * R.wave(f, 9), 0)), "head": R.P((-16, 0, 10 * R.wave(f, 9))),
                "arm-right": R.P((0, 70 + 12 * R.wave(f, 3), 40 + 20 * R.wave(f, 6))),
                "arm-left": R.P((0, 30 + 25 * R.wave(f, 9), -10))}
    anim.clip("ouch", 18, ouch, loop=True)

    # chase: running flat out, the broom raised overhead in both hands (0.47 s).
    def chase(f):
        ph = R.wave(f, 14)
        return {"root": R.P(loc=(0, 0, 0.05 * abs(R.wave(f, 14, 0.25)))),
                "leg-left": R.P((42 * ph, 0, 0)), "leg-right": R.P((-42 * ph, 0, 0)),
                "torso": R.P((14, 0, 4 * ph)), "head": R.P((-12, 0, -3 * ph)),
                **arms((0, -100 + 10 * R.wave(f, 7), -30))}
    anim.clip("chase", 14, chase, loop=True)

    # point: "There!" The right arm shoots forward and stays (0.4 s).
    aim = dict(idle_arms, **{"arm-right": R.P((0, 18, 92)), "arm-left": R.P((0, 50, -15)),
                             "torso": R.P((4, 0, -8)), "head": R.P((-6, 0, -4))})
    shake = dict(aim, **{"arm-right": R.P((0, 24, 88))})
    anim.clip("point", 12, R.keyed([(0, dict(idle_arms)), (4, aim, "out"), (7, shake), (12, aim, "io")]))


def load_source():
    """Kenney's model, imported: (armature, body mesh, head mesh, the texture its colours come from)."""
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    for o in list(bpy.data.objects):
        if o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.name = arm.data.name = "Armature"
    img = next(i for i in bpy.data.images if i.size[0] > 0)
    return arm, bpy.data.objects["body-mesh"], bpy.data.objects["head-mesh"], img


def top(obj):
    return max((obj.matrix_world @ Vector(c)).z for c in obj.bound_box)


def finish(arm, s):
    """Scales everything (armature, meshes, root motion) by `s` to the game's size, keeps and renames
    Kenney's useful clips, adds ours and stores the outline normals."""
    arm.scale = (s, s, s)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [arm] + list(arm.children):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # Clips: keep and rename the useful ones, scale their root motion, then add ours.
    for act in list(bpy.data.actions):
        if act.name not in RENAME:
            bpy.data.actions.remove(act)
            continue
        act.name = RENAME[act.name]
        act.use_fake_user = True
        for fc in fcurves(act):
            if fc.data_path.endswith(".location"):
                for kp in fc.keyframe_points:
                    kp.co.y *= s
                    kp.handle_left.y *= s
                    kp.handle_right.y *= s
    reversed_clip(bpy.data.actions["knocked"], "get_up", stretch=3.0)
    add_clips(arm)
    for o in arm.children:
        if o.type == "MESH":
            C.store_outline_normals(o)
    arm.animation_data.action = None
    for name in sorted(a.name for a in bpy.data.actions):
        a = bpy.data.actions[name]
        print("  clip %-11s frames %5.1f..%5.1f" % (name, *a.frame_range))


def build():
    arm, body, head, img = load_source()
    print("recolour body:")
    recolour(body, img, body_rule)
    print("recolour head:")
    recolour(head, img, head_rule)
    # Hat and badge (unscaled Kenney units: the head is a ~0.45 m cube on top of a 0.34 m body).
    head_top = top(head)
    hat = hard_hat(head_top, 0.235)
    R.skin_rigid(hat, arm, "head")
    badge = chest_badge(0.27)
    R.skin_rigid(badge, arm, "torso")
    R.join([body, badge, head], "Supervisor")
    finish(arm, HEIGHT / top(hat))
    return [arm]


if __name__ == "__main__":
    a = C.args("supervisor")
    C.reset()
    C.export(a.out, build(), animations=True)

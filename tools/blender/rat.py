"""The rat: a chunky cartoon rat in the Kenney mini-characters style, rigged and animated.

    blender -b -P tools/blender/rat.py -- [--out PATH]

Standing on its hind legs, slightly hunched, facing -Y (Godot +Z), feet on the origin. About 0.5 m to
the ear tips, 0.4 m wide, 0.55 m nose to rump plus a 0.5 m tail. One skinned mesh, every part
weighted 100 % to one bone.

The first half of this file holds small rig helpers that supervisor.py and fp_arms.py import too
(common.py stays prop-only): make_armature(), skin_rigid(), join(), and Animator, which writes
clips from pose functions.

Pose convention used by every clip: a pose maps bone name -> [rx, ry, rz, lx, ly, lz], i.e. an
Euler rotation in degrees (X, then Y, then Z) about the model axes (Blender: X = the character's
left, -Y = forward, Z = up) relative to the parent bone, plus an offset in metres along those axes.
All bones are made pointing +Z with roll 0, so their rest frames are axis-aligned: in Godot
every bone's rest rotation is identity and its local axes are the model axes (x left, y up, z
forward), which keeps BoneAttachment3D offsets and code-driven bone rotations simple.
Rotation cheat sheet (Blender axes): +X tips the top forward (a bow, a nod, a leg swinging back),
+Z turns towards the character's left, +Y lowers a left arm held out sideways (raises a right one).
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

ASSETS = [("rat", {})]
ANIMATED = True


# --- Rig helpers (shared with supervisor.py and fp_arms.py) --------------------------------------

def make_armature(name, bones, length=0.05):
    """bones: [(name, parent name or None, head (x, y, z)), ...] in order (parents first). Every bone
    points +Z with roll 0 (axis-aligned rest frame, see the module docstring)."""
    data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, parent, head in bones:
        eb = data.edit_bones.new(bname)
        eb.head = Vector(head)
        eb.tail = Vector(head) + Vector((0, 0, length))
        eb.roll = 0.0
        if parent:
            eb.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def skin_rigid(obj, arm, bone):
    """Weights every vertex of `obj` 100 % to `bone` and parents it to the armature (no move)."""
    vg = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    vg.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        obj.modifiers.new("Armature", "ARMATURE").object = arm
    world = obj.matrix_world.copy()
    obj.parent = arm
    obj.matrix_world = world
    return obj


def join(objs, name):
    """Joins meshes into the first one (vertex groups merge by name) and keeps only used materials."""
    target = objs[0]
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=target, object=target, selected_objects=objs,
                                       selected_editable_objects=objs):
            bpy.ops.object.join()
    target.name = target.data.name = name
    me = target.data
    used = sorted({p.material_index for p in me.polygons})
    mats = [me.materials[i] for i in used]
    remap = {old: new for new, old in enumerate(used)}
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", idx)
    return target


def lerp(a, b, t):
    return a + (b - a) * t


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def wave(f, period, phase=0.0):
    """sin over `period` frames, phase in cycles (0..1)."""
    return math.sin(2 * math.pi * (f / period + phase))


def add(*poses):
    """Sums poses (bone -> 6 floats)."""
    out = {}
    for p in poses:
        for bone, v in p.items():
            o = out.setdefault(bone, [0.0] * 6)
            for i, x in enumerate(v):
                o[i] += x
    return out


def P(rot=(0, 0, 0), loc=(0, 0, 0)):
    """One bone's pose entry."""
    return [*rot, *loc]


def keyed(keys, loop=False):
    """A pose function interpolating key poses: keys = [(frame, {bone: P(...)}, mode), ...] with mode
    (optional, for the segment ending at that key): "cr" (default: smooth Catmull-Rom through the
    keys), "lin", "in" (accelerate), "out" (decelerate), "io" (ease in-out, stops at both keys).
    Bones missing from a key are at rest there. With loop, the first and last key must match."""
    keys = [(k[0], k[1], k[2] if len(k) > 2 else "cr") for k in keys]
    bones = sorted({b for _, pose, _ in keys for b in pose})
    frames = [k[0] for k in keys]
    vals = [[k[1].get(b, [0.0] * 6) for b in bones] for k in keys]
    n = len(keys)

    def tangent(i, bi, c):
        if loop and (i == 0 or i == n - 1):
            span = (frames[-1] - frames[-2]) + (frames[1] - frames[0])
            return (vals[1][bi][c] - vals[-2][bi][c]) / span
        if i == 0 or i == n - 1:
            return 0.0
        return (vals[i + 1][bi][c] - vals[i - 1][bi][c]) / (frames[i + 1] - frames[i - 1])

    def fn(f):
        if f <= frames[0]:
            i, t = 0, 0.0
        elif f >= frames[-1]:
            i, t = n - 2, 1.0
        else:
            i = max(j for j in range(n - 1) if frames[j] <= f)
            t = (f - frames[i]) / (frames[i + 1] - frames[i])
        mode = keys[i + 1][2]
        dt = frames[i + 1] - frames[i]
        out = {}
        for bi, b in enumerate(bones):
            v0, v1 = vals[i][bi], vals[i + 1][bi]
            res = []
            for c in range(6):
                if mode == "cr":
                    m0, m1 = tangent(i, bi, c) * dt, tangent(i + 1, bi, c) * dt
                    t2, t3 = t * t, t * t * t
                    res.append((2 * t3 - 3 * t2 + 1) * v0[c] + (t3 - 2 * t2 + t) * m0
                               + (-2 * t3 + 3 * t2) * v1[c] + (t3 - t2) * m1)
                else:
                    e = {"lin": t, "in": t * t, "out": 1 - (1 - t) ** 2, "io": smooth(t)}[mode]
                    res.append(lerp(v0[c], v1[c], e))
            out[b] = res
        return out
    return fn


class Animator:
    """Writes actions on an armature from pose functions (see the module docstring), one key per
    frame for every bone (rotation + location), linear interpolation. Clips start at frame 0."""

    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}
        arm.animation_data_create()
        self.clips = []

    def clip(self, name, frames, pose_fn, loop=False):
        arm = self.arm
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        samples = {b: [] for b in self.rest}
        for f in range(frames + 1):
            pose = pose_fn(0 if (loop and f == frames) else f)
            for b, r in self.rest.items():
                v = pose.get(b, [0.0] * 6)
                qw = Euler([math.radians(a) for a in v[:3]], "XYZ").to_quaternion()
                ql = r.inverted() @ qw @ r
                prev = samples[b][-1][0] if samples[b] else None
                if prev is not None and prev.dot(ql) < 0:
                    ql.negate()
                samples[b].append((ql, r.inverted() @ Vector(v[3:])))
        for b, keys in samples.items():
            for prop, size in (("rotation_quaternion", 4), ("location", 3)):
                for i in range(size):
                    fc = act.fcurve_ensure_for_datablock(arm, 'pose.bones["%s"].%s' % (b, prop), index=i,
                                                         group_name=b)
                    co = []
                    for f, (ql, lv) in enumerate(keys):
                        co += [f, (ql if size == 4 else lv)[i]]
                    fc.keyframe_points.add(len(keys))
                    fc.keyframe_points.foreach_set("co", co)
                    for kp in fc.keyframe_points:
                        kp.interpolation = "LINEAR"
                    fc.update()
        act.use_frame_range = True
        act.frame_start, act.frame_end = 0, frames
        act.use_cyclic = loop
        arm.animation_data.action = None
        self.clips.append((name, frames, loop))
        return act

    def finish(self):
        """Back to the rest pose with no action assigned (the export bind pose)."""
        self.arm.animation_data.action = None
        for pb in self.arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
        for name, frames, loop in self.clips:
            print("  clip %-10s %3d frames %.2f s %s" % (name, frames, frames / 30.0, "loop" if loop else "once"))


# --- Modelling helpers ------------------------------------------------------------------------------

def taper(b, before, axis, lo, hi, s_lo, s_hi, centre=(0, 0, 0)):
    """Scales the vertices added to builder `b` since `before` (a set of verts) across `axis`
    (0/1/2): by s_lo (x, y, z factors) at coordinate lo, s_hi at hi, about `centre`."""
    for v in b.bm.verts:
        if v in before:
            continue
        t = min(max((v.co[axis] - lo) / (hi - lo), 0.0), 1.0)
        for k in range(3):
            if k != axis:
                f = lerp(s_lo[k], s_hi[k], t)
                v.co[k] = centre[k] + (v.co[k] - centre[k]) * f


def rod(b, p0, p1, r0, r1, color, segments=8):
    """A (tapered) cylinder from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler("XYZ")
    b.cylinder(r0, d.length, p0, color, rot=[math.degrees(a) for a in rot], segments=segments,
               radius_top=r1, base=True)


# --- The rat ------------------------------------------------------------------------------------

BONES = [
    ("root", None, (0, 0, 0)),
    ("body", "root", (0, 0.03, 0.13)),
    ("head", "body", (0, -0.05, 0.31)),
    ("jaw", "head", (0, -0.19, 0.275)),
    ("ear_l", "head", (0.10, -0.06, 0.40)),
    ("ear_r", "head", (-0.10, -0.06, 0.40)),
    ("arm_l", "body", (0.105, -0.07, 0.28)),
    ("arm_r", "body", (-0.105, -0.07, 0.28)),
    ("leg_l", "root", (0.075, 0.03, 0.12)),
    ("leg_r", "root", (-0.075, 0.03, 0.12)),
    ("tail_1", "body", (0, 0.13, 0.11)),
    ("tail_2", "tail_1", (0, 0.24, 0.06)),
    ("tail_3", "tail_2", (0, 0.36, 0.05)),
    ("tail_4", "tail_3", (0, 0.465, 0.085)),
]
TAIL_END = (0, 0.54, 0.17)
BONE_HEAD = {n: Vector(h) for n, _, h in BONES}
SCRUFF = Vector((0, 0.04, 0.33))  # back of the neck, where a supervisor grabs the rat


def _body(name):
    b = C.Builder(name)
    # Pear-shaped torso, tilted forward a little: narrow shoulders, wide hips.
    before = set(b.bm.verts)
    b.box((0.27, 0.23, 0.24), (0, 0.01, 0.235), "rat_grey", rot=(14, 0, 0), bevel=0.05)
    taper(b, before, 2, 0.12, 0.35, (1.05, 1.08, 1), (0.8, 0.85, 1))
    before = set(b.bm.verts)
    b.box((0.19, 0.04, 0.17), (0, -0.098, 0.205), "rat_grey_light", rot=(14, 0, 0), bevel=0.03)
    taper(b, before, 2, 0.12, 0.29, (1.05, 1, 1), (0.8, 1, 1))
    return b.finish()


def _head(name):
    b = C.Builder(name)
    # Big boxy skull, wider at the back (cheeks).
    before = set(b.bm.verts)
    b.box((0.29, 0.24, 0.2), (0, -0.09, 0.355), "rat_grey", bevel=0.055)
    taper(b, before, 1, -0.21, 0.03, (0.9, 1, 0.92), (1.0, 1, 1.0), centre=(0, 0, 0.35))
    # Pointy muzzle: a box tapering to the nose.
    before = set(b.bm.verts)
    b.box((0.17, 0.17, 0.12), (0, -0.265, 0.315), "rat_grey_light", bevel=0.04)
    taper(b, before, 1, -0.35, -0.18, (0.62, 1, 0.72), (1, 1, 1), centre=(0, 0, 0.30))
    # Dark mouth roof, just under the muzzle: hidden by the jaw until it opens.
    b.box((0.06, 0.08, 0.01), (0, -0.26, 0.27), "red_dark")
    b.sphere(0.034, (0, -0.352, 0.33), "rat_pink_dark", scale=(1.15, 0.9, 0.9), segments=8, rings=6)
    # Buck teeth hanging from the front of the muzzle.
    for x in (-0.016, 0.016):
        b.box((0.026, 0.016, 0.046), (x, -0.333, 0.256), "tooth", bevel=0.005)
    # Shiny black eyes with a white glint, and cheeky eyebrows.
    for s in (-1, 1):
        b.sphere(0.036, (s * 0.07, -0.205, 0.39), "eye_black", scale=(0.9, 0.55, 1.15), segments=10, rings=6)
        b.sphere(0.011, (s * 0.06 + 0.004, -0.224, 0.405), "eye_shine", segments=6, rings=4)
        b.box((0.065, 0.025, 0.02), (s * 0.075, -0.205, 0.44), "rat_grey_dark", rot=(0, s * 14, 0), bevel=0.006)
    # Tuft of fur on top.
    b.box((0.05, 0.08, 0.05), (0, -0.07, 0.465), "rat_grey_dark", rot=(20, 0, 0), bevel=0.015)
    b.box((0.04, 0.06, 0.04), (0.035, -0.04, 0.46), "rat_grey_dark", rot=(10, -25, 0), bevel=0.012)
    # Whiskers.
    for s in (-1, 1):
        for k, dz in enumerate((0.012, -0.012)):
            b.box((0.07, 0.008, 0.008), (s * 0.095, -0.31, 0.31 + dz), "rat_grey_dark",
                  rot=(0, s * (8 - 16 * k), s * -10))
    return b.finish()


def _jaw(name):
    b = C.Builder(name)
    before = set(b.bm.verts)
    b.box((0.12, 0.14, 0.045), (0, -0.265, 0.2525), "rat_grey_light", bevel=0.015)
    taper(b, before, 1, -0.34, -0.2, (0.7, 1, 1), (1, 1, 1))
    for x in (-0.012, 0.012):
        b.box((0.02, 0.012, 0.025), (x, -0.322, 0.272), "tooth", bevel=0.004)
    return b.finish()


def _ear(name, s):
    b = C.Builder(name)
    c = (s * 0.128, -0.055, 0.428)
    b.cylinder(0.072, 0.03, c, "rat_grey", rot=(90, 0, s * -18), segments=14, bevel=0.01)
    inner = Vector(c) + Vector((s * -0.003, -0.016, -0.004))
    b.cylinder(0.05, 0.012, inner, "rat_pink", rot=(90, 0, s * -18), segments=12)
    return b.finish()


def _arm(name, s):
    b = C.Builder(name)
    b.box((0.065, 0.065, 0.12), (s * 0.12, -0.105, 0.235), "rat_grey", rot=(32, 0, s * -8), bevel=0.02)
    b.box((0.06, 0.06, 0.055), (s * 0.125, -0.145, 0.175), "rat_pink", rot=(32, 0, 0), bevel=0.02)
    return b.finish()


def _leg(name, s):
    b = C.Builder(name)
    b.box((0.1, 0.14, 0.13), (s * 0.085, 0.03, 0.095), "rat_grey", bevel=0.035)
    b.box((0.075, 0.15, 0.036), (s * 0.08, -0.04, 0.0), "rat_pink", base=True, bevel=0.014)
    # Little toes.
    for k in (-1, 0, 1):
        b.box((0.022, 0.03, 0.03), (s * 0.08 + k * 0.024, -0.118, 0.0), "rat_pink_dark", base=True, bevel=0.008)
    return b.finish()


def _tail_segment(name, i):
    names = [n for n, _, _ in BONES if n.startswith("tail")]
    p0 = BONE_HEAD[names[i]]
    p1 = BONE_HEAD[names[i + 1]] if i + 1 < len(names) else Vector(TAIL_END)
    r = [0.03, 0.024, 0.019, 0.014, 0.009]
    b = C.Builder(name)
    rod(b, p0, p1, r[i], r[i + 1], "rat_pink", segments=8)
    b.sphere(r[i] * 1.12, p0, "rat_pink_dark", segments=8, rings=5)
    if i == len(names) - 1:
        b.sphere(r[i + 1] * 1.3, p1, "rat_pink", segments=6, rings=4)
    return b.finish()


def build_model():
    arm = make_armature("Armature", BONES)
    parts = [(_body("body"), "body"), (_head("head"), "head"), (_jaw("jaw"), "jaw"),
             (_ear("ear_l", 1), "ear_l"), (_ear("ear_r", -1), "ear_r"),
             (_arm("arm_l", 1), "arm_l"), (_arm("arm_r", -1), "arm_r"),
             (_leg("leg_l", 1), "leg_l"), (_leg("leg_r", -1), "leg_r")]
    parts += [(_tail_segment("tail_%d" % (i + 1), i), "tail_%d" % (i + 1)) for i in range(4)]
    for obj, bone in parts:
        skin_rigid(obj, arm, bone)
    join([o for o, _ in parts], "Rat")
    return arm


def build():
    arm = build_model()
    anim = Animator(arm)
    add_clips(anim)
    anim.finish()
    return [arm]


def bump(f, a, b):
    """0 outside [a, b], a smooth hump inside."""
    if f <= a or f >= b:
        return 0.0
    return math.sin(math.pi * (f - a) / (b - a)) ** 2


def pair(part, rot=(0, 0, 0), loc=(0, 0, 0)):
    """The left bone with this pose and the right one mirrored (part: "arm", "leg", "ear")."""
    return {part + "_l": P(rot, loc),
            part + "_r": P((rot[0], -rot[1], -rot[2]), (-loc[0], loc[1], loc[2]))}


def tail_wave(f, period, amp_z=0.0, amp_x=0.0, lag=0.12, base_x=(0, 0, 0, 0), base_z=(0, 0, 0, 0)):
    """A wave running down the tail (each segment adds to its parent's bend)."""
    return {"tail_%d" % (k + 1): P((base_x[k] + amp_x * wave(f, period, -k * lag), 0,
                                    base_z[k] + amp_z * wave(f, period, -k * lag))) for k in range(4)}


def _euler_q(r):
    return Euler([math.radians(a) for a in r], "XYZ").to_quaternion()


def add_clips(anim):
    # idle: breathing, a sniff, ear twitches, hands rubbing, tail sway (2 s).
    def idle(f):
        breath, sniff, rub = wave(f, 60), bump(f, 6, 28), bump(f, 30, 58)
        p = {"body": P((1.5 * breath, 0, 0)),
             "head": P((-1.5 * breath + 4 * sniff * wave(f, 5), 3 * wave(f, 60, 0.25), 0)),
             "jaw": P((4 * sniff * max(0.0, wave(f, 5, 0.25)), 0, 0)),
             "ear_l": P((0, 28 * bump(f, 40, 47), 0)),
             "ear_r": P((-6 * bump(f, 14, 20), -20 * bump(f, 14, 20), 0)),
             "arm_l": P((-38 + 7 * rub * wave(f, 10), 0, -16)),
             "arm_r": P((-38 - 7 * rub * wave(f, 10), 0, 16))}
        return add(p, tail_wave(f, 60, amp_z=7, amp_x=2, lag=0.1, base_x=(-4, 5, 7, 9)))
    anim.clip("idle", 60, idle, loop=True)

    # run: an energetic forward-leaning scamper (0.47 s cycle).
    def run(f):
        ph = wave(f, 14)
        p = {"root": P(loc=(0, 0, 0.035 * abs(ph))),
             "body": P((40 + 4 * wave(f, 7, 0.25), 0, 6 * ph)),
             "head": P((-32 - 4 * wave(f, 7, 0.25), 0, -5 * ph)),
             "jaw": P((10 + 6 * wave(f, 7), 0, 0)),
             "leg_l": P((55 * ph, 0, 0)), "leg_r": P((-55 * ph, 0, 0)),
             "arm_l": P((-55 - 45 * ph, 0, -6)), "arm_r": P((-55 + 45 * ph, 0, 6))}
        p.update(pair("ear", (-32 + 8 * wave(f, 7), 8, 0)))
        return add(p, tail_wave(f, 14, amp_z=10, amp_x=5, lag=0.15, base_x=(-36, 5, 6, 6)))
    anim.clip("run", 14, run, loop=True)

    # jump: stretch up off the ground, then tuck (0.4 s, holds the tuck).
    stretch = {"body": P((-12, 0, 0)), "head": P((-12, 0, 0)), "jaw": P((10, 0, 0)),
               **pair("arm", (-150, -25, 0)), **pair("leg", (35, 0, 0)), **pair("ear", (-25, 10, 0)),
               "tail_1": P((20, 0, 0)), "tail_2": P((8, 0, 0))}
    tuck = {"root": P(loc=(0, 0, 0.03)), "body": P((10, 0, 0)), "head": P((-6, 0, 0)), "jaw": P((14, 0, 0)),
            **pair("arm", (-100, -40, 0)), **pair("leg", (-50, 0, 0)), **pair("ear", (-5, 25, 0)),
            "tail_1": P((10, 0, 0)), "tail_2": P((25, 0, 0)), "tail_3": P((25, 0, 0)), "tail_4": P((25, 0, 0))}
    anim.clip("jump", 12, keyed([(0, {}), (3, stretch, "out"), (12, tuck, "io")]))

    # fall: flailing arms and legs, ears up, mouth open (0.53 s loop).
    def fall(f):
        w, w4 = wave(f, 8), wave(f, 8, 0.25)
        p = {"body": P((-10 + 3 * wave(f, 16), 0, 0)), "head": P((-15, 0, 0)),
             "jaw": P((24 + 6 * wave(f, 4), 0, 0)),
             "arm_l": P((-150 + 20 * w, -35 + 10 * w4, 0)), "arm_r": P((-150 - 20 * w, 35 - 10 * w4, 0)),
             "leg_l": P((-25 + 30 * w, 0, 0)), "leg_r": P((-25 - 30 * w, 0, 0)),
             "ear_l": P((-10, 35 + 15 * w, 0)), "ear_r": P((-10, -35 - 15 * w, 0))}
        return add(p, tail_wave(f, 16, amp_z=12, amp_x=8, lag=0.15, base_x=(25, 15, 15, 10)))
    anim.clip("fall", 16, fall, loop=True)

    # crawl: on all fours for the vents, diagonal gait, ears flat (0.6 s loop, < 0.45 m high).
    def crawl(f):
        ph = wave(f, 18)
        p = {"root": P(loc=(0, 0, 0.012 * abs(ph))),
             "body": P((66 + 2 * wave(f, 9), 0, 6 * ph)),
             "head": P((-60 - 2 * wave(f, 9), 0, -6 * ph)),
             "arm_l": P((-50 + 35 * ph, 0, 0)), "arm_r": P((-50 - 35 * ph, 0, 0)),
             "leg_l": P((25 - 30 * ph, 0, 0)), "leg_r": P((25 + 30 * ph, 0, 0))}
        p.update(pair("ear", (-40, 12, 0)))
        return add(p, tail_wave(f, 18, amp_z=10, amp_x=3, lag=0.15, base_x=(-68, 4, 4, 4)))
    anim.clip("crawl", 18, crawl, loop=True)

    # bite: rear back with the mouth open, lunge, CHOMP, recover (0.37 s).
    rear = {"root": P(loc=(0, 0.02, 0)), "body": P((-10, 0, 0)), "head": P((-20, 0, 0)), "jaw": P((38, 0, 0)),
            **pair("arm", (-40, 0, 0)), **pair("ear", (-15, 0, 0)), "tail_1": P((15, 0, 0))}
    lunge = {"root": P(loc=(0, -0.13, 0)), "body": P((32, 0, 0)), "head": P((-10, 0, 0)), "jaw": P((40, 0, 0)),
             **pair("arm", (-95, 0, 0)), **pair("ear", (-30, 0, 0)), "leg_l": P((-20, 0, 0)),
             "leg_r": P((30, 0, 0)), "tail_1": P((5, 0, 0)), "tail_2": P((15, 0, 0))}
    chomp = dict(lunge, jaw=P((-2, 0, 0)), head=P((-4, 0, 0)))
    anim.clip("bite", 11, keyed([(0, {}), (3, rear, "out"), (6, lunge, "in"), (7, chomp, "lin"),
                                 (8, chomp, "lin"), (11, {}, "io")]))

    # gnaw: hands up at the mouth, jaw chattering, tugging at the wires (0.6 s loop).
    def gnaw(f):
        tug = wave(f, 18)
        p = {"body": P((16 + 3 * tug, 0, 0)), "head": P((6 + 5 * tug, 0, 6 * wave(f, 9))),
             "jaw": P((14 + 14 * wave(f, 6), 0, 0)),
             "arm_l": P((-92 + 6 * tug, 0, -26)), "arm_r": P((-92 + 6 * tug, 0, 26))}
        p.update(pair("ear", (5 * wave(f, 6), 10, 0)))
        return add(p, tail_wave(f, 18, amp_z=10, lag=0.12, base_x=(-8, 5, 5, 5)))
    anim.clip("gnaw", 18, gnaw, loop=True)

    # stunned: sitting, dizzy wobble, head circling, droopy ears (1.2 s loop).
    def stunned(f):
        a, b = wave(f, 36), wave(f, 36, 0.25)
        p = {"root": P(loc=(0, 0, -0.065)),
             "body": P((4 + 6 * b, 9 * a, 0)), "head": P((-2 + 12 * b, 14 * a, 6 * a)),
             "jaw": P((18, 0, 0)),
             "leg_l": P((-78, 0, 12)), "leg_r": P((-78, 0, -12)),
             "ear_l": P((10, 55 + 8 * a, 0)), "ear_r": P((10, -55 + 8 * a, 0))}
        p.update(pair("arm", (15, -25 + 5 * a, 0)))
        return add(p, tail_wave(f, 36, amp_z=4, lag=0.1, base_x=(-24, -4, 0, 2)))
    anim.clip("stunned", 36, stunned, loop=True)

    # dangle: held up by the scruff (pinned at the origin), legs paddling, tail swinging (1.6 s loop).
    body_head = BONE_HEAD["body"]

    def dangle(f):
        sw, sw2, pad = wave(f, 48), wave(f, 48, 0.25), wave(f, 12)
        root_r, body_r = (-20 + 5 * sw, 6 * sw2, 0), (-10, 0, 0)
        scruff = _euler_q(root_r) @ (body_head + _euler_q(body_r) @ (SCRUFF - body_head))
        p = {"root": P(root_r, -scruff), "body": P(body_r), "head": P((18, 6 * sw2, 0)),
             "jaw": P((6, 0, 0)),
             "leg_l": P((-15 + 35 * pad, 0, 0)), "leg_r": P((-15 - 35 * pad, 0, 0)),
             "arm_l": P((-40 + 30 * wave(f, 12, 0.5), -15, 0)), "arm_r": P((-40 - 30 * wave(f, 12, 0.5), 15, 0))}
        p.update(pair("ear", (5, 25, 0)))
        return add(p, tail_wave(f, 48, amp_z=12, lag=0.1, base_x=(-55, -15, -8, -5)))
    anim.clip("dangle", 48, dangle, loop=True)

    # caged: sitting, sad; now and then it grabs the (imaginary) bars and shakes them (3 s loop).
    def caged(f):
        sh, breath = bump(f, 40, 78), wave(f, 90)
        rattle = wave(f, 5)
        p = {"root": P(loc=(0, 0, -0.065)),
             "body": P((22 - 22 * sh + 2 * breath + 7 * sh * rattle, 0, 0)),
             "head": P((22 - 34 * sh + 3 * breath, 0, 0)),
             "jaw": P((16 * sh * (0.5 + 0.5 * rattle), 0, 0)),
             "leg_l": P((-78, 0, 8)), "leg_r": P((-78, 0, -8)),
             "ear_l": P((10, 45 - 30 * sh, 0)), "ear_r": P((10, -45 + 30 * sh, 0))}
        p.update(pair("arm", (lerp(-25, -100, sh) + 12 * sh * rattle, 0, -15 + 5 * sh)))
        return add(p, tail_wave(f, 18, amp_z=3 + 4 * sh, lag=0.1, base_x=(-24, -4, 0, 2)))
    anim.clip("caged", 90, caged, loop=True)

    # squeak: a cheeky taunt, little hop, arms up, ears flapping, tail wagging (0.8 s).
    up = {"root": P(loc=(0, 0, 0.05)), "body": P((-12, 0, 0)), "head": P((-18, 12, 0)), "jaw": P((35, 0, 0)),
          **pair("arm", (-165, -30, 0)), **pair("leg", (15, 0, 0)),
          **{"tail_%d" % k: P((20, 0, 0)) for k in range(1, 5)}}
    land = dict(up, root=P())
    hold = dict(land, body=P((-8, 0, 0)), head=P((-12, -10, 0)), jaw=P((25, 0, 0)))
    base = keyed([(0, {}), (5, up, "out"), (9, land, "in"), (18, hold), (24, {}, "io")])

    def squeak(f):
        ears = bump(f, 2, 22) * wave(f, 6)
        arms = bump(f, 4, 20) * wave(f, 6, 0.25)
        extra = {"ear_l": P((0, 32 * ears, 0)), "ear_r": P((0, 32 * ears, 0)),
                 "arm_l": P((0, 0, 15 * arms)), "arm_r": P((0, 0, 15 * arms))}
        return add(base(f), extra, tail_wave(f, 8, amp_z=15 * bump(f, 0, 24), lag=0.12))
    anim.clip("squeak", 24, squeak)


if __name__ == "__main__":
    a = C.args("rat")
    C.reset()
    roots = build()
    C.export(a.out, roots, animations=True)

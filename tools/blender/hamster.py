"""The hamsters of the intro (client/intro/): what the rats were before the spill. Chubby cartoon
hamsters in the Kenney mini-characters style of rat.py, rigged and animated the same way.

    blender -b -P tools/blender/hamster.py -- [--coat golden|cream|cocoa] [--out PATH]

Sitting on its haunches, facing -Y (Godot +Z), feet on the origin. About 0.27 m to the ear tips,
0.25 m wide across the cheek pouches: half a rat, and round where the rat is lean. One skinned
mesh, every part weighted 100 % to one bone (rat.py's rig helpers and pose convention).

Three coats (one .glb each): golden (the classic), cream and cocoa.
Clips: idle, nibble, run (on the wheel), beg, hop, shiver (covered in goo), wash, look_up.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402
import rat as R  # noqa: E402  (rig helpers)
from rat import P, bump, keyed, pair, wave  # noqa: E402

ANIMATED = True

# coat -> (fur, darker patches, belly / cheeks / muzzle)
COATS = {
    "golden": ("dough", "orange", "off_white"),
    "cream": ("beige_light", "wood_light", "white"),
    "cocoa": ("wood", "brown", "beige_light"),
}
ASSETS = [("hamster", {"coat": "golden"}), ("hamster_cream", {"coat": "cream"}),
          ("hamster_cocoa", {"coat": "cocoa"})]

BONES = [
    ("root", None, (0, 0, 0)),
    ("body", "root", (0, 0.01, 0.06)),
    ("head", "body", (0, -0.01, 0.15)),
    ("jaw", "head", (0, -0.105, 0.13)),
    ("ear_l", "head", (0.06, -0.01, 0.235)),
    ("ear_r", "head", (-0.06, -0.01, 0.235)),
    ("arm_l", "body", (0.05, -0.07, 0.125)),
    ("arm_r", "body", (-0.05, -0.07, 0.125)),
    ("leg_l", "root", (0.055, 0.0, 0.05)),
    ("leg_r", "root", (-0.055, 0.0, 0.05)),
    ("tail", "body", (0, 0.095, 0.045)),
]


def _body(name, fur, patch, belly):
    b = C.Builder(name)
    # Round where the rat is boxy: a squashed ball, a cream bib in front, a darker saddle behind.
    b.sphere(0.1, (0, 0.005, 0.09), fur, scale=(1.06, 0.98, 0.92), segments=16, rings=10)
    b.sphere(0.068, (0, -0.046, 0.078), belly, scale=(0.95, 0.78, 0.98), segments=14, rings=8)
    b.sphere(0.066, (0, 0.052, 0.118), patch, scale=(1.0, 0.92, 0.72), segments=12, rings=7)
    return b.finish()


def _head(name, fur, patch, belly):
    b = C.Builder(name)
    # Big round head sitting straight on the body (hamsters have no neck).
    b.sphere(0.09, (0, -0.028, 0.18), fur, scale=(1.08, 0.95, 0.88), segments=16, rings=10)
    # Puffy cheek pouches with rosy cheeks, and a little muzzle.
    for s in (-1, 1):
        b.sphere(0.039, (s * 0.054, -0.078, 0.153), belly, scale=(1.0, 0.9, 0.86), segments=12, rings=7)
        b.sphere(0.015, (s * 0.073, -0.102, 0.161), "icing_pink", scale=(1.2, 0.4, 0.8), segments=8, rings=4)
    b.sphere(0.031, (0, -0.104, 0.161), belly, scale=(1.15, 1.0, 0.92), segments=12, rings=7)
    b.sphere(0.0135, (0, -0.135, 0.172), "rat_pink_dark", scale=(1.3, 0.9, 0.9), segments=8, rings=5)
    # Big shiny eyes, wide apart: the cute version of the rat's.
    for s in (-1, 1):
        b.sphere(0.024, (s * 0.046, -0.097, 0.203), "eye_black", scale=(0.92, 0.55, 1.1), segments=10, rings=6)
        b.sphere(0.0085, (s * 0.04 + 0.004, -0.109, 0.214), "eye_shine", segments=6, rings=4)
        b.sphere(0.004, (s * 0.052, -0.11, 0.194), "eye_shine", segments=5, rings=3)
    # A darker patch on top of the head, between the ears.
    b.sphere(0.045, (0, -0.022, 0.248), patch, scale=(1.15, 1.25, 0.36), segments=12, rings=6)
    return b.finish()


def _jaw(name, belly):
    b = C.Builder(name)
    b.sphere(0.02, (0, -0.116, 0.132), belly, scale=(1.2, 1.0, 0.6), segments=10, rings=5)
    for x in (-0.0062, 0.0062):  # two tiny front teeth
        b.box((0.01, 0.006, 0.015), (x, -0.133, 0.137), "tooth", bevel=0.002)
    return b.finish()


def _ear(name, s, fur):
    b = C.Builder(name)
    c = (s * 0.066, -0.014, 0.242)
    b.cylinder(0.035, 0.016, c, fur, rot=(90, 0, s * -22), segments=12, bevel=0.005)
    b.cylinder(0.023, 0.008, (s * 0.0645, -0.023, 0.241), "rat_pink", rot=(90, 0, s * -22), segments=10)
    return b.finish()


def _arm(name, s, fur):
    b = C.Builder(name)
    b.sphere(0.021, (s * 0.054, -0.083, 0.106), fur, scale=(0.9, 0.9, 1.25), rot=(25, 0, 0), segments=10, rings=6)
    b.sphere(0.0155, (s * 0.056, -0.096, 0.081), "rat_pink", scale=(1.1, 1.0, 0.85), segments=8, rings=5)
    return b.finish()


def _leg(name, s, fur):
    b = C.Builder(name)
    b.box((0.065, 0.08, 0.06), (s * 0.06, 0.0, 0.032), fur, bevel=0.024)
    b.box((0.042, 0.07, 0.016), (s * 0.06, -0.04, 0.0), "rat_pink", base=True, bevel=0.006)
    for k in (-1, 0, 1):  # little toes
        b.box((0.012, 0.016, 0.014), (s * 0.06 + k * 0.013, -0.076, 0.0), "rat_pink_dark", base=True, bevel=0.004)
    return b.finish()


def _tail(name):
    b = C.Builder(name)
    b.sphere(0.017, (0, 0.105, 0.045), "rat_pink", scale=(0.9, 1.3, 0.9), segments=8, rings=5)
    return b.finish()


def build_model(coat="golden"):
    fur, patch, belly = COATS[coat]
    arm = R.make_armature("Armature", BONES, length=0.03)
    parts = [(_body("body", fur, patch, belly), "body"), (_head("head", fur, patch, belly), "head"),
             (_jaw("jaw", belly), "jaw"), (_ear("ear_l", 1, fur), "ear_l"), (_ear("ear_r", -1, fur), "ear_r"),
             (_arm("arm_l", 1, fur), "arm_l"), (_arm("arm_r", -1, fur), "arm_r"),
             (_leg("leg_l", 1, fur), "leg_l"), (_leg("leg_r", -1, fur), "leg_r"), (_tail("tail"), "tail")]
    for obj, bone in parts:
        R.skin_rigid(obj, arm, bone)
    R.join([o for o, _ in parts], "Hamster")
    return arm


def build(coat="golden"):
    arm = build_model(coat)
    anim = R.Animator(arm)
    add_clips(anim)
    anim.finish()
    return [arm]


def add_clips(anim):
    # idle: breathing, quick sniffs, an ear flick, paws held at the chest (2 s).
    def idle(f):
        breath, sniff = wave(f, 60), bump(f, 8, 26) + bump(f, 38, 50)
        return {"body": P((2 * breath, 0, 2 * wave(f, 60, 0.25))),
                "head": P((-2 * breath + 3 * sniff * wave(f, 4), 4 * wave(f, 60, 0.4), 0)),
                "jaw": P((5 * sniff * max(0.0, wave(f, 4, 0.25)), 0, 0)),
                "ear_l": P((0, 25 * bump(f, 30, 36), 0)), "ear_r": P((0, -18 * bump(f, 44, 49), 0)),
                "arm_l": P((-30, 0, -12)), "arm_r": P((-30, 0, 12)),
                "tail": P((0, 0, 10 * wave(f, 20)))}
    anim.clip("idle", 60, idle, loop=True)

    # nibble: sitting up a little, paws at the mouth, jaw chattering away (0.8 s).
    def nibble(f):
        chew = wave(f, 4)
        return {"body": P((-10 + 1.5 * wave(f, 24), 0, 0)),
                "head": P((6 + 2.5 * wave(f, 8), 0, 2 * wave(f, 24))),
                "jaw": P((9 + 9 * chew, 0, 0)),
                "arm_l": P((-82 + 6 * wave(f, 8), 0, -32)), "arm_r": P((-82 + 6 * wave(f, 8, 0.1), 0, 32)),
                "ear_l": P((0, 6 * wave(f, 8), 0)), "ear_r": P((0, -6 * wave(f, 8), 0)),
                "tail": P((0, 0, 6 * wave(f, 12)))}
    anim.clip("nibble", 24, nibble, loop=True)

    # run: a frantic scurry, for the exercise wheel (0.33 s).
    def run(f):
        ph = wave(f, 10)
        p = {"root": P(loc=(0, 0, 0.018 * abs(wave(f, 10, 0.25)))),
             "body": P((48 + 4 * wave(f, 5), 0, 4 * ph)),
             "head": P((-36 - 4 * wave(f, 5), 0, -4 * ph)),
             "leg_l": P((60 * ph, 0, 0)), "leg_r": P((-60 * ph, 0, 0)),
             "arm_l": P((-70 - 50 * ph, 0, -6)), "arm_r": P((-70 + 50 * ph, 0, 6)),
             "tail": P((-20, 0, 12 * ph))}
        p.update(pair("ear", (-25 + 6 * wave(f, 5), 6, 0)))
        return p
    anim.clip("run", 10, run, loop=True)

    # beg: up on the hind legs, paws waving for a treat, head tilting (1 s).
    def beg(f):
        tilt = wave(f, 30)
        return {"root": P(loc=(0, 0.01, 0.015 + 0.006 * abs(wave(f, 15)))),
                "body": P((-26 + 2 * wave(f, 15), 0, 3 * tilt)),
                "head": P((-8 + 3 * wave(f, 15), 0, -12 * tilt)),
                "jaw": P((10 + 6 * max(0.0, wave(f, 15)), 0, 0)),
                "arm_l": P((-150 + 22 * wave(f, 10), 0, -20)), "arm_r": P((-150 + 22 * wave(f, 10, 0.5), 0, 20)),
                "leg_l": P((-12, 0, 0)), "leg_r": P((-12, 0, 0)),
                "ear_l": P((-8, -12 + 8 * wave(f, 15), 0)), "ear_r": P((-8, 12 - 8 * wave(f, 15), 0)),
                "tail": P((0, 0, 20 * wave(f, 10)))}
    anim.clip("beg", 30, beg, loop=True)

    # hop: a happy "popcorn" jump, legs kicking, ears flapping (0.6 s).
    crouch = {"root": P(loc=(0, 0, -0.008)), "body": P((18, 0, 0)), "head": P((-10, 0, 0)),
              **pair("arm", (-20, 0, -10)), **pair("leg", (-25, 0, 0)), **pair("ear", (-15, 10, 0))}
    air = {"root": P(loc=(0, 0, 0.11)), "body": P((-14, 0, 8)), "head": P((-14, 12, 0)), "jaw": P((14, 0, 0)),
           **pair("arm", (-160, -30, 0)), **pair("leg", (55, 0, 12)), **pair("ear", (10, 40, 0)),
           "tail": P((30, 0, 0))}
    anim.clip("hop", 18, keyed([(0, {}), (4, crouch, "out"), (9, air, "out"), (14, crouch, "in"), (18, {}, "io")]))

    # shiver: dripping with goo, fur on end, trembling all over (0.27 s loop).
    def shiver(f):
        j = wave(f, 4)
        return {"root": P(loc=(0.004 * j, 0, 0.006 * abs(wave(f, 8)))),
                "body": P((-6 + 3 * wave(f, 8, 0.25), 0, 5 * j)),
                "head": P((-14 + 4 * wave(f, 4, 0.25), 6 * j, -5 * j)),
                "jaw": P((20 + 6 * wave(f, 2), 0, 0)),
                "arm_l": P((-60, -55 + 8 * j, 0)), "arm_r": P((-60, 55 - 8 * j, 0)),
                "leg_l": P((-8, 0, 10)), "leg_r": P((-8, 0, -10)),
                "ear_l": P((-20, 30 + 10 * j, 0)), "ear_r": P((-20, -30 + 10 * j, 0)),
                "tail": P((40, 0, 15 * j))}
    anim.clip("shiver", 8, shiver, loop=True)

    # wash: grooming the face with both paws, in little circles (1.2 s).
    def wash(f):
        c, s = wave(f, 12), wave(f, 12, 0.25)
        return {"body": P((6 + 2 * c, 0, 0)), "head": P((14 + 5 * c, 6 * wave(f, 36), 0)),
                "jaw": P((4, 0, 0)),
                "arm_l": P((-105 + 14 * c, 0, -26 + 10 * s)), "arm_r": P((-105 + 14 * s, 0, 26 - 10 * c)),
                "ear_l": P((5, 8, 0)), "ear_r": P((5, -8, 0)), "tail": P((0, 0, 8 * wave(f, 18)))}
    anim.clip("wash", 36, wash, loop=True)

    # look_up: frozen, staring up at something coming (the bottle), ears back (1 s).
    def look_up(f):
        return {"body": P((-12, 0, 0)), "head": P((-30 + 1.5 * wave(f, 30), 0, 0)), "jaw": P((14, 0, 0)),
                "arm_l": P((-50, -10, -8)), "arm_r": P((-50, 10, 8)),
                "ear_l": P((-30, 20, 0)), "ear_r": P((-30, -20, 0)), "tail": P((10, 0, 0))}
    anim.clip("look_up", 30, look_up, loop=True)


if __name__ == "__main__":
    a = C.args("hamster", lambda p: p.add_argument("--coat", default="golden", choices=sorted(COATS)))
    C.reset()
    C.export(a.out, build(a.coat), animations=True)

#!/usr/bin/env python3
"""Generates the game's synthesized sounds and music (M7, ASSETS §6) into assets/audio/:

    python3 tools/audio/make_audio.py              # everything (about a minute)
    python3 tools/audio/make_audio.py sfx          # only sound effects
    python3 tools/audio/make_audio.py music        # only music
    python3 tools/audio/make_audio.py squeak hiss  # only sounds (and music) whose name starts with these
    python3 tools/audio/make_audio.py intro        # the intro's sounds and its music
    python3 tools/audio/make_audio.py outro        # the end-of-match cinematics' sounds and scores

Everything here is made from scratch with numpy (tools/audio/synth.py), so it belongs to the
project. Recorded CC0 sounds (Kenney packs: footsteps, impacts, UI clicks, doors) are used as they
are from assets/third_party/ by client/sound_bank.gd. Needs numpy and ffmpeg (libvorbis).
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import music  # noqa: E402
import synth as S  # noqa: E402
from synth import SR, samples, t_axis  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")

SOUNDS = {}  # name -> function returning a mono array


def sound(name):
    def deco(fn):
        SOUNDS[name] = fn
        return fn
    return deco


def rng(seed):
    return np.random.default_rng(seed)


# --- Rats ------------------------------------------------------------------------------------------

def _chirp(f0, f1, dur, vib=0.0, vib_rate=30.0):
    t = t_axis(dur)
    u = t / dur
    f = f0 + (f1 - f0) * np.sin(np.pi * 0.5 * u) + vib * np.sin(2 * np.pi * vib_rate * t)
    x = np.sin(S.phase(f, len(t))) + 0.25 * np.sin(2 * S.phase(f, len(t)))
    return x * S.bell(dur, 0.6)


for _i, _shape in enumerate([
        [(2400, 3600, 0.09, 0), (3300, 2600, 0.12, 120)],
        [(2800, 4200, 0.07, 0), (3000, 4000, 0.07, 0), (3800, 2500, 0.16, 180)],
        [(2200, 3200, 0.2, 260)],
        [(3500, 2400, 0.08, 0), (2600, 3900, 0.14, 150)]]):
    def _make(shape=_shape):
        parts = [np.concatenate([_chirp(f0, f1, d, v), np.zeros(samples(0.025))]) for f0, f1, d, v in shape]
        return S.fade(S.normalize(np.concatenate(parts), 0.7))
    SOUNDS["squeak_%d" % (_i + 1)] = _make


@sound("chomp")
def chomp():
    r = rng(2)
    out = np.zeros(samples(0.32))
    for at in (0.0, 0.13):
        clack = S.bandpass(S.noise(0.008, r), 2000, 9000) * 1.2
        crunch = S.bandpass(S.noise(0.07, r), 500, 4000) * S.env_exp(0.07, 0.025)
        S.mix_at(out, clack, samples(at))
        S.mix_at(out, crunch, samples(at + 0.006), 0.8)
    return S.fade(S.normalize(out, 0.85))


@sound("gnaw_loop")
def gnaw_loop():
    r = rng(3)
    dur = 1.2
    out = np.zeros(samples(dur))
    at = 0.0
    while at < dur:
        n = r.uniform(0.012, 0.03)
        burst = S.bandpass(S.noise(n, r), 1800, 7000) * S.env_exp(n, n / 3)
        S.mix_loop(out, burst, samples(at), r.uniform(0.4, 1.0))
        at += r.uniform(0.04, 0.09)
    return S.normalize(out, 0.6)


@sound("rat_step")
def rat_step():
    r = rng(4)
    t = t_axis(0.03)
    x = S.bandpass(S.noise(0.03, r), 1500, 6000) * np.exp(-t / 0.006)
    return S.normalize(x, 0.5)


@sound("crawl_loop")
def crawl_loop():
    """Rattling sheet metal under small feet (vents)."""
    r = rng(5)
    dur = 1.0
    out = np.zeros(samples(dur))
    for k in range(9):
        at = r.uniform(0, dur)
        t = t_axis(0.12)
        ring = sum(np.sin(2 * np.pi * f * t + r.uniform(0, 6)) * np.exp(-t / r.uniform(0.02, 0.05))
                   for f in (r.uniform(900, 1300), r.uniform(2500, 3200), r.uniform(4000, 4800)))
        S.mix_loop(out, ring, samples(at), r.uniform(0.3, 0.8))
    return S.normalize(out, 0.5)


# --- Supervisors -------------------------------------------------------------------------------------

def _voice(dur, f0, f1, formants_from, formants_to, seed):
    """A cartoon vocal grunt: a glottal buzz through moving formants."""
    r = rng(seed)
    t = t_axis(dur)
    u = t / dur
    pitch = f0 + (f1 - f0) * u + 4 * np.sin(2 * np.pi * 6 * t)
    src = S.lowpass(S.saw(pitch, dur), 3500, 1) + 0.05 * S.noise(dur, r)
    freqs = [a + (b - a) * np.clip(u * 1.6, 0, 1) for a, b in zip(formants_from, formants_to)]
    y = S.resonator(src, freqs, [90, 110, 160])
    env = np.clip(t / 0.02, 0, 1) * np.clip((dur - t) / 0.12, 0, 1)
    return S.fade(S.normalize(y * env, 0.8))


@sound("ow_1")
def ow_1():
    return _voice(0.45, 260, 170, (800, 1200, 2700), (380, 650, 2400), 6)


@sound("ow_2")
def ow_2():
    return _voice(0.38, 300, 190, (750, 1300, 2600), (420, 800, 2300), 7)


@sound("whoosh")
def whoosh():
    r = rng(8)
    dur = 0.28
    x = S.sweep_filter(S.noise(dur, r), lambda u: 300 + 900 * u, lambda u: 1200 + 2500 * u)
    return S.fade(S.normalize(x * S.bell(dur, 1.5), 0.6))


@sound("bonk")
def bonk():
    """Cartoon BONK: a hollow knock that drops in pitch, plus a little spring boing."""
    dur = 0.6
    t = t_axis(dur)
    f = 380 * (1 + 0.5 * np.exp(-t / 0.02))
    knock = (np.sin(S.phase(f, len(t))) + 0.5 * np.sin(S.phase(f * 2.76, len(t)))) * np.exp(-t / 0.07)
    click = np.zeros(len(t))
    click[:samples(0.004)] = S.noise(0.004, rng(9))
    boing_f = 220 * (1 + 0.25 * np.sin(2 * np.pi * 22 * t) * np.exp(-t / 0.25))
    boing = np.sin(S.phase(boing_f, len(t))) * np.exp(-t / 0.22) * np.clip((t - 0.03) / 0.02, 0, 1)
    return S.fade(S.normalize(knock * 1.0 + click * 0.6 + boing * 0.45, 0.95))


@sound("snap_crack")
def snap_crack():
    dur = 0.4
    t = t_axis(dur)
    crack = S.highpass(S.noise(dur, rng(10)), 1500) * np.exp(-t / 0.012)
    ring = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / 0.08) for f in (2450, 3710, 5200)) * 0.25
    thud = np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.05) * 0.6
    return S.fade(S.normalize(crack + ring + thud, 0.95))


@sound("munch")
def munch():
    r = rng(11)
    out = np.zeros(samples(1.0))
    for at in (0.0, 0.3, 0.55):
        n = 0.12
        bite = S.bandpass(S.noise(n, r), 400, 3500) * S.env_exp(n, 0.04)
        S.mix_at(out, bite, samples(at))
    hum = _voice(0.3, 160, 140, (300, 900, 2300), (280, 800, 2200), 12)
    S.mix_at(out, hum * 0.5, samples(0.72))
    return S.fade(S.normalize(out, 0.8))


@sound("spit")
def spit():
    """A caged rat's PTOOEY: a lip pop, a quick squeaky "too-ee" and a wet spray."""
    r = rng(60)
    out = np.zeros(samples(0.45))
    S.mix_at(out, S.lowpass(S.noise(0.02, r), 900) * S.env_exp(0.02, 0.006), 0, 1.0)
    S.mix_at(out, _voice(0.16, 560, 820, (330, 900, 2300), (300, 2300, 3000), 61), samples(0.025), 0.5)
    spray = S.sweep_filter(S.noise(0.24, r), lambda u: 2500 - 1000 * u, lambda u: 9000 - 3000 * u)
    S.mix_at(out, spray * S.env_exp(0.24, 0.06, 0.005), samples(0.12), 0.55)
    return S.fade(S.normalize(out, 0.75))


@sound("splat")
def splat():
    """Rat spit landing: a small wet slap and a couple of drips."""
    r = rng(62)
    out = np.zeros(samples(0.4))
    t = t_axis(0.12)
    S.mix_at(out, np.sin(S.phase(160 + 260 * np.exp(-t / 0.02), len(t))) * np.exp(-t / 0.04), 0, 0.6)
    S.mix_at(out, S.bandpass(S.noise(0.15, r), 600, 5000) * S.env_exp(0.15, 0.03), 0, 1.0)
    for at in (0.13, 0.25):
        tp = t_axis(0.06)
        drop = np.sin(S.phase(r.uniform(1000, 1400) * (1 + 1.1 * tp / 0.06), len(tp))) * np.exp(-tp / 0.015)
        S.mix_at(out, drop, samples(at), 0.2)
    return S.fade(S.normalize(out, 0.8))


@sound("emote_whistle")
def emote_whistle():
    """A cheerful three-note whistle (supervisor emote)."""
    out = np.zeros(samples(0.9))
    for at, note, d in ((0.0, 84, 0.18), (0.2, 88, 0.18), (0.4, 91, 0.4)):
        f = S.midi(note)
        x = S.sine(f * (1 + 0.01 * np.sin(2 * np.pi * 7 * t_axis(d))), d) * S.env_adsr(d, 0.02, 0.03, 0.8, 0.05)
        S.mix_at(out, x + 0.05 * S.lowpass(S.noise(d), 4000), samples(at))
    return S.fade(S.normalize(out, 0.6))


# --- Plant and hazards -----------------------------------------------------------------------------------

@sound("hiss_loop")
def hiss_loop():
    r = rng(13)
    dur = 2.0
    x = S.bandpass(S.noise(dur + 0.1, r), 1800, 9000) + 0.3 * S.lowpass(S.noise(dur + 0.1, r), 600)
    mod = 1 + 0.15 * S.lowpass(r.uniform(-1, 1, len(x)), 6, 1) * 20
    return S.normalize(S.loopable(x * mod, 0.1), 0.6)


@sound("puff")
def puff():
    dur = 0.35
    x = S.sweep_filter(S.noise(dur, rng(14)), lambda u: 600 - 300 * u, lambda u: 6000 - 3500 * u)
    return S.fade(S.normalize(x * S.env_exp(dur, 0.1, 0.01), 0.6))


def _crackle(dur, seed, density=60, buzz=120.0):
    r = rng(seed)
    t = t_axis(dur)
    out = 0.35 * np.sign(np.sin(2 * np.pi * buzz * t)) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t))
    out = S.lowpass(out, 2500)
    for _ in range(int(density * dur)):
        n = r.uniform(0.002, 0.01)
        S.mix_at(out, S.highpass(S.noise(n, r), 2000) * r.uniform(0.5, 1.5), samples(r.uniform(0, dur)))
    return out


@sound("zap_1")
def zap_1():
    dur = 0.4
    return S.fade(S.normalize(S.distort(_crackle(dur, 15) * S.env_exp(dur, 0.15), 2.5), 0.8))


@sound("zap_2")
def zap_2():
    dur = 0.3
    return S.fade(S.normalize(S.distort(_crackle(dur, 16, 90, 100.0) * S.env_exp(dur, 0.1), 2.5), 0.8))


@sound("buzz_loop")
def buzz_loop():
    """A live electrified puddle: mains buzz with sparse crackles."""
    return S.normalize(S.loopable(_crackle(1.05, 17, 12), 0.05), 0.45)


for _i in range(3):
    def _geiger(k=_i):
        t = t_axis(0.02)
        x = S.highpass(S.noise(0.02, rng(20 + k)), 1200 + 400 * k) * np.exp(-t / 0.0025)
        return S.normalize(x, 0.7)
    SOUNDS["geiger_%d" % (_i + 1)] = _geiger


@sound("whistle_fall")
def whistle_fall():
    dur = 0.9
    t = t_axis(dur)
    f = 1500 - 800 * (t / dur) ** 1.4
    x = S.sine(f, dur) * 0.8 + 0.1 * S.lowpass(S.noise(dur), 3000)
    return S.fade(S.normalize(x * np.clip(t / 0.1, 0, 1), 0.5))


@sound("rumble")
def rumble():
    dur = 1.0
    t = t_axis(dur)
    x = S.lowpass(S.noise(dur, rng(21)), 160, 3) * np.exp(-t / 0.3)
    return S.fade(S.normalize(x, 0.9))


@sound("klaxon_loop")
def klaxon_loop():
    """CRITICAL: an "AWOO-GA" horn, twice per 2.4 s loop (plays from the alarm beacons)."""
    dur = 2.4
    out = np.zeros(samples(dur))
    for at in (0.0, 1.2):
        d = 0.9
        t = t_axis(d)
        f = 170 + 260 * np.clip(t / 0.55, 0, 1) ** 0.7
        x = S.saw(f, d) + 0.5 * S.square(f * 1.005, d)
        x = S.lowpass(S.distort(x, 1.5), 1800) * S.env_adsr(d, 0.03, 0.05, 0.9, 0.12)
        S.mix_at(out, x, samples(at))
    return S.normalize(out, 0.7)


@sound("warning_loop")
def warning_loop():
    """WARNING: a two-note chime every 2 s."""
    dur = 2.0
    out = np.zeros(samples(dur))
    for at, note in ((0.0, 76), (0.25, 72)):
        f = S.midi(note)
        t = t_axis(0.9)
        x = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.01 * t)) * np.exp(-t / 0.3)
        S.mix_at(out, x, samples(at))
    return S.normalize(out, 0.6)


@sound("scram_klaxon")
def scram_klaxon():
    dur = 2.0
    t = t_axis(dur)
    f = np.where((t % 0.5) < 0.25, 330.0, 250.0)
    x = S.lowpass(S.square(f, dur) + S.saw(f * 0.5, dur) * 0.5, 2200) * S.env_adsr(dur, 0.02, 0.1, 0.9, 0.2)
    return S.fade(S.normalize(x, 0.75))


@sound("coolant_whoosh")
def coolant_whoosh():
    dur = 2.0
    x = S.sweep_filter(S.noise(dur, rng(22)), lambda u: 150 + 200 * u, lambda u: 900 + 5000 * (1 - u))
    gurgle = S.sine(90 + 30 * np.sin(2 * np.pi * 9 * t_axis(dur)), dur) * 0.3
    return S.fade(S.normalize((x + gurgle) * S.bell(dur, 0.8), 0.7))


def _hum(dur, base, harmonics, noise_band, noise_gain, mod_rate=0.0, mod_depth=0.0, seed=30):
    """A loopable machine hum: frequencies are rounded so each repeats a whole number of times."""
    t = t_axis(dur)
    x = np.zeros(len(t))
    for h, a in harmonics:
        f = round(base * h * dur) / dur
        x += a * np.sin(2 * np.pi * f * t)
    n = S.bandpass(S.noise(dur + 0.2, rng(seed)), *noise_band)
    x += noise_gain * S.loopable(n, 0.2)[:len(t)]
    if mod_rate:
        rate = round(mod_rate * dur) / dur
        x *= 1 - mod_depth * 0.5 * (1 + np.cos(2 * np.pi * rate * t))
    return S.normalize(x, 0.5)


@sound("hum_room_loop")
def hum_room_loop():
    return _hum(4.0, 60, [(1, 0.3), (2, 0.2), (3, 0.08)], (200, 2000), 0.25, seed=31)


@sound("hum_reactor_loop")
def hum_reactor_loop():
    return _hum(4.0, 41, [(1, 0.6), (2, 0.3), (3, 0.2), (7, 0.05)], (80, 600), 0.4, 0.5, 0.25, seed=32)


@sound("hum_turbine_loop")
def hum_turbine_loop():
    x = _hum(4.0, 55, [(1, 0.5), (2, 0.2), (21, 0.12), (31, 0.06)], (300, 3000), 0.3, seed=33)
    return S.normalize(x, 0.5)


@sound("hum_pump_loop")
def hum_pump_loop():
    return _hum(4.0, 48, [(1, 0.5), (2, 0.3), (5, 0.08)], (100, 1200), 0.35, 2.0, 0.6, seed=34)


@sound("hum_electric_loop")
def hum_electric_loop():
    return _hum(4.0, 120, [(1, 0.4), (2, 0.25), (3, 0.15), (5, 0.08)], (2000, 8000), 0.06, seed=35)


@sound("fan_loop")
def fan_loop():
    return _hum(4.0, 24, [(1, 0.2), (6, 0.2)], (150, 2500), 0.6, 6.0, 0.35, seed=36)


@sound("crickets_loop")
def crickets_loop():
    r = rng(37)
    dur = 6.0
    out = 0.15 * S.loopable(S.lowpass(S.noise(dur + 0.3, r), 400), 0.3)[:samples(dur)]  # distant wind
    for k in range(14):
        at = r.uniform(0, dur)
        f = r.uniform(4200, 5200)
        chirp = S.sine(f, 0.25) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 30 * t_axis(0.25)))) * S.bell(0.25)
        S.mix_loop(out, chirp, samples(at), r.uniform(0.05, 0.15))
    return S.normalize(out, 0.4)


@sound("drip_loop")
def drip_loop():
    r = rng(38)
    dur = 5.0
    out = 0.2 * S.loopable(S.lowpass(S.noise(dur + 0.3, r), 250), 0.3)[:samples(dur)]
    for k in range(6):
        at = r.uniform(0, dur)
        d = 0.08
        t = t_axis(d)
        f = r.uniform(900, 1400) * (1 + 1.2 * t / d)
        drop = np.sin(S.phase(f, len(t))) * np.exp(-t / 0.02)
        S.mix_loop(out, drop, samples(at), r.uniform(0.3, 0.6))
    return S.normalize(out, 0.45)


@sound("spark")
def spark():
    dur = 0.25
    return S.fade(S.normalize(S.distort(_crackle(dur, 39, 120, 0.0001) * S.env_exp(dur, 0.06), 3.0), 0.6))


# --- Interactions and UI ---------------------------------------------------------------------------------

@sound("beep")
def beep():
    d = 0.12
    return S.fade(S.normalize(S.sine(880, d) + 0.2 * S.sine(1760, d), 0.6), 0.002, 0.02)


@sound("beep_go")
def beep_go():
    d = 0.45
    return S.fade(S.normalize(S.sine(1320, d) + 0.2 * S.sine(2640, d), 0.6) * S.env_exp(d, 0.25), 0.002, 0.03)


@sound("button")
def button():
    d = 0.09
    t = t_axis(d)
    x = S.woodblock(1600, 1.0)[:len(t)] + S.sine(900, d) * np.exp(-t / 0.02) * 0.4
    return S.fade(S.normalize(x, 0.6))


@sound("lever_pull")
def lever_pull():
    r = rng(40)
    d = 0.5
    t = t_axis(d)
    creak = S.bandpass(S.saw(70 + 40 * t / d + 3 * np.sin(2 * np.pi * 13 * t), d), 300, 2500) * S.bell(d) * 0.4
    clunk = np.zeros(len(t))
    S.mix_at(clunk, np.sin(2 * np.pi * 120 * t_axis(0.15)) * S.env_exp(0.15, 0.04)
             + S.bandpass(S.noise(0.15, r), 200, 2000) * S.env_exp(0.15, 0.02), samples(0.33))
    return S.fade(S.normalize(creak + clunk, 0.8))


@sound("repair_done")
def repair_done():
    out = np.zeros(samples(0.7))
    for at, note in ((0.0, 79), (0.1, 84), (0.2, 88)):
        S.mix_at(out, S.xylophone(S.midi(note), 0.5), samples(at))
    return S.fade(S.normalize(out, 0.6))


@sound("sabotage_done")
def sabotage_done():
    d = 0.8
    t = t_axis(d)
    fizz = S.distort(_crackle(d, 41, 80) * S.env_exp(d, 0.3), 2.0) * 0.6
    down = S.sine(600 * np.exp(-t / 0.35), d) * S.env_exp(d, 0.4) * 0.5
    return S.fade(S.normalize(fizz + down, 0.75))


# --- The intro (client/intro/) ------------------------------------------------------------------------

for _i, _shape in enumerate([
        [(3900, 5300, 0.05, 0), (4300, 5800, 0.06, 0)],
        [(4800, 3900, 0.09, 140), (4100, 5200, 0.05, 0)]]):
    def _make(shape=_shape):
        """A hamster: higher, shorter and softer than a rat."""
        parts = [np.concatenate([_chirp(f0, f1, d, v, 40.0), np.zeros(samples(0.02))]) for f0, f1, d, v in shape]
        return S.fade(S.normalize(np.concatenate(parts), 0.55))
    SOUNDS["intro_squeak_%d" % (_i + 1)] = _make


@sound("intro_sparkle")
def intro_sparkle():
    """Hearts: a quick rising twinkle."""
    out = np.zeros(samples(0.8))
    for k, note in enumerate((91, 95, 98, 103)):
        S.mix_at(out, S.glockenspiel(S.midi(note), 0.5, 0.25), samples(k * 0.045), 0.8 - k * 0.1)
    S.mix_at(out, S.highpass(S.noise(0.5, rng(50)), 6000) * S.bell(0.5) * 0.06, 0)
    return S.fade(S.normalize(out, 0.5))


def _shout(dur, pitch, formants, seed, vib=(5.0, 0.02), breath=0.05):
    """A cartoon voice: a buzz with the pitch curve `pitch(u)` (u = 0..1, Hz) through the formants
    `formants(u)` (three Hz values), with vibrato (rate, depth) and a little breath."""
    t = t_axis(dur)
    u = t / dur
    f = pitch(u) * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t))
    src = S.lowpass(S.saw(f, dur), 4000, 1) + breath * S.noise(dur, rng(seed))
    fr = formants(u)
    y = S.resonator(src, fr, [90, 120, 170])
    env = np.clip(t / 0.03, 0, 1) * np.clip((dur - t) / 0.1, 0, 1)
    return S.normalize(y * env, 0.8)


@sound("intro_whoa")
def intro_whoa():
    """The new guy, tripping: "WHOA-oa-oa!", the pitch flying up and wobbling down."""
    def pitch(u):
        return np.where(u < 0.25, 190 + 170 * (u / 0.25), 360 - 170 * np.clip((u - 0.25) / 0.75, 0, 1) ** 1.3)

    def formants(u):
        a = np.clip(u * 4, 0, 1)
        return [300 + 400 * a, 620 + 480 * a, 2300 + 100 * a]
    x = _shout(0.75, pitch, formants, 51, vib=(9.0, 0.035))
    return S.fade(S.normalize(S.distort(x, 1.3), 0.85))


@sound("intro_eek")
def intro_eek():
    """Two supervisors in falsetto: "EEEEK!" (a rat!)."""
    out = np.zeros(samples(0.7))
    for k, (lo, hi, at) in enumerate(((680, 980, 0.0), (610, 900, 0.045))):
        def pitch(u, lo=lo, hi=hi):
            return lo + (hi - lo) * np.clip(u * 3, 0, 1)
        voice = _shout(0.55, pitch, lambda u: [320 + 0 * u, 2450 + 0 * u, 3150 + 0 * u], 52 + k, vib=(11.0, 0.03))
        S.mix_at(out, S.distort(voice, 1.6), samples(at), 0.6)
    S.mix_at(out, S.bandpass(S.noise(0.02, rng(54)), 2000, 6000) * 0.3, samples(0.56))  # the "k"
    return S.fade(S.normalize(out, 0.85))


@sound("intro_splash")
def intro_splash():
    """The bottle lands on the donuts: a fat wet SPLAT, bubbles, a few drips."""
    r = rng(55)
    d = 1.2
    out = np.zeros(samples(d))
    t = t_axis(0.3)
    S.mix_at(out, np.sin(S.phase(45 + 50 * np.exp(-t / 0.05), len(t))) * np.exp(-t / 0.12), 0, 0.9)
    S.mix_at(out, S.bandpass(S.noise(0.4, r), 250, 2600) * S.env_exp(0.4, 0.07), 0, 1.0)
    S.mix_at(out, S.bandpass(S.noise(0.6, r), 2000, 8000) * S.env_exp(0.6, 0.15), samples(0.01), 0.35)
    for _ in range(9):  # bubbles popping up out of the goo
        f = r.uniform(300, 900)
        d_b = r.uniform(0.03, 0.06)
        tb = t_axis(d_b)
        blip = np.sin(S.phase(f * (1 + 0.8 * tb / d_b), len(tb))) * S.bell(d_b)
        S.mix_at(out, blip, samples(r.uniform(0.05, 0.6)), r.uniform(0.2, 0.45))
    for _ in range(5):  # drips
        d_p = 0.07
        tp = t_axis(d_p)
        drop = np.sin(S.phase(r.uniform(900, 1300) * (1 + 1.1 * tp / d_p), len(tp))) * np.exp(-tp / 0.018)
        S.mix_at(out, drop, samples(r.uniform(0.4, 1.05)), r.uniform(0.12, 0.25))
    return S.fade(S.normalize(out, 0.9))


@sound("intro_glug")
def intro_glug():
    """The upturned bottle emptying: glug, glug, glug."""
    r = rng(56)
    out = np.zeros(samples(0.75))
    for k in range(4):
        d = 0.09
        t = t_axis(d)
        f = (120 + 15 * k) * (1 + 1.2 * t / d)
        glug = np.sin(S.phase(f, len(t))) * S.bell(d, 0.8) + 0.15 * S.lowpass(S.noise(d, r), 900) * S.bell(d)
        S.mix_at(out, glug, samples(0.04 + k * 0.15 + r.uniform(-0.01, 0.01)), 1.0 - k * 0.12)
    return S.fade(S.normalize(out, 0.75))


@sound("intro_clonk")
def intro_clonk():
    """The empty plastic bottle hitting the floor, bouncing once, twice."""
    out = np.zeros(samples(0.6))
    for at, gain in ((0.0, 1.0), (0.13, 0.45), (0.22, 0.2)):
        d = 0.18
        t = t_axis(d)
        x = (np.sin(2 * np.pi * 290 * t) + 0.6 * np.sin(2 * np.pi * 690 * t) + 0.25 * np.sin(2 * np.pi * 1530 * t))
        x = x * np.exp(-t / 0.045)
        x[:samples(0.003)] += S.noise(0.003, rng(57)) * 0.8
        S.mix_at(out, x, samples(at), gain)
    return S.fade(S.normalize(out, 0.75))


for _i, _k in enumerate((1.0, 1.12, 1.26)):
    def _poof(k=_k, seed=60 + _i):
        """The transformation: a cork POP, a whoosh of smoke and a shimmer of magic (each one higher)."""
        r = rng(seed)
        d = 0.95
        out = np.zeros(samples(d))
        t = t_axis(0.12)
        S.mix_at(out, np.sin(S.phase(k * (180 + 1100 * np.exp(-t / 0.012)), len(t))) * np.exp(-t / 0.04), 0, 1.0)
        S.mix_at(out, np.sin(2 * np.pi * 55 * k * t_axis(0.3)) * S.env_exp(0.3, 0.09), 0, 0.6)
        whoosh = S.sweep_filter(S.noise(0.5, r), lambda u: k * (500 + 900 * np.sin(np.pi * u)),
                                lambda u: k * (2200 + 2600 * np.sin(np.pi * u)))
        S.mix_at(out, whoosh * S.bell(0.5, 1.2), samples(0.01), 0.55)
        for _ in range(12):
            S.mix_at(out, S.glockenspiel(k * r.uniform(2200, 6500), 0.4, 0.12), samples(r.uniform(0.03, 0.5)),
                     r.uniform(0.08, 0.2))
        return S.fade(S.normalize(out, 0.9))
    SOUNDS["intro_poof_%d" % (_i + 1)] = _poof


@sound("intro_flip")
def intro_flip():
    """The board's number cards flipping over: clack-clack."""
    out = np.zeros(samples(0.25))
    for at, f in ((0.0, 2300), (0.06, 1700), (0.1, 2000)):
        S.mix_at(out, S.woodblock(f, 1.0), samples(at), 0.8)
    S.mix_at(out, S.bandpass(S.noise(0.12, rng(63)), 1500, 6000) * S.env_exp(0.12, 0.03) * 0.3, 0)
    return S.fade(S.normalize(out, 0.7))


# --- The end-of-match cinematics (client/outro/) ------------------------------------------------------------

def _granny(dur, pitch, formants, seed, vib=(5.5, 0.03), breath=0.08, drive=1.0):
    """Grandma's voice: a soft, a little shaky buzz (higher than the supervisors') through formants."""
    x = _shout(dur, pitch, formants, seed, vib=vib, breath=breath)
    return S.normalize(S.distort(x, drive) if drive > 1.0 else x, 0.8)


@sound("outro_birds")
def outro_birds():
    """Dawn in town: a few birds chirping, far and near, over a soft breeze (the supervisors' ending)."""
    r = rng(70)
    dur = 9.0
    out = 0.05 * S.lowpass(S.noise(dur, r), 500)
    at = 0.2
    while at < dur - 0.6:
        f0 = r.uniform(2600, 4200)
        notes = r.integers(2, 6)
        gain = r.uniform(0.25, 0.7)
        for k in range(notes):
            d = r.uniform(0.04, 0.09)
            t = t_axis(d)
            f = f0 * (1 + r.uniform(-0.25, 0.3) * t / d) + 300 * np.sin(2 * np.pi * r.uniform(25, 45) * t)
            S.mix_at(out, S.sine(f, d) * S.bell(d, 0.7), samples(at + k * r.uniform(0.07, 0.11)), gain)
        at += r.uniform(0.35, 1.0)
    return S.fade(S.normalize(out, 0.5), 0.3, 0.6)


@sound("outro_lever")
def outro_lever():
    """The toaster's lever going down: a spring creaks, KA-CHUNK, the latch clicks."""
    r = rng(71)
    out = np.zeros(samples(0.45))
    d = 0.12
    t = t_axis(d)
    creak = S.bandpass(S.saw(220 + 140 * t / d, d), 600, 3500) * S.bell(d) * 0.3
    S.mix_at(out, creak, 0)
    t2 = t_axis(0.2)
    thunk = np.sin(S.phase(140 * (1 + 0.6 * np.exp(-t2 / 0.02)), len(t2))) * np.exp(-t2 / 0.05)
    S.mix_at(out, thunk, samples(0.1), 0.9)
    S.mix_at(out, S.bandpass(S.noise(0.03, r), 1500, 7000) * S.env_exp(0.03, 0.006), samples(0.1), 0.8)
    ring = sum(np.sin(2 * np.pi * f * t2) * np.exp(-t2 / 0.06) for f in (2300, 3450, 5100)) * 0.18
    S.mix_at(out, ring, samples(0.11))
    return S.fade(S.normalize(out, 0.85))


def _element_hum(dur, seed, wobble=0.0):
    t = t_axis(dur)
    f = 120.0 * (1 + wobble * 0.04 * np.sin(2 * np.pi * 1.7 * t) * np.sin(2 * np.pi * 0.43 * t))
    x = 0.5 * np.sin(S.phase(f, len(t))) + 0.25 * np.sin(S.phase(f * 2, len(t))) + 0.1 * np.sin(S.phase(f * 3, len(t)))
    x += 0.06 * S.bandpass(S.noise(dur, rng(seed)), 2500, 7000)  # the coils ticking
    if wobble:
        x *= 0.75 + 0.25 * np.sin(2 * np.pi * 2.3 * t) * np.sin(2 * np.pi * 0.9 * t + 1)
    return x


@sound("outro_hum")
def outro_hum():
    """The toaster's elements warming: a steady electric hum (loops)."""
    return S.normalize(S.loopable(_element_hum(2.05, 72), 0.05), 0.45)


@sound("outro_hum_weak")
def outro_hum_weak():
    """The same hum on a failing grid: wobbling in pitch and level (loops)."""
    return S.normalize(S.loopable(_element_hum(2.55, 73, wobble=1.0), 0.05), 0.4)


@sound("outro_tap")
def outro_tap():
    """A fingertip tapping the formica: tok."""
    t = t_axis(0.08)
    x = np.sin(2 * np.pi * 700 * t) * np.exp(-t / 0.012) + 0.6 * S.bandpass(S.noise(0.08, rng(74)), 800, 4000) * np.exp(-t / 0.006)
    return S.fade(S.normalize(x, 0.6))


@sound("outro_sniff")
def outro_sniff():
    """A sniff: two quick breaths in through the nose."""
    r = rng(75)
    out = np.zeros(samples(0.32))
    for at, d in ((0.0, 0.11), (0.15, 0.14)):
        x = S.sweep_filter(S.noise(d, r), lambda u: 1200 + 800 * u, lambda u: 4000 + 2500 * u) * S.bell(d, 0.6)
        S.mix_at(out, x, samples(at))
    return S.fade(S.normalize(out, 0.55))


@sound("outro_ding")
def outro_ding():
    """The toaster's bell: a bright DING with a long shimmer."""
    d = 1.6
    t = t_axis(d)
    f = 1760.0
    x = sum(a * np.sin(2 * np.pi * f * h * t) * np.exp(-t / (tau * 0.9)) for h, a, tau in
            ((1.0, 1.0, 0.7), (2.76, 0.45, 0.25), (5.4, 0.25, 0.1), (8.9, 0.12, 0.05), (0.5, 0.2, 0.9)))
    x[:samples(0.002)] += S.noise(0.002, rng(76)) * 0.5
    return S.fade(S.normalize(x, 0.8), 0.001, 0.2)


@sound("outro_pop")
def outro_pop():
    """The slices spring up: a cartoon BOING and a little whoosh."""
    d = 0.5
    t = t_axis(d)
    f = 330 * (1 + 0.35 * np.sin(2 * np.pi * 18 * t) * np.exp(-t / 0.15)) * (1 + 0.5 * t / d)
    boing = np.sin(S.phase(f, len(t))) * np.exp(-t / 0.16)
    whoosh = S.sweep_filter(S.noise(d, rng(77)), lambda u: 800 + 2000 * u, lambda u: 3000 + 4000 * u) * S.bell(d, 1.5)
    return S.fade(S.normalize(boing + 0.35 * whoosh, 0.8))


@sound("outro_land")
def outro_land():
    """A slice of toast landing on a china plate: a light clack and a crumble."""
    r = rng(78)
    out = np.zeros(samples(0.3))
    t = t_axis(0.12)
    clack = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / 0.025) for f in (1900, 3100)) * 0.4
    clack += np.sin(2 * np.pi * 260 * t) * np.exp(-t / 0.03) * 0.7
    S.mix_at(out, clack, 0)
    for _ in range(8):
        d = r.uniform(0.004, 0.012)
        S.mix_at(out, S.highpass(S.noise(d, r), 2500) * r.uniform(0.15, 0.4), samples(r.uniform(0.02, 0.2)))
    return S.fade(S.normalize(out, 0.7))


@sound("outro_ooh")
def outro_ooh():
    """Grandma, delighted: "Ooh!", up and down."""
    def pitch(u):
        return 300 + 160 * np.sin(np.pi * np.clip(u * 1.3, 0, 1))

    def formants(u):
        return [330 + 0 * u, 760 + 0 * u, 2350 + 0 * u]
    return _granny(0.55, pitch, formants, 79)


@sound("outro_hop")
def outro_hop():
    """Her slippers landing: a soft pff."""
    t = t_axis(0.18)
    x = S.lowpass(S.noise(0.18, rng(80)), 900) * np.exp(-t / 0.04) + 0.5 * np.sin(2 * np.pi * 90 * t) * np.exp(-t / 0.05)
    return S.fade(S.normalize(x, 0.6))


def _crunch(dur, bites, seed, low=1.0):
    r = rng(seed)
    out = np.zeros(samples(dur))
    t = t_axis(0.15)
    S.mix_at(out, np.sin(S.phase(110 * (1 + np.exp(-t / 0.02)), len(t))) * np.exp(-t / 0.05) * low, 0, 0.7)
    for _ in range(bites):
        d = r.uniform(0.003, 0.014)
        burst = S.bandpass(S.noise(d, r), r.uniform(1500, 3000), r.uniform(6000, 11000)) * r.uniform(0.4, 1.0)
        S.mix_at(out, burst, samples(r.uniform(0.0, dur * 0.7) ** 1.3 / (dur * 0.7) ** 0.3))
    S.mix_at(out, S.bandpass(S.noise(dur * 0.6, r), 900, 5000) * S.env_exp(dur * 0.6, dur * 0.12), 0, 0.5)
    return out


@sound("outro_crunch")
def outro_crunch():
    """Her bite into golden toast: a big, crisp CRUNCH."""
    return S.fade(S.normalize(_crunch(0.42, 70, 81), 0.95))


@sound("outro_nibble")
def outro_nibble():
    """A rat's quick crunch in the dark."""
    return S.fade(S.normalize(_crunch(0.16, 22, 82, low=0.4), 0.7))


@sound("outro_mmm")
def outro_mmm():
    """Bliss: a happy, closed-mouth "Mmm!" that wobbles up."""
    def pitch(u):
        return 260 + 90 * u + 25 * np.sin(2 * np.pi * 3 * u)

    def formants(u):
        return [250 + 0 * u, 1300 + 0 * u, 2600 + 0 * u]
    x = _granny(0.7, pitch, formants, 83, vib=(6.0, 0.035), breath=0.03)
    return S.fade(S.normalize(S.lowpass(x, 1800), 0.75))


@sound("outro_flicker")
def outro_flicker():
    """The lamp flickers: a buzz, cut twice."""
    d = 0.22
    t = t_axis(d)
    x = _crackle(d, 84, 40, 100.0)
    gate = np.where(((t > 0.03) & (t < 0.07)) | ((t > 0.11) & (t < 0.14)), 0.1, 1.0)
    return S.fade(S.normalize(x * gate, 0.5))


@sound("outro_hmm")
def outro_hmm():
    """Grandma, puzzled: "Hm?", rising."""
    def pitch(u):
        return 230 + 140 * u ** 1.5

    def formants(u):
        return [260 + 0 * u, 1400 + 0 * u, 2500 + 0 * u]
    return S.fade(S.normalize(S.lowpass(_granny(0.4, pitch, formants, 85, breath=0.04), 2000), 0.7))


@sound("outro_tonk")
def outro_tonk():
    """Knuckles rapping a chrome toaster: tonk."""
    d = 0.35
    t = t_axis(d)
    x = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t / tau) for f, a, tau in
            ((620, 1.0, 0.09), (1530, 0.5, 0.05), (2870, 0.3, 0.03), (4100, 0.15, 0.02)))
    x[:samples(0.003)] += S.noise(0.003, rng(86)) * 0.6
    return S.fade(S.normalize(x, 0.75))


@sound("outro_pwomp")
def outro_pwomp():
    """The slices creep up on a dying spring: a sad, deflated "pwomp"."""
    d = 0.55
    t = t_axis(d)
    f = 150 * (1 - 0.35 * (t / d) ** 0.7)
    x = S.saw(f, d) * 0.6 + np.sin(S.phase(f, len(t)))
    x = S.sweep_filter(x, lambda u: 60, lambda u: 700 - 450 * u) * S.env_adsr(d, 0.03, 0.1, 0.8, 0.2)
    t2 = t_axis(0.12)
    S.mix_at(x, np.sin(2 * np.pi * 75 * t2) * np.exp(-t2 / 0.04), 0, 0.6)
    return S.fade(S.normalize(x, 0.8))


@sound("outro_oh")
def outro_oh():
    """Grandma, shocked: "Oh!", jumping up."""
    def pitch(u):
        return 280 + 260 * np.clip(u * 5, 0, 1) - 60 * u

    def formants(u):
        return [480 + 0 * u, 820 + 0 * u, 2700 + 0 * u]
    return _granny(0.32, pitch, formants, 87, vib=(7.0, 0.02), drive=1.3)


@sound("outro_hmph")
def outro_hmph():
    """Grandma, disappointed: a huffy "Hmph.", falling."""
    r = rng(88)
    out = np.zeros(samples(0.5))
    def pitch(u):
        return 250 - 70 * u

    def formants(u):
        return [280 + 0 * u, 1200 + 0 * u, 2400 + 0 * u]
    S.mix_at(out, S.lowpass(_granny(0.26, pitch, formants, 89, breath=0.06), 1800), 0)
    S.mix_at(out, S.bandpass(S.noise(0.16, r), 600, 3000) * S.env_exp(0.16, 0.05), samples(0.22), 0.6)  # the "ph"
    return S.fade(S.normalize(out, 0.7))


@sound("outro_creak")
def outro_creak():
    """The photo tilting on its nail: a small wooden creak."""
    d = 0.5
    t = t_axis(d)
    rate = 30 + 25 * np.sin(np.pi * t / d)
    clicks = np.sin(S.phase(rate, len(t))) > 0.92
    x = S.bandpass(S.noise(d, rng(90)), 900, 3200) * clicks * S.bell(d, 0.5)
    x += 0.2 * S.bandpass(S.saw(380 + 60 * t / d, d), 500, 2500) * S.bell(d)
    return S.fade(S.normalize(x, 0.55))


@sound("outro_bzzzt")
def outro_bzzzt():
    """The power goes out all over town: a buzz that falls and dies (bzzzzt...)."""
    d = 0.75
    t = t_axis(d)
    f = 120 * (1 - 0.8 * (t / d) ** 0.8)
    buzz = S.square(f, d) * 0.5 + S.saw(f * 1.01, d) * 0.5
    buzz = S.lowpass(buzz, 2500) * (1 - (t / d) ** 1.5)
    crack = _crackle(0.12, 91, 120, 0.0001)
    S.mix_at(buzz, crack, 0, 0.6)
    return S.fade(S.normalize(S.distort(buzz, 1.6), 0.8))


@sound("outro_blink")
def outro_blink():
    """Two eyes opening in the dark: a tiny cartoon plink."""
    out = np.zeros(samples(0.2))
    for at, f in ((0.0, 2400), (0.05, 3200)):
        t = t_axis(0.08)
        S.mix_at(out, np.sin(2 * np.pi * f * t) * np.exp(-t / 0.02), samples(at), 0.7)
    return S.fade(S.normalize(out, 0.45))


@sound("outro_snicker")
def outro_snicker():
    """The rat's snicker in the dark: hee-hee-hee."""
    out = np.zeros(samples(0.6))
    for k in range(4):
        d = 0.07
        S.mix_at(out, _chirp(3300 - k * 150, 2600 - k * 150, d, 90), samples(k * 0.12), 0.8 - k * 0.12)
    return S.fade(S.normalize(out, 0.6))


@sound("outro_strike")
def outro_strike():
    """A match: scritch along the box, then the flare (fwoof)."""
    r = rng(92)
    out = np.zeros(samples(0.6))
    d = 0.09
    scratch = S.bandpass(S.noise(d, r), 2000, 9000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 90 * t_axis(d))))
    S.mix_at(out, scratch * S.bell(d, 0.4), 0)
    d2 = 0.45
    flare = S.sweep_filter(S.noise(d2, r), lambda u: 300 + 400 * u, lambda u: 2500 - 1200 * u) * S.env_exp(d2, 0.15, 0.01)
    S.mix_at(out, flare, samples(0.07), 0.8)
    for _ in range(6):
        S.mix_at(out, S.highpass(S.noise(0.004, r), 3000) * 0.4, samples(r.uniform(0.1, 0.5)))
    return S.fade(S.normalize(out, 0.75))


@sound("outro_huh")
def outro_huh():
    """Grandma, baffled: "Huh?"."""
    def pitch(u):
        return 240 + 200 * u ** 2

    def formants(u):
        return [620 + 0 * u, 1150 + 0 * u, 2500 + 0 * u]
    return _granny(0.36, pitch, formants, 93, breath=0.12)


@sound("outro_blow")
def outro_blow():
    """She blows the match out: fft."""
    d = 0.22
    x = S.sweep_filter(S.noise(d, rng(94)), lambda u: 600, lambda u: 5000 - 2000 * u) * S.env_exp(d, 0.07, 0.008)
    return S.fade(S.normalize(x, 0.6))


@sound("outro_heart")
def outro_heart():
    """The cooling towers puff a heart: a soft, round pomf far away, then a rising glassy "aww"."""
    r = rng(95)
    out = np.zeros(samples(1.1))
    t = t_axis(0.3)
    pomf = np.sin(S.phase(90 * (1 + 0.8 * np.exp(-t / 0.04)), len(t))) * np.exp(-t / 0.09)
    pomf += 0.6 * S.lowpass(S.noise(0.3, r), 700) * S.env_exp(0.3, 0.08, 0.01)
    S.mix_at(out, pomf, 0, 0.8)
    for k, note in enumerate((84, 88, 91, 96)):  # the heart swelling: a little harp-ish rise
        S.mix_at(out, S.glockenspiel(S.midi(note), 0.7, 0.35), samples(0.12 + k * 0.07), 0.35 + 0.08 * k)
    return S.fade(S.normalize(out, 0.6))


@sound("outro_wink")
def outro_wink():
    """Her grandson winks back from his photo: a bright cartoon "ting!" with a sparkle."""
    out = np.zeros(samples(0.7))
    S.mix_at(out, S.glockenspiel(S.midi(100), 0.6, 0.3), 0, 0.9)
    S.mix_at(out, S.glockenspiel(S.midi(107), 0.5, 0.2), samples(0.05), 0.5)
    S.mix_at(out, S.highpass(S.noise(0.35, rng(96)), 7000) * S.bell(0.35) * 0.08, samples(0.03))
    return S.fade(S.normalize(out, 0.55))


@sound("outro_rat_hmph")
def outro_rat_hmph():
    """The caged rat turns its back on her: a squeaky, huffy "hmph!" (a nasal hum falling, then the ph)."""
    r = rng(97)
    out = np.zeros(samples(0.45))

    def pitch(u):
        return 640 - 260 * u ** 0.8

    def formants(u):
        return [320 + 0 * u, 2100 + 0 * u, 3200 + 0 * u]
    hum = S.lowpass(_shout(0.2, pitch, formants, 98, vib=(9.0, 0.02), breath=0.04), 3500)
    S.mix_at(out, hum, 0)
    S.mix_at(out, S.bandpass(S.noise(0.11, r), 1800, 4500) * S.env_exp(0.11, 0.03) * S.bell(0.11, 0.3), samples(0.17),
             0.3)  # the "ph"
    return S.fade(S.normalize(out, 0.65))


@sound("outro_cough")
def outro_cough():
    """Sunny Acres coughs, far away: a muffled, gloopy "hu-KOFF" (the goo bubbling in it)."""
    r = rng(99)
    out = np.zeros(samples(1.2))
    for at, d, f, gain in ((0.0, 0.16, 70, 0.45), (0.2, 0.42, 58, 1.0)):
        t = t_axis(d)
        burst = S.lowpass(S.noise(d, r), 420) * S.env_exp(d, d * 0.35, 0.012)
        thump = np.sin(S.phase(f * (1 + 0.5 * np.exp(-t / 0.05)), len(t))) * np.exp(-t / (d * 0.5))
        glop = 1.0 + 0.5 * np.sin(2 * np.pi * 23 * t) * np.exp(-t / 0.2)  # the goo
        S.mix_at(out, S.fade((burst + 0.8 * thump) * glop, 0.004, d * 0.4), samples(at), gain)
    for k in range(6):  # bubbles popping after it
        t = t_axis(0.06)
        S.mix_at(out, np.sin(S.phase(300 + 140 * k + 500 * t / 0.06, len(t))) * S.bell(0.06) * 0.25,
                 samples(0.55 + k * 0.07 + r.uniform(0, 0.03)))
    return S.fade(S.normalize(S.lowpass(out, 1800), 0.8), 0.003, 0.2)


@sound("outro_click")
def outro_click():
    """A house's lights going out: a switch's tk and a tiny falling "bwip" (the power dying)."""
    out = np.zeros(samples(0.22))
    t = t_axis(0.03)
    S.mix_at(out, S.bandpass(S.noise(0.03, rng(100)), 1800, 7000) * np.exp(-t / 0.004), 0, 0.8)
    t2 = t_axis(0.16)
    S.mix_at(out, S.fade(np.sin(S.phase(900 * (1 - 0.6 * t2 / 0.16), len(t2))) * np.exp(-t2 / 0.05), 0.002, 0.06),
             samples(0.01), 0.5)
    return S.fade(S.normalize(out, 0.6))


@sound("outro_giggle")
def outro_giggle():
    """The last rat, by her ear in the dark: a small, close "hee-hee"."""
    out = np.zeros(samples(0.42))
    for k in range(3):
        S.mix_at(out, _chirp(3600 - k * 220, 2900 - k * 220, 0.06, 70), samples(k * 0.11), 0.75 - k * 0.15)
    return S.fade(S.normalize(S.lowpass(out, 6000), 0.5))


SFX_ONLY = set(SOUNDS)


# --- Main ----------------------------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    prefixes = [a for a in args if a not in ("sfx", "music")]
    want_sfx = not args or "sfx" in args or bool(prefixes)
    want_music = not args or "music" in args or bool(prefixes)
    if want_sfx:
        for name, fn in SOUNDS.items():
            if prefixes and not any(name.startswith(p) for p in prefixes):
                continue
            x = fn()
            S.write(os.path.join(SFX_DIR, name + ".ogg"), x)
            print("sfx   %-20s %5.2f s" % (name, len(x) / SR))
    if want_music:
        for name, x in music.render_all(prefixes):
            S.write(os.path.join(MUSIC_DIR, name + ".ogg"), x, quality=6)
            print("music %-20s %5.2f s" % (name, len(x) / SR))


if __name__ == "__main__":
    main()

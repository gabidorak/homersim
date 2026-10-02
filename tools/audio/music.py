"""The music (M7): a sneaky match theme in three synced layers, a lounge loop for the lobby, and
win/lose stingers. All synthesized (tools/audio/synth.py).

Match layers (client/music_director.gd plays them together and fades them with the plant alarm):
  match_calm      pizzicato walking bass, marimba melody, a ticking clock: always on in a match
  match_warning   + kick/snare, brass stabs, tremolo strings              (WARNING and CRITICAL)
  match_critical  + fast hats, toms, a siren lead, low brass hits          (CRITICAL)
All three are 16 bars at 120 BPM (32 s exactly), so they loop in lock-step.
"""
import numpy as np

import synth as S
from synth import SR, samples

BPM = 120.0
BEAT = 60.0 / BPM
BARS = 16
LOOP_S = BARS * 4 * BEAT

# A minor, two 8-bar phrases.
CHORDS = ["Am", "Am", "Dm", "Am", "F", "E7", "Am", "E7", "Am", "Am", "Dm", "Dm", "F", "E7", "Am", "E7"]
CHORD_NOTES = {  # bass root (MIDI) and chord tones (mid register)
    "Am": (45, [57, 60, 64]), "Dm": (50, [57, 62, 65]), "F": (41, [57, 60, 65]), "E7": (40, [56, 59, 62, 64]),
}
WALK = {  # pizzicato bass, one bar of quarter notes
    "Am": [45, 52, 57, 55], "Dm": [50, 45, 50, 48], "F": [41, 48, 53, 52], "E7": [40, 47, 52, 44],
}
# Marimba melody: per bar, (beat, MIDI note, length in beats).
MELODY = [
    [(0, 69, .5), (1, 72, .5), (1.5, 76, .5), (2.5, 75, .25), (2.75, 76, .75)],
    [(0.5, 72, .5), (1, 69, .5), (2, 64, 1.0)],
    [(0, 74, .5), (1, 77, .5), (1.5, 81, .5), (2.5, 80, .25), (2.75, 81, .75)],
    [(0.5, 76, .5), (1, 72, .5), (2, 69, 1.0)],
    [(0, 72, .5), (0.5, 77, .5), (1, 81, .5), (2, 79, .5), (2.5, 77, .5), (3, 76, .5)],
    [(0, 74, .5), (0.5, 76, .5), (1, 80, 1.0), (2.5, 83, .5), (3, 80, .5)],
    [(0, 81, .5), (1, 76, .5), (1.5, 72, .5), (2, 69, .5), (3, 71, .25), (3.25, 72, .25), (3.5, 74, .25), (3.75, 75, .25)],
    [(0, 76, 1.0), (1.5, 68, .5), (2, 71, .5), (3, 74, .5)],
    [(0, 69, .5), (1, 72, .5), (1.5, 76, .5), (2.5, 75, .25), (2.75, 76, .75)],
    [(0.5, 72, .5), (1, 69, .5), (2, 64, 1.0)],
    [(0, 74, .5), (1, 77, .5), (1.5, 81, .5), (2.5, 80, .25), (2.75, 81, .75)],
    [(0.5, 77, .5), (1, 74, .5), (2, 69, 1.0)],
    [(0, 72, .5), (0.5, 77, .5), (1, 81, .5), (2, 79, .5), (2.5, 77, .5), (3, 76, .5)],
    [(0, 74, .5), (0.5, 76, .5), (1, 80, 1.0), (2.5, 83, .5), (3, 80, .5)],
    [(0, 69, .5), (0.5, 72, .5), (1, 76, .5), (1.5, 81, 1.5)],
    [(0, 80, .5), (1, 76, .5), (2, 71, .5), (3, 68, .5)],
]


def pan(x, p):
    """Mono → stereo, p in -1 (left) .. 1 (right), constant power."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


class Track:
    """A stereo loop buffer notes are mixed into (wrapping at the end, so it loops seamlessly)."""

    def __init__(self, seconds, beat=BEAT):
        self.n = samples(seconds)
        self.buf = np.zeros((self.n, 2))
        self.beat = beat

    def add(self, x, at_beats, gain=1.0, p=0.0):
        st = pan(x * gain, p)
        at = samples(at_beats * self.beat)
        for ch in range(2):
            S.mix_loop(self.buf[:, ch], st[:, ch], at)

    def reverb(self, wet=0.18, decay=0.9, seed=7):
        """Circular convolution with a decaying-noise impulse (a small hall), so the tail wraps."""
        rng = np.random.default_rng(seed)
        n_ir = samples(decay * 1.5)
        t = np.arange(n_ir) / SR
        out = self.buf.copy()
        for ch in range(2):
            ir = rng.uniform(-1, 1, n_ir) * np.exp(-t / (decay / 3))
            ir[:samples(0.01)] = 0
            ir /= np.sqrt(np.sum(ir ** 2))
            size = self.n
            spec = np.fft.rfft(self.buf[:, ch], size) * np.fft.rfft(ir, size)
            out[:, ch] += wet * np.fft.irfft(spec, size)[:size]
        self.buf = out
        return self


# --- Match layers ----------------------------------------------------------------------------------------

def match_calm():
    tr = Track(LOOP_S)
    rng = np.random.default_rng(1)
    for bar, chord in enumerate(CHORDS):
        b0 = bar * 4
        for k, note in enumerate(WALK[chord]):
            tr.add(S.pluck(S.midi(note), BEAT * 1.2, 0.35, 0.995, rng), b0 + k, 0.9, -0.05)
        for beat, note, length in MELODY[bar]:
            tr.add(S.marimba(S.midi(note), max(0.3, length * BEAT * 1.6), 0.55), b0 + beat, 1.0, -0.25)
        for k in range(4):  # the clock: tick, tock
            tr.add(S.woodblock(1250 if k % 2 == 0 else 950, 0.18), b0 + k, 1.0, 0.35)
        for k in range(4):
            tr.add(S.hat(0.12, rng=rng), b0 + k + 0.5, 1.0, 0.4)
    return tr.reverb(0.15).buf


def match_warning():
    tr = Track(LOOP_S)
    rng = np.random.default_rng(2)
    for bar, chord in enumerate(CHORDS):
        b0 = bar * 4
        root, tones = CHORD_NOTES[chord]
        tr.add(S.kick(0.9), b0, 1.0)
        tr.add(S.kick(0.7), b0 + 2, 1.0)
        tr.add(S.snare(0.55, rng), b0 + 1, 1.0, 0.1)
        tr.add(S.snare(0.55, rng), b0 + 3, 1.0, 0.1)
        for k in (1.5, 3.5):  # brass stabs on the off-beats
            stab = sum(S.brass(S.midi(n), BEAT * 0.4, 0.5, 1800) for n in tones[:3])
            tr.add(stab, b0 + k, 0.7, -0.35)
        for k in range(16):  # tremolo strings: chord tones in sixteenths, swelling over the bar
            n = tones[1 + (k // 2) % 2] + 12
            x = S.lowpass(S.saw(S.midi(n), BEAT * 0.24), 1400) * S.env_adsr(BEAT * 0.24, 0.01, 0.02, 0.8, 0.03)
            tr.add(x, b0 + k * 0.25, 0.10 + 0.08 * (k / 16), 0.45)
        tr.add(S.tuba(S.midi(root), BEAT * 0.45, 0.8), b0, 0.6, 0.0)
        tr.add(S.tuba(S.midi(root + 7), BEAT * 0.45, 0.8), b0 + 2, 0.6, 0.0)
    return tr.reverb(0.12).buf


def match_critical():
    tr = Track(LOOP_S)
    rng = np.random.default_rng(3)
    for bar, chord in enumerate(CHORDS):
        b0 = bar * 4
        root, tones = CHORD_NOTES[chord]
        for k in range(16):
            tr.add(S.hat(0.5 if k % 2 else 0.3, rng=rng), b0 + k * 0.25, 1.0, 0.45)
        tr.add(S.kick(1.0), b0 + 1, 1.0)
        tr.add(S.kick(1.0), b0 + 3, 1.0)
        low = sum(S.brass(S.midi(n - 12), BEAT * 0.9, 0.7, 1200) for n in tones[:3])
        tr.add(low, b0, 0.8, -0.2)
        # Siren lead: glides between the chord's top tone and the root, two beats each way.
        hi, lo = S.midi(tones[-1] + 12), S.midi(root + 36)
        d = BEAT * 4
        t = np.arange(samples(d)) / SR
        f = lo + (hi - lo) * (0.5 - 0.5 * np.cos(2 * np.pi * t / (BEAT * 4)))
        siren = (S.sine(f, d) + 0.3 * S.sine(f * 2, d)) * S.env_adsr(d, 0.05, 0.1, 0.9, 0.1)
        tr.add(siren, b0, 0.16, 0.3)
        if bar % 4 == 3:  # tom fill into the next phrase
            for k, fr in enumerate((180, 150, 120, 95)):
                tr.add(S.tom(fr, 0.8), b0 + 3 + k * 0.25, 1.0, -0.3 + 0.2 * k)
    return tr.reverb(0.1).buf


# --- Lobby: elevator lounge in F, 100 BPM -----------------------------------------------------------------

LOBBY_BPM = 100.0
LOBBY_BEAT = 60.0 / LOBBY_BPM
LOBBY_CHORDS = [  # (bass root, chord tones) per half bar
    (41, [57, 60, 64, 65]), (41, [57, 60, 64, 65]), (40, [55, 59, 62, 64]), (45, [55, 57, 61, 64]),
    (38, [57, 60, 62, 65]), (38, [57, 60, 62, 65]), (36, [55, 58, 60, 63]), (41, [57, 60, 63, 65]),
    (46, [57, 58, 62, 65]), (46, [57, 58, 62, 65]), (46, [56, 58, 61, 67]), (46, [56, 58, 61, 67]),
    (45, [55, 57, 60, 64]), (38, [54, 57, 60, 62]), (43, [53, 55, 58, 62]), (36, [52, 55, 58, 60]),
]
LOBBY_MELODY = [  # (beat, note, beats) over 8 bars, played twice (second time an octave up in places)
    (0, 76, 1.5), (1.5, 77, 0.5), (2, 79, 2), (4, 77, 1), (5, 76, 1), (6, 74, 2),
    (8, 72, 1.5), (9.5, 74, 0.5), (10, 76, 2), (12, 74, 1), (13, 72, 1), (14, 69, 2),
    (16, 70, 1.5), (17.5, 72, 0.5), (18, 74, 2), (20, 73, 1), (21, 70, 1), (22, 68, 2),
    (24, 69, 1), (25, 72, 1), (26, 76, 1), (27, 74, 1), (28, 72, 3),
]


def lobby():
    bars = 16
    tr = Track(bars * 4 * LOBBY_BEAT, LOBBY_BEAT)
    rng = np.random.default_rng(4)
    for half in range(bars * 2):
        root, tones = LOBBY_CHORDS[half % len(LOBBY_CHORDS)]
        b0 = half * 2
        for at, length in ((0, 0.9), (0.75, 0.5), (1.5, 0.45)):  # bossa comping
            chord = sum(S.epiano(S.midi(n), length * LOBBY_BEAT * 2.5, 0.5) for n in tones)
            tr.add(chord, b0 + at, 0.35, -0.2)
        tr.add(S.pluck(S.midi(root), LOBBY_BEAT * 1.4, 0.2, 0.996, rng), b0, 0.9)
        tr.add(S.pluck(S.midi(root + 7), LOBBY_BEAT * 1.0, 0.2, 0.996, rng), b0 + 1.5, 0.7)
        for k in range(4):  # shaker
            tr.add(S.hat(0.15 if k % 2 else 0.08, rng=rng), b0 + k * 0.5, 1.0, 0.35)
    for rep in range(2):
        for beat, note, length in LOBBY_MELODY:
            n = note + (12 if rep == 1 and beat >= 16 else 0)
            tr.add(S.flute(S.midi(n), length * LOBBY_BEAT * 0.95, 0.7), rep * 32 + beat, 0.6, 0.15)
    return tr.reverb(0.25, 1.4).buf


# --- Stingers ---------------------------------------------------------------------------------------------

def stinger_win():
    beat = 0.14
    out = Track(2.8, beat)
    for k, note in enumerate((72, 76, 79, 84)):
        out.add(S.brass(S.midi(note), beat * 1.2, 0.8, 3000), k, 0.6, -0.1)
        out.add(S.xylophone(S.midi(note + 12), 0.3), k, 0.4, 0.3)
    chord = sum(S.brass(S.midi(n), 1.6, 0.8, 3200) for n in (60, 64, 67, 72, 76))
    out.add(chord, 5, 0.45)
    out.add(S.cymbal(1.8, 0.5), 5, 1.0, 0.2)
    out.add(S.kick(1.0), 5, 0.8)
    buf = out.buf
    buf[-samples(0.3):] *= np.linspace(1, 0, samples(0.3))[:, None]
    return buf


def stinger_lose():
    """The cartoon fail: "wah, wah, wah, waaah" on a muted trombone."""
    out = Track(3.4, 1.0)
    for k, (note, d) in enumerate(((55, 0.5), (54, 0.5), (53, 0.5), (52, 1.6))):
        t = np.arange(samples(d)) / SR
        vib = 1 + (0.012 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.3) / 0.3, 0, 1) if d > 1 else 0)
        x = S.saw(S.midi(note) * vib, d) + 0.6 * S.saw(S.midi(note) * 1.004 * vib, d)
        x = S.sweep_filter(x, lambda u: 80, lambda u, d=d: 500 + 1400 * np.sin(np.pi * min(1.0, u * (1.6 if d < 1 else 1.0))))
        x *= S.env_adsr(d, 0.04, 0.1, 0.85, 0.15)
        out.add(x, [0.0, 0.55, 1.1, 1.65][k], 0.6)
    buf = out.buf
    buf[-samples(0.2):] *= np.linspace(1, 0, samples(0.2))[:, None]
    return buf


def _master(stems, level=0.85):
    """Scales stems together so their sum peaks at `level` (keeps the layers' balance)."""
    total = sum(stems)
    m = np.max(np.abs(total))
    return [s * (level / m) for s in stems]


def render_all():
    calm, warning, critical = _master([match_calm(), match_warning(), match_critical()])
    yield "match_calm", calm
    yield "match_warning", warning
    yield "match_critical", critical
    yield "lobby", S.normalize(lobby(), 0.75)
    yield "stinger_win", S.normalize(stinger_win(), 0.85)
    yield "stinger_lose", S.normalize(stinger_lose(), 0.85)

"""The music (M7): a sneaky match theme in three synced layers, a lounge loop for the lobby, win/lose
stingers, and the score of the intro cinematic. All synthesized (tools/audio/synth.py).

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


# --- Intro: the cinematic before the menu (client/intro/intro.gd) ----------------------------------------
# Written to the intro's clock, in seconds: each section starts on a cue of intro.gd's timeline (the
# trip, the splash, the POOFs, the alarm, the BONK). Move a cue there, move it here too.

INTRO_S = 18.6
INTRO_TRIP = 5.9  # the record scratch
INTRO_SPLASH = 7.55
INTRO_POOFS = 9.2  # three POOFs, 0.25 s apart (sound effects): the riser ends on the reveal
INTRO_REVEAL = 9.95  # "DUN-DUN-DUNNN": three rats
INTRO_CHASE = 10.45  # EEK: the chase starts, 160 BPM...
INTRO_CHASE_BEAT = 60.0 / 160.0
INTRO_ALARM = INTRO_CHASE + 8 * INTRO_CHASE_BEAT  # ...the alarm on the 3rd bar's downbeat (13.45 s)
INTRO_BONK = INTRO_CHASE + 14.5 * INTRO_CHASE_BEAT  # ...and everything stops on the BONK (15.89 s)
INTRO_CODA = 16.2  # "wah, wah, wah, waaah"


class Score(Track):
    """A track that plays once: positions in seconds, nothing wraps around (notes, reverb tail)."""

    def __init__(self, seconds):
        super().__init__(seconds, 1.0)

    def add(self, x, at, gain=1.0, p=0.0):
        st = pan(x * gain, p)
        for ch in range(2):
            S.mix_at(self.buf[:, ch], st[:, ch], samples(at))

    def reverb(self, wet=0.18, decay=0.9, seed=7):
        rng = np.random.default_rng(seed)
        n_ir = samples(decay * 1.5)
        t = np.arange(n_ir) / SR
        size = 1 << int(np.ceil(np.log2(self.n + n_ir)))
        out = self.buf.copy()
        for ch in range(2):
            ir = rng.uniform(-1, 1, n_ir) * np.exp(-t / (decay / 3))
            ir[:samples(0.01)] = 0
            ir /= np.sqrt(np.sum(ir ** 2))
            spec = np.fft.rfft(self.buf[:, ch], size) * np.fft.rfft(ir, size)
            out[:, ch] += wet * np.fft.irfft(spec, size)[:self.n]
        self.buf = out
        return self


def _strings(notes, dur, vel=1.0, attack=0.25, cutoff=1600):
    """A soft string section holding a chord (detuned saws, slow bow)."""
    x = sum(S.saw(S.midi(n) * d, dur) for n in notes for d in (0.997, 1.003))
    x = S.lowpass(x, cutoff, 2)
    return x * S.env_adsr(dur, attack, 0.1, 0.9, min(0.3, dur * 0.3)) * vel * 0.1


def _tremolo(freq, dur, vel=1.0, rate=13.0):
    """Bowed tremolo on one note (`freq` may be an array: a glissando)."""
    t = np.arange(samples(dur)) / SR
    x = S.lowpass(S.saw(freq, dur) + S.saw(np.asarray(freq) * 1.004, dur), 2600, 2)
    bow = S.lowpass(0.55 + 0.45 * np.sign(np.sin(2 * np.pi * rate * t)), 90, 1)
    return x * bow * S.env_adsr(dur, 0.05, 0.1, 0.9, 0.08) * vel * 0.16


def _choir(note, dur, vel=1.0, vowel=(730, 1090, 2440)):
    """An "aaah" voice (a buzz through vowel formants, with vibrato)."""
    t = np.arange(samples(dur)) / SR
    f = S.midi(note) * (1 + 0.012 * np.sin(2 * np.pi * 5.2 * t + note))
    y = S.resonator(S.lowpass(S.saw(f, dur), 3500, 1), list(vowel), [80, 90, 120])
    return S.normalize(y, 1.0) * S.env_adsr(dur, 0.35, 0.2, 0.85, 0.15) * vel * 0.3


def _timpani(note, dur=1.2, vel=1.0, rng=None):
    t = np.arange(samples(dur)) / SR
    f = S.midi(note) * (1 + 0.12 * np.exp(-t / 0.04))
    x = np.sin(S.phase(f, len(t))) * np.exp(-t / 0.45)
    x += 0.35 * S.bandpass(S.noise(dur, rng), 80, 900) * np.exp(-t / 0.03)
    return x * vel


def _scratch(dur=0.32, rng=None):
    """A record scratch: the needle dragged back and forth ("wikka")."""
    t = np.arange(samples(dur)) / SR
    hand = np.sin(np.pi * 3.0 * t / dur) ** 2
    f = 220 + 1300 * hand
    x = 0.5 * S.saw(f, dur) + 0.6 * S.noise(dur, rng)
    x = S.sweep_filter(x, lambda u: 300 + 900 * np.sin(np.pi * 3.0 * u) ** 2, lambda u: 2500 + 3500 * u)
    return x * S.env_adsr(dur, 0.005, 0.05, 0.8, 0.06)


def intro():
    sc = Score(INTRO_S)
    rng = np.random.default_rng(11)

    # A. The good old days (0 - 4.35 s): a music box tune in F, pizzicato, a ukulele-ish strum, soft
    #    strings and a shaker. 120 BPM.
    b = 0.5
    chords = [(0, 4, [53, 57, 60]), (4, 2, [53, 58, 62]), (6, 2, [52, 55, 58, 60]), (8, 0.8, [53, 57, 60])]
    for b0, nb, tones in chords:
        sc.add(_strings(tones, nb * b + 0.35, 0.9, attack=0.3), b0 * b, 1.0)
    for k, n in enumerate([41, 48, 45, 48, 46, 41, 48, 52, 41]):
        sc.add(S.pluck(S.midi(n), b * 1.1, 0.35, 0.995, rng), k * b, 0.9, -0.1)
    for k in range(8):
        tones = chords[0][2] if k < 4 else (chords[1][2] if k < 6 else chords[2][2])
        strum = sum(S.pluck(S.midi(n + 12), b * 0.45, 0.6, 0.99, rng) for n in tones)
        sc.add(strum, (k + 0.5) * b + 0.01, 0.22, 0.3)
    melody = [(0, 84, .5), (.5, 81, .5), (1, 77, .5), (1.5, 81, .5), (2, 84, 1), (3, 86, .5), (3.5, 84, .5),
              (4, 82, .5), (4.5, 86, .5), (5, 89, 1), (6, 88, .5), (6.5, 86, .5), (7, 84, .5), (7.5, 82, .5),
              (8, 81, 1.4)]
    for beat, n, length in melody:
        sc.add(S.glockenspiel(S.midi(n), max(0.7, length * b * 2.5), 0.5), beat * b, 0.42, -0.25)
    for k in range(9):
        sc.add(S.hat(0.1 if k % 2 else 0.06, rng=rng), (k + 0.5) * b, 1.0, 0.35)

    # B. The new guy (4.35 - 5.9 s), whistling (a sound effect): a creeping chromatic walk-up on
    #    pizzicato and tuba, the tick-tock of the match theme's clock, strings holding their breath.
    for k in range(4):
        at = 4.35 + k * 0.38
        sc.add(S.pluck(S.midi(41 + k), 0.4, 0.3, 0.99, rng), at, 0.9)
        sc.add(S.tuba(S.midi(41 + k), 0.2, 0.7), at, 0.45)
        sc.add(S.woodblock(1250 if k % 2 == 0 else 950, 0.5), at, 0.9, 0.35)
    sc.add(_strings([72, 77], 1.55, 0.7, attack=1.0, cutoff=2400), 4.38, 0.8, 0.2)

    # C. The trip: a record scratch, and a beat of silence.
    sc.add(_scratch(0.32, rng), INTRO_TRIP - 0.02, 0.75)

    # D. Slow motion (6.05 - 7.55 s): a choir swelling, high tremolo creeping up, a soft boom; the
    #    splash hits with a crash and a timpani.
    d = INTRO_SPLASH - 6.02
    for n in (57, 64, 69, 72):
        sc.add(_choir(n, d + 0.1) * np.linspace(0.45, 1.0, samples(d + 0.1)), 6.02, 0.8, (n - 64) / 20)
    t = np.arange(samples(d)) / SR
    sc.add(_tremolo(S.midi(88) * 2 ** (t / d / 12), d), 6.02, 0.7, 0.4)
    sc.add(_tremolo(S.midi(89) * 2 ** (t / d / 12), d), 6.02, 0.5, -0.4)
    sc.add(_timpani(33, 1.4, 0.6, rng), 6.02, 1.0)
    sc.add(S.cymbal(1.8, 0.7, rng), INTRO_SPLASH, 0.9, 0.2)
    sc.add(_timpani(33, 1.6, 1.0, rng), INTRO_SPLASH, 1.0)

    # E. Something is happening (7.6 - 9.95 s): a dark organ cluster, a radioactive wobble speeding up,
    #    a heartbeat on the timpani, tremolo strings climbing, a riser into the reveal.
    dur = INTRO_REVEAL - 7.6
    t = np.arange(samples(dur)) / SR
    sc.add((S.organ(S.midi(33), dur, 0.7) + S.organ(S.midi(34), dur, 0.45)) * np.linspace(0.6, 1.0, len(t)), 7.6,
           0.8)
    rate = 2.0 + 7.0 * (t / dur) ** 1.5
    wobble = S.lowpass(S.saw(S.midi(45), dur) + S.saw(S.midi(45) * 1.006, dur), 900, 2)
    wobble *= 0.5 + 0.5 * np.sin(S.phase(rate, len(t)))
    sc.add(wobble * np.linspace(0.3, 1.0, len(t)) * 0.25, 7.6, 1.0, -0.2)
    for at in (7.95, 8.45, 8.85, 9.12):
        sc.add(_timpani(36, 0.5, 0.7, rng), at, 1.0)
        sc.add(_timpani(36, 0.5, 0.45, rng), at + 0.13, 1.0)
    climb = S.midi(76) * 2 ** (3 * (t / dur) / 12)
    sc.add(_tremolo(climb, dur, 1.0) * np.linspace(0.3, 1.0, len(t)), 7.6, 0.7, 0.35)
    sc.add(_tremolo(climb * 2 ** (1 / 12), dur, 1.0) * np.linspace(0.3, 1.0, len(t)), 7.6, 0.6, -0.35)
    rise = INTRO_REVEAL - 8.9
    tr = np.arange(samples(rise)) / SR
    riser = S.sweep_filter(S.noise(rise, rng), lambda u: 300 + 3000 * u ** 2, lambda u: 1500 + 7000 * u ** 2)
    riser += 0.4 * S.sine(200 * 2 ** (3 * tr / rise), rise)
    sc.add(riser * (tr / rise) ** 2 * 0.35, 8.9, 1.0)

    # F. The reveal (9.95 s): DUN - DUN - DUNNN, low brass and timpani.
    for k, (notes, length) in enumerate((([45, 52, 57, 60], 0.15), ([46, 53, 58, 62], 0.15), ([45, 52, 57, 60], 0.5))):
        at = INTRO_REVEAL + k * 0.17
        stab = sum(S.brass(S.midi(n), length, 0.9, 1800) for n in notes)
        sc.add(stab, at, 0.9)
        sc.add(_timpani(33 if k != 1 else 34, 0.6, 1.0, rng), at, 0.9)
    sc.add(S.cymbal(1.2, 0.6, rng), INTRO_REVEAL + 0.34, 0.7, 0.2)

    # G. The chase (10.45 - 15.89 s), 160 BPM in A minor: drums, an octave-jumping bass, the match
    #    theme's sneaky motif on xylophone; at the alarm the critical layer's siren lead comes in;
    #    everything stops dead on the BONK.
    cb = INTRO_CHASE_BEAT

    def at(beat):
        return INTRO_CHASE + beat * cb

    for k in range(15):
        if at(k) >= INTRO_BONK:
            break
        sc.add(S.kick(1.0 if k % 2 == 0 else 0.7), at(k), 0.9)
        if k % 2 == 1:
            sc.add(S.snare(0.7, rng), at(k), 0.9, 0.1)
    for k in range(29):  # hats: eighths, sixteenths from the alarm on
        sub = 2 if at(k / 2) < INTRO_ALARM else 4
        for j in range(sub // 2):
            when = at(k / 2 + j / sub)
            if when < INTRO_BONK:
                sc.add(S.hat(0.35 if (k + j) % 2 else 0.2, rng=rng), when, 1.0, 0.45)
    for j in range(8):  # a snare roll into the alarm
        sc.add(S.snare(0.25 + 0.06 * j, rng), at(7 + j / 8), 0.8, 0.1)
    walk = [45, 57, 45, 57, 43, 55, 44, 56]
    for k in range(29):
        when = at(k / 2)
        if when >= INTRO_BONK:
            break
        sc.add(S.pluck(S.midi(walk[k % 8]), cb * 0.6, 0.45, 0.99, rng), when, 0.85, -0.05)
        if k % 2 == 0:
            sc.add(S.tuba(S.midi(walk[k % 8]), cb * 0.4, 0.6), when, 0.35)
    motif = [(0, 69, .5), (1, 72, .5), (1.5, 76, .5), (2.5, 75, .25), (2.75, 76, .75), (4.5, 72, .5), (5, 69, .5),
             (6, 64, 1.0)]
    for beat, n, length in motif:
        sc.add(S.xylophone(S.midi(n + 12), 0.35), at(beat), 0.55, -0.3)
        sc.add(S.marimba(S.midi(n), max(0.25, length * cb * 1.5), 0.6), at(beat), 0.5, -0.2)
    for beat in (5.5, 7.5, 9.5, 11.5, 13.5):  # brass stabs on the off-beats
        stab = sum(S.brass(S.midi(n), cb * 0.4, 0.7, 2000) for n in (57, 60, 64))
        sc.add(stab, at(beat), 0.55, -0.35)
    siren_d = INTRO_BONK - INTRO_ALARM
    ts = np.arange(samples(siren_d)) / SR
    hi, lo = S.midi(76), S.midi(69)
    f = lo + (hi - lo) * (0.5 - 0.5 * np.cos(2 * np.pi * ts / (cb * 4)))
    siren = (S.sine(f, siren_d) + 0.3 * S.sine(f * 2, siren_d)) * S.env_adsr(siren_d, 0.05, 0.1, 0.9, 0.02)
    sc.add(siren, INTRO_ALARM, 0.2, 0.3)
    sc.add(sum(_tremolo(S.midi(n), siren_d, 0.8) for n in (69, 72, 76)), INTRO_ALARM, 0.6, -0.4)
    hit = sum(S.brass(S.midi(n), 0.35, 1.0, 2400) for n in (45, 57, 60, 64))
    sc.add(hit, INTRO_BONK, 0.9)
    sc.add(S.cymbal(0.5, 0.8, rng) * S.env_exp(0.5, 0.08), INTRO_BONK, 0.9, 0.2)

    # H. The coda (16.2 s): the game's cartoon fail, "wah, wah, wah, waaah", on a muted trombone.
    for k, (note, length) in enumerate(((55, 0.4), (54, 0.4), (53, 0.4), (52, 1.05))):
        tl = np.arange(samples(length)) / SR
        vib = 1 + (0.012 * np.sin(2 * np.pi * 5.5 * tl) * np.clip((tl - 0.3) / 0.3, 0, 1) if length > 1 else 0)
        x = S.saw(S.midi(note) * vib, length) + 0.6 * S.saw(S.midi(note) * 1.004 * vib, length)
        x = S.sweep_filter(x, lambda u: 80, lambda u, ln=length: 500 + 1400 * np.sin(np.pi * min(1.0, u * (1.6 if ln < 1 else 1.0))))
        x *= S.env_adsr(length, 0.04, 0.1, 0.85, 0.15)
        sc.add(x, INTRO_CODA + k * 0.42, 0.55)
    buf = sc.reverb(0.16, 1.1).buf
    buf[-samples(0.3):] *= np.linspace(1, 0, samples(0.3))[:, None]
    return buf


def _master(stems, level=0.85):
    """Scales stems together so their sum peaks at `level` (keeps the layers' balance)."""
    total = sum(stems)
    m = np.max(np.abs(total))
    return [s * (level / m) for s in stems]


def render_all(only=()):
    """(name, stereo buffer) for each piece; `only`: name prefixes to render (none = everything)."""
    def wanted(name):
        return not only or any(name.startswith(p) for p in only)
    if any(wanted(n) for n in ("match_calm", "match_warning", "match_critical")):
        stems = _master([match_calm(), match_warning(), match_critical()])
        for name, x in zip(("match_calm", "match_warning", "match_critical"), stems):
            if wanted(name):
                yield name, x
    for name, fn, level in (("lobby", lobby, 0.75), ("stinger_win", stinger_win, 0.85),
                            ("stinger_lose", stinger_lose, 0.85), ("intro", intro, 0.8)):
        if wanted(name):
            yield name, S.normalize(fn(), level)

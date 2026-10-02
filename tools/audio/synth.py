"""Tiny numpy synthesizer used by make_audio.py: oscillators, envelopes, FFT filters, a few
instruments, and an .ogg writer (ffmpeg + libvorbis). Everything is mono float64 in -1..1 at SR,
except music stems, which are (n, 2) stereo arrays."""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
RNG = np.random.default_rng(1234)


def seconds(n):
    return n / SR


def samples(dur):
    return int(round(dur * SR))


def t_axis(dur):
    return np.arange(samples(dur)) / SR


# --- Oscillators (frequency may be an array: per-sample frequency, phase is integrated) ----------

def phase(freq, n):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return 2 * np.pi * np.cumsum(f) / SR


def sine(freq, dur):
    n = samples(dur)
    return np.sin(phase(freq, n))


def saw(freq, dur):
    n = samples(dur)
    p = phase(freq, n) / (2 * np.pi)
    return 2.0 * (p - np.floor(p + 0.5))


def square(freq, dur, duty=0.5):
    n = samples(dur)
    p = phase(freq, n) / (2 * np.pi)
    return np.where((p - np.floor(p)) < duty, 1.0, -1.0)


def tri(freq, dur):
    return 2.0 * np.abs(saw(freq, dur)) - 1.0


def noise(dur, rng=None):
    return (rng or RNG).uniform(-1, 1, samples(dur))


# --- Envelopes --------------------------------------------------------------------------------------

def env_exp(dur, tau, attack=0.002):
    t = t_axis(dur)
    e = np.exp(-t / max(tau, 1e-4))
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def env_adsr(dur, a=0.01, d=0.05, s=0.7, r=0.05):
    n = samples(dur)
    t = np.arange(n) / SR
    e = np.ones(n) * s
    e = np.where(t < a, t / max(a, 1e-5), e)
    dmask = (t >= a) & (t < a + d)
    e[dmask] = 1.0 - (1.0 - s) * (t[dmask] - a) / max(d, 1e-5)
    rel = t > dur - r
    e[rel] *= np.clip((dur - t[rel]) / max(r, 1e-5), 0, 1)
    return e


def bell(dur, power=1.0):
    """0 → 1 → 0 sine-shaped envelope."""
    return np.sin(np.pi * np.linspace(0, 1, samples(dur))) ** power


def fade(x, fin=0.003, fout=0.01):
    x = x.copy()
    a, b = samples(fin), samples(fout)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


# --- Filters (zero-phase FFT; fine for one-shots and whole notes) ------------------------------------

def _fft_filter(x, response):
    n = len(x)
    size = 1 << int(np.ceil(np.log2(max(n, 2))))
    spec = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1 / SR)
    return np.fft.irfft(spec * response(f), size)[:n]


def lowpass(x, cutoff, order=2):
    return _fft_filter(x, lambda f: 1 / np.sqrt(1 + (f / max(cutoff, 1)) ** (2 * order)))


def highpass(x, cutoff, order=2):
    return _fft_filter(x, lambda f: 1 / np.sqrt(1 + (max(cutoff, 1) / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def peak(x, centre, q=4.0, gain=1.0):
    """Adds a resonant bump around `centre` Hz."""
    return _fft_filter(x, lambda f: 1 + gain / (1 + ((f - centre) / (centre / q)) ** 2))


def sweep_filter(x, lo_curve, hi_curve, block=0.02):
    """Time-varying band-pass: per block (Hann overlap-add), the band goes from lo_curve(t) to
    hi_curve(t) (functions of 0..1 progress)."""
    n = len(x)
    size = samples(block)
    hop = size // 2
    win = np.hanning(size)
    out = np.zeros(n + size)
    for start in range(0, n, hop):
        seg = np.zeros(size)
        chunk = x[start:start + size]
        seg[:len(chunk)] = chunk
        u = start / max(n - 1, 1)
        y = bandpass(seg * win, lo_curve(u), hi_curve(u))
        out[start:start + size] += y
    return out[:n]


def resonator(x, freqs, bws):
    """Time-varying two-pole resonators in series-parallel (formants): freqs/bws are arrays (one
    value per sample) or scalars, per formant. Sample loop: keep inputs short."""
    n = len(x)
    out = np.zeros(n)
    for fr, bw in zip(freqs, bws):
        fr = np.broadcast_to(np.asarray(fr, float), (n,))
        bw = np.broadcast_to(np.asarray(bw, float), (n,))
        r = np.exp(-np.pi * bw / SR)
        a1 = -2 * r * np.cos(2 * np.pi * fr / SR)
        a2 = r * r
        g = 1 - r
        y1 = y2 = 0.0
        y = np.zeros(n)
        for i in range(n):
            v = g[i] * x[i] - a1[i] * y1 - a2[i] * y2
            y2, y1 = y1, v
            y[i] = v
        out += y
    return out


def distort(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def normalize(x, level=0.9):
    m = np.max(np.abs(x))
    return x * (level / m) if m > 0 else x


def mix_at(buf, x, at, gain=1.0):
    """Adds `x` into `buf` starting at sample `at` (clipped to the buffer)."""
    if at >= len(buf):
        return
    end = min(len(buf), at + len(x))
    buf[at:end] += x[:end - at] * gain


def mix_loop(buf, x, at, gain=1.0):
    """Like mix_at, but what runs past the end wraps to the start (seamless loops)."""
    n = len(buf)
    for k in range(0, len(x), n):
        part = x[k:k + n]
        s = (at + k) % n
        first = min(len(part), n - s)
        buf[s:s + first] += part[:first] * gain
        if first < len(part):
            buf[:len(part) - first] += part[first:] * gain


def loopable(x, xfade=0.05):
    """Makes a sound loop seamlessly by crossfading its tail into its head (shortens it)."""
    k = samples(xfade)
    head = x[:k] * np.linspace(0, 1, k)
    tail = x[-k:] * np.linspace(1, 0, k)
    y = x[:-k].copy()
    y[:k] = head + tail
    return y


# --- Instruments --------------------------------------------------------------------------------------

def midi(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def pluck(freq, dur, brightness=0.5, decay=0.996, rng=None):
    """Karplus-Strong string (pizzicato, plucked bass)."""
    rng = rng or RNG
    n = samples(dur)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    buf = lowpass(buf, 2000 + 8000 * brightness, 1) if period > 8 else buf
    out = np.zeros(n)
    idx = 0
    prev = 0.0
    for i in range(n):
        v = buf[idx]
        nv = decay * 0.5 * (v + prev)
        prev = v
        buf[idx] = nv
        out[i] = v
        idx = (idx + 1) % period
    return fade(out, 0.001, 0.02)


def marimba(freq, dur, vel=1.0):
    t = t_axis(dur)
    x = (np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.35)
         + 0.35 * np.sin(2 * np.pi * freq * 3.9 * t) * np.exp(-t / 0.06)
         + 0.12 * np.sin(2 * np.pi * freq * 9.8 * t) * np.exp(-t / 0.015))
    return fade(x * vel, 0.001, 0.03)


def xylophone(freq, dur, vel=1.0):
    t = t_axis(dur)
    x = (np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.18)
         + 0.5 * np.sin(2 * np.pi * freq * 3.0 * t) * np.exp(-t / 0.05))
    return fade(x * vel, 0.0005, 0.02)


def tuba(freq, dur, vel=1.0):
    """Brassy oompah bass: saw through a low-pass that opens at the attack."""
    x = saw(freq, dur) * 0.6 + sine(freq, dur) * 0.6
    x = lowpass(x, freq * 5, 2)
    return fade(x * env_adsr(dur, 0.02, 0.08, 0.6, 0.06) * vel, 0.002, 0.02)


def brass(freq, dur, vel=1.0, cutoff=2400):
    x = saw(freq, dur) + saw(freq * 1.006, dur) * 0.7 + saw(freq * 0.994, dur) * 0.7
    x = lowpass(x, cutoff, 2)
    return fade(x * env_adsr(dur, 0.03, 0.1, 0.7, 0.08) * vel * 0.4, 0.002, 0.02)


def organ(freq, dur, vel=1.0):
    x = sum(a * sine(freq * h, dur) for h, a in ((1, 1.0), (2, 0.5), (3, 0.25), (4, 0.15), (6, 0.08)))
    return fade(x * env_adsr(dur, 0.04, 0.1, 0.8, 0.1) * vel * 0.35, 0.002, 0.03)


def epiano(freq, dur, vel=1.0):
    """Electric-piano-ish FM bell (lounge chords)."""
    t = t_axis(dur)
    mod = np.sin(2 * np.pi * freq * t) * 1.2 * np.exp(-t / 0.4)
    x = np.sin(2 * np.pi * freq * t + mod) * np.exp(-t / 1.2)
    return fade(x * vel * 0.5, 0.002, 0.05)


def flute(freq, dur, vel=1.0):
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t_axis(dur))
    x = sine(freq * vib, dur) + 0.15 * sine(2 * freq * vib, dur) + 0.04 * lowpass(noise(dur), 3000)
    return fade(x * env_adsr(dur, 0.06, 0.1, 0.8, 0.12) * vel * 0.5, 0.002, 0.03)


def kick(vel=1.0):
    dur = 0.35
    t = t_axis(dur)
    f = 50 + 110 * np.exp(-t / 0.03)
    x = np.sin(phase(f, len(t))) * np.exp(-t / 0.12)
    x[:samples(0.003)] += noise(0.003) * 0.3
    return x * vel


def snare(vel=1.0, rng=None):
    dur = 0.25
    t = t_axis(dur)
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04)
    rattle = bandpass(noise(dur, rng), 1500, 9000) * np.exp(-t / 0.07)
    return (body * 0.6 + rattle * 1.1) * vel


def hat(vel=1.0, open_=False, rng=None):
    dur = 0.3 if open_ else 0.06
    t = t_axis(dur)
    x = highpass(noise(dur, rng), 7000) * np.exp(-t / (0.12 if open_ else 0.018))
    return x * vel


def tom(freq, vel=1.0):
    dur = 0.4
    t = t_axis(dur)
    f = freq * (1 + 0.6 * np.exp(-t / 0.05))
    return np.sin(phase(f, len(t))) * np.exp(-t / 0.15) * vel


def cymbal(dur=1.6, vel=1.0, rng=None):
    t = t_axis(dur)
    return bandpass(noise(dur, rng), 3000, 14000) * np.exp(-t / 0.5) * vel


def woodblock(freq=900, vel=1.0):
    dur = 0.12
    t = t_axis(dur)
    return (np.sin(2 * np.pi * freq * t) + 0.4 * np.sin(2 * np.pi * freq * 2.7 * t)) * np.exp(-t / 0.025) * vel


# --- Output ------------------------------------------------------------------------------------------

def to_int16(x):
    return (np.clip(x, -1, 1) * 32767).astype(np.int16)


def write(path, x, quality=5):
    """Writes .ogg (via ffmpeg/libvorbis) or .wav, mono or stereo."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x)
    channels = 1 if x.ndim == 1 else x.shape[1]
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(to_int16(x).tobytes())
    if path.endswith(".wav"):
        os.replace(wav_path, path)
        return
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality),
                    path], check=True)
    os.remove(wav_path)

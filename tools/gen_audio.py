#!/usr/bin/env python3
"""Synthesise every sound in the game (no samples, no external assets).

  heart_lub/dub(_hard)   violent heartbeat, split in two so the screen shake
                         can hit exactly on each beat
  breath_{calm,heavy,pant}_{in,out}_N   shaky breathing / panting
  step_N                 slow footsteps on stone paving
  lamp_buzz / lamp_zap   failing lamp hum and arcing
  amb_night              lakeside night: crickets, frogs, water, wind, city hum
  bgm_corridor           the eerie score: drones, dissonant strings, a detuned
                         music box, bowed metal, low piano tolls
  riser / stinger        tension riser and blackout hit
  ui_hover / ui_click / ui_back

Usage: python3 tools/gen_audio.py       (writes assets/audio/*.ogg)
Deps:  numpy, scipy, soundfile
"""
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
SR = 44100
rng = np.random.default_rng(666)


# ----------------------------------------------------------------------------
# DSP helpers
# ----------------------------------------------------------------------------
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def lp(x, f, order=2):
    sos = signal.butter(order, min(f, SR * 0.45), "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def hp(x, f, order=2):
    sos = signal.butter(order, f, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def bp(x, f, q=2.0, order=2):
    lo, hi = f / (1 + 0.5 / q), f * (1 + 0.5 / q)
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def reson(x, f, q):
    """2-pole resonator (peaky formant)."""
    b, a = signal.iirpeak(f, q, fs=SR)
    return signal.lfilter(b, a, x, axis=0)


def noise(n, color="white", seed=None):
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal(n)
    if color == "pink":
        f = np.fft.rfft(w)
        k = np.arange(len(f))
        k[0] = 1
        w = np.fft.irfft(f / np.sqrt(k), n)
    elif color == "brown":
        w = np.cumsum(w)
        w = hp(w, 15)
    return w / (np.abs(w).max() + 1e-9)


def env_adsr(n, a, d, s, r, sustain_level=0.7):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False) if a_n else np.zeros(0),
        np.linspace(1, sustain_level, d_n, endpoint=False) if d_n else np.zeros(0),
        np.full(s_n, sustain_level),
        np.linspace(sustain_level, 0, r_n) if r_n else np.zeros(0),
    ])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def smooth_rand(n, period, seed):
    """Smooth random curve (cubic interpolation of points every `period` s), ~[-1, 1]."""
    r = np.random.default_rng(seed)
    k = int(n / (period * SR)) + 4
    pts = r.uniform(-1, 1, k)
    xs = np.arange(k) * period * SR
    from scipy.interpolate import CubicSpline
    return np.clip(CubicSpline(xs, pts)(np.arange(n)), -1.2, 1.2)


def pan(x, p):
    """p in -1 (left) .. 1 (right), equal power."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], 1)


def make_ir(rt60=4.0, pre=0.02, damp=0.35, seed=3):
    n = int((rt60 + pre) * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    ir = np.zeros((n, 2))
    for ch in range(2):
        wn = r.standard_normal(n)
        low = lp(wn, 2500) * np.exp(-6.9 * t / rt60)
        high = hp(wn, 2500) * np.exp(-6.9 * t / (rt60 * damp))
        ir[:, ch] = low + high
    ir[: int(pre * SR)] = 0
    # a few early reflections
    for k in range(6):
        d = int((pre + 0.004 + 0.011 * k + r.uniform(0, 0.006)) * SR)
        ir[d, 0] += r.uniform(0.2, 0.5) * (0.8 ** k)
        ir[d + int(r.uniform(0.0005, 0.003) * SR), 1] += r.uniform(0.2, 0.5) * (0.8 ** k)
    return ir / np.abs(ir).max()


def reverb(x, ir, wet=0.35, dry=1.0):
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    y = np.stack([signal.fftconvolve(x[:, c], ir[:, c])[: len(x)] for c in range(2)], 1)
    y /= (np.abs(y).max() + 1e-9)
    xm = x / (np.abs(x).max() + 1e-9)
    return xm * dry + y * wet


def pad_tail(x, sec):
    z = np.zeros((int(sec * SR),) + x.shape[1:])
    return np.concatenate([x, z])


def normalize(x, peak=0.89):
    return x * (peak / (np.abs(x).max() + 1e-9))


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def write(name, x, peak=0.89, quality=5):
    """Write as Ogg Vorbis via ffmpeg/libvorbis (libsndfile's encoder crashes on long files)."""
    import subprocess
    import tempfile
    x = normalize(np.asarray(x, np.float64), peak).astype(np.float32)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav = tmp.name
    sf.write(wav, x, SR, subtype="FLOAT")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality),
                    str(OUT / f"{name}.ogg")], check=True)
    Path(wav).unlink()
    print("wrote", name, f"{len(x) / SR:.2f}s")


def loopify(x, xfade):
    """Crossfade the tail into the head so the file loops seamlessly."""
    n = int(xfade * SR)
    head, tail = x[:n], x[-n:]
    w = np.linspace(0, 1, n)
    if x.ndim == 2:
        w = w[:, None]
    body = x[: len(x) - n].copy()
    body[:n] = tail * (1 - w) + head * w
    return body


# ----------------------------------------------------------------------------
# heartbeat
# ----------------------------------------------------------------------------
def heart(kind="lub", hard=False, seed=0):
    r = np.random.default_rng(seed)
    dur = 0.55 if kind == "lub" else 0.42
    t = t_axis(dur)
    f0, f1 = (78.0, 36.0) if kind == "lub" else (96.0, 44.0)
    if hard:
        f0 *= 0.92
        f1 *= 0.9
    fr = f1 + (f0 - f1) * np.exp(-t / 0.045)
    ph = 2 * np.pi * np.cumsum(fr) / SR
    dec = 0.11 if kind == "lub" else 0.075
    if hard:
        dec *= 1.45
    body = np.sin(ph) * np.exp(-t / dec) * (1 - np.exp(-t / 0.003))
    # valve "thud" texture
    th = lp(noise(len(t), seed=seed + 1), 260, 4) * np.exp(-t / (dec * 0.6)) * 0.9
    # chest resonance
    chest = reson(noise(len(t), seed=seed + 2) * np.exp(-t / 0.03), 112 if kind == "lub" else 135, 6) * 0.35
    x = body * 1.0 + th * 0.55 + chest
    if hard:
        sub = np.sin(2 * np.pi * np.cumsum(28 + 20 * np.exp(-t / 0.08)) / SR) * np.exp(-t / 0.22) * 0.8
        click = lp(noise(len(t), seed=seed + 3), 900) * np.exp(-t / 0.006) * 0.25
        rush = bp(noise(len(t), seed=seed + 4), 180, 1.0) * np.exp(-t / 0.14) * 0.3
        x = x + sub + click + rush
        x = softclip(x * 2.2, 1.6)
    else:
        x = softclip(x * 1.4, 1.1)
    x = lp(x, 1600 if hard else 900)
    fade = np.ones_like(x)
    fade[-int(0.05 * SR):] = np.linspace(1, 0, int(0.05 * SR))
    return x * fade


# ----------------------------------------------------------------------------
# breathing
# ----------------------------------------------------------------------------
def breath(phase, intensity, seed):
    """phase: in|out, intensity: calm|heavy|pant"""
    r = np.random.default_rng(seed)
    durs = {
        ("in", "calm"): (1.25, 1.6), ("out", "calm"): (1.7, 2.3),
        ("in", "heavy"): (0.75, 1.0), ("out", "heavy"): (0.85, 1.2),
        ("in", "pant"): (0.33, 0.48), ("out", "pant"): (0.38, 0.55),
    }
    dur = r.uniform(*durs[(phase, intensity)])
    n = int(dur * SR)
    t = np.arange(n) / SR
    k = t / dur
    src = noise(n, "white", seed)
    if phase == "in":
        # nose/mouth hiss, brightening as the airflow builds
        f = [(2600, 2.0, 1.0), (4300, 2.5, 0.7), (1400, 2.0, 0.35), (6800, 2.0, 0.3)]
        shape = np.sin(np.pi * np.clip(k, 0, 1) ** 0.8) ** 1.2
        shape *= np.clip((1 - k) * 8, 0, 1)
    else:
        # "haaa": open-vowel formants, stronger at the start
        f = [(720, 3.0, 1.0), (1250, 3.5, 0.75), (2550, 4.0, 0.45), (3500, 3.0, 0.2)]
        shape = np.clip(k * 9, 0, 1) * np.exp(-k * (2.2 if intensity != "calm" else 1.6))
    x = np.zeros(n)
    for fc, q, g in f:
        x += bp(src, fc * r.uniform(0.93, 1.07), q) * g
    x *= shape
    if intensity != "calm":
        # trembling, irregular airflow
        trem_rate = r.uniform(6.0, 10.0) if intensity == "pant" else r.uniform(4.5, 7.0)
        jitter = lp(noise(n, seed=seed + 11), 12)
        trem = 1 + (0.35 if intensity == "pant" else 0.22) * np.sin(2 * np.pi * trem_rate * t + 3 * jitter)
        x *= trem
        if phase == "out" or intensity == "pant":
            # faint voiced whimper under the air
            f0 = r.uniform(115, 150) * (1 + 0.04 * np.sin(2 * np.pi * 5 * t))
            ph = 2 * np.pi * np.cumsum(f0) / SR
            voice = sum(np.sin(ph * h) / h ** 1.3 for h in range(1, 14))
            voice = reson(voice, 700, 4) + reson(voice, 1200, 5) * 0.6
            vamt = 0.06 if intensity == "heavy" else 0.11
            x += voice * shape * vamt * (1 if phase == "out" else 0.5)
    x = hp(x, 160)
    x = lp(x, 9000)
    st = np.stack([x, np.roll(x, 7)], 1)
    return st


# ----------------------------------------------------------------------------
# footsteps
# ----------------------------------------------------------------------------
def footstep(seed):
    r = np.random.default_rng(seed)
    dur = 0.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    # heel strike
    imp = np.zeros(n)
    imp[int(0.005 * SR)] = 1.0
    heel = reson(imp, r.uniform(95, 130), 3.0) * 3.0 + reson(imp, r.uniform(700, 1000), 5.0) * 0.6
    heel += lp(noise(n, seed=seed), 2500) * np.exp(-t / 0.012) * 0.5
    x += heel
    # sole roll / scuff
    t2 = r.uniform(0.05, 0.08)
    sc_env = np.clip((t - t2) / 0.01, 0, 1) * np.exp(-np.clip(t - t2, 0, None) / r.uniform(0.035, 0.06))
    scuff = bp(noise(n, seed=seed + 1), r.uniform(2400, 3600), 0.8) * sc_env * 0.55
    x += scuff
    # grit under the sole
    grit = np.zeros(n)
    for _ in range(r.integers(6, 16)):
        p = int((t2 + r.uniform(0, 0.07)) * SR)
        if p < n:
            grit[p] = r.uniform(-1, 1)
    x += hp(grit, 4500) * 0.5
    x = lp(x, 7000)
    x *= np.exp(-t / 0.25)
    return np.stack([x, x], 1)


# ----------------------------------------------------------------------------
# lamps
# ----------------------------------------------------------------------------
def lamp_buzz():
    dur = 4.0
    t = t_axis(dur)
    n = len(t)
    x = np.zeros(n)
    for h in range(1, 18):
        f = 100.0 * h
        amp = (1.0 / h ** 0.9) * (1.4 if h % 2 == 0 else 1.0)
        x += amp * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28))
    x = lp(x, 2500) * 0.35
    sizzle = hp(noise(n, seed=21), 3500) * (0.5 + 0.5 * np.sin(2 * np.pi * 100 * t)) ** 4 * 0.25
    # periodic noise for seamless looping
    sizzle = loop_noise(sizzle, 0.25)
    flutter = 1 + 0.08 * np.sin(2 * np.pi * 0.25 * t) + 0.05 * np.sin(2 * np.pi * 1.75 * t)
    x = (x + sizzle) * flutter
    return np.stack([x, x], 1)


def loop_noise(x, xf):
    n = int(xf * SR)
    w = np.linspace(0, 1, n)
    y = x.copy()
    y[:n] = x[:n] * w + x[-n:] * (1 - w)
    return y


def lamp_zap():
    dur = 0.6
    t = t_axis(dur)
    n = len(t)
    crack = np.zeros(n)
    p = 0
    while p < int(0.18 * SR):
        crack[p] = rng.uniform(-1, 1)
        p += int(rng.exponential(0.004) * SR) + 1
    crack = hp(crack, 1500) + bp(noise(n, seed=31), 4000, 1.0) * 0.35
    crack *= np.exp(-t / 0.07)
    ping = np.sin(2 * np.pi * 3150 * t) * np.exp(-t / 0.09) * 0.15
    thump = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.05) * 0.4
    x = crack + ping + thump
    return np.stack([x, np.roll(x, 11)], 1)


# ----------------------------------------------------------------------------
# night ambience
# ----------------------------------------------------------------------------
def cricket(dur, freq, rate, pulses, p_dur, seed):
    r = np.random.default_rng(seed)
    t = t_axis(dur)
    n = len(t)
    env = np.zeros(n)
    tt = r.uniform(0, 0.5)
    while tt < dur - 0.3:
        for k in range(pulses):
            s = int((tt + k * p_dur * 1.8) * SR)
            e = s + int(p_dur * SR)
            if e < n:
                env[s:e] += np.hanning(e - s)
        tt += 1.0 / rate * r.uniform(0.85, 1.15)
        if r.random() < 0.05:
            tt += r.uniform(0.5, 3.0)  # pauses
    carrier = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2.01 * t)
    return carrier * env


def frog(dur, seed):
    r = np.random.default_rng(seed)
    t = t_axis(dur)
    n = len(t)
    x = np.zeros(n)
    tt = r.uniform(0.5, 4.0)
    while tt < dur - 1.0:
        cd = r.uniform(0.18, 0.45)
        s = int(tt * SR)
        e = s + int(cd * SR)
        tc = np.arange(e - s) / SR
        f0 = r.uniform(240, 420)
        pulse = (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(18, 32) * tc)) ** 3
        tone = sum(np.sin(2 * np.pi * f0 * h * tc) / h for h in range(1, 7))
        x[s:e] += tone * pulse * np.hanning(e - s)
        tt += cd + r.uniform(0.15, 0.6) if r.random() < 0.5 else cd + r.uniform(2.0, 7.0)
    return reson(x, 600, 2) * 0.5 + x * 0.3


def ambience():
    dur = 64.0
    n = int(dur * SR)
    out = np.zeros((n, 2))
    # distant city hum and wind
    hum = lp(noise(n, "brown", 41), 120) * 0.25
    out += np.stack([hum, hum], 1)
    wind_env = np.clip(0.55 + 0.45 * smooth_rand(n, 3.0, 42), 0, 1)
    leaves = bp(noise(n, "pink", 43), 1800, 0.6) * wind_env ** 2 * 0.12
    out += pan(leaves, 0.55)
    # crickets in the bushes (right) and a dense far chorus
    for i in range(7):
        c = cricket(dur, rng.uniform(3900, 5200), rng.uniform(1.6, 3.2), int(rng.integers(3, 6)), rng.uniform(0.012, 0.02), 100 + i)
        c = lp(c, rng.uniform(5000, 9000)) * rng.uniform(0.03, 0.09)
        out += pan(c, rng.uniform(0.1, 0.95))
    chorus = bp(noise(n, seed=44), 4600, 3.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 7.5 * t_axis(dur)) ** 2) * 0.05
    out += pan(chorus, 0.3)
    # frogs on the lake (left)
    for i in range(4):
        f = lp(frog(dur, 200 + i), 2500) * rng.uniform(0.05, 0.12)
        out += pan(f, rng.uniform(-0.95, -0.4))
    # water lapping against the embankment (left)
    lap = np.zeros(n)
    tt = 0.3
    while tt < dur - 1:
        s = int(tt * SR)
        ln = int(rng.uniform(0.25, 0.6) * SR)
        e = min(n, s + ln)
        lap[s:e] += np.hanning(e - s) * rng.uniform(0.3, 1.0)
        tt += rng.uniform(0.8, 3.0)
    water = bp(noise(n, seed=45), 500, 0.7) * lp(lap, 30) * 0.18
    out += pan(water, -0.7)
    out = loopify(out, 4.0)
    return out


# ----------------------------------------------------------------------------
# music
# ----------------------------------------------------------------------------
def note_hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def string_tone(dur, f, seed, bright=0.6, vib=0.004):
    r = np.random.default_rng(seed)
    t = t_axis(dur)
    x = np.zeros(len(t))
    vibrato = 1 + vib * np.sin(2 * np.pi * r.uniform(4.5, 5.5) * t + r.uniform(0, 6)) * np.clip(t / 2.0, 0, 1)
    drift = 1 + 0.0025 * smooth_rand(len(t), 1.7, seed + 99)
    for h in range(1, 16):
        amp = (1 / h) * (bright ** (h / 4))
        ph = 2 * np.pi * np.cumsum(f * h * vibrato * drift * (1 + r.uniform(-0.0008, 0.0008))) / SR
        x += amp * np.sin(ph + r.uniform(0, 6))
    bow = bp(r.standard_normal(len(t)), min(f * 6, 8000), 1.0) * 0.02
    return x + bow


def swell(n, attack, release):
    t = np.arange(n) / SR
    dur = n / SR
    e = np.clip(t / attack, 0, 1) ** 2 * np.clip((dur - t) / release, 0, 1) ** 1.5
    return e


def music_box_note(f, seed, dur=3.5):
    r = np.random.default_rng(seed)
    t = t_axis(dur)
    x = np.zeros(len(t))
    for ratio, amp, dec in [(1.0, 1.0, 1.4), (2.0, 0.35, 0.7), (2.76, 0.22, 0.5), (5.4, 0.12, 0.25), (8.93, 0.06, 0.12)]:
        x += amp * np.sin(2 * np.pi * f * ratio * t * (1 + r.uniform(-0.001, 0.001))) * np.exp(-t / dec)
    click = hp(np.random.default_rng(seed).standard_normal(len(t)), 3000) * np.exp(-t / 0.003) * 0.15
    return (x + click) * (1 - np.exp(-t / 0.002))


def piano_toll(f, dur=7.0):
    t = t_axis(dur)
    x = np.zeros(len(t))
    for h in range(1, 12):
        inh = h * np.sqrt(1 + 0.0004 * h * h)
        x += (1 / h ** 1.2) * np.sin(2 * np.pi * f * inh * t) * np.exp(-t / (5.0 / h ** 0.6))
    ham = lp(noise(len(t), seed=77), 400) * np.exp(-t / 0.02) * 0.3
    return (x + ham) * (1 - np.exp(-t / 0.004))


def bowed_metal(dur, f, seed):
    r = np.random.default_rng(seed)
    t = t_axis(dur)
    x = np.zeros(len(t))
    for ratio in [1.0, 1.593, 2.135, 2.653, 3.155, 4.11]:
        fr = f * ratio * (1 + 0.002 * np.sin(2 * np.pi * r.uniform(0.1, 0.4) * t))
        x += np.sin(2 * np.pi * np.cumsum(fr) / SR) * r.uniform(0.3, 1.0)
    rough = 1 + 0.25 * lp(r.standard_normal(len(t)), 25) * 8
    return x * rough


def score():
    dur = 168.0
    n = int(dur * SR)
    t = t_axis(dur)
    mix = np.zeros((n, 2))
    # 1) sub drone on D with a slowly breathing filter
    d1 = note_hz(26)  # D1
    drone = np.zeros(n)
    for k, (m, a) in enumerate([(26, 1.0), (33, 0.5), (38, 0.35), (39, 0.12)]):  # D1 A1 D2 Eb2
        f = note_hz(m)
        for det in (-0.6, 0.0, 0.7):
            drone += a * signal.sawtooth(2 * np.pi * (f + det * 0.15) * t + rng.uniform(0, 6))
    cutoff_lfo = 0.5 + 0.5 * np.sin(2 * np.pi * t / 41.0 - 1.2)
    drone_lo = lp(drone, 140)
    drone_hi = lp(drone, 420) - drone_lo
    drone = drone_lo + drone_hi * cutoff_lfo * 0.6
    drone *= 0.22
    mix += np.stack([drone, np.roll(drone, 23)], 1)

    # 2) dissonant string clusters swelling in and out
    clusters = [
        (8.0, 22.0, [50, 51, 57]), (26.0, 20.0, [53, 54, 60]), (44.0, 26.0, [50, 56, 57, 63]),
        (66.0, 18.0, [62, 63, 69]), (86.0, 24.0, [49, 50, 56]), (112.0, 22.0, [55, 56, 62, 63]),
        (134.0, 28.0, [50, 51, 57, 58]),
    ]
    for i, (st, ln, notes) in enumerate(clusters):
        s = int(st * SR)
        m = int(ln * SR)
        e = min(n, s + m)
        seg = np.zeros(e - s)
        for j, nt in enumerate(notes):
            seg += string_tone((e - s) / SR, note_hz(nt) * (1 + rng.uniform(-0.004, 0.004)), 500 + i * 10 + j, bright=0.55)[: e - s]
        seg *= swell(e - s, ln * 0.45, ln * 0.4)
        seg = lp(seg, 3500) * 0.05
        p = rng.uniform(-0.5, 0.5)
        mix[s:e] += pan(seg, p)

    # 3) bowed metal, high and thin
    for i, st in enumerate([34.0, 72.0, 101.0, 146.0]):
        ln = rng.uniform(9, 14)
        s, e = int(st * SR), min(n, int((st + ln) * SR))
        seg = bowed_metal((e - s) / SR, rng.uniform(820, 1150), 600 + i)[: e - s]
        seg *= swell(e - s, ln * 0.5, ln * 0.4) * 0.018
        mix[s:e] += pan(hp(seg, 500), rng.uniform(-0.8, 0.8))

    # 4) a detuned, slowing music box (D minor, Phrygian flat 2)
    phrase_a = [(74, 1.0), (77, 1.0), (81, 1.0), (79, 1.5), (77, 0.5), (76, 1.0), (74, 2.0), (73, 1.0), (74, 3.0)]
    phrase_b = [(81, 1.0), (82, 1.0), (81, 1.0), (77, 1.5), (76, 0.5), (75, 1.5), (74, 1.0), (73, 2.0), (74, 4.0)]
    for start, phrase, beat in [(22.0, phrase_a, 0.62), (58.0, phrase_b, 0.66), (120.0, phrase_a, 0.7), (142.0, phrase_b, 0.78)]:
        tt = start
        slowdown = 1.0
        for k, (m, b) in enumerate(phrase):
            if k > len(phrase) - 4:
                slowdown *= 1.12  # the mechanism winding down
            detune = 2 ** (rng.uniform(-28, 28) / 1200) * (1 / slowdown ** 0.15)
            nb = music_box_note(note_hz(m) * detune, 700 + k + int(start))
            s = int(tt * SR)
            e = min(n, s + len(nb))
            mix[s:e] += pan(nb[: e - s] * 0.09, rng.uniform(-0.35, 0.35))
            tt += b * beat * slowdown * rng.uniform(0.94, 1.08)

    # 5) low piano tolls
    for st in [15.0, 50.0, 96.0, 130.0, 160.0]:
        tol = piano_toll(note_hz(rng.choice([26, 27, 38])))
        s = int(st * SR)
        e = min(n, s + len(tol))
        mix[s:e] += pan(tol[: e - s] * 0.12, rng.uniform(-0.2, 0.2))

    # 6) reversed swells into the dips
    for st in [62.0, 108.0, 150.0]:
        ln = 5.0
        cl = sum(string_tone(ln, note_hz(m), 900 + m, bright=0.8) for m in (62, 63, 68))
        cl *= np.exp(-t_axis(ln) / 1.2)
        rev = cl[::-1] * np.linspace(0, 1, len(cl)) ** 2
        s = int((st - ln) * SR)
        mix[s : s + len(rev)] += pan(rev * 0.05, 0.0)

    ir = make_ir(5.5, 0.03, 0.4, seed=5)
    wet = np.stack([signal.fftconvolve(mix[:, c], ir[:, c])[:n] for c in range(2)], 1)
    out = mix * 0.65 + wet / (np.abs(wet).max() + 1e-9) * np.abs(mix).max() * 0.85
    out = hp(out, 22)
    out = loopify(out, 6.0)
    return out


def riser():
    dur = 5.0
    t = t_axis(dur)
    n = len(t)
    k = t / dur
    x = np.zeros(n)
    for m in [50, 51, 56, 57, 62, 63]:
        f = note_hz(m) * (1 + 0.5 * k ** 2)
        x += signal.sawtooth(2 * np.pi * np.cumsum(f) / SR + rng.uniform(0, 6))
    # opening filter: crossfade between progressively brighter low-passes
    bands = [lp(x, fc) for fc in (600, 1500, 3500, 6600)]
    pos = np.clip(k ** 2 * 3.0, 0, 2.999)
    i0 = np.floor(pos).astype(int)
    fr = pos - i0
    stack = np.stack(bands, 0)
    x = stack[i0, np.arange(n)] * (1 - fr) + stack[np.minimum(i0 + 1, 3), np.arange(n)] * fr
    x = x * k ** 2.5 * 0.4
    nz = hp(noise(n, seed=91), 2000) * k ** 3 * 0.5
    # accelerating pulses
    pulses = np.zeros(n)
    tt = 0.0
    while tt < dur - 0.1:
        s = int(tt * SR)
        w = int(0.05 * SR)
        if s + w > n:
            break
        pulses[s : s + w] += np.hanning(w)
        tt += 0.5 * (1 - k[s]) ** 1.5 + 0.06
    thumps = lp(pulses * noise(n, seed=92), 200) * 2.0
    y = x + nz + thumps
    y[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    return np.stack([y, np.roll(y, 31)], 1)


def stinger():
    dur = 5.5
    t = t_axis(dur)
    n = len(t)
    boom = np.sin(2 * np.pi * np.cumsum(32 + 60 * np.exp(-t / 0.06)) / SR) * np.exp(-t / 1.1)
    boom = softclip(boom * 2.5, 2.0)
    hit = lp(noise(n, seed=95), 1200) * np.exp(-t / 0.15) * 0.8
    screech = np.zeros(n)
    for f in [1480, 1567, 2217, 2349, 3136]:
        screech += np.sin(2 * np.pi * f * t * (1 + 0.003 * np.sin(2 * np.pi * 6 * t)))
    screech = screech * np.exp(-t / 0.9) * np.clip(t / 0.02, 0, 1) * 0.12
    x = boom + hit + screech
    ir = make_ir(4.0, 0.02, 0.35, seed=8)
    y = reverb(x, ir, wet=0.5)
    return y


def tinnitus():
    """Seamless 6 s ring: a high tone with slow beating (all partials complete
    whole cycles in 6 s so the loop has no click) plus a thin hiss."""
    dur = 6.0
    t = t_axis(dur)
    n = len(t)
    trem = 1 + 0.12 * np.sin(2 * np.pi * 0.5 * t)
    l = (np.sin(2 * np.pi * 6150.0 * t) + 0.6 * np.sin(2 * np.pi * 6152.5 * t) + 0.2 * np.sin(2 * np.pi * 3075.0 * t)) * trem
    r = (np.sin(2 * np.pi * 6151.0 * t) + 0.6 * np.sin(2 * np.pi * 6153.5 * t) + 0.2 * np.sin(2 * np.pi * 3075.5 * t)) * trem
    hiss = loop_noise(hp(noise(n, seed=120), 7000), 0.5) * 0.06
    return np.stack([l * 0.3 + hiss, r * 0.3 + hiss], 1)


def dizzy():
    """Seamless 8 s vertigo bed: flanged low drone, a wobbling whine and a
    breathy rush of blood in the ears."""
    dur = 8.0
    t = t_axis(dur)
    n = len(t)
    drone = np.sin(2 * np.pi * 55.0 * t) + 0.6 * np.sin(2 * np.pi * 82.5 * t) + 0.35 * np.sin(2 * np.pi * 110.25 * t)
    # flanger with a periodic delay (0.25 Hz -> 2 cycles per loop)
    d = (0.003 + 0.002 * np.sin(2 * np.pi * 0.25 * t)) * SR
    idx = np.arange(n) - d
    i0 = np.floor(idx).astype(int) % n
    fr = idx - np.floor(idx)
    delayed = drone[i0] * (1 - fr) + drone[(i0 + 1) % n] * fr
    flanged = (drone + delayed) * 0.5
    ph = 2 * np.pi * (220.0 * t - 6.0 / (2 * np.pi * 0.25) * np.cos(2 * np.pi * 0.25 * t))
    whine = np.sin(ph) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.125 * t)) * 0.12
    rush = loop_noise(bp(noise(n, "pink", 121), 480, 0.7), 0.6) * (0.55 + 0.45 * np.sin(2 * np.pi * 0.125 * t - 1.0)) * 0.9
    x = flanged * 0.5 + whine + rush * 0.6
    return np.stack([x, np.roll(x, 37)], 1)


def ui_hover():
    dur = 0.6
    t = t_axis(dur)
    x = np.sin(2 * np.pi * 196 * t) * np.exp(-t / 0.12) * 0.5 + np.sin(2 * np.pi * 207.6 * t) * np.exp(-t / 0.14) * 0.35
    x += bp(noise(len(t), seed=96), 2500, 2) * np.exp(-t / 0.02) * 0.15
    return reverb(x, make_ir(1.5, 0.01, 0.4, seed=9), wet=0.35)


def ui_click():
    t = t_axis(1.2)
    x = heart("lub", True, seed=97)
    x = np.pad(x, (0, len(t) - len(x)))
    x += np.sin(2 * np.pi * 55 * t) * np.exp(-t / 0.3) * 0.4
    return reverb(x, make_ir(2.5, 0.01, 0.4, seed=10), wet=0.3)


def ui_back():
    dur = 0.9
    t = t_axis(dur)
    x = bp(noise(len(t), "pink", 98), 900, 0.8) * np.sin(np.pi * t / dur) ** 2
    x = x[::-1] * 0.6
    return reverb(x, make_ir(1.5, 0.01, 0.4, seed=11), wet=0.3)


def main():
    write("heart_lub", np.stack([heart("lub", False, 1)] * 2, 1), 0.85)
    write("heart_dub", np.stack([heart("dub", False, 2)] * 2, 1), 0.7)
    write("heart_lub_hard", np.stack([heart("lub", True, 3)] * 2, 1), 0.95)
    write("heart_dub_hard", np.stack([heart("dub", True, 4)] * 2, 1), 0.8)
    for intensity in ("calm", "heavy", "pant"):
        for i in range(1, 5):
            write(f"breath_{intensity}_in_{i}", breath("in", intensity, 1000 + i * 7 + len(intensity)), 0.8)
            write(f"breath_{intensity}_out_{i}", breath("out", intensity, 2000 + i * 7 + len(intensity)), 0.8)
    for i in range(1, 9):
        write(f"step_{i}", footstep(3000 + i), 0.8)
    write("lamp_buzz", lamp_buzz(), 0.6)
    write("lamp_zap", lamp_zap(), 0.85)
    write("amb_night", ambience(), 0.7)
    write("riser", riser(), 0.85)
    write("stinger", stinger(), 0.95)
    write("ui_hover", ui_hover(), 0.6)
    write("ui_click", ui_click(), 0.8)
    write("ui_back", ui_back(), 0.6)
    write("tinnitus", tinnitus(), 0.5)
    write("dizzy", dizzy(), 0.7)
    write("bgm_corridor", score(), 0.8)


if __name__ == "__main__":
    main()

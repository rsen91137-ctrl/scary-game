#!/usr/bin/env python3
"""Outdoor sounds for the estate and the forest (all synthesised, deterministic).

Writes assets/audio/:
  amb_courtyard.ogg   the courtyard at night: far traffic, a dog somewhere,
                      a lamp buzzing, a breath of wind in dry leaves (loops)
  amb_forest.ogg      the forest: wind in the pines, trunks creaking, an owl,
                      twigs snapping, long silences (loops)
  step_leaf_1..6      footsteps in leaf litter and needles
  step_gravel_1..6    footsteps on gravel, grit on paving
  lamp_buzz.ogg       a mercury street lamp humming (loops; 100 Hz mains hum)
  amb_forest_rustle.ogg  needles and dry leaves hissing in a gust (loops; the
                      game swells it with the same envelope that sways the trees)
The looping files are set to loop at runtime by ExteriorBuilder (stream.loop).
Usage: python3 tools/gen_outside_sfx.py [name ...]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
SR = 44100


def write_ogg(name: str, x: np.ndarray, q: int = 5, peak_to: float = 0.89) -> None:
    x = np.asarray(x, np.float64)
    if x.ndim == 1:
        x = x[:, None]
    peak = float(np.max(np.abs(x))) or 1.0
    x = (x / peak * peak_to).astype(np.float32)
    wav = OUT / f"{name}.wav"
    sf.write(str(wav), x, SR, subtype="PCM_16")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", str(q), str(OUT / f"{name}.ogg")], check=True)
    wav.unlink()
    print("wrote", name)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def loopify(x, xfade=3.0):
    n = int(xfade * SR)
    w = np.linspace(0, 1, n)
    if x.ndim > 1:
        w = w[:, None]
    head = x[:n].copy()
    tail = x[-n:].copy()
    y = x[:-n].copy()
    y[:n] = head * w + tail * (1 - w)
    return y


def reverb(x, secs=1.8, wet=0.35, seed=0, damp=3000.0):
    """Cheap outdoor reverb: convolve with decaying, darkened noise."""
    r = np.random.default_rng(seed)
    n = int(secs * SR)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / (secs * SR / 6.0))
    ir = lp(ir, damp)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    y = signal.fftconvolve(x, ir)[: len(x)]
    return x * (1 - wet) + y * wet


def place(dst, src, at, gain=1.0):
    at = int(at)
    if at >= len(dst):
        return
    m = min(len(src), len(dst) - at)
    dst[at:at + m] += src[:m] * gain


def pan(mono, p):
    """p -1 (left) .. 1 (right), equal power."""
    a = (p + 1) * np.pi / 4
    return np.cos(a) * mono, np.sin(a) * mono


# ---------------------------------------------------------------------------
def dog_bark(rng, far=True):
    """One bark: a short, harmonically rich yelp with a falling pitch."""
    dur = rng.uniform(0.16, 0.26)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = rng.uniform(420, 620) * (1.0 + 0.25 * np.exp(-t / 0.03)) * (1.0 - 0.18 * t / dur)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    x = sum(np.sin(ph * k) / k ** 0.8 for k in range(1, 9))
    x += 0.4 * bp(rng.standard_normal(n), 600, 2500)
    env = np.minimum(1.0, t / 0.008) * np.exp(-t / (dur * 0.45))
    x = bp(x * env, 300, 2400)
    if far:
        x = lp(x, 1400)
    return x


def car_pass(rng, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.exp(-((t - dur * 0.5) / (dur * 0.22)) ** 2)
    x = lp(rng.standard_normal(n), 500) * 0.6 + bp(rng.standard_normal(n), 400, 1500) * 0.25
    tyre = bp(rng.standard_normal(n), 800, 3000) * 0.1
    return (x + tyre) * env


def amb_courtyard():
    rng = np.random.default_rng(7)
    dur = 64.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    L = np.zeros(n)
    R = np.zeros(n)
    # the town beyond the trees: a low, slowly breathing rumble
    for ch, s in ((L, 1), (R, 2)):
        r2 = np.random.default_rng(100 + s)
        rum = lp(r2.standard_normal(n), 160) * 0.7 + lp(r2.standard_normal(n), 60) * 0.9
        slow = lp(r2.standard_normal(n), 0.15)
        slow /= np.max(np.abs(slow)) + 1e-9
        ch += rum * (0.55 + 0.3 * slow)
    # now and then a car far off on the main road
    for k in range(5):
        d = rng.uniform(6, 11)
        at = rng.uniform(0, dur - d) * SR
        c = car_pass(rng, d) * rng.uniform(0.4, 0.8)
        l, r = pan(c, rng.uniform(-0.8, 0.8))
        place(L, l, at)
        place(R, r, at)
    # a dog behind the blocks: two bouts
    for bout in range(2):
        start = rng.uniform(4, dur - 14) * SR
        for k in range(rng.integers(3, 7)):
            b = dog_bark(rng) * rng.uniform(0.5, 1.0)
            b = reverb(np.pad(b, (0, SR)), 2.2, 0.55, seed=bout * 10 + k)
            l, r = pan(b, -0.6 if bout == 0 else 0.5)
            place(L, l, start, 0.9)
            place(R, r, start, 0.9)
            start += rng.uniform(0.35, 0.9) * SR
    # the lamp across the yard: a thin 100 Hz hum
    hum = sum(np.sin(2 * np.pi * 100 * k * t) / k ** 1.3 for k in range(1, 9))
    hum *= 0.025 * (0.85 + 0.15 * np.sin(2 * np.pi * 0.13 * t))
    L += hum * 0.6
    R += hum * 0.9
    # wind: a soft breath through the yard, dry leaves skittering on paving
    for ch, s in ((L, 3), (R, 4)):
        r2 = np.random.default_rng(200 + s)
        w = bp(r2.standard_normal(n), 300, 2500) * 0.06
        gust = lp(r2.standard_normal(n), 0.08)
        gust = np.clip(gust / (np.max(np.abs(gust)) + 1e-9) + 0.3, 0, None)
        ch += w * gust
        for k in range(30):
            at = r2.uniform(0, dur - 1) * SR
            ln = int(r2.uniform(0.2, 0.7) * SR)
            tt = np.arange(ln) / SR
            sk = hp(r2.standard_normal(ln), 2500) * (r2.random(ln) < 0.08) * np.sin(np.pi * tt / tt[-1]) * 0.25
            place(ch, sk, at)
    # a television through a window: muffled voices, very low
    tv = np.zeros(n)
    at = rng.uniform(20, 30) * SR
    ln = int(rng.uniform(8, 14) * SR)
    syll = lp((rng.random(ln) < 0.0004).astype(float), 8)
    syll = lp(np.abs(syll), 4)
    v = bp(rng.standard_normal(ln), 250, 900) * (syll / (np.max(syll) + 1e-9))
    place(tv, v * 0.12, at)
    L += tv * 0.4
    R += tv * 0.25
    st = np.stack([L, R], 1)
    st = loopify(st, 3.0)
    write_ogg("amb_courtyard", st, 4)


def owl(rng):
    """A tawny owl: hoo ... hu-hu-hoooo."""
    parts = []
    for (f, d, gap) in ((rng.uniform(440, 480), 0.55, 0.9), (rng.uniform(450, 490), 0.12, 0.12), (rng.uniform(450, 490), 0.12, 0.1), (rng.uniform(430, 470), 0.9, 0.0)):
        n = int(d * SR)
        t = np.arange(n) / SR
        fm = f * (1.0 + 0.02 * np.sin(2 * np.pi * 7 * t)) * (1.0 - 0.04 * t / d)
        ph = 2 * np.pi * np.cumsum(fm) / SR
        x = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
        env = np.minimum(1, t / 0.05) * np.minimum(1, (d - t) / 0.12)
        x *= env * (1.0 + 0.3 * np.sin(2 * np.pi * 21 * t))
        parts.append(x)
        parts.append(np.zeros(int(gap * SR)))
    return np.concatenate(parts)


def creak(rng):
    """A trunk rubbing in the wind: a slow, gritty, pitch-bending groan."""
    d = rng.uniform(0.9, 2.2)
    n = int(d * SR)
    t = np.arange(n) / SR
    f = rng.uniform(140, 320) * (1.0 + 0.3 * np.sin(2 * np.pi * rng.uniform(0.3, 0.8) * t + rng.uniform(0, 6)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = 2 * (ph / (2 * np.pi) % 1.0) - 1
    grit = (rng.random(n) < 0.3).astype(float)
    x = bp(saw * (0.6 + 0.4 * grit), 200, 1800)
    env = np.sin(np.pi * t / d) ** 1.5 * (0.6 + 0.4 * np.sin(2 * np.pi * 3.1 * t))
    return x * env


def snap(rng):
    """A twig breaking under something's foot."""
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(rng.integers(1, 4)):
        at = int(rng.uniform(0, 0.08) * SR)
        ln = int(0.03 * SR)
        tt = np.arange(ln) / SR
        c = bp(rng.standard_normal(ln), 1200, 7000) * np.exp(-tt / 0.004)
        c += np.sin(2 * np.pi * rng.uniform(1800, 3200) * tt) * np.exp(-tt / 0.006) * 0.6
        x[at:at + ln] += c * rng.uniform(0.6, 1.0)
    return x


def amb_forest():
    rng = np.random.default_rng(11)
    dur = 92.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    L = np.zeros(n)
    R = np.zeros(n)
    # wind in the pines: a hushing roar high up, coming in long gusts
    for ch, s in ((L, 1), (R, 2)):
        r2 = np.random.default_rng(300 + s)
        gust = lp(r2.standard_normal(n), 0.05)
        gust = gust / (np.max(np.abs(gust)) + 1e-9)
        gust = np.clip(gust * 0.9 + 0.35, 0.05, None) ** 1.6
        hush = bp(r2.standard_normal(n), 900, 6000) * 0.05
        body = bp(r2.standard_normal(n), 180, 900) * 0.035
        # resonant whistle through the needles, wandering
        w = r2.standard_normal(n)
        out = np.zeros(n)
        blk = 4096
        cf = 520 + 180 * np.sin(2 * np.pi * t / 29.0 + s) + 90 * np.sin(2 * np.pi * t / 7.7)
        for i in range(0, n, blk):
            b, a = signal.iirpeak(float(cf[i]) / (SR / 2), 9.0)
            out[i:i + blk] = signal.lfilter(b, a, w[i:i + blk])
        ch += (hush + body + out * 0.012) * gust
        ch += lp(r2.standard_normal(n), 70) * 0.25
    # trunks creaking
    for k in range(7):
        c = reverb(np.pad(creak(rng), (0, SR)), 1.5, 0.4, seed=k)
        l, r = pan(c, rng.uniform(-0.9, 0.9))
        at = rng.uniform(2, dur - 4) * SR
        g = rng.uniform(0.04, 0.1)
        place(L, l, at, g)
        place(R, r, at, g)
    # an owl, twice, from different sides
    for k, p in ((0, -0.7), (1, 0.6)):
        o = reverb(np.pad(owl(rng), (0, 2 * SR)), 2.6, 0.55, seed=40 + k, damp=2200)
        l, r = pan(lp(o, 2500), p)
        at = rng.uniform(8 + k * 40, 30 + k * 40) * SR
        place(L, l, at, 0.12)
        place(R, r, at, 0.12)
    # twigs snapping somewhere in the dark
    for k in range(6):
        s = reverb(np.pad(snap(rng), (0, SR)), 1.2, 0.45, seed=60 + k)
        l, r = pan(s, rng.uniform(-1, 1))
        at = rng.uniform(1, dur - 2) * SR
        g = rng.uniform(0.15, 0.45)
        place(L, l, at, g)
        place(R, r, at, g)
    # a few leaves rattling down
    for k in range(20):
        ln = int(rng.uniform(0.3, 1.0) * SR)
        tt = np.arange(ln) / SR
        x = hp(rng.standard_normal(ln), 3000) * (rng.random(ln) < 0.05) * np.sin(np.pi * tt / tt[-1]) * 0.06
        l, r = pan(x, rng.uniform(-1, 1))
        at = rng.uniform(0, dur - 1.5) * SR
        place(L, l, at)
        place(R, r, at)
    st = np.stack([L, R], 1)
    st = loopify(st, 4.0)
    write_ogg("amb_forest", st, 4)


def _step(rng, kind):
    dur = 0.34 if kind == "leaf" else 0.26
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    # heel thump
    th = np.sin(2 * np.pi * rng.uniform(55, 85) * t) * np.exp(-t / 0.025) * 0.5
    x += lp(th + lp(rng.standard_normal(n), 300) * np.exp(-t / 0.03) * 0.5, 400)
    # the crunch: heel then a rolling toe
    for (t0, spread, cnt, amp) in ((0.0, 0.06, 1.0, 1.0), (rng.uniform(0.07, 0.12), 0.09, 0.7, 0.7)):
        m = int((spread + 0.05) * SR)
        tt = np.arange(m) / SR
        if kind == "leaf":
            clicks = (rng.random(m) < 0.06 * cnt) * rng.uniform(0.3, 1.0, m)
            cr = bp(clicks * rng.standard_normal(m), 1800, 9000) * 2.2
            rustle = bp(rng.standard_normal(m), 900, 6000) * 0.35
            env = np.minimum(1, tt / 0.006) * np.exp(-tt / (spread * 0.6))
            seg = (cr + rustle) * env * amp
        else:
            clicks = (rng.random(m) < 0.09 * cnt) * rng.uniform(0.3, 1.0, m)
            cr = bp(clicks * rng.standard_normal(m), 700, 5500) * 2.0
            grind = bp(rng.standard_normal(m), 500, 3000) * 0.3
            env = np.minimum(1, tt / 0.004) * np.exp(-tt / (spread * 0.5))
            seg = (cr + grind) * env * amp
        place(x, seg, t0 * SR)
    x = reverb(x, 0.4, 0.12, seed=int(rng.integers(0, 999)))
    fade = np.minimum(1, (dur - t) / 0.05)
    return x * fade


def steps():
    for kind in ("leaf", "gravel"):
        for k in range(6):
            rng = np.random.default_rng((1 if kind == "leaf" else 2) * 100 + k)
            write_ogg(f"step_{kind}_{k + 1}", _step(rng, kind), 5, peak_to=0.8)


def lamp_buzz():
    dur = 4.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(5)
    x = np.zeros(n)
    for k in range(1, 14):
        x += np.sin(2 * np.pi * 100 * k * t + rng.uniform(0, 6)) / k ** 1.1 * (1.3 if k % 2 == 0 else 1.0)
    # the ballast's rattle: 100 Hz pulses with a little grit (periodic, so it loops)
    pulse = (np.sin(2 * np.pi * 100 * t) > 0.97).astype(float)
    x += bp(pulse * rng.standard_normal(n), 2000, 8000) * 0.4
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t)
    write_ogg("lamp_buzz", x, 5, peak_to=0.7)


def amb_forest_rustle():
    rng = np.random.default_rng(13)
    dur = 32.0
    n = int(dur * SR)
    out = []
    for s in (1, 2):
        r2 = np.random.default_rng(400 + s)
        flutter = lp(r2.standard_normal(n), 6.0)
        flutter = 0.6 + 0.4 * flutter / (np.max(np.abs(flutter)) + 1e-9)
        hiss = bp(r2.standard_normal(n), 1800, 9000) * 0.12 * flutter
        body = bp(r2.standard_normal(n), 400, 1800) * 0.05 * flutter
        ticks = bp((r2.random(n) < 0.004) * r2.standard_normal(n), 2500, 10000) * 0.5
        out.append(hiss + body + ticks)
    st = loopify(np.stack(out, 1), 3.0)
    write_ogg("amb_forest_rustle", st, 4)


ALL = {"amb_courtyard": amb_courtyard, "amb_forest": amb_forest, "steps": steps, "lamp_buzz": lamp_buzz, "amb_forest_rustle": amb_forest_rustle}

if __name__ == "__main__":
    for nm in sys.argv[1:] or list(ALL):
        ALL[nm]()

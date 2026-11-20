#!/usr/bin/env python3
"""Ambiences and sound effects (all synthesised, deterministic).

Writes assets/audio/*.ogg. Loops listed in tools/fix_imports.py LOOPS.
Usage: python3 tools/gen_sfx.py [name ...]
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


def write_ogg(name: str, x: np.ndarray, q: int = 4, peak_to: float = 0.89) -> None:
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


def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def loopify(x, xfade=2.0):
    """Crossfade the tail into the head so the file loops seamlessly."""
    n = int(xfade * SR)
    head = x[:n].copy()
    tail = x[-n:].copy()
    w = np.linspace(0, 1, n)
    if x.ndim > 1:
        w = w[:, None]
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1 - w)
    return x


def stereo(l, r):
    return np.stack([l, r], 1)


# ---------------------------------------------------------------------------
def rain_bed(n, rng, density=1.0):
    """Rain on a window and a roof: filtered noise + many tiny drops."""
    base = bp(rng.standard_normal(n), 400, 9000) * 0.08 * density
    slow = lp(rng.standard_normal(n), 0.4)
    slow = slow / (np.max(np.abs(slow)) + 1e-9)
    base *= 0.75 + 0.25 * slow
    drops = np.zeros(n)
    for _ in range(int(n / SR * 140 * density)):
        p = rng.integers(0, n - 2000)
        ln = rng.integers(300, 1500)
        f = rng.uniform(1800, 6000)
        t = np.arange(ln) / SR
        drops[p:p + ln] += np.sin(2 * np.pi * f * t * (1 - 0.3 * t * 40)) * np.exp(-t / 0.004) * rng.uniform(0.02, 0.12)
    return base + drops


def amb_stair():
    """Night in the stairwell of an old block: rain through a broken pane,
    wind moaning in the shaft, drips, pipes ticking, a far-off TV, a bulb."""
    rng = np.random.default_rng(1)
    dur = 64.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    L = rain_bed(n, rng, 0.8)
    R = rain_bed(n, rng, 0.8)
    # wind in the stairwell: resonant noise sweeping slowly
    for ch in (L, R):
        w = rng.standard_normal(n)
        cf = 320 + 140 * np.sin(2 * np.pi * t / 23.0 + rng.uniform(0, 6)) + 60 * np.sin(2 * np.pi * t / 7.3)
        out = np.zeros(n)
        blk = 2048
        for s in range(0, n, blk):
            f0 = float(cf[s])
            b, a = signal.iirpeak(f0 / (SR / 2), 6.0)
            out[s:s + blk] = signal.lfilter(b, a, w[s:s + blk])
        gust = 0.5 + 0.5 * np.sin(2 * np.pi * t / 17.0 + rng.uniform(0, 6)) ** 2
        ch += out * 0.05 * gust
    # low building rumble
    rum = lp(rng.standard_normal(n), 60) * 0.6
    L += rum
    R += rum
    # drips into a puddle (left), pipe ticks (right)
    for _ in range(46):
        p = rng.integers(0, n - 8000)
        ln = 6000
        tt = np.arange(ln) / SR
        f = rng.uniform(700, 1300)
        d = np.sin(2 * np.pi * f * tt * (1 + 2.5 * tt)) * np.exp(-tt / 0.03) * 0.25
        L[p:p + ln] += d
        R[p:p + ln] += d * 0.3
    for _ in range(18):
        p = rng.integers(0, n - 3000)
        ln = 2500
        tt = np.arange(ln) / SR
        k = bp(rng.standard_normal(ln), 1500, 5000) * np.exp(-tt / 0.006) * 0.35
        R[p:p + ln] += k
        L[p:p + ln] += k * 0.4
    # a bulb buzzing upstairs, coming and going
    buzz = (np.sin(2 * np.pi * 100 * t) + 0.5 * np.sin(2 * np.pi * 200 * t) + 0.25 * np.sign(np.sin(2 * np.pi * 100 * t))) * 0.01
    buzz *= 0.5 + 0.5 * (lp(rng.standard_normal(n), 0.8) > 0)
    L += buzz * 0.4
    R += buzz
    # muffled television through a wall, now and then
    tv = lp(rng.standard_normal(n), 900) * 0.0
    for _ in range(6):
        p = rng.integers(0, n - 6 * SR)
        ln = int(rng.uniform(2.0, 5.0) * SR)
        syll = (lp(rng.standard_normal(ln), 6) > 0).astype(float)
        voice = bp(rng.standard_normal(ln), 180, 900) * lp(syll, 20) * 0.12
        tv[p:p + ln] += voice
    L += tv * 0.6
    R += tv
    x = stereo(L, R)
    write_ogg("amb_stair", loopify(x), q=3)


def drone_eye():
    """Under the red eye: a sub drone, a slow dissonant cluster that breathes,
    a thin high whine and something like breathing through a wall."""
    rng = np.random.default_rng(2)
    dur = 48.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    L = np.zeros(n)
    R = np.zeros(n)
    for f, a in ((41.2, 0.5), (43.65, 0.3), (61.7, 0.25)):
        ph = rng.uniform(0, 6)
        L += a * np.sin(2 * np.pi * f * t + ph) * (0.8 + 0.2 * np.sin(2 * np.pi * t / 11))
        R += a * np.sin(2 * np.pi * f * 1.003 * t + ph + 0.5) * (0.8 + 0.2 * np.sin(2 * np.pi * t / 13))
    # dissonant string-like cluster (detuned saws, filtered), swelling
    for f in (220.0, 233.1, 246.9, 311.1, 329.6):
        for det in (-0.3, 0.3):
            ph = rng.uniform(0, 1)
            saw = 2 * ((f * (1 + det / 100) * t + ph) % 1.0) - 1
            sw = lp(saw, 1200) * 0.03
            swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / rng.uniform(9, 16) + rng.uniform(0, 6))
            if det < 0:
                L += sw * swell
            else:
                R += sw * swell
    whine = np.sin(2 * np.pi * 3520 * t + 2 * np.sin(2 * np.pi * 0.3 * t)) * 0.004
    L += whine
    R += whine * 0.7
    breath = bp(rng.standard_normal(n), 300, 1800) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 4.6)) ** 4 * 0.06
    L += breath * 0.7
    R += breath
    write_ogg("drone_eye", loopify(stereo(L, R)), q=3)


def glass_shatter():
    rng = np.random.default_rng(3)
    n = int(2.6 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    # impact crack
    imp = int(0.04 * SR)
    x[:imp] += hp(rng.standard_normal(imp), 1500) * env_exp(imp, 0.01) * 1.0
    x[:imp] += np.sin(2 * np.pi * 90 * t[:imp]) * env_exp(imp, 0.02) * 0.8
    # many shards: short high resonances scattered in time, falling
    for _ in range(260):
        p = int(min(rng.exponential(0.25), 1.8) * SR) + rng.integers(0, 400)
        ln = rng.integers(800, 6000)
        if p + ln >= n:
            continue
        tt = np.arange(ln) / SR
        f = rng.uniform(2500, 9500)
        s = np.sin(2 * np.pi * f * tt + rng.uniform(0, 6)) * np.exp(-tt / rng.uniform(0.004, 0.03))
        x[p:p + ln] += s * rng.uniform(0.05, 0.3) * np.exp(-p / SR / 0.8)
    x += hp(rng.standard_normal(n), 3000) * env_exp(n, 0.15) * 0.3
    write_ogg("glass_shatter", x)


def whoosh():
    rng = np.random.default_rng(4)
    n = int(1.8 * SR)
    t = np.arange(n) / SR
    e = np.sin(np.pi * np.clip(t / 1.8, 0, 1)) ** 2
    x = np.zeros(n)
    w = rng.standard_normal(n)
    blk = 1024
    for s in range(0, n, blk):
        f0 = 300 + 2500 * (s / n)
        b, a = signal.iirpeak(f0 / (SR / 2), 2.0)
        x[s:s + blk] = signal.lfilter(b, a, w[s:s + blk])
    write_ogg("whoosh", x * e)


def ring():
    n = int(4.0 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 6200 * t) * 0.5 + np.sin(2 * np.pi * 6260 * t) * 0.3
    x *= np.clip(t / 0.4, 0, 1) * np.clip((4.0 - t) / 0.8, 0, 1)
    write_ogg("ring", x)


ALL = {"amb_stair": amb_stair, "drone_eye": drone_eye, "glass_shatter": glass_shatter, "whoosh": whoosh, "ring": ring}


def cane_tap():
    """A white cane tip on concrete: a short dry knock, a few variants."""
    rng = np.random.default_rng(10)
    for i in range(1, 5):
        n = int(0.25 * SR)
        t = np.arange(n) / SR
        click = hp(rng.standard_normal(n), 1800) * np.exp(-t / 0.004) * 0.9
        body = np.sin(2 * np.pi * rng.uniform(900, 1400) * t) * np.exp(-t / 0.012) * 0.5
        tube = np.sin(2 * np.pi * rng.uniform(2400, 3100) * t) * np.exp(-t / 0.03) * 0.15   # aluminium ring
        grit = bp(rng.standard_normal(n), 2000, 7000) * np.exp(-t / 0.02) * 0.2
        write_ogg(f"cane_tap_{i}", click + body + tube + grit, peak_to=0.8)


def relay_click():
    rng = np.random.default_rng(11)
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    x = hp(rng.standard_normal(n), 800) * np.exp(-t / 0.003)
    x[int(0.035 * SR):] += hp(rng.standard_normal(n - int(0.035 * SR)), 1200) * np.exp(-t[:n - int(0.035 * SR)] / 0.002) * 0.6
    x += np.sin(2 * np.pi * 100 * t) * np.exp(-t / 0.08) * 0.08     # the bulb's hum starting
    write_ogg("relay_click", x, peak_to=0.6)


def thunder():
    rng = np.random.default_rng(12)
    for i in range(1, 3):
        n = int(7.0 * SR)
        t = np.arange(n) / SR
        crack_t = rng.uniform(0.0, 0.3)
        x = lp(rng.standard_normal(n), 120) * 3.0
        env = np.exp(-np.clip(t - crack_t, 0, None) / rng.uniform(1.2, 2.2)) * np.clip((t - crack_t) / 0.05, 0, 1)
        rumble = lp(rng.standard_normal(n), 60) * 2.0
        roll = 0.6 + 0.4 * np.sin(2 * np.pi * t * rng.uniform(0.8, 1.6)) ** 2
        y = (x * env + rumble * env * roll)
        y += bp(rng.standard_normal(n), 300, 2000) * np.exp(-np.clip(t - crack_t, 0, None) / 0.15) * (t > crack_t) * 0.5
        write_ogg(f"thunder_{i}", stereo(y, lp(y, 900) * 0.9 + y * 0.1), q=3)


def door_creak():
    rng = np.random.default_rng(13)
    n = int(2.4 * SR)
    t = np.arange(n) / SR
    f0 = 180 + 120 * np.sin(2 * np.pi * t / 2.4 * 0.8) + 30 * np.sin(2 * np.pi * 7 * t)
    ph = np.cumsum(f0) / SR * 2 * np.pi
    stick = (np.sin(ph) > 0.2).astype(float) * (rng.random(n) < 0.6)
    x = bp(stick * rng.standard_normal(n), 300, 3000) * 0.5 + np.sin(ph * 3) * 0.08
    env = np.clip(t / 0.2, 0, 1) * np.clip((2.4 - t) / 0.5, 0, 1)
    write_ogg("door_creak", x * env)


def door_slam():
    rng = np.random.default_rng(14)
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    x = lp(rng.standard_normal(n), 400) * np.exp(-t / 0.08) * 2.0 + np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.15)
    x += bp(rng.standard_normal(n), 1500, 4000) * np.exp(-t / 0.01) * 0.5
    # far away, up the stairwell: muffled and reverberant
    ir = rng.standard_normal(int(1.2 * SR)) * np.exp(-np.arange(int(1.2 * SR)) / (0.35 * SR))
    y = lp(signal.fftconvolve(x, ir)[:n], 900) * 0.3 + lp(x, 600)
    write_ogg("door_slam", y)


def drip():
    rng = np.random.default_rng(15)
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = 1100
    x = np.sin(2 * np.pi * f * t * (1 + 3 * t)) * np.exp(-t / 0.04)
    write_ogg("drip", x, peak_to=0.6)


ALL.update({"cane_tap": cane_tap, "relay_click": relay_click, "thunder": thunder,
            "door_creak": door_creak, "door_slam": door_slam, "drip": drip})


if __name__ == "__main__":
    names = sys.argv[1:] or list(ALL)
    for nm in names:
        ALL[nm]()

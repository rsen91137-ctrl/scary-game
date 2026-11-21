#!/usr/bin/env python3
"""Jump-scare stingers and hallucination sounds, synthesised with numpy.

A startle needs a near-instant onset and its energy where the ear is most
sensitive (1-5 kHz), roughened by 40-110 Hz modulation the way a scream is;
sub bass is kept well under the mid band. Twelve variants so no two scares in
a night sound alike. Run from the project root: python3 tools/gen_scare_sfx.py
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/audio"
SR = 44100


def write_ogg(name: str, x: np.ndarray, peak: float = 0.97, q: int = 5) -> None:
    x = np.asarray(x, np.float64)
    x = x / (np.abs(x).max() + 1e-9) * peak
    wav = OUT / f"_{name}.wav"
    sf.write(str(wav), x, SR, subtype="PCM_16")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", str(q), str(OUT / f"{name}.ogg")], check=True)
    wav.unlink()
    print("wrote", name, f"{len(x) / SR:.2f}s")


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def env(n, attack, hold, release):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    e *= np.where(t < hold, 1.0, np.exp(-(t - hold) / release))
    return e


def room(x, rng, secs=0.9, mix=0.22):
    n = int(secs * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (secs * 0.22 * SR))
    ir = hp(ir, 300)
    wet = signal.fftconvolve(x, ir)
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return dry + wet / (np.abs(wet).max() + 1e-9) * np.abs(x).max() * mix


def drive(x, g):
    return np.tanh(x / (np.abs(x).max() + 1e-9) * g)


def slam(n, rng, lo=700, hi=6500, tau=0.07):
    x = rng.standard_normal(n) * np.exp(-np.arange(n) / (tau * SR))
    return bp(x, lo, hi) + 0.5 * hp(x, 5000) * np.exp(-np.arange(n) / (0.02 * SR))


def sub(n, f=58.0, tau=0.22):
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * (f * t + 30.0 * tau * (1 - np.exp(-t / 0.05)))) * np.exp(-t / tau)


def shriek(rng, dur, f_lo, f_hi, rough, breath=0.35):
    """A woman's scream: a jump in pitch, harsh subharmonics, bright formants."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = f_lo + (f_hi - f_lo) * (1 - np.exp(-t / 0.025))
    f0 = f0 * (1.0 - 0.22 * (t / dur) ** 2)
    f0 = f0 * (1.0 + 0.035 * np.sin(2 * np.pi * rng.uniform(5, 8) * t) + 0.02 * lp(rng.standard_normal(n), 40) * 6)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    x = np.zeros(n)
    for k in range(1, 9):
        x += np.sin(ph * k + rng.uniform(0, 6.28)) / k ** 0.8
    # subharmonic break-up and a 40-110 Hz rasp
    x += 0.7 * np.sin(ph * 0.5) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rng.uniform(2, 5) * t)))
    x *= 1.0 - 0.75 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rough * t + lp(rng.standard_normal(n), 30) * 20)))
    y = bp(x, 900, 1500) * 1.0 + bp(x, 2400, 3400) * 1.5 + bp(x, 3500, 4700) * 1.1
    y += breath * bp(rng.standard_normal(n), 2500, 8000) * np.abs(y).max() * 0.5
    return drive(y, 3.5) * env(n, 0.003, dur * 0.62, dur * 0.16)


def scrape(rng, dur, n_part=18):
    """Bowed piano wire: a dissonant cluster, every partial grinding."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for _ in range(n_part):
        f = rng.uniform(950, 4800) * (1.0 + rng.uniform(-0.05, 0.08) * t / dur)
        am = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(35, 110) * t + rng.uniform(0, 6.28))
        x += np.sin(2 * np.pi * np.cumsum(f) / SR + 2.5 * np.sin(2 * np.pi * rng.uniform(60, 240) * t)) * am * rng.uniform(0.4, 1.0)
    return drive(x, 2.6) * env(n, 0.002, dur * 0.5, dur * 0.2)


def piano_smash(rng, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    notes = list(rng.uniform(28, 40, 7)) + list(rng.uniform(72, 96, 9))
    for m in notes:
        f = 440.0 * 2 ** ((m - 69) / 12.0)
        for k in range(1, 12):
            fk = f * k * np.sqrt(1 + 0.0007 * k * k)
            if fk > 9000:
                break
            x += np.sin(2 * np.pi * fk * t + rng.uniform(0, 6.28)) * np.exp(-t * (1.2 + 0.5 * k)) / k ** 0.6
    x = x / np.abs(x).max()
    return drive(x + 0.6 * slam(n, rng, 500, 5000, 0.03) / 3.0, 2.8)


def stingers() -> None:
    k = 0
    recipes = [
        ("shriek", 1.25, 820, 1650, 71), ("scrape", 1.3), ("slam", 1.0), ("shriek", 0.95, 1000, 2100, 96),
        ("piano", 1.9), ("scrape", 0.9), ("shriek", 1.5, 640, 1380, 54), ("slam", 1.3),
        ("shriek", 1.1, 900, 1900, 83), ("piano", 1.6), ("scrape", 1.6), ("shriek", 1.35, 760, 1750, 64),
    ]
    for r in recipes:
        k += 1
        rng = np.random.default_rng(900 + k)
        dur = r[1]
        n = int(dur * SR)
        hit = slam(n, rng) / 3.0
        if r[0] == "shriek":
            body = shriek(rng, dur, r[2], r[3], r[4]) + 0.5 * scrape(rng, dur, 8)
            x = body + 0.8 * hit
        elif r[0] == "scrape":
            x = scrape(rng, dur) + 0.9 * hit + 0.35 * shriek(rng, dur, 1100, 2300, 88, 0.6)
        elif r[0] == "piano":
            x = piano_smash(rng, dur) + 0.5 * scrape(rng, dur, 10)
        else:
            x = 1.6 * hit + 0.8 * scrape(rng, dur, 14) + 0.5 * shriek(rng, dur, 700, 1500, 60)
        x = x / np.abs(x).max()
        x = x + 0.28 * sub(n)                      # felt, not heard: kept under the mids
        x[: int(0.0015 * SR)] *= np.linspace(0, 1, int(0.0015 * SR))
        write_ogg(f"scare_{k:02d}", room(drive(x, 2.2), rng))


def screams() -> None:
    # her scream, close and dry, laid over every big hit
    specs = ((1.7, 760, 1700, 62), (2.2, 880, 2050, 88), (1.4, 1000, 2300, 104), (2.0, 680, 1520, 48),
             (1.6, 940, 1880, 76), (2.4, 820, 1960, 58))
    for i, (dur, lo, hi, r) in enumerate(specs, 1):
        rng = np.random.default_rng(300 + i)
        x = shriek(rng, dur, lo, hi, r, 0.55)
        # a second voice a hair behind it, cracking: one throat tearing
        y = shriek(rng, dur, lo * 1.007, hi * 0.992, r * 1.31, 0.3)
        x = x + 0.55 * np.concatenate([np.zeros(300), y[:-300]])
        x[: int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
        write_ogg(f"scream_{i}", room(drive(x, 3.0), rng, 0.7, 0.16))


def extras() -> None:
    rng = np.random.default_rng(77)
    # a scream from another room: only in your head
    for i, (lo, hi, r) in enumerate(((700, 1500, 66), (850, 1800, 90)), 1):
        x = shriek(rng, 1.8, lo, hi, r, 0.5)
        x = lp(room(x, rng, 1.6, 0.9), 2600)
        write_ogg(f"scream_far_{i}", x, 0.8)
    # a fist on a door
    for i in (1, 2):
        n = int(0.9 * SR)
        x = np.zeros(n)
        for at in ((0.0, 1.0), (0.24, 0.85), (0.5, 1.0))[: 2 + i]:
            j = int(at[0] * SR)
            seg = n - j
            t = np.arange(seg) / SR
            x[j:] += at[1] * (np.sin(2 * np.pi * 82 * t) * np.exp(-t / 0.07) + 0.6 * bp(rng.standard_normal(seg), 200, 1800) * np.exp(-t / 0.02))
        write_ogg(f"bang_{i}", room(x, rng, 0.6, 0.3), 0.95)
    # the tick under a single flashed frame
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    x = slam(n, rng, 1800, 7000, 0.012) + 0.5 * np.sin(2 * np.pi * 3100 * t) * np.exp(-t / 0.03)
    write_ogg("flash_tick", x, 0.9)
    # breath on your neck
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    x = bp(rng.standard_normal(n), 500, 3200) * np.sin(np.pi * t / 1.6) ** 2 * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t))
    write_ogg("breath_near", x, 0.7)
    # wet flesh: something heavy and soft landing
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    x = lp(rng.standard_normal(n), 900) * np.exp(-t / 0.05) + 0.7 * sub(n, 70, 0.1) + 0.4 * bp(rng.standard_normal(n), 1500, 5000) * np.exp(-t / 0.015)
    write_ogg("wet_thud", x, 0.95)
    # every wire in the piano let go at once, low and long: dread under a set piece
    n = int(4.0 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f in (41.2, 43.7, 55.0, 58.3, 82.4, 87.3, 116.5):
        x += np.sin(2 * np.pi * f * t * (1 + 0.002 * np.sin(2 * np.pi * 0.3 * t)) + rng.uniform(0, 6.28)) * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(0.2, 0.9) * t))
    x += 0.25 * bp(rng.standard_normal(n), 300, 900) * (t / 4.0) ** 2
    write_ogg("dread_swell", x * np.sin(np.pi * t / 4.0) ** 1.5, 0.6)


if __name__ == "__main__":
    import sys
    if "--screams" in sys.argv:
        screams()
    else:
        stingers()
        screams()
        extras()

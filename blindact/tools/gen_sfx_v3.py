#!/usr/bin/env python3
"""Sounds for the long night (v3): locks and keys, the WC, the kitchen,
dinner, the camera, the attic, the secret doors. numpy synthesis only.
Run from the project root: python3 tools/gen_sfx_v3.py
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
RNG = np.random.default_rng(2024)


def write(name: str, x: np.ndarray, peak: float = 0.9, q: int = 4) -> None:
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


def n(secs):
    return RNG.standard_normal(int(secs * SR))


def t_(secs):
    return np.arange(int(secs * SR)) / SR


def dec(secs, tau):
    return np.exp(-t_(secs) / tau)


def place(total, events):
    out = np.zeros(int(total * SR))
    for at, x in events:
        i = int(at * SR)
        j = min(len(out), i + len(x))
        out[i:j] += x[: j - i]
    return out


def room(x, secs=0.5, mix=0.2):
    m = int(secs * SR)
    ir = RNG.standard_normal(m) * np.exp(-np.arange(m) / (secs * 0.25 * SR))
    wet = signal.fftconvolve(x, hp(ir, 200))
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return dry + wet / (np.abs(wet).max() + 1e-9) * np.abs(x).max() * mix


def click(f=3000, tau=0.004, secs=0.05):
    return bp(n(secs), f * 0.6, f * 1.6) * dec(secs, tau)


def metal_ring(freqs, secs, tau):
    t = t_(secs)
    return sum(np.sin(2 * np.pi * f * t + RNG.uniform(0, 6)) * np.exp(-t / (tau * (1 + 0.3 * i))) for i, f in enumerate(freqs))


def main() -> None:
    # a key turned in an old lock: insert, two turns of the bolt
    x = place(1.4, [(0.0, bp(n(0.18), 1500, 6000) * dec(0.18, 0.05) * 0.4), (0.35, click(2200, 0.006)), (0.42, click(1500, 0.01) * 1.4),
                    (0.8, click(2400, 0.006)), (0.88, click(1300, 0.012) * 1.6), (0.9, lp(n(0.2), 300) * dec(0.2, 0.04) * 0.8)])
    write("key_lock", room(x, 0.4, 0.15))
    # keys on a ring
    ev = [(RNG.uniform(0, 0.7), metal_ring(RNG.uniform(2500, 7000, 3), 0.4, 0.05) * RNG.uniform(0.3, 1.0)) for _ in range(14)]
    write("keys_jingle", place(1.2, ev))
    # steps coming up the stairwell outside, getting closer
    ev = []
    for i in range(14):
        k = i / 13.0
        s = lp(n(0.25), 600) * dec(0.25, 0.04) + 0.3 * bp(n(0.25), 1500, 4000) * dec(0.25, 0.01)
        ev.append((i * 0.55, s * (0.15 + 0.85 * k)))
    write("stair_steps_up", room(place(8.0, ev), 1.2, 0.5))
    # a WC cistern: the chain, the gush, the refill
    t = t_(6.0)
    gush = bp(n(6.0), 200, 3000) * np.minimum(1.0, t / 0.15) * np.exp(-np.maximum(t - 1.2, 0) / 1.4)
    fill = bp(n(6.0), 600, 2500) * 0.25 * np.clip((t - 2.0) / 0.5, 0, 1) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t))
    write("toilet_flush", room(place(6.0, [(0.0, click(1200, 0.02, 0.1) * 2.0)]) + gush + fill, 0.6, 0.3))
    # a newspaper page turned
    x = bp(n(0.7), 800, 7000) * (np.abs(lp(n(0.7), 18)) * 6) * dec(0.7, 0.25)
    write("newspaper", x)
    write("paper_rustle", bp(n(0.5), 1200, 8000) * (np.abs(lp(n(0.5), 25)) * 6) * dec(0.5, 0.15))
    # a man's cough behind a door
    ev = []
    for i in range(2):
        seg = bp(n(0.3), 150, 1800) * dec(0.3, 0.07) * (1 + 0.5 * np.sin(2 * np.pi * 110 * t_(0.3)))
        ev.append((i * 0.42, seg))
    write("cough_man", lp(place(1.0, ev), 1500))
    # a zip
    x = bp(n(0.5), 1500, 6000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 70 * t_(0.5)))) * np.sin(np.pi * t_(0.5) / 0.5)
    write("zipper", x)
    # the cleaver: through meat into the block, sometimes bone
    for i in range(1, 5):
        wet = lp(n(0.5), 900) * dec(0.5, 0.05)
        thunk = np.sin(2 * np.pi * (110 + 20 * i) * t_(0.5)) * dec(0.5, 0.06)
        crack = bp(n(0.5), 1500, 5000) * dec(0.5, 0.012) * (1.6 if i % 2 == 0 else 0.4)
        write(f"chop_{i}", room(wet + 1.2 * thunk + crack, 0.4, 0.2))
    # a stock pot at the boil (loop)
    secs = 6.0
    x = np.zeros(int(secs * SR))
    for _ in range(260):
        at = int(RNG.uniform(0, secs - 0.1) * SR)
        f = RNG.uniform(250, 900)
        ln = int(0.06 * SR)
        b = np.sin(2 * np.pi * f * np.arange(ln) / SR * (1 + np.arange(ln) / ln)) * np.exp(-np.arange(ln) / (0.015 * SR))
        x[at:at + ln] += b * RNG.uniform(0.2, 1.0)
    x += 0.15 * lp(n(secs), 400)
    fade = int(0.5 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    write("boil_loop", x[:-fade], 0.6)
    # china on wood
    write("plate_set", room(metal_ring([2100, 3300, 5200], 0.6, 0.08) * 0.6 + lp(n(0.6), 500) * dec(0.6, 0.02), 0.3, 0.15))
    write("cutlery_1", place(0.8, [(0.0, metal_ring([3800, 6100], 0.4, 0.05)), (0.12, metal_ring([4300, 7000], 0.4, 0.05) * 0.7), (0.3, metal_ring([3500], 0.4, 0.04) * 0.5)]))
    write("cutlery_2", place(0.6, [(0.0, metal_ring([4100, 6600], 0.4, 0.06)), (0.18, metal_ring([3900], 0.3, 0.05) * 0.6)]))
    # a fridge door: the seal, the hum
    t = t_(2.0)
    x = place(2.0, [(0.0, lp(n(0.3), 700) * dec(0.3, 0.06))]) + 0.3 * np.sin(2 * np.pi * 50 * t) * (t > 0.2) + 0.15 * np.sin(2 * np.pi * 100 * t) * (t > 0.2)
    write("fridge_open", x * np.minimum(1, (2.0 - t) / 0.4))
    # chewing (wet), swallowing
    for i in range(1, 4):
        ev = []
        for k in range(5):
            ev.append((k * 0.28 + RNG.uniform(0, 0.05), bp(n(0.2), 300, 2500) * dec(0.2, 0.05) * (1 + np.abs(lp(n(0.2), 40)) * 3)))
        write(f"chew_{i}", lp(place(1.6, ev), 3000), 0.7)
    t = t_(0.6)
    write("swallow", lp(n(0.6), 500) * np.exp(-((t - 0.25) / 0.08) ** 2) + 0.6 * np.sin(2 * np.pi * 180 * t) * np.exp(-((t - 0.28) / 0.05) ** 2), 0.7)
    # wine (thick) poured into a glass
    t = t_(2.2)
    x = bp(n(2.2), 400, 3000) * (0.5 + 0.5 * np.sin(2 * np.pi * (6 + 3 * t) * t)) * np.minimum(1, t / 0.1) * np.minimum(1, (2.2 - t) / 0.3)
    write("wine_pour", x + 0.3 * metal_ring([1800, 2900], 2.2, 0.6) * (t < 0.1))
    # a flash gun: the pop, the whine of the recharge
    t = t_(2.5)
    pop = bp(n(2.5), 800, 8000) * dec(2.5, 0.01) * 2
    whine = np.sin(2 * np.pi * np.cumsum(1200 + 2600 * np.minimum(1, t / 2.0)) / SR) * 0.12 * (t > 0.15)
    write("camera_flash", pop + whine)
    ev = [(0.05 * i, click(2600, 0.003, 0.03) * 0.8) for i in range(12)]
    write("camera_wind", place(0.9, ev))
    # an iron bed taking weight
    t = t_(1.4)
    x = np.sin(2 * np.pi * np.cumsum(300 + 60 * np.sin(2 * np.pi * 1.3 * t)) / SR) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 37 * t))) * np.sin(np.pi * t / 1.4)
    write("bed_creak", bp(x, 250, 2500) * 0.8 + 0.2 * lp(n(1.4), 300) * np.sin(np.pi * t / 1.4))
    # nails on wood, under the bed
    ev = [(i * 0.33 + RNG.uniform(0, 0.08), bp(n(0.25), 1800, 6000) * np.sin(np.pi * t_(0.25) / 0.25) * (np.abs(lp(n(0.25), 60)) * 5)) for i in range(7)]
    write("scratch", place(2.6, ev))
    # sirens, a long way off, coming
    t = t_(7.0)
    f = 700 + 300 * np.sin(2 * np.pi * 0.45 * t)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(2 * np.pi * np.cumsum(2 * f) / SR)
    write("siren_far", lp(x, 1800) * np.minimum(1, t / 6.0) * 0.5 + 0.05 * lp(n(7.0), 300))
    # the bookcase: wood grinding on a hidden track
    t = t_(1.6)
    x = bp(n(1.6), 120, 900) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t)) * np.sin(np.pi * t / 1.6) + 0.5 * place(1.6, [(1.45, lp(n(0.15), 300) * dec(0.15, 0.03))])
    write("bookcase_grind", room(x, 0.5, 0.2))
    write("safe_click", place(0.9, [(0.0, click(3200, 0.003)), (0.25, click(3000, 0.003)), (0.5, click(3400, 0.003)), (0.75, click(2800, 0.004))]))
    write("safe_open", place(1.4, [(0.0, click(2600, 0.004)), (0.2, click(2500, 0.004)), (0.45, click(1500, 0.015) * 2), (0.6, lp(n(0.6), 500) * dec(0.6, 0.15) * 0.5)]))
    t = t_(1.2)
    write("ladder_creak", bp(np.sin(2 * np.pi * np.cumsum(500 + 120 * np.sin(2 * np.pi * 2 * t)) / SR) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 23 * t))), 300, 3000) * np.sin(np.pi * t / 1.2))
    # nails screaming out of a window frame
    t = t_(2.4)
    sq = np.sin(2 * np.pi * np.cumsum(900 + 500 * np.sin(2 * np.pi * 1.7 * t) + 200 * RNG.standard_normal(len(t)) * 0.02) / SR) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 61 * t)))
    write("nails_pry", room(bp(sq, 500, 5000) * (0.3 + 0.7 * np.abs(np.sin(np.pi * t / 0.8))) + place(2.4, [(2.2, lp(n(0.2), 400) * dec(0.2, 0.03) * 2)]), 0.5, 0.2))
    # rain on a roof right over your head (loop)
    secs = 8.0
    x = hp(n(secs), 600) * 0.25 + lp(n(secs), 250) * 0.2
    for _ in range(int(secs * 900)):
        at = int(RNG.uniform(0, secs - 0.01) * SR)
        x[at:at + 40] += bp(RNG.standard_normal(40), 1500, 6000) * RNG.uniform(0.05, 0.4)
    fade = int(0.6 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    write("roof_rain_loop", x[:-fade], 0.55)

    # leaves in the wind: thousands of tiny ticks over a soft hiss (loop)
    secs = 8.0
    x = bp(n(secs), 1800, 9000) * 0.18
    for _ in range(int(secs * 2600)):
        at = int(RNG.uniform(0, secs - 0.01) * SR)
        ln = int(RNG.uniform(0.002, 0.008) * SR)
        x[at:at + ln] += bp(RNG.standard_normal(ln), 2500, 9500)[:ln] * RNG.uniform(0.02, 0.22) * np.hanning(ln)
    x *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.35 * np.arange(len(x)) / SR)
    fade = int(0.6 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    write("leaves_rustle_loop", x[:-fade], 0.6)
    # wind through pines: a deep, slowly breathing roar (loop)
    secs = 10.0
    t = t_(secs)
    x = lp(n(secs), 500) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t)) + bp(n(secs), 300, 1400) * 0.35 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t + 1.0))
    fade = int(0.8 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    write("wind_loop", x[:-fade], 0.6)


if __name__ == "__main__":
    main()

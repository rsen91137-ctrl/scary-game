#!/usr/bin/env python3
"""An old, slightly out-of-tune upright piano, synthesised.

Writes assets/audio/piano/:
  pn_<midi>.ogg        clean-ish notes every 3 semitones, A1 (33) .. C7 (96);
                       the game picks the nearest and pitch-shifts <= 1.5 st
  pnb_thud_<i>.ogg     broken: a dead key, felt and wood, almost no tone
  pnb_buzz_<i>.ogg     broken: a loose string rattling against the frame
  pnb_sour_<i>.ogg     broken: the unison strings wildly apart
  pnr_<midi>.ogg       reversed swells (for the menu)

Model per note: 2-3 strings detuned by a few cents (old piano, more spread
in the treble), inharmonic partials f_k = k f0 sqrt(1 + B k^2), hammer
spectrum with the strike-point comb, two-stage (prompt + aftersound) decay
that is faster for high partials, a felt/wood thump at the attack and a
soundboard EQ. Deterministic (seeded).
Usage: python3 tools/gen_piano.py
"""
from __future__ import annotations

import math
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "piano"
OUT.mkdir(parents=True, exist_ok=True)
SR = 44100


def write_ogg(path: Path, x: np.ndarray, q: int = 5) -> None:
    x = np.asarray(x, np.float32)
    peak = float(np.max(np.abs(x))) or 1.0
    x = x / peak * 0.89
    wav = path.with_suffix(".wav")
    sf.write(str(wav), x, SR, subtype="PCM_16")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", str(q), str(path)], check=True)
    wav.unlink()


def biquad_peak(x, f0, gain_db, q):
    A = 10 ** (gain_db / 40)
    w0 = 2 * math.pi * f0 / SR
    alpha = math.sin(w0) / (2 * q)
    b = [1 + alpha * A, -2 * math.cos(w0), 1 - alpha * A]
    a = [1 + alpha / A, -2 * math.cos(w0), 1 - alpha / A]
    return signal.lfilter(b, a, x)


def soundboard(x):
    for f0, g, q in ((110, 3.0, 1.2), (240, 2.0, 1.5), (520, -2.5, 1.0), (1800, 1.5, 1.4), (3800, -4.0, 0.8)):
        x = biquad_peak(x, f0, g, q)
    b, a = signal.butter(2, 7500 / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def note(midi: int, vel: float = 0.8, seed: int = 0, detune_cents: float | None = None,
         length: float | None = None, damp: float = 1.0, rattle: float = 0.0) -> np.ndarray:
    rng = np.random.default_rng(seed * 1000 + midi)
    f0 = 440.0 * 2 ** ((midi - 69) / 12)
    if length is None:
        length = float(np.interp(midi, [21, 60, 108], [7.0, 4.5, 2.2]))
    n = int(length * SR)
    t = np.arange(n) / SR
    nstr = 2 if midi < 45 else 3
    spread = detune_cents if detune_cents is not None else float(np.interp(midi, [21, 60, 108], [2.5, 4.0, 7.0]))
    # an old piano is not tuned evenly: each note gets its own offset too
    note_off = rng.normal(0, 3.0)
    B = float(np.interp(midi, [21, 40, 70, 108], [0.0009, 0.00025, 0.0004, 0.0018]))
    tau0 = float(np.interp(midi, [21, 60, 108], [9.0, 4.0, 1.2])) * damp
    alpha = np.interp(vel, [0.2, 1.0], [1.9, 1.05])
    strike = rng.uniform(0.11, 0.14)
    y = np.zeros(n)
    kmax = int(min(40, (SR * 0.42) / f0))
    for s in range(nstr):
        cents = note_off + (s - (nstr - 1) / 2) * spread + rng.normal(0, spread * 0.25)
        fs = f0 * 2 ** (cents / 1200)
        ph = rng.uniform(0, 2 * np.pi, kmax + 1)
        for k in range(1, kmax + 1):
            fk = k * fs * math.sqrt(1 + B * k * k)
            if fk > SR * 0.45:
                break
            amp = (1.0 / k ** alpha) * abs(math.sin(math.pi * k * strike)) ** 0.6
            tau_fast = tau0 * 0.18 / (1 + 0.25 * k)
            tau_slow = tau0 / (1 + 0.09 * k)
            env = 0.65 * np.exp(-t / tau_fast) + 0.35 * np.exp(-t / tau_slow)
            # slight pitch wobble of the old soundboard
            wob = 1.0 + 0.0004 * np.sin(2 * np.pi * (0.6 + 0.3 * s) * t + ph[k])
            y += amp * env * np.sin(2 * np.pi * fk * t * wob + ph[k])
    y /= nstr
    # attack shaping (a few ms) and the hammer/felt thump
    att = np.clip(t / 0.0025, 0, 1)
    y *= att
    thump_n = int(0.06 * SR)
    thump = rng.standard_normal(thump_n)
    b, a = signal.butter(2, [60 / (SR / 2), min(0.99, (900 + f0) / (SR / 2))], "band")
    thump = signal.lfilter(b, a, thump) * np.exp(-np.arange(thump_n) / (0.012 * SR))
    y[:thump_n] += thump * 0.12 * vel
    knock = np.sin(2 * np.pi * 95 * t[:thump_n]) * np.exp(-np.arange(thump_n) / (0.008 * SR))
    y[:thump_n] += knock * 0.08 * vel
    if rattle > 0:
        # a loose string buzzing against something metallic
        env = np.exp(-t / (tau0 * 0.5))
        carrier = np.sign(np.sin(2 * np.pi * f0 * t)) * env
        noise = rng.standard_normal(n)
        b, a = signal.butter(2, [1500 / (SR / 2), 6000 / (SR / 2)], "band")
        buzz = signal.lfilter(b, a, noise) * (carrier > 0.3) * env
        y += buzz * rattle * 0.5
    y = soundboard(y)
    # fade the tail to zero
    fade = int(0.08 * SR)
    y[-fade:] *= np.linspace(1, 0, fade)
    return y * vel


def thud(seed: int, midi: int) -> np.ndarray:
    """A dead key: the hammer hits felt and wood, a ghost of pitch."""
    y = note(midi, vel=0.9, seed=seed, length=1.2, damp=0.05)
    rng = np.random.default_rng(seed)
    n = len(y)
    t = np.arange(n) / SR
    wood = rng.standard_normal(n)
    b, a = signal.butter(2, [80 / (SR / 2), 1200 / (SR / 2)], "band")
    wood = signal.lfilter(b, a, wood) * np.exp(-t / 0.05)
    clunk = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.06)
    return y * 0.6 + wood * 0.5 + clunk * 0.4


def main():
    for midi in range(33, 97, 3):
        write_ogg(OUT / f"pn_{midi}.ogg", note(midi, vel=0.8, seed=1))
    for i, midi in enumerate((36, 43, 50, 55, 62, 69)):
        write_ogg(OUT / f"pnb_thud_{i}.ogg", thud(i + 10, midi))
    for i, midi in enumerate((38, 45, 52, 57, 64, 71)):
        write_ogg(OUT / f"pnb_buzz_{i}.ogg", note(midi, vel=0.95, seed=20 + i, rattle=1.0))
    for i, midi in enumerate((40, 47, 54, 59, 66, 73)):
        write_ogg(OUT / f"pnb_sour_{i}.ogg", note(midi, vel=0.85, seed=30 + i, detune_cents=38.0))
    for midi in (36, 45, 51, 57, 63):
        y = note(midi, vel=0.85, seed=40, length=4.0)
        y = y[::-1].copy()
        # cut the reversed attack into a short choke at the end
        y[-int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))
        write_ogg(OUT / f"pnr_{midi}.ogg", y)
    print("piano samples written to", OUT)


if __name__ == "__main__":
    main()

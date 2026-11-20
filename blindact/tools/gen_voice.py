#!/usr/bin/env python3
"""The man's whispers and mutterings.

Lines are spoken by espeak-ng (Mandarin `cmn`, English MBROLA `us2`), then
turned into a real whisper: frame-by-frame LPC analysis keeps the vocal
tract (what makes the words) and the voiced excitation is replaced by
breath noise. Slowed a little (deeper, more male), EQ'd, given a breathy
top and a short dark room. Mutterings are low voiced nonsense through a wall.

Writes assets/audio/voice/whisper_{zh,en}_{n}.ogg and murmur_{n}.ogg.
The subtitle text for each line lives in scripts/i18n.gd (WHISPER_n).
Usage: python3 tools/gen_voice.py
"""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "voice"
OUT.mkdir(parents=True, exist_ok=True)
SR = 22050

LINES = [
    ("我看见你了。", "I see you."),
    ("你看得见……对吧？", "You can see… can't you?"),
    ("别回头。", "Don't look back."),
    ("继续弹。", "Keep playing."),
    ("嘘……", "Shh…"),
    ("她还在等你。", "She's still waiting for you."),
    ("你在发抖。", "You're shaking."),
    ("别出声。", "Don't make a sound."),
    ("下一个，就是你。", "You're next."),
    ("睁开眼睛。", "Open your eyes."),
    ("你不是瞎子。", "You're not blind."),
    ("进来吧。", "Come in."),
]


def espeak(text: str, voice: str, speed: int, pitch: int) -> np.ndarray:
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "v.wav"
        subprocess.run(["espeak-ng", "-v", voice, "-s", str(speed), "-p", str(pitch), "-w", str(wav), text], check=True)
        x, sr = sf.read(str(wav))
    if x.ndim > 1:
        x = x.mean(1)
    if sr != SR:
        x = signal.resample_poly(x, SR, sr)
    return x.astype(np.float64)


def lpc(seg: np.ndarray, order: int) -> np.ndarray:
    r = np.correlate(seg, seg, "full")[len(seg) - 1: len(seg) + order]
    if r[0] <= 1e-9:
        return np.r_[1.0, np.zeros(order)]
    r[0] *= 1.0001
    a = np.zeros(order + 1)
    a[0] = 1.0
    e = r[0]
    for i in range(1, order + 1):
        acc = r[i] + np.dot(a[1:i], r[i - 1:0:-1])
        k = -acc / e
        a_new = a.copy()
        a_new[1:i] = a[1:i] + k * a[i - 1:0:-1]
        a_new[i] = k
        a = a_new
        e *= (1 - k * k)
        if e <= 1e-12:
            break
    return a


def whisperize(x: np.ndarray, seed: int, order: int = 22) -> np.ndarray:
    rng = np.random.default_rng(seed)
    N = int(0.03 * SR)
    H = N // 2
    win = np.hanning(N)
    out = np.zeros(len(x) + N)
    pre = signal.lfilter([1, -0.9], [1], x)   # pre-emphasis for a better fit
    for start in range(0, len(x) - N, H):
        seg = pre[start:start + N] * win
        if np.sqrt(np.mean(seg ** 2)) < 1e-4:
            continue
        a = lpc(seg, order)
        res = signal.lfilter(a, [1], seg)
        g = np.sqrt(np.mean(res ** 2))
        y = signal.lfilter([1], a, rng.standard_normal(N) * g)
        out[start:start + N] += y * win
    out = signal.lfilter([1], [1, -0.9], out)   # de-emphasis
    return out[:len(x)]


def room(x: np.ndarray, seed: int, length: float = 0.55, wet: float = 0.18) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(length * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (0.12 * SR))
    b, a = signal.butter(2, 3500 / (SR / 2), "low")
    ir = signal.lfilter(b, a, ir)
    ir /= np.sqrt(np.sum(ir ** 2))
    return x + signal.fftconvolve(x, ir)[:len(x)] * wet


def finish(x: np.ndarray, hp: float = 160, lp: float = 7000) -> np.ndarray:
    b, a = signal.butter(2, [hp / (SR / 2), lp / (SR / 2)], "band")
    x = signal.lfilter(b, a, x)
    pad = int(0.25 * SR)
    x = np.r_[np.zeros(int(0.03 * SR)), x, np.zeros(pad)]
    f = int(0.02 * SR)
    x[:f] *= np.linspace(0, 1, f)
    x[-pad:] *= np.linspace(1, 0, pad)
    return x


def write_ogg(path: Path, x: np.ndarray) -> None:
    peak = float(np.max(np.abs(x))) or 1.0
    x = (x / peak * 0.85).astype(np.float32)
    wav = path.with_suffix(".wav")
    sf.write(str(wav), x, SR, subtype="PCM_16")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4", str(path)], check=True)
    wav.unlink()


def whisper_line(text: str, voice: str, speed: int, pitch: int, seed: int) -> np.ndarray:
    x = espeak(text, voice, speed, pitch)
    w1 = whisperize(x, seed)
    w2 = whisperize(x, seed + 99)
    # two breaths of the same words a hair apart: closer, wrong
    d = int(0.018 * SR)
    w = w1 + np.r_[np.zeros(d), w2[:-d]] * 0.55
    # slow down: lower formants, a heavier, more male whisper
    w = signal.resample(w, int(len(w) / 0.86))
    env = np.abs(signal.hilbert(w))
    env = signal.lfilter([1], [1, -0.995], env) * 0.005
    rng = np.random.default_rng(seed + 7)
    b, a = signal.butter(2, 3000 / (SR / 2), "high")
    breath = signal.lfilter(b, a, rng.standard_normal(len(w))) * env * 0.6
    w = w + breath
    w = room(w, seed)
    return finish(w)


def murmur(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    syl = ["ma", "no", "di", "ra", "hu", "ke", "lo", "sa", "ve", "mi", "do", "ru", "ne", "ta", "go", "ha"]
    words = []
    for _ in range(rng.integers(8, 14)):
        words.append("".join(rng.choice(syl, rng.integers(1, 4))))
    text = " ".join(words)
    x = espeak(text, "mb-us2", 95, 12)
    # through a wall: muffled, dull, a little room
    b, a = signal.butter(3, 700 / (SR / 2), "low")
    x = signal.lfilter(b, a, x)
    x = room(x, seed, 0.8, 0.35)
    return finish(x, hp=70, lp=1500)


def main():
    for i, (zh, en) in enumerate(LINES, start=1):
        write_ogg(OUT / f"whisper_zh_{i}.ogg", whisper_line(zh, "cmn", 105, 25, 100 + i))
        write_ogg(OUT / f"whisper_en_{i}.ogg", whisper_line(en, "mb-us2", 115, 30, 200 + i))
        print("line", i, zh, en)
    for i in range(1, 5):
        write_ogg(OUT / f"murmur_{i}.ogg", murmur(300 + i))
    print("voices written to", OUT)


if __name__ == "__main__":
    main()

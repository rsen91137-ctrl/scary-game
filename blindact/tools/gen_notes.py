#!/usr/bin/env python3
"""Hand-inked musical note sprites that float up with the broken piano.

White ink on transparent (tinted red in the game), rough edges, 256x256.
Writes assets/ui/notes/note_<name>.png.
Usage: python3 tools/gen_notes.py
"""
from __future__ import annotations

import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

import texlib as T

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui" / "notes"
OUT.mkdir(parents=True, exist_ok=True)
S = 4                     # supersampling
W = H = 256


def canvas():
    im = Image.new("L", (W * S, H * S), 0)
    return im, ImageDraw.Draw(im)


def head(d, cx, cy, filled=True, scale=1.0):
    rx, ry = 30 * S * scale, 21 * S * scale
    pts = []
    for i in range(48):
        a = 2 * math.pi * i / 48
        x, y = rx * math.cos(a), ry * math.sin(a)
        r = math.radians(-24)
        pts.append((cx + x * math.cos(r) - y * math.sin(r), cy + x * math.sin(r) + y * math.cos(r)))
    if filled:
        d.polygon(pts, fill=255)
    else:
        d.line(pts + [pts[0]], fill=255, width=int(9 * S * scale))


def stem(d, x, y0, y1, w=7):
    d.line([(x, y0), (x, y1)], fill=255, width=w * S)


def flag(d, x, y, n=1, down=1):
    for k in range(n):
        yy = y + k * 26 * S * down
        pts = []
        for i in range(20):
            t = i / 19
            pts.append((x + (34 * t + 10 * math.sin(t * math.pi)) * S, yy + (40 * t + 18 * t * t) * S * down))
        d.line(pts, fill=255, width=10 * S)


def roughen(im: Image.Image, seed: int, drip: bool = False) -> np.ndarray:
    a = np.asarray(im).astype(np.float32) / 255.0
    n = T.fft_noise(a.shape[0], a.shape[1], seed, beta=1.4)
    a = cv2.GaussianBlur(a, (0, 0), 2.0 * S)
    a = T.smoothstep(0.38, 0.62, a + (n - 0.5) * 0.35)
    if drip:
        r = np.random.default_rng(seed)
        ys, xs = np.nonzero(a > 0.5)
        for _ in range(3):
            i = r.integers(0, len(xs))
            x0, y0 = xs[i], ys[i]
            ln = r.integers(30, 80) * S
            w = r.integers(3, 6) * S
            cv2.line(a, (int(x0), int(y0)), (int(x0 + r.integers(-3, 3) * S), int(min(y0 + ln, a.shape[0] - 8 * S))), 1.0, int(w))
            cv2.circle(a, (int(x0), int(min(y0 + ln, a.shape[0] - 8 * S))), int(w * 1.3), 1.0, -1)
    small = cv2.resize(a, (W, H), interpolation=cv2.INTER_AREA)
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[..., :3] = 1.0
    rgba[..., 3] = small
    return rgba


def make():
    cx = 100 * S
    # quarter
    im, d = canvas()
    head(d, cx, 190 * S)
    stem(d, cx + 26 * S, 186 * S, 40 * S)
    T.save(OUT / "note_quarter.png", roughen(im, 1))
    # eighth
    im, d = canvas()
    head(d, cx, 190 * S)
    stem(d, cx + 26 * S, 186 * S, 40 * S)
    flag(d, cx + 26 * S, 40 * S, 1)
    T.save(OUT / "note_eighth.png", roughen(im, 2))
    # sixteenth
    im, d = canvas()
    head(d, cx, 190 * S)
    stem(d, cx + 26 * S, 186 * S, 30 * S)
    flag(d, cx + 26 * S, 30 * S, 2)
    T.save(OUT / "note_sixteenth.png", roughen(im, 3))
    # beamed pair
    im, d = canvas()
    head(d, 60 * S, 200 * S, scale=0.85)
    head(d, 170 * S, 170 * S, scale=0.85)
    stem(d, 82 * S, 196 * S, 60 * S)
    stem(d, 192 * S, 166 * S, 32 * S)
    d.polygon([(80 * S, 52 * S), (196 * S, 22 * S), (196 * S, 46 * S), (80 * S, 76 * S)], fill=255)
    T.save(OUT / "note_beam.png", roughen(im, 4))
    # half note
    im, d = canvas()
    head(d, cx, 190 * S, filled=False)
    stem(d, cx + 27 * S, 186 * S, 40 * S)
    T.save(OUT / "note_half.png", roughen(im, 5))
    # broken: the stem snapped and the head cracked
    im, d = canvas()
    head(d, cx, 196 * S)
    d.line([(cx - 34 * S, 176 * S), (cx + 8 * S, 214 * S)], fill=0, width=6 * S)
    stem(d, cx + 26 * S, 190 * S, 120 * S)
    d.line([(cx + 40 * S, 104 * S), (cx + 52 * S, 30 * S)], fill=255, width=7 * S)
    flag(d, cx + 52 * S, 30 * S, 1)
    T.save(OUT / "note_broken.png", roughen(im, 6))
    # dripping
    im, d = canvas()
    head(d, cx, 150 * S)
    stem(d, cx + 26 * S, 146 * S, 20 * S)
    flag(d, cx + 26 * S, 20 * S, 1)
    T.save(OUT / "note_drip.png", roughen(im, 7, drip=True))


if __name__ == "__main__":
    make()

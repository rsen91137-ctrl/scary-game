#!/usr/bin/env python3
"""Tileable PBR textures for the old apartment block (stairwell and flat).

All procedural (numpy), deterministic. Writes assets/textures/<name>_{albedo,normal,rough}.png
and a few single maps:
  concrete     raw cast concrete: aggregate, pores, cracks, grime
  plaster      dirty whitewash over plaster: stains, soot, scuffs
  peel         grayscale masks: R = peeled-off paint, G = water stain, B = grime (no colour)
  brick        old red brick with crumbling mortar (shows where plaster fell off)
  paint_green  the dark green dado paint of old stairwells, chipped and scratched
  rust         rusty painted steel (railings, doors, meter boxes)
  wood         worn handrail / door wood
Usage: python3 tools/gen_textures.py [name ...]
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

import texlib as T

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "textures"
OUT.mkdir(parents=True, exist_ok=True)
N = 1024
L = T.srgb_to_linear


def save_set(name, albedo_lin, height, rough, nstrength=3.0):
    T.save(OUT / f"{name}_albedo.png", T.linear_to_srgb(albedo_lin))
    T.save(OUT / f"{name}_normal.png", T.normal_from_height(height, nstrength))
    T.save(OUT / f"{name}_rough.png", np.clip(rough, 0, 1))


def cracks(n, seed, count=6, width=1.2):
    r = T.rng(seed)
    img = np.zeros((n, n), np.float32)
    for _ in range(count):
        x, y = r.uniform(0, n), r.uniform(0, n)
        a = r.uniform(0, 2 * np.pi)
        ln = r.uniform(n * 0.15, n * 0.5)
        pts = []
        steps = 40
        for i in range(steps):
            a += r.normal(0, 0.25)
            x += np.cos(a) * ln / steps
            y += np.sin(a) * ln / steps
            pts.append((x % n, y % n))
        for i in range(len(pts) - 1):
            p0, p1 = pts[i], pts[i + 1]
            if abs(p0[0] - p1[0]) > n / 2 or abs(p0[1] - p1[1]) > n / 2:
                continue
            w = max(1, int(width * (1 - i / steps) + 0.5))
            cv2.line(img, (int(p0[0]), int(p0[1])), (int(p1[0]), int(p1[1])), 1.0, w, cv2.LINE_AA)
    return np.clip(img, 0, 1)


def concrete():
    big = T.fft_noise(N, N, 1, beta=3.0)
    mid = T.fft_noise(N, N, 2, beta=2.0)
    fine = T.fft_noise(N, N, 3, beta=0.9)
    f1, _ = T.worley(N, N, 2600, 4)
    pores = T.smoothstep(3.0, 0.5, f1) * (T.fft_noise(N, N, 5, beta=1.0) > 0.55)
    agg_f1, agg_f2 = T.worley(N, N, 900, 6)
    agg = T.smoothstep(0.0, 6.0, agg_f2 - agg_f1) * 0.5
    cr = cracks(N, 7, 7)
    grime = T.smoothstep(0.45, 0.8, T.fft_noise(N, N, 8, beta=2.6))
    h = 0.35 * big + 0.25 * mid + 0.12 * fine + 0.15 * agg - 0.5 * pores - 0.6 * cr
    base = L([0.50, 0.49, 0.46])
    col = np.zeros((N, N, 3), np.float32) + base
    col *= (0.78 + 0.35 * mid + 0.12 * fine)[..., None]
    col = T.lerp(col, L([0.36, 0.34, 0.31]), (grime * 0.55)[..., None])
    col *= (1 - 0.5 * pores - 0.55 * cr)[..., None]
    rough = 0.82 + 0.12 * fine - 0.1 * grime
    save_set("concrete", col, T.blur_wrap(h, 0.6), rough, 4.0)


def plaster():
    big = T.fft_noise(N, N, 11, beta=3.2)
    mid = T.fft_noise(N, N, 12, beta=2.2)
    fine = T.fft_noise(N, N, 13, beta=1.0)
    trowel = T.fft_noise(N, N, 14, beta=2.4, aniso=(1, 3))
    h = 0.4 * big + 0.25 * trowel + 0.1 * fine - 0.35 * cracks(N, 15, 5, 1.0)
    col = np.zeros((N, N, 3), np.float32) + L([0.76, 0.74, 0.69])
    col *= (0.86 + 0.18 * mid + 0.06 * fine)[..., None]
    # long vertical grime runs and soot blotches
    runs = T.fft_noise(N, N, 16, beta=1.8, aniso=(6, 0.4))
    col = T.lerp(col, L([0.52, 0.48, 0.40]), (T.smoothstep(0.55, 0.85, runs) * 0.45)[..., None])
    soot = T.smoothstep(0.6, 0.9, T.fft_noise(N, N, 17, beta=2.8))
    col = T.lerp(col, L([0.28, 0.27, 0.26]), (soot * 0.35)[..., None])
    rough = 0.9 - 0.05 * fine
    save_set("plaster", col, T.blur_wrap(h, 0.8), rough, 2.5)


def peel():
    # R: paint peeled off (sharp, flaky edges); G: water stain rings; B: grime
    n1 = T.fft_noise(N, N, 21, beta=2.6)
    n2 = T.fft_noise(N, N, 22, beta=1.2)
    pe = T.smoothstep(0.58, 0.62, n1 + (n2 - 0.5) * 0.12)
    st = T.fft_noise(N, N, 23, beta=3.0)
    ring = np.exp(-np.square((st - 0.68) / 0.012)) * 0.9 + T.smoothstep(0.62, 0.75, st) * 0.4
    gr = T.fft_noise(N, N, 24, beta=2.0)
    T.save(OUT / "peel_mask.png", np.stack([pe, np.clip(ring, 0, 1), gr], -1))


def brick():
    h = np.zeros((N, N), np.float32)
    col = np.zeros((N, N, 3), np.float32)
    r = T.rng(31)
    rows = 16
    bh = N // rows
    bw = bh * 2.1
    mortar = np.ones((N, N), np.float32)
    tint = np.zeros((N, N, 3), np.float32)
    for row in range(rows):
        off = (row % 2) * bw / 2
        x = -off
        while x < N:
            x0, x1 = int(max(x + 3, 0)), int(min(x + bw - 3, N))
            y0, y1 = row * bh + 3, (row + 1) * bh - 3
            if x1 > x0:
                mortar[y0:y1, x0:x1] = 0.0
                c = L([r.uniform(0.38, 0.55), r.uniform(0.14, 0.22), r.uniform(0.09, 0.14)])
                tint[y0:y1, x0:x1] = c
            x += bw
    # wrap the last partial bricks
    fine = T.fft_noise(N, N, 32, beta=1.2)
    mid = T.fft_noise(N, N, 33, beta=2.2)
    mortar = T.blur_wrap(mortar, 1.2)
    chip = T.smoothstep(0.6, 0.75, T.fft_noise(N, N, 34, beta=1.6))
    col = tint * (0.75 + 0.4 * fine[..., None]) * (0.85 + 0.3 * mid[..., None])
    col = T.lerp(col, L([0.42, 0.40, 0.36]) * (0.8 + 0.3 * fine[..., None]), mortar[..., None])
    col = T.lerp(col, col * 0.6, (chip * 0.5)[..., None])
    h = (1 - mortar) * 0.8 + 0.15 * fine - 0.3 * chip
    rough = 0.85 + 0.1 * mortar
    save_set("brick", col, T.blur_wrap(h, 0.8), rough, 5.0)


def paint_green():
    mid = T.fft_noise(N, N, 41, beta=2.4)
    fine = T.fft_noise(N, N, 42, beta=1.0)
    scratches = np.zeros((N, N), np.float32)
    r = T.rng(43)
    for _ in range(140):
        x, y = r.uniform(0, N), r.uniform(0, N)
        a = r.uniform(-0.4, 0.4) + (np.pi / 2 if r.random() < 0.3 else 0)
        ln = r.uniform(20, 140)
        cv2.line(scratches, (int(x), int(y)), (int(x + np.cos(a) * ln), int(y + np.sin(a) * ln)), 1.0, 1, cv2.LINE_AA)
    chips = T.smoothstep(0.72, 0.76, T.fft_noise(N, N, 44, beta=2.0) + (fine - 0.5) * 0.1)
    col = np.zeros((N, N, 3), np.float32) + L([0.20, 0.33, 0.27])
    col *= (0.8 + 0.3 * mid + 0.08 * fine)[..., None]
    under = L([0.62, 0.60, 0.55])
    col = T.lerp(col, under, (np.clip(chips + scratches * 0.7, 0, 1))[..., None])
    grime = T.smoothstep(0.5, 0.9, T.fft_noise(N, N, 45, beta=2.6, aniso=(1, 2)))
    col = T.lerp(col, L([0.12, 0.13, 0.11]), (grime * 0.45)[..., None])
    h = -0.6 * chips - 0.3 * scratches + 0.1 * fine
    rough = 0.55 + 0.25 * grime + 0.3 * chips
    save_set("paint_green", col, T.blur_wrap(h, 0.5), rough, 3.0)


def rust():
    mid = T.fft_noise(N, N, 51, beta=2.4)
    fine = T.fft_noise(N, N, 52, beta=0.9)
    rm = T.smoothstep(0.45, 0.75, T.fft_noise(N, N, 53, beta=2.2) + (fine - 0.5) * 0.25)
    paint = L([0.16, 0.20, 0.22])
    rustc = L([0.36, 0.16, 0.07])
    col = T.lerp(paint * (0.85 + 0.3 * mid[..., None]), rustc * (0.7 + 0.6 * fine[..., None]), rm[..., None])
    h = 0.4 * rm * fine + 0.1 * mid
    rough = 0.45 + 0.5 * rm
    save_set("rust", col, T.blur_wrap(h, 0.5), rough, 3.0)


def wood():
    r = T.rng(61)
    grain = T.fft_noise(N, N, 62, beta=1.6, aniso=(0.25, 8))
    rings = np.sin((np.arange(N)[:, None] / N * 40 + grain * 6) * np.pi)
    fine = T.fft_noise(N, N, 63, beta=1.0)
    col = np.zeros((N, N, 3), np.float32) + L([0.30, 0.17, 0.09])
    col *= (0.75 + 0.2 * rings[..., None] * 0.5 + 0.3 * grain[..., None])
    wear = T.smoothstep(0.55, 0.8, T.fft_noise(N, N, 64, beta=2.2))
    col = T.lerp(col, L([0.42, 0.30, 0.20]), (wear * 0.5)[..., None])
    h = 0.3 * rings + 0.2 * fine
    rough = 0.6 - 0.25 * wear
    save_set("wood", col, T.blur_wrap(h, 0.5), rough, 1.5)


ALL = {"concrete": concrete, "plaster": plaster, "peel": peel, "brick": brick,
       "paint_green": paint_green, "rust": rust, "wood": wood}




if __name__ == "__main__":
    for nm in sys.argv[1:] or list(ALL):
        ALL[nm]()

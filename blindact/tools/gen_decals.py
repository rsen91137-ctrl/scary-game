#!/usr/bin/env python3
"""Wall decals for the decaying block. No readable language on purpose:
spray-paint tags (abstract letterforms), arrows, an X, a sprayed eye,
stencilled floor numbers (digits only), a tear-off flyer with a piano on it
(his own), a missing-person poster with a smudged photo and illegible
lines, water stains, mould, soot and a dirty handprint.
RGBA 512x512 each, sRGB. Writes assets/textures/decals/<name>.png
Usage: python3 tools/gen_decals.py
"""
from __future__ import annotations

import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import texlib as T

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "textures" / "decals"
OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob("*.png"):
    old.unlink()
S = 512
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"


def spray(mask_strokes: np.ndarray, color, seed, drips=6, overspray=1.0, alpha_max=0.92) -> np.ndarray:
    """Turn a hard stroke mask into sprayed paint: soft overspray, speckle,
    drips running down from heavy spots."""
    r = T.rng(seed)
    m = np.ascontiguousarray(mask_strokes.astype(np.float32))
    halo = cv2.GaussianBlur(m, (0, 0), 7) * 0.45 * overspray
    core = cv2.GaussianBlur(m, (0, 0), 1.6)
    speck = (r.random((S, S)) < 0.25 * halo).astype(np.float32)
    a = np.clip(np.maximum(core, halo * 0.6) + speck * 0.5, 0, 1)
    ys, xs = np.nonzero(m > 0.5)
    for _ in range(drips if len(xs) else 0):
        i = r.integers(0, len(xs))
        x0, y0 = int(xs[i]), int(ys[i])
        ln = int(r.integers(25, 120))
        w = int(r.integers(2, 5))
        cv2.line(a, (x0, y0), (x0 + int(r.integers(-2, 3)), min(y0 + ln, S - 6)), 1.0, w, cv2.LINE_AA)
        cv2.circle(a, (x0, min(y0 + ln, S - 6)), w + 1, 1.0, -1, cv2.LINE_AA)
    n = T.fft_noise(S, S, seed + 3, beta=1.0)
    a *= (0.75 + 0.3 * n)
    rgb = np.zeros((S, S, 3), np.float32) + np.array(color, np.float32)
    rgb *= (0.85 + 0.25 * n)[..., None]
    return np.concatenate([rgb, np.clip(a * alpha_max, 0, 1)[..., None]], -1)


def bez(p0, p1, p2, p3, n=40):
    t = np.linspace(0, 1, n)[:, None]
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3


def tag(name, seed, color, strokes=7, width=(10, 18)):
    """An abstract graffiti signature: loopy letter-like strokes with an underline."""
    r = T.rng(seed)
    m = np.zeros((S, S), np.float32)
    x = 70.0
    for k in range(strokes):
        h = r.uniform(110, 200)
        w = r.uniform(40, 70)
        p0 = np.array([x, 300 + r.uniform(-20, 20)])
        p1 = np.array([x + r.uniform(-30, 30), 300 - h])
        p2 = np.array([x + w + r.uniform(-20, 40), 300 - h * r.uniform(0.5, 1.2)])
        p3 = np.array([x + w, 300 + r.uniform(-30, 30)])
        pts = bez(p0, p1, p2, p3)
        cv2.polylines(m, [pts.astype(np.int32)], False, 1.0, int(r.uniform(*width)), cv2.LINE_AA)
        x += w * r.uniform(0.7, 1.0)
        if x > S - 90:
            break
    sw = bez(np.array([50.0, 360]), np.array([200.0, 420]), np.array([330.0, 300]), np.array([480.0, 350]))
    cv2.polylines(m, [sw.astype(np.int32)], False, 1.0, 9, cv2.LINE_AA)
    T.save(OUT / f"{name}.png", spray(m, color, seed))


def arrow(name, seed, color):
    m = np.zeros((S, S), np.float32)
    pts = bez(np.array([80.0, 380]), np.array([180.0, 150]), np.array([330.0, 330]), np.array([420.0, 140]))
    cv2.polylines(m, [pts.astype(np.int32)], False, 1.0, 22, cv2.LINE_AA)
    cv2.line(m, (420, 140), (330, 150), 1.0, 22, cv2.LINE_AA)
    cv2.line(m, (420, 140), (440, 230), 1.0, 22, cv2.LINE_AA)
    T.save(OUT / f"{name}.png", spray(m, color, seed))


def cross(name, seed, color):
    m = np.zeros((S, S), np.float32)
    cv2.line(m, (110, 100), (400, 410), 1.0, 34, cv2.LINE_AA)
    cv2.line(m, (410, 110), (100, 400), 1.0, 30, cv2.LINE_AA)
    T.save(OUT / f"{name}.png", spray(m, color, seed, drips=10))


def eye_tag(name, seed, color):
    m = np.zeros((S, S), np.float32)
    top = bez(np.array([40.0, 270]), np.array([170.0, 120]), np.array([340.0, 120]), np.array([470.0, 260]))
    bot = bez(np.array([40.0, 270]), np.array([180.0, 360]), np.array([330.0, 370]), np.array([470.0, 260]))
    cv2.polylines(m, [top.astype(np.int32)], False, 1.0, 16, cv2.LINE_AA)
    cv2.polylines(m, [bot.astype(np.int32)], False, 1.0, 16, cv2.LINE_AA)
    cv2.circle(m, (256, 255), 78, 1.0, 14, cv2.LINE_AA)
    cv2.circle(m, (256, 255), 34, 1.0, -1, cv2.LINE_AA)
    T.save(OUT / f"{name}.png", spray(m, color, seed, drips=12))


def number(name, text, seed, color):
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 330 if len(text) == 1 else 250, index=2)
    bb = d.textbbox((0, 0), text, font=f)
    d.text(((S - (bb[2] - bb[0])) / 2 - bb[0], (S - (bb[3] - bb[1])) / 2 - bb[1] - 10), text, font=f, fill=255)
    m = np.asarray(im).astype(np.float32) / 255.0
    # stencil bridges
    m[:, S // 2 - 4:S // 2 + 4] *= 0.0 if len(text) == 1 else 1.0
    T.save(OUT / f"{name}.png", spray(m, color, seed, drips=5, overspray=0.6))


def paper(w, h, seed, base=(226, 222, 208)):
    r = T.rng(seed)
    x0, y0 = (S - w) // 2, (S - h) // 2
    mask = np.zeros((S, S), np.float32)
    mask[y0:y0 + h, x0:x0 + w] = 1.0
    n = T.fft_noise(S, S, seed, beta=1.4)
    mask = T.smoothstep(0.45, 0.55, cv2.GaussianBlur(mask, (0, 0), 4) + (n - 0.5) * 0.5) * mask
    tone = T.fft_noise(S, S, seed + 1, beta=2.4)
    rgb = np.zeros((S, S, 3), np.float32) + np.array(base, np.float32) / 255.0
    rgb *= (0.8 + 0.25 * tone)[..., None]
    stain = T.smoothstep(0.58, 0.85, T.fft_noise(S, S, seed + 2, beta=2.0))
    rgb = T.lerp(rgb, np.array([0.5, 0.42, 0.28]), (stain * 0.55)[..., None])
    return rgb, mask, (x0, y0)


def scribble_lines(rgb, x0, y0, w, rows, seed, col=(0.12, 0.12, 0.12), h=8):
    """Illegible printed lines: blurred dashes of varying length."""
    r = T.rng(seed)
    a = np.zeros((S, S), np.float32)
    for i, yy in enumerate(rows):
        x = x0
        while x < x0 + w:
            ln = r.uniform(12, 48)
            cv2.line(a, (int(x), int(yy)), (int(min(x + ln, x0 + w)), int(yy)), 1.0, h)
            x += ln + r.uniform(6, 14)
    a = cv2.GaussianBlur(a, (0, 0), 1.8) * T.smoothstep(0.2, 0.6, T.fft_noise(S, S, seed, beta=0.8))
    return T.lerp(rgb, np.array(col), (a * 0.85)[..., None])


def flyer():
    rgb, mask, (x0, y0) = paper(230, 330, 120)
    d = np.zeros((S, S), np.float32)
    # a little upright piano drawing
    cv2.rectangle(d, (x0 + 45, y0 + 40), (x0 + 185, y0 + 150), 1.0, 5)
    for k in range(9):
        cv2.line(d, (x0 + 50 + k * 15, y0 + 125), (x0 + 50 + k * 15, y0 + 150), 1.0, 2)
    cv2.rectangle(d, (x0 + 40, y0 + 120), (x0 + 190, y0 + 128), 1.0, -1)
    d = cv2.GaussianBlur(d, (0, 0), 0.8)
    rgb = T.lerp(rgb, np.array([0.08, 0.08, 0.08]), (d * 0.9)[..., None])
    rgb = scribble_lines(rgb, x0 + 30, y0 + 180, 170, [y0 + 180, y0 + 198, y0 + 216], 121)
    # tear-off tabs at the bottom, some missing
    r = T.rng(122)
    for k in range(7):
        tx = x0 + 8 + k * 31
        if r.random() < 0.35:
            mask[y0 + 250:y0 + 330, tx:tx + 29] = 0.0
            continue
        cv2.line(mask, (tx + 29, y0 + 250), (tx + 29, y0 + 330), 0.0, 2)
        tab = scribble_lines(np.zeros((S, S, 3)), tx + 10, y0 + 260, 8, [], 123)
        cv2.line(rgb, (tx + 14, y0 + 262), (tx + 14, y0 + 322), (0.15, 0.15, 0.15), 3)
    T.save(OUT / "flyer_piano.png", np.concatenate([rgb, mask[..., None] * 0.97], -1))


def missing():
    rgb, mask, (x0, y0) = paper(300, 400, 300)
    # a heavy smudged header bar (letters too faded to read)
    rgb = scribble_lines(rgb, x0 + 40, y0 + 30, 220, [y0 + 36], 301, h=26)
    yy, xx = np.mgrid[0:S, 0:S]
    cx, cy = x0 + 150, y0 + 165
    face = np.exp(-(((xx - cx) / 52.0) ** 2 + ((yy - cy) / 66.0) ** 2))
    hair = np.exp(-(((xx - cx) / 78.0) ** 2 + ((yy - cy + 10) / 92.0) ** 2))
    ph = np.clip(hair * 0.9 - face * 0.55, 0, 1)
    eyes = np.exp(-(((xx - cx + 20) / 9.0) ** 2 + ((yy - cy + 8) / 5.0) ** 2)) + np.exp(-(((xx - cx - 20) / 9.0) ** 2 + ((yy - cy + 8) / 5.0) ** 2))
    ph = np.clip(ph + eyes * 0.8, 0, 1)
    box = (np.abs(xx - cx) < 90) & (np.abs(yy - cy) < 95)
    ph = np.where(box, np.clip(ph + 0.15 + T.fft_noise(S, S, 302, beta=0.6) * 0.25, 0, 1), 0)
    rgb = T.lerp(rgb, np.zeros(3), (ph * 0.85)[..., None])
    rgb = scribble_lines(rgb, x0 + 30, y0 + 280, 240, [y0 + 285, y0 + 305, y0 + 325, y0 + 345], 303)
    T.save(OUT / "missing.png", np.concatenate([rgb, mask[..., None] * 0.97], -1))


def blot(name, seed, color, beta=2.6, thr=(0.55, 0.62), ring=False, alpha_max=0.8):
    n = T.fft_noise(S, S, seed, beta=beta)
    yy, xx = np.mgrid[0:S, 0:S]
    rad = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S / 2)
    m = T.smoothstep(thr[0], thr[1], n * (1.2 - rad))
    if ring:
        edge = m - cv2.GaussianBlur(m, (0, 0), 6)
        m = np.clip(m * 0.4 + np.maximum(edge, 0) * 3.0, 0, 1)
    rgb = np.zeros((S, S, 3), np.float32) + np.array(color, np.float32)
    T.save(OUT / f"{name}.png", np.concatenate([rgb, (m * alpha_max)[..., None]], -1))


def handprint():
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    d.ellipse((185, 250, 335, 410), fill=255)
    for i, (dx, ln, w) in enumerate(((-82, 95, 26), (-38, 135, 28), (6, 150, 28), (48, 130, 27), (88, 90, 24))):
        x = 258 + dx
        ang = -0.32 + i * 0.15
        pts = [(x - math.sin(ang) * 10, 285)]
        for k in range(1, 6):
            t = k / 5
            pts.append((x + math.sin(ang) * ln * t, 285 - math.cos(ang) * ln * t))
        d.line(pts, fill=255, width=w, joint="curve")
        d.ellipse((pts[-1][0] - w / 2, pts[-1][1] - w / 2, pts[-1][0] + w / 2, pts[-1][1] + w / 2), fill=255)
    a = cv2.GaussianBlur(np.asarray(im).astype(np.float32) / 255.0, (0, 0), 2.5)
    n = T.fft_noise(S, S, 401, beta=0.8)
    a = T.smoothstep(0.3, 0.7, a * (0.55 + 0.65 * n))
    for k in range(1, 26):
        a = np.maximum(a, np.roll(a, k * 2, 0) * (1 - k / 26) * 0.45)
    rgb = np.zeros((S, S, 3), np.float32) + np.array([0.12, 0.05, 0.04])
    T.save(OUT / "handprint.png", np.concatenate([rgb, (a * 0.85)[..., None]], -1))


def main():
    red = [0.62, 0.06, 0.05]
    black = [0.04, 0.04, 0.045]
    white = [0.82, 0.8, 0.76]
    green = [0.18, 0.5, 0.22]
    tag("tag_red", 11, red)
    tag("tag_black", 12, black, strokes=9, width=(8, 14))
    tag("tag_white", 13, white, strokes=6, width=(12, 20))
    tag("tag_green", 14, green, strokes=8)
    arrow("arrow", 15, red)
    cross("cross", 16, black)
    eye_tag("eye_tag", 17, red)
    for n in ("1", "2", "3", "4", "5", "6", "7", "8", "9", "13"):
        number(f"floor_{n}", n, 30 + int(n), white)
    flyer()
    missing()
    blot("stain", 501, [0.32, 0.24, 0.14], ring=True, alpha_max=0.7)
    blot("stain2", 504, [0.26, 0.2, 0.12], beta=2.2, ring=True, alpha_max=0.6)
    blot("mold", 502, [0.06, 0.08, 0.05], beta=1.6, thr=(0.5, 0.56), alpha_max=0.9)
    blot("soot", 503, [0.03, 0.03, 0.03], beta=3.0, thr=(0.35, 0.65), alpha_max=0.75)
    handprint()
    print("decals written to", OUT)


if __name__ == "__main__":
    main()

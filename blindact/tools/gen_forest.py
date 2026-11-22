#!/usr/bin/env python3
"""Textures for the outdoor night: the housing estate and the forest round it.

All procedural (numpy + OpenCV), deterministic. Writes assets/textures/forest/:
  bark_pine / bark_spruce / bark_oak / bark_birch   albedo, normal, rough (tileable;
                       u round the trunk, v along it). Lichen and moss are painted in;
                       the bark shader adds more moss by height and facing.
  moss                 moss carpet (albedo, normal) for bark, rocks and the ground
  card_spruce / card_pine / card_twigs / card_birch / card_fern / card_bush /
  card_grass           foliage cards, RGBA (alpha-scissor), drawn supersampled
  ground_litter / ground_dirt / ground_lawn / ground_mud   forest floor, paths,
                       lawns, stream bed
  rock                 granite with lichen
  paving / asphalt / render / tiles / planks / roof   the estate
  door_green / door_blue   painted steel doors (albedo; door_normal, door_rough shared)
  streaks              grime runs (alpha atlas, 4 variants) for walls
  signs                painted unit numbers, block numbers, notices (RGBA atlas)
  water_normal         ripples for the stream
Opaque tiling maps are JPEG (4:4:4) to keep the repository small; cards and atlases
with alpha are PNG.

Usage: python3 tools/gen_forest.py [name ...]
       python3 tools/gen_forest.py --fix-imports   (after a first `godot --import`:
       VRAM compression, mipmaps and normal-map flags for these files; import again)
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.spatial import cKDTree

import texlib as T

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "textures" / "forest"
OUT.mkdir(parents=True, exist_ok=True)
N = 1024
L = T.srgb_to_linear


def c8(r, g, b):
    """sRGB 0..255 -> linear 0..1."""
    return L(np.array([r, g, b], np.float32) / 255.0)


# ---------------------------------------------------------------------------
# saving
# ---------------------------------------------------------------------------
def _to8(a):
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def save_jpg(name, arr, q=92):
    a8 = _to8(arr)
    im = Image.fromarray(a8, "L" if a8.ndim == 2 else "RGB")
    im.save(str(OUT / name), quality=q, subsampling=0, optimize=True)
    print("wrote", name, im.size)


def save_png(name, arr):
    a8 = _to8(arr)
    mode = {2: "L", 3: "RGB", 4: "RGBA"}[1 if a8.ndim == 2 else a8.shape[2]] if a8.ndim == 3 else "L"
    im = Image.fromarray(a8, mode)
    im.save(str(OUT / name), optimize=True)
    print("wrote", name, im.size)


def save_set(name, albedo_lin, height, rough, nstrength=3.0, q=92):
    save_jpg(f"{name}_albedo.jpg", T.linear_to_srgb(albedo_lin), q)
    save_jpg(f"{name}_normal.jpg", T.normal_from_height(height, nstrength), 95)
    save_jpg(f"{name}_rough.jpg", np.clip(rough, 0, 1), 88)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def worley_aniso(h, w, n, seed, sy=1.0):
    """Tileable Worley noise with cells stretched `sy` times along y.
    Returns F1, F2 (pixels, in the stretched metric) and the cell index."""
    r = T.rng(seed)
    pts = r.random((n, 2)) * [h, w]
    offs = [(dy, dx) for dy in (-h, 0, h) for dx in (-w, 0, w)]
    allp = np.concatenate([pts + o for o in offs]) / [sy, 1.0]
    tree = cKDTree(allp)
    yy, xx = np.mgrid[0:h, 0:w]
    q = np.stack([yy.ravel() / sy, xx.ravel()], 1).astype(np.float64)
    d, idx = tree.query(q, k=2)
    f1 = d[:, 0].reshape(h, w).astype(np.float32)
    f2 = d[:, 1].reshape(h, w).astype(np.float32)
    cid = (idx[:, 0] % n).reshape(h, w)
    return f1, f2, cid


def warp_tile(a, dx, dy):
    """Displace a tileable map by per-pixel offsets (pixels), wrapping."""
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    mx = np.mod(xx + dx, w).astype(np.float32)
    my = np.mod(yy + dy, h).astype(np.float32)
    return cv2.remap(a, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)


def wrap_offsets(pts, w, h, margin):
    """Offsets needed so a shape near an edge is also drawn on the other side."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    ox = [0]
    oy = [0]
    if min(xs) < margin:
        ox.append(w)
    if max(xs) > w - margin:
        ox.append(-w)
    if min(ys) < margin:
        oy.append(h)
    if max(ys) > h - margin:
        oy.append(-h)
    return [(a, b) for a in ox for b in oy]


def poly_i(pts):
    return np.round(np.array(pts, np.float64) * 4.0).astype(np.int32)


def fill_poly(img, pts, val, wrap=False):
    """Filled polygon with 2 bits of subpixel precision (cv2 shift=2)."""
    h, w = img.shape[:2]
    offs = wrap_offsets(pts, w, h, 60) if wrap else [(0, 0)]
    for ox, oy in offs:
        p = poly_i([(x + ox, y + oy) for x, y in pts])
        cv2.fillPoly(img, [p], val, cv2.LINE_8, 2)


def line(img, a, b, val, th, wrap=False):
    h, w = img.shape[:2]
    offs = wrap_offsets([a, b], w, h, 60) if wrap else [(0, 0)]
    for ox, oy in offs:
        p0 = (int(round((a[0] + ox) * 4)), int(round((a[1] + oy) * 4)))
        p1 = (int(round((b[0] + ox) * 4)), int(round((b[1] + oy) * 4)))
        cv2.line(img, p0, p1, val, max(1, int(round(th))), cv2.LINE_8, 2)


def polyline(img, pts, val, th, wrap=False):
    for i in range(len(pts) - 1):
        t = th[i] if isinstance(th, (list, np.ndarray)) else th
        line(img, pts[i], pts[i + 1], val, t, wrap)


def down(a, f=2):
    return T.downsample(a, f)


def leaf_poly(cx, cy, length, width, ang, lobes=0, tip=1.0, n=18):
    """Outline of a leaf: an ellipse-ish blade, optionally lobed (oak)."""
    pts = []
    ca, sa = math.cos(ang), math.sin(ang)
    for i in range(n * 2):
        t = i / (n * 2) * 2 * math.pi
        x = math.cos(t)
        y = math.sin(t)
        # pointed tip, round base
        r = 1.0
        if x > 0:
            r = 1.0 - 0.25 * tip * x * x
        wv = width * (1.0 - 0.3 * max(x, 0.0))
        if lobes:
            wv *= 1.0 + 0.28 * math.sin(abs(t) * lobes) ** 2
        px = x * length * 0.5 * r
        py = y * wv * 0.5
        pts.append((cx + px * ca - py * sa, cy + px * sa + py * ca))
    return pts


# ---------------------------------------------------------------------------
# bark
# ---------------------------------------------------------------------------
def bark_pine():
    r = T.rng(101)
    n = N
    f1, f2, cid = worley_aniso(n, n, 230, 102, sy=2.8)
    edge = f2 - f1
    wn = T.fft_noise(n, n, 103, beta=2.2)
    wn2 = T.fft_noise(n, n, 104, beta=1.4)
    e = edge + (wn - 0.5) * 22.0 + (wn2 - 0.5) * 8.0
    plate = T.smoothstep(4.0, 17.0, e)                       # 0 fissure .. 1 plate
    prand = r.random(230).astype(np.float32)[cid]
    # flaky terraces on the plates
    fl = T.fft_noise(n, n, 105, beta=1.8, aniso=(1.0, 0.35))
    terr = np.mod(fl * 9.0 + prand * 3.0, 1.0)
    flake_edge = T.smoothstep(0.86, 0.98, terr)
    dome = T.smoothstep(0.0, 26.0, f1 * 0.0 + e) * 0.35
    fine = T.fft_noise(n, n, 106, beta=0.9)
    h = plate * (0.55 + 0.25 * prand + 0.12 * terr + dome) + 0.06 * fine - 0.04 * flake_edge
    outer = c8(92, 82, 74)
    outer2 = c8(70, 64, 60)
    redc = c8(150, 78, 48)
    fis = c8(22, 17, 14)
    col = T.lerp(outer2, outer, (0.4 + 0.6 * prand)[..., None])
    col = col * (0.75 + 0.45 * terr[..., None]) * (0.85 + 0.25 * fine[..., None])
    redm = np.clip(flake_edge * 0.8 + T.smoothstep(0.55, 0.8, fl) * T.smoothstep(0.6, 0.9, prand), 0, 1)
    col = T.lerp(col, redc * (0.8 + 0.4 * fine[..., None]), redm[..., None] * 0.85)
    col = T.lerp(fis * (0.7 + 0.6 * wn2[..., None]), col, plate[..., None])
    # pale blue-green lichen on the plate tops, moss deep in the cracks
    li = T.smoothstep(0.62, 0.72, T.fft_noise(n, n, 107, beta=2.4) + (fine - 0.5) * 0.15) * plate
    col = T.lerp(col, c8(132, 150, 138) * (0.8 + 0.4 * fine[..., None]), li[..., None] * 0.8)
    mo = (1.0 - plate) * T.smoothstep(0.5, 0.7, T.fft_noise(n, n, 108, beta=2.0))
    col = T.lerp(col, c8(48, 72, 30), mo[..., None] * 0.7)
    h = h + li * 0.05
    rough = 0.78 + 0.12 * plate - 0.1 * redm + 0.08 * li
    save_set("bark_pine", col, T.blur_wrap(h, 0.7), rough, 6.0)


def bark_spruce():
    r = T.rng(111)
    n = N
    f1, f2, cid = worley_aniso(n, n, 760, 112, sy=1.5)
    crand = r.random(760).astype(np.float32)[cid]
    scale_edge = T.smoothstep(1.0, 7.0, f2 - f1 + (T.fft_noise(n, n, 116, beta=1.6) - 0.5) * 6.0)
    dome = 1.0 - T.smoothstep(0.0, 30.0, f1)
    big = T.fft_noise(n, n, 113, beta=2.6, aniso=(1.0, 0.5))
    fine = T.fft_noise(n, n, 114, beta=0.9)
    h = scale_edge * (0.45 + 0.35 * dome + 0.2 * crand) + 0.15 * big + 0.05 * fine
    base = T.lerp(c8(70, 58, 52), c8(104, 86, 74), crand[..., None])
    col = base * (0.7 + 0.35 * dome[..., None]) * (0.8 + 0.3 * big[..., None])
    col = T.lerp(c8(30, 24, 21), col, scale_edge[..., None])
    # resin runs
    resin = np.zeros((n, n), np.float32)
    for _ in range(5):
        x = r.uniform(0, n)
        y = r.uniform(0, n)
        ln = r.uniform(40, 160)
        for k in range(int(ln)):
            xx = int(x + math.sin(k * 0.05) * 2) % n
            yy = int(y + k) % n
            cv2.circle(resin, (xx, yy), int(max(1, 4 - k / ln * 3)), 1.0, -1)
    resin = T.blur_wrap(resin, 1.2)
    col = T.lerp(col, c8(150, 104, 40), resin[..., None] * 0.7)
    li = T.smoothstep(0.66, 0.78, T.fft_noise(n, n, 115, beta=2.2)) * scale_edge
    col = T.lerp(col, c8(122, 140, 128), li[..., None] * 0.7)
    rough = 0.8 + 0.1 * scale_edge - 0.55 * resin + 0.06 * li
    save_set("bark_spruce", col, T.blur_wrap(h + resin * 0.15, 0.6), rough, 5.0)


def bark_oak():
    r = T.rng(121)
    n = N
    f1, f2, cid = worley_aniso(n, n, 520, 122, sy=4.5)
    prand = r.random(520).astype(np.float32)[cid]
    wn = T.fft_noise(n, n, 123, beta=2.0, aniso=(3.0, 0.5))
    fine = T.fft_noise(n, n, 124, beta=0.9)
    e = (f2 - f1) + (wn - 0.5) * 14.0
    ridge = T.smoothstep(2.0, 10.0, e)
    rough_s = T.fft_noise(n, n, 127, beta=1.3, aniso=(1.5, 0.6))
    h = ridge * (0.6 + 0.25 * prand + 0.2 * rough_s) + 0.06 * fine
    col = T.lerp(c8(66, 62, 56), c8(98, 94, 86), prand[..., None])
    col = col * (0.75 + 0.35 * rough_s[..., None]) * (0.85 + 0.25 * fine[..., None])
    col = T.lerp(c8(16, 15, 14) * (0.8 + 0.4 * wn[..., None]), col, ridge[..., None])
    # green algae down one side, lichen crusts on the ridges
    alg = T.smoothstep(0.45, 0.75, T.fft_noise(n, n, 125, beta=2.6))
    col = T.lerp(col, c8(56, 78, 44), (alg * ridge)[..., None] * 0.5)
    li = T.smoothstep(0.66, 0.74, T.fft_noise(n, n, 126, beta=2.0) + (fine - 0.5) * 0.2) * ridge
    col = T.lerp(col, c8(150, 162, 150), li[..., None] * 0.75)
    rough = 0.8 + 0.12 * ridge + 0.05 * li
    save_set("bark_oak", col, T.blur_wrap(h + li * 0.04, 0.6), rough, 7.0)


def bark_birch():
    r = T.rng(131)
    n = N
    big = T.fft_noise(n, n, 132, beta=2.6)
    fine = T.fft_noise(n, n, 133, beta=1.0)
    col = np.zeros((n, n, 3), np.float32) + c8(184, 190, 186)
    col *= (0.86 + 0.16 * big[..., None] + 0.05 * fine[..., None])
    # peeling bands (slightly pinkish-cream / grey)
    band = T.fft_noise(n, n, 134, beta=2.0, aniso=(0.25, 6.0))
    col = T.lerp(col, c8(208, 196, 182), T.smoothstep(0.6, 0.8, band)[..., None] * 0.5)
    col = T.lerp(col, c8(150, 156, 152), T.smoothstep(0.65, 0.85, 1 - band)[..., None] * 0.35)
    h = 0.4 + 0.1 * big + 0.04 * fine
    dark = np.zeros((n, n), np.float32)
    # lenticels: short horizontal dashes
    for _ in range(900):
        x = r.uniform(0, n)
        y = r.uniform(0, n)
        ln = r.uniform(8, 60)
        th = r.uniform(1.5, 4.5)
        line(dark, (x, y), (x + ln, y + r.uniform(-1.5, 1.5)), 1.0, th, wrap=True)
    # black diamond fissures and scars
    for _ in range(9):
        x = r.uniform(0, n)
        y = r.uniform(0, n)
        wv = r.uniform(40, 120)
        hv = wv * r.uniform(0.25, 0.55)
        pts = [(x, y - hv * 0.5), (x + wv * 0.5, y + r.uniform(-8, 8)), (x, y + hv * 0.5), (x - wv * 0.5, y + r.uniform(-8, 8))]
        jit = [(p[0] + r.uniform(-12, 12), p[1] + r.uniform(-5, 5)) for p in pts]
        fill_poly(dark, jit, 1.0, wrap=True)
    dark = dark[:n, :n]
    dark = np.clip(T.blur_wrap(dark, 1.0) * 1.3, 0, 1)
    rough_dark = dark * T.smoothstep(0.3, 0.6, fine + 0.2)
    col = T.lerp(col, c8(28, 26, 26) * (0.8 + 0.5 * fine[..., None]), dark[..., None] * 0.92)
    li = T.smoothstep(0.7, 0.8, T.fft_noise(n, n, 135, beta=2.3))
    col = T.lerp(col, c8(128, 150, 118), li[..., None] * 0.5)
    h = h - 0.35 * dark - 0.1 * rough_dark
    rough = 0.55 + 0.35 * dark + 0.1 * li
    save_set("bark_birch", col, T.blur_wrap(h, 0.6), rough, 4.0)


def moss():
    n = 512
    f1, f2, cid = worley_aniso(n, n, 500, 141)
    clump = 1.0 - T.smoothstep(0.0, 18.0, f1)
    fine = T.fft_noise(n, n, 142, beta=0.7)
    mid = T.fft_noise(n, n, 143, beta=2.2)
    h = clump * 0.6 + fine * 0.35 + mid * 0.2
    col = T.lerp(c8(28, 46, 16), c8(86, 112, 34), (clump * 0.5 + fine * 0.5)[..., None])
    col = T.lerp(col, c8(110, 116, 50), T.smoothstep(0.7, 0.9, mid)[..., None] * 0.4)
    save_jpg("moss_albedo.jpg", T.linear_to_srgb(col))
    save_jpg("moss_normal.jpg", T.normal_from_height(T.blur_wrap(h, 0.6), 5.0), 95)


# ---------------------------------------------------------------------------
# foliage cards (RGBA). Drawn at 2x and box-filtered down.
# ---------------------------------------------------------------------------
class Card:
    def __init__(self, w, h, ss=2):
        self.ss = ss
        self.w = w * ss
        self.h = h * ss
        self.col = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)

    def line(self, p0, p1, colr, th):
        s = self.ss
        a = (p0[0] * s, p0[1] * s)
        b = (p1[0] * s, p1[1] * s)
        line(self.col, a, b, tuple(float(v) for v in colr), th * s)
        line(self.a, a, b, 1.0, th * s)

    def poly(self, pts, colr):
        s = self.ss
        q = [(x * s, y * s) for x, y in pts]
        fill_poly(self.col, q, tuple(float(v) for v in colr))
        fill_poly(self.a, q, 1.0)

    def save(self, name, edge_dilate=True):
        col = down(self.col, self.ss)
        a = down(self.a, self.ss)
        # bleed colour into transparent texels so mipmaps don't fringe dark
        if edge_dilate:
            m = (a > 0.02).astype(np.float32)
            c = col * m[..., None]
            for _ in range(6):
                cb = cv2.blur(c, (5, 5))
                mb = cv2.blur(m, (5, 5))
                fill = (m < 0.5) & (mb > 0.01)
                c[fill] = cb[fill] / mb[fill][..., None]
                m = np.maximum(m, (mb > 0.01).astype(np.float32))
            col = np.where(a[..., None] > 0.02, col, c)
        rgba = np.concatenate([T.linear_to_srgb(col), a[..., None]], -1)
        save_png(name, rgba)


def needle_col(r, base, var=0.25):
    k = 1.0 + r.uniform(-var, var)
    return np.clip(base * k, 0, 1)


def card_spruce():
    r = T.rng(201)
    W, H = 512, 1024
    c = Card(W, H)
    dark = c8(14, 34, 28)
    mid = c8(26, 66, 48)
    tipc = c8(60, 104, 74)
    twig_c = c8(70, 50, 34)
    pts = []
    for i in range(41):
        t = i / 40
        pts.append((W * 0.5 + math.sin(t * 2.2) * 16 * t, H - 14 - t * (H - 50)))

    def needles(p0, p1, density, nlen, side_ang, layer):
        d = np.array(p1, np.float64) - np.array(p0, np.float64)
        ln = float(np.linalg.norm(d))
        if ln < 1:
            return
        u = d / ln
        nrm = np.array([-u[1], u[0]])
        cnt = max(1, int(ln * density))
        for k in range(cnt):
            t = (k + r.uniform(0, 1)) / cnt
            base = np.array(p0) + d * t
            for sd in (-1.0, 1.0):
                a = math.radians(side_ang + r.uniform(-15, 15))
                v = u * math.cos(a) + nrm * sd * math.sin(a)
                L_ = nlen * r.uniform(0.75, 1.2)
                colr = T.lerp(dark, mid, layer) * r.uniform(0.8, 1.2)
                c.line(base, base + v * L_ * 0.7, colr, 1.4)
                c.line(base + v * L_ * 0.65, base + v * L_, T.lerp(colr, tipc, 0.55), 1.1)

    def twig(base, v, ln, depth):
        tw = [tuple(base)]
        for k in range(1, 7):
            t = k / 6
            p = np.array(base) + v * ln * t + np.array([0.0, -1.0]) * (t * t * 0.12 * ln)
            tw.append((p[0], p[1]))
        out = [tw]
        if depth > 0:
            alt = 1.0
            for k in range(1, 6):
                q = np.array(tw[k])
                dv = np.array(tw[min(k + 1, 6)]) - np.array(tw[k - 1])
                dv /= np.linalg.norm(dv) + 1e-6
                nn = np.array([-dv[1], dv[0]]) * alt
                a = math.radians(48 + r.uniform(-8, 8))
                sv = dv * math.cos(a) + nn * math.sin(a)
                out += twig(q, sv, ln * (0.42 - 0.05 * k) * r.uniform(0.8, 1.1), depth - 1)
                alt = -alt
        return out

    twigs = []
    s_ = 0.03
    alt = 1.0
    while s_ < 0.94:
        lmax = 250.0 * (math.sin(math.pi * min(1.0, s_ * 0.85 + 0.15)) ** 0.7) * (1.0 - 0.5 * s_)
        i = int(s_ * 40)
        base = np.array(pts[i])
        dv = np.array(pts[min(i + 1, 40)]) - base
        dv /= np.linalg.norm(dv) + 1e-6
        nn = np.array([-dv[1], dv[0]]) * alt
        a = math.radians(55 + r.uniform(-8, 8))
        v = dv * math.cos(a) + nn * math.sin(a)
        twigs += twig(base, v, lmax * r.uniform(0.85, 1.05), 1)
        s_ += r.uniform(0.03, 0.042)
        alt = -alt
    for tw in twigs:
        for k in range(len(tw) - 1):
            needles(tw[k], tw[k + 1], 0.2, 22, 58, 0.1)
    for i in range(len(pts) - 1):
        needles(pts[i], pts[i + 1], 0.22, 24, 55, 0.15)
    for i in range(len(pts) - 1):
        c.line(pts[i], pts[i + 1], twig_c, 3.6 - 2.4 * i / 40)
    for tw in twigs:
        for k in range(len(tw) - 1):
            c.line(tw[k], tw[k + 1], twig_c * 0.9, 1.6 - 0.15 * k)
    for tw in twigs:
        for k in range(len(tw) - 1):
            needles(tw[k], tw[k + 1], 0.12, 19, 46, 0.7)
    for i in range(len(pts) - 1):
        needles(pts[i], pts[i + 1], 0.1, 20, 42, 0.8)
    c.save("card_spruce.png")


def card_pine():
    """A Scots pine branch end: a forked twig, each fork ending in a brush of
    long paired needles, needles all along the outer twigs; dense enough that
    a crown of these reads as a mass, not as separate fronds."""
    r = T.rng(211)
    W, H = 512, 512
    c = Card(W, H)
    nd = c8(34, 62, 52)
    nl = c8(74, 104, 82)
    twig_c = c8(96, 62, 40)
    tufts = []

    def twig(p, ang, ln, th, depth):
        pts = [p]
        a = ang
        for k in range(5):
            a += r.uniform(-0.14, 0.14)
            pts.append((pts[-1][0] + math.cos(a) * ln / 5, pts[-1][1] + math.sin(a) * ln / 5))
        for k in range(len(pts) - 1):
            c.line(pts[k], pts[k + 1], twig_c * r.uniform(0.85, 1.1), th * (1 - 0.12 * k))
        if depth > 0:
            for j in range(3):
                t = r.uniform(0.35, 0.85)
                i = int(t * 5)
                twig(pts[i], a + (j - 1) * r.uniform(0.45, 0.8) + r.uniform(-0.15, 0.15), ln * r.uniform(0.45, 0.65), th * 0.62, depth - 1)
        tufts.append((pts[-1], a, pts[1]))

    twig((W * 0.5, H - 6), -math.pi / 2 + r.uniform(-0.1, 0.1), 270, 6.0, 2)
    for (tip, a, mid) in tufts:
        for k in range(60):
            t = r.uniform(0.0, 1.0)
            base = (mid[0] + (tip[0] - mid[0]) * t, mid[1] + (tip[1] - mid[1]) * t)
            spread = math.radians(r.uniform(20, 70)) * (1 if r.random() < 0.5 else -1)
            ln = r.uniform(36, 70) * (0.6 + 0.4 * t)
            aa = a + spread * (1.0 - 0.45 * t)
            end = (base[0] + math.cos(aa) * ln, base[1] + math.sin(aa) * ln)
            c.line(base, end, T.lerp(nd, nl, r.uniform(0, 1)) * r.uniform(0.8, 1.1), 1.4)
        for k in range(55):
            spread = r.uniform(-0.95, 0.95)
            ln = r.uniform(44, 84)
            aa = a + spread
            end = (tip[0] + math.cos(aa) * ln, tip[1] + math.sin(aa) * ln)
            c.line(tip, end, T.lerp(nd, nl, r.uniform(0.2, 1)), 1.4)
    c.save("card_pine.png")


def card_twigs():
    r = T.rng(221)
    W, H = 1024, 1024
    c = Card(W, H)
    tw = c8(60, 52, 48)
    leaves = []

    def branch(p, ang, ln, th, depth):
        pts = [p]
        a = ang
        for k in range(4):
            a += r.uniform(-0.2, 0.2) + (-math.pi / 2 - a) * 0.06
            pts.append((pts[-1][0] + math.cos(a) * ln / 4, pts[-1][1] + math.sin(a) * ln / 4))
        colr = tw * r.uniform(0.8, 1.15)
        for k in range(4):
            c.line(pts[k], pts[k + 1], colr, max(0.9, th * (1 - 0.15 * k)))
        if depth <= 0:
            if r.random() < 0.03:
                leaves.append((pts[-1], a))
            return
        nch = 3 if r.random() < 0.55 else 2
        for j in range(nch):
            t = r.uniform(0.3, 1.0)
            i = min(4, int(t * 4 + 0.5))
            da = r.uniform(0.28, 0.7) * (1 if j % 2 == 0 else -1)
            branch(pts[i], a + da, ln * r.uniform(0.6, 0.8), th * 0.68, depth - 1)

    branch((W * 0.5, H - 4), -math.pi / 2, 380, 10.0, 7)
    branch((W * 0.5, H - 4), -math.pi / 2 - 0.45, 300, 7.0, 6)
    branch((W * 0.5, H - 4), -math.pi / 2 + 0.45, 300, 7.0, 6)
    for (p, a) in leaves:
        L_ = r.uniform(24, 40)
        ang = a + r.uniform(-1.2, 1.2) + math.pi * 0.35
        cx = p[0] + math.cos(ang) * L_ * 0.5
        cy = p[1] + math.sin(ang) * L_ * 0.5
        base = [c8(96, 62, 34), c8(122, 84, 40), c8(78, 50, 30), c8(110, 96, 46)][r.integers(0, 4)]
        c.poly(leaf_poly(cx, cy, L_, L_ * 0.55, ang, lobes=4), base * r.uniform(0.8, 1.15))
        c.line(p, (cx + math.cos(ang) * L_ * 0.45, cy + math.sin(ang) * L_ * 0.45), base * 0.6, 1.2)
    c.save("card_twigs.png")


def card_birch():
    r = T.rng(231)
    W, H = 512, 1024
    c = Card(W, H)
    tw = c8(78, 46, 40)
    for k in range(7):
        x0 = W * 0.5 + r.uniform(-30, 30)
        a = (0.15 if k % 2 == 0 else math.pi - 0.15) + r.uniform(-0.25, 0.25)
        pts = [(x0, 8 + r.uniform(0, 30))]
        for i in range(9):
            a += (math.pi * 0.5 - a) * 0.13 + r.uniform(-0.06, 0.06)
            q = (pts[-1][0] + math.cos(a) * 30, pts[-1][1] + math.sin(a) * 30)
            q = (min(max(q[0], 10), W - 10), q[1])
            pts.append(q)
        for i in range(9):
            c.line(pts[i], pts[i + 1], tw, 3.0 - i * 0.25)
        for i in range(1, 10):
            for j in range(3):
                q = pts[i]
                b = math.pi * 0.5 + r.uniform(-0.6, 0.6)
                whip = [q]
                for m in range(int(r.uniform(8, 22))):
                    b += (math.pi * 0.5 - b) * 0.22 + r.uniform(-0.12, 0.12)
                    nq = (whip[-1][0] + math.cos(b) * 24, whip[-1][1] + math.sin(b) * 24)
                    if nq[1] > H - 8:
                        break
                    whip.append(nq)
                for m in range(len(whip) - 1):
                    c.line(whip[m], whip[m + 1], tw * 0.9, 1.3)
                    if r.random() < 0.07:
                        L_ = r.uniform(16, 28)
                        ang = b + r.uniform(-0.8, 0.8)
                        cx = whip[m][0] + math.cos(ang) * L_ * 0.5
                        cy = whip[m][1] + math.sin(ang) * L_ * 0.5
                        lc = [c8(172, 146, 58), c8(140, 116, 50), c8(110, 90, 44)][r.integers(0, 3)]
                        c.poly(leaf_poly(cx, cy, L_, L_ * 0.7, ang), lc * r.uniform(0.8, 1.1))
    c.save("card_birch.png")


def card_fern():
    r = T.rng(241)
    W, H = 512, 1024
    c = Card(W, H)
    green = c8(44, 94, 40)
    dark = c8(24, 54, 24)
    yel = c8(132, 118, 48)
    pts = []
    for i in range(61):
        t = i / 60
        pts.append((W * 0.5 + math.sin(t * 1.8) * 26 * t, H - 4 - t * (H - 24)))
    side = 1.0
    t = 0.1
    while t < 0.975:
        i = int(t * 60)
        base = np.array(pts[i])
        dirv = np.array(pts[min(i + 1, 60)]) - base
        dirv /= np.linalg.norm(dirv) + 1e-6
        nrm = np.array([-dirv[1], dirv[0]]) * side
        plen = 232.0 * math.sin(math.pi * min(1.0, (t - 0.02) / 0.98)) ** 0.75 * (1.0 - 0.3 * t)
        ang = math.radians(64 + r.uniform(-6, 6))
        v = dirv * math.cos(ang) + nrm * math.sin(ang)
        tipk = r.uniform(0, 1)
        nlob = max(4, int(plen / 10))
        for k in range(nlob):
            s = (k + 0.5) / nlob
            q = base + v * plen * s + dirv * (s * s * plen * 0.18)
            lw = (1.0 - s * 0.75) * 17.0
            colr = T.lerp(green, yel, np.clip((s * 0.6 + tipk * 0.3) * (0.3 + t * 0.6), 0, 1)) * r.uniform(0.85, 1.12)
            for sd in (-1, 1):
                pn = np.array([-v[1], v[0]]) * sd
                p0 = q - v * lw * 0.6
                p1 = q + pn * lw * 0.95 - v * lw * 0.05
                p2 = q + pn * lw * 0.55 + v * lw * 0.5
                p3 = q + v * lw * 0.65
                c.poly([tuple(p0), tuple(p1), tuple(p2), tuple(p3)], colr)
        c.line(tuple(base), tuple(base + v * plen * 0.97), dark, 1.8)
        side = -side
        t += 0.021
    for i in range(60):
        c.line(pts[i], pts[i + 1], dark, 4.2 - 3.0 * i / 60)
    c.save("card_fern.png")


def card_bush():
    r = T.rng(251)
    W, H = 512, 512
    c = Card(W, H)
    stem = c8(70, 40, 34)
    cols = [c8(36, 74, 34), c8(46, 88, 38), c8(30, 60, 32), c8(118, 34, 44), c8(96, 30, 52), c8(126, 106, 44)]
    wts = np.array([0.28, 0.26, 0.2, 0.12, 0.08, 0.06])
    for k in range(26):
        x = W * 0.5 + r.normal(0, 70)
        a = -math.pi / 2 + r.normal(0, 0.45)
        pts = [(x, H - 2)]
        ln = r.uniform(180, 420)
        for i in range(8):
            a += r.uniform(-0.15, 0.15)
            pts.append((pts[-1][0] + math.cos(a) * ln / 8, pts[-1][1] + math.sin(a) * ln / 8))
        for i in range(8):
            c.line(pts[i], pts[i + 1], stem, 2.2 - i * 0.2)
        for i in range(2, 9):
            for j in range(3):
                p = pts[i]
                L_ = r.uniform(14, 30)
                ang = a + r.uniform(-1.6, 1.6)
                cx = p[0] + math.cos(ang) * L_ * 0.6
                cy = p[1] + math.sin(ang) * L_ * 0.6
                cc = cols[r.choice(len(cols), p=wts / wts.sum())]
                c.poly(leaf_poly(cx, cy, L_, L_ * 0.58, ang), cc * r.uniform(0.75, 1.15))
    c.save("card_bush.png")


def card_grass():
    r = T.rng(261)
    W, H = 512, 512
    c = Card(W, H)
    cols = [c8(62, 92, 46), c8(84, 108, 52), c8(132, 124, 76), c8(104, 92, 58), c8(48, 76, 44)]
    for k in range(240):
        x = W * 0.5 + r.normal(0, 80)
        hgt = r.uniform(0.35, 0.98) * H
        lean = r.normal(0, 0.35)
        wb = r.uniform(4, 9)
        cc = cols[r.integers(0, len(cols))] * r.uniform(0.8, 1.15)
        n = 10
        left = []
        right = []
        for i in range(n + 1):
            t = i / n
            px = x + lean * hgt * t * t
            py = H - 1 - hgt * t
            wv = wb * (1 - t) ** 0.8 + 0.3
            left.append((px - wv * 0.5, py))
            right.append((px + wv * 0.5, py))
        c.poly(left + right[::-1], cc * (0.85 + 0.15 * r.random()))
    c.save("card_grass.png")


# ---------------------------------------------------------------------------
# ground
# ---------------------------------------------------------------------------
def ground_litter():
    r = T.rng(301)
    S = 2048
    col = np.zeros((S, S, 3), np.float32)
    hgt = np.zeros((S, S), np.float32)
    soil = T.fft_noise(S, S, 302, beta=2.2)
    col[:] = c8(36, 28, 21)
    col *= (0.7 + 0.5 * soil[..., None])
    layer = 0.0
    browns = [c8(92, 60, 36), c8(120, 82, 44), c8(70, 46, 30), c8(96, 84, 44), c8(140, 104, 52),
              c8(60, 40, 28), c8(110, 70, 40)]
    for k in range(4200):
        cx, cy = r.uniform(0, S), r.uniform(0, S)
        L_ = r.uniform(34, 90)
        ang = r.uniform(0, 2 * math.pi)
        lob = 5 if r.random() < 0.35 else 0
        base = browns[r.integers(0, len(browns))]
        dark = 0.55 + 0.45 * (k / 4200.0)
        cc = base * r.uniform(0.75, 1.15) * dark
        pts = leaf_poly(cx, cy, L_, L_ * r.uniform(0.45, 0.65), ang, lobes=lob)
        layer += 0.0002
        fill_poly(col, pts, tuple(float(v) for v in cc), wrap=True)
        fill_poly(hgt, pts, float(0.25 + layer + r.uniform(0, 0.05)), wrap=True)
        if r.random() < 0.7:
            a = (cx - math.cos(ang) * L_ * 0.5, cy - math.sin(ang) * L_ * 0.5)
            b = (cx + math.cos(ang) * L_ * 0.45, cy + math.sin(ang) * L_ * 0.45)
            line(col, a, b, tuple(float(v) for v in cc * 0.6), 2, wrap=True)
            line(hgt, a, b, float(0.27 + layer), 2, wrap=True)
    # pine needles on top
    for k in range(9000):
        x, y = r.uniform(0, S), r.uniform(0, S)
        a = r.uniform(0, 2 * math.pi)
        ln = r.uniform(30, 80)
        b = (x + math.cos(a) * ln, y + math.sin(a) * ln)
        cc = T.lerp(c8(110, 66, 36), c8(150, 100, 56), r.random()) * r.uniform(0.6, 1.1)
        line(col, (x, y), b, tuple(float(v) for v in cc), 2, wrap=True)
        line(hgt, (x, y), b, float(1.2 + r.uniform(0, 0.1)), 2, wrap=True)
    # small twigs
    for k in range(220):
        x, y = r.uniform(0, S), r.uniform(0, S)
        a = r.uniform(0, 2 * math.pi)
        pts = [(x, y)]
        for i in range(5):
            a += r.uniform(-0.3, 0.3)
            pts.append((pts[-1][0] + math.cos(a) * 30, pts[-1][1] + math.sin(a) * 30))
        cc = c8(70, 58, 46) * r.uniform(0.7, 1.2)
        th = r.uniform(4, 9)
        polyline(col, pts, tuple(float(v) for v in cc), th, wrap=True)
        polyline(hgt, pts, 1.6, th, wrap=True)
    col = down(col)
    hgt = down(hgt)
    fine = T.fft_noise(N, N, 303, beta=1.0)
    hgt = hgt + 0.08 * fine
    rough = 0.82 + 0.12 * fine
    save_set("ground_litter", col, T.blur_wrap(hgt, 0.7), rough, 5.0)


def ground_dirt():
    r = T.rng(311)
    n = N
    big = T.fft_noise(n, n, 312, beta=2.4)
    mid = T.fft_noise(n, n, 313, beta=1.6)
    fine = T.fft_noise(n, n, 314, beta=0.8)
    f1, f2, cid = worley_aniso(n, n, 2200, 315)
    prand = r.random(2200).astype(np.float32)[cid]
    psz = 2.0 + 5.0 * prand
    peb = (1.0 - T.smoothstep(psz * 0.5, psz, f1)) * (prand > 0.78)
    col = np.zeros((n, n, 3), np.float32) + c8(64, 52, 42)
    col *= (0.65 + 0.45 * big[..., None] + 0.15 * fine[..., None])
    col = T.lerp(col, c8(44, 36, 30), T.smoothstep(0.55, 0.8, mid)[..., None] * 0.6)
    col = T.lerp(col, c8(84, 80, 74) * (0.6 + 0.5 * prand[..., None]), peb[..., None] * 0.85)
    hgt = 0.3 * big + 0.15 * mid + 0.08 * fine + 0.45 * peb * (1 - T.smoothstep(0, 6.5, f1))
    # roots crossing the path
    roots = np.zeros((n * 2, n * 2), np.float32)
    rc = np.zeros((n * 2, n * 2), np.float32)
    for k in range(9):
        x, y = r.uniform(0, n * 2), r.uniform(0, n * 2)
        a = r.uniform(0, 2 * math.pi)
        th = r.uniform(10, 22)
        pts = [(x, y)]
        for i in range(30):
            a += r.uniform(-0.18, 0.18)
            pts.append((pts[-1][0] + math.cos(a) * 26, pts[-1][1] + math.sin(a) * 26))
        ths = [th * (1 - i / 34) for i in range(30)]
        polyline(roots, pts, 1.0, ths, wrap=True)
    roots = T.blur_wrap(down(roots), 2.0)
    roots = np.clip(roots * 1.5, 0, 1)
    col = T.lerp(col, c8(76, 58, 44) * (0.8 + 0.3 * fine[..., None]), roots[..., None] * 0.9)
    hgt += roots * 0.6
    # scattered needles and leaf bits pressed in
    bits = np.zeros((n * 2, n * 2), np.float32)
    for k in range(1600):
        x, y = r.uniform(0, n * 2), r.uniform(0, n * 2)
        a = r.uniform(0, 2 * math.pi)
        ln = r.uniform(16, 50)
        line(bits, (x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), 1.0, 2, wrap=True)
    bits = down(bits)
    col = T.lerp(col, c8(100, 66, 38), bits[..., None] * 0.6)
    wet = T.smoothstep(0.65, 0.85, T.fft_noise(n, n, 316, beta=2.6))
    col *= (1.0 - 0.35 * wet[..., None])
    rough = 0.85 - 0.45 * wet + 0.05 * fine - 0.1 * peb
    save_set("ground_dirt", col, T.blur_wrap(hgt, 0.6), rough, 5.0)


def ground_lawn():
    r = T.rng(321)
    S = 2048
    base = T.fft_noise(S, S, 322, beta=2.2)
    col = np.zeros((S, S, 3), np.float32) + c8(56, 46, 34)
    col *= (0.7 + 0.5 * base[..., None])
    hgt = np.zeros((S, S), np.float32)
    bare = T.smoothstep(0.62, 0.75, T.fft_noise(S, S, 323, beta=2.4))
    greens = [c8(56, 78, 40), c8(74, 92, 46), c8(96, 104, 56), c8(124, 116, 70), c8(44, 66, 38)]
    for k in range(26000):
        x, y = r.uniform(0, S), r.uniform(0, S)
        if bare[int(y) % S, int(x) % S] > 0.5 and r.random() < 0.85:
            continue
        a = r.uniform(0, 2 * math.pi)
        ln = r.uniform(18, 48)
        cc = greens[r.integers(0, len(greens))] * r.uniform(0.7, 1.15)
        b = (x + math.cos(a) * ln, y + math.sin(a) * ln)
        line(col, (x, y), b, tuple(float(v) for v in cc), 3, wrap=True)
        line(hgt, (x, y), b, float(0.4 + r.uniform(0, 0.6)), 3, wrap=True)
    col = down(col)
    hgt = down(hgt)
    fine = T.fft_noise(N, N, 324, beta=0.9)
    rough = 0.86 + 0.08 * fine
    save_set("ground_lawn", col, T.blur_wrap(hgt, 0.6) + 0.05 * fine, rough, 4.0)


def ground_mud():
    r = T.rng(331)
    n = 512
    f1, f2, cid = worley_aniso(n, n, 380, 332)
    prand = r.random(380).astype(np.float32)[cid]
    rad = 7.0 + 9.0 * prand
    stone = (1.0 - T.smoothstep(rad * 0.75, rad, f1)) * (prand > 0.25)
    dome = (1.0 - T.smoothstep(0.0, rad, f1)) * stone
    fine = T.fft_noise(n, n, 333, beta=1.0)
    silt = T.fft_noise(n, n, 334, beta=2.4)
    col = np.zeros((n, n, 3), np.float32) + c8(38, 34, 28)
    col *= (0.7 + 0.5 * silt[..., None])
    sc = T.lerp(c8(70, 74, 72), c8(108, 104, 96), prand[..., None]) * (0.8 + 0.3 * fine[..., None])
    col = T.lerp(col, sc, stone[..., None])
    col = T.lerp(col, c8(46, 70, 40), (T.smoothstep(0.6, 0.8, fine) * stone)[..., None] * 0.4)
    hgt = dome * 0.8 + 0.1 * silt + 0.05 * fine
    rough = 0.35 + 0.25 * stone + 0.1 * fine
    save_set("ground_mud", col, T.blur_wrap(hgt, 0.6), rough, 5.0)


def rock():
    r = T.rng(341)
    n = N
    big = T.fft_noise(n, n, 342, beta=2.6)
    mid = T.fft_noise(n, n, 343, beta=1.8)
    gr = T.fft_noise(n, n, 344, beta=0.3)
    gr2 = T.fft_noise(n, n, 345, beta=0.4)
    col = np.zeros((n, n, 3), np.float32) + c8(92, 94, 96)
    col *= (0.7 + 0.45 * big[..., None] + 0.2 * mid[..., None])
    col = T.lerp(col, c8(30, 30, 32), T.smoothstep(0.72, 0.9, gr)[..., None] * 0.8)
    col = T.lerp(col, c8(160, 158, 150), T.smoothstep(0.75, 0.92, gr2)[..., None] * 0.6)
    cr = np.zeros((n * 2, n * 2), np.float32)
    for k in range(18):
        x, y = r.uniform(0, n * 2), r.uniform(0, n * 2)
        a = r.uniform(0, 2 * math.pi)
        pts = [(x, y)]
        for i in range(40):
            a += r.uniform(-0.25, 0.25)
            pts.append((pts[-1][0] + math.cos(a) * 18, pts[-1][1] + math.sin(a) * 18))
        polyline(cr, pts, 1.0, r.uniform(2, 5), wrap=True)
    cr = T.blur_wrap(down(cr), 0.8)
    col *= (1.0 - 0.6 * cr[..., None])
    li = T.smoothstep(0.6, 0.66, T.fft_noise(n, n, 346, beta=2.2) + (mid - 0.5) * 0.1)
    li2 = T.smoothstep(0.7, 0.76, T.fft_noise(n, n, 347, beta=2.0))
    col = T.lerp(col, c8(140, 156, 140) * (0.8 + 0.3 * gr[..., None]), li[..., None] * 0.75)
    col = T.lerp(col, c8(150, 138, 82), li2[..., None] * 0.45)
    streak = T.smoothstep(0.55, 0.85, T.fft_noise(n, n, 348, beta=1.8, aniso=(5.0, 0.4)))
    col *= (1.0 - 0.3 * streak[..., None])
    hgt = 0.5 * big + 0.25 * mid + 0.06 * gr - 0.5 * cr + 0.06 * li
    rough = 0.72 + 0.15 * li + 0.08 * gr
    save_set("rock", col, T.blur_wrap(hgt, 0.6), rough, 5.0)


# ---------------------------------------------------------------------------
# the estate
# ---------------------------------------------------------------------------
def paving():
    """2 m x 2 m: 4 x 4 square concrete pavers, mossy joints, cracks, a sunk one."""
    r = T.rng(401)
    n = N
    cells = 4
    cs = n // cells
    joint = 7
    col = np.zeros((n, n, 3), np.float32)
    hgt = np.zeros((n, n), np.float32)
    fine = T.fft_noise(n, n, 402, beta=1.0)
    mid = T.fft_noise(n, n, 403, beta=2.2)
    yy, xx = np.mgrid[0:n, 0:n]
    for i in range(cells):
        for j in range(cells):
            y0, x0 = i * cs, j * cs
            tone = r.uniform(0.82, 1.1)
            tilt = r.normal(0, 0.12, 2)
            sunk = -0.25 if r.random() < 0.08 else 0.0
            sl = (slice(y0 + joint // 2, y0 + cs - joint // 2), slice(x0 + joint // 2, x0 + cs - joint // 2))
            ly = (yy[sl] - y0) / cs - 0.5
            lx = (xx[sl] - x0) / cs - 0.5
            hgt[sl] = 0.7 + sunk + tilt[0] * ly + tilt[1] * lx
            col[sl] = c8(118, 120, 118) * tone
    jmask = (hgt <= 0.0).astype(np.float32)
    jm = T.blur_wrap(jmask, 1.0)
    col *= (0.82 + 0.25 * mid[..., None] + 0.08 * fine[..., None])
    moss_c = T.lerp(c8(30, 46, 22), c8(70, 92, 38), fine[..., None])
    col = np.where(jmask[..., None] > 0.5, moss_c * (0.6 + 0.5 * mid[..., None]), col)
    hgt = np.where(jmask > 0.5, 0.15 + 0.2 * fine, hgt)
    cr = np.zeros((n * 2, n * 2), np.float32)
    for k in range(14):
        x, y = r.uniform(0, n * 2), r.uniform(0, n * 2)
        a = r.uniform(0, 2 * math.pi)
        pts = [(x, y)]
        for q in range(16):
            a += r.uniform(-0.4, 0.4)
            pts.append((pts[-1][0] + math.cos(a) * 18, pts[-1][1] + math.sin(a) * 18))
        polyline(cr, pts, 1.0, 3, wrap=True)
    cr = down(cr)
    col *= (1.0 - 0.55 * cr[..., None])
    hgt -= 0.3 * cr
    stain = T.smoothstep(0.6, 0.85, T.fft_noise(n, n, 404, beta=2.6))
    col *= (1.0 - 0.3 * stain[..., None])
    rough = 0.82 + 0.1 * fine - 0.25 * stain + 0.1 * jm
    save_set("paving", col, T.blur_wrap(hgt, 0.8), rough, 4.0)


def asphalt():
    r = T.rng(411)
    n = N
    f1, f2, cid = worley_aniso(n, n, 9000, 412)
    agg = (1.0 - T.smoothstep(0.5, 3.0, f1))
    prand = r.random(9000).astype(np.float32)[cid]
    fine = T.fft_noise(n, n, 413, beta=0.8)
    mid = T.fft_noise(n, n, 414, beta=2.2)
    col = np.zeros((n, n, 3), np.float32) + c8(46, 47, 50)
    col *= (0.8 + 0.3 * mid[..., None])
    col = T.lerp(col, c8(88, 88, 86) * (0.6 + 0.6 * prand[..., None]), (agg * 0.5)[..., None])
    c1, c2, _ = worley_aniso(n, n, 60, 415)
    croc = (1.0 - T.smoothstep(0.0, 2.5, c2 - c1)) * T.smoothstep(0.55, 0.7, T.fft_noise(n, n, 416, beta=2.4))
    col *= (1.0 - 0.7 * croc[..., None])
    patch = np.zeros((n, n), np.float32)
    for k in range(3):
        x, y = r.integers(0, n), r.integers(0, n)
        w, h = r.integers(120, 300), r.integers(80, 240)
        pts = [(x, y), (x + w, y + r.uniform(-8, 8)), (x + w + r.uniform(-8, 8), y + h), (x, y + h)]
        fill_poly(patch, pts, 1.0, wrap=True)
    patch = patch[:n, :n]
    patch = T.blur_wrap(patch, 2.0)
    col = T.lerp(col, c8(38, 39, 42) * (0.85 + 0.3 * fine[..., None]), patch[..., None] * 0.6)
    oil = T.smoothstep(0.7, 0.9, T.fft_noise(n, n, 417, beta=2.8))
    col *= (1.0 - 0.3 * oil[..., None])
    hgt = 0.4 * agg * prand + 0.1 * mid - 0.5 * croc + 0.05 * patch
    rough = 0.88 - 0.25 * oil - 0.1 * patch + 0.05 * fine
    save_set("asphalt", col, T.blur_wrap(hgt, 0.5), rough, 4.0)


def render():
    """Cement render on the blocks (neutral; tinted per block in the material)."""
    r = T.rng(421)
    n = N
    fine = T.fft_noise(n, n, 422, beta=0.9)
    mid = T.fft_noise(n, n, 423, beta=2.0)
    big = T.fft_noise(n, n, 424, beta=3.0)
    trowel = T.fft_noise(n, n, 425, beta=2.2, aniso=(1.0, 3.0))
    col = np.zeros((n, n, 3), np.float32) + c8(178, 180, 176)
    col *= (0.84 + 0.12 * mid[..., None] + 0.06 * fine[..., None] + 0.08 * big[..., None])
    rep = T.smoothstep(0.62, 0.66, T.fft_noise(n, n, 426, beta=2.8))
    col = T.lerp(col, col * np.array([0.92, 0.94, 0.95], np.float32), rep[..., None])
    runs = T.fft_noise(n, n, 427, beta=1.6, aniso=(8.0, 0.25))
    col *= (1.0 - 0.25 * T.smoothstep(0.55, 0.9, runs)[..., None])
    cr = np.zeros((n * 2, n * 2), np.float32)
    for k in range(10):
        x, y = r.uniform(0, n * 2), r.uniform(0, n * 2)
        a = r.uniform(0, 2 * math.pi)
        pts = [(x, y)]
        for q in range(30):
            a += r.uniform(-0.3, 0.3)
            pts.append((pts[-1][0] + math.cos(a) * 14, pts[-1][1] + math.sin(a) * 14))
        polyline(cr, pts, 1.0, 2, wrap=True)
    cr = down(cr)
    col *= (1.0 - 0.5 * cr[..., None])
    hgt = 0.25 * trowel + 0.12 * fine + 0.1 * mid - 0.4 * cr + 0.04 * rep
    rough = 0.9 - 0.04 * fine
    save_set("render", col, T.blur_wrap(hgt, 0.6), rough, 3.0)


def tiles():
    """Small facade tiles (16 x 8 per metre), grimy grout, a few missing."""
    r = T.rng(431)
    n = N
    cols, rows = 16, 8
    tw, th = n / cols, n / rows
    g = 4
    col = np.zeros((n, n, 3), np.float32)
    hgt = np.zeros((n, n), np.float32)
    for i in range(rows):
        for j in range(cols):
            x0, y0 = int(j * tw) + g // 2, int(i * th) + g // 2
            x1, y1 = int((j + 1) * tw) - g // 2, int((i + 1) * th) - g // 2
            miss = r.random() < 0.015
            tone = r.uniform(0.86, 1.08)
            if miss:
                col[y0:y1, x0:x1] = c8(90, 88, 84)
                hgt[y0:y1, x0:x1] = 0.15
            else:
                col[y0:y1, x0:x1] = c8(196, 198, 192) * tone
                hgt[y0:y1, x0:x1] = 0.7 + r.uniform(-0.05, 0.05)
    grout = (hgt == 0.0)
    col[grout] = c8(110, 108, 102)
    fine = T.fft_noise(n, n, 432, beta=1.0)
    mid = T.fft_noise(n, n, 433, beta=2.2)
    col *= (0.9 + 0.1 * fine[..., None]) * (0.85 + 0.2 * mid[..., None])
    runs = T.fft_noise(n, n, 434, beta=1.6, aniso=(8.0, 0.25))
    col *= (1.0 - 0.3 * T.smoothstep(0.5, 0.9, runs)[..., None])
    rough = np.where(grout, 0.92, 0.32 + 0.2 * fine)
    save_set("tiles", col, T.blur_wrap(hgt, 0.7), rough, 3.0)


def planks():
    """2 m square: five weathered boards with gaps, grain, knots, moss at the edges."""
    r = T.rng(441)
    n = N
    nb = 5
    bw = n / nb
    grain = T.fft_noise(n, n, 442, beta=1.5, aniso=(6.0, 0.15))
    fine = T.fft_noise(n, n, 443, beta=0.9)
    col = np.zeros((n, n, 3), np.float32)
    hgt = np.zeros((n, n), np.float32)
    xx = np.arange(n)[None, :].repeat(n, 0)
    for b in range(nb):
        x0, x1 = int(b * bw) + 3, int((b + 1) * bw) - 3
        tone = r.uniform(0.75, 1.1)
        col[:, x0:x1] = c8(96, 86, 74) * tone
        hgt[:, x0:x1] = 0.7
    gap = hgt == 0.0
    col *= (0.7 + 0.5 * grain[..., None]) * (0.9 + 0.15 * fine[..., None])
    for k in range(9):
        cx, cy = r.uniform(0, n), r.uniform(0, n)
        rr = r.uniform(6, 16)
        cv2.ellipse(col, (int(cx), int(cy)), (int(rr), int(rr * 1.8)), 0, 0, 360, tuple(float(v) for v in c8(40, 32, 26)), -1)
    moss_m = T.smoothstep(0.6, 0.8, T.fft_noise(n, n, 444, beta=2.2)) * T.smoothstep(0.0, 1.0, 1.0 - np.abs((xx % bw) / bw - 0.5) * 2.0 + 0.2)
    col = T.lerp(col, c8(50, 76, 32), np.clip(moss_m, 0, 1)[..., None] * 0.6)
    col[gap] = c8(14, 12, 10)
    hgt = np.where(gap, 0.0, hgt + 0.15 * grain + 0.05 * fine)
    rough = np.where(gap, 1.0, 0.82 + 0.1 * grain)
    save_set("planks", col, T.blur_wrap(hgt, 0.6), rough, 4.0)


def roof():
    n = 512
    fine = T.fft_noise(n, n, 451, beta=1.0)
    mid = T.fft_noise(n, n, 452, beta=2.2)
    col = np.zeros((n, n, 3), np.float32) + c8(38, 40, 44)
    col *= (0.8 + 0.3 * mid[..., None] + 0.1 * fine[..., None])
    hgt = 0.2 * mid + 0.1 * fine
    rough = 0.8 + 0.1 * fine
    save_set("roof", col, T.blur_wrap(hgt, 0.6), rough, 3.0)


def doors():
    r = T.rng(461)
    n = 512
    fine = T.fft_noise(n, n, 462, beta=1.0)
    mid = T.fft_noise(n, n, 463, beta=2.2)
    rustm = T.smoothstep(0.62, 0.78, T.fft_noise(n, n, 464, beta=2.0) + (fine - 0.5) * 0.2)
    scr = np.zeros((n, n), np.float32)
    for k in range(80):
        x, y = r.uniform(0, n), r.uniform(0, n)
        a = r.uniform(-0.5, 0.5)
        ln = r.uniform(10, 70)
        line(scr, (x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), 1.0, 1, wrap=True)
    scr = scr[:n, :n]
    low = np.linspace(0, 1, n)[:, None].repeat(n, 1)
    rustm = np.clip(rustm + T.smoothstep(0.82, 1.0, low) * 0.6 * mid, 0, 1)
    for nm, paint in (("door_green", c8(38, 84, 76)), ("door_blue", c8(40, 62, 100))):
        col = np.zeros((n, n, 3), np.float32) + paint
        col *= (0.8 + 0.3 * mid[..., None] + 0.06 * fine[..., None])
        col = T.lerp(col, c8(120, 116, 106), scr[..., None] * 0.7)
        col = T.lerp(col, c8(96, 46, 22) * (0.7 + 0.5 * fine[..., None]), rustm[..., None])
        save_jpg(f"{nm}_albedo.jpg", T.linear_to_srgb(col))
    hgt = 0.1 * mid - 0.2 * scr + 0.25 * rustm * fine
    save_jpg("door_normal.jpg", T.normal_from_height(T.blur_wrap(hgt, 0.5), 3.0), 95)
    save_jpg("door_rough.jpg", np.clip(0.45 + 0.45 * rustm + 0.1 * scr, 0, 1), 88)


def streaks():
    """Four grime runs side by side; alpha = darkness. Top of each at row 0:
    a dirty smudge where the water gathers, then broad soft runs fading down."""
    r = T.rng(471)
    W, H = 512, 512
    out = np.zeros((H, W), np.float32)
    yy = np.linspace(0, 1, H)[:, None]
    for v in range(4):
        img = np.zeros((H, 128), np.float32)
        for k in range(int(r.uniform(5, 9))):
            x = r.uniform(14, 114)
            ln = r.uniform(0.45, 1.0)
            wv = r.uniform(10, 34)
            a = r.uniform(0.35, 0.8)
            xs = np.arange(128)[None, :]
            wob = np.sin(yy * r.uniform(3, 9) + k) * r.uniform(1, 5)
            prof = np.exp(-((xs - x - wob) / (wv * 0.5)) ** 2)
            fall = np.clip(1.0 - yy / ln, 0, 1) ** 1.2
            img = np.maximum(img, prof * fall * a)
        top = np.exp(-yy * 6.0) * 0.55
        ramp = np.clip(np.sin(np.linspace(0, math.pi, 128))[None, :] * 1.6, 0, 1)
        img = np.clip(img + top * ramp, 0, 1)
        img *= 0.75 + 0.25 * T.fft_noise(H, 128, 480 + v, beta=1.2)
        img = cv2.GaussianBlur(img.astype(np.float32), (0, 0), 2.0)
        out[:, v * 128:(v + 1) * 128] = img
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[..., 3] = np.clip(out, 0, 1)
    save_png("streaks.png", rgba)


def _font(size, serif=False):
    cands = ["/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
             "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc"]
    if serif:
        cands = cands[::-1]
    for c in cands:
        if Path(c).exists():
            return ImageFont.truetype(c, size, index=2 if "Sans" in c else 0)
    return ImageFont.load_default()


def signs():
    """1024 x 512 atlas, 4 x 4 cells of 256 x 128 (see ExteriorProps.SIGN_CELLS)."""
    r = T.rng(481)
    W, H = 1024, 512
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def painted(cell, text, size, color=(150, 18, 16), drips=True):
        cx, cy = (cell % 4) * 256, (cell // 4) * 128
        layer = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        f = _font(size)
        bb = ld.textbbox((0, 0), text, font=f)
        tx = (256 - (bb[2] - bb[0])) // 2 - bb[0]
        ty = (128 - (bb[3] - bb[1])) // 2 - bb[1] - 6
        ld.text((tx, ty), text, font=f, fill=color + (235,))
        a = np.array(layer).astype(np.float32)
        if drips:
            m = a[..., 3] > 100
            ys, xs = np.nonzero(m)
            for k in range(14):
                if len(xs) == 0:
                    break
                i = r.integers(0, len(xs))
                x, y = xs[i], ys[i]
                ln = int(r.uniform(6, 34))
                for q in range(ln):
                    yy = min(127, y + q)
                    a[yy, max(0, x - 1):x + 1, :3] = color
                    a[yy, max(0, x - 1):x + 1, 3] = 220 * (1 - q / ln) ** 0.5
        # worn paint: knock holes in the alpha
        nz = T.fft_noise(128, 256, int(r.integers(0, 9999)), beta=1.6)
        a[..., 3] *= np.clip((nz - 0.18) * 2.5, 0, 1)
        img.alpha_composite(Image.fromarray(a.astype(np.uint8), "RGBA"), (cx, cy))

    for k in range(4):
        painted(k, f"{k + 1}单元", 66)
    for k in range(4):
        painted(4 + k, f"{k + 1}号楼", 74, (40, 52, 60), drips=False)
    painted(8, "5号楼", 74, (40, 52, 60), drips=False)
    # 森林防火: a red-on-white enamel board
    cx, cy = 1 * 256, 2 * 128
    d.rectangle([cx + 6, cy + 10, cx + 250, cy + 118], fill=(196, 200, 194, 255), outline=(150, 20, 18, 255), width=6)
    f = _font(54)
    d.text((cx + 20, cy + 30), "森林防火", font=f, fill=(160, 22, 18, 255))
    # 拆 in a circle (demolition mark)
    painted(10, "", 10, drips=False)
    cx, cy = 2 * 256, 2 * 128
    d.ellipse([cx + 72, cy + 8, cx + 184, cy + 120], outline=(170, 24, 20, 230), width=9)
    f = _font(70)
    d.text((cx + 93, cy + 14), "拆", font=f, fill=(170, 24, 20, 235))
    # 危险 勿近 (danger, keep away)
    painted(11, "危险勿近", 50)
    # notices: a missing person poster, a paper notice
    for cell, title in ((12, "寻人启事"), (13, "通  知")):
        cx, cy = (cell % 4) * 256, (cell // 4) * 128
        d.rectangle([cx + 70, cy + 4, cx + 186, cy + 124], fill=(208, 206, 196, 255))
        f = _font(20)
        d.text((cx + 84, cy + 8), title, font=f, fill=(30, 30, 34, 255))
        if cell == 12:
            d.rectangle([cx + 96, cy + 34, cx + 160, cy + 80], fill=(70, 74, 78, 255))
            d.ellipse([cx + 116, cy + 40, cx + 140, cy + 64], fill=(150, 150, 146, 255))
            d.rectangle([cx + 110, cy + 60, cx + 146, cy + 80], fill=(150, 150, 146, 255))
        for k in range(6):
            yy = cy + (86 if cell == 12 else 40) + k * 6
            if yy > cy + 118:
                break
            d.line([cx + 80, yy, cx + 176 - (k % 3) * 14, yy], fill=(80, 80, 84, 255), width=2)
    # 14: arrow / 15: blank intercom plate with buttons
    cx, cy = 2 * 256, 3 * 128
    d.rounded_rectangle([cx + 88, cy + 10, cx + 168, cy + 118], 8, fill=(120, 124, 126, 255), outline=(60, 62, 64, 255), width=3)
    for k in range(4):
        for j in range(3):
            d.ellipse([cx + 100 + j * 20, cy + 50 + k * 15, cx + 110 + j * 20, cy + 60 + k * 15], fill=(40, 42, 44, 255))
    d.rectangle([cx + 98, cy + 18, cx + 158, cy + 40], fill=(30, 46, 40, 255))
    img = img.filter(__import__("PIL.ImageFilter", fromlist=["GaussianBlur"]).GaussianBlur(0.6))
    img.save(str(OUT / "signs.png"), optimize=True)
    print("wrote signs.png", img.size)


def water_normal():
    n = 512
    a = T.fft_noise(n, n, 491, beta=2.6, aniso=(1.0, 2.0))
    b = T.fft_noise(n, n, 492, beta=1.8)
    h = 0.7 * a + 0.3 * b
    save_jpg("water_normal.jpg", T.normal_from_height(T.blur_wrap(h, 1.0), 6.0), 95)


ALL = {
    "bark_pine": bark_pine, "bark_spruce": bark_spruce, "bark_oak": bark_oak, "bark_birch": bark_birch,
    "moss": moss,
    "card_spruce": card_spruce, "card_pine": card_pine, "card_twigs": card_twigs, "card_birch": card_birch,
    "card_fern": card_fern, "card_bush": card_bush, "card_grass": card_grass,
    "ground_litter": ground_litter, "ground_dirt": ground_dirt, "ground_lawn": ground_lawn, "ground_mud": ground_mud,
    "rock": rock, "paving": paving, "asphalt": asphalt, "render": render, "tiles": tiles, "planks": planks,
    "roof": roof, "doors": doors, "streaks": streaks, "signs": signs, "water_normal": water_normal,
}


def fix_imports():
    """VRAM compression + mipmaps for every texture in this folder (3D use)."""
    count = 0
    for p in OUT.glob("*.import"):
        s = p.read_text()
        normal = "_normal" in p.name
        card = p.name.startswith("card_") or p.name.startswith("signs") or p.name.startswith("streaks")
        subs = [
            (r"^compress/mode=\d", "compress/mode=2"),
            (r"^mipmaps/generate=\w+", "mipmaps/generate=true"),
            (r"^compress/high_quality=\w+", "compress/high_quality=false"),
            (r"^compress/normal_map=\d", "compress/normal_map=%d" % (1 if normal else 2)),
            (r"^detect_3d/compress_to=\d", "detect_3d/compress_to=0"),
            (r"^process/size_limit=\d+", "process/size_limit=1024"),
        ]
        if card:
            subs.append((r"^process/fix_alpha_border=\w+", "process/fix_alpha_border=true"))
        for pat, rep in subs:
            s = re.sub(pat, rep, s, flags=re.M)
        p.write_text(s)
        count += 1
    print("fixed", count, "import files")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--fix-imports"]:
        fix_imports()
        sys.exit(0)
    for nm in args or list(ALL):
        ALL[nm]()

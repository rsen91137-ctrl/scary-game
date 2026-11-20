#!/usr/bin/env python3
"""High-detail tileable PBR sets for her flat (2048 px, deterministic).

  damask      printed damask wallpaper on aged paper: a half-drop ornament
              (bud, scrolling acanthus, crown, drops), the ink faded and
              slightly glossier and raised; linen emboss, foxing, yellowing;
              the strip seam on the tile edge. One repeat = 0.53 x 0.53 m
  glue        the wall under the paper: old plaster blotched with paste
  herring     oak herringbone parquet, 7 x 35 cm planks: per-plank tone,
              grain, pores and rays, bevels with dirt in the gaps, scratches,
              worn varnish. One repeat = 0.70 m (laid at 45 deg by the shader)
  ceiling     distemper over plaster: brush marks, craquelure, cracks, flakes
              lifting. One repeat = 2.0 m
  walltile    15 cm cream glazed tiles: cushion edges, wavy glaze, crazing,
              chipped corners, dirty grout. One repeat = 0.60 m (4 x 4)
  hexfloor    2.5 cm hexagonal mosaic, white with black rosettes, grimy
              grout, cracked and missing pieces. One repeat = 0.50 m
  panel       dark varnished wood for wainscoting, doors and furniture
Writes assets/textures/<name>_{albedo,normal,rough}.png
Usage: python3 tools/gen_interior.py [name ...]
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texlib as T  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "textures"
N = 2048
L = T.srgb_to_linear


def save_set(name, albedo_lin, height, rough, nstrength):
    T.save(OUT / f"{name}_albedo.png", T.linear_to_srgb(albedo_lin))
    T.save(OUT / f"{name}_normal.png", T.normal_from_height(height.astype(np.float32), nstrength))
    T.save(OUT / f"{name}_rough.png", np.clip(rough, 0, 1))


def noise(seed, beta=2.0, aniso=(1.0, 1.0), n=N):
    return T.fft_noise(n, n, seed, beta=beta, aniso=aniso)


def wrap_draw(canvas, fn):
    """Draw with fn(img, ox, oy) at the 9 wrapped offsets so strokes that
    leave one edge come back on the other (seamless tiling)."""
    h, w = canvas.shape[:2]
    for oy in (-h, 0, h):
        for ox in (-w, 0, w):
            fn(canvas, ox, oy)


# ---------------------------------------------------------------------------
# damask wallpaper
# ---------------------------------------------------------------------------
def _bezier(p0, p1, p2, p3, n=40):
    t = np.linspace(0, 1, n)[:, None]
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3


def _spiral(c, r0, r1, a0, turns, n=60, sgn=1.0):
    t = np.linspace(0, 1, n)
    a = a0 + sgn * t * turns * 2 * np.pi
    r = r0 + (r1 - r0) * t
    return np.stack([c[0] + np.cos(a) * r, c[1] + np.sin(a) * r], -1)


def _stroke(img, pts, w0, w1, val=1.0):
    n = len(pts)
    for i in range(n - 1):
        w = w0 + (w1 - w0) * i / max(n - 2, 1)
        a = (int(round(pts[i][0] * 4)), int(round(pts[i][1] * 4)))
        b = (int(round(pts[i + 1][0] * 4)), int(round(pts[i + 1][1] * 4)))
        cv2.line(img, a, b, val, max(1, int(round(w))), cv2.LINE_AA, shift=2)


def _leaf(img, base, tip, width, val=1.0, bend=0.25):
    """A pointed leaf / petal from base to tip, bulging to one side."""
    base = np.asarray(base, float)
    tip = np.asarray(tip, float)
    d = tip - base
    nrm = np.array([-d[1], d[0]]) / (np.linalg.norm(d) + 1e-9)
    t = np.linspace(0, 1, 30)
    prof = np.sin(np.pi * t) ** 0.8 * width
    mid = base[None] + d[None] * t[:, None] + nrm[None] * (np.sin(np.pi * t) * bend * np.linalg.norm(d))[:, None]
    left = mid + nrm[None] * prof[:, None] * 0.5
    right = mid - nrm[None] * prof[:, None] * 0.5
    poly = np.concatenate([left, right[::-1]])
    cv2.fillPoly(img, [np.round(poly * 4).astype(np.int32)], val, cv2.LINE_AA, shift=2)


def damask_motif(w, h):
    """One ornament on a (h, w) canvas, mirror-symmetric about the vertical
    axis. Coordinates in pixels, origin top-left."""
    m = np.zeros((h, w), np.float32)
    det = np.zeros((h, w), np.float32)      # fine inner lines (cut out of the ink)
    cx = w / 2.0
    S = w / 2.0                              # unit = half width

    def P(x, y):                             # motif units (x right, y up, origin centre)
        return np.array([cx + x * S, h / 2.0 - y * S])

    half = np.zeros_like(m)
    hdet = np.zeros_like(m)
    # the central bud (an ogee), drawn as a filled shape on both halves at once
    ys = np.linspace(-0.62, 0.78, 80)
    wid = 0.36 * np.sin(np.clip((ys + 0.62) / 1.4, 0, 1) * np.pi) ** 0.9 * (1 - 0.35 * np.clip((ys - 0.3) / 0.5, 0, 1))
    left = np.stack([cx - wid * S, h / 2.0 - ys * S], -1)
    right = np.stack([cx + wid * S, h / 2.0 - ys * S], -1)
    cv2.fillPoly(m, [np.round(np.concatenate([left, right[::-1]]) * 4).astype(np.int32)], 1.0, cv2.LINE_AA, shift=2)
    # inside the bud: an outline, a smaller bud, a spine of beads
    wid2 = wid * 0.72
    l2 = np.stack([cx - wid2 * S, h / 2.0 - (ys * 0.86 + 0.02) * S], -1)
    r2 = np.stack([cx + wid2 * S, h / 2.0 - (ys * 0.86 + 0.02) * S], -1)
    cv2.polylines(det, [np.round(np.concatenate([l2, r2[::-1]]) * 4).astype(np.int32)], True, 1.0, max(1, int(S * 0.025)), cv2.LINE_AA, shift=2)
    for k, yb in enumerate(np.linspace(-0.4, 0.55, 9)):
        c = P(0.0, yb)
        cv2.circle(det, (int(c[0] * 4), int(c[1] * 4)), int(S * (0.035 - 0.0015 * k) * 4), 1.0, -1, cv2.LINE_AA, shift=2)
    # one half of the scrollwork (mirrored below)
    # big acanthus scroll sweeping out and up from the bud's foot, ending in a volute
    sc = _bezier(P(0.12, -0.55), P(0.75, -0.75), P(1.05, 0.05), P(0.72, 0.38), 60)
    _stroke(half, sc, S * 0.09, S * 0.05)
    vol = _spiral(P(0.62, 0.24), S * 0.16, S * 0.02, np.pi * 0.3, 1.1, 60, 1.0)
    _stroke(half, vol, S * 0.05, S * 0.015)
    # leaves along the scroll
    for t, ln, ang in ((0.18, 0.32, -0.7), (0.38, 0.36, -0.2), (0.58, 0.3, 0.35), (0.3, 0.22, 2.3), (0.52, 0.2, 2.6)):
        i = int(t * (len(sc) - 1))
        b = sc[i]
        tip = b + np.array([np.cos(ang), -np.sin(ang)]) * ln * S
        _leaf(half, b, tip, S * 0.12, 1.0, 0.22)
    # the crown at the top: three lobes
    _leaf(half, P(0.0, 0.78), P(0.0, 1.32), S * 0.18, 1.0, 0.0)
    _leaf(half, P(0.04, 0.8), P(0.42, 1.18), S * 0.15, 1.0, -0.25)
    sp = _spiral(P(0.47, 1.1), S * 0.09, S * 0.015, np.pi * 1.2, 0.9, 40, -1.0)
    _stroke(half, sp, S * 0.035, S * 0.012)
    # hanging drops at the bottom
    _leaf(half, P(0.08, -0.62), P(0.36, -1.18), S * 0.13, 1.0, 0.3)
    _leaf(half, P(0.02, -0.66), P(0.02, -1.3), S * 0.09, 1.0, 0.0)
    for k in range(5):
        c = P(0.5 + 0.08 * k, -0.95 + 0.11 * k)
        cv2.circle(half, (int(c[0] * 4), int(c[1] * 4)), int(S * 0.028 * 4), 1.0, -1, cv2.LINE_AA, shift=2)
    # a vein cut through every leaf (detail lines)
    _stroke(hdet, sc, S * 0.018, S * 0.008)
    # mirror the half to the other side
    half = np.maximum(half, half[:, ::-1])
    hdet = np.maximum(hdet, hdet[:, ::-1])
    m = np.maximum(m, half)
    det = np.maximum(det, hdet)
    return np.clip(m, 0, 1), np.clip(det, 0, 1)


def damask():
    n = N
    ink = np.zeros((n, n), np.float32)
    det = np.zeros((n, n), np.float32)
    mw, mh = n // 2, int(n * 0.8)
    mot, mdet = damask_motif(mw, mh)
    small, sdet = damask_motif(n // 5, int(n * 0.27))

    def place(img, src, cx, cy):
        h, w = src.shape
        x0, y0 = int(cx - w / 2), int(cy - h / 2)
        for oy in (-n, 0, n):
            for ox in (-n, 0, n):
                xa, ya = x0 + ox, y0 + oy
                xs0, ys0 = max(0, -xa), max(0, -ya)
                xs1, ys1 = min(w, n - xa), min(h, n - ya)
                if xs1 <= xs0 or ys1 <= ys0:
                    continue
                sub = img[ya + ys0:ya + ys1, xa + xs0:xa + xs1]
                np.maximum(sub, src[ys0:ys1, xs0:xs1], out=sub)

    # half-drop: big ornaments in two columns, the second dropped half a repeat;
    # small sprigs in between
    place(ink, mot, n * 0.25, n * 0.5)
    place(ink, mot, n * 0.75, 0.0)
    place(det, mdet, n * 0.25, n * 0.5)
    place(det, mdet, n * 0.75, 0.0)
    place(ink, small, n * 0.75, n * 0.5)
    place(ink, small, n * 0.25, 0.0)
    place(det, sdet, n * 0.75, n * 0.5)
    place(det, sdet, n * 0.25, 0.0)
    ink = T.blur(np.ascontiguousarray(ink), 0.6)
    print_ink = np.clip(ink - det * 0.85, 0, 1)
    # print imperfections: worn, unevenly inked
    wear = noise(201, 1.6)
    print_ink *= np.clip(0.55 + 0.6 * T.smoothstep(0.2, 0.75, wear), 0, 1)
    mis = noise(202, 0.6)
    print_ink *= (0.88 + 0.12 * mis)
    # paper: linen emboss, fibres, uneven yellowing, foxing
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    linen = (np.sin(xx * 2 * np.pi / 7.0) * 0.5 + 0.5) * (np.sin(yy * 2 * np.pi / 7.0 + np.sin(xx * 0.05)) * 0.5 + 0.5)
    fibres = noise(203, 0.9, (1.0, 3.0))
    yellow = noise(204, 2.6)
    paper = np.zeros((n, n, 3), np.float32) + L([0.55, 0.59, 0.56])
    paper *= (0.9 + 0.08 * fibres + 0.04 * linen)[..., None]
    # tone-on-tone ground: fine satin pinstripes
    stripe = T.smoothstep(0.55, 0.8, np.sin(xx * 2 * np.pi / (n / 48.0)) * 0.5 + 0.5)
    paper *= (1 - 0.07 * stripe)[..., None]
    paper = T.lerp(paper, L([0.45, 0.47, 0.42]), (T.smoothstep(0.45, 0.9, yellow) * 0.6)[..., None])
    ink_col = np.zeros((n, n, 3), np.float32) + L([0.2, 0.25, 0.26])
    ink_col = T.lerp(ink_col, L([0.32, 0.36, 0.36]), (T.smoothstep(0.4, 0.9, wear) * 0.5)[..., None])
    col = T.lerp(paper, ink_col, (print_ink * 0.82)[..., None])
    # foxing: small rusty spots
    r = T.rng(205)
    fox = np.zeros((n, n), np.float32)
    for _ in range(140):
        x, y = r.uniform(0, n), r.uniform(0, n)
        rad = r.uniform(2, 9)
        wrap_draw(fox, lambda img, ox, oy: cv2.circle(img, (int(x + ox), int(y + oy)), int(rad), float(r.uniform(0.3, 0.9)), -1, cv2.LINE_AA))
    fox = T.blur(fox, 2.0)
    col = T.lerp(col, L([0.3, 0.29, 0.25]), (np.clip(fox, 0, 1) * 0.6)[..., None])
    # the strip seam on the tile's left/right edge: a hairline gap, glue grime
    sd = np.minimum(xx, n - 1 - xx)
    gap = np.exp(-(sd / 1.4) ** 2)
    edge = np.exp(-(sd / 26.0) ** 2) * (0.6 + 0.4 * noise(206, 1.8))
    col *= (1 - 0.6 * gap)[..., None]
    col = T.lerp(col, col * np.array([0.72, 0.72, 0.68], np.float32), (edge * 0.5)[..., None])
    h = 0.5 * print_ink + 0.06 * linen + 0.12 * fibres - 0.8 * gap + 0.15 * edge + 0.05 * stripe
    rough = 0.86 - 0.3 * print_ink + 0.04 * fibres - 0.08 * stripe
    save_set("damask", col, T.blur_wrap(h, 0.7), rough, 2.2)


def glue():
    n = 1024
    base = noise(211, 2.2, n=n)
    fine = noise(212, 1.0, n=n)
    blot = T.smoothstep(0.45, 0.75, noise(213, 2.6, n=n))
    col = np.zeros((n, n, 3), np.float32) + L([0.52, 0.53, 0.5])
    col *= (0.82 + 0.25 * base + 0.06 * fine)[..., None]
    col = T.lerp(col, L([0.4, 0.38, 0.32]), (blot * 0.6)[..., None])
    # scraps of paper still stuck on
    scraps = T.smoothstep(0.72, 0.78, noise(214, 1.4, n=n))
    col = T.lerp(col, L([0.5, 0.53, 0.5]), (scraps * 0.8)[..., None])
    h = 0.3 * base + 0.25 * fine + 0.3 * scraps
    rough = 0.88 - 0.25 * blot
    T.save(OUT / "glue_albedo.png", T.linear_to_srgb(col))
    T.save(OUT / "glue_normal.png", T.normal_from_height(T.blur_wrap(h, 0.6), 2.5))
    T.save(OUT / "glue_rough.png", np.clip(rough, 0, 1))


# ---------------------------------------------------------------------------
# herringbone parquet
# ---------------------------------------------------------------------------
def herring():
    n = N
    k = 5                                     # plank = 1 x k widths; repeat = 2k widths
    per = 2 * k
    px = n / per                              # pixels per plank width
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    X = xx / px
    Y = yy / px
    m = np.floor(Y)
    b = np.floor((X - (m - k)) / per)
    Xp = X - b * per                          # in [m - k, m + k)
    horiz = Xp >= m
    kk = np.floor(Xp)
    along = np.where(horiz, Xp - m, Y - (kk + 1))
    across = np.where(horiz, Y - m, Xp - kk)
    pid = np.where(horiz, np.mod(m, per), np.mod(kk, per) + per).astype(np.int64)
    r = T.rng(301)
    tone = r.uniform(0.6, 1.25, 2 * per)
    hue = r.uniform(-1, 1, 2 * per)
    goff = r.uniform(0, 64, (2 * per, 2))
    flip = r.integers(0, 2, 2 * per)
    # oak grain: a long strip of grain noise sampled in plank coordinates
    gsrc = T.fft_noise(1024, 1024, 302, beta=1.4, aniso=(0.15, 10.0))   # streaks along x (fine across rows)
    pores_src = T.fft_noise(1024, 1024, 303, beta=0.4, aniso=(0.5, 14.0))
    ray_src = T.fft_noise(1024, 1024, 304, beta=0.8, aniso=(0.4, 3.0))
    u = (along / k * 700 + goff[pid, 0] * 10) % 1024
    v = (np.where(flip[pid] == 1, 1 - across, across) * 120 + goff[pid, 1] * 10) % 1024
    ui = u.astype(np.int64)
    vi = v.astype(np.int64)
    grain = gsrc[vi, ui]
    pores = pores_src[vi, ui]
    rays = ray_src[(vi * 3) % 1024, ui]
    base = L([0.26, 0.23, 0.2])
    col = np.zeros((n, n, 3), np.float32) + base
    col *= (tone[pid] * (0.62 + 0.75 * grain ** 1.4))[..., None].astype(np.float32)
    # darker late-wood streaks
    late = T.smoothstep(0.55, 0.75, gsrc[(vi * 2) % 1024, (ui + 300) % 1024])
    col *= (1 - 0.3 * late)[..., None]
    col = T.lerp(col, col * np.array([0.92, 0.96, 1.0], np.float32), (np.clip(hue[pid], 0, 1) * 0.5)[..., None].astype(np.float32))
    col *= (1 - 0.35 * T.smoothstep(0.62, 0.8, pores))[..., None]
    col = T.lerp(col, col * 1.25, (T.smoothstep(0.7, 0.85, rays) * 0.5)[..., None])
    # bevels: the plank edges dip and collect dirt
    ex = np.minimum(along, k - along) * px      # px from the plank's ends
    ey = np.minimum(across, 1 - across) * px    # px from its sides
    e = np.minimum(ex, ey)
    bevel = T.smoothstep(5.0, 0.0, e)
    gapline = T.smoothstep(1.6, 0.0, e)
    col *= (1 - 0.45 * bevel)[..., None]
    col = T.lerp(col, L([0.05, 0.035, 0.025]), (gapline * 0.85)[..., None])
    # scratches and dents, worn varnish
    scr = np.zeros((n, n), np.float32)
    rs = T.rng(305)
    for _ in range(420):
        x, y = rs.uniform(0, n), rs.uniform(0, n)
        a = rs.normal(0.0, 0.5) + (np.pi / 2 if rs.random() < 0.5 else 0.0)
        ln = rs.uniform(8, 90)
        x2, y2 = x + np.cos(a) * ln, y + np.sin(a) * ln
        val = float(rs.uniform(0.3, 1.0))
        wrap_draw(scr, lambda img, ox, oy: cv2.line(img, (int(x + ox), int(y + oy)), (int(x2 + ox), int(y2 + oy)), val, 1, cv2.LINE_AA))
    col = T.lerp(col, col * np.array([1.2, 1.2, 1.2], np.float32), (scr * 0.45)[..., None])
    wear = T.smoothstep(0.5, 0.85, noise(306, 2.4))
    col = T.lerp(col, col * 0.9 + L([0.08, 0.08, 0.08]), (wear * 0.5)[..., None])
    h = 0.9 - 0.9 * bevel - 0.6 * gapline + 0.08 * grain - 0.1 * T.smoothstep(0.62, 0.8, pores) - 0.15 * scr
    rough = 0.32 + 0.25 * wear + 0.15 * scr + 0.35 * bevel + 0.08 * grain
    save_set("herring", col.astype(np.float32), h, rough, 3.0)


# ---------------------------------------------------------------------------
# ceiling
# ---------------------------------------------------------------------------
def ceiling():
    n = N
    brush = noise(401, 1.2, (0.3, 6.0))
    lumpy = noise(402, 2.4)
    fine = noise(403, 0.8)
    f1, f2 = T.worley(n, n, 900, 404)
    craq = T.smoothstep(2.2, 0.0, f2 - f1) * T.smoothstep(0.45, 0.8, noise(405, 2.6))
    big = np.zeros((n, n), np.float32)
    rc = T.rng(406)
    for _ in range(7):
        x, y = rc.uniform(0, n), rc.uniform(0, n)
        a = rc.uniform(0, 2 * np.pi)
        pts = []
        for i in range(70):
            a += rc.normal(0, 0.22)
            x += np.cos(a) * 9
            y += np.sin(a) * 9
            pts.append((x, y))
        for i in range(len(pts) - 1):
            p0, p1 = pts[i], pts[i + 1]
            w = 2 if i < 45 else 1
            x0_, y0_ = np.mod(p0[0], n), np.mod(p0[1], n)
            x1_, y1_ = x0_ + (p1[0] - p0[0]), y0_ + (p1[1] - p0[1])
            wrap_draw(big, lambda img, ox, oy: cv2.line(img, (int(x0_ + ox), int(y0_ + oy)), (int(x1_ + ox), int(y1_ + oy)), 1.0, w, cv2.LINE_AA))
    big = np.clip(big, 0, 1)
    # flakes of paint lifting along the big cracks
    near = T.blur(big, 10.0)
    flakes = T.smoothstep(0.08, 0.14, near * noise(407, 1.0)) * T.smoothstep(0.4, 0.6, noise(408, 1.6))
    col = np.zeros((n, n, 3), np.float32) + L([0.64, 0.66, 0.65])
    col *= (0.92 + 0.06 * brush + 0.06 * lumpy + 0.03 * fine)[..., None]
    col *= (1 - 0.35 * craq)[..., None]
    col *= (1 - 0.7 * big)[..., None]
    col = T.lerp(col, L([0.48, 0.49, 0.47]), (flakes * 0.7)[..., None])
    h = 0.15 * brush + 0.35 * lumpy + 0.05 * fine - 0.3 * craq - 0.9 * big + 0.4 * flakes
    rough = 0.9 - 0.05 * brush
    save_set("ceiling", col, T.blur_wrap(h, 0.8), rough, 2.0)


# ---------------------------------------------------------------------------
# bathroom tiles
# ---------------------------------------------------------------------------
def walltile():
    n = N
    nt = 4
    ts = n / nt
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    lx = np.mod(xx, ts)
    ly = np.mod(yy, ts)
    ix = np.floor(xx / ts).astype(int)
    iy = np.floor(yy / ts).astype(int)
    tid = iy * nt + ix
    g = 5.0                                       # half grout width, px
    dx = np.minimum(lx, ts - lx)
    dy = np.minimum(ly, ts - ly)
    d = np.minimum(dx, dy)
    grout = T.smoothstep(g + 1.0, g - 0.5, d)
    cushion = T.smoothstep(g, g + 26.0, d)          # rounded tile edges
    r = T.rng(501)
    tone = r.uniform(0.9, 1.04, nt * nt)
    tint = r.uniform(-1, 1, nt * nt)
    wav = noise(502, 2.8)
    glaze = np.zeros((n, n, 3), np.float32) + L([0.72, 0.77, 0.74])
    glaze *= (tone[tid] * (0.97 + 0.05 * wav))[..., None]
    glaze = T.lerp(glaze, glaze * np.array([0.94, 0.98, 1.0], np.float32), (np.clip(tint[tid], 0, 1) * 0.6)[..., None])
    # crazing on some tiles
    craze_tiles = r.random(nt * nt) < 0.45
    f1, f2 = T.worley(n, n, 700, 503)
    craze = T.smoothstep(1.6, 0.0, f2 - f1) * craze_tiles[tid]
    craze *= T.smoothstep(0.35, 0.7, noise(504, 2.2))
    # chipped corners: the beige body shows through
    chip = np.zeros((n, n), np.float32)
    for t in range(nt * nt):
        if r.random() < 0.35:
            cxp = (t % nt) * ts + (0 if r.random() < 0.5 else ts)
            cyp = (t // nt) * ts + (0 if r.random() < 0.5 else ts)
            rad = r.uniform(14, 40)
            pts = []
            for a in np.linspace(0, 2 * np.pi, 14, endpoint=False):
                rr = rad * r.uniform(0.6, 1.2)
                pts.append((cxp + np.cos(a) * rr, cyp + np.sin(a) * rr))
            poly = np.array(pts, np.float32)
            wrap_draw(chip, lambda img, ox, oy: cv2.fillPoly(img, [np.round((poly + [ox, oy]) * 4).astype(np.int32)], 1.0, cv2.LINE_AA, shift=2))
    chip *= (1 - grout)
    col = glaze
    col *= (1 - 0.4 * craze)[..., None]
    col = T.lerp(col, L([0.5, 0.48, 0.44]), (chip * 0.9)[..., None])
    gcol = np.zeros((n, n, 3), np.float32) + L([0.26, 0.28, 0.27])
    gdirt = noise(505, 1.8)
    gcol *= (0.55 + 0.6 * gdirt)[..., None]
    col = T.lerp(col, gcol, grout[..., None])
    col *= (0.86 + 0.14 * cushion)[..., None]
    h = 0.55 * cushion - 0.5 * grout + 0.03 * wav - 0.15 * craze - 0.35 * chip
    rough = 0.08 + 0.05 * wav + 0.8 * grout + 0.6 * chip + 0.2 * craze
    save_set("walltile", col, T.blur_wrap(h, 0.8), rough, 3.0)


def hexfloor():
    n = N
    cols = 20                                     # hexes across one repeat
    rows = 24
    w = n / cols                                  # flat-to-flat width (px)
    rh = n / rows                                 # row spacing (px), slightly squashed
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    # nearest hex centre in a pointy-top grid (odd rows shifted by w/2)
    best = np.full((n, n), 1e9, np.float32)
    second = np.full((n, n), 1e9, np.float32)
    cid = np.zeros((n, n), np.int64)
    rowi = np.floor(yy / rh).astype(int)
    for dr in (-1, 0, 1):
        rr_ = rowi + dr
        off = np.where(np.mod(rr_, 2) == 1, w * 0.5, 0.0)
        cy = (rr_ + 0.5) * rh
        coli = np.floor((xx - off) / w).astype(int)
        for dc in (-1, 0, 1):
            cc = coli + dc
            cx = (cc + 0.5) * w + off
            # hex distance (pointy top): max of three projections
            px_ = np.abs(xx - cx)
            py_ = np.abs(yy - cy) * (w * 0.866 / rh)
            hd = np.maximum(px_, px_ * 0.5 + py_ * 0.866)
            upd = hd < best
            second = np.where(upd, best, np.minimum(second, hd))
            best = np.where(upd, hd, best)
            cid = np.where(upd, np.mod(rr_, rows) * cols + np.mod(cc, cols), cid)
    edge = (second - best)
    grout = T.smoothstep(3.0, 1.0, edge)
    r = T.rng(601)
    nh = rows * cols
    dark = np.zeros(nh, bool)
    for rr_ in range(rows):
        for cc in range(cols):
            # black rosettes: a centre and its ring, on a sparse lattice
            if (rr_ % 4 == 1 and cc % 4 == 1) or (rr_ % 4 == 3 and cc % 4 == 3):
                dark[rr_ * cols + cc] = True
    tone = r.uniform(0.88, 1.05, nh)
    cracked = r.random(nh) < 0.06
    missing = r.random(nh) < 0.012
    white = L([0.68, 0.7, 0.68])
    black = L([0.04, 0.04, 0.045])
    col = np.where(dark[cid][..., None], black, white).astype(np.float32) * tone[cid][..., None].astype(np.float32)
    f1, f2 = T.worley(n, n, 500, 602)
    crk = T.smoothstep(1.8, 0.0, f2 - f1) * cracked[cid]
    col *= (1 - 0.5 * crk)[..., None]
    gcol = np.zeros((n, n, 3), np.float32) + L([0.24, 0.23, 0.2]) * (0.6 + 0.6 * noise(603, 1.6))[..., None]
    col = T.lerp(col, gcol, grout[..., None])
    miss = missing[cid].astype(np.float32)
    col = T.lerp(col, L([0.3, 0.29, 0.26]) * (0.7 + 0.5 * noise(604, 1.0))[..., None], miss[..., None])
    dirt = T.smoothstep(0.45, 0.9, noise(605, 2.4))
    col = T.lerp(col, col * np.array([0.62, 0.64, 0.6], np.float32), (dirt * 0.5)[..., None])
    dome = T.smoothstep(0.0, 9.0, edge)
    h = 0.5 * dome - 0.4 * grout - 0.6 * miss - 0.1 * crk
    rough = 0.15 + 0.7 * grout + 0.6 * miss + 0.25 * dirt + 0.2 * crk
    save_set("hexfloor", col.astype(np.float32), T.blur_wrap(h, 0.8), rough, 3.0)


# ---------------------------------------------------------------------------
# dark varnished panel wood
# ---------------------------------------------------------------------------
def panel():
    n = N
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    # grain runs along x (the long axis of every board, as MeshUtil.box lays its UVs)
    warp = noise(701, 1.8, (0.2, 6.0))
    rings = np.sin((yy / n * 36.0 + warp * 7.0) * np.pi)
    grain = noise(702, 1.2, (0.15, 12.0))
    pores = T.smoothstep(0.66, 0.82, noise(703, 0.5, (0.4, 14.0)))
    col = np.zeros((n, n, 3), np.float32) + L([0.13, 0.11, 0.1])
    col *= (0.8 + 0.12 * rings + 0.25 * grain)[..., None]
    col *= (1 - 0.3 * pores)[..., None]
    scuff = T.smoothstep(0.6, 0.85, noise(704, 2.2)) * T.smoothstep(0.5, 0.8, noise(705, 1.0))
    col = T.lerp(col, L([0.26, 0.25, 0.23]), (scuff * 0.5)[..., None])
    h = 0.1 * rings + 0.15 * grain - 0.2 * pores - 0.1 * scuff
    rough = 0.3 + 0.35 * scuff + 0.1 * grain
    save_set("panel", col, T.blur_wrap(h, 0.6), rough, 2.0)


# ---------------------------------------------------------------------------
# upholstery and dust sheets
# ---------------------------------------------------------------------------
def velvet():
    """Dusty grey-teal velvet: pile direction, bald worn patches, stains."""
    n = 1024
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    weave = (np.sin(xx * 2 * np.pi / 5) * np.sin(yy * 2 * np.pi / 5) * 0.5 + 0.5)
    pile = noise(801, 1.6, (1.0, 3.0), n)
    mid = noise(802, 2.2, n=n)
    col = np.zeros((n, n, 3), np.float32) + L([0.2, 0.26, 0.26])
    col *= (0.65 + 0.4 * pile + 0.2 * mid)[..., None]
    bald = T.smoothstep(0.62, 0.8, noise(803, 2.4, n=n))
    col = T.lerp(col, L([0.33, 0.36, 0.34]), (bald * 0.6)[..., None])
    stain = T.smoothstep(0.68, 0.82, noise(804, 2.6, n=n))
    col = T.lerp(col, L([0.12, 0.13, 0.12]), (stain * 0.6)[..., None])
    h = 0.3 * weave * (1 - bald) + 0.3 * pile
    rough = 0.92 - 0.12 * pile + 0.05 * bald
    T.save(OUT / "velvet_albedo.png", T.linear_to_srgb(col))
    T.save(OUT / "velvet_normal.png", T.normal_from_height(T.blur_wrap(h, 0.5), 2.0))
    T.save(OUT / "velvet_rough.png", np.clip(rough, 0, 1))


def linen():
    """A dust sheet: grey-white linen, coarse weave, dust, mildew, old stains."""
    n = 1024
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    wx = np.sin(xx * 2 * np.pi / 4.0) * 0.5 + 0.5
    wy = np.sin(yy * 2 * np.pi / 4.0) * 0.5 + 0.5
    slub = noise(811, 1.0, (0.3, 8.0), n) * 0.5 + noise(812, 1.0, (8.0, 0.3), n) * 0.5
    col = np.zeros((n, n, 3), np.float32) + L([0.66, 0.68, 0.66])
    col *= (0.85 + 0.1 * (wx * wy) + 0.12 * slub)[..., None]
    dust = T.smoothstep(0.4, 0.9, noise(813, 2.4, n=n))
    col = T.lerp(col, L([0.48, 0.48, 0.45]), (dust * 0.45)[..., None])
    mil = T.smoothstep(0.7, 0.8, noise(814, 1.8, n=n)) * T.smoothstep(0.5, 0.7, noise(815, 2.6, n=n))
    col = T.lerp(col, L([0.3, 0.33, 0.3]), (mil * 0.5)[..., None])
    stain = noise(816, 2.8, n=n)
    ring = np.exp(-np.square((stain - 0.72) / 0.012)) * 0.7 + T.smoothstep(0.7, 0.8, stain) * 0.35
    col = T.lerp(col, L([0.42, 0.4, 0.34]), (np.clip(ring, 0, 1) * 0.5)[..., None])
    h = 0.4 * wx * wy + 0.3 * slub
    rough = 0.95 - 0.05 * slub
    T.save(OUT / "linen_albedo.png", T.linear_to_srgb(col))
    T.save(OUT / "linen_normal.png", T.normal_from_height(T.blur_wrap(h, 0.4), 1.5))
    T.save(OUT / "linen_rough.png", np.clip(rough, 0, 1))


ALL = {"velvet": velvet, "linen": linen, "damask": damask, "glue": glue, "herring": herring, "ceiling": ceiling,
       "walltile": walltile, "hexfloor": hexfloor, "panel": panel}

if __name__ == "__main__":
    for nm in sys.argv[1:] or list(ALL):
        print("--", nm)
        ALL[nm]()

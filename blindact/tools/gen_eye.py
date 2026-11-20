#!/usr/bin/env python3
"""Textures for the main-menu eye (shaders/eye.gdshader).

The eye follows the owner's sketch: a long almond with a tapering tail on
the left (outer corner), a rounder inner corner on the right (caruncle),
and a large iris cut by the upper lid.

  eye_iris.png    polar iris: x = angle (0..1 around), y = radius (top = pupil
                  edge, bottom = limbus). RGB = colour (sRGB), A = height.
  eye_veins.png   sclera vessels in an azimuthal-equidistant chart centred on
                  the gaze axis: X = theta*cos(phi), Y = theta*sin(phi),
                  theta in [0, 1.8] rad mapped to [-1.8, 1.8] -> uv [0, 1]
                  (uv.y = 0.5 - Y / 3.6).
                  R = superficial veins, G = capillaries, B = haemorrhage,
                  A = deep (episcleral) vessels.
  eye_skin.png    skin around the eye in eye units, x in [-3.2, 3.2],
                  y in [-1.8, 1.8] (iris radius = 0.5), lids open.
                  RGB = albedo (sRGB), A = cavity.
  eye_skin_n.png  matching normal map (fine detail only: pores, wrinkles).
  eye_lash_up.png / eye_lash_lo.png  eyelash strips: x = along the fissure
                  (left tip -> right corner), y = distance from the margin
                  (bottom row = margin for the upper strip, top row = margin
                  for the lower strip).

The lid curves below MUST match the ones in eye.gdshader.
Usage: python3 tools/gen_eye.py
"""
from __future__ import annotations

import math
from pathlib import Path

import cv2
import numpy as np

import texlib as T

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "textures"
OUT.mkdir(parents=True, exist_ok=True)

# ---- lid geometry (eye units, shared with the shader) ----------------------
X_L, Y_L = -2.0, 0.07           # left tip (outer corner, long tail)
X_R, Y_R = 1.35, -0.25          # right corner (inner corner, caruncle)
UP_H, UP_PK, UP_PL, UP_PR = 0.69, 0.68, 1.6, 0.5
LO_H, LO_PK, LO_PL, LO_PR = 0.32, 0.65, 1.85, 0.45
L_UP, L_LO = 0.42, 0.20          # lash strip heights


def bump2(s, peak, pl, pr):
    s = np.clip(s, 0.0, 1.0)
    left = s < peak
    u = np.where(left, s / peak, (1.0 - s) / (1.0 - peak))
    v = np.maximum(np.sin(0.5 * np.pi * u), 0.0)
    return np.where(left, np.power(v, pl), np.power(v, pr))


def fiss_s(x):
    return (x - X_L) / (X_R - X_L)


def base_y(x):
    return Y_L + (Y_R - Y_L) * np.clip(fiss_s(x), 0.0, 1.0)


def lid_up(x):
    return base_y(x) + UP_H * bump2(fiss_s(x), UP_PK, UP_PL, UP_PR)


def lid_lo(x):
    return base_y(x) - LO_H * bump2(fiss_s(x), LO_PK, LO_PL, LO_PR)


def crease(x):
    return lid_up(x) + 0.22 + 0.10 * bump2(fiss_s(x), UP_PK, 1.2, 0.8)


# ---------------------------------------------------------------------------
# iris
# ---------------------------------------------------------------------------
def make_iris():
    W, H = 2048, 512
    v = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None]
    disp = (T.fft_noise(H, W, 11, beta=3.2, aniso=(3, 1)) - 0.5) * 18.0
    mapx = (np.arange(W, dtype=np.float32)[None, :] + disp).astype(np.float32)
    mapy = np.repeat(np.arange(H, dtype=np.float32)[:, None], W, 1)

    def warp(a):
        return cv2.remap(a, mapx, mapy, cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)

    fib = warp(T.fft_noise(H, W, 1, beta=1.3, aniso=(16, 1)))
    fib2 = warp(T.fft_noise(H, W, 2, beta=1.0, aniso=(30, 1.6)))
    fine = T.fft_noise(H, W, 3, beta=0.8, aniso=(4, 4))
    low = T.fft_noise(H, W, 4, beta=3.0, aniso=(2, 1))

    n1 = T.fft_noise(1, W * 4, 5, beta=2.2)[0, ::4]
    n2 = T.fft_noise(1, W * 4, 6, beta=1.2)[0, ::4]
    vc = 0.30 + 0.06 * (n1 - 0.5) + 0.03 * (n2 - 0.5)
    collar = np.exp(-np.square((v - vc[None, :]) / 0.022))
    pupillary = T.smoothstep(0.0, 0.03, vc[None, :] - v)

    r = T.rng(7)
    crypt = np.zeros((H, W), np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    for _ in range(140):
        cu = r.random() * W
        cv_ = (r.uniform(0.33, 0.7)) * H
        sx = r.uniform(2.5, 8.0)
        sy = r.uniform(14.0, 50.0)
        dx = (xx - cu + W / 2) % W - W / 2
        dy = yy - cv_
        g = np.exp(-(dx * dx) / (2 * sx * sx) - (dy * dy) / (2 * sy * sy))
        crypt = np.maximum(crypt, g * r.uniform(0.4, 1.0))
    crypt = T.smoothstep(0.3, 0.9, crypt) * (0.5 + 0.5 * fine)

    furrow = np.zeros((H, W), np.float32)
    for i, vf in enumerate((0.60, 0.71, 0.82, 0.90)):
        brk = T.fft_noise(1, W * 2, 20 + i, beta=2.0)[0, ::2]
        wob = (T.fft_noise(1, W * 2, 30 + i, beta=2.6)[0, ::2] - 0.5) * 0.04
        ring = np.exp(-np.square((v - vf - wob[None, :]) / 0.006))
        furrow = np.maximum(furrow, ring * T.smoothstep(0.45, 0.65, brk)[None, :])

    # a dark, slightly reddish brown iris
    L = T.srgb_to_linear
    c_pup = L([0.27, 0.16, 0.10])
    c_col = L([0.36, 0.24, 0.15])
    c_cil = L([0.30, 0.19, 0.12])
    c_cil2 = L([0.30, 0.25, 0.19])
    c_dark = L([0.06, 0.035, 0.025])
    col = np.zeros((H, W, 3), np.float32)
    green = T.smoothstep(0.55, 0.8, T.fft_noise(H, W, 8, beta=2.0, aniso=(6, 1)))[..., None]
    col[:] = T.lerp(c_cil, c_cil2, green * 0.5)
    col = T.lerp(col, c_pup, pupillary[..., None])
    col *= (0.28 + 1.45 * fib)[..., None] * (0.7 + 0.6 * fib2)[..., None] * (0.85 + 0.3 * low)[..., None]
    col = T.lerp(col, c_col * (0.75 + 0.5 * fib2[..., None]), (collar * 0.35)[..., None])
    col = T.lerp(col, c_dark, (crypt * 0.8)[..., None])
    col = T.lerp(col, c_dark, (furrow * 0.45)[..., None])
    limbal = T.smoothstep(0.8, 1.0, v) * (0.85 + 0.15 * fine)
    col = T.lerp(col, L([0.035, 0.025, 0.02]), limbal[..., None])
    ruff = T.smoothstep(0.05, 0.0, v + (fine - 0.5) * 0.03)
    col = T.lerp(col, L([0.07, 0.04, 0.025]), ruff[..., None])
    for _ in range(9):
        cu, cv_ = r.random() * W, r.uniform(0.4, 0.85) * H
        rad = r.uniform(3, 8)
        dx = (xx - cu + W / 2) % W - W / 2
        g = np.exp(-(dx * dx + (yy - cv_) ** 2) / (2 * rad * rad))
        col = T.lerp(col, L([0.14, 0.06, 0.03]), (T.smoothstep(0.3, 0.7, g) * 0.8)[..., None])

    height = 0.55 * fib + 0.25 * fib2 + 0.25 * collar - 0.6 * crypt - 0.3 * furrow - 0.25 * limbal
    height = T.normalize(T.blur_wrap(height, 0.8))
    rgba = np.concatenate([T.linear_to_srgb(col), height[..., None]], -1)
    T.save(OUT / "eye_iris.png", rgba)


# ---------------------------------------------------------------------------
# sclera vessels
# ---------------------------------------------------------------------------
def make_veins():
    N = 2048
    SS = 2
    M = N * SS
    th_max = 1.8
    canvas_r = np.zeros((M, M), np.float32)
    canvas_g = np.zeros((M, M), np.float32)
    canvas_a = np.zeros((M, M), np.float32)
    r = T.rng(42)

    def to_px(X, Y):
        return (X / (2 * th_max) + 0.5) * M, (0.5 - Y / (2 * th_max)) * M

    def walk(canvas, X, Y, ang, width, th_end, depth, meander, branch_p, step=0.012):
        pts = [(X, Y)]
        w = width
        while True:
            th = math.hypot(X, Y)
            if th < th_end or w < 0.0012 or len(pts) > 600:
                break
            to_c = math.atan2(-Y, -X)
            d = (to_c - ang + math.pi) % (2 * math.pi) - math.pi
            ang += d * 0.08 + r.normal(0, meander)
            X += math.cos(ang) * step
            Y += math.sin(ang) * step
            pts.append((X, Y))
            w *= 0.985
            if depth < 4 and r.random() < branch_p:
                side = 1 if r.random() < 0.5 else -1
                walk(canvas, X, Y, ang + side * r.uniform(0.35, 1.1), w * r.uniform(0.45, 0.8),
                     th_end + r.uniform(0.0, 0.3), depth + 1, meander * 1.35, branch_p * 0.8, step * 0.9)
        for i in range(len(pts) - 1):
            k = i / max(len(pts) - 1, 1)
            wd = width * (1.0 - 0.75 * k)
            p0 = to_px(*pts[i])
            p1 = to_px(*pts[i + 1])
            th_px = max(1, int(round(wd / (2 * th_max) * M)))
            cv2.line(canvas, (int(p0[0] * 4), int(p0[1] * 4)), (int(p1[0] * 4), int(p1[1] * 4)),
                     1.0, th_px, cv2.LINE_AA, shift=2)

    # superficial veins come in from the corners (phi ~ 0 and pi): the fissure
    # is narrow, so that is all you see
    for i in range(54):
        side = 0.0 if i % 2 == 0 else math.pi
        phi = side + r.normal(0, 0.38)
        if r.random() < 0.12:
            phi = r.uniform(0, 2 * math.pi)
        th0 = r.uniform(1.55, 1.78)
        X, Y = th0 * math.cos(phi), th0 * math.sin(phi)
        walk(canvas_r, X, Y, phi + math.pi + r.normal(0, 0.3), r.uniform(0.008, 0.019),
             r.uniform(0.6, 1.0), 0, 0.17, 0.055)
    for i in range(16):
        side = 0.0 if i % 2 == 0 else math.pi
        phi = side + r.normal(0, 0.5)
        th0 = r.uniform(1.5, 1.78)
        walk(canvas_a, th0 * math.cos(phi), th0 * math.sin(phi), phi + math.pi, r.uniform(0.02, 0.035),
             r.uniform(0.8, 1.2), 1, 0.12, 0.03, 0.02)
    for _ in range(900):
        side = 0.0 if r.random() < 0.5 else math.pi
        phi = side + r.normal(0, 0.6)
        th = r.uniform(0.62, 1.7)
        X, Y = th * math.cos(phi), th * math.sin(phi)
        walk(canvas_g, X, Y, r.uniform(0, 2 * math.pi), r.uniform(0.0022, 0.004),
             th - r.uniform(0.05, 0.22), 2, 0.5, 0.06, 0.006)

    rch = cv2.resize(canvas_r, (N, N), interpolation=cv2.INTER_AREA)
    gch = cv2.resize(canvas_g, (N, N), interpolation=cv2.INTER_AREA)
    ach = cv2.resize(canvas_a, (N, N), interpolation=cv2.INTER_AREA)
    ach = T.normalize(T.blur(ach, 6.0)) ** 0.8
    rch = np.clip(rch + T.blur(rch, 3.0) * 0.45, 0, 1)
    gch = np.clip(gch * 0.85 + T.blur(gch, 2.0) * 0.35, 0, 1)

    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    X = (xx / N - 0.5) * 2 * th_max
    Y = (0.5 - yy / N) * 2 * th_max
    hem = np.zeros((N, N), np.float32)
    nz = T.fft_noise(N, N, 99, beta=2.4)
    nz2 = T.fft_noise(N, N, 98, beta=1.2)
    for i in range(7):
        side = 0.0 if i % 2 == 0 else math.pi
        phi = side + r.normal(0, 0.25)
        th = r.uniform(0.8, 1.5)
        cx, cy = th * math.cos(phi), th * math.sin(phi)
        rad = r.uniform(0.14, 0.32)
        d = np.sqrt(((X - cx) * 0.8) ** 2 + (Y - cy) ** 2) / rad
        hem = np.maximum(hem, T.smoothstep(1.0, 0.82, d + (nz - 0.5) * 0.8 + (nz2 - 0.5) * 0.18))
    rgba = np.stack([rch, gch, np.clip(hem, 0, 1), ach], -1)
    T.save(OUT / "eye_veins.png", rgba)


# ---------------------------------------------------------------------------
# skin around the eye
# ---------------------------------------------------------------------------
def make_skin():
    W, H = 2560, 1440
    x = np.linspace(-3.2, 3.2, W, dtype=np.float32)[None, :]
    y = np.linspace(1.8, -1.8, H, dtype=np.float32)[:, None]
    X = np.repeat(x, H, 0)
    Y = np.repeat(y, W, 1)
    yu = lid_up(X)
    yl = lid_lo(X)
    yc = crease(X)
    s = fiss_s(X)
    in_span = T.smoothstep(-0.12, 0.04, s) * T.smoothstep(1.12, 0.97, s)

    r = T.rng(5)
    f1, f2 = T.worley(H // 2, W // 2, 30000, 51)
    pores = cv2.resize(T.smoothstep(2.0, 0.5, f1), (W, H), interpolation=cv2.INTER_LINEAR)
    cell = cv2.resize(T.smoothstep(0.0, 3.0, f2 - f1), (W, H), interpolation=cv2.INTER_LINEAR)
    micro = T.fft_noise(H, W, 52, beta=1.0)
    hx = 0.22 * cell + 0.12 * micro
    lid_zone = T.smoothstep(0.35, 0.0, np.minimum(np.abs(Y - yu), np.abs(Y - yl)))
    hx -= pores * (0.45 - 0.3 * lid_zone)

    def lines_along(curve_y, offsets, width, wob_seed, s_rng=(-0.2, 1.1)):
        out = np.zeros((H, W), np.float32)
        for i, off in enumerate(offsets):
            wob = (T.fft_noise(1, W, wob_seed + i, beta=2.2)[0] - 0.5) * 0.05
            brk = T.smoothstep(0.35, 0.6, T.fft_noise(1, W, wob_seed + 50 + i, beta=1.8)[0])
            d = Y - (curve_y + off + wob[None, :])
            out += np.exp(-np.square(d / width)) * brk[None, :]
        tt = T.smoothstep(s_rng[0], s_rng[0] + 0.15, s) * T.smoothstep(s_rng[1], s_rng[1] - 0.15, s)
        return out * tt

    up_w = lines_along(yu, [0.06, 0.1, 0.15, 0.19], 0.007, 300)
    lo_w = lines_along(yl, [-0.07, -0.13, -0.2, -0.28, -0.37], 0.009, 400)
    hx -= 0.18 * up_w + 0.22 * lo_w
    dc = Y - yc
    hx -= 0.6 * np.exp(-np.square(dc / 0.02)) * in_span
    # crow's feet from the long outer (left) corner
    ox, oy = X_L + 0.15, Y_L
    ang = np.arctan2(Y - oy, -(X - ox))
    rad = np.hypot(X - ox, Y - oy)
    cf = np.zeros((H, W), np.float32)
    for k in range(10):
        a0 = -0.8 + k * 0.18 + r.normal(0, 0.04)
        wob = 0.03 * np.sin(rad * 9.0 + k)
        cf += np.exp(-np.square((ang - a0 - wob) * rad / 0.011)) * T.smoothstep(0.15, 0.4, rad) * T.smoothstep(1.3, 0.8, rad)
    hx -= 0.18 * cf * (X < ox)
    height = T.blur(hx, 0.7)
    nrm = T.normal_from_height(height, strength=2.0, wrap=False)

    Lc = T.srgb_to_linear
    base = Lc([0.60, 0.47, 0.42])
    col = np.zeros((H, W, 3), np.float32) + base
    mott = T.fft_noise(H, W, 60, beta=2.6)
    blot = T.fft_noise(H, W, 61, beta=1.8)
    col *= (0.88 + 0.24 * mott)[..., None]
    red = Lc([0.62, 0.28, 0.27])
    rim = T.smoothstep(0.3, 0.0, np.minimum(np.abs(Y - yu), np.abs(Y - yl))) * in_span
    col = T.lerp(col, red, (np.clip(0.38 * rim + 0.3 * (blot - 0.35), 0, 1))[..., None])
    inner = T.smoothstep(0.6, 0.0, np.hypot(X - X_R, (Y - Y_R) * 1.3))
    col = T.lerp(col, Lc([0.58, 0.26, 0.27]), (inner * 0.5)[..., None])
    under = T.smoothstep(0.0, -0.12, Y - yl) * T.smoothstep(-0.9, -0.3, Y - yl) * T.smoothstep(1.9, 0.6, np.abs(X + 0.2))
    col = T.lerp(col, Lc([0.33, 0.24, 0.28]), (under * 0.55)[..., None])
    lid = T.smoothstep(0.0, 0.05, Y - yu) * T.smoothstep(0.02, -0.04, Y - yc) * in_span
    col = T.lerp(col, Lc([0.66, 0.40, 0.40]), (lid * 0.2)[..., None])
    vn = T.fft_noise(H, W, 62, beta=1.6, aniso=(1, 3))
    veinl = T.smoothstep(0.012, 0.0, np.abs(vn - 0.5)) * T.smoothstep(0.0, 0.6, lid + under)
    col = T.lerp(col, Lc([0.36, 0.30, 0.46]), (veinl * 0.4)[..., None])
    col *= (1.0 - 0.07 * pores * (1 - lid_zone))[..., None]
    col *= (1.0 - 0.1 * np.clip(up_w + lo_w + cf, 0, 1))[..., None]
    col *= (1.0 - 0.15 * np.exp(-np.square(dc / 0.03)) * in_span)[..., None]
    for (mx, my, mr) in ((0.95, -1.05, 0.022), (-2.35, -0.55, 0.016)):
        d = np.hypot(X - mx, Y - my) / mr
        col = T.lerp(col, Lc([0.2, 0.11, 0.07]), (T.smoothstep(1.0, 0.6, d) * 0.85)[..., None])

    cavity = T.normalize(T.blur(height, 2.0))
    rgba = np.concatenate([T.linear_to_srgb(col), cavity[..., None]], -1)
    T.save(OUT / "eye_skin.png", rgba)
    T.save(OUT / "eye_skin_n.png", nrm)


# ---------------------------------------------------------------------------
# eyelashes
# ---------------------------------------------------------------------------
def draw_lashes(W, H, count, Lstrip, length_rng, seed, upper=True):
    SS = 2
    Wc, Hc = W * SS, H * SS
    span = X_R - X_L
    canvas = np.zeros((Hc, Wc), np.float32)
    r = T.rng(seed)
    ppx = Wc / span
    ppy = Hc / Lstrip
    clumps = []
    i = 0
    while i < count:
        k = int(r.integers(1, 4))
        clumps.append(k)
        i += k
    lo_s, hi_s = (0.04, 0.93) if upper else (0.08, 0.8)
    roots = np.sort(r.uniform(lo_s, hi_s, len(clumps)))
    for cu, k in zip(roots, clumps):
        # longest over the outer half (left), short at the inner corner (right)
        prof = math.exp(-((cu - 0.42) / 0.3) ** 2)
        L = length_rng[0] + (length_rng[1] - length_rng[0]) * prof * r.uniform(0.75, 1.05)
        L *= T.smoothstep(0.0, 0.12, cu) * 0.6 + 0.4
        # lashes sweep outwards (to the left) on the outer part
        tilt = (cu - 0.72) * (1.5 if upper else 1.1)
        tip_u = cu + math.sin(tilt + r.normal(0, 0.12)) * L / span + r.normal(0, 0.004)
        for j in range(k):
            u0 = cu + r.normal(0, 0.004)
            v0 = abs(r.normal(0, 0.01))
            Lj = L * r.uniform(0.7, 1.0)
            tu = tip_u + r.normal(0, 0.0015)
            p0 = np.array([u0 * span, v0])
            p2 = np.array([tu * span, Lj])
            p1 = np.array([u0 * span + (tu - u0) * span * 0.15, Lj * 0.65])
            ts = np.linspace(0, 1, 28)
            pts = (1 - ts)[:, None] ** 2 * p0 + 2 * (1 - ts)[:, None] * ts[:, None] * p1 + ts[:, None] ** 2 * p2
            for q in range(len(pts) - 1):
                w = 0.0058 * (1.0 - 0.85 * ts[q]) + 0.0009
                a, b = pts[q], pts[q + 1]
                ax, ay = a[0] * ppx, Hc - a[1] * ppy
                bx, by = b[0] * ppx, Hc - b[1] * ppy
                if not upper:
                    ay, by = Hc - ay, Hc - by
                thick = max(1, int(round(w * ppx)))
                cv2.line(canvas, (int(ax * 4), int(ay * 4)), (int(bx * 4), int(by * 4)), 1.0, thick, cv2.LINE_AA, shift=2)
    alpha = cv2.resize(np.clip(canvas, 0, 1), (W, H), interpolation=cv2.INTER_AREA)
    rgb = np.zeros((H, W, 3), np.float32) + np.array([0.03, 0.025, 0.022], np.float32)
    return np.concatenate([rgb, alpha[..., None]], -1)


def make_lashes():
    T.save(OUT / "eye_lash_up.png", draw_lashes(3072, 512, 260, L_UP, (0.13, 0.38), 77, True))
    T.save(OUT / "eye_lash_lo.png", draw_lashes(3072, 256, 110, L_LO, (0.04, 0.13), 78, False))


if __name__ == "__main__":
    import sys
    which = sys.argv[1:] or ["iris", "veins", "lashes", "skin"]
    if "iris" in which:
        make_iris()
    if "veins" in which:
        make_veins()
    if "lashes" in which:
        make_lashes()
    if "skin" in which:
        make_skin()

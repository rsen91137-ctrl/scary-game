#!/usr/bin/env python3
"""Generate the game's textures.

Sources:
  * art/reference/corridor_0*.jpg  - the reference photos of the real corridor.
    Pillar sandstone blocks and weathered beam wood are rectified straight out of
    these photos (perspective-corrected, de-lit and colour-normalised).
  * Everything that the photos cannot supply at high enough resolution
    (granite, floor stone, bench wood, bark, leaves, tree line, flare...) is
    synthesised procedurally and colour-matched to the photos.

Usage:  python3 tools/gen_textures.py        (writes into assets/textures/)
Deps:   numpy, opencv-python-headless
"""
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "art" / "reference"
OUT = ROOT / "assets" / "textures"
OUT.mkdir(parents=True, exist_ok=True)


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def load_photo(n):
    im = cv2.imread(str(REF / f"corridor_0{n}.jpg"), cv2.IMREAD_COLOR)[:, :, ::-1]
    return im.astype(np.float32) / 255.0


def save(name, img):
    img = np.clip(img, 0.0, 1.0)
    u8 = (img * 255.0 + 0.5).astype(np.uint8)
    if u8.ndim == 3 and u8.shape[2] == 3:
        u8 = u8[:, :, ::-1]
    elif u8.ndim == 3 and u8.shape[2] == 4:
        u8 = u8[:, :, [2, 1, 0, 3]]
    cv2.imwrite(str(OUT / name), u8, [cv2.IMWRITE_PNG_COMPRESSION, 9])
    print("wrote", name, img.shape)


def s2l(x):
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4).astype(np.float32)


def l2s(x):
    x = np.clip(x, 0.0, None)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055).astype(np.float32)


def lum(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def hexcol(r, g, b):
    return s2l(np.array([r, g, b], np.float32) / 255.0)


def warp(img, quad, w, h):
    src = np.float32(quad)
    dst = np.float32([[0, 0], [w, 0], [w, h], [0, h]])
    m = cv2.getPerspectiveTransform(src, dst)
    return cv2.warpPerspective(img, m, (w, h), flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REFLECT)


def blur(img, sigma, wrap=False):
    if wrap:
        p = int(sigma * 3) + 1
        pad = [(p, p), (p, p)] + [(0, 0)] * (img.ndim - 2)
        big = np.pad(img, pad, mode="wrap")
        big = cv2.GaussianBlur(big, (0, 0), sigma)
        return big[p:-p, p:-p]
    return cv2.GaussianBlur(img, (0, 0), sigma, borderType=cv2.BORDER_REFLECT)


def noise(h, w, beta=2.0, seed=0, ax=1.0, ay=1.0, lo=0.0, hi=1e9):
    """Periodic (tileable) spectral noise, zero mean / unit std.
    beta: spectral slope, ax/ay: anisotropy (ax>ay stretches features along y)."""
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    rad = np.sqrt((fx * ax) ** 2 + (fy * ay) ** 2)
    rad[0, 0] = 1.0
    amp = 1.0 / rad ** (beta / 2.0)
    amp[(rad < lo) | (rad > hi)] = 0.0
    amp[0, 0] = 0.0
    n = np.real(np.fft.ifft2(f * amp)).astype(np.float32)
    return (n - n.mean()) / (n.std() + 1e-8)


def normal_from_height(hgt, strength):
    dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5
    dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------
# 1. Sandstone pillar blocks, rectified from the photos
# ----------------------------------------------------------------------------
# Each face: photo, left edge (top xy, bottom xy), right edge (top xy, bottom xy),
# and the four horizontal lines (top, joint1, joint2, bottom) as (y_left, y_right).
FACES = [
    (1, ((581, 327), (588, 840)), ((667, 311), (675, 872)), [(327, 311), (490, 488), (670, 684), (812, 846)]),
    (1, ((667, 311), (675, 872)), ((762, 321), (770, 846)), [(311, 321), (488, 490), (684, 677), (872, 846)]),
    (1, ((1066, 450), (1068, 776)), ((1140, 446), (1143, 778)), [(450, 446), (552, 554), (663, 669), (742, 752)]),
    (3, ((1006, 432), (1006, 758)), ((1096, 432), (1096, 760)), [(432, 432), (544, 549), (660, 667), (748, 752)]),
    (3, ((311, 432), (311, 738)), ((381, 432), (381, 740)), [(432, 432), (534, 534), (637, 638), (716, 718)]),
]
TILE_W, TILE_H = 512, 640  # one stone block face (0.46 m x 0.575 m)
SAND = hexcol(206, 186, 146)


def edge_x(edge, y):
    (x0, y0), (x1, y1) = edge
    return x0 + (x1 - x0) * (y - y0) / (y1 - y0)


def extract_blocks():
    photos = {n: load_photo(n) for n in (1, 3)}
    tiles = []
    for photo, le, re, lines in FACES:
        img = photos[photo]
        for i in range(3):
            (yl0, yr0), (yl1, yr1) = lines[i], lines[i + 1]
            # inset away from the joints / edges (joints are real geometry in game)
            yl0, yr0, yl1, yr1 = yl0 + 3, yr0 + 3, yl1 - 3, yr1 - 3
            quad = [
                (edge_x(le, yl0) + 1.5, yl0),
                (edge_x(re, yr0) - 1.5, yr0),
                (edge_x(re, yr1) - 1.5, yr1),
                (edge_x(le, yl1) + 1.5, yl1),
            ]
            tiles.append(warp(img, quad, TILE_W, TILE_H))
    return tiles


def delight(tile_srgb, target_lin, sigma, keep=0.18):
    lin = s2l(tile_srgb)
    lu = lum(lin)
    low = blur(lu, sigma) + 1e-4
    # flatten the photographed lighting (flash fall-off etc.) but keep a little
    flat = lin * (lu.mean() / low)[..., None] ** (1.0 - keep)
    # white balance each tile to the target material colour
    mean = flat.reshape(-1, 3).mean(0)
    flat = flat * (target_lin / (mean + 1e-6))
    return flat


def sandstone_atlas():
    tiles = extract_blocks()
    rng = np.random.default_rng(7)
    # 16 slots: 15 photo blocks + one mirrored duplicate
    tiles.append(tiles[4][:, ::-1].copy())
    cols, rows = 4, 4
    alb = np.zeros((rows * TILE_H, cols * TILE_W, 3), np.float32)
    hgt = np.zeros((rows * TILE_H, cols * TILE_W), np.float32)
    rough = np.zeros((rows * TILE_H, cols * TILE_W), np.float32)
    yy, xx = np.mgrid[0:TILE_H, 0:TILE_W].astype(np.float32)
    edge = np.minimum.reduce([xx, TILE_W - 1 - xx, yy, TILE_H - 1 - yy])
    for k, t in enumerate(tiles):
        a = delight(t, SAND, sigma=150)
        rows = lum(a).mean(1)
        band = rows / (blur(rows[:, None], 5)[:, 0] + 1e-5)
        a = a / band[:, None, None]
        a = blur(a, 0.6)
        lu = lum(a)
        detail = lu / (blur(lu, 6) + 1e-4) - 1.0
        # procedural sandstone grain on top of the (upscaled) photo detail
        g1 = noise(TILE_H, TILE_W, beta=0.6, seed=100 + k, lo=40)
        g2 = noise(TILE_H, TILE_W, beta=1.6, seed=200 + k, lo=6, hi=60)
        strata = noise(TILE_H, TILE_W, beta=2.8, seed=300 + k, ax=1.0, ay=0.5, lo=1, hi=14)
        a = a * (1.0 + 0.035 * g1[..., None] + 0.03 * g2[..., None] + 0.02 * strata[..., None])
        # dirt: darker towards the block edges, run-off streaks from the top
        dirt = 1.0 - 0.22 * np.exp(-edge / 10.0) - 0.06 * np.exp(-edge / 45.0)
        streak = noise(TILE_H, TILE_W, beta=2.0, seed=400 + k, ax=0.15, ay=6.0, lo=1)
        streak = np.clip(streak, 0, None) * np.exp(-yy / (TILE_H * 0.6))
        dirt *= 1.0 - 0.10 * streak
        speck = (noise(TILE_H, TILE_W, beta=0.2, seed=500 + k) > 2.6).astype(np.float32)
        dirt *= 1.0 - 0.25 * blur(speck, 0.7)
        a *= dirt[..., None]
        r, c = divmod(k, cols)
        alb[r * TILE_H:(r + 1) * TILE_H, c * TILE_W:(c + 1) * TILE_W] = a
        h = 0.55 * np.clip(detail, -0.4, 0.4) + 0.05 * g1 + 0.08 * g2 + 0.06 * strata - 0.5 * speck
        h -= 0.6 * np.exp(-edge / 6.0)  # bevelled / worn arrises
        hgt[r * TILE_H:(r + 1) * TILE_H, c * TILE_W:(c + 1) * TILE_W] = h
        rough[r * TILE_H:(r + 1) * TILE_H, c * TILE_W:(c + 1) * TILE_W] = 0.86 + 0.05 * g2 - 0.06 * streak
    save("sandstone_albedo.png", l2s(alb))
    save("sandstone_normal.png", normal_from_height(blur(hgt, 0.8), 2.2))
    save("sandstone_rough.png", np.clip(rough, 0, 1))


# ----------------------------------------------------------------------------
# 2. Weathered beam wood, rectified from photo 1 / photo 3
# ----------------------------------------------------------------------------
BEAM = hexcol(112, 98, 84)


def beam_atlas():
    p1, p3 = load_photo(1), load_photo(3)
    strips = [
        warp(p1, [(0, 6), (370, 99), (370, 150), (0, 72)], 2048, 256),
        warp(p3, [(0, 12), (1180, 3), (1180, 21), (0, 66)], 2048, 256),
    ]
    out = []
    for k, s in enumerate(strips):
        a = delight(s, BEAM, sigma=60, keep=0.25)
        # make tileable along the length with a crossfade
        n = 380
        head, tail = a[:, :n].copy(), a[:, -n:].copy()
        w = np.linspace(0.0, 1.0, n, dtype=np.float32)[None, :, None]
        a = a[:, : 2048 - n].copy()
        a[:, :n] = tail * (1 - w) + head * w
        a = cv2.resize(a, (2048, 256), interpolation=cv2.INTER_CUBIC)
        grain = noise(256, 2048, beta=1.8, seed=900 + k, ax=1.0, ay=0.05, lo=2)
        fine = noise(256, 2048, beta=0.8, seed=950 + k, ax=1.0, ay=0.2, lo=20)
        a *= (1.0 + 0.07 * grain + 0.05 * fine)[..., None]
        out.append((a, grain, fine))
    alb = np.concatenate([o[0] for o in out], 0)
    hg = np.concatenate([0.5 * o[1] + 0.35 * o[2] for o in out], 0)
    lu = lum(alb)
    hg += 2.0 * (lu / (blur(lu, 4) + 1e-4) - 1.0)
    # cracks along the grain
    cr = noise(512, 2048, beta=2.2, seed=990, ax=1.0, ay=0.04, lo=1)
    cracks = smoothstep(0.035, 0.0, np.abs(cr)) * (noise(512, 2048, beta=2.0, seed=991, lo=1) > 0.6)
    alb *= (1.0 - 0.55 * cracks)[..., None]
    hg -= 1.5 * cracks
    save("beam_albedo.png", l2s(alb))
    save("beam_normal.png", normal_from_height(blur(hg, 0.7), 1.6))


# ----------------------------------------------------------------------------
# 3. Procedural materials, colour matched to the photos
# ----------------------------------------------------------------------------
def granite(size=1024):
    base = hexcol(176, 170, 160)
    n1 = noise(size, size, beta=0.0, seed=11)
    n2 = noise(size, size, beta=0.0, seed=12)
    n3 = noise(size, size, beta=0.0, seed=13)
    blot = noise(size, size, beta=2.4, seed=14, lo=1)
    grain = lambda n, s: blur(n, s, wrap=True) / (blur(n, s, wrap=True).std() + 1e-6)
    dark = smoothstep(1.2, 1.7, grain(n1, 1.6))
    white = smoothstep(1.3, 1.8, grain(n2, 2.2))
    warm = smoothstep(1.1, 1.6, grain(n3, 2.8))
    a = np.ones((size, size, 3), np.float32) * base
    a *= (1.0 + 0.06 * blot)[..., None]
    a = a * (1 - warm[..., None]) + hexcol(196, 168, 140) * warm[..., None]
    a = a * (1 - white[..., None]) + hexcol(222, 220, 214) * white[..., None]
    a = a * (1 - dark[..., None]) + hexcol(38, 36, 36) * dark[..., None]
    h = 0.4 * dark - 0.3 * white + 0.1 * noise(size, size, beta=1.0, seed=15)
    save("granite_albedo.png", l2s(a))
    save("granite_normal.png", normal_from_height(blur(h, 0.8, wrap=True), 1.2))


def floor_stone(size=1024):
    base = hexcol(132, 129, 121)
    mott = noise(size, size, beta=2.2, seed=21, lo=1)
    mid = noise(size, size, beta=1.4, seed=22, lo=8)
    fine = noise(size, size, beta=0.3, seed=23, lo=60)
    pits = (noise(size, size, beta=0.0, seed=24) > 3.0).astype(np.float32)
    pits = blur(pits, 0.8, wrap=True)
    pits /= pits.max() + 1e-6
    a = np.ones((size, size, 3), np.float32) * base
    a *= (1.0 + 0.07 * mott + 0.045 * mid + 0.035 * fine)[..., None]
    tint = noise(size, size, beta=2.5, seed=25, lo=1)
    a[..., 0] *= 1 + 0.02 * tint
    a[..., 2] *= 1 - 0.02 * tint
    a *= (1.0 - 0.45 * pits)[..., None]
    h = 0.25 * mid + 0.15 * fine - 1.2 * pits
    rough = np.clip(0.72 + 0.06 * mid + 0.05 * fine, 0, 1)
    save("floor_albedo.png", l2s(a))
    save("floor_normal.png", normal_from_height(blur(h, 0.7, wrap=True), 1.4))
    save("floor_rough.png", rough)


def bench_wood(size=1024):
    # varnished hardwood, grain runs along +x (u)
    warpn = noise(size, size, beta=3.0, seed=31, ax=2.5, ay=0.6, lo=1, hi=6)
    rings = np.sin(2 * np.pi * (np.mgrid[0:size, 0:size][0] / size * 26.0 + 0.55 * warpn))
    fib = noise(size, size, beta=1.2, seed=32, ax=1.0, ay=0.03, lo=4)
    pores = noise(size, size, beta=0.2, seed=33, ax=1.0, ay=0.1, lo=30)
    late = smoothstep(0.35, 0.98, rings) * (0.75 + 0.25 * np.clip(fib, -1, 1))
    c_early, c_late = hexcol(150, 82, 42), hexcol(88, 42, 20)
    a = c_early * (1 - late[..., None]) + c_late * late[..., None]
    a *= (1.0 + 0.06 * fib + 0.015 * pores)[..., None]
    wear = smoothstep(0.8, 2.0, noise(size, size, beta=2.4, seed=34, lo=1))
    a = a * (1 - 0.25 * wear[..., None]) + hexcol(120, 82, 56) * 0.25 * wear[..., None]
    h = 0.3 * late + 0.25 * fib + 0.2 * pores
    rough = np.clip(0.34 + 0.10 * wear + 0.04 * fib, 0, 1)
    save("benchwood_albedo.png", l2s(a))
    save("benchwood_normal.png", normal_from_height(blur(h, 0.7, wrap=True), 0.9))
    save("benchwood_rough.png", rough)


def bark(size=1024):
    fib = noise(size, size, beta=1.8, seed=41, ax=0.08, ay=1.0, lo=2)   # vertical fibres
    big = noise(size, size, beta=2.6, seed=42, lo=1)
    lent = noise(size, size, beta=1.0, seed=43, ax=1.0, ay=0.08, lo=20)  # horizontal lenticels
    moss = smoothstep(0.6, 1.6, noise(size, size, beta=2.2, seed=44, lo=2))
    a = np.ones((size, size, 3), np.float32) * hexcol(92, 86, 78)
    a *= (1.0 + 0.10 * fib + 0.12 * big)[..., None]
    a *= (1.0 - 0.18 * smoothstep(1.3, 2.2, lent))[..., None]
    a = a * (1 - moss[..., None]) + hexcol(52, 60, 40) * moss[..., None]
    h = 0.7 * fib + 0.6 * big - 0.4 * smoothstep(1.3, 2.2, lent)
    save("bark_albedo.png", l2s(a))
    save("bark_normal.png", normal_from_height(blur(h, 1.0, wrap=True), 2.0))


def leaves(size=1024):
    """Ficus / banyan leaf clusters on alpha, 2x2 atlas."""
    ss = 2
    big = size * ss
    rgb = np.zeros((big, big, 3), np.float32)
    alpha = np.zeros((big, big), np.float32)
    rng = np.random.default_rng(51)
    half = big // 2
    for cell in range(4):
        ox, oy = (cell % 2) * half, (cell // 2) * half
        cx, cy = ox + half / 2, oy + half / 2
        for _ in range(170):
            ang = rng.uniform(0, 2 * np.pi)
            rad = abs(rng.normal(0, half * 0.2))
            px = cx + np.cos(ang) * rad
            py = cy + np.sin(ang) * rad
            ln = rng.uniform(0.07, 0.11) * half
            wd = ln * rng.uniform(0.38, 0.5)
            rot = rng.uniform(0, 360)
            pts = []
            for t in np.linspace(0, 1, 18):
                pts.append((t * ln - ln / 2, np.sin(np.pi * t) ** 0.8 * wd / 2))
            for t in np.linspace(1, 0, 18):
                pts.append((t * ln - ln / 2, -np.sin(np.pi * t) ** 0.8 * wd / 2))
            pts = np.array(pts)
            cr, sr = np.cos(np.radians(rot)), np.sin(np.radians(rot))
            pts = pts @ np.array([[cr, sr], [-sr, cr]]) + [px, py]
            pts = np.clip(pts, [ox + 2, oy + 2], [ox + half - 3, oy + half - 3]).astype(np.int32)
            shade = rng.uniform(0.55, 1.15)
            col = hexcol(46, 64, 34) * shade
            cv2.fillPoly(rgb, [pts], col.tolist(), lineType=cv2.LINE_AA)
            cv2.fillPoly(alpha, [pts], 1.0, lineType=cv2.LINE_AA)
            # mid vein
            a0 = pts[0]
            a1 = pts[17]
            cv2.line(rgb, tuple(int(v) for v in a0), tuple(int(v) for v in a1), (col * 1.35).tolist(), 1, cv2.LINE_AA)
    rgb = cv2.resize(rgb, (size, size), interpolation=cv2.INTER_AREA)
    alpha = cv2.resize(alpha, (size, size), interpolation=cv2.INTER_AREA)
    # bleed colour into transparent texels to avoid dark fringes when mipmapped
    filled = rgb.copy()
    m = alpha > 0.01
    for _ in range(8):
        b = blur(filled, 2.0)
        wsum = blur(m.astype(np.float32), 2.0)[..., None] + 1e-5
        filled = np.where(m[..., None], filled, b / wsum)
        m = wsum[..., 0] > 0.02
    save("leaves_albedo.png", np.dstack([l2s(filled), alpha]))


def treeline(w=4096, h=512, seed=61, name="treeline.png"):
    """Silhouette of the far bank: lumpy tree crowns + a few lamp posts."""
    rng = np.random.default_rng(seed)
    x = np.arange(w)
    prof = np.zeros(w, np.float32) + h * 0.55
    # crowns
    for _ in range(120):
        cx = rng.uniform(0, w)
        r = rng.uniform(20, 95)
        top = h * rng.uniform(0.15, 0.55)
        d = np.minimum(np.abs(x - cx), w - np.abs(x - cx))
        bump = np.where(d < r, top + (r - np.sqrt(np.maximum(r * r - d * d, 0))) * 0.8, h)
        prof = np.minimum(prof, bump)
    rough = noise(1, w, beta=1.2, seed=seed + 1, lo=20)[0] * 6
    prof = prof + rough
    yy = np.arange(h)[:, None]
    alpha = smoothstep(-1.5, 1.5, yy - prof[None, :])
    # leafy fuzz at the edge
    fuzz = noise(h, w, beta=0.6, seed=seed + 2)
    edge = np.exp(-np.abs(yy - prof[None, :]) / 6.0)
    alpha = np.clip(alpha + edge * 0.6 * fuzz * (yy < prof[None, :] + 8), 0, 1)
    alpha = np.where(yy > prof[None, :] + 8, 1.0, alpha)
    col = np.ones((h, w, 3), np.float32) * hexcol(12, 15, 14)
    col *= (1.0 + 0.25 * noise(h, w, beta=2.0, seed=seed + 3, lo=2))[..., None]
    save(name, np.dstack([l2s(col), alpha]))


def starburst(size=1024):
    """Phone-camera starburst / lens streaks, like the lamps in the photos."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    dx, dy = (xx - c) / c, (yy - c) / c
    r = np.sqrt(dx * dx + dy * dy) + 1e-6
    th = np.arctan2(dy, dx)
    rng = np.random.default_rng(71)
    img = np.exp(-r / 0.035) * 1.0 + np.exp(-r / 0.12) * 0.35 + np.exp(-r / 0.4) * 0.06
    base_angles = [0.28, 0.28 + np.pi]  # the dominant diagonal streak pair seen in photo 5
    for k in range(14):
        if k < 2:
            ang, length, width, amp = base_angles[k], 1.0, 0.004, 0.9
        else:
            ang = rng.uniform(0, 2 * np.pi)
            length, width, amp = rng.uniform(0.15, 0.6), rng.uniform(0.003, 0.012), rng.uniform(0.15, 0.5)
        d = np.angle(np.exp(1j * (th - ang)))
        img += amp * np.exp(-(d / (width / np.maximum(r, 0.02) * 0.05 + width)) ** 2) * np.exp(-r / (0.35 * length))
    img *= smoothstep(1.0, 0.85, r)
    img = img / img.max()
    save("starburst.png", np.clip(img, 0, 1))


def soft_dot(size=64):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / c
    a = np.clip(1 - r, 0, 1) ** 2.2
    save("soft_dot.png", np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a]))


def water_normal(size=1024):
    h = 0.6 * noise(size, size, beta=3.0, seed=81, lo=3, hi=60) + 0.25 * noise(size, size, beta=1.5, seed=82, lo=20)
    save("water_normal.png", normal_from_height(h, 3.0))


if __name__ == "__main__":
    sandstone_atlas()
    beam_atlas()
    granite()
    floor_stone()
    bench_wood()
    bark()
    leaves()
    treeline()
    treeline(seed=62, name="treeline_far.png")
    starburst()
    soft_dot()
    water_normal()

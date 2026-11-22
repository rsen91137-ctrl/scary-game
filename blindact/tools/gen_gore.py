#!/usr/bin/env python3
"""Gore texture variants and blood decals, painted over the existing textures.

  womanc_*  the body as he left it: congested, bleeding, the wire's furrow
  womang_*  what the pianist's panic makes of her: flayed, hollow-eyed
  manm_*    what he becomes once he knows you can see
  decals/blood_*  spatter, pool, drag smear, wall runs, handprint

The MakeHuman skins share one UV layout: the face lies on its side on the
right of the sheet (forehead to -x, chin to +x), the neck tops the torso.
Run from the project root:  python3 tools/gen_gore.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parent.parent
CH = ROOT / "assets/textures/chars"
DEC = ROOT / "assets/textures/decals"

# face landmarks on the 2048 skin sheet (x, y)
EYES = ((1717, 980), (1717, 1125))
NOSE = (1792, 1052)
MOUTH = (1853, 1058)
MID = 1053


def load(name: str) -> np.ndarray:
    return np.asarray(Image.open(CH / f"{name}.png").convert("RGB"), dtype=np.float32) / 255.0


def save(name: str, a: np.ndarray) -> None:
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(CH / f"{name}.png", optimize=True)
    print("wrote", name)


def fbm(h: int, w: int, scale: int, seed: int, octaves: int = 4) -> np.ndarray:
    r = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, scale >> o)
        g = r.random((h // s + 3, w // s + 3)).astype(np.float32)
        out += ndi.zoom(g, s, order=1)[:h, :w] * amp
        tot += amp
        amp *= 0.5
    return out / tot


def sstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blob(h: int, w: int, cx: float, cy: float, rx: float, ry: float, soft: float = 0.5) -> np.ndarray:
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    return 1.0 - sstep(1.0 - soft, 1.0, d)


def strokes(h: int, w: int, paths: list, blur: float = 1.2) -> np.ndarray:
    """paths: [(points, width0, width1)], drawn tapering, softened."""
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    for pts, w0, w1 in paths:
        n = len(pts)
        for i in range(n - 1):
            ww = w0 + (w1 - w0) * i / max(1, n - 2)
            d.line([tuple(pts[i]), tuple(pts[i + 1])], fill=255, width=max(1, int(round(ww))))
            r = ww * 0.5
            d.ellipse([pts[i + 1][0] - r, pts[i + 1][1] - r, pts[i + 1][0] + r, pts[i + 1][1] + r], fill=255)
    if blur > 0:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(im, dtype=np.float32) / 255.0


def run(rng, start, direction, length, wobble=0.35, step=9.0):
    """A wandering trickle from `start` along `direction`."""
    p = np.array(start, np.float32)
    d = np.array(direction, np.float32)
    d /= np.linalg.norm(d)
    side = np.array([-d[1], d[0]])
    pts = [tuple(p)]
    drift = 0.0
    for _ in range(int(length / step)):
        drift = drift * 0.8 + rng.normal(0, wobble)
        p = p + d * step + side * drift * step * 0.5
        pts.append(tuple(p))
    return pts


def blood(img: np.ndarray, m: np.ndarray, wet: float = 1.0) -> np.ndarray:
    """Lay blood where m > 0: bright and thin at the rim, near black where thick."""
    m = np.clip(m, 0, 1)[..., None]
    thin = np.array([0.56, 0.02, 0.03], np.float32)
    thick = np.array([0.20, 0.0, 0.008], np.float32)
    col = thin + (thick - thin) * sstep(0.45, 1.0, m)
    return img * (1 - m * wet) + col * m * wet


def tint(img: np.ndarray, m: np.ndarray, col, k: float) -> np.ndarray:
    m = (np.clip(m, 0, 1) * k)[..., None]
    return img * (1 - m) + img * np.array(col, np.float32) * m


def paint(img: np.ndarray, m: np.ndarray, col, k: float = 1.0) -> np.ndarray:
    m = (np.clip(m, 0, 1) * k)[..., None]
    return img * (1 - m) + np.array(col, np.float32) * m


def dots(h, w, rng, mask, n, r0=1.0, r1=2.6) -> np.ndarray:
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    ys, xs = np.nonzero(mask > 0.35)
    if len(xs) == 0:
        return np.zeros((h, w), np.float32)
    for i in rng.integers(0, len(xs), n):
        r = rng.uniform(r0, r1)
        d.ellipse([xs[i] - r, ys[i] - r, xs[i] + r, ys[i] + r], fill=int(rng.uniform(140, 255)))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(0.6)), dtype=np.float32) / 255.0


def veins(h, w, rng, seeds, n_steps=70, width=3.0) -> np.ndarray:
    paths = []
    for (sx, sy) in seeds:
        stack = [(np.array([sx, sy], np.float32), rng.uniform(0, 6.283), width, n_steps)]
        while stack:
            p, a, ww, left = stack.pop()
            pts = [tuple(p)]
            for _ in range(left):
                a += rng.normal(0, 0.28)
                p = p + np.array([np.cos(a), np.sin(a)], np.float32) * 7.0
                pts.append(tuple(p))
                if ww > 1.3 and rng.random() < 0.05:
                    stack.append((p.copy(), a + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1), ww * 0.65, left // 2))
            paths.append((pts, ww, max(1.0, ww * 0.4)))
    return strokes(h, w, paths, 0.8)


def mouth_inside(img: np.ndarray, seed: int, k: float = 1.0) -> np.ndarray:
    """The mouth cavity and gums (two islands of the sheet): black, wet, bloody."""
    h, w = img.shape[:2]
    m = np.zeros((h, w), np.float32)
    m[1740:2040, 1520:1910] = 1.0
    m[720:940, 0:330] = 1.0
    m = ndi.gaussian_filter(m, 6)
    n = fbm(h, w, 18, seed)
    img = paint(img, m, (0.07, 0.0, 0.004), 0.96 * k)
    return paint(img, m * sstep(0.5, 0.7, n), (0.32, 0.01, 0.02), 0.8 * k)


def neck_line(img: np.ndarray) -> np.ndarray:
    """The ligature mark already painted across the neck (top of the torso)."""
    reg = img[20:260, 480:1080]
    m = ((reg[..., 0] > reg[..., 1] * 1.5) & (reg.sum(-1) < 1.3)).astype(np.float32)
    full = np.zeros(img.shape[:2], np.float32)
    full[20:260, 480:1080] = m
    return full


# ---------------------------------------------------------------- the corpse
def corpse_skin(src: str, dst: str, seed: int) -> None:
    rng = np.random.default_rng(seed)
    img = load(src)
    h, w = img.shape[:2]
    n1 = fbm(h, w, 96, seed + 1)
    face = blob(h, w, 1765, MID, 250, 370, 0.45)
    # a strangled face: dusky, swollen plum above the wire
    img = tint(img, face * (0.65 + 0.5 * n1), (0.86, 0.50, 0.66), 0.75)
    for e in EYES:
        img = tint(img, blob(h, w, e[0], e[1], 85, 70, 0.8), (0.62, 0.30, 0.40), 0.85)
    img = tint(img, blob(h, w, MOUTH[0], MOUTH[1], 62, 80, 0.7), (0.45, 0.33, 0.62), 0.9)
    # petechiae: pinpoint bleeding across lids, cheeks, brow
    img = paint(img, dots(h, w, rng, face * sstep(0.35, 0.7, n1 + 0.15), 2600), (0.40, 0.02, 0.05), 0.85)
    # blood from the nose and the corner of the mouth, run down one cheek
    paths = []
    for sy in (-13, 13):
        for k in range(3):
            paths.append((run(rng, (NOSE[0] + 4, NOSE[1] + sy), (0.45, 1.0), rng.uniform(170, 330)), rng.uniform(9, 15), 3))
    for k in range(5):
        paths.append((run(rng, (MOUTH[0] + rng.uniform(-10, 14), MOUTH[1] + 38), (0.35 + 0.2 * k, 1.0), rng.uniform(200, 420)), rng.uniform(10, 20), 4))
    for k in range(4):
        paths.append((run(rng, (MOUTH[0] + 20, MOUTH[1] + rng.uniform(-30, 30)), (1.0, rng.uniform(-0.2, 0.5)), rng.uniform(90, 170)), rng.uniform(10, 18), 5))
    m = strokes(h, w, paths, 1.6)
    m = np.clip(m * 1.5 + blob(h, w, MOUTH[0] + 6, MOUTH[1], 52, 66, 0.9) * (0.5 + 0.8 * n1), 0, 1)
    img = blood(img, m * sstep(0.25, 0.5, m + 0.25 * n1))
    # the wire: a deep furrow, bruised either side, weeping
    line = neck_line(img)
    wide = ndi.gaussian_filter(ndi.binary_dilation(line > 0, iterations=14).astype(np.float32), 9)
    img = tint(img, wide, (0.55, 0.26, 0.42), 0.9)
    core = ndi.gaussian_filter(ndi.binary_dilation(line > 0, iterations=3).astype(np.float32), 1.5)
    ys, xs = np.nonzero(line > 0)
    paths = []
    if len(xs):
        for i in rng.integers(0, len(xs), 46):
            paths.append((run(rng, (xs[i], ys[i]), (rng.normal(0, 0.25), 1.0), rng.uniform(60, 420), 0.25), rng.uniform(5, 12), 2))
        # her own nails, clawing at it
        for i in rng.integers(0, len(xs), 26):
            a = rng.uniform(-0.5, 0.5)
            p0 = (xs[i] + rng.uniform(-30, 30), ys[i] - rng.uniform(10, 60))
            paths.append(([p0, (p0[0] + np.sin(a) * 70, p0[1] + np.cos(a) * 70)], 3, 1))
    m = np.clip(strokes(h, w, paths, 1.0) + core * 1.4, 0, 1)
    img = blood(img, m)
    # under the jaw on the head island
    jaw = blob(h, w, 1985, MID, 60, 330, 0.9)
    img = tint(img, jaw, (0.55, 0.25, 0.4), 0.8)
    img = blood(img, jaw * sstep(0.5, 0.75, fbm(h, w, 40, seed + 5)) * 0.9)
    # fingertips torn on the wire
    hands = np.zeros((h, w), np.float32)
    hands[1890:2010, 60:1560] = 1.0
    img = blood(img, hands * sstep(0.5, 0.72, fbm(h, w, 30, seed + 8)) * 0.85)
    save(dst, mouth_inside(img, seed + 9, 0.7))


# ------------------------------------------------- what panic makes of a face
def horror_skin(src: str, dst: str, seed: int, pale=(0.80, 0.83, 0.82), flay_side: int = -1) -> None:
    rng = np.random.default_rng(seed)
    img = load(src)
    h, w = img.shape[:2]
    lum = img.mean(-1, keepdims=True)
    n1 = fbm(h, w, 128, seed + 1)
    n2 = fbm(h, w, 24, seed + 2)
    # drained, waxy, mottled
    img = (img * 0.12 + lum * 0.88) * np.array(pale, np.float32) * 1.06
    img = tint(img, sstep(0.45, 0.75, n1), (0.62, 0.70, 0.74), 0.7)
    # black veins crawling out from the eyes and mouth, and over the whole body
    seeds = [(e[0] + rng.normal(0, 40), e[1] + rng.normal(0, 40)) for e in EYES for _ in range(9)]
    seeds += [(MOUTH[0] + rng.normal(0, 50), MOUTH[1] + rng.normal(0, 70)) for _ in range(10)]
    seeds += [(rng.uniform(1560, 2000), rng.uniform(700, 1400)) for _ in range(14)]
    seeds += [(rng.uniform(100, 1250), rng.uniform(60, 1900)) for _ in range(110)]
    v = veins(h, w, rng, seeds)
    img = paint(img, v, (0.06, 0.07, 0.11), 0.82)
    # flayed: the skin gone from brow to cheek on one side, wet muscle under it
    fy = MID + flay_side * 175
    fm = blob(h, w, 1670, fy, 150, 170, 0.6) + blob(h, w, 1800, fy + flay_side * 40, 90, 110, 0.6) * 0.9
    fm = sstep(0.42, 0.56, fm * (0.55 + 0.9 * n2))
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    fibre = 0.5 + 0.5 * np.sin(y * 0.33 + x * 0.05 + n2 * 14.0)
    meat = np.array([0.50, 0.035, 0.045], np.float32) * (0.45 + 0.75 * fibre[..., None])
    meat = meat + np.array([0.5, 0.42, 0.2], np.float32) * sstep(0.74, 0.8, fbm(h, w, 10, seed + 3))[..., None] * 0.5
    edge = np.clip(ndi.gaussian_filter(fm, 5) - fm * 0.6, 0, 1) * (fm < 0.5)
    img = paint(img, edge * 2.2, (0.30, 0.02, 0.03), 0.9)
    f3 = fm[..., None]
    img = img * (1 - f3) + meat * f3
    # the eyes: hollows, black to the bone, bleeding
    for e in EYES:
        img = paint(img, blob(h, w, e[0], e[1], 120, 96, 0.75), (0.30, 0.015, 0.02), 0.85)
        img = paint(img, blob(h, w, e[0], e[1], 84, 62, 0.6), (0.015, 0.0, 0.0), 0.97)
    paths = []
    for e in EYES:
        for k in range(7):
            paths.append((run(rng, (e[0] + 30, e[1] + rng.uniform(-34, 34)), (1.0, rng.normal(0, 0.12)), rng.uniform(150, 360), 0.3), rng.uniform(9, 17), 3))
    # the mouth cut back to the ears, lips gone
    cut = []
    for s in (-1, 1):
        cut.append(([(MOUTH[0], MOUTH[1])] + [(MOUTH[0] - 6 * t - 0.9 * t * t, MOUTH[1] + s * (40 + 34 * t)) for t in range(0, 8)], 44, 12))
    gash = strokes(h, w, cut, 2.0)
    gash = sstep(0.3, 0.55, gash * (0.6 + 0.8 * n2))
    rim = np.clip(ndi.gaussian_filter(gash, 9) * 1.8 - gash, 0, 1)
    img = paint(img, rim, (0.45, 0.02, 0.03), 0.95)
    img = paint(img, gash, (0.03, 0.0, 0.0), 0.97)
    img = paint(img, blob(h, w, MOUTH[0], MOUTH[1], 58, 84, 0.5), (0.04, 0.0, 0.0), 0.95)
    for k in range(16):
        paths.append((run(rng, (MOUTH[0] + 24, MOUTH[1] + rng.uniform(-150, 150)), (1.0, rng.normal(0, 0.2)), rng.uniform(80, 240), 0.3), rng.uniform(10, 22), 4))
    m = strokes(h, w, paths, 1.5)
    chin = blob(h, w, 1935, MID, 95, 250, 0.9) * sstep(0.3, 0.6, n2 + 0.2)
    img = blood(img, np.clip(m * 1.4 + chin, 0, 1))
    # down the throat and chest
    paths = []
    for k in range(70):
        paths.append((run(rng, (rng.uniform(560, 980), rng.uniform(60, 200)), (rng.normal(0, 0.2), 1.0), rng.uniform(120, 900), 0.3), rng.uniform(6, 18), 2))
    m = strokes(h, w, paths, 1.4)
    throat = np.zeros((h, w), np.float32)
    throat[30:330, 500:1050] = 1.0
    throat = ndi.gaussian_filter(throat, 40) * sstep(0.35, 0.6, n1 + 0.25 * n2)
    img = blood(img, np.clip(m + throat, 0, 1))
    # spatter everywhere, nails and hands soaked
    img = blood(img, dots(h, w, rng, np.ones((h, w), np.float32), 5200, 1.5, 6.5) * 0.95)
    hands = np.zeros((h, w), np.float32)
    hands[1640:2010, 40:1580] = 1.0
    img = blood(img, ndi.gaussian_filter(hands, 30) * sstep(0.4, 0.62, fbm(h, w, 48, seed + 9)))
    save(dst, mouth_inside(img, seed + 10))


# ------------------------------------------------------------------- eyeballs
def eyes(src: str, dst: str, mode: str, seed: int) -> None:
    im = Image.open(CH / f"{src}.png").convert("RGBA")
    a = np.asarray(im, dtype=np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3:]
    h, w = rgb.shape[:2]
    s = w / 1024.0
    n = fbm(h, w, 40, seed)
    rng = np.random.default_rng(seed)
    for (cx, cy) in ((723 * s, 301 * s), (301 * s, 717 * s)):
        y, x = np.mgrid[0:h, 0:w].astype(np.float32)
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / s
        ball = 1.0 - sstep(270, 300, d)
        iris = 1.0 - sstep(108, 120, d)
        if mode == "corpse":
            # burst vessels flooding the white, the pupil blown
            hem = ball * (1 - iris) * sstep(0.3, 0.6, n + 0.12)
            rgb = paint(rgb, hem, (0.50, 0.02, 0.03), 0.92)
            rgb = paint(rgb, ball * (1 - iris), (0.6, 0.25, 0.25), 0.3)
            rgb = paint(rgb, iris, (0.42, 0.44, 0.46), 0.45)
            rgb = paint(rgb, 1.0 - sstep(62, 70, d), (0.0, 0.0, 0.0), 1.0)
        else:
            # a black ball, a milk-white iris, a pinprick for a pupil
            rgb = paint(rgb, ball * (1 - iris), (0.05, 0.0, 0.0), 0.96)
            rgb = paint(rgb, ball * (1 - iris) * sstep(0.5, 0.7, n), (0.35, 0.01, 0.02), 0.8)
            ray = 0.82 + 0.18 * np.sin(np.arctan2(y - cy, x - cx) * 46.0 + n * 8.0)
            rgb = rgb * (1 - iris[..., None]) + (np.array([0.86, 0.88, 0.84], np.float32) * ray[..., None]) * iris[..., None]
            rgb = paint(rgb, sstep(96, 118, d) * iris, (0.25, 0.02, 0.03), 0.8)
            rgb = paint(rgb, 1.0 - sstep(9, 14, d), (0.0, 0.0, 0.0), 1.0)
    out = np.concatenate([rgb, alpha], -1)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(CH / f"{dst}.png", optimize=True)
    print("wrote", dst)


def soak(src: str, dst: str, seed: int, cover: float, base=None) -> None:
    img = load(src)
    h, w = img.shape[:2]
    if base is not None:
        lum = img.mean(-1, keepdims=True)
        img = (img * 0.25 + lum * 0.75) * np.array(base, np.float32) * 1.9
    n = fbm(h, w, 160, seed) * 0.7 + fbm(h, w, 28, seed + 1) * 0.3
    m = sstep(1.0 - cover - 0.08, 1.0 - cover + 0.08, n)
    img = blood(img, m * 0.93)
    rng = np.random.default_rng(seed)
    img = blood(img, dots(h, w, rng, np.ones((h, w), np.float32), 2500, 2, 9) * 0.9)
    save(dst, img)


def teeth(src: str, dst: str) -> None:
    img = load(src)
    h, w = img.shape[:2]
    n = fbm(h, w, 20, 3)
    img = img * np.array([0.5, 0.26, 0.2], np.float32)
    save(dst, blood(img, sstep(0.4, 0.58, n) * 0.9))


def tongue(src: str, dst: str) -> None:
    img = load(src)
    h, w = img.shape[:2]
    img = img * np.array([0.3, 0.05, 0.06], np.float32)
    save(dst, blood(img, sstep(0.45, 0.62, fbm(h, w, 16, 5)) * 0.8))


# -------------------------------------------------------------------- decals
def save_decal(name: str, m: np.ndarray, alpha_max: float = 0.97) -> None:
    m = np.clip(m, 0, 1)
    thin = np.array([0.62, 0.02, 0.03], np.float32)
    thick = np.array([0.24, 0.0, 0.01], np.float32)
    rgb = thin + (thick - thin) * sstep(0.4, 1.0, m)[..., None]
    a = sstep(0.04, 0.3, m) * alpha_max
    out = np.concatenate([np.broadcast_to(rgb, m.shape + (3,)), a[..., None]], -1)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(DEC / f"{name}.png", optimize=True)
    print("wrote decal", name)


def decals() -> None:
    S = 512
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    c = S / 2
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    ang = np.arctan2(y - c, x - c)
    # impact spatter: a wet core, elongated drops flung outward
    for k in (1, 2):
        rng = np.random.default_rng(40 + k)
        n = fbm(S, S, 64, 50 + k)
        core = sstep(0.42, 0.62, (1.0 - r * 2.3) + n * 0.9)
        im = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(im)
        for _ in range(260):
            a = rng.uniform(0, 6.283)
            rr = rng.uniform(0.12, 0.98) ** 0.8 * c
            ln = rng.uniform(2, 30) * (1.2 - rr / c)
            wd = rng.uniform(1.5, 7) * (1.25 - rr / c)
            p0 = (c + np.cos(a) * rr, c + np.sin(a) * rr)
            p1 = (c + np.cos(a) * (rr + ln), c + np.sin(a) * (rr + ln))
            d.line([p0, p1], fill=255, width=max(1, int(wd)))
            d.ellipse([p1[0] - wd, p1[1] - wd, p1[0] + wd, p1[1] + wd], fill=255)
        sp = np.asarray(im.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0
        save_decal(f"blood_splat{k}", np.clip(core + sp * (0.6 + 0.4 * n), 0, 1))
    # a pool: thick, lobed, creeping
    n = fbm(S, S, 128, 61, 5)
    pool = sstep(0.36, 0.5, (1.0 - r * 1.25) * 0.75 + n * 0.5)
    save_decal("blood_pool", pool * (0.72 + 0.28 * sstep(0.2, 0.9, 1.0 - r)), 0.985)
    # a drag smear along x: bristled, breaking up, heel gouges
    hsh = fbm(S, S, 6, 62, 2)
    rows = ndi.gaussian_filter1d(np.random.default_rng(63).random(S).astype(np.float32), 2.0)
    rows = (rows - rows.min()) / (rows.max() - rows.min())
    band = sstep(0.0, 0.2, 1.0 - np.abs(y - c) / (c * 0.86))
    smear = band * sstep(0.3, 0.62, rows[:, None] * 0.75 + fbm(S, S, 96, 64) * 0.55 + hsh * 0.15)
    ends = sstep(0.0, 0.2, x / S) * sstep(0.0, 0.2, 1.0 - x / S)
    save_decal("blood_drag", smear * ends * (0.5 + 0.5 * fbm(S, S, 200, 65)), 0.93)
    # runs down a wall: a slap of blood at the top, long drips
    rng = np.random.default_rng(66)
    win = sstep(0.0, 0.16, x / S) * sstep(0.0, 0.16, 1.0 - x / S) * sstep(0.0, 0.08, y / S)
    top = sstep(0.4, 0.58, (1.0 - np.abs(y - 70) / 90.0) * 0.8 * win + fbm(S, S, 48, 67) * 0.6 * win) * sstep(200.0, 150.0, y)
    paths = []
    for _ in range(13):
        x0 = rng.uniform(40, S - 40)
        paths.append((run(rng, (x0, rng.uniform(50, 110)), (0.0, 1.0), rng.uniform(90, 400), 0.12, 7.0), rng.uniform(5, 12), rng.uniform(4, 9)))
    save_decal("blood_drip", np.clip(top + strokes(S, S, paths, 1.0), 0, 1))
    # a hand dragged down a wall
    hp = np.asarray(Image.open(DEC / "handprint.png").convert("RGBA").resize((S, S)), np.float32) / 255.0
    ha = hp[..., 3]
    drag = np.maximum.accumulate(ha * (0.55 + 0.45 * fbm(S, S, 5, 68, 2)), axis=0) * sstep(1.0, 0.25, y / S)
    save_decal("blood_hand", np.clip(ha * 1.3 + drag * 0.55, 0, 1))


# ------------------------------------------------- him, at the door: her blood
def bloodied_man(src: str, dst: str, seed: int) -> None:
    """Spattered from the front: face, neck, hands. Still a man, still smiling."""
    rng = np.random.default_rng(seed)
    img = load(src)
    h, w = img.shape[:2]
    n1 = fbm(h, w, 64, seed + 1)
    face = blob(h, w, 1760, MID, 250, 360, 0.5)
    # a fine spray over the face (cast-off from the wire), heavier one side
    side = blob(h, w, 1760, MID + 110, 220, 260, 0.6)
    img = blood(img, dots(h, w, rng, face, 3400, 1.0, 4.5) * (0.6 + 0.4 * side))
    img = blood(img, dots(h, w, rng, side, 900, 3.0, 9.0) * 0.95)
    # wiped with the back of a hand: a smear across cheek and mouth
    smear = strokes(h, w, [([(1700, MID - 160), (1760, MID - 40), (1830, MID + 80), (1860, MID + 200)], 70, 40)], 9.0)
    img = blood(img, smear * sstep(0.35, 0.6, n1 + 0.2) * 0.85)
    # runs from the hairline and down the neck
    paths = []
    for k in range(14):
        paths.append((run(rng, (rng.uniform(1560, 1640), MID + rng.uniform(-260, 260)), (1.0, rng.normal(0, 0.15)), rng.uniform(80, 260), 0.25), rng.uniform(6, 13), 2))
    for k in range(22):
        paths.append((run(rng, (rng.uniform(560, 980), rng.uniform(40, 120)), (rng.normal(0, 0.2), 1.0), rng.uniform(60, 300), 0.3), rng.uniform(5, 12), 2))
    img = blood(img, strokes(h, w, paths, 1.2))
    # hands: soaked to the wrist
    hands = np.zeros((h, w), np.float32)
    hands[1620:2040, 30:1600] = 1.0
    img = blood(img, ndi.gaussian_filter(hands, 25) * sstep(0.35, 0.6, fbm(h, w, 40, seed + 4)) * 0.95)
    save(dst, img)


def bloodied_cloth(src: str, dst: str, seed: int) -> None:
    """Her blood on his shirt: soaked at the front and the cuffs, sprayed in
    arcs across it, smeared where he wiped his hands."""
    img = load(src)
    h, w = img.shape[:2]
    rng = np.random.default_rng(seed)
    n = fbm(h, w, 140, seed) * 0.7 + fbm(h, w, 24, seed + 1) * 0.3
    img = blood(img, sstep(0.6, 0.74, n) * 0.95)
    # cast-off: arcs of elongated drops
    paths = []
    for k in range(18):
        a0 = rng.uniform(0, 6.283)
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(120, 420)
        for j in range(rng.integers(6, 16)):
            a = a0 + j * rng.uniform(0.05, 0.1)
            x, y = cx + np.cos(a) * r, cy + np.sin(a) * r
            ln = rng.uniform(8, 30)
            paths.append(([(x, y), (x + np.cos(a + 1.57) * ln, y + np.sin(a + 1.57) * ln)], rng.uniform(5, 11), 2))
    img = blood(img, strokes(h, w, paths, 1.0) * 0.95)
    # smears: dragged hand-widths
    sm = []
    for k in range(9):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        sm.append(([(x, y), (x + rng.uniform(-160, 160), y + rng.uniform(60, 260))], rng.uniform(40, 80), rng.uniform(10, 30)))
    img = blood(img, strokes(h, w, sm, 6.0) * sstep(0.3, 0.6, fbm(h, w, 30, seed + 3) + 0.2) * 0.8)
    img = blood(img, dots(h, w, rng, np.ones((h, w), np.float32), 900, 1.0, 4.0) * 0.85)
    save(dst, img)


def photo_dead() -> None:
    """Her photograph, when she looks back: the eyes gone, blood down the face."""
    im = np.asarray(Image.open(DEC / "photo_her.png").convert("RGBA"), np.float32) / 255.0
    rgb, a = im[..., :3], im[..., 3:]
    h, w = rgb.shape[:2]
    rng = np.random.default_rng(71)
    for (ex, ey) in ((236, 132), (274, 132)):
        rgb = paint(rgb, blob(h, w, ex, ey, 11, 8, 0.6), (0.0, 0.0, 0.0), 1.0)
    paths = []
    for (ex, ey) in ((236, 138), (274, 138)):
        for k in range(3):
            paths.append((run(rng, (ex + rng.uniform(-3, 3), ey), (rng.normal(0, 0.08), 1.0), rng.uniform(60, 190), 0.18, 4.0), rng.uniform(3, 5), 1.5))
    rgb = blood(rgb, strokes(h, w, paths, 0.8))
    rgb = paint(rgb, blob(h, w, 255, 166, 9, 14, 0.6), (0.02, 0.0, 0.0), 0.95)
    out = np.concatenate([rgb, a], -1)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(DEC / "photo_her_dead.png", optimize=True)
    print("wrote decal photo_her_dead")


def meat() -> None:
    """Roasted flesh: a browned crust, fat in streaks, glistening."""
    out = ROOT / "assets/textures/props"
    out.mkdir(parents=True, exist_ok=True)
    S = 512
    n1 = fbm(S, S, 64, 81)
    n2 = fbm(S, S, 12, 82)
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    streak = sstep(0.62, 0.72, 0.5 + 0.5 * np.sin(y * 0.05 + n1 * 9.0))
    crust = np.array([0.36, 0.16, 0.07], np.float32) * (0.55 + 0.6 * n2[..., None])
    char = np.array([0.08, 0.035, 0.02], np.float32)
    fat = np.array([0.82, 0.68, 0.48], np.float32)
    raw = np.array([0.55, 0.14, 0.12], np.float32)
    img = crust * (1 - sstep(0.62, 0.8, n1)[..., None]) + char * sstep(0.62, 0.8, n1)[..., None]
    img = img * (1 - streak[..., None] * 0.7) + fat * streak[..., None] * 0.7
    img = img * (1 - sstep(0.7, 0.85, n2)[..., None] * 0.5) + raw * sstep(0.7, 0.85, n2)[..., None] * 0.5
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out / "meat_albedo.png", optimize=True)
    print("wrote props/meat_albedo")


def main() -> None:
    import sys
    if "--decals" in sys.argv:
        decals()
        return
    if "--meat" in sys.argv:
        meat()
        return
    if "--photo" in sys.argv:
        photo_dead()
        return
    if "--manb" in sys.argv:
        bloodied_man("man_skin_albedo", "manb_skin_albedo", 41)
        bloodied_cloth("man_cloth_albedo", "manb_cloth_albedo", 42)
        return
    corpse_skin("woman_skin_albedo", "womanc_skin_albedo", 11)
    eyes("woman_eyes_albedo", "womanc_eyes_albedo", "corpse", 12)
    soak("woman_cloth_albedo", "womanc_cloth_albedo", 13, 0.26, base=(0.80, 0.78, 0.70))
    horror_skin("woman_skin_albedo", "womang_skin_albedo", 21)
    eyes("woman_eyes_albedo", "womang_eyes_albedo", "horror", 22)
    soak("woman_cloth_albedo", "womang_cloth_albedo", 23, 0.5, base=(0.62, 0.62, 0.58))
    teeth("woman_teeth_albedo", "womang_teeth_albedo")
    tongue("woman_tongue_albedo", "womang_tongue_albedo")
    tongue("man_tongue_albedo", "manm_tongue_albedo")
    tongue("woman_tongue_albedo", "womanc_tongue_albedo")
    horror_skin("man_skin_albedo", "manm_skin_albedo", 31, pale=(0.66, 0.68, 0.72), flay_side=1)
    eyes("man_eyes_albedo", "manm_eyes_albedo", "horror", 32)
    teeth("man_teeth_albedo", "manm_teeth_albedo")
    bloodied_man("man_skin_albedo", "manb_skin_albedo", 41)
    bloodied_cloth("man_cloth_albedo", "manb_cloth_albedo", 42)
    decals()
    photo_dead()
    meat()


if __name__ == "__main__":
    main()

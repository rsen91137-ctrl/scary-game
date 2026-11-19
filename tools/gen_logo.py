#!/usr/bin/env python3
"""Design the CORRIDOR logotype.

Cinzel capitals, widely tracked, slightly misaligned and eroded like old
stencilled stone. The "I" is blood: a blood-red letter with ragged wet edges,
a darker coagulated rim, wet highlights, spatter droplets (elongated away
from the impact, some landing on the neighbouring letters) and drips running
down from it.

Writes:
  assets/ui/logo_mask.png    RGB masks for the in-game shader
                             R = bone letters, G = blood coverage, B = blood shading
  assets/ui/logo_preview.png composited preview (for docs / store art)
  icon.png                   window/app icon (the blood "I")

Usage: python3 tools/gen_logo.py
"""
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "art" / "fonts" / "Cinzel-Regular.ttf"
OUT = ROOT / "assets" / "ui"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 3200, 1000
CAP = 360            # font size in px
TRACK = 0.30         # extra tracking (em)
rng = np.random.default_rng(1918)

BONE = np.array([0.86, 0.83, 0.79])
BLOOD_DARK = np.array([0.13, 0.0, 0.004])
BLOOD = np.array([0.6, 0.025, 0.02])


def noise(h, w, scale, seed):
    r = np.random.default_rng(seed)
    small = r.random((max(2, h // scale), max(2, w // scale))).astype(np.float32)
    return cv2.resize(small, (w, h), interpolation=cv2.INTER_CUBIC)


def glyph(font, ch, x, baseline, asc, rot=0.0, dy=0.0):
    layer = Image.new("L", (W, H), 0)
    ImageDraw.Draw(layer).text((x, baseline - asc + dy), ch, font=font, fill=255)
    arr = np.asarray(layer).astype(np.float32) / 255.0
    if rot:
        cx = x + font.getlength(ch) / 2
        m = cv2.getRotationMatrix2D((cx, baseline - CAP * 0.35), rot, 1.0)
        arr = cv2.warpAffine(arr, m, (W, H), flags=cv2.INTER_CUBIC)
    return arr


def layout():
    font = ImageFont.truetype(str(FONT), CAP)
    word = "CORRIDOR"
    adv = [font.getlength(ch) for ch in word]
    total = sum(adv) + TRACK * CAP * (len(word) - 1)
    x = (W - total) / 2
    asc, _ = font.getmetrics()
    baseline = H * 0.42 + CAP * 0.36
    bone = np.zeros((H, W), np.float32)
    i_mask = None
    i_box = None
    for ch, a in zip(word, adv):
        if ch == "I":
            i_mask = glyph(font, ch, x, baseline, asc, rot=rng.uniform(-1.2, 1.2), dy=rng.uniform(-4, 4))
            i_box = (x, x + a)
        else:
            bone = np.maximum(bone, glyph(font, ch, x, baseline, asc, rot=rng.uniform(-0.6, 0.6), dy=rng.uniform(-6, 6)))
        x += a + TRACK * CAP
    return bone, i_mask, i_box, baseline


def erode(mask):
    h, w = mask.shape
    soft = cv2.GaussianBlur(mask, (0, 0), 2.2)
    n1 = noise(h, w, 3, 1) * 0.6 + noise(h, w, 9, 2) * 0.4
    n_fine = noise(h, w, 2, 11)
    edge = np.clip((soft - 0.34 - (n1 - 0.5) * 0.75 - (n_fine - 0.5) * 0.25) * 6.0, 0, 1)
    chips = (noise(h, w, 14, 12) > 0.78).astype(np.float32) * (soft < 0.8)
    edge *= 1.0 - cv2.GaussianBlur(chips, (0, 0), 1.2)
    out = np.minimum(mask, edge)
    out = np.where(soft > 0.75, np.minimum(mask, 0.4 + 0.6 * edge + 0.6), out)
    out = np.clip(out, 0, 1)
    pits = (noise(h, w, 2, 3) > 0.86).astype(np.float32) * (noise(h, w, 55, 4) > 0.62)
    out *= 1.0 - np.clip(cv2.GaussianBlur(pits, (0, 0), 1.0) * 1.6, 0, 0.85)
    scr = np.zeros((h, w), np.float32)
    for _ in range(26):
        sx = rng.integers(0, w)
        y0 = rng.integers(0, h // 2)
        y1 = y0 + rng.integers(h // 4, h)
        cv2.line(scr, (int(sx), int(y0)), (int(sx + rng.integers(-12, 12)), int(y1)), 1.0, int(rng.integers(1, 3)))
    out *= 1.0 - 0.75 * cv2.GaussianBlur(scr, (0, 0), 0.6)
    out *= 0.72 + 0.28 * noise(h, w, 60, 5)
    stain = noise(h, w, 25, 13) * np.clip(noise(h, w, 400, 14) - 0.35, 0, 1) * 2.0
    stain = cv2.resize(cv2.resize(stain, (w, h // 8)), (w, h), interpolation=cv2.INTER_CUBIC)
    out *= 1.0 - 0.35 * np.clip(stain, 0, 1)
    return np.clip(out, 0, 1)


# ----------------------------------------------------------------------------
# blood
# ----------------------------------------------------------------------------
def blood_letter(i_mask):
    """Bolder than the other letters, with ragged, slightly swollen wet edges."""
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (17, 13))
    i_mask = cv2.dilate(i_mask, k)
    soft = cv2.GaussianBlur(i_mask, (0, 0), 3.0)
    n = noise(H, W, 5, 21) * 0.55 + noise(H, W, 17, 22) * 0.45
    m = np.clip((soft - 0.28 - (n - 0.5) * 0.55) * 7.0, 0, 1)
    return m


def drop(canvas, cx, cy, r, ang=0.0, elong=1.0, tail=False):
    """Antialiased droplet; elongated along `ang` with an optional tail dot."""
    ax = max(1, int(round(r * elong)))
    ay = max(1, int(round(r)))
    cv2.ellipse(canvas, (int(cx * 4), int(cy * 4)), (ax * 4, ay * 4), np.degrees(ang), 0, 360, 1.0, -1, cv2.LINE_AA, 2)
    if tail:
        d = r * elong * rng.uniform(1.4, 2.4)
        tx, ty = cx + np.cos(ang) * d, cy + np.sin(ang) * d
        tr = max(1.0, r * rng.uniform(0.25, 0.45))
        cv2.circle(canvas, (int(tx * 4), int(ty * 4)), int(tr * 4), 1.0, -1, cv2.LINE_AA, 2)


def spatter(i_box, baseline):
    canvas = np.zeros((H, W), np.float32)
    x0, x1 = i_box
    cx = (x0 + x1) / 2
    top = baseline - CAP * 0.72
    cy = (baseline + top) / 2
    # impact slightly above the middle of the letter, spray mostly sideways
    main_dir = -0.42  # flung up and to the right
    for k in range(170):
        size_class = rng.random()
        if size_class < 0.74:
            r = rng.uniform(1.0, 3.6)
            dist = rng.exponential(150) + 45
        elif size_class < 0.95:
            r = rng.uniform(3.6, 7.5)
            dist = rng.exponential(85) + 40
        else:
            r = rng.uniform(7.5, 13.0)
            dist = rng.exponential(35) + 35
        if rng.random() < 0.72:
            ang = main_dir + rng.normal(0, 0.75)
        else:
            ang = rng.uniform(-np.pi, np.pi)
        # flatten vertically so the spray stays near the word
        dx, dy = np.cos(ang) * dist * 1.25, np.sin(ang) * dist * 0.62
        px, py = cx + dx, cy + dy
        elong = 1.0 + min(2.6, dist / 110.0) * rng.uniform(0.4, 1.0)
        drop(canvas, px, py, r, np.arctan2(dy, dx), elong, tail=(dist > 90 and rng.random() < 0.45))
    # fine mist
    for k in range(420):
        ang = main_dir + rng.normal(0, 1.0) if rng.random() < 0.7 else rng.uniform(-np.pi, np.pi)
        dist = rng.exponential(170) + 30
        px, py = cx + np.cos(ang) * dist * 1.3, cy + np.sin(ang) * dist * 0.7
        cv2.circle(canvas, (int(px * 4), int(py * 4)), int(rng.uniform(0.5, 1.4) * 4), 1.0, -1, cv2.LINE_AA, 2)
    return canvas


def drips(i_box, baseline):
    canvas = np.zeros((H, W), np.float32)
    x0, x1 = i_box
    stem_l = x0 + (x1 - x0) * 0.22
    stem_r = x1 - (x1 - x0) * 0.22
    starts = [(stem_l + 4, baseline - 6, 1.0), ((stem_l + stem_r) / 2 + 3, baseline - 4, 1.45), (stem_r - 2, baseline - 8, 0.55)]
    for sx, sy, scale in starts:
        length = rng.uniform(70, 110) * scale
        wdt = rng.uniform(9.0, 13.0) * (0.75 + 0.35 * scale)
        steps = 40
        for i in range(steps + 1):
            t = i / steps
            y = sy + t * length
            x = sx + np.sin(t * 3.0 + sx) * 1.5
            w = wdt * (1.0 - 0.45 * t) * (0.9 + 0.2 * np.sin(t * 9.0))
            cv2.circle(canvas, (int(x * 4), int(y * 4)), max(1, int(w * 0.5 * 4)), 1.0, -1, cv2.LINE_AA, 2)
        # the heavy bead at the end
        cv2.circle(canvas, (int(sx * 4), int((sy + length + wdt * 0.4) * 4)), int(wdt * 0.85 * 4), 1.0, -1, cv2.LINE_AA, 2)
    return canvas


def shade(cover):
    """B channel: dark coagulated rims, lighter wet pools, specular glints."""
    binm = (cover > 0.5).astype(np.uint8)
    dist = cv2.distanceTransform(binm, cv2.DIST_L2, 5).astype(np.float32)
    rim = np.exp(-dist / 3.0)
    body = 0.55 + 0.25 * (noise(H, W, 9, 31) - 0.5) + 0.12 * np.clip(dist / 14.0, 0, 1)
    sh = body * (1.0 - 0.75 * rim)
    # vertical smear streaks inside the letter
    streak = cv2.resize(noise(H // 6, W, 3, 32), (W, H), interpolation=cv2.INTER_CUBIC)
    sh *= 0.85 + 0.3 * (streak - 0.5)
    # glints: small bright spots up-left of the thicker areas
    glint = (dist > 7.0).astype(np.float32) * (noise(H, W, 7, 33) > 0.93)
    glint = np.roll(np.roll(glint, -2, 0), -2, 1)
    glint = cv2.GaussianBlur(glint, (0, 0), 1.6)
    sh = np.clip(sh + glint * 0.45, 0, 1)
    return sh


def main():
    bone, i_mask, i_box, baseline = layout()
    bone = erode(bone)
    # faint hairline under the word
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ly = baseline + CAP * 0.3
    hair = np.exp(-np.abs(yy - ly) / 1.1) * np.exp(-np.abs(xx - W / 2) / 620.0) * 0.35
    bone = np.maximum(bone, hair)

    letter = blood_letter(i_mask)
    spat = spatter(i_box, baseline)
    drp = drips(i_box, baseline)
    cover = np.clip(np.maximum.reduce([letter, spat, drp]), 0, 1)
    sh = shade(cover)

    rgb = np.dstack([bone, cover, sh])
    any_ = np.maximum(bone, cover)
    ys, xs = np.where(any_ > 0.02)
    y0, y1 = max(0, ys.min() - 30), min(H, ys.max() + 30)
    x0, x1 = max(0, xs.min() - 30), min(W, xs.max() + 30)
    rgb = rgb[y0:y1, x0:x1]
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(OUT / "logo_mask.png", optimize=True)

    # preview composite
    b, c, s = rgb[..., 0:1], rgb[..., 1:2], rgb[..., 2:3]
    bg = np.array([0.02, 0.02, 0.025])
    blood = BLOOD_DARK + (BLOOD - BLOOD_DARK) * np.clip(s * 1.3, 0, 1) + np.clip(s - 0.8, 0, 1) * 2.0 * np.array([0.9, 0.5, 0.45])
    col = bg + b * (BONE - bg)
    col = col * (1 - c) + blood * c
    Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(OUT / "logo_preview.png", optimize=True)
    print("logo", rgb.shape)

    # icon: the blood I alone on near-black
    ix0 = int((i_box[0] + i_box[1]) / 2 - x0)
    iy = int(baseline - CAP * 0.36 - y0)
    half = int(CAP * 0.78)
    crop = col[max(0, iy - half):iy + half, max(0, ix0 - half):ix0 + half]
    icon = cv2.resize(crop.astype(np.float32), (256, 256), interpolation=cv2.INTER_AREA)
    Image.fromarray((np.clip(icon, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(ROOT / "icon.png")


if __name__ == "__main__":
    main()

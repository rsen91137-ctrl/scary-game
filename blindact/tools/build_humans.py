#!/usr/bin/env python3
"""Build the two people of the night from the MakeHuman CC0 data in
art/makehuman, in headless Blender (pip package `bpy`).

  man    the husband: heavy-set, about fifty, white shirt with the sleeves
         rolled up (blood on the cuffs and the front), dark trousers, black
         shoes, stubble, short dark hair
  woman  his wife, dead: slim, thirty-ish, a dark slip dress, barefoot, pale
         with the lividity of the dead, a thin ligature mark round her neck
         (a piano string), long dark hair, eyes half open, mouth slack

Outputs
  assets/models/man.glb, assets/models/woman.glb       skinned (MakeHuman
      default skeleton, 163 bones, A-pose rest), facing +Z, Y up, metres
  assets/textures/chars/<who>_albedo.png / _normal.png / _rough.png
  assets/textures/chars/hair_strands.png, eye_brown.png
Usage: python3 tools/build_humans.py [man|woman]
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texlib as T  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MH = ROOT / "art" / "makehuman"
OUT_M = ROOT / "assets" / "models"
OUT_T = ROOT / "assets" / "textures" / "chars"
OUT_M.mkdir(parents=True, exist_ok=True)
OUT_T.mkdir(parents=True, exist_ok=True)
SCALE = 0.1                    # MakeHuman decimetres -> metres
TEX = 2048

SPEC = {
    "man": {
        "targets": [("universal-male-young-averagemuscle-averageweight", 0.42),
                    ("universal-male-young-averagemuscle-maxweight", 0.2),
                    ("universal-male-old-averagemuscle-averageweight", 0.38),
                    ("caucasian-male-young", 0.6), ("caucasian-male-old", 0.4),
                    ("mouth-corner-puller", 0.12)],
    },
    "woman": {
        "targets": [("universal-female-young-averagemuscle-averageweight", 0.6),
                    ("universal-female-young-averagemuscle-minweight", 0.4),
                    ("caucasian-female-young", 1.0),
                    ("mouth-open", 0.32), ("eye-left-closure", 0.55), ("eye-right-closure", 0.6)],
    },
}


# ---------------------------------------------------------------------------
# MakeHuman data
# ---------------------------------------------------------------------------
def load_obj(path: Path):
    V, VT, faces = [], [], []
    group = None
    for line in open(path):
        if line.startswith("v "):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("vt "):
            VT.append([float(x) for x in line.split()[1:3]])
        elif line.startswith("g "):
            group = line.split()[1]
        elif line.startswith("f "):
            vids, tids = [], []
            for p in line.split()[1:]:
                q = p.split("/")
                vids.append(int(q[0]) - 1)
                tids.append(int(q[1]) - 1 if len(q) > 1 and q[1] else -1)
            faces.append((vids, tids, group))
    return np.array(V, np.float64), np.array(VT, np.float64), faces


def load_target(name: str):
    idx, d = [], []
    for line in open(MH / "targets" / f"{name}.target"):
        if line.startswith("#") or not line.strip():
            continue
        p = line.split()
        idx.append(int(p[0]))
        d.append([float(p[1]), float(p[2]), float(p[3])])
    return np.array(idx, np.int64), np.array(d, np.float64).reshape(-1, 3)


def vertex_normals(V, tris):
    n = np.zeros_like(V)
    a, b, c = V[tris[:, 0]], V[tris[:, 1]], V[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(n, tris[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-12)


def neighbours(nv, tris):
    nb = [set() for _ in range(nv)]
    for a, b, c in tris:
        nb[a].update((b, c))
        nb[b].update((a, c))
        nb[c].update((a, b))
    return [np.array(sorted(s), dtype=np.int64) for s in nb]


# ---------------------------------------------------------------------------
# 3D value noise for texturing
# ---------------------------------------------------------------------------
def _hash3(ix, iy, iz):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float32) / 65535.0


def noise3(p, freq):
    q = p * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    u = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[..., 0] if dx else 1 - u[..., 0]) * (u[..., 1] if dy else 1 - u[..., 1]) * (u[..., 2] if dz else 1 - u[..., 2])
                out = out + w * _hash3(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz)
    return out


def fbm3(p, freq, octaves=4):
    s = 0.0
    a = 0.5
    for _ in range(octaves):
        s = s + a * noise3(p, freq)
        freq *= 2.03
        a *= 0.5
    return s / (1 - 0.5 ** octaves)


# ---------------------------------------------------------------------------
# build one person
# ---------------------------------------------------------------------------
def build(who: str):
    V0, VT, faces = load_obj(MH / "base.obj")
    V = V0.copy()
    for name, w in SPEC[who]["targets"]:
        idx, d = load_target(name)
        if len(idx):
            V[idx] += d * w
    sk = json.load(open(MH / "rigs" / "default.mhskel"))
    wts = json.load(open(MH / "rigs" / "default_weights.mhw"))["weights"]
    J = sk["joints"]

    def joint(name):
        return V[J[name]].mean(0) * SCALE

    # keep the body only (drop helper geometry), remap
    body_faces = [f for f in faces if f[2] == "body"]
    used = sorted({v for f in body_faces for v in f[0]})
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    P = V[used] * SCALE
    quads = [[int(remap[v]) for v in f[0]] for f in body_faces]
    fuv = [f[1] for f in body_faces]
    tris = []
    tri_uv = []
    for q, tq in zip(quads, fuv):
        for k in range(1, len(q) - 1):
            tris.append([q[0], q[k], q[k + 1]])
            tri_uv.append([tq[0], tq[k], tq[k + 1]])
    tris = np.array(tris)
    tri_uv = np.array(tri_uv)
    nv = len(P)

    # bone weights per vertex (remapped)
    W = {}
    for bone, lst in wts.items():
        if isinstance(lst, dict):
            items = list(lst.items())
        else:
            items = lst
        arr = np.zeros(nv)
        for vi, w in items:
            vi = int(vi)
            if remap[vi] >= 0:
                arr[remap[vi]] = float(w)
        if arr.any():
            W[bone] = arr

    def bw(*prefixes):
        s = np.zeros(nv)
        for b, a in W.items():
            if any(b.startswith(p) for p in prefixes):
                s += a
        return np.clip(s, 0, 1)

    N = vertex_normals(P, tris)
    nb = neighbours(nv, tris)

    def along(p_from, p_to):
        d = p_to - p_from
        return np.clip(((P - p_from) @ d) / (d @ d), 0, 1)

    # ---- regions ----------------------------------------------------------
    j_neck = joint(sk["bones"]["neck01"]["head"])
    j_head = joint(sk["bones"]["head"]["head"])
    groups = {}
    for f in faces:
        groups.setdefault(f[2], set()).update(f[0])
    eye_l = V[sorted(groups["joint-l-eye"])].mean(0) * SCALE
    eye_r = V[sorted(groups["joint-r-eye"])].mean(0) * SCALE
    eye_y = (eye_l[1] + eye_r[1]) * 0.5
    face_z = P[:, 2].max()
    torso = bw("spine", "breast", "clavicle", "shoulder01", "root")
    upper_arm = bw("upperarm")
    fore = bw("lowerarm")
    hip = bw("pelvis")
    thigh = bw("upperleg")
    shin = bw("lowerleg")
    foot = bw("foot", "toe")
    neck = bw("neck")
    headw = bw("head", "jaw", "oris", "orbicularis", "levator", "risorius", "special", "oculi", "eye", "tongue")
    lips = bw("oris")
    hands = bw("wrist", "metacarpal", "finger")
    # forearm position along elbow -> wrist (both sides)
    t_fore = np.zeros(nv)
    for side in ("L", "R"):
        e = joint(sk["bones"][f"lowerarm01.{side}"]["head"])
        wr = joint(sk["bones"][f"wrist.{side}"]["head"])
        mask = (np.sign(P[:, 0]) == (1 if side == "L" else -1))
        t_fore = np.where(mask, along(e, wr), t_fore)
    t_thigh = np.zeros(nv)
    for side in ("L", "R"):
        hp_ = joint(sk["bones"][f"upperleg01.{side}"]["head"])
        kn = joint(sk["bones"][f"lowerleg01.{side}"]["head"])
        mask = (np.sign(P[:, 0]) == (1 if side == "L" else -1))
        t_thigh = np.where(mask, along(hp_, kn), t_thigh)
    neck_low = np.clip((j_neck[1] + 0.045 - P[:, 1]) / 0.03, 0, 1) * neck

    if who == "man":
        cloth_top = np.clip(torso + upper_arm + neck_low + fore * (t_fore < 0.42) + bw("breast"), 0, 1)
        cloth_top = cloth_top * (1 - hip * 0.0)
        cloth_bot = np.clip(hip + thigh + shin * (1 - foot), 0, 1)
        shoes = np.clip(foot + shin * (P[:, 1] < joint(sk["bones"]["foot.L"]["head"])[1] + 0.05), 0, 1)
        cloth_bot = np.clip(cloth_bot - shoes, 0, 1)
        # the shirt is tucked in: the waistband belongs to the trousers
        waist = joint(sk["bones"]["spine05"]["head"])[1] + 0.04
        tuck = np.clip((waist - P[:, 1]) / 0.02, 0, 1)
        cloth_bot = np.maximum(cloth_bot, cloth_top * tuck * (1 - upper_arm) * (1 - fore))
        cloth_top = cloth_top * (1 - tuck * (1 - upper_arm) * (1 - fore))
        inflate = cloth_top * 0.011 + cloth_bot * 0.009 + shoes * 0.012
    else:
        dress = np.clip(torso + bw("breast") + hip + thigh * (t_thigh < 0.62), 0, 1)
        dress = dress * (1 - np.clip(bw("clavicle", "shoulder01") * 0.6, 0, 1))
        cloth_top = dress
        cloth_bot = np.zeros(nv)
        shoes = np.zeros(nv)
        inflate = dress * 0.008
    # scalp hair cap for the man (short hair)
    rel = P - np.array([0.0, eye_y, 0.0])
    front = (P[:, 2] - (j_head[2] + 0.03)) / 0.08
    hairline = 0.058 - 0.12 * np.clip(-front, 0, 1)         # lower at the back and sides
    scalp = np.clip((rel[:, 1] - hairline) / 0.02, 0, 1) * np.clip(headw, 0, 1)
    if who == "man":
        inflate = inflate + scalp * 0.004

    # ---- inflate the clothes and smooth away the anatomy under them ----------
    off = N * inflate[:, None]
    P2 = P + off
    cl = np.clip(cloth_top + cloth_bot, 0, 1)
    for _ in range(6):
        avg = np.array([P2[n].mean(0) if len(n) else P2[i] for i, n in enumerate(nb)])
        P2 = P2 + (avg - P2) * (cl * 0.5)[:, None]
    P = P2
    N = vertex_normals(P, tris)

    # ---- texture: rasterise attributes into UV space -------------------------
    attrs = {
        "pos": P, "nrm": N, "top": cloth_top, "bot": cloth_bot, "shoe": shoes, "lips": lips,
        "scalp": scalp, "hands": hands, "neck": neck, "head": headw, "tfore": t_fore,
    }
    tex = rasterize(VT, tri_uv, tris, attrs)
    albedo, normal, rough = paint(who, tex, eye_y, eye_l, eye_r, j_neck, face_z)
    T.save(OUT_T / f"{who}_albedo.png", albedo)
    T.save(OUT_T / f"{who}_normal.png", normal)
    T.save(OUT_T / f"{who}_rough.png", rough)

    # ---- hair (woman) -----------------------------------------------------------
    hair = make_hair(P, N, scalp, eye_y, j_head, short=(who == "man"))

    # ---- eyes -------------------------------------------------------------------
    eyes = load_eyes(V0, V, groups)

    bake_eye(who, eyes)
    blender_export(who, P, quads, fuv, VT, W, sk, joint, hair, eyes)


def rasterize(VT, tri_uv, tris, attrs):
    """For every texel covered by a triangle in UV space, interpolate the
    per-vertex attributes. Returns dict of (TEX, TEX, C) arrays + 'mask'."""
    H = Wd = TEX
    out = {k: np.zeros((H, Wd) + ((v.shape[1],) if v.ndim == 2 else ()), np.float32) for k, v in attrs.items()}
    mask = np.zeros((H, Wd), np.float32)
    uv = VT[tri_uv]                     # (T, 3, 2)
    px = uv[..., 0] * Wd
    py = (1.0 - uv[..., 1]) * H
    for t in range(len(tris)):
        x0, x1 = int(max(np.floor(px[t].min()), 0)), int(min(np.ceil(px[t].max()), Wd - 1))
        y0, y1 = int(max(np.floor(py[t].min()), 0)), int(min(np.ceil(py[t].max()), H - 1))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        ax, ay = px[t, 0], py[t, 0]
        bx, by = px[t, 1], py[t, 1]
        cx, cy = px[t, 2], py[t, 2]
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
        l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        l3 = 1 - l1 - l2
        inside = (l1 >= -0.01) & (l2 >= -0.01) & (l3 >= -0.01)
        if not inside.any():
            continue
        yy = ys[inside].astype(int)
        xx = xs[inside].astype(int)
        b = np.stack([l1[inside], l2[inside], l3[inside]], -1)
        vi = tris[t]
        for k, v in attrs.items():
            vals = v[vi]                # (3,) or (3, C)
            if vals.ndim == 1:
                out[k][yy, xx] = b @ vals
            else:
                out[k][yy, xx] = b @ vals
        mask[yy, xx] = 1.0
    out["mask"] = mask
    return out


def dilate(img, mask, it=8):
    """Grow the painted islands into the empty texels to hide UV seams."""
    m = mask.copy()
    img = img.copy()
    k = np.ones((3, 3), np.float32)
    for _ in range(it):
        if img.ndim == 3:
            s = cv2.filter2D(img * m[..., None], -1, k)
        else:
            s = cv2.filter2D(img * m, -1, k)
        c = cv2.filter2D(m, -1, k)
        grow = (c > 0) & (m == 0)
        if img.ndim == 3:
            img[grow] = s[grow] / c[grow][:, None]
        else:
            img[grow] = s[grow] / c[grow]
        m = np.where(grow, 1.0, m)
    return img


def paint(who, tex, eye_y, eye_l, eye_r, j_neck, face_z):
    L = T.srgb_to_linear
    pos = tex["pos"]
    msk = tex["mask"]
    n_big = fbm3(pos, 9.0, 3)
    n_mid = fbm3(pos, 40.0, 3)
    n_fine = fbm3(pos, 180.0, 2)
    # ---- skin
    if who == "man":
        skin = np.zeros(pos.shape, np.float32) + L([0.70, 0.52, 0.43])
        skin *= (0.88 + 0.22 * n_big)[..., None]
        skin = T.lerp(skin, L([0.66, 0.38, 0.33]), (np.clip(n_mid - 0.45, 0, 1) * 0.6)[..., None])
    else:
        skin = np.zeros(pos.shape, np.float32) + L([0.74, 0.66, 0.63])
        skin *= (0.9 + 0.15 * n_big)[..., None]
        # the dead: grey-violet pooling on the lower / back side, blue lips and nails
        livor = np.clip(-tex["nrm"][..., 2] * 0.6 + (0.3 - tex["nrm"][..., 1]) * 0.4, 0, 1) * (0.6 + 0.4 * n_mid)
        skin = T.lerp(skin, L([0.48, 0.36, 0.46]), (livor * 0.55)[..., None])
        skin = T.lerp(skin, skin * np.array([0.92, 0.95, 1.05]), 0.6)
    # lips, cheeks
    lips = np.clip(tex["lips"] * 1.2, 0, 1)
    lip_col = L([0.58, 0.36, 0.33]) if who == "man" else L([0.46, 0.36, 0.43])
    skin = T.lerp(skin, lip_col, (T.smoothstep(0.62, 0.9, lips) * 0.6)[..., None])
    # eyebrows: two arcs above the eyes on the front of the face
    brow = np.zeros(msk.shape, np.float32)
    for ep in (eye_l, eye_r):
        dx = (pos[..., 0] - ep[0]) / 0.03
        dy = (pos[..., 1] - (ep[1] + 0.022 + 0.006 * (1 - dx * dx))) / 0.0055
        front = pos[..., 2] > face_z - 0.06
        brow = np.maximum(brow, np.exp(-dx * dx * dx * dx - dy * dy) * front)
    hairy = T.smoothstep(0.35, 0.7, brow * (0.6 + 0.6 * n_fine))
    hair_col = L([0.06, 0.045, 0.035])
    skin = T.lerp(skin, hair_col, (hairy * 0.9)[..., None])
    # stubble for him: jaw, chin, upper lip
    if who == "man":
        head = tex["head"]
        below_nose = np.clip((eye_y - 0.045 - pos[..., 1]) / 0.02, 0, 1)
        above_neck = np.clip((pos[..., 1] - (j_neck[1] + 0.01)) / 0.02, 0, 1)
        beard = head * below_nose * above_neck * (1 - lips)
        speck = (fbm3(pos, 900.0, 1) > 0.55).astype(np.float32)
        skin = T.lerp(skin, skin * np.array([0.55, 0.55, 0.6]), (beard * (0.35 + 0.35 * speck))[..., None])
        sc = T.smoothstep(0.2, 0.8, tex["scalp"])
        hair = L([0.07, 0.055, 0.045]) * (0.7 + 0.6 * fbm3(pos, 600.0, 2))[..., None]
        skin = T.lerp(skin, hair, sc[..., None])
    else:
        # the ligature: a thin dark line round the neck, scuffed skin around it
        ny = j_neck[1] + 0.055 + 0.006 * np.sin(pos[..., 0] * 40.0)
        mark = np.exp(-((pos[..., 1] - ny) / 0.0035) ** 2) * T.smoothstep(0.2, 0.6, tex["neck"])
        bruise = np.exp(-((pos[..., 1] - ny) / 0.014) ** 2) * T.smoothstep(0.2, 0.6, tex["neck"])
        skin = T.lerp(skin, L([0.36, 0.18, 0.26]), (bruise * 0.5)[..., None])
        skin = T.lerp(skin, L([0.25, 0.04, 0.05]), (mark * 0.9)[..., None])
        sc = T.smoothstep(0.2, 0.8, tex["scalp"])
        skin = T.lerp(skin, L([0.03, 0.025, 0.02]), (T.smoothstep(0.0, 0.5, tex["scalp"]) * 0.97)[..., None])
    albedo = skin
    rough = np.zeros(msk.shape, np.float32) + 0.52 - 0.12 * lips
    nh = n_fine * 0.25                                   # pore-scale height
    # ---- clothes
    top = T.smoothstep(0.35, 0.6, tex["top"])
    bot = T.smoothstep(0.35, 0.6, tex["bot"])
    shoe = T.smoothstep(0.35, 0.6, tex["shoe"])
    folds = 0.5 + 0.5 * np.sin(pos[..., 1] * 90.0 + n_big * 12.0) * n_mid
    weave = fbm3(pos, 1400.0, 1)
    if who == "man":
        shirt = L([0.74, 0.72, 0.66]) * (0.85 + 0.15 * folds)[..., None] * (0.95 + 0.08 * weave)[..., None]
        # sweat yellowing and blood: sprayed on the front and soaked into the cuffs
        stain = T.smoothstep(0.7, 0.78, fbm3(pos, 14.0, 4)) * (pos[..., 2] > 0.02) * 0.8
        cuff = T.smoothstep(0.3, 0.42, tex["tfore"]) * (tex["tfore"] > 0.0) * T.smoothstep(0.55, 0.65, fbm3(pos, 30.0, 3))
        spray = (fbm3(pos, 220.0, 2) > 0.72) * T.smoothstep(0.45, 0.6, fbm3(pos, 6.0, 2))
        blood = np.clip(stain + cuff + spray, 0, 1)
        shirt = T.lerp(shirt, L([0.28, 0.03, 0.025]), (blood * 0.9)[..., None])
        trousers = L([0.075, 0.075, 0.085]) * (0.8 + 0.3 * folds)[..., None]
        leather = L([0.03, 0.028, 0.026]) * (0.9 + 0.2 * n_mid)[..., None]
        albedo = T.lerp(albedo, shirt, top[..., None])
        albedo = T.lerp(albedo, trousers, bot[..., None])
        albedo = T.lerp(albedo, leather, shoe[..., None])
        rough = T.lerp(rough, 0.82 - 0.3 * blood, top)
        rough = T.lerp(rough, 0.78, bot)
        rough = T.lerp(rough, 0.3, shoe)
        nh = nh * (1 - top - bot) + (folds * 0.6 + weave * 0.15) * (top + bot)
    else:
        silk = L([0.10, 0.03, 0.04]) * (0.75 + 0.35 * folds)[..., None]
        albedo = T.lerp(albedo, silk, top[..., None])
        rough = T.lerp(rough, 0.35, top)
        nh = nh * (1 - top) + folds * 0.5 * top
    # hem lines where cloth meets skin
    cl = dilate(np.ascontiguousarray(top + bot + shoe), msk, 6)
    edge = np.abs(cv2.Laplacian(cl, cv2.CV_32F, ksize=3)) * msk
    albedo *= (1 - np.clip(edge * 1.5, 0, 0.5))[..., None]
    nrm = T.normal_from_height(nh, strength=4.0, wrap=False)
    albedo = dilate(albedo, msk)
    nrm = dilate(nrm, msk)
    rough = dilate(rough, msk)
    return T.linear_to_srgb(albedo), nrm, np.clip(rough, 0, 1)


def make_hair(P, N, scalp, eye_y, j_head, short=False):
    """Hair as ribbons. Long (her): over the skull, then hanging down past the
    shoulders. Short (him): strands combed back, lying on the scalp."""
    rng = np.random.default_rng(9 if not short else 19)
    roots = np.nonzero(scalp > 0.55)[0]
    centre = np.array([0.0, eye_y + 0.035, j_head[2] + 0.005])
    verts, uvs, idx = [], [], []
    count = 900 if short else 620
    segs = 8 if short else 14
    for k in range(count):
        r = roots[rng.integers(0, len(roots))]
        p0 = P[r] + N[r] * 0.003
        rad = np.linalg.norm(p0 - centre)
        out = p0 - centre
        out[1] = 0.0
        ln = np.linalg.norm(out)
        out = out / ln if ln > 1e-6 else np.array([0.0, 0.0, -1.0])
        pts = []
        if short:
            # comb back over the skull, hugging it
            comb = np.array([0.0, 0.25, -1.0])
            comb = comb / np.linalg.norm(comb) + rng.normal(0, 0.15, 3)
            L = rng.uniform(0.035, 0.07)
            for s in range(segs):
                t = s / (segs - 1)
                q = p0 + comb * L * t
                d = q - centre
                q = centre + d / np.linalg.norm(d) * (rad + 0.004 + 0.003 * np.sin(t * np.pi))
                pts.append(q)
            width = rng.uniform(0.008, 0.014)
        else:
            length = rng.uniform(0.36, 0.5)
            for s in range(segs):
                t = s / (segs - 1)
                if t < 0.3:
                    tt = t / 0.3
                    q = p0 + out * 0.012 * tt + np.array([0.0, -0.035 * tt, 0.0])
                    d = q - centre
                    q = centre + d / np.linalg.norm(d) * max(np.linalg.norm(d), rad + 0.006 * tt)
                else:
                    tt = (t - 0.3) / 0.7
                    q = p0 + out * (0.012 + 0.035 * tt) + np.array([0.0, -0.035 - length * tt, 0.0])
                    q[0] += rng.normal(0, 0.003)
                pts.append(q)
            width = rng.uniform(0.016, 0.03)
        pts = np.array(pts)
        tang = np.gradient(pts, axis=0)
        base = len(verts)
        for s, q in enumerate(pts):
            nrm = q - centre
            nrm /= np.linalg.norm(nrm) + 1e-9
            side = np.cross(tang[s], nrm)
            side /= np.linalg.norm(side) + 1e-9
            w = width * (1.0 - 0.6 * s / (segs - 1))
            verts.append(q - side * w * 0.5)
            verts.append(q + side * w * 0.5)
            u0 = rng.uniform(0, 0.75)
            uvs.append([u0, s / (segs - 1)])
            uvs.append([u0 + 0.25, s / (segs - 1)])
        for s in range(segs - 1):
            a = base + s * 2
            idx.append([a, a + 1, a + 3, a + 2])
    if not short:
        hair_tex = np.zeros((1024, 512, 4), np.float32)
        alpha = np.zeros((1024, 512), np.float32)
        rr = np.random.default_rng(10)
        for _ in range(1400):
            x = rr.uniform(0, 512)
            w = rr.uniform(0.6, 1.6)
            ln = rr.uniform(0.7, 1.0)
            a = rr.uniform(0.5, 1.0)
            pts2 = [(x + np.sin(t * 3 + x) * 3, t * 1024 * ln) for t in np.linspace(0, 1, 30)]
            cv2.polylines(alpha, [np.array(pts2, np.int32)], False, float(a), max(1, int(w)), cv2.LINE_AA)
        hair_tex[..., 3] = np.clip(alpha, 0, 1)
        hair_tex[..., :3] = np.array([0.05, 0.04, 0.035])
        T.save(OUT_T / "hair_strands.png", hair_tex)
    return np.array(verts), np.array(uvs), idx


def load_eyes(V0, V, groups):
    EV, EVT, EF = load_obj(MH / "eyes" / "high-poly.obj")
    EV = EV.copy()
    EV[:, 1] += V0[:, 1].min()          # stored with the feet at y = 0
    out = []
    for side, jn in (("L", "joint-l-eye"), ("R", "joint-r-eye")):
        gi = sorted(groups[jn])
        j0 = V0[gi].mean(0)
        j1 = V[gi].mean(0)
        sel = (EV[:, 0] > 0) if side == "L" else (EV[:, 0] <= 0)
        faces = [f for f in EF if all(sel[v] for v in f[0])]
        used = sorted({v for f in faces for v in f[0]})
        rm = {v: i for i, v in enumerate(used)}
        pts = (EV[used] - j0 + j1) * 0.1
        out.append((pts, [[rm[v] for v in f[0]] for f in faces], [f[1] for f in faces]))
    return out, EVT


def bake_eye(who, eyes):
    """Paint the eyeball by direction (the MakeHuman eye texture does not
    survive our UV path): sclera with vessels, iris, pupil; hers clouded."""
    (eye_list, evt) = eyes
    pts, faces, ftex = eye_list[0]
    c = pts.mean(0)
    c[2] = pts[:, 2].min() + (pts[:, 2].max() - pts[:, 2].min()) * 0.5
    d = pts - c
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    tris, tuv = [], []
    for f, tq in zip(faces, ftex):
        for k in range(1, len(f) - 1):
            tris.append([f[0], f[k], f[k + 1]])
            tuv.append([tq[0], tq[k], tq[k + 1]])
    tex = rasterize(evt, np.array(tuv), np.array(tris), {"dir": d, "pos": pts})
    L = T.srgb_to_linear
    cosang = np.clip(tex["dir"][..., 2], -1, 1)
    ang = np.arccos(cosang)
    n = fbm3(tex["pos"] * 40.0, 3.0, 3)
    sclera = np.zeros(ang.shape + (3,), np.float32) + L([0.82, 0.78, 0.74])
    veins = (fbm3(tex["pos"] * 80.0, 4.0, 3) > 0.62) * T.smoothstep(0.6, 1.4, ang)
    sclera = T.lerp(sclera, L([0.6, 0.15, 0.12]), (veins * 0.6)[..., None])
    sclera = T.lerp(sclera, L([0.75, 0.55, 0.5]), (T.smoothstep(0.8, 1.6, ang) * 0.5)[..., None])
    iris_col = (L([0.32, 0.2, 0.1]) * (0.7 + 0.6 * n)[..., None])
    if who == "woman":
        iris_col = T.lerp(iris_col, L([0.62, 0.64, 0.66]), 0.7)
    col = T.lerp(sclera, iris_col, T.smoothstep(0.54, 0.5, ang)[..., None])
    col = T.lerp(col, L([0.03, 0.025, 0.02]), (T.smoothstep(0.5, 0.47, ang) * T.smoothstep(0.42, 0.47, ang) * 0.7)[..., None])
    pupil = T.smoothstep(0.2, 0.17, ang) if who == "man" else T.smoothstep(0.26, 0.23, ang) * 0.6
    col = T.lerp(col, L([0.01, 0.01, 0.012]) if who == "man" else L([0.3, 0.32, 0.34]), pupil[..., None])
    col = dilate(col, tex["mask"], 10)
    T.save(OUT_T / f"eye_{who}.png", T.linear_to_srgb(col))


# ---------------------------------------------------------------------------
# Blender: mesh + armature + weights -> glb
# ---------------------------------------------------------------------------
def blender_export(who, P, quads, fuv, VT, W, sk, joint, hair, eyes):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)

    def b(v):            # MakeHuman (Y up, +Z front) -> Blender (Z up, -Y front)
        return (float(v[0]), float(-v[2]), float(v[1]))

    def mesh_obj(name, verts, faces, uvs_per_face, uv_src, mat_name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([b(v) for v in verts], [], faces)
        me.update()
        uvl = me.uv_layers.new(name="UVMap")
        li = 0
        for poly, tq in zip(me.polygons, uvs_per_face):
            for k, loop_index in enumerate(poly.loop_indices):
                t = tq[k]
                uvl.data[loop_index].uv = (float(uv_src[t][0]), float(uv_src[t][1])) if t >= 0 else (0.0, 0.0)
        for poly in me.polygons:
            poly.use_smooth = True
        mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        return ob

    body = mesh_obj(who, P, quads, fuv, VT, f"{who}_skin")
    for bone, arr in W.items():
        vg = body.vertex_groups.new(name=bone)
        nz = np.nonzero(arr > 0.002)[0]
        for vi in nz:
            vg.add([int(vi)], float(arr[vi]), "REPLACE")

    # armature
    arm_data = bpy.data.armatures.new(f"{who}_rig")
    arm = bpy.data.objects.new(f"{who}_rig", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    bones = sk["bones"]
    order = []
    done = set()

    def visit(n):
        if n in done:
            return
        p = bones[n]["parent"]
        if p:
            visit(p)
        done.add(n)
        order.append(n)

    for n in bones:
        visit(n)
    for n in order:
        eb = arm_data.edit_bones.new(n)
        h = joint(bones[n]["head"])
        t = joint(bones[n]["tail"])
        if np.linalg.norm(t - h) < 1e-4:
            t = h + np.array([0.0, 0.01, 0.0])
        eb.head = b(h)
        eb.tail = b(t)
        p = bones[n]["parent"]
        if p:
            eb.parent = arm_data.edit_bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    body.parent = arm
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

    # eyes, weighted to the head
    eye_objs = []
    (eye_list, evt) = eyes
    for i, (pts, faces, ftex) in enumerate(eye_list):
        eo = mesh_obj(f"{who}_eye{i}", pts, faces, ftex, evt, f"{who}_eye")
        vg = eo.vertex_groups.new(name="head")
        vg.add(list(range(len(pts))), 1.0, "REPLACE")
        eo.parent = arm
        m = eo.modifiers.new("Armature", "ARMATURE")
        m.object = arm
        eye_objs.append(eo)
    if hair is not None:
        hv, huv, hidx = hair
        me = bpy.data.meshes.new(f"{who}_hair")
        me.from_pydata([b(v) for v in hv], [], hidx)
        me.update()
        uvl = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for loop_index in poly.loop_indices:
                vi = me.loops[loop_index].vertex_index
                uvl.data[loop_index].uv = (float(huv[vi][0]), 1.0 - float(huv[vi][1]))
        me.materials.append(bpy.data.materials.new(f"{who}_hair"))
        ho = bpy.data.objects.new(f"{who}_hair", me)
        bpy.context.collection.objects.link(ho)
        vg = ho.vertex_groups.new(name="head")
        vg.add(list(range(len(hv))), 1.0, "REPLACE")
        ho.parent = arm
        m = ho.modifiers.new("Armature", "ARMATURE")
        m.object = arm

    path = OUT_M / f"{who}.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_skins=True,
                              export_animations=False, export_yup=True, export_apply=False,
                              export_materials="PLACEHOLDER", export_all_influences=False)
    print("wrote", path)


if __name__ == "__main__":
    for who in (sys.argv[1:] or ["man", "woman"]):
        build(who)

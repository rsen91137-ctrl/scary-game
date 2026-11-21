#!/usr/bin/env python3
"""Build the two people of the night from MakeHuman CC0 data, in headless
Blender (pip package `bpy`).

  man    the husband, about fifty: a white dress shirt (blood sprayed on the
         front, soaked into the cuffs, wiped off his hands on the hips), dark
         jeans and belt, black shoes, short greying hair, stubble, tired eyes,
         three fresh scratches down the left side of his neck (she fought)
  woman  his wife, dead: thirty-ish, a wine-dark satin blouse (damp from the
         bath) and a charcoal skirt, barefoot, long dark hair; bloodless,
         livid where the blood settled, a thin deep ligature groove round the
         neck (a piano string) with her own nail scratches above it, clouded
         eyes with petechiae, eyes half open, mouth slack

Data
  art/makehuman          base mesh, skeleton + weights, targets (committed)
  art/makehuman/mh111    MakeHuman 1.1.1 system assets: clothes, shoes, hair,
                         brows, lashes, teeth, tongue, eyes, skin textures
                         (fetch with tools/fetch_makehuman.sh)
Every proxy (.mhclo) is fitted to the morphed body the way MakeHuman does:
each vertex is a weighted sum of three body vertices plus an offset scaled by
the body's proportions; its skin weights are blended from the same vertices
(or read from the proxy's own .mhw). Body vertices a garment covers are
removed so nothing pokes through.

Outputs
  assets/models/<who>.glb  meshes <who>_body/_cloth/_shoes/_hair/_brows/
      _lashes/_eyes/_cornea/_teeth/_tongue skinned to the MakeHuman default
      skeleton (163 bones, A-pose rest); body and clothes subdivided once;
      facing +Z, Y up, metres
  assets/textures/chars/<who>_<part>_{albedo,normal,rough}.png
Usage: python3 tools/build_humans.py [man|woman]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texlib as T  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MH = ROOT / "art" / "makehuman"
MX = MH / "mh111"
OUT_M = ROOT / "assets" / "models"
OUT_T = ROOT / "assets" / "textures" / "chars"
OUT_M.mkdir(parents=True, exist_ok=True)
OUT_T.mkdir(parents=True, exist_ok=True)
SCALE = 0.1                    # MakeHuman decimetres -> metres
L = T.srgb_to_linear
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)

SPEC = {
    "man": {
        "targets": [("universal-male-young-averagemuscle-averageweight", 0.42),
                    ("universal-male-young-averagemuscle-maxweight", 0.2),
                    ("universal-male-old-averagemuscle-averageweight", 0.38),
                    ("caucasian-male-young", 0.6), ("caucasian-male-old", 0.4),
                    ("mouth-corner-puller", 0.12)],
        "skin": "skins/textures/middleage_lightskinned_male_diffuse.png",
        "eye": "eyes/materials/brown_eye.png",
        "parts": [("cloth", "clothes/male_casualsuit01"), ("shoes", "clothes/shoes03"),
                  ("hair", "hair/short02"), ("brows", "eyebrows/eyebrow009"),
                  ("lashes", "eyelashes/eyelashes01"), ("teeth", "teeth/teeth_base"),
                  ("tongue", "tongue/tongue01"), ("eyes", "eyes/high-poly")],
    },
    "woman": {
        "targets": [("universal-female-young-averagemuscle-averageweight", 0.6),
                    ("universal-female-young-averagemuscle-minweight", 0.4),
                    ("caucasian-female-young", 1.0),
                    ("mouth-open", 0.22), ("eye-left-closure", 0.55), ("eye-right-closure", 0.6)],
        "skin": "skins/textures/young_lightskinned_female_diffuse.png",
        "eye": "eyes/materials/brownlight_eye.png",
        "parts": [("cloth", "clothes/female_elegantsuit01"), ("hair", "hair/long01"),
                  ("brows", "eyebrows/eyebrow010"), ("lashes", "eyelashes/eyelashes02"),
                  ("teeth", "teeth/teeth_base"), ("tongue", "tongue/tongue01"),
                  ("eyes", "eyes/high-poly")],
    },
}
SUBDIV = {"body", "cloth", "shoes"}
UPPER = ("spine", "clavicle", "shoulder", "upperarm", "lowerarm", "wrist", "neck", "breast", "head",
         "finger", "metacarpal")
LOWER = ("pelvis", "upperleg", "lowerleg", "foot", "toe", "root")


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


def parse_mhclo(path: Path) -> dict:
    """MakeHuman proxy file: reference vertices / weights / offsets per proxy
    vertex, the axis scale references and the body vertices it hides."""
    refs, wts, offs = [], [], []
    delete: set[int] = set()
    scale = [None, None, None]
    status = None
    for line in open(path):
        w = line.split()
        if not w or w[0].startswith("#") or w[0].startswith("//"):
            continue
        k = w[0]
        if k[0].isalpha():
            # like MakeHuman: keywords switch sections only when they name one
            if k == "verts":
                status = "v"
            elif k == "delete_verts":
                status = "d"
            elif k == "weights":
                status = None
            elif k in ("x_scale", "y_scale", "z_scale"):
                scale["xyz".index(k[0])] = (int(w[1]), int(w[2]), float(w[3]))
            continue
        if status == "v":
            if len(w) == 1:
                refs.append([int(w[0])] * 3)
                wts.append([1.0, 0.0, 0.0])
                offs.append([0.0, 0.0, 0.0])
            else:
                refs.append([int(x) for x in w[:3]])
                wts.append([float(x) for x in w[3:6]])
                offs.append([float(x) for x in w[6:9]] if len(w) >= 9 else [0.0, 0.0, 0.0])
        elif status == "d":
            seq = False
            v0 = 0
            for t in w:
                if t == "-":
                    seq = True
                    continue
                v = int(t)
                if seq:
                    delete.update(range(v0, v + 1))
                    seq = False
                else:
                    delete.add(v)
                v0 = v
    return {"refs": np.array(refs, np.int64), "wts": np.array(wts, np.float64),
            "offs": np.array(offs, np.float64), "delete": delete, "scale": scale}


def fit(px: dict, V: np.ndarray) -> np.ndarray:
    S = np.ones(3)
    for n, sd in enumerate(px["scale"]):
        if sd:
            a, b, den = sd
            S[n] = abs(V[a, n] - V[b, n]) / den
    return (V[px["refs"]] * px["wts"][..., None]).sum(1) + px["offs"] * S


def normalize_weights(W: dict, n: int, fallback: dict | None = None) -> dict:
    tot = np.zeros(n)
    for a in W.values():
        tot += a
    bad = tot < 1e-6
    if bad.any() and fallback:
        for b, a in fallback.items():
            W.setdefault(b, np.zeros(n))
            W[b] = np.where(bad, a, W[b])
        tot = np.zeros(n)
        for a in W.values():
            tot += a
    tot = np.where(tot > 1e-9, tot, 1.0)
    out = {}
    for b, a in W.items():
        a = a / tot
        a = np.where(a > 0.004, a, 0.0)
        if a.any():
            out[b] = a
    return out


def proxy_weights(px: dict, Wfull: dict, n: int, own: Path | None) -> dict:
    if own is not None and own.exists():
        raw = json.load(open(own))["weights"]
        W = {}
        for bone, lst in raw.items():
            items = lst.items() if isinstance(lst, dict) else lst
            a = np.zeros(n)
            for vi, w in items:
                if int(vi) < n:
                    a[int(vi)] = float(w)
            if a.any():
                W[bone] = a
        return normalize_weights(W, n)
    W = {}
    for bone, arr in Wfull.items():
        w = (arr[px["refs"]] * px["wts"]).sum(1)
        w = np.where(w > 1e-4, w, 0.0)
        if w.any():
            W[bone] = w
    first = {b: arr[px["refs"][:, 0]] for b, arr in Wfull.items() if arr[px["refs"][:, 0]].any()}
    return normalize_weights(W, n, first)


def region(W: dict, n: int, prefixes) -> np.ndarray:
    s = np.zeros(n)
    for b, a in W.items():
        if any(b.startswith(p) for p in prefixes):
            s += a
    return np.clip(s, 0, 1)


def vertex_normals(V, quads):
    n = np.zeros_like(V)
    for k in range(1, quads.shape[1] - 1):
        a, b, c = V[quads[:, 0]], V[quads[:, k]], V[quads[:, k + 1]]
        fn = np.cross(b - a, c - a)
        for j in (0, k, k + 1):
            np.add.at(n, quads[:, j], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-12)


def tris_of(quads, fuv):
    q = np.asarray(quads)
    u = np.asarray(fuv)
    t = np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])
    tu = np.concatenate([u[:, [0, 1, 2]], u[:, [0, 2, 3]]])
    keep = (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    return t[keep], tu[keep]


def uv_islands(fuv: np.ndarray, ntex: int) -> np.ndarray:
    parent = np.arange(ntex)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for f in fuv:
        r0 = find(int(f[0]))
        for t in f[1:]:
            r = find(int(t))
            if r != r0:
                parent[r] = r0
    return np.array([find(int(f[0])) for f in fuv])


# ---------------------------------------------------------------------------
# 3D value noise for painting in object space
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
# texture space helpers
# ---------------------------------------------------------------------------
def rasterize(VT, tri_uv, tris, attrs, size):
    """For every texel covered by a triangle in UV space, interpolate the
    per-vertex attributes. Returns dict of (size, size[, C]) arrays + 'mask'."""
    H = Wd = size
    out = {k: np.zeros((H, Wd) + ((v.shape[1],) if v.ndim == 2 else ()), np.float32) for k, v in attrs.items()}
    mask = np.zeros((H, Wd), np.float32)
    uv = VT[tri_uv]
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
        inside = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
        if not inside.any():
            continue
        yy = ys[inside].astype(int)
        xx = xs[inside].astype(int)
        b = np.stack([l1[inside], l2[inside], l3[inside]], -1)
        vi = tris[t]
        for k, v in attrs.items():
            out[k][yy, xx] = b @ v[vi]
        mask[yy, xx] = 1.0
    out["mask"] = mask
    return out


def dilate(img, mask, it=10):
    """Grow the painted islands into the empty texels to hide UV seams."""
    m = mask.astype(np.float32).copy()
    img = np.ascontiguousarray(img, np.float32).copy()
    k = np.ones((3, 3), np.float32)
    for _ in range(it):
        s = cv2.filter2D(img * (m[..., None] if img.ndim == 3 else m), -1, k)
        c = cv2.filter2D(m, -1, k)
        grow = (c > 0) & (m == 0)
        if img.ndim == 3:
            img[grow] = s[grow] / c[grow][:, None]
        else:
            img[grow] = s[grow] / c[grow]
        m = np.where(grow, 1.0, m)
    return img


def load_img(rel: str, size: int | None = None):
    im = cv2.imread(str(MX / rel), cv2.IMREAD_UNCHANGED)
    if im is None:
        raise FileNotFoundError(MX / rel)
    if im.ndim == 2:
        im = im[..., None]
    if im.shape[2] == 4:
        im = im[..., [2, 1, 0, 3]]
    elif im.shape[2] == 3:
        im = im[..., ::-1]
    im = im.astype(np.float32) / 255.0
    if size and im.shape[0] != size:
        im = cv2.resize(im, (size, size), interpolation=cv2.INTER_AREA)
        if im.ndim == 2:
            im = im[..., None]
    return np.ascontiguousarray(im)


def lum(c):
    return (c[..., :3] * LUMA).sum(-1)


def highpass(a, sigma):
    return a - T.blur(np.ascontiguousarray(a), sigma)


def segments_dist(px, py, pts):
    """Distance from points (px, py) to a polyline pts [(x, y), ...]."""
    d = np.full(px.shape, 1e9, np.float32)
    for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
        vx, vy = bx - ax, by - ay
        t = np.clip(((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy + 1e-12), 0, 1)
        d = np.minimum(d, np.hypot(px - (ax + vx * t), py - (ay + vy * t)))
    return d


def save_set(who, part, albedo=None, normal=None, rough=None, alpha=None):
    if albedo is not None:
        a = T.linear_to_srgb(albedo)
        if alpha is not None:
            a = np.concatenate([a, alpha[..., None]], -1)
        T.save(OUT_T / f"{who}_{part}_albedo.png", a)
    if normal is not None:
        T.save(OUT_T / f"{who}_{part}_normal.png", normal)
    if rough is not None:
        T.save(OUT_T / f"{who}_{part}_rough.png", np.clip(rough, 0, 1))


# ---------------------------------------------------------------------------
# build one person
# ---------------------------------------------------------------------------
def build(who: str):
    spec = SPEC[who]
    V0, VT, faces = load_obj(MH / "base.obj")
    V = V0.copy()
    for name, w in spec["targets"]:
        idx, d = load_target(name)
        if len(idx):
            V[idx] += d * w
    sk = json.load(open(MH / "rigs" / "default.mhskel"))
    raw = json.load(open(MH / "rigs" / "default_weights.mhw"))["weights"]
    J = sk["joints"]
    nV = len(V)
    Wfull = {}
    for bone, lst in raw.items():
        items = lst.items() if isinstance(lst, dict) else lst
        a = np.zeros(nV)
        for vi, w in items:
            a[int(vi)] = float(w)
        if a.any():
            Wfull[bone] = a

    def joint(name):
        return V[J[name]].mean(0) * SCALE

    groups: dict[str, set] = {}
    for f in faces:
        groups.setdefault(f[2], set()).update(f[0])
    ctx = {
        "who": who,
        "eye_l": V[sorted(groups["joint-l-eye"])].mean(0) * SCALE,
        "eye_r": V[sorted(groups["joint-r-eye"])].mean(0) * SCALE,
        "neck": joint(sk["bones"]["neck01"]["head"]),
        "head": joint(sk["bones"]["head"]["head"]),
        "elbow_l": joint(sk["bones"]["lowerarm01.L"]["head"]), "wrist_l": joint(sk["bones"]["wrist.L"]["head"]),
        "elbow_r": joint(sk["bones"]["lowerarm01.R"]["head"]), "wrist_r": joint(sk["bones"]["wrist.R"]["head"]),
        "hip": joint(sk["bones"]["pelvis.L"]["head"]),
    }

    # ---- proxies ---------------------------------------------------------------
    parts = []
    delete: set[int] = set()
    for part, rel in spec["parts"]:
        folder = MX / rel
        name = folder.name
        px = parse_mhclo(folder / f"{name}.mhclo")
        z = np.load(folder / f"{name}.npz")
        P = fit(px, V) * SCALE
        n = len(P)
        assert n == len(z["coord"]), (rel, n, len(z["coord"]))
        W = proxy_weights(px, Wfull, n, folder / f"{name}.mhw")
        parts.append({"part": part, "rel": rel, "P": P, "quads": z["fvert"].astype(np.int64),
                      "fuv": z["fuvs"].astype(np.int64), "VT": z["texco"].astype(np.float64), "W": W})
        delete |= px["delete"]
        print(f"{who}: {part:7s} {rel:30s} {n:6d} verts, hides {len(px['delete'])} body verts")

    # ---- the body (minus what the clothes cover) ----------------------------------
    body_faces = [f for f in faces if f[2] == "body"]
    used = sorted({v for f in body_faces for v in f[0]})
    remap = -np.ones(nV, np.int64)
    remap[used] = np.arange(len(used))
    Pb = V[used] * SCALE
    nb = len(Pb)
    all_q = np.array([[remap[v] for v in f[0]] for f in body_faces], np.int64)
    all_uv = np.array([f[1] for f in body_faces], np.int64)
    dmask = np.zeros(nV, bool)
    dmask[list(delete)] = True
    keep = ~np.array([dmask[f[0]].any() for f in body_faces])
    Wb = {b: a[used] for b, a in Wfull.items() if a[used].any()}
    Wb = normalize_weights(Wb, nb)
    body = {"part": "body", "P": Pb, "quads": all_q[keep], "fuv": all_uv[keep], "VT": VT, "W": Wb}
    print(f"{who}: body {nb} verts, {keep.sum()} of {len(keep)} faces kept")

    # how snug do the clothes sit? (cloth vertex -> nearest body vertex along its normal)
    from scipy.spatial import cKDTree
    Nb = vertex_normals(Pb, all_q)
    tree = cKDTree(Pb)
    for p in parts:
        if p["part"] in ("cloth", "shoes", "hair"):
            d, i = tree.query(p["P"])
            sd = ((p["P"] - Pb[i]) * Nb[i]).sum(1)
            print(f"   {p['part']}: offset from skin median {np.median(sd) * 1000:.1f} mm, "
                  f"{(sd < -0.002).mean() * 100:.1f}% inside")

    # ---- textures ---------------------------------------------------------------------
    paint_skin(ctx, spec, body, all_q, all_uv, Wb)
    for p in parts:
        fn = {"cloth": paint_cloth, "shoes": paint_shoes, "hair": paint_hair, "brows": paint_brows,
              "lashes": paint_lashes, "teeth": paint_teeth, "tongue": paint_tongue, "eyes": paint_eyes}[p["part"]]
        fn(ctx, spec, p)

    # the eye proxy carries a cornea shell mapped to the transparent disc of
    # the eye texture: split it off as its own wet, glossy mesh
    for p in list(parts):
        if p["part"] == "eyes":
            tex = load_img(spec["eye"])
            uvc = p["VT"][p["fuv"]].mean(1)
            hh, ww = tex.shape[:2]
            a = tex[np.clip(((1 - uvc[:, 1]) * hh).astype(int), 0, hh - 1), np.clip((uvc[:, 0] * ww).astype(int), 0, ww - 1), 3]
            corn = a < 0.5
            cornea = dict(p)
            cornea["part"] = "cornea"
            cornea["quads"] = p["quads"][corn]
            cornea["fuv"] = p["fuv"][corn]
            p["quads"] = p["quads"][~corn]
            p["fuv"] = p["fuv"][~corn]
            parts.append(cornea)
            print(f"{who}: cornea {corn.sum()} faces, eyeball {(~corn).sum()}")

    blender_export(who, [body] + parts, sk, joint)
    if who == "woman":
        export_head(who, ctx, body, all_q, all_uv, parts)


# ---------------------------------------------------------------------------
# painting
# ---------------------------------------------------------------------------
def neck_coords(pos, ctx):
    """Height and arc length round the neck (0 = throat, + towards his/her
    left, i.e. +X), for marks that wrap round it."""
    cz = ctx["neck"][2] - 0.012
    th = np.arctan2(pos[..., 0], pos[..., 2] - cz)
    return pos[..., 1], th


def paint_skin(ctx, spec, body, all_q, all_uv, W):
    who = ctx["who"]
    P = body["P"]
    n = len(P)
    N = vertex_normals(P, all_q)
    tris, tuv = tris_of(all_q, all_uv)
    attrs = {
        "pos": P, "nrm": N,
        "head": region(W, n, ("head", "jaw", "oris", "orbicularis", "levator", "risorius", "special", "oculi",
                                "eye", "tongue", "temporalis", "mandible", "nose", "cheek")),
        "neck": region(W, n, ("neck",)),
        "lips": region(W, n, ("oris",)),
        "hands": region(W, n, ("wrist", "metacarpal", "finger")),
        "tips": region(W, n, ("finger1-3", "finger2-3", "finger3-3", "finger4-3", "finger5-3")),
    }
    S = 2048
    tex = rasterize(body["VT"], tuv, tris, attrs, S)
    msk = tex["mask"]
    pos = tex["pos"]
    D = L(load_img(spec["skin"], S)[..., :3])
    lm = lum(D)
    rough = np.full(msk.shape, 0.5, np.float32)
    lmb = T.blur(np.ascontiguousarray(lm), 0.7)
    height = highpass(lmb, 2.0) * 0.9 + highpass(lmb, 9.0) * 0.5
    lips = T.smoothstep(0.45, 0.85, tex["lips"])
    front = pos[..., 2] > ctx["eye_l"][2] - 0.05
    yy, th = neck_coords(pos, ctx)
    neckish = T.smoothstep(0.15, 0.5, tex["neck"] + tex["head"] * 0.5)
    if who == "man":
        D = D * np.array([1.0, 0.975, 0.96], np.float32)
        # tired: dark, faintly violet hollows under the eyes
        for ep in (ctx["eye_l"], ctx["eye_r"]):
            d = ((pos[..., 0] - ep[0]) / 0.021) ** 2 + ((pos[..., 1] - (ep[1] - 0.017)) / 0.008) ** 2
            bag = np.exp(-d) * front
            D = T.lerp(D, D * np.array([0.7, 0.6, 0.66], np.float32), (bag * 0.5)[..., None])
        # sweat on the forehead and the nose
        fh = T.smoothstep(0.02, 0.05, pos[..., 1] - ctx["eye_l"][1]) * front * T.smoothstep(0.3, 0.7, tex["head"])
        rough = rough - 0.12 * fh - 0.08 * lips
        # three nail scratches down the left side of the neck, fresh
        r = 0.058
        s = th * r
        jaw = ctx["head"][1] - 0.012
        sc = np.zeros(msk.shape, np.float32)
        edge = np.zeros(msk.shape, np.float32)
        for k in range(3):
            pts = [(r * (0.78 + k * 0.1) + 0.004 * np.sin(k * 2.0 + t * 3.0), jaw - 0.004 - k * 0.006 - t * 0.075)
                   for t in np.linspace(0, 1, 8)]
            pts = [(x + 0.012 * t, y) for (x, y), t in zip(pts, np.linspace(0, 1, 8))]
            d = segments_dist(s, yy, pts)
            fade = np.clip(1.0 - (jaw - yy - 0.01) / 0.09, 0, 1) * (pos[..., 0] > 0.01)
            sc = np.maximum(sc, np.exp(-(d / 0.0007) ** 2) * fade)
            edge = np.maximum(edge, np.exp(-(d / 0.0026) ** 2) * fade)
        sc *= neckish
        edge *= neckish
        D = T.lerp(D, D * np.array([1.25, 0.72, 0.7], np.float32), (edge * 0.75)[..., None])
        D = T.lerp(D, L(np.array([0.36, 0.05, 0.05], np.float32)), (sc * 0.92)[..., None])
        height += edge * 0.15 - sc * 0.35
        rough = T.lerp(rough, 0.28, sc)
        # dried blood worked into the creases of his hands
        crease = np.clip(-highpass(lm, 3.0) * 14.0, 0, 1)
        hb = T.smoothstep(0.3, 0.7, tex["hands"]) * T.smoothstep(0.45, 0.65, fbm3(pos, 60.0, 3))
        D = T.lerp(D, L(np.array([0.30, 0.05, 0.04], np.float32)), (np.clip(crease * 0.9 + 0.25, 0, 1) * hb * 0.7)[..., None])
        rough = T.lerp(rough, 0.6, hb * 0.6)
    else:
        # bloodless: grey, cool, waxy
        g = lm[..., None] * np.array([1.0, 0.97, 0.93], np.float32)
        D = T.lerp(D, g, 0.5) * 0.98
        # lividity: blood settled into the back and the backs of the legs
        nz = tex["nrm"][..., 2]
        mott = T.smoothstep(0.35, 0.7, fbm3(pos, 22.0, 4))
        liv = T.smoothstep(0.05, 0.6, -nz) * (0.45 + 0.55 * mott) * (1 - T.smoothstep(0.3, 0.7, tex["head"]))
        D = T.lerp(D, lm[..., None] * np.array([1.05, 0.55, 0.85], np.float32), (liv * 0.65)[..., None])
        # sunken, bruised-looking eyes; petechiae on the lids and cheeks
        for ep in (ctx["eye_l"], ctx["eye_r"]):
            d = ((pos[..., 0] - ep[0]) / 0.026) ** 2 + ((pos[..., 1] - (ep[1] - 0.004)) / 0.014) ** 2
            ring = np.exp(-d) * front
            D = T.lerp(D, D * np.array([0.7, 0.64, 0.74], np.float32), (ring * 0.4)[..., None])
            dots = T.smoothstep(0.8, 0.86, fbm3(pos, 520.0, 2)) * np.exp(-d * 0.35) * front
            D = T.lerp(D, L(np.array([0.6, 0.12, 0.13], np.float32)), (dots * 0.6)[..., None])
        # cyanosed lips, blue nails
        D = T.lerp(D, L(np.array([0.42, 0.32, 0.42], np.float32)), (lips * 0.75)[..., None])
        D = T.lerp(D, D * np.array([0.75, 0.8, 1.15], np.float32), (T.smoothstep(0.3, 0.8, tex["tips"]) * 0.7)[..., None])
        # the ligature: a thin deep groove, rising towards the back of the neck
        # low on the throat in front, rising to the nape (pulled from behind)
        y0 = ctx["neck"][1] + (ctx["head"][1] - ctx["neck"][1]) * 0.15
        yl = y0 + 0.026 * (1 - np.cos(th)) * 0.5
        d = np.abs(yy - yl)
        neckish = T.smoothstep(0.3, 0.6, tex["neck"]) * (yy < ctx["head"][1] - 0.006)
        core = np.exp(-(d / 0.0009) ** 2) * neckish
        abr = np.exp(-(d / 0.0035) ** 2) * neckish
        bruise = np.exp(-(d / 0.012) ** 2) * neckish
        beads = (fbm3(pos, 900.0, 2) > 0.7) * abr
        D = T.lerp(D, D * np.array([0.9, 0.6, 0.85], np.float32), (bruise * 0.6)[..., None])
        D = T.lerp(D, L(np.array([0.55, 0.2, 0.22], np.float32)), (abr * 0.7)[..., None])
        D = T.lerp(D, L(np.array([0.2, 0.03, 0.035], np.float32)), (np.maximum(core, beads * 0.8) * 0.95)[..., None])
        height += -core * 0.6 - abr * 0.12
        rough = T.lerp(rough, 0.32, np.maximum(core, beads))
        # her own nails, clawing at the string: short scratches above it
        rng = np.random.default_rng(31)
        r = 0.052
        s = th * r
        nail = np.zeros(msk.shape, np.float32)
        for _ in range(7):
            a = rng.uniform(-0.75, 0.75)
            top = rng.uniform(0.012, 0.03)
            ylk = y0 + 0.026 * (1 - np.cos(a)) * 0.5
            pts = [(a * r + rng.normal(0, 0.0015) * t, ylk + 0.002 + top * t) for t in np.linspace(0, 1, 5)]
            nail = np.maximum(nail, np.exp(-(segments_dist(s, yy, pts) / 0.0008) ** 2))
        nail *= neckish * front
        D = T.lerp(D, L(np.array([0.45, 0.1, 0.1], np.float32)), (nail * 0.8)[..., None])
        height -= nail * 0.2
        rough = rough + 0.08 - 0.06 * lips
    rough = T.lerp(rough, rough - 0.08, lips)
    nrm = T.normal_from_height(height, strength=3.0, wrap=False)
    D = dilate(D, msk)
    nrm = dilate(nrm, msk)
    rough = dilate(rough, msk)
    save_set(who, "skin", D, nrm, rough)


def _prep(p, size, extra=None):
    """Rasterise a proxy's rest-pose position / normal / weights into its UVs."""
    n = len(p["P"])
    N = vertex_normals(p["P"], p["quads"])
    attrs = {"pos": p["P"], "nrm": N,
             "upper": region(p["W"], n, UPPER), "lower": region(p["W"], n, LOWER)}
    if extra:
        attrs.update(extra)
    tris, tuv = tris_of(p["quads"], p["fuv"])
    return rasterize(p["VT"], tuv, tris, attrs, size)


def fore_param(P, ctx):
    """0 at the elbow -> 1 at the wrist, per vertex (either arm)."""
    out = np.full(len(P), -1.0)
    for side, sgn in (("l", 1), ("r", -1)):
        e, w = ctx["elbow_" + side], ctx["wrist_" + side]
        d = w - e
        t = np.clip(((P - e) @ d) / (d @ d), -1, 1.5)
        dist = np.linalg.norm(P - (e + np.clip(t, 0, 1.2)[:, None] * d), axis=1)
        near = (np.sign(P[:, 0]) == sgn) & (dist < 0.075)
        out = np.where(near, t, out)
    return out


def paint_cloth(ctx, spec, p):
    who = ctx["who"]
    folder = p["rel"].split("/")[1]
    S = 2048
    # whole garment pieces (UV islands) are either top or bottom
    isl = uv_islands(p["fuv"], len(p["VT"]))
    n = len(p["P"])
    up = region(p["W"], n, UPPER)
    lo = region(p["W"], n, LOWER)
    cls_v = np.zeros(n)
    for r in np.unique(isl):
        f = p["quads"][isl == r]
        vv = np.unique(f)
        is_top = up[vv].mean() > lo[vv].mean() * 1.15
        cls_v[vv] = np.maximum(cls_v[vv], 1.0 if is_top else 0.0)
    tex = _prep(p, S, {"top": cls_v, "fore": fore_param(p["P"], ctx)})
    msk = tex["mask"]
    pos = tex["pos"]
    D = L(load_img(f"clothes/{folder}/{folder}_diffuse.png", S)[..., :3])
    NM = load_img(f"clothes/{folder}/{folder}_normal.png", S)[..., :3]
    AO = load_img(f"clothes/{folder}/{folder}_ao.png", S)[..., 0]
    top = T.smoothstep(0.4, 0.6, tex["top"])
    lm = lum(D)
    front = T.smoothstep(-0.1, 0.4, tex["nrm"][..., 2])
    rough = np.full(msk.shape, 0.82, np.float32)
    if who == "man":
        # the navy shirt becomes white: keep its folds, lose its colour
        sel = (top > 0.5) & (msk > 0)
        med = np.median(lm[sel]) if sel.any() else 0.05
        sh = np.clip(T.blur(np.ascontiguousarray(lm), 1.5) / med, 0.72, 1.18) ** 0.6
        shirt = L(np.array([0.86, 0.85, 0.8], np.float32)) * sh[..., None]
        # sweat yellowing round the collar and under the arms
        coll = T.smoothstep(ctx["neck"][1] - 0.03, ctx["neck"][1] + 0.01, pos[..., 1])
        pit = np.exp(-(((np.abs(pos[..., 0]) - 0.15) / 0.05) ** 2 + ((pos[..., 1] - (ctx["neck"][1] - 0.17)) / 0.05) ** 2))
        shirt = T.lerp(shirt, shirt * np.array([0.95, 0.88, 0.7], np.float32), (np.clip(coll + pit, 0, 1) * 0.5)[..., None])
        jeans = T.lerp(D, lm[..., None], 0.25) * 0.7
        D = T.lerp(jeans, shirt, top[..., None])
        # blood: a spray across the front, the cuffs soaked, smears where he
        # wiped his hands on his hips
        clump = T.smoothstep(0.52, 0.66, fbm3(pos, 6.0, 3))
        drops = T.smoothstep(0.6, 0.7, fbm3(pos, 70.0, 3)) * clump * front
        fine = T.smoothstep(0.74, 0.8, fbm3(pos, 260.0, 2)) * clump * front * 0.8
        t = tex["fore"]
        soak = t + (fbm3(pos, 25.0, 4) - 0.5) * 0.7
        cuff = T.smoothstep(0.55, 0.85, soak) * T.smoothstep(0.35, 0.55, fbm3(pos * np.array([1, 0.3, 1]), 45.0, 3) + 0.25) * top
        hipy = ctx["hip"][1]
        smear = np.zeros(msk.shape, np.float32)
        for sx in (-1, 1):
            q = pos.copy()
            q[..., 1] *= 0.25
            streak = T.smoothstep(0.5, 0.65, fbm3(q, 60.0, 3))
            zone = np.exp(-(((pos[..., 0] - sx * 0.15) / 0.045) ** 2 + ((pos[..., 1] - hipy - 0.02) / 0.09) ** 2))
            smear = np.maximum(smear, streak * zone)
        blood = np.clip(np.maximum.reduce([drops, fine, cuff * 0.95, smear * 0.85]), 0, 1)
        core = T.smoothstep(0.45, 0.85, T.blur(np.ascontiguousarray(blood), 2.5))
        bcol = T.lerp(L(np.array([0.36, 0.1, 0.08], np.float32)), L(np.array([0.5, 0.03, 0.03], np.float32)), core[..., None])
        D = T.lerp(D, bcol, (blood * 0.95)[..., None])
        rough = T.lerp(np.full(msk.shape, 0.85, np.float32), np.full(msk.shape, 0.88, np.float32), 1 - top)
        rough = T.lerp(rough, 0.5 - 0.2 * core, blood)
    else:
        # wine satin blouse, folds from the AO and the normal map (the stripes go)
        shade = np.clip(AO, 0.25, 1) ** 0.9 * (0.72 + 0.28 * np.clip(NM[..., 2] * 2 - 1, 0, 1))
        blouse = L(np.array([0.27, 0.05, 0.075], np.float32)) * shade[..., None]
        sel = (top < 0.5) & (msk > 0)
        med = np.median(lm[sel]) if sel.any() else 0.2
        weave = np.clip(lm / med, 0.6, 1.3)
        skirt = L(np.array([0.13, 0.13, 0.14], np.float32)) * (weave * shade)[..., None]
        D = T.lerp(skirt, blouse, top[..., None])
        # damp from the bath: darker, glossier patches
        damp = T.smoothstep(0.5, 0.7, fbm3(pos, 9.0, 4)) * (pos[..., 1] < ctx["neck"][1] - 0.12)
        D = D * (1 - 0.35 * damp)[..., None]
        # blood run down from the neck
        q = pos.copy()
        q[..., 1] *= 0.12
        run = T.smoothstep(0.6, 0.7, fbm3(q, 90.0, 2)) * front * top
        run *= T.smoothstep(ctx["neck"][1] - 0.2, ctx["neck"][1] - 0.02, pos[..., 1]) * (np.abs(pos[..., 0]) < 0.07)
        D = T.lerp(D, L(np.array([0.22, 0.02, 0.02], np.float32)), (run * 0.9)[..., None])
        rough = T.lerp(np.full(msk.shape, 0.85, np.float32), np.full(msk.shape, 0.55, np.float32), top)
        rough = rough - 0.15 * damp - 0.1 * run
    D = D * T.lerp(1.0, np.clip(AO, 0, 1), 0.45 if who == "man" else 0.65)[..., None]
    D = dilate(D, msk)
    rough = dilate(rough, msk)
    save_set(who, "cloth", D, NM, rough)


def paint_shoes(ctx, spec, p):
    who = ctx["who"]
    folder = p["rel"].split("/")[1]
    tex = _prep(p, 1024)
    D = L(load_img(f"clothes/{folder}/{folder}_diffuse.png", 1024)[..., :3]) * 0.8
    lm = lum(D)
    drops = T.smoothstep(0.7, 0.76, fbm3(tex["pos"], 200.0, 2)) * (tex["pos"][..., 2] > 0.05)
    D = T.lerp(D, L(np.array([0.2, 0.02, 0.02], np.float32)), (drops * 0.8)[..., None])
    rough = 0.42 - highpass(lm, 3.0) * 2.0 - 0.1 * drops
    nrm = T.normal_from_height(lm * 3.0, strength=4.0, wrap=False)
    save_set(who, "shoes", dilate(D, tex["mask"]), dilate(nrm, tex["mask"]), dilate(rough, tex["mask"]))


def paint_hair(ctx, spec, p):
    who = ctx["who"]
    folder = p["rel"].split("/")[1]
    src = load_img(f"hair/{folder}/{folder}_diffuse.png")
    alpha = src[..., 3]
    D = L(src[..., :3])
    lm = lum(D)
    med = np.median(lm[alpha > 0.5])
    sh = np.clip(lm / med, 0.3, 2.2)
    hh = src.shape[0]
    rng = np.random.default_rng(5)
    if who == "man":
        base = L(np.array([0.17, 0.13, 0.1], np.float32))
        grey = L(np.array([0.62, 0.6, 0.57], np.float32))
        # grey strands: thin streaks along the texture's strand direction
        streak = T.fft_noise(hh, hh, 3, beta=1.2, aniso=(6.0, 0.6))
        gm = T.smoothstep(0.62, 0.7, streak)
        col = T.lerp(base, grey, gm[..., None] * 0.85) * sh[..., None]
    else:
        base = L(np.array([0.085, 0.06, 0.05], np.float32))
        col = base * (sh ** 1.15)[..., None]
    nsrc = MX / f"hair/{folder}/{folder}_normal.png"
    if nsrc.exists():
        nrm = load_img(f"hair/{folder}/{folder}_normal.png")[..., :3]
    else:
        nrm = T.normal_from_height(highpass(lm, 2.0) * 8.0, strength=4.0, wrap=False)
    rough = np.clip(0.55 - highpass(lm, 2.0) * 1.5, 0.35, 0.8)
    del rng
    save_set(who, "hair", col, nrm, rough, alpha)


def paint_brows(ctx, spec, p):
    who = ctx["who"]
    folder = p["rel"].split("/")[1]
    src = load_img(f"eyebrows/{folder}/{folder}.png")
    c = L(np.array([0.13, 0.1, 0.08] if who == "man" else [0.1, 0.075, 0.06], np.float32))
    col = np.zeros(src.shape[:2] + (3,), np.float32) + c
    save_set(who, "brows", col, None, None, np.clip(src[..., 3] * 1.1, 0, 1))


def paint_lashes(ctx, spec, p):
    who = ctx["who"]
    folder = p["rel"].split("/")[1]
    src = load_img(f"eyelashes/{folder}/{folder}.png")
    col = np.zeros(src.shape[:2] + (3,), np.float32) + L(np.array([0.05, 0.04, 0.035], np.float32))
    save_set(who, "lashes", col, None, None, src[..., 3])


def paint_teeth(ctx, spec, p):
    who = ctx["who"]
    src = load_img("teeth/materials/teeth.png", 1024)
    D = L(src[..., :3])
    gum = T.smoothstep(0.05, 0.2, D[..., 0] - D[..., 2])
    if who == "man":
        D = T.lerp(D, D * np.array([1.0, 0.93, 0.78], np.float32), ((1 - gum) * 0.6)[..., None])
    else:
        D = T.lerp(D, lum(D)[..., None] * np.array([1.0, 0.8, 0.9], np.float32), (gum * 0.6)[..., None])
    rough = 0.3 + 0.25 * gum
    save_set(who, "teeth", D, None, rough)


def paint_tongue(ctx, spec, p):
    who = ctx["who"]
    D = L(load_img("tongue/tongue01/tongue01_diffuse.png", 512)[..., :3])
    if who == "woman":
        D = T.lerp(D, lum(D)[..., None] * np.array([0.9, 0.75, 0.95], np.float32), 0.6)
    save_set(who, "tongue", D, None, np.full(D.shape[:2], 0.35, np.float32))


def paint_eyes(ctx, spec, p):
    who = ctx["who"]
    src = load_img(spec["eye"])
    D = L(src[..., :3])
    alpha = src[..., 3]
    hh = src.shape[0]
    lm = lum(D)
    # find the two irises: the dark blobs
    dark = ((lm < 0.12) & (alpha > 0.5)).astype(np.uint8)
    nl, lab, stats, cent = cv2.connectedComponentsWithStats(dark)
    order = np.argsort(-stats[1:, cv2.CC_STAT_AREA])[:2] + 1
    yy, xx = np.mgrid[0:hh, 0:hh].astype(np.float32)
    rr = np.full((hh, hh), 1e9, np.float32)
    rad = 1.0
    for k in order:
        cx, cy = cent[k]
        rad = np.sqrt(stats[k, cv2.CC_STAT_AREA] / np.pi)
        rr = np.minimum(rr, np.hypot(xx - cx, yy - cy) / rad)
    iris = T.smoothstep(1.08, 0.96, rr)
    pupil = T.smoothstep(0.42, 0.36, rr)
    sclera = (1 - iris) * (alpha > 0.5)
    redness = np.clip((D[..., 0] - D[..., 1]) * 6.0, 0, 1)
    if who == "man":
        # bloodshot: the vessels he has fill and spread
        veins = T.smoothstep(0.55, 0.62, T.fft_noise(hh, hh, 41, beta=1.6)) * T.smoothstep(1.6, 2.6, rr)
        v = np.clip(redness * 1.2 + veins * 0.35, 0, 1) * sclera * T.smoothstep(1.3, 2.2, rr)
        D = T.lerp(D, L(np.array([0.62, 0.16, 0.14], np.float32)), (v * 0.45)[..., None])
        D = T.lerp(D, D * np.array([1.0, 0.94, 0.86], np.float32), (sclera * 0.5)[..., None])
    else:
        # clouded: the cornea goes milky, the iris loses its colour
        milk = L(np.array([0.6, 0.62, 0.64], np.float32))
        D = T.lerp(D, milk * (0.7 + 0.3 * lm[..., None] / max(lm.max(), 1e-3)), (iris * 0.62)[..., None])
        D = T.lerp(D, L(np.array([0.32, 0.34, 0.37], np.float32)), (pupil * 0.75)[..., None])
        D = T.lerp(D, D * np.array([0.96, 0.95, 0.85], np.float32), (sclera * 0.6)[..., None])
        # petechiae: pinpoint bleeds in the whites
        rng = np.random.default_rng(12)
        spots = np.zeros((hh, hh), np.float32)
        ys, xs = np.nonzero(sclera > 0.5)
        for i in rng.integers(0, len(ys), 260):
            cv2.circle(spots, (int(xs[i]), int(ys[i])), int(rng.integers(1, 4)), float(rng.uniform(0.6, 1.0)), -1, cv2.LINE_AA)
        D = T.lerp(D, L(np.array([0.55, 0.04, 0.05], np.float32)), (T.blur(spots, 0.7) * sclera)[..., None])
    save_set(who, "eyes", D, None, np.where(iris > 0.5, 0.15, 0.3).astype(np.float32), alpha)


# ---------------------------------------------------------------------------
# Blender: meshes + armature + weights -> glb
# ---------------------------------------------------------------------------
def blender_export(who, parts, sk, joint):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)

    def b(v):            # MakeHuman (Y up, +Z front) -> Blender (Z up, -Y front)
        return (float(v[0]), float(-v[2]), float(v[1]))

    arm_data = bpy.data.armatures.new(f"{who}_rig")
    arm = bpy.data.objects.new(f"{who}_rig", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    bones = sk["bones"]
    order = []
    done = set()

    def visit(nm):
        if nm in done:
            return
        par = bones[nm]["parent"]
        if par:
            visit(par)
        done.add(nm)
        order.append(nm)

    for nm in bones:
        visit(nm)
    for nm in order:
        eb = arm_data.edit_bones.new(nm)
        h = joint(bones[nm]["head"])
        t = joint(bones[nm]["tail"])
        if np.linalg.norm(t - h) < 1e-4:
            t = h + np.array([0.0, 0.01, 0.0])
        eb.head = b(h)
        eb.tail = b(t)
        par = bones[nm]["parent"]
        if par:
            eb.parent = arm_data.edit_bones[par]
    bpy.ops.object.mode_set(mode="OBJECT")

    for p in parts:
        name = f"{who}_{p['part']}"
        quads = p["quads"]
        used = np.unique(quads)
        rm = -np.ones(len(p["P"]), np.int64)
        rm[used] = np.arange(len(used))
        verts = p["P"][used]
        fq = rm[quads]
        me = bpy.data.meshes.new(name)
        me.from_pydata([b(v) for v in verts], [], [list(map(int, f)) for f in fq])
        me.update()
        uvl = me.uv_layers.new(name="UVMap")
        loop_uv = p["VT"][p["fuv"]].reshape(-1, 2)
        uvl.data.foreach_set("uv", loop_uv.astype(np.float32).ravel())
        me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
        me.materials.append(bpy.data.materials.new(name))
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        for bone, arr in p["W"].items():
            a = arr[used]
            nz = np.nonzero(a > 0.004)[0]
            if not len(nz):
                continue
            vg = ob.vertex_groups.new(name=bone)
            for vi in nz:
                vg.add([int(vi)], float(a[vi]), "REPLACE")
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        if p["part"] in SUBDIV:
            sub = ob.modifiers.new("Subdivision", "SUBSURF")
            sub.levels = 1
            sub.render_levels = 1
            sub.uv_smooth = "PRESERVE_BOUNDARIES"
        print(f"  blender {name}: {len(verts)} verts, {len(fq)} faces{' (subdivided)' if p['part'] in SUBDIV else ''}")

    path = OUT_M / f"{who}.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_skins=True,
                              export_animations=False, export_yup=True, export_apply=True,
                              export_materials="PLACEHOLDER", export_all_influences=False)
    print("wrote", path)


# ---------------------------------------------------------------------------
# her head on its own (for the piano): cut at the neck, the stump capped
# ---------------------------------------------------------------------------
def export_head(who, ctx, body, all_q, all_uv, parts):
    y_cut = ctx["neck"][1] + 0.035
    centre = np.array([0.0, ctx["head"][1] + 0.06, ctx["head"][2] + 0.02])
    P = body["P"]
    keep = np.all(P[all_q][:, :, 1] > y_cut, axis=1)
    hq = all_q[keep]
    huv = all_uv[keep]
    out = [{"part": "body", "P": P - centre, "quads": hq, "fuv": huv, "VT": body["VT"]}]
    # the open neck: boundary edges near the cut, chained into loops, capped
    from collections import defaultdict
    cnt = defaultdict(int)
    for f in hq:
        for k in range(4):
            e = (int(f[k]), int(f[(k + 1) % 4]))
            cnt[(min(e), max(e))] += 1
    near = P[:, 1] < y_cut + 0.04
    edges = [e for e, c in cnt.items() if c == 1 and near[e[0]] and near[e[1]]]
    adj = defaultdict(list)
    for a_, b_ in edges:
        adj[a_].append(b_)
        adj[b_].append(a_)
    seen = set()
    cap_v = []
    cap_f = []
    for start in list(adj):
        if start in seen:
            continue
        loop = [start]
        seen.add(start)
        prev, cur = None, start
        while True:
            nxt = [n for n in adj[cur] if n != prev and n not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            loop.append(cur)
        if len(loop) < 6:
            continue
        pts = P[loop] - centre
        c = pts.mean(0) + np.array([0.0, -0.004, 0.0])
        base = len(cap_v)
        cap_v.append(c)
        cap_v.extend(list(pts))
        for i in range(len(loop)):
            j = (i + 1) % len(loop)
            cap_f.append([base, base + 1 + i, base + 1 + j, base])
    if cap_v:
        cv = np.array(cap_v)
        cf = np.array(cap_f, np.int64)
        out.append({"part": "stump", "P": cv, "quads": cf, "fuv": np.zeros_like(cf), "VT": np.array([[0.5, 0.5]])})
    for p in parts:
        if p["part"] in ("cloth", "shoes"):
            continue
        q = p["quads"]
        if p["part"] == "hair":
            q = q[np.any(p["P"][q][:, :, 1] > y_cut + 0.02, axis=1)]
            fuv = p["fuv"][np.any(p["P"][p["quads"]][:, :, 1] > y_cut + 0.02, axis=1)]
        else:
            fuv = p["fuv"]
        out.append({"part": p["part"], "P": p["P"] - centre, "quads": q, "fuv": fuv, "VT": p["VT"]})
    blender_export_static(f"{who}_head", who, out)


def blender_export_static(fname, who, parts):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)

    def b(v):
        return (float(v[0]), float(-v[2]), float(v[1]))

    for p in parts:
        name = f"{who}_{p['part']}"
        quads = p["quads"]
        used = np.unique(quads)
        rm = -np.ones(len(p["P"]), np.int64)
        rm[used] = np.arange(len(used))
        verts = p["P"][used]
        fq = rm[quads]
        faces = []
        for f in fq:
            f = list(map(int, f))
            if f[3] == f[0] or f[3] == f[2]:
                f = f[:3]
            faces.append(f)
        me = bpy.data.meshes.new(name)
        me.from_pydata([b(v) for v in verts], [], faces)
        me.update()
        uvl = me.uv_layers.new(name="UVMap")
        loop_uv = []
        for f_src, f in zip(p["fuv"], faces):
            for k in range(len(f)):
                loop_uv.append(p["VT"][int(f_src[k])])
        uvl.data.foreach_set("uv", np.array(loop_uv, np.float32).ravel())
        me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
        me.materials.append(bpy.data.materials.new(name))
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        if p["part"] == "body":
            sub = ob.modifiers.new("Subdivision", "SUBSURF")
            sub.levels = 1
            sub.render_levels = 1
            sub.uv_smooth = "PRESERVE_BOUNDARIES"
        print(f"  blender {name}: {len(verts)} verts, {len(faces)} faces")
    path = OUT_M / f"{fname}.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_skins=False,
                              export_animations=False, export_yup=True, export_apply=True,
                              export_materials="PLACEHOLDER")
    print("wrote", path)


if __name__ == "__main__":
    if not (MX / ".complete").exists():
        sys.exit("MakeHuman system assets missing: run tools/fetch_makehuman.sh first")
    for who in (sys.argv[1:] or ["man", "woman"]):
        build(who)

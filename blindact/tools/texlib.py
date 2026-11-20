"""Small numpy toolkit shared by the texture generators.

Everything is deterministic (seeded) so regenerating gives identical files.
Arrays are float32, values usually 0..1, shape (H, W) or (H, W, C).
"""
from __future__ import annotations

import numpy as np
from PIL import Image

try:
    import cv2  # opencv-python-headless
except Exception:  # pragma: no cover
    cv2 = None


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


# ---------------------------------------------------------------------------
# noise
# ---------------------------------------------------------------------------
def fft_noise(h: int, w: int, seed: int, beta: float = 2.0, fmin: float = 1.0,
              fmax: float | None = None, aniso: tuple[float, float] = (1.0, 1.0)) -> np.ndarray:
    """Tileable 1/f^beta noise (periodic in both axes), normalised to 0..1.
    aniso=(sx, sy) stretches frequencies (sx>1 -> features finer along x)."""
    r = rng(seed)
    white = r.standard_normal((h, w)).astype(np.float32)
    fy = np.fft.fftfreq(h)[:, None] * h / aniso[1]
    fx = np.fft.fftfreq(w)[None, :] * w / aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = 1.0 / np.power(f, beta * 0.5)
    amp[f < fmin] = 0.0
    if fmax is not None:
        amp *= np.exp(-np.square(f / fmax))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * amp)).astype(np.float32)
    return normalize(out)


def normalize(a: np.ndarray, lo: float = 0.0, hi: float = 1.0) -> np.ndarray:
    mn, mx = float(a.min()), float(a.max())
    if mx - mn < 1e-12:
        return np.full_like(a, lo)
    return ((a - mn) / (mx - mn) * (hi - lo) + lo).astype(np.float32)


def smoothstep(e0: float, e1: float, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0:
        return a
    if cv2 is not None:
        k = int(sigma * 3) * 2 + 1
        return cv2.GaussianBlur(a, (k, k), sigma, borderType=cv2.BORDER_WRAP if False else cv2.BORDER_REFLECT)
    from scipy.ndimage import gaussian_filter
    return gaussian_filter(a, sigma)


def blur_wrap(a: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur that wraps around (for tileable maps)."""
    from scipy.ndimage import gaussian_filter
    return gaussian_filter(a, sigma, mode="wrap")


def worley(h: int, w: int, n: int, seed: int, wrap: bool = True) -> tuple[np.ndarray, np.ndarray]:
    """Distance to nearest / second nearest feature point (in pixels)."""
    from scipy.spatial import cKDTree
    r = rng(seed)
    pts = r.random((n, 2)) * [h, w]
    if wrap:
        offs = [(dy, dx) for dy in (-h, 0, h) for dx in (-w, 0, w)]
        allp = np.concatenate([pts + o for o in offs])
    else:
        allp = pts
    tree = cKDTree(allp)
    yy, xx = np.mgrid[0:h, 0:w]
    d, _ = tree.query(np.stack([yy.ravel(), xx.ravel()], 1), k=2)
    return d[:, 0].reshape(h, w).astype(np.float32), d[:, 1].reshape(h, w).astype(np.float32)


# ---------------------------------------------------------------------------
# maps
# ---------------------------------------------------------------------------
def normal_from_height(hgt: np.ndarray, strength: float = 2.0, wrap: bool = True) -> np.ndarray:
    """OpenGL-style normal map (+Y up) from a height field, returned 0..1 RGB."""
    if wrap:
        dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5
        dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5
    else:
        dy, dx = np.gradient(hgt)
    nx = -dx * strength
    ny = dy * strength          # image rows grow downwards; +Y (green) is up
    nz = np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], -1)
    return (n * 0.5 + 0.5).astype(np.float32)


def srgb_to_linear(c):
    c = np.asarray(c, np.float32)
    return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))


def linear_to_srgb(c):
    c = np.clip(np.asarray(c, np.float32), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def lerp(a, b, t):
    return a + (b - a) * t


def save(path, arr: np.ndarray, mode: str | None = None) -> None:
    a = np.clip(arr, 0.0, 1.0)
    img8 = (a * 255.0 + 0.5).astype(np.uint8)
    if img8.ndim == 2:
        im = Image.fromarray(img8, "L")
    elif img8.shape[2] == 3:
        im = Image.fromarray(img8, "RGB")
    else:
        im = Image.fromarray(img8, "RGBA")
    if mode:
        im = im.convert(mode)
    im.save(str(path), optimize=True)
    print("wrote", path, im.size)


def downsample(a: np.ndarray, factor: int) -> np.ndarray:
    """Box filter downsample by an integer factor."""
    h, w = a.shape[:2]
    h2, w2 = h // factor, w // factor
    a = a[: h2 * factor, : w2 * factor]
    if a.ndim == 2:
        return a.reshape(h2, factor, w2, factor).mean((1, 3)).astype(np.float32)
    return a.reshape(h2, factor, w2, factor, a.shape[2]).mean((1, 3)).astype(np.float32)

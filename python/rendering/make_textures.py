"""Procedural PNG textures for the render-only scenes (no stock images): MLI gold foil, solar-cell array,
brushed-aluminium panels with seams and fasteners, white radiator. Deterministic (fixed seeds).
Usage: python make_textures.py <out_dir>   (never overwrites)"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(116075)


def save(a, name):
    p = os.path.join(out, name)
    assert not os.path.exists(p), p
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(p)
    print("written", p)


def smooth_noise(n, scales, weights):
    acc = np.zeros((n, n))
    for s, w in zip(scales, weights):
        img = Image.fromarray((rng.random((n, n)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(s))
        a = np.asarray(img, float); a = (a - a.mean()) / (a.std() + 1e-9)
        acc += w * a
    return acc


# 1. MLI gold foil: crinkled multilayer insulation (anisotropic smooth noise + creases + specular glints)
n = 1024
cr = smooth_noise(n, [2, 6, 18, 48], [0.35, 0.6, 0.8, 0.5])
gx, gy = np.gradient(cr)
shade = 0.5 + 0.5 * np.tanh(1.8 * (gx * 0.8 - gy * 0.6))           # directional light on the crinkles
crease = np.zeros((n, n))
for _ in range(70):                                                 # thin creases (random polylines)
    x, y = rng.uniform(0, n, 2); a = rng.uniform(0, np.pi)
    for _ in range(int(rng.uniform(60, 260))):
        a += rng.normal(0, 0.08); x += np.cos(a); y += np.sin(a)
        if 0 <= int(y) < n and 0 <= int(x) < n:
            crease[int(y), int(x)] = 1.0
crease = np.asarray(Image.fromarray((crease * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), float) / 255
gold = np.array([212, 160, 62], float); dark = np.array([120, 82, 26], float); glint = np.array([255, 236, 170], float)
t = np.clip(shade - 0.35 * crease, 0, 1)[..., None]
img = dark * (1 - t) + gold * t
img = img + (glint - img) * (np.clip(shade - 0.86, 0, 1) / 0.14)[..., None] * 0.8
save(img, "tex_mli_gold.png")

# 2. Solar array: 8 x 4 strings of cells, dark blue with subtle per-cell variation, silver gaps and bus bars
W, H = 1024, 512
img = np.zeros((H, W, 3)); img[:] = (176, 180, 188)                 # silver substrate (gaps)
nx, ny = 16, 8; gap = 4
cw, ch = (W - gap * (nx + 1)) / nx, (H - gap * (ny + 1)) / ny
yy, xx = np.mgrid[0:H, 0:W]
for i in range(nx):
    for j in range(ny):
        x0 = gap + i * (cw + gap); y0 = gap + j * (ch + gap)
        m = (xx >= x0) & (xx < x0 + cw) & (yy >= y0) & (yy < y0 + ch)
        base = np.array([18, 30, 72]) * rng.uniform(0.9, 1.1)
        grad = ((yy - y0) / ch)[m][:, None] * np.array([10, 14, 26])
        img[m] = base + grad
        for k in range(1, 4):                                       # thin bus bars
            bx = int(x0 + k * cw / 4)
            img[int(y0):int(y0 + ch), bx:bx + 1] = (120, 128, 150)
img += rng.normal(0, 2.5, img.shape)
save(img, "tex_solar_cells.png")

# 3. Aluminium panels: brushed metal with panel seams and fasteners (target body / arm base)
n = 512
br = np.asarray(Image.fromarray((rng.random((n, n)) * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(0)), float)
br = np.asarray(Image.fromarray(br.astype(np.uint8)).resize((n, n)).filter(ImageFilter.GaussianBlur(0.6)), float)
streak = np.asarray(Image.fromarray((rng.random((n, 1)) * 255).astype(np.uint8)).resize((n, n), Image.BILINEAR), float)
base = 150 + 0.06 * (br - 128) + 0.10 * (streak - 128)
img = np.stack([base * 0.97, base, base * 1.03], -1)
for s in (0, n // 2):                                               # seams
    img[s:s + 2, :] *= 0.55; img[:, s:s + 2] *= 0.55
for cx in np.arange(16, n, 64):                                     # fasteners along the seams
    for cy in (6, n // 2 + 6):
        img[cy - 2:cy + 2, cx - 2:cx + 2] = (95, 97, 100)
        img[cx - 2:cx + 2, cy - 2:cy + 2] = (95, 97, 100)
save(img, "tex_aluminium_panels.png")

# 4. White radiator with faint fin pattern
img = np.zeros((256, 256, 3)) + 232
for x in range(0, 256, 16):
    img[:, x:x + 2] -= 18
img += rng.normal(0, 2, img.shape)
save(img, "tex_radiator.png")

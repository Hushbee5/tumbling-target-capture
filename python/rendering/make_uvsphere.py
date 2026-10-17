"""Writes uvsphere.obj: a unit UV sphere with texture coordinates (equirectangular map), for a render-only Earth.
Usage: python make_uvsphere.py <out.obj> [n_lat] [n_lon]"""
import math
import os
import sys

out = sys.argv[1]
nlat = int(sys.argv[2]) if len(sys.argv) > 2 else 64
nlon = int(sys.argv[3]) if len(sys.argv) > 3 else 128
assert not os.path.exists(out), out
v, vt, f = [], [], []
for i in range(nlat + 1):                       # latitude from +90 to -90 deg
    th = math.pi * i / nlat
    for j in range(nlon + 1):                   # longitude 0..360 (seam duplicated for the texture)
        ph = 2 * math.pi * j / nlon
        v.append((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
        vt.append((j / nlon, 1.0 - i / nlat))
idx = lambda i, j: i * (nlon + 1) + j + 1
for i in range(nlat):
    for j in range(nlon):
        a, b, c, d = idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)
        f.append((a, b, c)); f.append((a, c, d))
with open(out, "x") as fh:
    fh.write("# unit UV sphere, %d x %d\n" % (nlat, nlon))
    for p in v: fh.write("v %.6f %.6f %.6f\n" % p)
    for p in vt: fh.write("vt %.6f %.6f\n" % p)
    for a, b, c in f: fh.write("f %d/%d %d/%d %d/%d\n" % (a, a, b, b, c, c))
print("written", out, len(v), "vertices", len(f), "faces")

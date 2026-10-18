"""Fetches and generates the render-only assets that are not stored in the repository.

  - NASA Visible Earth "Blue Marble" land/shallow-water/topography map (8192 x 4096 TIFF), converted to
    land_shallow_topo_8192.png and land_shallow_topo_2048.png in python/rendering/
  - uvsphere.obj (unit UV sphere with texture coordinates) in python/rendering/

Usage: python scripts/setup_assets.py
Existing files are kept. Only the renders need these assets; simulations and checks do not."""
import os
import subprocess
import sys
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REND = os.path.join(ROOT, "python", "rendering")
URL = "https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57752/land_shallow_topo_8192.tif"
TIF = os.path.join(REND, "land_shallow_topo_8192.tif")

Image.MAX_IMAGE_PIXELS = None

if not os.path.exists(TIF):
    print("downloading", URL)
    urllib.request.urlretrieve(URL, TIF + ".part")
    os.replace(TIF + ".part", TIF)

img = None
for w in (8192, 2048):
    out = os.path.join(REND, "land_shallow_topo_%d.png" % w)
    if os.path.exists(out):
        continue
    if img is None:
        img = Image.open(TIF).convert("RGB")
    im = img if img.width == w else img.resize((w, w // 2), Image.LANCZOS)
    im.save(out)
    print("written", out)

obj = os.path.join(REND, "uvsphere.obj")
if not os.path.exists(obj):
    subprocess.check_call([sys.executable, os.path.join(REND, "make_uvsphere.py"), obj])
print("assets ready in", REND)

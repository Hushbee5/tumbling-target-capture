# -*- coding: utf-8 -*-
"""Assemble a slideshow GIF from rendered PNG frames under a size budget (one shared palette, so no colour flicker).
Usage: python make_gif.py <frame_dir> <out.gif> <width> <stride | a:b:s,c:d:t> <colors> <ms_per_frame> [<last_hold_ms>]
Refuses to overwrite <out.gif>."""
import glob
import os
import sys

from PIL import Image

src, out, width, stride, colors, ms = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5]), int(sys.argv[6])
hold = int(sys.argv[7]) if len(sys.argv) > 7 else 2500
assert not os.path.exists(out), out
files = sorted(glob.glob(os.path.join(src, "f*.png")))
if ":" in stride:                       # segments "a:b:s,c:d:t" (frame index ranges with their own strides)
    sel = []
    for seg in stride.split(","):
        a0, b0, s0 = (int(v) for v in seg.split(":"))
        sel += files[a0:b0:s0]
else:
    sel = files[::int(stride)]
if sel[-1] != files[-1]:
    sel.append(files[-1])
first = Image.open(sel[0]).convert("RGB")
height = int(round(first.height * width / first.width / 2) * 2)
frames = [Image.open(f).convert("RGB").resize((width, height), Image.LANCZOS) for f in sel]
# shared palette from a mosaic of evenly spaced frames
pick = frames[:: max(1, len(frames) // 12)][:12]
keys = [k for k in os.environ.get("GIF_KEYS", "").split(",") if k]     # e.g. "#ec6048,#f0c83c": colours that must
mos = Image.new("RGB", (width, height * (len(pick) + (1 if keys else 0))))  # survive (legend swatches, overlay text)
for i, fr in enumerate(pick):
    mos.paste(fr, (0, i * height))
for j, k in enumerate(keys):                                            # one full-height band per key colour
    x0 = j * width // len(keys)
    mos.paste(Image.new("RGB", (width // len(keys) + 1, height), k), (x0, len(pick) * height))
pal = mos.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
q = [fr.quantize(palette=pal, dither=Image.Dither.NONE) for fr in frames]
dur = [ms] * len(q)
dur[-1] = hold
q[0].save(out, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=True, disposal=1)
print("%s: %d frames, %dx%d, %d colours, %.2f MB" % (out, len(q), width, height, colors, os.path.getsize(out) / 2**20))

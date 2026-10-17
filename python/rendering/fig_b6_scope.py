# -*- coding: utf-8 -*-
"""Box 6 (Limits): scope of the evidence along the capture sequence, plus a drawing-style notes block."""
import sys

from engfig import *

VER = sys.argv[1] if len(sys.argv) > 1 else "v1"
W, H = 1440, 1080
b = [defs()]
b.append(text(40, 70, "What is shown, and what is not", size=46, weight=600))
b.append(text(40, 116, "Scope of the evidence along the capture sequence (all in simulation).", size=27, fill=INK2))

PH = [  # (title lines, status, detail lines, style)
    (["Far-range", "rendezvous"], "NOT MODELLED", ["everything before", "about 10 m"], "hatch"),
    (["Terminal", "approach"], "THIS PAPER", ["from about 10 m to the handle:", "600-run frozen stress test;", "V3 met its criteria on 60 new trials"], "main"),
    (["Grasp of", "the handle"], "PROTOTYPE", ["MuJoCo arm, gripper,", "ROS 2 lockstep;", "not validated"], "proto"),
    (["After", "capture"], "FUTURE WORK", ["detumbling,", "stabilisation"], "hatch"),
]
x0, y0, hgt = 40, 170, 190
widths = [270, 420, 380, 250]
gap = 20
x = x0
for (tl, st, det, style), w in zip(PH, widths):
    if style == "main":
        b.append(rect(x, y0, w, hgt, stroke=V3, sw=4, fill="#EEF3F9"))
        col = V3
    elif style == "proto":
        b.append(rect(x, y0, w, hgt, stroke=INK, sw=2.4, fill=PAPER, dash="12 7"))
        col = INK
    else:
        b.append(rect(x, y0, w, hgt, stroke=INK3, sw=2, fill="url(#hatchl)"))
        col = INK2
    for i, t in enumerate(tl):
        b.append(text(x + 22, y0 + 52 + 40 * i, t, size=34, weight=600, fill=col if style == "main" else INK))
    b.append(text(x + 22, y0 + hgt - 26, st, size=24, weight=700, fill=col))
    for i, d in enumerate(det):
        b.append(text(x + 4, y0 + hgt + 46 + 32 * i, d, size=25, fill=INK if style in ("main", "proto") else INK2))
    if x + w + gap < x0 + sum(widths) + gap * 3:
        ax = x + w + gap / 2
        b.append(path("M %.1f %.1f L %.1f %.1f" % (ax - 8, y0 + hgt / 2 - 14, ax + 2, y0 + hgt / 2), stroke=INK, w=2.4))
        b.append(path("M %.1f %.1f L %.1f %.1f" % (ax - 8, y0 + hgt / 2 + 14, ax + 2, y0 + hgt / 2), stroke=INK, w=2.4))
    x += w + gap

# notes block (drawing convention)
ny = 560
b.append(line(40, ny - 34, W - 40, ny - 34, stroke=HAIR, w=1.4))
b.append(text(40, ny + 6, "NOTES", size=28, weight=700))
notes = [
    "Simulation only. The servicer is a point mass; target attitude, rate and the relative state are measured exactly.",
    "“No violation” is an observation over the inspected samples, not a proof.",
    "The barrier guarantee is continuous-time and conditional; the controller is sampled every 0.1 s.",
    "The random trials span an engineering envelope, not the statistics of real debris.",
    "“Robust” in the title names the robust-adaptive barrier construction, not task success.",
]
for i, n in enumerate(notes):
    yy = ny + 56 + 50 * i
    b.append(text(40, yy, "%d." % (i + 1), size=27, weight=700))
    b.append(text(82, yy, n, size=27))
yy = ny + 56 + 50 * len(notes) + 36
b.append(line(40, yy - 34, W - 40, yy - 34, stroke=HAIR, w=1.4))
b.append(text(40, yy + 6, "NEXT", size=28, weight=700))
nxt = ["navigation filter with realistic sensor noise", "one simulation from approach through grasp",
       "detumbling after the grasp", "compiled NMPC with a timing budget"]
for i, n in enumerate(nxt):
    xx = 40 + (i % 2) * 690
    yv = yy + 56 + 46 * (i // 2)
    b.append(line(xx, yv - 9, xx + 18, yv - 9, stroke=INK, w=3))
    b.append(text(xx + 30, yv, n, size=27))

out = "b6_scope_%s" % VER
open(out + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), out))
render(out + ".html", "png/%s.png" % out, W, H)
print("written png/%s.png" % out)

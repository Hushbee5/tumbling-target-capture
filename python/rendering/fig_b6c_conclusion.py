# -*- coding: utf-8 -*-
"""Box 6 face (Conclusion): three take-aways with their numbers, the contribution and the scope, in the poster style.
Numbers: frozen proposed method 200 runs (100 U + 100 M), no observed violation over the observed portion of each run
(paper Table 6); V3 on 60 new trials: no observed violation 60/60, milestone 57/60 (paper Table 7, val_numbers.json)."""
import json
import sys

from engfig import *

VER = sys.argv[1] if len(sys.argv) > 1 else "v1"
W, H = 1440, 1080
J = json.load(open(r"results\val_v3_report_A11\val_numbers.json", encoding="utf-8"))
A = J["arms"]["V3"]
assert (A["no_viol_k"], A["no_viol_n"], A["prox_k"], A["prox_n"]) == (60, 60, 57, 60)

b = [defs()]
b.append(text(40, 78, "Conclusion", size=52, weight=600))
b.append(line(40, 108, W - 40, 108, stroke=INK, w=2.5))

rows = [
    ("1", [("200/200", V3), ("60/60", V3)], "No observed violation",
     ["in every run of ours: the frozen method in the 600-run test,", "and the corrected V3 on 60 new trials"]),
    ("2", [("57/60", V3)], "The corrected V3 arrives",
     ["proximity milestone on new trials, protocol frozen first;", "the frozen version: 1 and 12 of 100"]),
    ("3", [("SIM", INK2)], "Honest scope",
     ["simulation only; point-mass servicer; exact sensing;", "guarantee conditional; the grasp is a prototype"]),
]
y = 150
RH = 236
for num, bigs, head, lines_ in rows:
    b.append(text(40, y + 52, num, size=34, weight=700, fill=INK2))
    if len(bigs) == 2:
        b.append(text(90, y + 92, bigs[0][0], size=70, weight=700, fill=bigs[0][1]))
        b.append(text(90, y + 172, bigs[1][0], size=70, weight=700, fill=bigs[1][1]))
        b.append(text(392, y + 90, "frozen method", size=23, fill=INK2))
        b.append(text(392, y + 170, "V3, new trials", size=23, fill=INK2))
    elif bigs[0][0] == "SIM":
        b.append(text(90, y + 104, "simulation", size=58, weight=700, fill=INK2))
        b.append(text(90, y + 170, "only", size=58, weight=700, fill=INK2))
    else:
        b.append(text(90, y + 136, bigs[0][0], size=108, weight=700, fill=bigs[0][1]))
    b.append(text(580, y + 78, head, size=44, weight=600))
    for i, s in enumerate(lines_):
        b.append(text(580, y + 126 + 38 * i, s, size=29, fill=INK2))
    y += RH
    b.append(line(40, y - 14, W - 40, y - 14, stroke=HAIR, w=1.4))
b.append(text(40, y + 34, "Contribution: an integrated architecture, predeclared tests reported with their unfavourable",
              size=27))
b.append(text(40, y + 72, "results, and a diagnosis of what limited them. Not new theory.", size=27))
b.append(text(40, H - 30, "hasanbarangurbuz58@gmail.com", size=24, fill=INK2))
b.append(text(W - 40, H - 30, "Sources: paper, Tables 6 and 7", size=22, fill=INK2, anchor="end"))

out = "b6c_conclusion_%s" % VER
open(out + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), out))
render(out + ".html", "png/%s.png" % out, W, H)
print("written png/%s.png" % out)

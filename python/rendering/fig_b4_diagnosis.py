# -*- coding: utf-8 -*-
"""Box 4 (Why, and the fix): three exploratory findings on the frozen runs and the four V3 changes they motivated.
Finding 1 uses the per-run maximum preview error of condition U (p1_diagnosis/p1_runs_wide.csv, max_e_p_cp; the same
for the three methods of a trial). Finding 3 marks the eight early-stopped proposed runs at their trial indices
(abort notes of 2026-09-26 and 2026-09-29). Finding 2 is a schematic of the replays in the paper's Fig. 9."""
import csv
import statistics
import sys

from engfig import *

VER = sys.argv[1] if len(sys.argv) > 1 else "v1"
W, H = 1440, 1080
WIDE = r"p1_diagnosis\p1_runs_wide.csv"
S_CAP = 0.106226
rows = [r for r in csv.DictReader(open(WIDE, encoding="utf-8")) if r["cond"] == "U" and r["method"] == "proposed"]
err = {int(r["trial"]): float(r["max_e_p_cp"]) for r in rows}
assert len(err) == 100
med = statistics.median(err.values())
assert abs(med - 0.714) < 0.001, med
n_out = sum(v > S_CAP for v in err.values())
STOPS = {"U": [29, 64], "M": [10, 26, 78, 90, 93, 99]}

b = [defs()]
b.append(text(40, 70, "Why it rarely arrived, and what V3 changes", size=46, weight=600))
b.append(text(40, 116, "Exploratory, post hoc diagnosis of the frozen runs. The changes were then tested once, on new "
              "trials (Box 5).", size=27, fill=INK2))


def finding(y, num, title):
    return (line(40, y, 40, y + 44, stroke=INK, w=5) +
            text(58, y + 34, num, size=34, weight=700) + text(92, y + 34, title, size=34, weight=600))


# ---- finding 1: preview error, real per-run values (condition U)
y1 = 160
b.append(finding(y1, "1", "The preview drifted"))
X0, X1 = 70, 740
XM = 1.7
X = lambda v: X0 + (X1 - X0) * v / XM
ya = y1 + 190
b.append(line(X0, ya, X1, ya, stroke=INK2, w=1.5))
for t in (0, 0.5, 1.0, 1.5):
    b.append(line(X(t), ya, X(t), ya + 8, stroke=INK2, w=1.5))
    b.append(text(X(t), ya + 36, ("%.1f m" % t) if t else "0", size=22, fill=INK2, anchor="middle"))
b.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.10"/>'
         % (X(0), y1 + 70, X(S_CAP) - X(0), ya - y1 - 70, KEEP))
b.append(line(X(S_CAP), y1 + 64, X(S_CAP), ya, stroke=KEEP, w=2.4))
b.append(text(X(S_CAP) + 8, y1 + 84, "0.106 m room", size=22, weight=600, fill=KEEP))
for tr, v in sorted(err.items()):
    jy = y1 + 104 + ((tr * 37) % 60)               # deterministic vertical jitter, no meaning
    b.append(circle(X(v), jy, 5.5, stroke=PAPER, sw=1.2, fill=INK, op=0.85))
b.append(line(X(med), y1 + 92, X(med), ya, stroke=V3, w=2.4, dash="6 4"))
b.append(text(X(med) + 8, y1 + 84, "median 0.71 m", size=22, weight=600, fill=V3))
b.append(text(70, ya + 74, "Maximum preview error in each of the 100 trials of condition U; %d exceed 0.106 m." % n_out,
              size=23, fill=INK2))

# ---- finding 2: handoff band out of reach (schematic of the replays)
y2 = 470
b.append(finding(y2, "2", "The handoff band was out of reach"))
gx0, gx1, gy0, gy1 = 80, 700, y2 + 70, y2 + 220
b.append(line(gx0, gy0 - 6, gx0, gy1, stroke=INK2, w=1.5))
b.append(line(gx0, gy1, gx1, gy1, stroke=INK2, w=1.5))
band_y0, band_y1 = gy1 - 26, gy1
b.append('<rect x="%d" y="%d" width="%d" height="%d" fill="%s" opacity="0.16"/>' % (gx0, band_y0, gx1 - gx0, band_y1 - band_y0, V3))
b.append(text(gx1 - 6, band_y0 + 20, "handoff band (0.1 mm)", size=20, weight=600, fill=V3, anchor="end"))
hold = band_y0 - 26
b.append(line(gx0, hold, gx1, hold, stroke=INK, w=1.5, dash="8 6"))
b.append(text(gx1 - 6, hold - 10, "standoff the tightened row allows", size=20, fill=INK, anchor="end"))
b.append(path("M %d %d C %d %d, %d %d, %d %d L %d %d" % (gx0 + 4, gy0, gx0 + 120, gy0 + 40, gx0 + 200, hold - 2,
                                                       gx0 + 330, hold + 1, gx1 - 10, hold + 1), stroke=INK, w=3.2))
b.append(text(gx0 - 8, gy0 + 8, "range", size=20, fill=INK2, anchor="end"))
b.append(text(gx1, gy1 + 30, "time", size=20, fill=INK2, anchor="end"))
b.append(text(70, gy1 + 64, "Schematic (paper, Fig. 9): held just outside the band in 2 of 4 replays.",
              size=23, fill=INK2))

# ---- finding 3: eight solver stops, at their trial indices
y3 = 790
b.append(finding(y3, "3", "Eight solver stops"))
bx0, bw = 120, 610
for j, cond in enumerate(("U", "M")):
    yy = y3 + 78 + 44 * j
    b.append(text(70, yy + 10, cond, size=26, weight=600, fill=INK2))
    for tr in range(1, 101):
        x = bx0 + bw * (tr - 0.5) / 100
        if tr in STOPS[cond]:
            b.append(line(x, yy - 16, x, yy + 16, stroke=INK, w=4))
        else:
            b.append(line(x, yy - 7, x, yy + 7, stroke=HAIR, w=2))
b.append(text(70, y3 + 200, "Trials 1\u2013100; dark ticks = stopped early. At each stop, an LP check found a command "
              "meeting both rows.", size=23, fill=INK2))

# ---- the four changes
def fix(y, tagl, title, sub):
    o = [rect(860, y, 540, 112, stroke=INK, sw=2.4, fill=PAPER)]
    x = 860 + 34
    for t in tagl:
        o.append(rect(x - 19, y + 37 - 19, 38, 38, stroke=INK, sw=0, fill=INK))
        o.append(text(x, y + 47, t, size=28, weight=700, fill=PAPER, anchor="middle"))
        x += 46
    o.append(text(x - 8, y + 47, title, size=28, weight=600))
    o.append(text(880, y + 90, sub, size=22, fill=INK2))
    return "".join(o)


b.append(text(860, 196, "V3 CHANGES", size=24, weight=600, fill=INK2))
b.append(fix(214, "P", "Preview re-anchored", "every 0.1 s on the measured attitude and rate"))
b.append(fix(500, "H", "Reachable handoff", "release where the servicer can actually get to"))
b.append(fix(626, "A", "Authority gate", "release only with a 30 % braking reserve"))
b.append(fix(818, "Q", "Exact QP", "active-set solve, KKT-checked; fallbacks counted"))
for (ya_, yb_) in ((300, 270), (580, 556), (580, 682), (880, 874)):
    b.append(path("M %d %d L %d %d L %d %d L %d %d" % (770, ya_, 812, ya_, 812, yb_, 856, yb_), stroke=INK, w=2.2,
                  marker_end="arr_l"))

b.append(line(40, 1010, W - 40, 1010, stroke=HAIR, w=1.4))
b.append(text(40, 1046, "The 600 old runs are now development data. V3 was frozen, then evaluated once on 60 new "
              "trials drawn afterwards.", size=23, fill=INK2))

out = "b4_diagnosis_%s" % VER
open(out + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), out))
render(out + ".html", "png/%s.png" % out, W, H)
print("written png/%s.png  median %.3f  exceed %d" % (out, med, n_out))

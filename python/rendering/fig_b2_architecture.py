# -*- coding: utf-8 -*-
"""Box 2 (Our approach): block diagram of the two-layer architecture as corrected in V3 (paper Sections 3 and 5.10).
Tags P, H, A, Q mark the four V3 changes."""
import sys

from engfig import *

VER = sys.argv[1] if len(sys.argv) > 1 else "v1"
W, H = 1440, 1080
b = [defs()]


def block(x, y, w, h, title, lines=(), fill=PAPER, sw=2.6, tsize=30):
    o = [rect(x, y, w, h, stroke=INK, sw=sw, fill=fill)]
    o.append(text(x + 18, y + 46, title, size=tsize, weight=600))
    for i, s in enumerate(lines):
        o.append(text(x + 18, y + 46 + 36 + 30 * i, s, size=23, fill=INK2))
    return "".join(o)


def tag(x, y, letter):
    return rect(x - 19, y - 19, 38, 38, stroke=INK, sw=0, fill=INK) + text(x, y + 10, letter, size=28, weight=700,
                                                                          fill=PAPER, anchor="middle")


def sig(d, label=None, lx=0, ly=0, anchor="middle", italic=True):
    o = [path(d, stroke=INK, w=2.4, marker_end="arr_l")]
    if label:
        o.append(text(lx, ly, label, size=26, fill=INK, anchor=anchor, italic=italic))
    return "".join(o)


SAFE_FILL = "#EEF3F9"
MTH = '<tspan font-family="Cambria Math" font-style="italic">θ̂</tspan>'
MNU = '<tspan font-family="Cambria Math" font-style="italic">ν</tspan>'
# blocks
T = (40, 160, 250, 160)
P = (360, 160, 300, 160)
M = (730, 160, 290, 160)
Q = (1090, 130, 310, 430)
S = (1090, 680, 310, 140)
E = (360, 470, 300, 160)
HA = (730, 470, 290, 160)
b.append(block(*T, "Target (truth)", ["tumbling rigid body", "inertia uncertain"]))
b.append(block(*P, "Preview", ["capture-point path, 10 s", "re-anchored every 0.1 s"]))
b.append(block(*M, "Linear MPC", ["Clohessy–Wiltshire,", "re-solved every 0.1 s"]))
b.append(block(*Q, "Safety filter", ["HOCBF quadratic program:", "smallest change to the", "MPC command"], fill=SAFE_FILL))
# the two constraint rows inside the filter
for i, (t1, t2) in enumerate((("row 2  commitment", "until the handoff"), ("row 1  body keep-out", "always enforced"))):
    yy = Q[1] + 230 + 92 * i
    b.append(rect(Q[0] + 18, yy, Q[2] - 36, 78, stroke=INK2, sw=1.6, fill=PAPER))
    b.append(text(Q[0] + 32, yy + 33, t1, size=24, weight=600, fill=V3 if i == 0 else KEEP))
    b.append(text(Q[0] + 32, yy + 63, t2, size=22, fill=INK2))
b.append(block(*S, "Servicer", ["point mass"]))
b.append(block(*E, "Estimator", ["inertia ratios " + MTH + " (scale-free)", "and an error bound " + MNU]))
b.append(block(*HA, "Handoff gate", ["reachable boundary (H)", "braking reserve (A)"]))

# signals
yT = T[1] + 70
b.append(sig("M %d %d L %d %d" % (T[0] + T[2], yT, P[0], yT), "q, ω", (T[0] + T[2] + P[0]) / 2, yT - 14))
b.append(sig("M %d %d L %d %d" % (P[0] + P[2], yT, M[0], yT), "path", (P[0] + P[2] + M[0]) / 2, yT - 14))
b.append(sig("M %d %d L %d %d" % (M[0] + M[2], yT, Q[0], yT), 'u<tspan baseline-shift="sub" font-size="19">nom</tspan>', (M[0] + M[2] + Q[0]) / 2, yT - 14))
# target -> estimator (measured attitude and rate)
b.append(sig("M %d %d L %d %d L %d %d" % (T[0] + 135, T[1] + T[3], T[0] + 135, E[1] + 80, E[0], E[1] + 80),
             "q, ω", T[0] + 150, E[1] + 64, anchor="start"))
# estimator -> preview (theta hat)
b.append(sig("M %d %d L %d %d" % (P[0] + 150, E[1], P[0] + 150, P[1] + P[3]), MTH, P[0] + 166, E[1] - 52,
             anchor="start"))
# estimator -> filter row 2 (theta hat, nu), routed between the two block rows
yr = Q[1] + 230 + 22
b.append(sig("M %d %d L %d %d L %d %d" % (E[0] + E[2] - 40, E[1], E[0] + E[2] - 40, yr, Q[0], yr),
             MTH + ", " + MNU, (M[0] + M[2] / 2), yr - 12))
# handoff gate -> filter row 2 (release)
yh = Q[1] + 230 + 58
b.append(sig("M %d %d L %d %d L %d %d" % (HA[0] + HA[2] - 40, HA[1], HA[0] + HA[2] - 40, yh, Q[0], yh)))
b.append(text(HA[0] + HA[2] - 28, yh + 32, "release", size=22, fill=INK, anchor="start"))
# filter -> servicer
b.append(sig("M %d %d L %d %d" % (Q[0] + Q[2] / 2, Q[1] + Q[3], S[0] + S[2] / 2, S[1]), "u", Q[0] + Q[2] / 2 + 16,
             (Q[1] + Q[3] + S[1]) / 2 + 10, anchor="start"))
# state feedback: servicer -> top bus -> MPC and filter
yb = 70
xr = 1426
b.append(path("M %d %d L %d %d L %d %d L %d %d" % (S[0] + S[2], S[1] + 75, xr, S[1] + 75, xr, yb, M[0] + M[2] / 2, yb),
              stroke=INK, w=2.4))
b.append(sig("M %d %d L %d %d" % (M[0] + M[2] / 2, yb, M[0] + M[2] / 2, M[1])))
b.append(circle(Q[0] + Q[2] - 26, yb, 6, stroke="none", sw=0, fill=INK))
b.append(sig("M %d %d L %d %d" % (Q[0] + Q[2] - 26, yb, Q[0] + Q[2] - 26, Q[1])))
b.append(text(M[0] + M[2] / 2 + 14, yb - 14, "x  relative position and velocity (measured)", size=24, fill=INK,
              anchor="start", italic=True))

# layer labels
b.append(text(P[0] + 30, P[1] - 16, "UPPER LAYER  ·  tracking", size=24, weight=600, fill=INK2))
b.append(text(Q[0] + 30, Q[1] - 16, "LOWER LAYER  ·  safety", size=24, weight=600, fill=INK2))

# V3 change tags
b.append(tag(P[0], P[1], "P"))
b.append(tag(HA[0], HA[1], "H"))
b.append(tag(HA[0] + 46, HA[1], "A"))
b.append(tag(Q[0], Q[1], "Q"))

# key (drawing notes)
ky = 900
b.append(line(40, ky - 40, W - 40, ky - 40, stroke=HAIR, w=1.4))
b.append(tag(58, ky - 8, "P") + text(92, ky + 2, "preview re-anchored every 0.1 s (was computed once)", size=25))
b.append(tag(58, ky + 42, "H") + text(92, ky + 52, "handoff on the boundary the servicer can actually reach", size=25))
b.append(tag(760, ky - 8, "A") + text(794, ky + 2, "release only with a 30 % braking reserve", size=25))
b.append(tag(760, ky + 42, "Q") + text(794, ky + 52, "exact QP solve; every fallback counted", size=25))
b.append(text(40, ky + 112, "Tags mark the four V3 changes (paper, Section 5.10); the frozen 600-run test ran "
              "without them. The handoff gate also reads x and the path.", size=22, fill=INK2))
b.append(text(40, ky + 144, "Barrier guarantees are continuous-time and conditional; the controller is sampled every "
              "0.1 s.", size=22, fill=INK2))

out = "b2_architecture_%s" % VER
open(out + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), out))
render(out + ".html", "png/%s.png" % out, W, H)
print("written png/%s.png" % out)

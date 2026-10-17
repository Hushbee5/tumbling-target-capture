# -*- coding: utf-8 -*-
"""Box 1 (The challenge): planar section of the capture geometry, drawn to scale from the paper's Table 1 and the
render scene (target sphere 0.5 m, handle at |p_b| = 0.806 m, keep-out r_safe = 0.70 m, s_cap = 0.106 m)."""
import math
import sys

from engfig import *

VER = sys.argv[1] if len(sys.argv) > 1 else "v1"
W, H = 1440, 1080
S = 520.0                                  # px per metre (main view)
CX, CY = 500.0, 540.0
R_SAFE, P_B, R_BODY, S_CAP = 0.70, 0.806, 0.50, 0.106226
TH = 22.0                                  # handle direction [deg]


def pt(r_m, ang, cx=CX, cy=CY, s=S):
    return cx + r_m * s * math.cos(math.radians(ang)), cy - r_m * s * math.sin(math.radians(ang))


def sub(base, s, size=24, italic=True):
    it = ' font-style="italic"' if italic else ""
    return '<tspan%s>%s</tspan><tspan baseline-shift="sub" font-size="%d">%s</tspan>' % (it, base, size, s)


b = [defs()]
# capture-point locus (the handle sweeps this sphere as the target tumbles)
b.append(circle(CX, CY, P_B * S, stroke=INK3, sw=1.6, dash="3 9"))
# keep-out sphere: tinted disc + boundary
b.append(circle(CX, CY, R_SAFE * S, stroke="none", sw=0, fill=KEEP, op=0.07))
b.append(circle(CX, CY, R_SAFE * S, stroke=KEEP, sw=3, dash="18 8"))
# target body (sphere) with section hatching and two panel seams that show its attitude
b.append(circle(CX, CY, R_BODY * S, stroke=INK, sw=3, fill="url(#hatchl)"))
for a in (TH + 62, TH - 48):
    x0, y0 = pt(R_BODY, a)
    x1, y1 = pt(R_BODY, a + 180)
    b.append(line(x0, y0, x1, y1, stroke=INK3, w=1.6))
b.append(line(CX - 26, CY, CX + 26, CY, stroke=INK, w=1.6))
b.append(line(CX, CY - 26, CX, CY + 26, stroke=INK, w=1.6))
# handle: rod from the surface to p_b, knob, centre mark at the capture point
hx0, hy0 = pt(R_BODY, TH)
px, py = pt(P_B, TH)
b.append(line(hx0, hy0, px, py, stroke=INK, w=7, cap="round"))
b.append(circle(px, py, 12, stroke=INK, sw=3, fill=PAPER))
b.append(line(px - 22, py, px + 22, py, stroke=INK, w=1.6))
b.append(line(px, py - 22, px, py + 22, stroke=INK, w=1.6))
b.append(circle(px, py, S_CAP * S, stroke=V3, sw=2.4, dash="10 6"))

# rotation arrow (tumbling)
b.append(path(arc(CX, CY, 0.585 * S, 130, 198), stroke=INK, w=2.6, marker_end="arr_l"))
lx, ly = pt(0.64, 160)
b.append(text(lx - 8, ly, "ω", size=48, anchor="end", italic=True))

# servicer: 0.24 m box with two panels (to scale), approaching along a curved path
sx, sy = 1215.0, 230.0
hs = 0.12 * S
pw, pl = 0.17 * S, 0.27 * S
b.append(rect(sx - hs, sy - hs, 2 * hs, 2 * hs, stroke=INK, sw=3, fill="#EFEBE1"))
b.append(rect(sx - hs - 0.03 * S - pl, sy - pw / 2, pl, pw, stroke=INK, sw=2, fill="url(#hatch)"))
b.append(rect(sx + hs + 0.03 * S, sy - pw / 2, pl, pw, stroke=INK, sw=2, fill="url(#hatch)"))
b.append(line(sx - hs, sy, sx - hs - 0.03 * S, sy, stroke=INK, w=2))
b.append(line(sx + hs, sy, sx + hs + 0.03 * S, sy, stroke=INK, w=2))
b.append(text(sx, sy - hs - 50, "servicer", size=34, weight=600, anchor="middle"))
b.append(text(sx, sy - hs - 16, "a point mass in the controller", size=26, fill=INK2, anchor="middle"))
ang_end = 38.0
ex, ey = px + (S_CAP * S + 14) * math.cos(math.radians(ang_end)), py - (S_CAP * S + 14) * math.sin(math.radians(ang_end))
b.append(path("M %.1f %.1f C %.1f %.1f, %.1f %.1f, %.1f %.1f" % (sx - 40, sy + hs + 6, sx - 70, sy + 150,
                                                                  ex + 120, ey - 20, ex + 6, ey - 4),
              stroke=V3, w=3, dash="14 8", marker_end="arrv3_l"))

# ---- dimensions
a = 214.0                                  # r_safe, radial, inside the keep-out disc
x1, y1 = pt(R_SAFE, a)
b.append(line(CX, CY, x1, y1, stroke=KEEP, w=2, marker_end="arrk"))
tx, ty = pt(R_SAFE * 0.55, a)
b.append('<g transform="rotate(%.2f %.1f %.1f)">' % (-(a - 180), tx, ty))
b.append(text(tx, ty - 12, sub("r", "safe") + " = 0.70 m", size=34, weight=600, fill=KEEP, anchor="middle"))
b.append('</g>')
off = 64                                   # |p_b|, aligned dimension offset from the handle axis
nx, ny = -math.sin(math.radians(TH)) * off, -math.cos(math.radians(TH)) * off
b.append(line(CX + nx, CY + ny, px + nx, py + ny, stroke=INK, w=1.6, marker_end="arr", marker_start="arr"))
b.append(line(CX + nx * 0.25, CY + ny * 0.25, CX + nx * 1.2, CY + ny * 1.2, stroke=INK2, w=1.2))
b.append(line(px + nx * 0.4, py + ny * 0.4, px + nx * 1.2, py + ny * 1.2, stroke=INK2, w=1.2))
mx, my = CX + 0.42 * (px - CX) + nx, CY + 0.42 * (py - CY) + ny
b.append('<g transform="rotate(%.2f %.1f %.1f)">' % (-TH, mx, my))
b.append(text(mx, my - 12, "|" + sub("p", "b") + "| = 0.806 m", size=34, weight=600, anchor="middle"))
b.append('</g>')


def leader(x0, y0, x1, y1, label, subl=None, col=INK, anchor="start", size=32):
    """Leader with a horizontal shoulder; the label sits at the end of the shoulder (drawing convention)."""
    sh = 26 if anchor == "start" else -26
    o = [path("M %.1f %.1f L %.1f %.1f L %.1f %.1f" % (x0, y0, x1, y1, x1 + sh, y1), stroke=INK2, w=1.4),
         circle(x0, y0, 3.5, stroke="none", sw=0, fill=INK2)]
    tx = x1 + sh + (8 if anchor == "start" else -8)
    o.append(text(tx, y1 + size * 0.34, label, size=size, weight=600, fill=col, anchor=anchor))
    if subl:
        o.append(text(tx, y1 + size * 0.34 + size * 1.12, subl, size=size - 6, fill=INK2, anchor=anchor))
    return "".join(o)


b.append(leader(px - 6, py - 12, 760, 52, "handle = capture point", "fixed on the body, so it moves", anchor="end"))
lx2, ly2 = pt(P_B, 128)
b.append(leader(lx2, ly2, 340, 96, "capture-point locus", anchor="end", size=28))
bx, by = pt(0.46, 236)
b.append(leader(bx, by, 420, 975, "target", "tumbling; inertia uncertain", anchor="end"))
kx, ky = pt(R_SAFE, 300)
b.append(leader(kx, ky, 600, 975, "keep-out sphere", "must never be entered", col=KEEP))

# ---- detail A: the 0.106 m of room
dax, day = pt(P_B - S_CAP / 2, TH)
b.append(circle(dax, day, 70, stroke=INK, sw=1.6, dash="6 5"))
b.append(text(dax + 30, day + 104, "A", size=34, weight=700, anchor="middle"))
IX, IY, IW, IH = 1000, 430, 410, 500
Z = 3.0
icx, icy = IX + 300, IY + 320
b.append(line(dax + 58, day + 40, IX, IY + 120, stroke=INK2, w=1.4))
b.append(rect(IX, IY, IW, IH, stroke=INK, sw=2, fill=PAPER))
cxz = icx - P_B * S * Z
b.append('<clipPath id="clipA"><rect x="%d" y="%d" width="%d" height="%d"/></clipPath>' % (IX + 2, IY + 2, IW - 4, IH - 4))
b.append('<g clip-path="url(#clipA)">')
b.append(circle(cxz, icy, R_SAFE * S * Z, stroke="none", sw=0, fill=KEEP, op=0.07))
b.append(circle(cxz, icy, R_SAFE * S * Z, stroke=KEEP, sw=3, dash="18 8"))
b.append(circle(icx, icy, S_CAP * S * Z, stroke=V3, sw=2.4, dash="10 6"))
b.append(line(IX, icy, icx, icy, stroke=INK, w=10))
b.append(circle(icx, icy, 26, stroke=INK, sw=3, fill=PAPER))
b.append(line(icx - 40, icy, icx + 40, icy, stroke=INK, w=1.6))
b.append(line(icx, icy - 40, icx, icy + 40, stroke=INK, w=1.6))
b.append('</g>')
xk = cxz + R_SAFE * S * Z
ydim = icy - S_CAP * S * Z - 46
b.append(line(xk, icy - 8, xk, ydim - 18, stroke=INK2, w=1.2))
b.append(line(icx, icy - 44, icx, ydim - 18, stroke=INK2, w=1.2))
b.append(line(xk, ydim, icx, ydim, stroke=INK, w=2, marker_end="arr", marker_start="arr"))
b.append(text((xk + icx) / 2, ydim - 22, "0.106 m", size=56, weight=700, anchor="middle"))
b.append(text(IX + IW - 16, IY + 38, "DETAIL A  (3 : 1)", size=26, weight=600, fill=INK2, anchor="end"))
b.append(text(IX, IY + IH + 40, "proximity milestone:", size=28, weight=600, fill=V3))
b.append(text(IX, IY + IH + 76, "within 0.106 m of the handle", size=28, fill=V3))

b.append(text(40, H - 18, "Planar section of the 3-D geometry, to scale (paper, Table 1). All values simulated.",
              size=21, fill=INK2))

out = "b1_geometry_%s" % VER
open(out + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), out))
render(out + ".html", "png/%s.png" % out, W, H)
print("written png/%s.png" % out)

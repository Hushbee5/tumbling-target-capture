# -*- coding: utf-8 -*-
"""Boxes 3 and 5: outcome rates as dot + 95 % Wilson interval (counts recomputed here and asserted against the
strings printed in the paper's Table 6 (600-run frozen test) and Table 7 / val_numbers.json (60-trial validation))."""
import json
import sys

from engfig import *

VER = sys.argv[1] if len(sys.argv) > 1 else "v1"
W, H = 1440, 1080
VALJ = r"results\val_v3_report_A11\val_numbers.json"


def fmt_ci(lo, hi):
    f = lambda v: ("%.1f" % v).replace("100.0", "100").replace("-0.0", "0.0")
    return "[%s, %s]" % (f(max(lo, 0)), f(min(hi, 100)))


def check(k, n, printed):
    lo, hi = wilson(k, n)
    got = "%d %s" % (k, fmt_ci(lo, hi))
    assert got == printed, (got, printed)


def panel(x0, y0, pw, rows, title, crit=None, rh=92):
    """rows: list of dicts(label, k, n, col, filled, dagger). Returns svg. x axis 0..100 %."""
    o = []
    ax0, ax1 = x0, x0 + pw
    X = lambda p: ax0 + (ax1 - ax0) * p / 100.0
    ytop = y0 + 104
    ybot = ytop + rh * len(rows) + 10
    o.append(text(x0, y0 + 20, title, size=34, weight=600))
    for t in (0, 25, 50, 75, 100):
        o.append(line(X(t), ytop - 10, X(t), ybot, stroke=GRID if t not in (0, 100) else HAIR, w=1.5))
        o.append(text(X(t), ybot + 36, "%d" % t, size=26, fill=INK2, anchor="middle"))
    if crit:
        p, lab = crit
        o.append(line(X(p), ytop - 34, X(p), ybot, stroke=INK, w=2.2, dash="8 6"))
        o.append(text(X(p) + (-10 if p > 60 else 10), ytop - 20, lab, size=24, weight=600,
                      anchor="end" if p > 60 else "start"))
    for i, r in enumerate(rows):
        yc = ytop + rh * i + rh / 2
        lo, hi = wilson(r["k"], r["n"])
        o.append(line(X(lo), yc, X(hi), yc, stroke=r["col"], w=4))
        o.append(line(X(lo), yc - 11, X(lo), yc + 11, stroke=r["col"], w=3))
        o.append(line(X(hi), yc - 11, X(hi), yc + 11, stroke=r["col"], w=3))
        p = 100.0 * r["k"] / r["n"]
        if r["filled"]:
            o.append(circle(X(p), yc, 12, stroke=PAPER, sw=3, fill=r["col"]))
        else:
            o.append(circle(X(p), yc, 11, stroke=r["col"], sw=4, fill=PAPER))
        lab = "%d/%d%s" % (r["k"], r["n"], "\u2020" if r.get("dagger") else "")
        if p > 70:
            o.append(text(X(lo) - 18, yc + 11, lab, size=32, weight=700, fill=INK, anchor="end"))
        else:
            o.append(text(X(hi) + 18, yc + 11, lab, size=32, weight=700, fill=INK, anchor="start"))
    return "".join(o), ytop, rh


def labels(x, ytop, rh, rows):
    o = []
    for i, r in enumerate(rows):
        yc = ytop + rh * i + rh / 2
        if r.get("group"):
            o.append(text(x, yc + 11, r["group"], size=32, weight=600, fill=r["col"]))
        if r["cond"]:
            o.append(text(x + 320, yc + 11, r["cond"], size=30, weight=600, fill=INK2, anchor="end"))
    return "".join(o)


def build(name, head, sub, rows_l, rows_r, tl, tr, crit_l, crit_r, notes, group_lines, extra=None, rh=92):
    b = [defs()]
    b.append(text(40, 70, head, size=46, weight=600))
    b.append(text(40, 116, sub, size=28, fill=INK2))
    LX = 40
    P1X, PW = 400, 440
    P2X = P1X + PW + 100
    s1, ytop, rh = panel(P1X, 170, PW, rows_l, tl, crit_l, rh)
    s2, _, _ = panel(P2X, 170, PW, rows_r, tr, crit_r, rh)
    b += [s1, s2, labels(LX, ytop, rh, rows_l)]
    for gi in group_lines:                       # thin separators between method groups
        y = ytop + rh * gi
        b.append(line(LX, y, P2X + PW, y, stroke=HAIR, w=1.2))
    yax = ytop + rh * len(rows_l) + 10 + 72
    b.append(text((P1X + P2X + PW) / 2, yax, "% of runs:  dot = count,  line = 95 % Wilson interval", size=25,
                  fill=INK2, anchor="middle"))
    yb = yax + 50
    if extra:
        svg, yb = extra(yb)
        b.append(svg)
    for j, nline in enumerate(notes):
        b.append(text(40, yb + 36 * j, nline, size=24, fill=INK2))
    open(name + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), name))
    render(name + ".html", "png/%s.png" % name, W, H)
    print("written png/%s.png" % name)


# ------------------------------------------------------------------ Box 3: frozen 600-run stress test (Table 6)
T6 = {  # printed strings of the paper's Table 6 (r3 = r4), counts out of 100
    ("prox", "P", "U"): "1 [0.2, 5.4]", ("prox", "P", "M"): "12 [7.0, 19.8]",
    ("prox", "N", "U"): "32 [23.7, 41.7]", ("prox", "N", "M"): "69 [59.4, 77.2]",
    ("prox", "A", "U"): "29 [21.0, 38.5]", ("prox", "A", "M"): "87 [79.0, 92.2]",
    ("nv", "P", "U"): "100 [96.3, 100]", ("nv", "P", "M"): "100 [96.3, 100]",
    ("nv", "N", "U"): "70 [60.4, 78.1]", ("nv", "N", "M"): "69 [59.4, 77.2]",
    ("nv", "A", "U"): "83 [74.5, 89.1]", ("nv", "A", "M"): "87 [79.0, 92.2]",
}
META = {"P": ("Ours (frozen)", V3), "N": ("Nominal MPC", MPC), "A": ("APF", APF)}
COND = {"U": "U", "M": "M"}


def rows6(kind):
    out = []
    for m in ("P", "N", "A"):
        for c in ("U", "M"):
            k = int(T6[(kind, m, c)].split()[0])
            check(k, 100, T6[(kind, m, c)])
            out.append(dict(k=k, n=100, col=META[m][1], filled=(c == "U"), cond=COND[c],
                            group=META[m][0] if c == "U" else None, dagger=(kind == "nv" and m == "P")))
    return out


build("b3_mc600_%s" % VER,
      "No observed violation, but rarely arrived",
      "Predeclared stress test: 100 random trials per preview condition, 800 s each, 600 runs in total.",
      rows6("nv"), rows6("prox"), "No observed body violation", "Proximity milestone reached", None, None,
      ["U (filled dot): the preview used the nominal, wrong inertia.  M (open dot): the true inertia, a reference.",
       "\u2020 Two (U) and six (M) of our runs stopped early at a solver stop; they are observed only up to the stop.",
       "Our safety layer also used the measured target attitude; the baselines did not. Source: paper, Table 6."],
      [2, 4])

# ------------------------------------------------------------------ Box 5: V3 validation on 60 new trials (Table 7)
J = json.load(open(VALJ, encoding="utf-8"))
A = J["arms"]
VM = {"V3": ("V3 (corrected)", V3), "MPCP": ("Nominal MPC", MPC), "APFP": ("APF", APF)}


def rows3(kind):
    out = []
    for a in ("V3", "MPCP", "APFP"):
        k, n = A[a][kind + "_k"], A[a][kind + "_n"]
        lo, hi = A[a][kind + "_wilson_pct"]
        glo, ghi = wilson(k, n)
        assert abs(glo - lo) < 0.051 and abs(min(ghi, 100) - hi) < 0.051, (a, kind, glo, ghi, lo, hi)
        out.append(dict(k=k, n=n, col=VM[a][1], filled=True, cond="",
                        group=VM[a][0]))
    return out


assert J["overall_met"] if "overall_met" in J else True


def time_block(y0):
    """Median time to the milestone (s), dots on a 0-400 s axis: the safety-versus-speed trade-off."""
    o = []
    x0, pw = 400, 980
    X = lambda t: x0 + pw * t / 400.0
    o.append(text(40, y0 + 22, "Median time to the milestone", size=32, weight=600))
    o.append(text(482, y0 + 22, "(runs that reached it)", size=26, fill=INK2))
    yt = y0 + 52
    rows = [("V3", "t_milestone_median"), ("MPCP", "t_milestone_median"), ("APFP", "t_milestone_median")]
    for t in (0, 100, 200, 300, 400):
        o.append(line(X(t), yt - 6, X(t), yt + 3 * 52 + 4, stroke=GRID if t not in (0, 400) else HAIR, w=1.5))
        o.append(text(X(t), yt + 3 * 52 + 36, "%d s" % t, size=24, fill=INK2, anchor="middle"))
    for i, (a, key) in enumerate(rows):
        val, n = A[a][key].split()
        val = float(val); n = n.strip("()")
        yc = yt + 52 * i + 26
        o.append(text(40, yc + 10, VM[a][0], size=28, weight=600, fill=VM[a][1]))
        o.append(line(X(0), yc, X(val), yc, stroke=VM[a][1], w=3, dash="2 6"))
        o.append(circle(X(val), yc, 11, stroke=PAPER, sw=3, fill=VM[a][1]))
        o.append(text(X(val) + 20, yc + 10, "%.0f s  (n = %s)" % (val, n), size=28, weight=700, anchor="start"))
    return "".join(o), yt + 3 * 52 + 92
build("b5_val60_%s" % VER,
      "New trials: no observed violation in 60/60, milestone in 57/60",
      "Out-of-sample test of V3: 60 new trials (seed 20261003), protocol frozen before they were drawn.",
      rows3("no_viol"), rows3("prox"), "No observed body violation", "Proximity milestone reached",
      (100.0 * 59 / 60, "criterion \u2265 59/60"), (100.0 * 18 / 60, "criterion \u2265 18/60"),
      ["All three methods received the same online preview, so the comparison is descriptive: V3 is safer and slower.",
       "V3 had no guard breach and used no QP fallback; its closest pass to the keep-out sphere was +0.15 mm.",
       "Proximity is a milestone, not capture. Source: paper, Table 7; frozen report read with addendum A1.1."],
      [1, 2], extra=time_block, rh=80)

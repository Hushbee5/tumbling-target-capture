# -*- coding: utf-8 -*-
"""Box 5 video: the 60 new validation trials replayed side by side for V3, the nominal MPC and the APF (same preview).
READ-ONLY: every number comes from results/val_v3/O_t###_{V3,MPCP,APFP}.mat (frozen run files); nothing is simulated.
Top row: clearance to the keep-out sphere, |r| - r_safe, at the 8001 control samples of every run (r = X[0:3], the
servicer position relative to the target centre in LVLH). A run turns red from its first observed violation, taken as
the earliest sample or intersample point (inter_h_body: 9 points per interval at +0.01 ... +0.09 s) with h_body < 0.
Bottom row: running counts of runs with a violation and of runs that reached the proximity milestone (S.t_kstar).
Checks: for every run, "violation found" equals (S.no_viol == 0); per arm, the counts equal the frozen report
(no violation 60/45/52, milestone 57/45/52); for V3, the computed clearance equals the stored H.d_safe.
Outputs (never overwritten): <out>.mp4 (1920x1080, 30 fps), <out>_final.png, <out>_gifframes/ (every 3rd frame).
Usage: python anim_val60.py <out_basename>"""
import os
import sys

import imageio.v2 as iio
import matplotlib
import numpy as np
import scipy.io as sio

matplotlib.use("Agg")
import matplotlib.pyplot as plt                                  # noqa: E402
from matplotlib import font_manager                             # noqa: E402

out = sys.argv[1]
for ext in (".mp4", "_final.png", "_gifframes"):
    assert not os.path.exists(out + ext), out + ext
os.makedirs(out + "_gifframes")
font_manager.fontManager.addfont(r"C:\Windows\Fonts\bahnschrift.ttf")
plt.rcParams.update({"font.family": ["Bahnschrift", "Segoe UI"], "axes.edgecolor": "#8A939C", "axes.linewidth": 1.0,
                     "xtick.color": "#56606B", "ytick.color": "#56606B", "axes.labelcolor": "#56606B"})

RES = r"results\val_v3"
R_SAFE = 0.70
INK, INK2, HAIR, KEEP = "#1D232B", "#56606B", "#C9CED4", "#B3392B"
ARMS = [("V3", "V3 (corrected)", "#1D5FA8"), ("MPCP", "Nominal MPC", "#C47500"), ("APFP", "APF", "#00896B")]
EXPECT = {"V3": (60, 57), "MPCP": (45, 45), "APFP": (52, 52)}

t = None
data = {}
for arm, _, _ in ARMS:
    runs = []
    for tr in range(1, 61):
        d = sio.loadmat(os.path.join(RES, "O_t%03d_%s.mat" % (tr, arm)), squeeze_me=True, struct_as_record=False)
        S, Hh = d["S"], d["H"]
        tt = np.asarray(Hh.t, float)
        if t is None:
            t = tt
        assert tt.shape == (8001,) and np.array_equal(tt, t)
        r = np.asarray(Hh.X, float)[:3, :]
        clr = np.linalg.norm(r, axis=0) - R_SAFE
        if arm == "V3":
            assert np.max(np.abs(clr - np.asarray(Hh.d_safe, float))) < 1e-9
        ih = np.asarray(Hh.inter_h_body, float)
        assert ih.shape == (72000,)
        tv = np.inf
        js = np.nonzero(clr < 0)[0]
        if js.size:
            tv = t[js[0]]
        ji = np.nonzero(ih < 0)[0]
        if ji.size:
            tv = min(tv, (ji[0] // 9) * 0.1 + ((ji[0] % 9) + 1) * 0.01)
        assert np.isfinite(tv) == (int(S.no_viol) == 0), (arm, tr, tv, S.no_viol)
        tm = float(S.t_kstar) if int(S.prox) == 1 else np.inf
        runs.append(dict(clr=clr, tv=tv, tm=tm))
    nv = sum(not np.isfinite(r_["tv"]) for r_ in runs)
    npx = sum(np.isfinite(r_["tm"]) for r_ in runs)
    assert (nv, npx) == EXPECT[arm], (arm, nv, npx)
    data[arm] = runs
print("checks passed: violation sets and counts equal the frozen report")

# ---------------------------------------------------------------- figure
W, H, DPI = 1920, 1080, 100
fig = plt.figure(figsize=(W / DPI, H / DPI), dpi=DPI, facecolor="white")
fig.text(0.036, 0.952, "OUT-OF-SAMPLE VALIDATION  \u00b7  60 NEW TRIALS (SEED 20261003)  \u00b7  SAME ONLINE PREVIEW FOR ALL",
         fontsize=14, color=INK2)
fig.text(0.036, 0.900, "Sixty new trials, replayed side by side", fontsize=30, color=INK)
fig.text(0.036, 0.866, "Top: every run's distance to the keep-out sphere; below zero means inside it (a violation). "
         "Bottom: running counts.", fontsize=15, color=INK2)
tclock = fig.text(0.964, 0.900, "", fontsize=30, color=INK, ha="right")
ix = np.arange(0, 8001, 5)                                       # 0.5 s plotting grid
tp = t[ix]
axs, lines, counters = [], {}, {}
for j, (arm, lab, col) in enumerate(ARMS):
    ax = fig.add_axes([0.036 + j * 0.318, 0.43, 0.29, 0.37])
    ax.set_yscale("symlog", linthresh=0.05, linscale=0.7)
    ax.set_ylim(-0.6, 12); ax.set_xlim(0, 800)
    ax.axhspan(-0.6, 0, color=KEEP, alpha=0.08, lw=0)
    ax.axhline(0, color=KEEP, lw=1.6)
    ax.set_yticks([-0.5, -0.1, 0, 0.1, 1, 10]); ax.set_yticklabels(["\u22120.5", "\u22120.1", "0", "0.1", "1", "10 m"])
    ax.set_xticks([0, 200, 400, 600, 800]); ax.set_xticklabels(["0", "200", "400", "600", "800 s"])
    ax.tick_params(labelsize=12, length=3)
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)
    ax.grid(axis="y", color="#E6E9EC", lw=0.8)
    ax.set_title(lab + ("" if arm == "V3" else ", same preview"), loc="left", fontsize=19, color=col, pad=10)
    if j == 0:
        ax.text(10, -0.33, "inside the keep-out sphere", fontsize=12, color=KEEP, va="center")
    lines[arm] = [ax.plot([], [], color=col, lw=0.9, alpha=0.45)[0] for _ in range(60)]
    counters[arm] = (ax.text(0.56, 0.97, "", transform=ax.transAxes, ha="right", va="top", fontsize=17, color=INK),
                     ax.text(0.99, 0.97, "", transform=ax.transAxes, ha="right", va="top", fontsize=17, color=INK))
    axs.append(ax)
# running counts
ca = fig.add_axes([0.036, 0.075, 0.39, 0.25]); cb = fig.add_axes([0.53, 0.075, 0.39, 0.25])
step = {}
for ax, ttl, crit, clab in ((ca, "Runs with a violation, so far", 1, "V3 criterion: at most 1"),
                            (cb, "Runs that reached the proximity milestone, so far", 18, "V3 criterion: at least 18")):
    ax.set_xlim(0, 800); ax.set_ylim(0, 62)
    ax.set_xticks([0, 200, 400, 600, 800]); ax.set_xticklabels(["0", "200", "400", "600", "800 s"])
    ax.set_yticks([0, 20, 40, 60]); ax.tick_params(labelsize=12, length=3)
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)
    ax.grid(axis="y", color="#E6E9EC", lw=0.8)
    ax.set_title(ttl, loc="left", fontsize=17, color=INK, pad=8)
    ax.axhline(crit, color=INK, lw=1.0, ls=(0, (5, 4)))
    ax.text(795, crit + 1.5, clab, fontsize=11, color=INK2, ha="right", va="bottom")
for arm, lab, col in ARMS:
    step[arm] = (ca.plot([], [], color=col, lw=2.6, drawstyle="steps-post")[0],
                 cb.plot([], [], color=col, lw=2.6, drawstyle="steps-post")[0],
                 ca.text(0, 0, "", fontsize=13, color=col, va="center"), cb.text(0, 0, "", fontsize=13, color=col, va="center"))
cursors = [ax.axvline(0, color=INK, lw=0.8, alpha=0.5) for ax in axs + [ca, cb]]
fig.text(0.964, 0.012, "Source: results/val_v3 (frozen run files), read-only; counts equal the frozen report and addendum A1.1.",
         fontsize=11, color=INK2, ha="right")

tv = {a: np.array([r_["tv"] for r_ in data[a]]) for a, _, _ in ARMS}
tm = {a: np.array([r_["tm"] for r_ in data[a]]) for a, _, _ in ARMS}
grid = np.linspace(0, 800, 801)


def draw(T):
    kk = int(np.searchsorted(tp, T, side="right"))
    ends = {}
    for arm, lab, col in ARMS:
        for i, ln in enumerate(lines[arm]):
            ln.set_data(tp[:kk], data[arm][i]["clr"][ix][:kk])
            bad = data[arm][i]["tv"] <= T
            ln.set_color(KEEP if bad else col); ln.set_alpha(0.9 if bad else 0.45); ln.set_linewidth(1.3 if bad else 0.9)
        nvio = int(np.sum(tv[arm] <= T)); nms = int(np.sum(tm[arm] <= T))
        counters[arm][0].set_text("violations %d" % nvio)
        counters[arm][0].set_color(KEEP if nvio else INK)
        counters[arm][1].set_text("milestone %d" % nms)
        g = grid[grid <= T]
        cv = [int(np.sum(tv[arm] <= x)) for x in g]; cm = [int(np.sum(tm[arm] <= x)) for x in g]
        a1, a2, l1, l2 = step[arm]
        a1.set_data(g, cv); a2.set_data(g, cm)
        if len(g):
            short = {"V3": "V3", "MPCP": "MPC", "APFP": "APF"}[arm]
            l1.set_text("%s %d" % (short, cv[-1])); l2.set_text("%s %d" % (short, cm[-1]))
            ends[arm] = (g[-1], cv[-1], cm[-1])
    if ends:                                            # end labels: keep at least 4.5 count units apart, order kept
        for col_i, li in ((1, 2), (2, 3)):
            order = sorted(ends, key=lambda a: ends[a][col_i])
            ys = [float(ends[a][col_i]) for a in order]
            ys[0] = max(ys[0], 2.5)                     # keep the lowest label off the axis line
            for q in range(1, len(ys)):                 # forward pass: push labels up only, never reorder
                ys[q] = max(ys[q], ys[q - 1] + 4.5)
            for a, y in zip(order, ys):
                step[a][li].set_position((ends[a][0] + 6, y))
    for c in cursors:
        c.set_xdata([T, T])
    tclock.set_text("t = %3.0f s" % T)


FPS, SWEEP, HOLD = 30, 16.0, 3.0
Ts = np.linspace(0, 800, int(FPS * SWEEP) + 1)
wr = iio.get_writer(out + ".mp4", fps=FPS, codec="libx264", quality=8, pixelformat="yuv420p", macro_block_size=8)
ng = 0
for i, T in enumerate(Ts):
    draw(T)
    fig.canvas.draw()
    fr = np.asarray(fig.canvas.buffer_rgba())[:, :, :3].copy()
    wr.append_data(fr)
    if i % 3 == 0:
        iio.imwrite(os.path.join(out + "_gifframes", "f%04d.png" % ng), fr); ng += 1
for _ in range(int(FPS * HOLD)):
    wr.append_data(fr)
wr.close()
iio.imwrite(os.path.join(out + "_gifframes", "f%04d.png" % ng), fr)
iio.imwrite(out + "_final.png", fr)
print("frames %d | %s.mp4 %.1f MB" % (len(Ts), out, os.path.getsize(out + ".mp4") / 2**20))

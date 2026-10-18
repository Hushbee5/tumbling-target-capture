"""Closed-loop demo of the Python port: the chaser starts 10 m behind the target on the V-bar and is commanded to a point
3 m in front of it, so the straight path crosses the keep-out sphere. Runs the loop with and without the HOCBF-QP
filter and writes a figure.

Usage (from the repository root): python python/gnc/demo.py <out.png>"""
import os
import sys

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import gnc  # noqa: E402

out_png = sys.argv[1]
p = gnc.default_params()
x0 = np.array([0.0, -10.0, 0.0, 0.0, 0.0, 0.0])
r_ref = [0.0, 3.0, 0.0]
T = 600.0
runs = {True: gnc.simulate(p, x0, r_ref, T, use_filter=True),
        False: gnc.simulate(p, x0, r_ref, T, use_filter=False)}

fig, ax = plt.subplots(1, 2, figsize=(12, 4.4), gridspec_kw={"width_ratios": [1.25, 1]})
th = np.linspace(0, 2 * np.pi, 200)
ax[0].fill(p["r_safe"] * np.cos(th), p["r_safe"] * np.sin(th), color="#d62728", alpha=0.25, label="keep-out sphere")
for f, style, lab in [(False, "--", "MPC only"), (True, "-", "MPC + HOCBF-QP filter")]:
    X = runs[f]["X"]
    ax[0].plot(X[:, 1], X[:, 0], style, lw=2, label=lab)
    ax[1].plot(runs[f]["t"], np.linalg.norm(X[:, :3], axis=1) - p["r_safe"], style, lw=2, label=lab)
ax[0].plot(r_ref[1], r_ref[0], "k*", ms=12, label="set point")
ax[0].plot(x0[1], x0[0], "ko", ms=6, label="start")
ax[0].set_xlabel("along-track y [m]")
ax[0].set_ylabel("radial x [m]")
ax[0].set_xlim(-10.5, 3.8)
ax[0].set_ylim(-1.2, 1.2)
ax[0].set_aspect("equal")
ax[0].legend(loc="upper center", bbox_to_anchor=(0.5, -0.45), ncol=3, fontsize=8)
ax[0].set_title("Trajectory in the LVLH frame")
ax[1].axhline(0, color="#d62728", lw=1)
ax[1].set_xlabel("time [s]")
ax[1].set_ylabel("clearance |r| - r_safe [m]")
ax[1].set_yscale("symlog", linthresh=0.1)
ax[1].legend(loc="lower right", fontsize=8)
ax[1].set_title("Keep-out clearance")
for a in ax:
    a.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(out_png, dpi=150)
for f in (True, False):
    d = np.linalg.norm(runs[f]["X"][:, :3], axis=1) - p["r_safe"]
    print("filter %-5s minimum clearance %+.4f m, final position %s" % (f, d.min(), runs[f]["X"][-1, :3].round(3)))
print("written", out_png)

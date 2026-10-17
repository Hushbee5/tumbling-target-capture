"""Overview figures for the user, r3 (development material, not manuscript figures). Supersedes render_visuals_r2.py
(r2: hidden bottom-row titles, box text overflow, totals touching the grid; r1: clipped text, merged arrow).
Every number is read from results files.
  1. fig_capture_sequence.png   MuJoCo frames of the det_r3 capture, controller v3, nominal sensing
  2. fig_ros2_lockstep.png      ROS 2 node/topic design and the F1-F3 checks (values from the *_check.json files)
  3. fig_capture_robustness.png outcome grid of the stress sets r1 (v1), r2 (v2 filter), r3 (v3 post-grasp)
Usage: python render_visuals_r2.py <out_dir>   (never overwrites)"""
import glob
import json
import os
import sys
import textwrap

import matplotlib
matplotlib.use("Agg")
import matplotlib.patheffects as pe
import matplotlib.pyplot as plt
import mujoco
import numpy as np
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

import capture_core as CC
import sim_capture as SC
import stress_capture_v2 as V2
import stress_capture_v3 as V3

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
RES = r"results\mujoco_capture"
SURF, INK, INK2 = "#fcfcfb", "#0b0b0b", "#52514e"
GOOD, WARN, CRIT = "#0ca30c", "#fab219", "#d03b3b"
m = SC.m

# ---------------------------------------------------------------- 1. capture sequence
f1 = os.path.join(out, "fig_capture_sequence.png")
assert not os.path.exists(f1)
m.vis.headlight.ambient[:] = 0.32                         # rendering only; physics untouched
m.vis.headlight.diffuse[:] = 0.75
scn = [s for s in SC.scenarios() if s["id"] == "det_r3"][0]
plant, ctl, flt = V3.PlantV3(scn), CC.Controller(), V2.MeasFilter()
want = [0.5, 8.0, 16.0, 26.0]
H, W = 450, 600
rend = mujoco.Renderer(m, height=H, width=W)
cam = mujoco.MjvCamera()
fovy = float(m.vis.global_.fovy)
frames, hold = [], None


def project(P, pos, fwd, up):
    """Pinhole projection matching MuJoCo's free camera (fovy vertical, aspect from the viewport)."""
    rgt = np.cross(fwd, up)
    v = P - pos
    zc = v @ fwd
    th = np.tan(np.radians(fovy) / 2.0)
    x = (v @ rgt) / zc / (th * W / H)
    y = (v @ up) / zc / th
    return (0.5 + 0.5 * x) * W, (0.5 - 0.5 * y) * H


for k in range(int(round(27.0 / SC.DT_CTRL))):
    t = k * SC.DT_CTRL
    cmd, dg = ctl.step(flt(plant.measure()), t)
    if ctl.phase == "HOLD":
        if hold is None:
            Mf = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, plant.d, Mf); Mjj = np.diag(Mf)[SC.ARM_V]
            Kp = 50.0 * Mjj; hold = (plant.d.qpos[SC.ARM_Q].copy(), Kp, 2.0 * np.sqrt(Kp * Mjj))
        cmd = dict(cmd, hold_q=hold[0], Kp=hold[1], Kd=hold[2])
    phase_now = ctl.phase
    ci = plant.apply(cmd)
    ctl.contact_update(ci["fl"], ci["fr"], t)
    if want and t >= want[0] - 1e-9:
        d = plant.d
        cT = d.xpos[SC.BID["target"]].copy(); pB = d.xpos[SC.BID["bus"]].copy(); tcp = d.site_xpos[SC.TCP].copy()
        hdl = cT + SC.mat(d.xquat[SC.BID["target"]]) @ SC.PB
        u = pB - cT
        cam.lookat[:] = 0.5 * (cT + pB); cam.distance = 4.6
        cam.azimuth = np.degrees(np.arctan2(u[1], u[0])) + 90.0; cam.elevation = -25.0
        rend.update_scene(d, camera=cam)
        gc = rend.scene.camera[0]
        pos, fwd, up = np.array(gc.pos, float), np.array(gc.forward, float), np.array(gc.up, float)
        tags = {"target": project(cT, pos, fwd, up), "bus": project(pB, pos, fwd, up),
                "handle": project(hdl, pos, fwd, up)}
        frames.append((rend.render().copy(), t, phase_now, 100 * np.linalg.norm(tcp - hdl), tags))
        want.pop(0)
    if not want:
        break

S_nom = json.load(open(os.path.join(RES, "stress3_postgrasp", "det_r3_NOM.json")))
fig = plt.figure(figsize=(11.6, 10.2), facecolor=SURF)
gs = fig.add_gridspec(2, 2, left=0.015, right=0.985, top=0.885, bottom=0.085, hspace=0.20, wspace=0.05)
axs = np.array([[fig.add_subplot(gs[i, j]) for j in range(2)] for i in range(2)])
note = {"SYNC": "bus follows the tumbling handle at a 15 cm standoff",
        "APPROACH": "gripper closes the standoff while the bus stays synchronised",
        "CLOSE": "fingers close on the handle",
        "HOLD": "post-grasp hold: arm joints held, bus thrusters off"}
for i, (ax, (img, t, ph, dist, tags)) in enumerate(zip(axs.ravel(), frames)):
    ax.imshow(img); ax.set_axis_off()
    ax.set_title("t = %.1f s   %s   (TCP–handle %.1f cm)\n%s" % (t, ph, dist, note[ph]), fontsize=10, color=INK,
                 loc="left")
    if i == 0:
        for name, (x, y) in tags.items():
            dx, dy = {"target": (-70, -55), "bus": (40, -60), "handle": (-30, 60)}[name]
            ax.annotate(name, (x, y), xytext=(x + dx, y + dy), color="white", fontsize=10,
                        arrowprops=dict(arrowstyle="-", color="white", lw=1.0),
                        path_effects=[pe.withStroke(linewidth=2.5, foreground="black")])
fig.suptitle("MuJoCo capture prototype: det_r3 scenario (target rate 3.9 deg/s), controller v3, ideal measurements",
             fontsize=12.5, color=INK, x=0.015, ha="left")
foot = ("Free-floating 300 kg bus with a 6-DOF arm (UR5e kinematics and masses, approximated inertias: a generic research "
        "model, not flight hardware) and a two-finger gripper; tumbling 100 kg target with a handle at the capture point. "
        "This run (same seed and settings): outcome %s, grasp at %.2f s, %.0f s hold, peak pad force %.1f N, peak wrist "
        "force %.2f N, no forbidden contact. Development scenario, not a validation."
        % (S_nom["outcome"], S_nom["timeline_s"]["CLOSE"], S_nom["t_end_s"] - S_nom["timeline_s"]["HOLD"],
           S_nom["peak_pad_force_N"], S_nom["peak_wrist_force_N"]))
fig.text(0.015, 0.012, "\n".join(textwrap.wrap(foot, 150)), fontsize=8.6, color=INK2, ha="left", va="bottom")
fig.savefig(f1, dpi=120, facecolor=SURF); plt.close(fig)

# ---------------------------------------------------------------- 2. ROS 2 lockstep diagram
f2 = os.path.join(out, "fig_ros2_lockstep.png")
assert not os.path.exists(f2)
chk = {n: json.load(open(os.path.join(RES, p))) for n, p in
       (("det_r3 run 1", r"ros2_run1\det_r3_ros2_check.json"), ("det_r3 run 2", r"ros2_run2\det_r3_ros2_check.json"),
        ("w2_1", r"ros2_run3_w2_1\w2_1_ros2_check.json"))}
f3txt = open(os.path.join(RES, "ros2_F3_compare.txt")).readline()
fig, ax = plt.subplots(figsize=(11.6, 7.4), facecolor=SURF); ax.set_facecolor(SURF)
ax.set_xlim(0, 100); ax.set_ylim(0, 72); ax.set_axis_off()


def box(x, y, w, h, title, lines, edge):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.4,rounding_size=1.5", fc="white", ec=edge, lw=2))
    ax.text(x + 1.2, y + h - 2.2, title, fontsize=11.5, color=INK, weight="bold", va="top")
    for i, l in enumerate(lines):
        ax.text(x + 1.2, y + h - 7.2 - 3.3 * i, l, fontsize=9, color=INK2, va="top")


box(0.5, 31, 28.5, 31, "Process 1: plant node", ["MuJoCo 3.14 physics, RK4, 1 ms", "free-floating bus + 6-DOF arm",
    "tumbling target, handle, contact", "CW orbital terms on every body", "arm joint-velocity servo, 1 kHz",
    "contact monitor (allowed / forbidden)"], "#2a78d6")
box(71, 31, 28.5, 31, "Process 2: controller node", ["bus synchronisation", "  (PD + feed-forward)",
    "arm resolved-rate control with", "  bus-motion compensation", "phases SYNC, APPROACH, CLOSE, HOLD",
    "sees only the received messages"], "#eb6834")
topics = [("/capture/target/odom, /capture/bus/odom   nav_msgs/Odometry", 1),
          ("/capture/joint_states   sensor_msgs/JointState", 1),
          ("/capture/wrist_wrench   geometry_msgs/WrenchStamped", 1),
          ("/capture/contact   std_msgs/String", 1),
          ("/capture/bus_cmd   WrenchStamped (frame 'bus')", -1),
          ("/capture/joint_cmd   JointState (6 joint rates + gripper)", -1),
          ("/capture/status   std_msgs/String", -1)]
for i, (txt, dirn) in enumerate(topics):
    y = 58.5 - 3.7 * i - (1.8 if dirn < 0 else 0.0)
    a, b = ((30.5, y), (69.5, y)) if dirn > 0 else ((69.5, y), (30.5, y))
    ax.add_patch(FancyArrowPatch(a, b, arrowstyle="-|>", mutation_scale=11, color=INK2, lw=1.3))
    ax.text(50, y + 0.5, txt, fontsize=8.2, color=INK, ha="center", va="bottom")
ax.text(50, 61.8, "plant → controller", fontsize=8.5, color=INK2, ha="center", style="italic")
ax.text(50, 31.2, "controller → plant", fontsize=8.5, color=INK2, ha="center", style="italic")
ax.text(1, 27, "Deterministic lockstep every 10 ms: the plant publishes the measurements stamped t_k, waits for the "
        "commands stamped t_k, steps the physics 10 × 1 ms,", fontsize=9, color=INK, va="top")
ax.text(1, 23.8, "then publishes the contact flags. Integer-nanosecond stamps; frames per REP-105 (lvlh → target / bus); "
        "SI units. ROS 2 Humble (RoboStack) on Windows, localhost only.", fontsize=9, color=INK, va="top")
c1, c2, c3 = chk["det_r3 run 1"], chk["det_r3 run 2"], chk["w2_1"]
allc = [c1, c2, c3]
f2ok = all(c["F2_pass"] for c in allc)
rows = [("F2 stamps, frames, limits",
         "%s in all 3 runs: %d stamp mismatches, %d frame errors; max thrust %.2f N (limit 3), wheel torque %.3f N m "
         "(limit 0.2), joint-rate command %.3f rad/s (limit 0.5)"
         % ("PASS" if f2ok else "FAIL", sum(c["checks"]["stamp_mismatch"] for c in allc),
            sum(c["checks"]["frame_errors"] for c in allc), max(c["checks"]["max_thrust_N"] for c in allc),
            max(c["checks"]["max_wheel_Nm"] for c in allc), max(c["checks"]["max_qd_cmd"] for c in allc)),
         f2ok),
        ("F3 determinism", "%s: the two det_r3 runs are bit-identical in every history field (wall time excluded)"
         % ("PASS" if "PASS" in f3txt else "FAIL"), "PASS" in f3txt),
        ("F1 vs single-process run",
         "same outcome (%s) in all runs; worst relative difference: w2_1 %.1e (%s), det_r3 %.2e in the "
         "orientation-error history vs the 1e-9 limit (%s)" % (c1["outcome_ros2"], max(c3["F1_worst_rel"].values()),
                                                                "PASS" if c3["F1_pass"] else "FAIL",
                                                                c1["F1_worst_rel"]["e_o"],
                                                                "PASS" if c1["F1_pass"] else "FAIL"), None)]
for i, (k, v, ok) in enumerate(rows):
    y = 17.5 - 4.6 * i
    col, icon = (GOOD, "✓") if ok else ((WARN, "!") if ok is None else (CRIT, "✗"))
    ax.add_patch(FancyBboxPatch((1, y - 1.3), 2.2, 2.6, boxstyle="round,pad=0.1", fc=col, ec="none"))
    ax.text(2.1, y, icon, fontsize=9, color="white", ha="center", va="center", weight="bold")
    ax.text(4.6, y, k + ":", fontsize=9, color=INK, va="center", weight="bold")
    ax.text(27.5, y, "\n".join(textwrap.wrap(v, 112)), fontsize=8.6, color=INK, va="center")
ax.text(1, 2.0, "The ROS 2 runs use controller v1 with ideal measurements (det_r3 twice, w2_1 once). The filtered / "
        "post-grasp versions and the MATLAB approach controller are not in the ROS graph yet.", fontsize=8.6,
        color=INK2, va="center")
ax.text(1, 70.5, "ROS 2 + MuJoCo co-simulation of the capture phase: two processes, standard messages", fontsize=13,
        color=INK, weight="bold", va="top")
fig.savefig(f2, dpi=120, facecolor=SURF, bbox_inches="tight", pad_inches=0.15); plt.close(fig)

# ---------------------------------------------------------------- 3. robustness grid
f3 = os.path.join(out, "fig_capture_robustness.png")
assert not os.path.exists(f3)
sets = [("stress1", "v1  (no filter)", "dev3"), ("stress2_filter", "v2  (+ measurement filter)", "stress2_filter"),
        ("stress3_postgrasp", "v3  (+ filter + post-grasp hold)", "stress3_postgrasp")]
facs = [("B1", "unsynchronised start\n(10 cm, 1 cm/s)"), ("L1", "latency\n50 ms"), ("L2", "latency\n200 ms"),
        ("N1", "noise N1\n(0.5°, 5 mm, 1σ)"), ("N2", "noise N2\n(N1 × 3)")]
scns = [("det_r3", "r3"), ("w2_1", "w2"), ("w3_1", "w3")]
code = {"CAPTURED": ("captured", GOOD, "✓"), "NOT_REACHED": ("no grasp (never left SYNC)", WARN, "–"),
        "UNSAFE_CONTACT": ("unsafe contact (arm link hit own bus in HOLD)", CRIT, "✗")}
X0, GW, CW = 5.0, 2.75, 0.84
fig, ax = plt.subplots(figsize=(12.5, 5.2), facecolor=SURF); ax.set_facecolor(SURF)
ax.set_xlim(-0.4, 21.4); ax.set_ylim(-1.45, len(sets) + 1.35); ax.set_axis_off()
for r, (sd, lab, nomdir) in enumerate(sets):
    y = len(sets) - 1 - r
    ax.text(-0.35, y + 0.45, lab, fontsize=10, color=INK, ha="left", va="center")
    res = {}
    for f in glob.glob(os.path.join(RES, sd, "*.json")):
        S = json.load(open(f)); res[(S["id"], S.get("stress_factor"))] = S
        if S["outcome"] == "NOT_REACHED":
            assert list(S["timeline_s"]) == ["SYNC"], f
        if S["outcome"] == "UNSAFE_CONTACT":
            assert all(x[1].endswith("|g_bus") for x in S["forbidden_contacts"]) and "HOLD" in S["timeline_s"], f
    n_ok = 0
    for c, (fk, flab) in enumerate(facs):
        for j, (s, sl) in enumerate(scns):
            x = X0 + c * GW + j * CW
            S = res[(s, fk)]
            name, col, icon = code[S["outcome"]]
            n_ok += S["outcome"] == "CAPTURED"
            ax.add_patch(FancyBboxPatch((x - 0.38, y + 0.08), 0.76, 0.74, boxstyle="round,pad=0.02,rounding_size=0.08",
                                        fc=col, ec=SURF, lw=2))
            ax.text(x, y + 0.45, icon, fontsize=12, color="white", ha="center", va="center", weight="bold")
    noms = [json.load(open(f)) for f in glob.glob(os.path.join(RES, nomdir, "*.json"))
            if nomdir == "dev3" or f.endswith("_NOM.json")]
    ax.text(18.9, y + 0.45, "%d / 15" % n_ok, fontsize=11, color=INK, ha="center", va="center", weight="bold")
    ax.text(20.5, y + 0.45, "%d / %d" % (sum(S["outcome"] == "CAPTURED" for S in noms), len(noms)), fontsize=11,
            color=INK, ha="center", va="center")
for c, (fk, flab) in enumerate(facs):
    xc = X0 + c * GW + CW
    ax.text(xc, len(sets) + 0.4, flab, fontsize=9.2, color=INK, ha="center", va="center")
    for j, (s, sl) in enumerate(scns):
        ax.text(X0 + c * GW + j * CW, -0.18, sl, fontsize=8, color=INK2, ha="center")
ax.text(18.9, len(sets) + 0.4, "stress\ncaptured", fontsize=9.2, color=INK, ha="center", va="center")
ax.text(20.5, len(sets) + 0.4, "nominal\ncaptured", fontsize=9.2, color=INK, ha="center", va="center")
lx = X0 - 0.38
for name, col, icon in code.values():
    ax.add_patch(FancyBboxPatch((lx, -0.75), 0.3, 0.3, boxstyle="round,pad=0.01", fc=col, ec="none"))
    ax.text(lx + 0.15, -0.6, icon, fontsize=8, color="white", ha="center", va="center", weight="bold")
    ax.text(lx + 0.45, -0.6, name, fontsize=9, color=INK, va="center")
    lx += 0.45 + 0.118 * len(name) + 0.9
ax.text(-0.35, len(sets) + 1.2, "Capture stress tests in MuJoCo: one stress factor at a time, 3 scenarios each",
        fontsize=12.5, color=INK, weight="bold", va="center")
ax.text(-0.35, -1.2, "Scenarios: r3 = det_r3 (3.9 deg/s), w2 = w2_1 (2 deg/s), w3 = w3_1 (3 deg/s). Nominal = 10 scenarios "
        "with ideal measurements. Development iterations; each set's protocol was frozen before its runs.",
        fontsize=8.6, color=INK2, va="center")
fig.savefig(f3, dpi=120, facecolor=SURF, bbox_inches="tight", pad_inches=0.15); plt.close(fig)
print("written:", f1, f2, f3)

"""Capture stress set (protocols/CAPTURE_STRESS_PROTOCOL_r1.md, frozen before these runs): measurement noise, latency
and unsynchronized start, one at a time, on det_r3, w2_1 and w3_1. Same plant/controller/outcome rules as
capture_core (nominal reference set dev3). Usage: python stress_capture.py <out_dir>   (never overwrites)"""
import json
import os
import sys
import time
from collections import deque

import mujoco
import numpy as np

import capture_core as CC
import sim_capture as SC

m = SC.m


def rotvec_to_quat(rv):
    th = np.linalg.norm(rv)
    if th < 1e-15:
        return np.array([1.0, 0, 0, 0])
    a = rv / th
    return np.concatenate([[np.cos(th / 2)], np.sin(th / 2) * a])


def quat_mul(a, b):
    w1, x1, y1, z1 = a; w2, x2, y2, z2 = b
    return np.array([w1*w2 - x1*x2 - y1*y2 - z1*z2, w1*x2 + x1*w2 + y1*z2 - z1*y2,
                     w1*y2 - x1*z2 + y1*w2 + z1*x2, w1*z2 + x1*y2 - y1*x2 + z1*w2])


def noisy(meas, rng, k):
    q = meas["qpos"].copy(); v = meas["qvel"].copy()
    for qa, va, att in ((SC.QT, SC.VT, True), (SC.QB, SC.VB, False)):
        q[qa:qa + 3] += rng.normal(0, 0.005 * k, 3)
        v[va:va + 3] += rng.normal(0, 0.001 * k, 3)
        if att:
            dq = rotvec_to_quat(np.deg2rad(rng.normal(0, 0.5 * k, 3)))
            qq = quat_mul(q[qa + 3:qa + 7], dq); q[qa + 3:qa + 7] = qq / np.linalg.norm(qq)
            v[va + 3:va + 6] += np.deg2rad(rng.normal(0, 0.02 * k, 3))
    return {"qpos": q, "qvel": v, "sensordata": meas["sensordata"]}


def run(scn, factor, out_dir):
    tag = "%s_%s" % (scn["id"], factor)
    fj = os.path.join(out_dir, tag + ".json")
    if os.path.exists(fj):
        print("SKIP", tag); return
    t0w = time.time()
    plant, ctl = CC.Plant(scn), CC.Controller()
    if factor == "B1":
        d = plant.d
        RB = SC.mat(d.qpos[SC.QB + 3:SC.QB + 7])
        d.qpos[SC.QB:SC.QB + 3] += RB @ np.array([0.10, 0, 0])
        d.qvel[SC.VB:SC.VB + 3] += RB @ np.array([0, 0.01, 0])
        mujoco.mj_forward(m, d)
    rng = np.random.default_rng(31)                         # TEST generator (protocol)
    delay = {"L1": 5, "L2": 20}.get(factor, 0)
    buf = deque()
    H = {k: [] for k in ("t", "phase", "e_p", "e_o", "v_rel", "s", "bus_e", "bus_sat", "tau_sat", "fl", "fr",
                         "f_pad", "wrist_f", "wrist_t", "clear_tcp", "forbidden")}
    forbidden_all, peak_pad, hold_n, hold_both = [], 0.0, 0, 0
    for k in range(int(round(SC.T_MAX / SC.DT_CTRL))):
        t = k * SC.DT_CTRL
        meas = plant.measure()
        if factor in ("N1", "N2"):
            meas = noisy(meas, rng, 1 if factor == "N1" else 3)
        buf.append(meas)
        meas_used = buf[0] if len(buf) > delay else buf[0]
        if len(buf) > delay:
            meas_used = buf.popleft()
        cmd, dg = ctl.step(meas_used, t)
        ci = plant.apply(cmd)
        if ci["forbidden"]:
            forbidden_all += [(round(t, 3), x) for x in ci["forbidden"]]
        peak_pad = max(peak_pad, ci["f_pad"])
        ctl.contact_update(ci["fl"], ci["fr"], t)
        if ctl.phase == "HOLD":
            hold_n += 1; hold_both += int(ci["fl"] and ci["fr"])
        sd = plant.d.sensordata
        for key, val in (("t", t), ("phase", ctl.phase), ("e_p", dg["e_p"]), ("e_o", dg["e_o"]), ("v_rel", dg["v_rel"]),
                         ("s", dg["s"]), ("bus_e", dg["bus_e"]), ("bus_sat", dg["bus_sat"]), ("tau_sat", ci["tau_sat"]),
                         ("fl", ci["fl"]), ("fr", ci["fr"]), ("f_pad", ci["f_pad"]), ("wrist_f", np.linalg.norm(sd[0:3])),
                         ("wrist_t", np.linalg.norm(sd[3:6])), ("clear_tcp", dg["clear_tcp"]), ("forbidden", bool(ci["forbidden"]))):
            H[key].append(val)
        if ctl.phase == "HOLD" and t - ctl.tl["HOLD"] >= SC.T_HOLD:
            break
    S = CC.evaluate(scn, plant, ctl, H, peak_pad, forbidden_all, hold_n, hold_both, time.time() - t0w,
                    extra={"stress_factor": factor, "stress_protocol": "CAPTURE_STRESS_PROTOCOL_r1"})
    with open(fj, "x", encoding="utf-8") as fh:
        json.dump(S, fh, indent=1)
    print("%-12s -> %-15s timeline %s  end d %.4f m  v %.4f m/s  pad %.0f N  wrist %.1f N  forbidden %d  wall %.0f s" % (
        tag, S["outcome"], {kk: round(vv, 1) for kk, vv in S["timeline_s"].items()}, S["end_tcp_handle_dist_m"],
        S["end_rel_vel_mps"], S["peak_pad_force_N"], S["peak_wrist_force_N"], S["n_forbidden_samples"], S["wall_s"]),
        flush=True)


if __name__ == "__main__":
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    scns = {s["id"]: s for s in SC.scenarios()}
    for sid in ("det_r3", "w2_1", "w3_1"):
        for factor in ("N1", "N2", "L1", "L2", "B1"):
            run(scns[sid], factor, out_dir)

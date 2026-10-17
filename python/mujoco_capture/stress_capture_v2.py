"""Capture stress set r2 (protocols/CAPTURE_STRESS_PROTOCOL_r2_filter.md, frozen before these runs): controller v2 =
controller v1 (capture_core.Controller) + a fixed-gain measurement filter on the target and bus states. Runs the
nominal set (no noise) and the 15 stress runs. Usage: python stress_capture_v2.py <out_dir>   (never overwrites)"""
import json
import os
import sys
import time
from collections import deque

import numpy as np

import capture_core as CC
import sim_capture as SC
import stress_capture as ST

DT = SC.DT_CTRL
A_P, B_P, A_V = 0.05, 0.002, 0.05
A_Q, B_W = 0.05, 0.02


def qmul(a, b):
    return ST.quat_mul(a, b)


def qexp(rv):                      # rotation vector -> unit quaternion
    return ST.rotvec_to_quat(rv)


def qlog(q):                       # unit quaternion -> rotation vector
    q = q / np.linalg.norm(q)
    if q[0] < 0:
        q = -q
    s = np.linalg.norm(q[1:])
    if s < 1e-15:
        return 2 * q[1:]
    return 2 * np.arctan2(s, q[0]) * q[1:] / s


def qinv(q):
    return np.array([q[0], -q[1], -q[2], -q[3]])


class MeasFilter:
    def __init__(self):
        self.x = None

    def __call__(self, meas):
        q, v = meas["qpos"].copy(), meas["qvel"].copy()
        if self.x is None:
            self.x = (q.copy(), v.copy())
            return {"qpos": q, "qvel": v, "sensordata": meas["sensordata"]}
        qh, vh = self.x
        qo, vo = qh.copy(), vh.copy()
        for qa, va, att in ((SC.QT, SC.VT, True), (SC.QB, SC.VB, False)):
            # position / linear velocity (world frame), alpha-beta + velocity fusion
            pp = qh[qa:qa + 3] + vh[va:va + 3] * DT
            vp = vh[va:va + 3].copy()
            res = q[qa:qa + 3] - pp
            qo[qa:qa + 3] = pp + A_P * res
            vo[va:va + 3] = vp + (B_P / DT) * res + A_V * (v[va:va + 3] - vp)
            if att:
                # attitude (multiplicative) and body rate
                w_b = vh[va + 3:va + 6]
                qpred = qmul(qh[qa + 3:qa + 7], qexp(w_b * DT))
                qpred /= np.linalg.norm(qpred)
                dq = qlog(qmul(qinv(qpred), q[qa + 3:qa + 7]))
                qn = qmul(qpred, qexp(A_Q * dq)); qo[qa + 3:qa + 7] = qn / np.linalg.norm(qn)
                vo[va + 3:va + 6] = w_b + B_W * (v[va + 3:va + 6] - w_b)
            else:
                qo[qa + 3:qa + 7] = q[qa + 3:qa + 7]; vo[va + 3:va + 6] = v[va + 3:va + 6]   # bus attitude exact
        # joints and fingers pass through
        for adr in list(SC.ARM_Q) + [SC.m.jnt_qposadr[SC.m.joint(n).id] for n in ("jf_l", "jf_r")]:
            qo[adr] = q[adr]
        for adr in list(SC.ARM_V) + [SC.m.jnt_dofadr[SC.m.joint(n).id] for n in ("jf_l", "jf_r")]:
            vo[adr] = v[adr]
        self.x = (qo.copy(), vo.copy())
        return {"qpos": qo, "qvel": vo, "sensordata": meas["sensordata"]}


def run(scn, factor, out_dir):
    tag = "%s_%s" % (scn["id"], factor)
    fj = os.path.join(out_dir, tag + ".json")
    if os.path.exists(fj):
        print("SKIP", tag); return
    t0w = time.time()
    plant, ctl, flt = CC.Plant(scn), CC.Controller(), MeasFilter()
    if factor == "B1":
        d = plant.d
        RB = SC.mat(d.qpos[SC.QB + 3:SC.QB + 7])
        d.qpos[SC.QB:SC.QB + 3] += RB @ np.array([0.10, 0, 0])
        d.qvel[SC.VB:SC.VB + 3] += RB @ np.array([0, 0.01, 0])
        import mujoco
        mujoco.mj_forward(SC.m, d)
    rng = np.random.default_rng(31)
    delay = {"L1": 5, "L2": 20}.get(factor, 0)
    buf = deque()
    H = {k: [] for k in ("t", "phase", "e_p", "e_o", "v_rel", "s", "bus_e", "bus_sat", "tau_sat", "fl", "fr",
                         "f_pad", "wrist_f", "wrist_t", "clear_tcp", "forbidden")}
    forbidden_all, peak_pad, hold_n, hold_both = [], 0.0, 0, 0
    for k in range(int(round(SC.T_MAX / SC.DT_CTRL))):
        t = k * SC.DT_CTRL
        meas = plant.measure()
        if factor in ("N1", "N2"):
            meas = ST.noisy(meas, rng, 1 if factor == "N1" else 3)
        buf.append(meas)
        meas_used = buf.popleft() if len(buf) > delay else buf[0]
        cmd, dg = ctl.step(flt(meas_used), t)
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
                    extra={"stress_factor": factor, "stress_protocol": "CAPTURE_STRESS_PROTOCOL_r2_filter (controller v2)"})
    with open(fj, "x", encoding="utf-8") as fh:
        json.dump(S, fh, indent=1)
    print("%-14s -> %-15s timeline %s  end d %.4f m  v %.4f m/s  forbidden %d  wall %.0f s" % (
        tag, S["outcome"], {kk: round(vv, 1) for kk, vv in S["timeline_s"].items()}, S["end_tcp_handle_dist_m"],
        S["end_rel_vel_mps"], S["n_forbidden_samples"], S["wall_s"]), flush=True)


if __name__ == "__main__":
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    scns = {s["id"]: s for s in SC.scenarios()}
    for sid in ("det_r3", "w2_1", "w3_1"):
        for factor in ("N1", "N2", "L1", "L2", "B1"):
            run(scns[sid], factor, out_dir)
    for scn in SC.scenarios():
        run(scn, "NOM", out_dir)

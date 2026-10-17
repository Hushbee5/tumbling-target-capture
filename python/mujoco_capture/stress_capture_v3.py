"""Capture stress set r3 (protocols/CAPTURE_STRESS_PROTOCOL_r3_postgrasp.md, frozen before these runs): controller v3 =
v2 (v1 + measurement filter) + post-grasp mode. From the first HOLD sample: arm joint position hold
tau = Kp (q_hold - q) - Kd qdot + bias, Kp = 50 M_jj, Kd = 2 sqrt(Kp M_jj) (M_jj at HOLD start), clipped to the UR5e limits;
bus thrusters and wheels off. Same 25 runs as r2. Usage: python stress_capture_v3.py <out_dir>   (never overwrites)"""
import json
import os
import sys
import time
from collections import deque

import mujoco
import numpy as np

import capture_core as CC
import sim_capture as SC
import stress_capture as ST
import stress_capture_v2 as V2

m = SC.m


class PlantV3(CC.Plant):
    def apply(self, cmd):
        if cmd.get("hold_q") is None:
            return super().apply(cmd)
        d = self.d
        fl = fr = False; fpk = 0.0; forb = []; tau_sat = False
        for _ in range(int(round(SC.DT_CTRL / m.opt.timestep))):
            tau = cmd["Kp"] * (cmd["hold_q"] - d.qpos[SC.ARM_Q]) - cmd["Kd"] * d.qvel[SC.ARM_V] + d.qfrc_bias[SC.ARM_V]
            tau_sat |= bool(np.any(np.abs(tau) > SC.TAU_MAX))
            d.ctrl[0:6] = 0.0                                   # bus off: the stack floats freely
            d.ctrl[6:12] = np.clip(tau, -SC.TAU_MAX, SC.TAU_MAX)
            d.ctrl[12] = d.ctrl[13] = cmd["grip"]
            SC.cw_forces(d)
            mujoco.mj_step(m, d)
            fb, a1, a2, f1 = SC.classify_contacts(d)
            forb += fb; fl |= a1; fr |= a2; fpk = max(fpk, f1)
        return {"fl": fl, "fr": fr, "f_pad": fpk, "forbidden": sorted(set(forb)), "tau_sat": tau_sat}


def run(scn, factor, out_dir):
    tag = "%s_%s" % (scn["id"], factor)
    fj = os.path.join(out_dir, tag + ".json")
    if os.path.exists(fj):
        print("SKIP", tag); return
    t0w = time.time()
    plant, ctl, flt = PlantV3(scn), CC.Controller(), V2.MeasFilter()
    if factor == "B1":
        d = plant.d
        RB = SC.mat(d.qpos[SC.QB + 3:SC.QB + 7])
        d.qpos[SC.QB:SC.QB + 3] += RB @ np.array([0.10, 0, 0])
        d.qvel[SC.VB:SC.VB + 3] += RB @ np.array([0, 0.01, 0])
        mujoco.mj_forward(m, d)
    rng = np.random.default_rng(31)
    delay = {"L1": 5, "L2": 20}.get(factor, 0)
    buf = deque()
    H = {k: [] for k in ("t", "phase", "e_p", "e_o", "v_rel", "s", "bus_e", "bus_sat", "tau_sat", "fl", "fr",
                         "f_pad", "wrist_f", "wrist_t", "clear_tcp", "forbidden")}
    forbidden_all, peak_pad, hold_n, hold_both = [], 0.0, 0, 0
    hold = None
    for k in range(int(round(SC.T_MAX / SC.DT_CTRL))):
        t = k * SC.DT_CTRL
        meas = plant.measure()
        if factor in ("N1", "N2"):
            meas = ST.noisy(meas, rng, 1 if factor == "N1" else 3)
        buf.append(meas)
        meas_used = buf.popleft() if len(buf) > delay else buf[0]
        cmd, dg = ctl.step(flt(meas_used), t)
        if ctl.phase == "HOLD":
            if hold is None:                                     # first HOLD sample: freeze the hold configuration
                Mf = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, plant.d, Mf)
                Mjj = np.diag(Mf)[SC.ARM_V]
                Kp = 50.0 * Mjj; Kd = 2.0 * np.sqrt(Kp * Mjj)
                hold = (plant.d.qpos[SC.ARM_Q].copy(), Kp, Kd)
            cmd = dict(cmd, hold_q=hold[0], Kp=hold[1], Kd=hold[2])
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
                    extra={"stress_factor": factor, "stress_protocol": "CAPTURE_STRESS_PROTOCOL_r3_postgrasp (controller v3)"})
    with open(fj, "x", encoding="utf-8") as fh:
        json.dump(S, fh, indent=1)
    print("%-14s -> %-15s timeline %s  end d %.4f m  v %.4f m/s  pad %.0f N  wrist %.0f N  forbidden %d  wall %.0f s" % (
        tag, S["outcome"], {kk: round(vv, 1) for kk, vv in S["timeline_s"].items()}, S["end_tcp_handle_dist_m"],
        S["end_rel_vel_mps"], S["peak_pad_force_N"], S["peak_wrist_force_N"], S["n_forbidden_samples"], S["wall_s"]), flush=True)


if __name__ == "__main__":
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    scns = {s["id"]: s for s in SC.scenarios()}
    for sid in ("det_r3", "w2_1", "w3_1"):
        for factor in ("N1", "N2", "L1", "L2", "B1"):
            run(scns[sid], factor, out_dir)
    for scn in SC.scenarios():
        run(scn, "NOM", out_dir)

"""capture_core: the capture-phase prototype of sim_capture.py split into a PLANT (MuJoCo physics, CW terms, joint
velocity servo at 1 kHz, contact monitor) and a CONTROLLER (phase logic, synchronized bus control, resolved-rate arm
control). Same mathematics as sim_capture.run() (test R1 checks the in-process histories against sim_capture's bit
for bit), so the ROS 2 nodes (ros2_capture_nodes.py) can run the two halves as separate processes.

Measurement passed from plant to controller (exact state, as in r3): full qpos, qvel and the wrist sensor data.
Command passed back: bus wrench in the bus frame (6), arm joint-rate command (6), finger target (1), phase (str)."""
import json
import os

import mujoco
import numpy as np

import sim_capture as SC

m = SC.m


class Plant:
    def __init__(self, scn):
        self.scn = scn
        self.d = mujoco.MjData(m)
        self.ik_err = SC.setup(self.d, scn["w0_deg"], scn.get("q0", (1, 0, 0, 0)))
        self.Kv = np.zeros(6)

    def measure(self):
        d = self.d
        return {"qpos": d.qpos.copy(), "qvel": d.qvel.copy(), "sensordata": d.sensordata.copy()}

    def apply(self, cmd):
        """10 physics steps (one control period) with the joint velocity servo at 1 kHz; returns contact info."""
        d = self.d
        Mfull = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, d, Mfull)
        self.Kv = 200.0 * np.diag(Mfull)[SC.ARM_V]
        fl = fr = False; fpk = 0.0; forb = []; tau_sat = False
        steps = int(round(SC.DT_CTRL / m.opt.timestep))
        for _ in range(steps):
            tau = self.Kv * (cmd["qd_cmd"] - d.qvel[SC.ARM_V]) + d.qfrc_bias[SC.ARM_V]
            tau_sat |= bool(np.any(np.abs(tau) > SC.TAU_MAX))
            d.ctrl[0:6] = cmd["u_bus"]
            d.ctrl[6:12] = np.clip(tau, -SC.TAU_MAX, SC.TAU_MAX)
            d.ctrl[12] = d.ctrl[13] = cmd["grip"]
            SC.cw_forces(d)
            mujoco.mj_step(m, d)
            fb, a1, a2, f1 = SC.classify_contacts(d)
            forb += fb; fl |= a1; fr |= a2; fpk = max(fpk, f1)
        return {"fl": fl, "fr": fr, "f_pad": fpk, "forbidden": sorted(set(forb)), "tau_sat": tau_sat}


class Controller:
    def __init__(self):
        self.d = mujoco.MjData(m)               # the controller's own kinematic/dynamic model copy
        self.phase, self.s, self.t_ok = "SYNC", SC.S_PRE, 0.0
        self.tl = {"SYNC": 0.0}

    def step(self, meas, t):
        d = self.d
        d.qpos[:] = meas["qpos"]; d.qvel[:] = meas["qvel"]
        mujoco.mj_forward(m, d)
        cT, RT, vT, wT = SC.body_state(d, SC.BID["target"])
        pB, RB, vB, wB = SC.body_state(d, SC.BID["bus"])
        sdot = 0.0
        if self.phase == "APPROACH":
            self.s = max(0.0, self.s - 0.01 * SC.DT_CTRL); sdot = -0.01 if self.s > 0 else 0.0
        p_des, R_des, v_des, w_des = SC.desired_tcp(cT, RT, vT, wT, self.s, sdot)
        p = d.site_xpos[SC.TCP].copy(); R = d.site_xmat[SC.TCP].reshape(3, 3).copy()
        J = SC.site_jac(d)
        v_tcp = J @ d.qvel
        e_p = p_des - p; e_o = SC.ori_err(R, R_des)
        v_rel = np.linalg.norm(v_tcp[:3] - v_des)
        pbd = cT + RT @ (SC.R_HOLD_DIST * SC.U_HAT + SC.HOLD_OFFSET_Z * SC.E_Z); vbd = vT + np.cross(wT, pbd - cT)
        a_ff = np.cross(wT, np.cross(wT, pbd - cT))
        F_w = SC.M_SUB * (a_ff + 0.09 * (pbd - pB) + 0.6 * (vbd - vB))
        F_l = np.clip(RB.T @ F_w, -3.0, 3.0)
        Rd = RT @ SC.R_HOLD
        E = Rd.T @ RB - RB.T @ Rd
        eR = 0.5 * np.array([E[2, 1], E[0, 2], E[1, 0]])
        wBl = RB.T @ wB; ew = wBl - RB.T @ wT
        T_l = np.clip(SC.I_BUS * (-0.09 * eR - 0.6 * ew) + np.cross(wBl, SC.I_BUS * wBl), -0.2, 0.2)
        bus_sat = bool(np.any(np.abs(RB.T @ F_w) > 3.0))
        xi = np.concatenate([v_des + 2.0 * e_p, w_des + 2.0 * e_o]) - J[:, SC.BUS_V] @ d.qvel[SC.BUS_V]
        Jm = J[:, SC.ARM_V]
        qd_cmd = np.clip(Jm.T @ np.linalg.solve(Jm @ Jm.T + 1e-4 * np.eye(6), xi), -0.5, 0.5)
        ok_sync = np.linalg.norm(e_p) < 0.01 and np.degrees(np.linalg.norm(e_o)) < 5 and v_rel < 0.01
        if self.phase == "SYNC":
            self.t_ok = self.t_ok + SC.DT_CTRL if ok_sync else 0.0
            if self.t_ok >= 1.0:
                self.phase, self.tl["APPROACH"] = "APPROACH", t
        elif self.phase == "APPROACH":
            if self.s <= 0.0 and np.linalg.norm(e_p) < 0.005 and np.degrees(np.linalg.norm(e_o)) < 5 and v_rel < 0.01:
                self.phase, self.tl["CLOSE"] = "CLOSE", t
        grip = 0.04 if self.phase in ("CLOSE", "HOLD") else 0.0
        diag = {"e_p": float(np.linalg.norm(e_p)), "e_o": float(np.degrees(np.linalg.norm(e_o))), "v_rel": float(v_rel),
                "s": self.s, "bus_e": float(np.linalg.norm(pbd - pB)), "bus_sat": bus_sat,
                "clear_tcp": float(np.linalg.norm(p - cT) - 0.5)}
        return {"u_bus": np.concatenate([F_l, T_l]), "qd_cmd": qd_cmd, "grip": grip, "phase": self.phase}, diag

    def contact_update(self, fl, fr, t):
        if self.phase == "CLOSE" and fl and fr:
            self.phase, self.tl["HOLD"] = "HOLD", t


def evaluate(scn, plant, ctl, H, peak_pad, forbidden_all, hold_n, hold_both, wall, extra=None):
    """Outcome classification of CAPTURE_PHASE_PROTOCOL_r2 §3 (identical rules to sim_capture.run)."""
    d = plant.d
    cT, RT, vT, wT = SC.body_state(d, SC.BID["target"])
    handle_c = cT + RT @ SC.PB
    p = d.site_xpos[SC.TCP].copy(); J = SC.site_jac(d); v_tcp = (J @ d.qvel)[:3]
    v_handle = vT + np.cross(wT, handle_c - cT)
    end_dist = float(np.linalg.norm(p - handle_c)); end_vrel = float(np.linalg.norm(v_tcp - v_handle))
    wf_pk = float(np.max(H["wrist_f"])); wt_pk = float(np.max(H["wrist_t"]))
    tl = ctl.tl
    hold_frac = hold_both / hold_n if hold_n else 0.0
    if forbidden_all:
        outcome = "UNSAFE_CONTACT"
    elif peak_pad > 200 or wf_pk > 150 or wt_pk > 28:
        outcome = "LOAD_EXCEEDED"
    elif "HOLD" not in tl:
        outcome = "NOT_REACHED"
    elif hold_frac >= 0.95 and end_dist <= 0.02 and end_vrel <= 0.01 and (H["t"][-1] - tl["HOLD"]) >= SC.T_HOLD - 1e-9:
        outcome = "CAPTURED"
    else:
        outcome = "GRASP_FAILED"
    S = {"id": scn["id"], "w0_deg": list(map(float, scn["w0_deg"])), "w0_norm_deg": float(np.linalg.norm(scn["w0_deg"])),
         "outcome": outcome, "timeline_s": tl, "t_end_s": H["t"][-1], "ik_err": plant.ik_err,
         "hold_both_contact_fraction": hold_frac, "end_tcp_handle_dist_m": end_dist, "end_rel_vel_mps": end_vrel,
         "peak_pad_force_N": peak_pad, "peak_wrist_force_N": wf_pk, "peak_wrist_torque_Nm": wt_pk,
         "forbidden_contacts": forbidden_all[:20], "n_forbidden_samples": len(forbidden_all),
         "bus_saturation_fraction": float(np.mean(H["bus_sat"])), "arm_torque_saturation_fraction": float(np.mean(H["tau_sat"])),
         "min_tcp_clearance_to_target_sphere_m": float(np.min(H["clear_tcp"])),
         "max_bus_hold_error_m": float(np.max(H["bus_e"])), "wall_s": wall,
         "sync_saturated_flag": bool(np.mean(H["bus_sat"]) > 0.5),
         "protocol": "CAPTURE_PHASE_PROTOCOL_r2 (SHA-256 195414b1...)", "status": "DEVELOPMENT, GENERIC MODEL"}
    if extra:
        S.update(extra)
    return S


def run_inprocess(scn):
    """Plant and controller in one process, exchanging the same data the ROS 2 nodes exchange."""
    import time
    t0w = time.time()
    plant, ctl = Plant(scn), Controller()
    H = {k: [] for k in ("t", "phase", "e_p", "e_o", "v_rel", "s", "bus_e", "bus_sat", "tau_sat", "fl", "fr",
                         "f_pad", "wrist_f", "wrist_t", "clear_tcp", "forbidden")}
    forbidden_all, peak_pad, hold_n, hold_both = [], 0.0, 0, 0
    for k in range(int(round(SC.T_MAX / SC.DT_CTRL))):
        t = k * SC.DT_CTRL
        cmd, dg = ctl.step(plant.measure(), t)
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
    S = evaluate(scn, plant, ctl, H, peak_pad, forbidden_all, hold_n, hold_both, time.time() - t0w)
    return S, H


if __name__ == "__main__":
    # in-process reference runs of the split implementation: python capture_core.py <out_dir> <scenario|all>
    import sys
    out_dir, which = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for scn in SC.scenarios():
        if which not in ("all", scn["id"]):
            continue
        fj = os.path.join(out_dir, scn["id"] + ".json"); fz = os.path.join(out_dir, scn["id"] + ".npz")
        if os.path.exists(fj) or os.path.exists(fz):
            print("SKIP (exists)", scn["id"]); continue
        S, H = run_inprocess(scn)
        with open(fj, "x", encoding="utf-8") as fh:
            json.dump(S, fh, indent=1)
        np.savez_compressed(fz, **{k: np.array(v) for k, v in H.items()})
        print("%-8s |w0| %.2f -> %s  timeline %s  end d %.4f  v %.4f  wall %.0f s" % (
            scn["id"], S["w0_norm_deg"], S["outcome"], {k: round(v, 2) for k, v in S["timeline_s"].items()},
            S["end_tcp_handle_dist_m"], S["end_rel_vel_mps"], S["wall_s"]), flush=True)

"""Capture-phase prototype (gaps D/E) in MuJoCo, following protocols/CAPTURE_PHASE_PROTOCOL_r2.md (frozen,
SHA-256 195414b1...; r2 = r1 with the hold point offset 0.30 m along the handle axis). GENERIC RESEARCH MODEL; development scenarios only; outcome at most
IMPLEMENTED-UNVALIDATED.

Usage:  python sim_capture.py <out_dir> <scenario_id|all>
Writes <out_dir>/<scenario>.json (summary) and .npz (100 Hz histories); refuses to overwrite.
Measurement is exact (as in r3). World frame = target-centred LVLH (x radial, y along-track, z normal);
Clohessy-Wiltshire translational terms are applied to every body through xfrc_applied."""
import json
import math
import os
import sys
import time

import mujoco
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
N_ORB = 1.1314e-3
DT_CTRL = 0.01
T_MAX = 150.0
T_HOLD = 10.0

m = mujoco.MjModel.from_xml_path(os.path.join(HERE, "capture_scene.xml"))
assert abs(m.opt.timestep - 0.001) < 1e-15 and m.opt.integrator == mujoco.mjtIntegrator.mjINT_RK4
P = json.load(open(os.path.join(HERE, "model_params.json")))
PB = np.array(P["target"]["p_b_m"])
U_HAT = PB / np.linalg.norm(PB)
E_Z = np.array([0.0, 0.0, 1.0])
R_HOLD_DIST = 2.0
HOLD_OFFSET_Z = 0.30          # protocol r2
S_PRE = 0.15

BID = {n: m.body(n).id for n in ("target", "bus", "gripper", "finger_l", "finger_r")}
TCP = m.site("tcp").id
GID = {m.geom(i).name: i for i in range(m.ngeom)}
J_T = m.joint("target_free").id; J_B = m.joint("bus_free").id
QT = m.jnt_qposadr[J_T]; VT = m.jnt_dofadr[J_T]
QB = m.jnt_qposadr[J_B]; VB = m.jnt_dofadr[J_B]
ARM_Q = np.array([m.jnt_qposadr[m.joint("j%d" % i).id] for i in range(1, 7)])
ARM_V = np.array([m.jnt_dofadr[m.joint("j%d" % i).id] for i in range(1, 7)])
BUS_V = np.arange(VB, VB + 6)
TAU_MAX = np.array(P["arm"]["tau_max"])
M_SUB = m.body_subtreemass[BID["bus"]]
I_BUS = np.array(P["bus"]["inertia_kgm2"])
LINK_GEOMS = ["g_link%d" % i for i in range(1, 7)]
SERVICER_GEOMS = set(LINK_GEOMS + ["g_bus", "g_palm", "g_finger_l", "g_finger_r"])
GRIPPER_GEOMS = {"g_palm", "g_finger_l", "g_finger_r"}


def mat(q):
    R = np.zeros(9); mujoco.mju_quat2Mat(R, q); return R.reshape(3, 3)


def quat(R):
    q = np.zeros(4); mujoco.mju_mat2Quat(q, np.ascontiguousarray(R).flatten()); return q


# fixed body-frame geometry of the hold point and of the grasp frame
X_BUS = -U_HAT; Z_BUS = E_Z; Y_BUS = np.cross(Z_BUS, X_BUS)
R_HOLD = np.column_stack([X_BUS, Y_BUS, Z_BUS])          # bus axes expressed in the target body frame
Z_G = -U_HAT; X_G = E_Z; Y_G = np.cross(Z_G, X_G)
R_GRIP = np.column_stack([X_G, Y_G, Z_G])                 # desired TCP axes in the target body frame


def body_state(d, bid):
    v = np.zeros(6); mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, bid, v, 0)   # world [ang; lin]
    return d.xpos[bid].copy(), d.xmat[bid].reshape(3, 3).copy(), v[3:].copy(), v[:3].copy()


def site_jac(d):
    jp = np.zeros((3, m.nv)); jr = np.zeros((3, m.nv)); mujoco.mj_jacSite(m, d, jp, jr, TCP)
    return np.vstack([jp, jr])


def ori_err(R, Rd):
    return 0.5 * sum(np.cross(R[:, i], Rd[:, i]) for i in range(3))


def classify_contacts(d):
    forbidden, fl, fr, fpk = [], False, False, 0.0
    for i in range(d.ncon):
        c = d.contact[i]
        n1, n2 = m.geom(c.geom1).name, m.geom(c.geom2).name
        pair = {n1, n2}
        if "g_handle" in pair and (pair - {"g_handle"}) <= GRIPPER_GEOMS:
            f = np.zeros(6); mujoco.mj_contactForce(m, d, i, f)
            fpk = max(fpk, abs(f[0]))
            fl |= "g_finger_l" in pair; fr |= "g_finger_r" in pair
            continue
        if pair & {"g_target", "g_stalk"} and pair & SERVICER_GEOMS:
            forbidden.append("%s|%s" % (n1, n2)); continue
        if "g_handle" in pair and pair & (set(LINK_GEOMS) | {"g_bus"}):
            forbidden.append("%s|%s" % (n1, n2)); continue
        if pair <= SERVICER_GEOMS:
            forbidden.append("%s|%s" % (n1, n2)); continue
    return forbidden, fl, fr, fpk


def cw_forces(d):
    d.xfrc_applied[:] = 0.0
    for b in range(1, m.nbody):
        mb = m.body_mass[b]
        if mb <= 0:
            continue
        r = d.xipos[b]
        v = np.zeros(6); mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, b, v, 0)
        vl = v[3:]
        a = np.array([3 * N_ORB**2 * r[0] + 2 * N_ORB * vl[1], -2 * N_ORB * vl[0], -N_ORB**2 * r[2]])
        d.xfrc_applied[b, :3] = mb * a


def desired_tcp(cT, RT, vT, wT, s, sdot):
    p_des = cT + RT @ (PB + s * U_HAT)
    R_des = RT @ R_GRIP
    v_des = vT + np.cross(wT, p_des - cT) + RT @ (U_HAT * sdot)
    return p_des, R_des, v_des, wT.copy()


def ik_pregrasp(d, seeds):
    cT, RT, vT, wT = body_state(d, BID["target"])
    p_des, R_des, _, _ = desired_tcp(cT, RT, vT, wT, S_PRE, 0.0)
    best = None
    rng = np.random.default_rng(11)                      # TEST generator for extra IK seeds
    seeds = list(seeds) + [rng.uniform(-np.pi, np.pi, 6) for _ in range(40)]
    for seed in seeds:
        d.qpos[ARM_Q] = seed
        for it in range(1500):
            mujoco.mj_forward(m, d)
            p = d.site_xpos[TCP]; R = d.site_xmat[TCP].reshape(3, 3)
            e = np.concatenate([p_des - p, ori_err(R, R_des)])
            if np.linalg.norm(e) < 1e-10:
                break
            w = np.array([1, 1, 1, 0.3, 0.3, 0.3]) if it < 300 else np.ones(6)
            J = site_jac(d)[:, ARM_V] * w[:, None]
            dq = J.T @ np.linalg.solve(J @ J.T + 1e-3 * np.eye(6), e * w)
            d.qpos[ARM_Q] += np.clip(dq, -0.1, 0.1)
        mujoco.mj_forward(m, d)
        forb = classify_contacts(d)[0]
        err = np.linalg.norm(np.concatenate([p_des - d.site_xpos[TCP], ori_err(d.site_xmat[TCP].reshape(3, 3), R_des)]))
        if not forb and (best is None or err < best[0]):
            best = (err, d.qpos[ARM_Q].copy())
    assert best is not None and best[0] < 1e-6, "IK failed: %s" % (best,)
    d.qpos[ARM_Q] = best[1]
    mujoco.mj_forward(m, d)
    return best[0]


def setup(d, w0_deg, q0=(1, 0, 0, 0)):
    mujoco.mj_resetData(m, d)
    d.qpos[QT:QT + 3] = 0.0; d.qpos[QT + 3:QT + 7] = q0
    d.qvel[VT:VT + 3] = 0.0
    RT = mat(np.array(q0, float))
    w_world = RT @ np.deg2rad(np.array(w0_deg, float))
    # free-joint angular velocity: MuJoCo stores it in the body frame
    d.qvel[VT + 3:VT + 6] = RT.T @ w_world
    pB = RT @ (R_HOLD_DIST * U_HAT + HOLD_OFFSET_Z * E_Z)
    RB = RT @ R_HOLD
    d.qpos[QB:QB + 3] = pB; d.qpos[QB + 3:QB + 7] = quat(RB)
    d.qvel[VB:VB + 3] = np.cross(w_world, pB)
    d.qvel[VB + 3:VB + 6] = RB.T @ w_world
    mujoco.mj_forward(m, d)
    # check the stored target rate convention
    _, _, _, wchk = body_state(d, BID["target"])
    assert np.allclose(wchk, w_world, atol=1e-12), (wchk, w_world)
    ik_err = ik_pregrasp(d, seeds=[np.array([0.0, -1.2, 1.8, -2.2, -1.57, 0.0]),
                                   np.array([0.0, -1.6, 2.2, -2.2, 1.57, 0.0]),
                                   np.array([3.14, -1.2, 1.8, -2.2, -1.57, 0.0]),
                                   np.array([0.5, -1.0, 1.5, -2.0, -1.2, 0.3])])
    # arm joint rates that make the TCP co-move with the pre-grasp point
    cT, RT, vT, wT = body_state(d, BID["target"])
    p_des, R_des, v_des, w_des = desired_tcp(cT, RT, vT, wT, S_PRE, 0.0)
    J = site_jac(d)
    xi = np.concatenate([v_des, w_des]) - J[:, BUS_V] @ d.qvel[BUS_V]
    Jm = J[:, ARM_V]
    d.qvel[ARM_V] = Jm.T @ np.linalg.solve(Jm @ Jm.T + 1e-6 * np.eye(6), xi)
    mujoco.mj_forward(m, d)
    return ik_err


def run(scn, out_dir):
    f_json = os.path.join(out_dir, scn["id"] + ".json"); f_npz = os.path.join(out_dir, scn["id"] + ".npz")
    if os.path.exists(f_json) or os.path.exists(f_npz):
        print("SKIP (exists)", scn["id"]); return None
    d = mujoco.MjData(m)
    ik_err = setup(d, scn["w0_deg"], scn.get("q0", (1, 0, 0, 0)))
    phase, s, t_phase, t_ok = "SYNC", S_PRE, 0.0, 0.0
    tl = {"SYNC": 0.0}
    steps_per_ctrl = int(round(DT_CTRL / m.opt.timestep))
    n_ctrl = int(round(T_MAX / DT_CTRL))
    H = {k: [] for k in ("t", "phase", "e_p", "e_o", "v_rel", "s", "bus_e", "bus_sat", "tau_sat", "fl", "fr",
                         "f_pad", "wrist_f", "wrist_t", "clear_tcp", "forbidden")}
    forbidden_all, peak_pad = [], 0.0
    hold_n = hold_both = 0
    Kv = np.zeros(6); qd_cmd = np.zeros(6); u_bus = np.zeros(6)
    t0w = time.time()
    for k in range(n_ctrl):
        t = k * DT_CTRL
        cT, RT, vT, wT = body_state(d, BID["target"])
        pB, RB, vB, wB = body_state(d, BID["bus"])
        # --- standoff schedule -----------------------------------------------------------------
        sdot = 0.0
        if phase == "APPROACH":
            s = max(0.0, s - 0.01 * DT_CTRL); sdot = -0.01 if s > 0 else 0.0
        p_des, R_des, v_des, w_des = desired_tcp(cT, RT, vT, wT, s, sdot)
        p = d.site_xpos[TCP].copy(); R = d.site_xmat[TCP].reshape(3, 3).copy()
        J = site_jac(d)
        v_tcp = J @ d.qvel
        e_p = p_des - p; e_o = ori_err(R, R_des)
        v_rel = np.linalg.norm(v_tcp[:3] - v_des)
        # --- bus: synchronized hold point ----------------------------------------------------------
        pbd = cT + RT @ (R_HOLD_DIST * U_HAT + HOLD_OFFSET_Z * E_Z); vbd = vT + np.cross(wT, pbd - cT)
        a_ff = np.cross(wT, np.cross(wT, pbd - cT))
        F_w = M_SUB * (a_ff + 0.09 * (pbd - pB) + 0.6 * (vbd - vB))
        F_l = np.clip(RB.T @ F_w, -3.0, 3.0)
        Rd = RT @ R_HOLD
        eR = 0.5 * np.array([(Rd.T @ RB - RB.T @ Rd)[2, 1], (Rd.T @ RB - RB.T @ Rd)[0, 2], (Rd.T @ RB - RB.T @ Rd)[1, 0]])
        wBl = RB.T @ wB; ew = wBl - RB.T @ wT
        T_l = np.clip(I_BUS * (-0.09 * eR - 0.6 * ew) + np.cross(wBl, I_BUS * wBl), -0.2, 0.2)
        u_bus = np.concatenate([F_l, T_l])
        bus_sat = bool(np.any(np.abs(RB.T @ F_w) > 3.0))
        # --- arm: resolved rate with bus-motion compensation --------------------------------------
        xi = np.concatenate([v_des + 2.0 * e_p, w_des + 2.0 * e_o]) - J[:, BUS_V] @ d.qvel[BUS_V]
        Jm = J[:, ARM_V]
        qd_cmd = np.clip(Jm.T @ np.linalg.solve(Jm @ Jm.T + 1e-4 * np.eye(6), xi), -0.5, 0.5)
        Mfull = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, d, Mfull)
        Kv = 200.0 * np.diag(Mfull)[ARM_V]
        # --- phase logic (protocol §2) ---------------------------------------------------------------
        ok_sync = np.linalg.norm(e_p) < 0.01 and np.degrees(np.linalg.norm(e_o)) < 5 and v_rel < 0.01
        if phase == "SYNC":
            t_ok = t_ok + DT_CTRL if ok_sync else 0.0
            if t_ok >= 1.0:
                phase, tl["APPROACH"] = "APPROACH", t
        elif phase == "APPROACH":
            if s <= 0.0 and np.linalg.norm(e_p) < 0.005 and np.degrees(np.linalg.norm(e_o)) < 5 and v_rel < 0.01:
                phase, tl["CLOSE"] = "CLOSE", t
        grip = 0.04 if phase in ("CLOSE", "HOLD") else 0.0
        # --- integrate 10 physics steps with the joint velocity servo at 1 kHz --------------------------
        fl = fr = False; fpk = 0.0; forb_k = []; tau_sat = False
        for j in range(steps_per_ctrl):
            tau = Kv * (qd_cmd - d.qvel[ARM_V]) + d.qfrc_bias[ARM_V]
            tau_sat |= bool(np.any(np.abs(tau) > TAU_MAX))
            d.ctrl[0:6] = u_bus
            d.ctrl[6:12] = np.clip(tau, -TAU_MAX, TAU_MAX)
            d.ctrl[12] = d.ctrl[13] = grip
            cw_forces(d)
            mujoco.mj_step(m, d)
            fb, a1, a2, f1 = classify_contacts(d)
            forb_k += fb; fl |= a1; fr |= a2; fpk = max(fpk, f1)
        if forb_k:
            forbidden_all += [(round(t, 3), x) for x in sorted(set(forb_k))]
        peak_pad = max(peak_pad, fpk)
        if phase == "CLOSE" and fl and fr:
            phase, tl["HOLD"] = "HOLD", t
        if phase == "HOLD":
            hold_n += 1; hold_both += int(fl and fr)
        wf = np.linalg.norm(d.sensordata[0:3]); wt = np.linalg.norm(d.sensordata[3:6])
        for key, val in (("t", t), ("phase", phase), ("e_p", np.linalg.norm(e_p)), ("e_o", np.degrees(np.linalg.norm(e_o))),
                         ("v_rel", v_rel), ("s", s), ("bus_e", np.linalg.norm(pbd - pB)), ("bus_sat", bus_sat),
                         ("tau_sat", tau_sat), ("fl", fl), ("fr", fr), ("f_pad", fpk), ("wrist_f", wf), ("wrist_t", wt),
                         ("clear_tcp", np.linalg.norm(p - cT) - 0.5), ("forbidden", bool(forb_k))):
            H[key].append(val)
        if phase == "HOLD" and t - tl["HOLD"] >= T_HOLD:
            break
    # --- end-of-run evaluation (protocol §3) --------------------------------------------------------
    cT, RT, vT, wT = body_state(d, BID["target"])
    handle_c = cT + RT @ PB
    p = d.site_xpos[TCP].copy(); J = site_jac(d); v_tcp = (J @ d.qvel)[:3]
    v_handle = vT + np.cross(wT, handle_c - cT)
    end_dist = float(np.linalg.norm(p - handle_c)); end_vrel = float(np.linalg.norm(v_tcp - v_handle))
    wf_pk = float(np.max(H["wrist_f"])); wt_pk = float(np.max(H["wrist_t"]))
    load_exc = peak_pad > 200 or wf_pk > 150 or wt_pk > 28
    hold_frac = hold_both / hold_n if hold_n else 0.0
    if forbidden_all:
        outcome = "UNSAFE_CONTACT"
    elif load_exc:
        outcome = "LOAD_EXCEEDED"
    elif "HOLD" not in tl:
        outcome = "NOT_REACHED"
    elif hold_frac >= 0.95 and end_dist <= 0.02 and end_vrel <= 0.01 and (H["t"][-1] - tl["HOLD"]) >= T_HOLD - 1e-9:
        outcome = "CAPTURED"
    else:
        outcome = "GRASP_FAILED"
    S = {"id": scn["id"], "w0_deg": list(map(float, scn["w0_deg"])), "w0_norm_deg": float(np.linalg.norm(scn["w0_deg"])),
         "outcome": outcome, "timeline_s": tl, "t_end_s": H["t"][-1], "ik_err": ik_err,
         "hold_both_contact_fraction": hold_frac, "end_tcp_handle_dist_m": end_dist, "end_rel_vel_mps": end_vrel,
         "peak_pad_force_N": peak_pad, "peak_wrist_force_N": wf_pk, "peak_wrist_torque_Nm": wt_pk,
         "forbidden_contacts": forbidden_all[:20], "n_forbidden_samples": len(forbidden_all),
         "bus_saturation_fraction": float(np.mean(H["bus_sat"])), "arm_torque_saturation_fraction": float(np.mean(H["tau_sat"])),
         "min_tcp_clearance_to_target_sphere_m": float(np.min(H["clear_tcp"])),
         "max_bus_hold_error_m": float(np.max(H["bus_e"])), "wall_s": time.time() - t0w,
         "sync_saturated_flag": bool(np.mean(H["bus_sat"]) > 0.5),
         "protocol": "CAPTURE_PHASE_PROTOCOL_r2 (SHA-256 195414b1...)", "status": "DEVELOPMENT, GENERIC MODEL"}
    with open(f_json, "x", encoding="utf-8") as fh:
        json.dump(S, fh, indent=1)
    np.savez_compressed(f_npz, **{k: np.array(v) for k, v in H.items()})
    print("%-10s |w0| %.2f deg/s -> %-15s timeline %s  hold %.2f  end d %.4f m v %.4f m/s  pad %.1f N  wrist %.1f N %.2f N m  "
          "bus sat %.2f  wall %.0f s" % (scn["id"], S["w0_norm_deg"], outcome, {k: round(v, 1) for k, v in tl.items()},
                                          hold_frac, end_dist, end_vrel, peak_pad, wf_pk, wt_pk, S["bus_saturation_fraction"],
                                          S["wall_s"]))
    return S


def scenarios():
    sc = [{"id": "det_r3", "w0_deg": [2.0, -3.0, 1.5]}]
    rng = np.random.default_rng(2026)                      # TEST generator (protocol §4)
    for mag in (1.0, 2.0, 3.0):
        for j in range(3):
            v = rng.normal(size=3); v /= np.linalg.norm(v)
            sc.append({"id": "w%.0f_%d" % (mag, j + 1), "w0_deg": (mag * v).tolist()})
    return sc


if __name__ == "__main__":
    out_dir, which = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for scn in scenarios():
        if which in ("all", scn["id"]):
            run(scn, out_dir)

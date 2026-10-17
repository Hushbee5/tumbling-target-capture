"""Gap C: absolute mass / inertia of the target from a KNOWN excitation after the grasp (separate experiment).

Sequence: capture_core in-process up to HOLD + 2 s (scenario given), then an identification phase of T_ID s:
bus thrust and wheels OFF (the stack floats freely), grip held, the arm joints driven by a known small joint-rate
excitation (sum of sines). The estimator sees ONLY:
  * the interaction wrench applied to the target at the grasp (sum of the finger/palm contact forces on the handle;
    in hardware: finger or wrist force/torque sensing), expressed in the target body frame about the grasp point P
    (the handle centre, a known geometric attachment point);
  * the target motion (angular velocity in the body frame and the acceleration of P; exact state, as in r3; in
    hardware: the grasp makes the target move rigidly with the gripper, whose motion is known from the arm and bus
    navigation), differentiated at 1 kHz.
It estimates the 10 standard inertial parameters pi = [m, m c (3), I_P (6)] by least squares on the Newton-Euler
equations about P (linear in pi), then m, c, I_com (parallel-axis). Ground truth (m = 100 kg, c = -p_b, I_com =
diag(20, 25, 30) kg m^2) is used ONLY afterwards to score the estimate. A noisy variant adds white noise to the wrench
and the rate and reports 95 % intervals from the regression covariance.
Usage: python id_experiment.py <out_dir> <scenario>   (writes <out_dir>/<scenario>_id.json, never overwrites)"""
import json
import os
import sys
import time

import mujoco
import numpy as np

import capture_core as CC
import sim_capture as SC

m = SC.m
T_ID = 30.0
HANDLE = SC.GID["g_handle"]
GRIP_G = {SC.GID[n] for n in ("g_finger_l", "g_finger_r", "g_palm")}


def contact_wrench_on_target(d, P_world):
    """Total force on the target from gripper contacts, and its moment about P (world frame)."""
    F = np.zeros(3); Tq = np.zeros(3)
    for i in range(d.ncon):
        c = d.contact[i]
        if not ({c.geom1, c.geom2} & {HANDLE}) or not ({c.geom1, c.geom2} & GRIP_G):
            continue
        f6 = np.zeros(6); mujoco.mj_contactForce(m, d, i, f6)
        fr = c.frame.reshape(3, 3)                       # rows: contact frame axes in world coordinates
        f_world = fr.T @ f6[:3]                          # force exerted by geom1 on geom2 (MuJoCo convention)
        if c.geom1 == HANDLE:
            f_world = -f_world                           # force on the handle (geom1) is the reaction
        F += f_world
        Tq += np.cross(c.pos - P_world, f_world)
    return F, Tq


def regressor(w, wd, aP):
    """Rows of Y(pi) for f = m aP + wd x mc + w x (w x mc);  tau_P = I_P wd + w x (I_P w) + mc x aP  (body frame)."""
    def skew(v):
        return np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    Y = np.zeros((6, 10))
    Y[:3, 0] = aP
    Y[:3, 1:4] = skew(wd) + skew(w) @ skew(w)
    Y[3:, 1:4] = -skew(aP)
    def L(v):  # I v = L(v) [Ixx Ixy Ixz Iyy Iyz Izz]
        return np.array([[v[0], v[1], v[2], 0, 0, 0], [0, v[0], 0, v[1], v[2], 0], [0, 0, v[0], 0, v[1], v[2]]])
    Y[3:, 4:] = L(wd) + skew(w) @ L(w)
    return Y


def main(out_dir, sid):
    os.makedirs(out_dir, exist_ok=True)
    f_out = os.path.join(out_dir, sid + "_id.json")
    assert not os.path.exists(f_out), "exists"
    scn = [s for s in SC.scenarios() if s["id"] == sid][0]
    t0w = time.time()
    plant, ctl = CC.Plant(scn), CC.Controller()
    # ---- capture (same loop as capture_core.run_inprocess) up to HOLD + 2 s
    for k in range(int(round(SC.T_MAX / SC.DT_CTRL))):
        t = k * SC.DT_CTRL
        cmd, _ = ctl.step(plant.measure(), t)
        ci = plant.apply(cmd)
        ctl.contact_update(ci["fl"], ci["fr"], t)
        if ctl.phase == "HOLD" and t - ctl.tl["HOLD"] >= 2.0:
            break
    assert ctl.phase == "HOLD", "capture not reached"
    d = plant.d
    t_cap = t
    # ---- identification phase: free-floating stack, known joint-rate excitation
    freqs = np.array([0.11, 0.17, 0.23, 0.07, 0.13, 0.19]); amp = 0.05; phs = np.arange(6) * 0.9
    q_hold = d.qvel[SC.ARM_V].copy() * 0
    rows_Y, rows_b = [], []
    tb = SC.BID["target"]
    prev = None
    n_steps = int(round(T_ID / m.opt.timestep))
    Kv = None
    max_slip = 0.0
    for i in range(n_steps):
        tt = i * m.opt.timestep
        if i % 10 == 0:
            Mf = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, d, Mf)
            Kv = 200.0 * np.diag(Mf)[SC.ARM_V]
            qd_cmd = amp * np.sin(2 * np.pi * freqs * tt + phs)
        tau = Kv * (qd_cmd - d.qvel[SC.ARM_V]) + d.qfrc_bias[SC.ARM_V]
        d.ctrl[0:6] = 0.0
        d.ctrl[6:12] = np.clip(tau, -SC.TAU_MAX, SC.TAU_MAX)
        d.ctrl[12] = d.ctrl[13] = 0.04
        SC.cw_forces(d)
        mujoco.mj_step(m, d)
        mujoco.mj_forward(m, d)
        R = d.xmat[tb].reshape(3, 3)
        c_w = d.xipos[tb]                                  # used ONLY to build P from the body frame (geometry)
        P_w = d.xpos[tb] + R @ SC.PB                       # grasp point = handle centre (body-fixed, known geometry)
        v6 = np.zeros(6); mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, tb, v6, 1)   # local [ang; lin]
        w_b = v6[:3]
        vP_w = d.cvel[tb][3:] if False else None
        # velocity of P in world: v_origin + w x (P - origin), origin = body frame origin
        vo = np.zeros(6); mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, tb, vo, 0)
        vP = vo[3:] + np.cross(vo[:3], P_w - d.xpos[tb])
        F_w, T_w = contact_wrench_on_target(d, P_w)
        cur = (tt, R.copy(), w_b.copy(), vP.copy(), R.T @ F_w, R.T @ T_w)
        if prev is not None and i > 50:
            dt = cur[0] - prev[0]
            wd_b = (cur[2] - prev[2]) / dt
            aP_w = (cur[3] - prev[3]) / dt
            Rm = 0.5 * (cur[1] + prev[1])
            w_m = 0.5 * (cur[2] + prev[2])
            aP_b = Rm.T @ aP_w
            # body-frame acceleration of P: a_P(body) = R^T a_P(world) (expressed in the body frame)
            rows_Y.append(regressor(w_m, wd_b, aP_b))
            rows_b.append(np.concatenate([0.5 * (cur[4] + prev[4]), 0.5 * (cur[5] + prev[5])]))
        prev = cur
    Y = np.vstack(rows_Y); b = np.concatenate(rows_b)
    sc = np.linalg.norm(Y, axis=0); sc[sc == 0] = 1
    pi = np.linalg.lstsq(Y / sc, b, rcond=None)[0] / sc
    cond = np.linalg.cond(Y / sc)

    def unpack(pi):
        mm = pi[0]; c = pi[1:4] / mm
        IP = np.array([[pi[4], pi[5], pi[6]], [pi[5], pi[7], pi[8]], [pi[6], pi[8], pi[9]]])
        S = np.array([[0, -c[2], c[1]], [c[2], 0, -c[0]], [-c[1], c[0], 0]])
        Icom = IP - mm * (S.T @ S)
        return mm, c, Icom

    m_hat, c_hat, I_hat = unpack(pi)
    truth = {"m": 100.0, "c": (-SC.PB).tolist(), "I_com": [[20, 0, 0], [0, 25, 0], [0, 0, 30]]}
    err = {"m_rel": abs(m_hat - 100.0) / 100.0, "c_m": float(np.linalg.norm(c_hat + SC.PB)),
           "I_rel_fro": float(np.linalg.norm(I_hat - np.diag([20, 25, 30])) / np.linalg.norm(np.diag([20, 25, 30])))}
    # ---- noisy variant: white noise on wrench and rate, regression covariance -> 95 % intervals
    rng = np.random.default_rng(5)                            # TEST generator
    sig_f, sig_t, sig_w = 0.2, 0.05, 1e-4
    # rebuild with noise on b and on w (rate noise propagates to the numerically differentiated rate)
    bn = b + np.concatenate([np.concatenate([rng.normal(0, sig_f, 3), rng.normal(0, sig_t, 3)]) for _ in range(len(rows_b))])
    pin = np.linalg.lstsq(Y / sc, bn, rcond=None)[0] / sc
    res = bn - Y @ pin
    dof = len(bn) - 10
    s2 = float(res @ res) / dof
    cov = s2 * np.linalg.inv((Y / sc).T @ (Y / sc)) / np.outer(sc, sc)
    ci95 = 1.96 * np.sqrt(np.diag(cov))
    true_pi = np.array([100.0, *(100.0 * -SC.PB),
                        *[0] * 6])
    IPt = np.diag([20.0, 25.0, 30.0]) + 100.0 * (np.dot(SC.PB, SC.PB) * np.eye(3) - np.outer(SC.PB, SC.PB))
    true_pi[4:] = [IPt[0, 0], IPt[0, 1], IPt[0, 2], IPt[1, 1], IPt[1, 2], IPt[2, 2]]
    inside = [bool(abs(pin[j] - true_pi[j]) <= ci95[j]) for j in range(10)]
    mN, cN, IN = unpack(pin)
    out = {"scenario": sid, "t_capture_s": t_cap, "T_id_s": T_ID, "excitation": {"amp_rad_s": amp, "freqs_hz": freqs.tolist()},
           "n_rows": int(len(b) // 6), "regressor_condition": float(cond),
           "noise_free": {"m": float(m_hat), "c": c_hat.tolist(), "I_com": I_hat.tolist(), "errors": err},
           "noisy": {"sigma_force_N": sig_f, "sigma_torque_Nm": sig_t, "m": float(mN), "c": cN.tolist(), "I_com": IN.tolist(),
                     "pi_hat": pin.tolist(), "pi_ci95_halfwidth": ci95.tolist(), "pi_true": true_pi.tolist(),
                     "truth_inside_ci95": inside},
           "truth_used_only_for_scoring": truth, "wall_s": time.time() - t0w,
           "status": "DEVELOPMENT, single scenario, exact motion measurement"}
    with open(f_out, "x", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)
    print("ID %s: noise-free m %.3f kg (err %.2e), |c - c_true| %.2e m, I rel err %.2e, cond %.1e; noisy: m %.2f +- %.2f, truth in 95%% CI for %d/10 params; wall %.0f s"
          % (sid, m_hat, err["m_rel"], err["c_m"], err["I_rel_fro"], cond, mN, ci95[0], sum(inside), out["wall_s"]))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

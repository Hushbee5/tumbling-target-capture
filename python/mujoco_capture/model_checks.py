"""Model-level checks of capture_scene.xml (gap D). Prints one verdict line per check; exit 0 iff all pass.
Test RNG only (np.random.default_rng(1)); no campaign seed is used.
  M1  TCP Jacobian (mj_jacSite) vs central finite differences of the TCP position over all 20 velocity DOFs
      (free joints perturbed through mj_integratePos), 20 random configurations
  M2  free-floating momentum: no gravity, no external force, arm driven by internal joint torques for 20 s:
      drift of the total linear and angular momentum (about the world origin) of the servicer+arm subtree
  M3  centre of mass of the servicer+arm subtree stays fixed while the bus translates and rotates
      (base reaction is non-zero: the bus attitude changes by a reported angle)
  M4  generalised Jacobian (Umetani-Yoshida): with zero subtree momentum, the TCP velocity predicted from the
      joint rates, J* = J_m - J_b H_bb^-1 H_bm, matches the simulated TCP velocity
  M5  actuator limits in the model equal the UR5e torque limits and the bus thrust/torque limits
Writes nothing except stdout."""
import json
import os
import sys

import mujoco
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
m = mujoco.MjModel.from_xml_path(os.path.join(HERE, "capture_scene.xml"))
P = json.load(open(os.path.join(HERE, "model_params.json")))
rng = np.random.default_rng(1)
ok_all = True


def verdict(name, ok, msg):
    global ok_all
    ok_all &= bool(ok)
    print("%s %s -> %s" % (name, msg, "PASS" if ok else "FAIL"))


tcp = m.site("tcp").id
bus = m.body("bus").id
arm_dofs = [m.jnt_dofadr[m.joint("j%d" % i).id] for i in range(1, 7)]
bus_dofs = list(range(m.jnt_dofadr[m.joint("bus_free").id], m.jnt_dofadr[m.joint("bus_free").id] + 6))
arm_qpos = [m.jnt_qposadr[m.joint("j%d" % i).id] for i in range(1, 7)]

# ---------------------------------------------------------------- M1
d = mujoco.MjData(m)
worst = 0.0
for _ in range(20):
    mujoco.mj_resetData(m, d)
    d.qpos[arm_qpos] = rng.uniform(-np.pi, np.pi, 6)
    qb = m.jnt_qposadr[m.joint("bus_free").id]
    d.qpos[qb:qb + 3] = rng.normal(size=3)
    qq = rng.normal(size=4); d.qpos[qb + 3:qb + 7] = qq / np.linalg.norm(qq)
    mujoco.mj_forward(m, d)
    jp = np.zeros((3, m.nv)); jr = np.zeros((3, m.nv))
    mujoco.mj_jacSite(m, d, jp, jr, tcp)
    q0 = d.qpos.copy()
    J_fd = np.zeros((3, m.nv))
    for k in range(m.nv):
        h = 1e-6
        dv = np.zeros(m.nv); dv[k] = h
        qp = q0.copy(); mujoco.mj_integratePos(m, qp, dv, 1.0)
        qm = q0.copy(); mujoco.mj_integratePos(m, qm, -dv, 1.0)
        d.qpos[:] = qp; mujoco.mj_kinematics(m, d); xp = d.site_xpos[tcp].copy()
        d.qpos[:] = qm; mujoco.mj_kinematics(m, d); xm = d.site_xpos[tcp].copy()
        J_fd[:, k] = (xp - xm) / (2 * h)
    d.qpos[:] = q0
    rel = np.max(np.abs(J_fd - jp)) / max(1.0, np.max(np.abs(jp)))
    worst = max(worst, rel)
verdict("M1", worst < 1e-6, "TCP Jacobian vs central differences, 20 configurations: max error %.2e (relative)" % worst)

# ---------------------------------------------------------------- M2 / M3
mbus_sub = m.body_subtreemass[bus]
qb = m.jnt_qposadr[m.joint("bus_free").id]


def momentum_run(integrator, dt):
    """20 s of internal joint torques, contacts disabled (the target is a separate free body). Momentum is
    evaluated after mj_forward so that positions and velocities are consistent."""
    m.opt.integrator = integrator
    m.opt.timestep = dt
    m.opt.disableflags |= int(mujoco.mjtDisableBit.mjDSBL_CONTACT)
    dd = mujoco.MjData(m)
    q_init = np.array([0.3, -1.2, 1.5, -1.0, -1.57, 0.4]) + 0.3 * np.sin(np.arange(6))
    dd.qpos[arm_qpos] = q_init
    dd.qvel[arm_dofs] = 0.09 * np.cos(np.arange(6))
    kp = np.array([400, 400, 300, 60, 60, 20.0]); kd = np.array([80, 80, 60, 8, 8, 2.0])
    tau_lim = np.array([150, 150, 150, 28, 28, 28.0])
    mujoco.mj_forward(m, dd)
    Mf = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, dd, Mf)        # zero initial subtree momentum
    ib, im = np.array(bus_dofs), np.array(arm_dofs)
    dd.qvel[ib] = -np.linalg.solve(Mf[np.ix_(ib, ib)], Mf[np.ix_(ib, im)] @ dd.qvel[im])
    mujoco.mj_forward(m, dd)
    quat0 = dd.qpos[qb + 3:qb + 7].copy()
    lin0 = ang0 = com0 = None
    mdl = mda = mdc = 0.0
    for i in range(int(round(20.0 / dt))):
        t = i * dt
        dd.ctrl[:] = 0.0
        # realistic internal manoeuvre: PD tracking of smooth joint trajectories (amplitude 0.3 rad,
        # |qd| <= 0.09 rad/s, far inside the UR5e speed limit); torques clipped to the actuator ranges
        q_arm = dd.qpos[arm_qpos]; qd_arm = dd.qvel[arm_dofs]
        q_ref = q_init + 0.3 * np.sin(0.3 * t + np.arange(6))
        qd_ref = 0.09 * np.cos(0.3 * t + np.arange(6))
        tau = kp * (q_ref - q_arm) + kd * (qd_ref - qd_arm)
        dd.ctrl[6:12] = np.clip(tau, -tau_lim, tau_lim)
        dd.ctrl[12:14] = 0.002          # fingers held 2 mm off their joint limit (no limit constraint)
        mujoco.mj_step(m, dd)
        mujoco.mj_forward(m, dd)
        mujoco.mj_subtreeVel(m, dd)
        lin = dd.subtree_linvel[bus] * mbus_sub
        ang = dd.subtree_angmom[bus] + np.cross(dd.subtree_com[bus], lin)
        com = dd.subtree_com[bus].copy()
        if lin0 is None:
            lin0, ang0, com0 = lin.copy(), ang.copy(), com.copy()
        mdl = max(mdl, np.linalg.norm(lin - lin0)); mda = max(mda, np.linalg.norm(ang - ang0))
        mdc = max(mdc, np.linalg.norm(com - com0))
    q1 = dd.qpos[qb + 3:qb + 7]
    rot = 2 * np.degrees(np.arccos(min(1.0, abs(float(np.dot(quat0, q1))))))
    disp = np.linalg.norm(dd.xpos[bus] - np.array([-1.9, 0, 0]))
    m.opt.disableflags &= ~int(mujoco.mjtDisableBit.mjDSBL_CONTACT)
    return mdl, mda, mdc, rot, disp


integ0, dt0 = m.opt.integrator, m.opt.timestep
res = {}
for name, integ, dt in (("RK4 0.002 s", mujoco.mjtIntegrator.mjINT_RK4, 0.002),
                        ("RK4 0.001 s", mujoco.mjtIntegrator.mjINT_RK4, 0.001),
                        ("implicitfast 0.002 s", mujoco.mjtIntegrator.mjINT_IMPLICITFAST, 0.002)):
    res[name] = momentum_run(integ, dt)
    print("   momentum run %-22s max |dP| %.2e kg m/s, max |dL| %.2e kg m^2/s, CoM drift %.2e m, bus rot %.2f deg, "
          "bus disp %.3f m" % ((name,) + res[name]))
m.opt.integrator, m.opt.timestep = integ0, dt0
mdl, mda, mdc, rot_deg, bus_disp = res["RK4 0.001 s"]
order = np.log2(res["RK4 0.002 s"][0] / max(res["RK4 0.001 s"][0], 1e-300))
print("   RK4 momentum-drift convergence order (dt 2 ms -> 1 ms): %.2f" % order)
verdict("M2", mdl < 1e-6 and mda < 1e-5,
        "RK4 1 ms (model setting), 20 s PD arm manoeuvre: max |dP| %.2e kg m/s, max |dL| %.2e kg m^2/s (servicer+arm subtree); "
        "implicitfast at 2 ms drifts %.1e kg m/s (not used)" %
        (mdl, mda, res["implicitfast 0.002 s"][0]))
verdict("M3", mdc < 1e-6 and rot_deg > 0.01,
        "RK4 1 ms, zero initial momentum: subtree CoM drift %.2e m while the bus moved %.3f m and rotated %.3f deg (base reaction present)"
        % (mdc, bus_disp, rot_deg))

# ---------------------------------------------------------------- M4 generalised Jacobian
mujoco.mj_resetData(m, d)
d.qpos[arm_qpos] = [0.2, -1.0, 1.3, -0.8, -1.5, 0.2]
mujoco.mj_forward(m, d)
M = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, d, M)
idx_b, idx_m = np.array(bus_dofs), np.array(arm_dofs)
Hbb = M[np.ix_(idx_b, idx_b)]; Hbm = M[np.ix_(idx_b, idx_m)]
jp = np.zeros((3, m.nv)); jr = np.zeros((3, m.nv)); mujoco.mj_jacSite(m, d, jp, jr, tcp)
Jstar = jp[:, idx_m] - jp[:, idx_b] @ np.linalg.solve(Hbb, Hbm)
qdot = np.array([0.05, -0.04, 0.06, 0.03, -0.02, 0.05])
d.qvel[:] = 0.0
d.qvel[idx_m] = qdot
d.qvel[idx_b] = -np.linalg.solve(Hbb, Hbm @ qdot)      # zero subtree momentum (target is separate)
mujoco.mj_forward(m, d)
mujoco.mj_jacSite(m, d, jp, jr, tcp)
v_sim = jp @ d.qvel
v_gj = Jstar @ qdot
mujoco.mj_subtreeVel(m, d)
mom = np.linalg.norm(d.subtree_linvel[bus] * mbus_sub)
err = np.linalg.norm(v_sim - v_gj) / np.linalg.norm(v_gj)
verdict("M4", err < 1e-10 and mom < 1e-12,
        "generalised Jacobian TCP velocity vs full kinematics: relative error %.2e; subtree momentum %.1e"
        % (err, mom))

# ---------------------------------------------------------------- M5
lim = {m.actuator(i).name: tuple(m.actuator_ctrlrange[i]) for i in range(m.nu)}
okl = all(abs(lim["tau%d" % (i + 1)][1] - P["arm"]["tau_max"][i]) < 1e-12 for i in range(6)) \
      and abs(lim["bus_fx"][1] - 3.0) < 1e-12 and abs(lim["bus_tx"][1] - 0.2) < 1e-12
verdict("M5", okl, "actuator ranges: joints %s N m, bus %.1f N / %.1f N m" %
        ([lim["tau%d" % (i + 1)][1] for i in range(6)], lim["bus_fx"][1], lim["bus_tx"][1]))
print("MODEL CHECKS:", "ALL PASS" if ok_all else "FAILURES")
sys.exit(0 if ok_all else 1)

"""M6: MuJoCo orbital terms and time step. With contacts disabled, the target body released at r0 = [1, 0, 0.5] m with
zero LVLH velocity, under the Clohessy-Wiltshire forces of sim_capture.cw_forces and nothing else (gravity off in
the model), must follow the analytic CW solution for 600 s; the result at dt = 1 ms (model setting, RK4) is compared
with the analytic solution and with dt = 0.5 ms. Prints PASS/FAIL; writes nothing."""
import sys

import mujoco
import numpy as np

import sim_capture as SC

m = SC.m
n = SC.N_ORB
x0, z0 = 1.0, 0.5
T = 600.0


def run(dt):
    m.opt.timestep = dt
    m.opt.disableflags |= int(mujoco.mjtDisableBit.mjDSBL_CONTACT)
    d = mujoco.MjData(m)
    d.qpos[SC.QT:SC.QT + 3] = [x0, 0.0, z0]
    d.qpos[SC.QB:SC.QB + 3] = [-50.0, 0.0, 0.0]          # bus far away; its CW forces do not affect the target
    mujoco.mj_forward(m, d)
    for _ in range(int(round(T / dt))):
        SC.cw_forces(d)
        mujoco.mj_step(m, d)
    m.opt.disableflags &= ~int(mujoco.mjtDisableBit.mjDSBL_CONTACT)
    return d.xpos[SC.BID["target"]].copy()


nt = n * T
ana = np.array([(4 - 3 * np.cos(nt)) * x0, 6 * (np.sin(nt) - nt) * x0, z0 * np.cos(nt)])
p1 = run(0.001)
p2 = run(0.0005)
m.opt.timestep = 0.001
e1 = np.linalg.norm(p1 - ana); e12 = np.linalg.norm(p1 - p2)
drift = np.linalg.norm(ana - np.array([x0, 0, z0]))
ok = e1 < 1e-6 and e12 < 1e-9 and m.opt.gravity.tolist() == [0.0, 0.0, 0.0]
print("M6 CW terms over %.0f s: analytic displacement %.4f m; |MuJoCo(1 ms) - analytic| = %.2e m; |1 ms - 0.5 ms| = %.2e m; "
      "gravity %s -> %s" % (T, drift, e1, e12, m.opt.gravity.tolist(), "PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)

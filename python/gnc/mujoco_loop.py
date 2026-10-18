"""The Python controller flying a MuJoCo rigid body.

A 100 kg servicer (free body, 0.12 m sphere) moves next to a target whose keep-out sphere is drawn at the origin of the
LVLH frame. MuJoCo integrates the rigid-body motion (RK4, 10 ms). The Clohessy-Wiltshire terms and the commanded
acceleration enter as a passive force through mjcb_passive, so they are re-evaluated at every RK4 stage and the orbital
terms are integrated to fourth order (forces held over a whole physics step would make them first order). The
controller (preview MPC -> HOCBF-QP filter) samples the MuJoCo state every Ts = 0.1 s and holds its command in between.

Usage (from the repository root): python python/gnc/mujoco_loop.py [T_seconds]"""
import os
import sys

import mujoco
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gnc.dynamics import drift  # noqa: E402
from gnc.hocbf import cbf_qp_filter  # noqa: E402
from gnc.mpc import CondensedMPC  # noqa: E402
from gnc.params import default_params  # noqa: E402

XML = """
<mujoco model="servicer_lvlh">
  <option timestep="0.01" integrator="RK4" gravity="0 0 0"/>
  <worldbody>
    <light pos="0 0 20" dir="0 0 -1"/>
    <geom name="keep_out" type="sphere" size="{r_safe}" rgba="0.85 0.2 0.2 0.25" contype="0" conaffinity="0"/>
    <geom name="target" type="box" size="0.4 0.4 0.4" rgba="0.8 0.65 0.2 1" contype="0" conaffinity="0"/>
    <body name="servicer" pos="0 0 0">
      <freejoint/>
      <geom type="sphere" size="0.12" mass="100" rgba="0.3 0.5 0.9 1" contype="0" conaffinity="0"/>
    </body>
  </worldbody>
</mujoco>
"""


def run(p, x0, r_ref, T, use_filter=True):
    m = mujoco.MjModel.from_xml_string(XML.format(r_safe=p["r_safe"]))
    d = mujoco.MjData(m)
    mass = m.body_subtreemass[m.body("servicer").id]
    d.qpos[:3], d.qvel[:3] = x0[:3], x0[3:]
    mujoco.mj_forward(m, d)
    mpc = CondensedMPC(p)
    n_sub = int(round(p["Ts"] / m.opt.timestep))
    K = int(round(T / p["Ts"]))
    Pref = np.tile(np.asarray(r_ref, float).reshape(3, 1), (1, mpc.N + 1))
    Vref = np.zeros_like(Pref)
    X = np.zeros((K + 1, 6))
    U = np.zeros((K, 3))
    u_hold = np.zeros(3)

    def passive(m_, d_):                                 # called by MuJoCo at every RK4 stage
        xs = np.concatenate([d_.qpos[:3], d_.qvel[:3]])
        d_.qfrc_passive[:3] += mass * (drift(xs, p, "cw") + u_hold)

    r_min = np.inf                                       # clearance checked at every physics step
    mujoco.set_mjcb_passive(passive)
    try:
        for k in range(K):
            x = np.concatenate([d.qpos[:3], d.qvel[:3]])
            X[k] = x
            u, _ = mpc.step(x, Pref, Vref)
            if use_filter:
                u, info = cbf_qp_filter(x, u, p)
                if not info["feasible"]:
                    raise RuntimeError("HOCBF-QP infeasible at step %d" % k)
            U[k] = u
            u_hold[:] = u
            for _ in range(n_sub):
                mujoco.mj_step(m, d)
                r_min = min(r_min, np.linalg.norm(d.qpos[:3]))
    finally:
        mujoco.set_mjcb_passive(None)
    X[K] = np.concatenate([d.qpos[:3], d.qvel[:3]])
    return {"t": np.arange(K + 1) * p["Ts"], "X": X, "U": U, "r_min_fine": r_min}


if __name__ == "__main__":
    T = float(sys.argv[1]) if len(sys.argv) > 1 else 600.0
    p = default_params()
    out = run(p, np.array([0.0, -10.0, 0.0, 0.0, 0.0, 0.0]), [0.0, 3.0, 0.0], T)
    print("MuJoCo plant, %.0f s: minimum clearance %+.4f m (every physics step), final position %s"
          % (T, out["r_min_fine"] - p["r_safe"], out["X"][-1, :3].round(3)))

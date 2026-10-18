"""Closed loop: preview MPC -> HOCBF-QP safety filter -> plant, at the controller rate Ts.

The reference is a fixed point in the LVLH frame held at zero relative velocity, which is enough to exercise the safety
filter: a straight path to a point behind the target crosses the keep-out sphere. The capture-point preview of the
paper (a body-fixed point on the tumbling target) is not part of this port.

Plants: "cw" - exact zero-order-hold Clohessy-Wiltshire step (the controller's own model); "nonlinear" - two-body
relative motion integrated with an adaptive Runge-Kutta method."""
import numpy as np
from scipy.integrate import solve_ivp

from .dynamics import rel_dynamics
from .hocbf import cbf_qp_filter
from .mpc import CondensedMPC


def simulate(p, x0, r_ref, T, use_filter=True, plant="cw", N=None):
    mpc = CondensedMPC(p, N)
    K = int(round(T / p["Ts"]))
    X = np.zeros((K + 1, 6))
    X[0] = x0
    U_mpc = np.zeros((K, 3))
    U = np.zeros((K, 3))
    h = np.zeros(K + 1)
    status = np.zeros(K, dtype=int)
    Pref = np.tile(np.asarray(r_ref, float).reshape(3, 1), (1, mpc.N + 1))
    Vref = np.zeros_like(Pref)
    for k in range(K):
        x = X[k]
        u_mpc, _ = mpc.step(x, Pref, Vref)
        if use_filter:
            u, info = cbf_qp_filter(x, u_mpc, p)
            if not info["feasible"]:
                raise RuntimeError("HOCBF-QP infeasible at step %d" % k)
            status[k] = info["status"]
        else:
            u = u_mpc
        U_mpc[k], U[k] = u_mpc, u
        h[k] = x[:3] @ x[:3] - p["r_safe"] ** 2
        if plant == "cw":
            X[k + 1] = mpc.Ad @ x + mpc.Bd @ u
        else:
            sol = solve_ivp(lambda t, xx: rel_dynamics(xx, u, p, "nonlinear"), (0, p["Ts"]), x,
                            method="DOP853", rtol=1e-10, atol=1e-12)
            X[k + 1] = sol.y[:, -1]
    h[K] = X[K, :3] @ X[K, :3] - p["r_safe"] ** 2
    t = np.arange(K + 1) * p["Ts"]
    return {"t": t, "X": X, "U_mpc": U_mpc, "U": U, "h": h, "status": status}

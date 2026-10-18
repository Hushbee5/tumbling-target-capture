"""Relative translational dynamics in the LVLH frame (+x radial outward, +y along-track) and the keep-out barrier.

Python port of cw_matrices.m, rel_translational_dynamics.m and safety_function.m."""
import numpy as np
from scipy.linalg import expm


def cw_matrices(n, dt=None):
    """Continuous Clohessy-Wiltshire model xdot = A x + B u, x = [r; v]; with dt also its exact ZOH discretisation."""
    A = np.array([[0, 0, 0, 1, 0, 0],
                  [0, 0, 0, 0, 1, 0],
                  [0, 0, 0, 0, 0, 1],
                  [3 * n ** 2, 0, 0, 0, 2 * n, 0],
                  [0, 0, 0, -2 * n, 0, 0],
                  [0, 0, -n ** 2, 0, 0, 0]], dtype=float)
    B = np.vstack([np.zeros((3, 3)), np.eye(3)])
    if dt is None:
        return A, B
    M = expm(np.block([[A, B], [np.zeros((3, 9))]]) * dt)
    return A, B, M[:6, :6], M[:6, 6:]


def drift(x, p, mode="cw"):
    """Drift acceleration (no input) of the chaser relative to the target."""
    r, v = x[:3], x[3:]
    n = p["n"]
    if mode == "cw":
        return np.array([3 * n ** 2 * r[0] + 2 * n * v[1], -2 * n * v[0], -n ** 2 * r[2]])
    if mode == "nonlinear":
        w = np.array([0.0, 0.0, n])
        Rt = np.array([p["a_m"], 0.0, 0.0])
        rc = Rt + r
        a_grav = -p["mu_m"] * rc / np.linalg.norm(rc) ** 3 + p["mu_m"] * Rt / np.linalg.norm(Rt) ** 3
        return a_grav - 2 * np.cross(w, v) - np.cross(w, np.cross(w, r))
    raise ValueError("unknown mode " + mode)


def rel_dynamics(x, u, p, mode="cw"):
    return np.concatenate([x[3:], drift(x, p, mode) + u])


def safety_function(x, p):
    """Keep-out barrier h = |r|^2 - r_safe^2 (h >= 0 is safe) and the terms of h_ddot = Lf2h + Lgh u (CW model)."""
    r, v = x[:3], x[3:]
    h = r @ r - p["r_safe"] ** 2
    d_safe = np.linalg.norm(r) - p["r_safe"]
    hdot = 2 * r @ v
    Lf2h = 2 * v @ v + 2 * r @ drift(x, p, "cw")
    Lgh = 2 * r
    return h, d_safe, hdot, Lf2h, Lgh

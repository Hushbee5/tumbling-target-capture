"""High-order CBF safety filter for the keep-out sphere. Python port of cbf_qp_filter.m.

    min 0.5 |u - u_nom|^2   s.t.   psi2(x, u) = h_ddot + (k1 + k2) h_dot + k1 k2 h >= delta,   |u_i| <= u_max

With an identity weighting this is the Euclidean projection of u_nom onto one halfspace intersected with a box. It is
solved exactly through its scalar dual: u(lam) = clip(u_nom - lam a), and g(lam) = a'u(lam) - b is continuous and
non-increasing, so the root is bracketed and bisected with a fixed number of steps (deterministic)."""
import numpy as np

from .dynamics import safety_function


def cbf_qp_filter(x, u_nom, p):
    """Returns (u_safe, info). info['status']: 1 solved with the row active, 0 row inactive, -1 infeasible."""
    u_nom = np.asarray(u_nom, dtype=float)
    umax = p["u_max"]
    k1, k2 = p["k1"], p["k2"]
    h, d_safe, hdot, Lf2h, Lgh = safety_function(x, p)
    psi1 = hdot + k1 * h
    a = -Lgh
    b = Lf2h + (k1 + k2) * hdot + k1 * k2 * h - p["delta"]

    def clip(u):
        return np.clip(u, -umax, umax)

    def g(lam):
        return a @ clip(u_nom - lam * a) - b

    def psi2(u):
        return Lf2h + Lgh @ u + (k1 + k2) * hdot + k1 * k2 * h

    info = {"h": h, "d_safe": d_safe, "hdot": hdot, "psi1": psi1, "A_cbf": a, "b_cbf": b}
    feas_margin = b + umax * np.abs(a).sum()        # min over the box of a'u is -u_max |a|_1
    info["feas_margin"] = feas_margin
    if feas_margin < 0:
        u = clip(u_nom)
        info.update(feasible=False, lam=0.0, status=-1, psi2=np.nan)
    else:
        u0 = clip(u_nom)
        if a @ u0 - b <= 0:
            u, lam, status = u0, 0.0, 0
        else:
            # Bracket from the significant components only. A component many orders of magnitude below the others
            # (e.g. 1e-74 left by an integrator in an axis that should be exactly zero) would otherwise push lam_hi
            # to ~1e72, beyond what the fixed 200 bisection steps can resolve. If the bracket is not yet valid it is
            # doubled below, as before.
            nz = np.abs(a) > 1e-12 * np.abs(a).max()
            lam_hi = np.max((np.abs(u_nom[nz]) + umax) / np.abs(a[nz])) if nz.any() else 1.0
            if not np.isfinite(lam_hi):
                lam_hi = 1.0
            lam_hi = max(lam_hi, np.finfo(float).eps)
            while g(lam_hi) > 0:
                lam_hi *= 2
            lam_lo = 0.0
            for _ in range(200):
                mid = 0.5 * (lam_lo + lam_hi)
                if g(mid) > 0:
                    lam_lo = mid
                else:
                    lam_hi = mid
            lam = lam_hi                             # endpoint with g <= 0: feasible
            u, status = clip(u_nom - lam * a), 1
        info.update(feasible=True, lam=lam, status=status, psi2=psi2(u))
    info["dev_inf"] = np.max(np.abs(u - u_nom))
    info["active"] = info["dev_inf"] > p["act_thresh"]
    return u, info

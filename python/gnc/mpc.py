"""Condensed linear MPC on the discrete Clohessy-Wiltshire model. Python port of mpc_condensed.m and mpc_step.m.

    X = Sx x0 + Su U,   J = sum_{j<N} |x_j - xr_j|_Q^2 + |x_N - xr_N|_P^2 + sum_j |u_j|_R^2,   |u_i| <= u_max

so  min 0.5 U'H U + f'U  with  H = 2 (Su' Qbar Su + Rbar),  f = 2 Su' Qbar (Sx x0 - Xr).
Q and R are normalised by physical scales; the terminal weight P is the discrete LQR cost matrix. The box-constrained
QP is solved with OSQP, then refined to the exact solution on the identified active set (MATLAB: quadprog)."""
import numpy as np
import osqp
from scipy import sparse
from scipy.linalg import solve_discrete_are

from .dynamics import cw_matrices


class CondensedMPC:
    def __init__(self, p, N=None):
        self.N = N = N or p["N"]
        _, _, Ad, Bd = cw_matrices(p["n"], p["Ts"])
        nx, nu = 6, 3
        Q = np.diag([1 / p["sigma_p"] ** 2] * 3 + [1 / p["sigma_v"] ** 2] * 3)
        R = p["rho"] / p["u_max"] ** 2 * np.eye(nu)
        if p["use_dlqr_terminal"]:
            P = solve_discrete_are(Ad, Bd, Q, R)
            K = np.linalg.solve(Bd.T @ P @ Bd + R, Bd.T @ P @ Ad)
        else:
            P, K = Q, None
        Sx = np.zeros((nx * N, nx))
        Su = np.zeros((nx * N, nu * N))
        Apow = np.eye(nx)
        AiB = [Bd]
        for i in range(1, N):
            AiB.append(Ad @ AiB[-1])                 # Ad^i Bd
        for i in range(N):
            Apow = Apow @ Ad
            Sx[i * nx:(i + 1) * nx] = Apow
            for j in range(i + 1):
                Su[i * nx:(i + 1) * nx, j * nu:(j + 1) * nu] = AiB[i - j]
        qdiag = [Q] * (N - 1) + [P]
        Qbar = np.zeros((nx * N, nx * N))
        for i, Qi in enumerate(qdiag):
            Qbar[i * nx:(i + 1) * nx, i * nx:(i + 1) * nx] = Qi
        Rbar = np.kron(np.eye(N), R)
        H = 2 * (Su.T @ Qbar @ Su + Rbar)
        self.H = (H + H.T) / 2
        self.Ad, self.Bd, self.Q, self.R, self.P, self.K = Ad, Bd, Q, R, P, K
        self.Sx, self.Su, self.Qbar = Sx, Su, Qbar
        self.nu = nu
        self.u_max = p["u_max"]
        self._G = 2 * Su.T @ Qbar                    # f = G (Sx x0 - Xr)
        self._solver = osqp.OSQP()
        nU = nu * N
        self._solver.setup(P=sparse.triu(sparse.csc_matrix(self.H), format="csc"), q=np.zeros(nU),
                           A=sparse.identity(nU, format="csc"), l=-self.u_max * np.ones(nU),
                           u=self.u_max * np.ones(nU), eps_abs=1e-9, eps_rel=1e-9, max_iter=200000,
                           polishing=False, verbose=False)

    def step(self, x, Pref, Vref):
        """First move of the optimal input sequence. Pref, Vref: 3 x (N+1) references, column 0 = now."""
        N = self.N
        Xr = np.vstack([Pref[:, 1:N + 1], Vref[:, 1:N + 1]]).T.reshape(-1)
        f = self._G @ (self.Sx @ x - Xr)
        self._solver.update(q=f)
        res = self._solver.solve(raise_error=False)
        if res.info.status not in ("solved", "solved inaccurate"):
            return np.zeros(3), {"status": res.info.status, "U": None}
        U = self._refine(res.x, f)
        return U[:3].copy(), {"status": res.info.status, "U": U, "cost": 0.5 * U @ self.H @ U + f @ U}

    def _refine(self, U, f, tol=1e-6):
        """Exact solution on the active set identified by OSQP: inputs at a bound are fixed there and the free ones
        solve the reduced KKT system. Accepted only if the result satisfies the KKT conditions of the box QP."""
        um = self.u_max
        fixed = np.abs(U) >= um - tol
        Uf = np.where(fixed, np.sign(U) * um, 0.0)
        free = ~fixed
        if free.any():
            Hff = self.H[np.ix_(free, free)]
            Uf[free] = np.linalg.solve(Hff, -(f[free] + self.H[np.ix_(free, fixed)] @ Uf[fixed]))
        grad = self.H @ Uf + f
        ok = (np.all(np.abs(Uf[free]) <= um + 1e-12)
              and np.all(grad[fixed] * np.sign(Uf[fixed]) <= 1e-9 * max(1.0, np.abs(grad).max())))
        return Uf if ok else U

"""Concurrent-learning estimator of the target's scale-free inertia ratios. Python port of cl_records.m,
cl_estimator_init.m and cl_estimator_step.m.

Torque-free rotation obeys omega_dot = Y(omega) * theta with Y = diag(w2 w3, w3 w1, w1 w2) and
theta = ((I2 - I3)/I1, (I3 - I1)/I2, (I1 - I2)/I3). Integrating over windows of length Tw gives exact linear
regression records Delta_omega_j = Ybar_j .* theta (Simpson quadrature on the control grid). A history stack of at
most M records drives
    theta_hat += Ts * gamma * (S - Lambda .* theta_hat),   Lambda = sum Ybar_j^2,   S = sum Ybar_j .* Delta_omega_j
and the error bound carried by the safety layer is nu(t) = nu0 * exp(-gamma * integral of lambda_min(Lambda))."""
import numpy as np


def cl_records(t, w, Tw, Ts):
    """Window records from the measured rate history w (N x 3) on the control grid t (N)."""
    nw = int(round(Tw / Ts))
    assert nw % 2 == 0 and nw >= 2 and abs(nw * Ts - Tw) < 1e-12
    c = np.ones(nw + 1)
    c[1:-1:2] = 4.0
    c[2:-1:2] = 2.0
    starts = np.arange(0, len(t) - nw, nw)              # record j spans [j Tw, (j+1) Tw], available at its end
    Y = np.zeros((len(starts), 3))
    D = np.zeros((len(starts), 3))
    Te = np.zeros(len(starts))
    for j, a in enumerate(starts):
        wk = w[a:a + nw + 1]
        Yk = np.column_stack([wk[:, 1] * wk[:, 2], wk[:, 2] * wk[:, 0], wk[:, 0] * wk[:, 1]])
        Y[j] = Ts / 3 * (c @ Yk)
        D[j] = w[a + nw] - w[a]
        Te[j] = t[a + nw]
    return {"Y": Y, "D": D, "Te": Te}


class CLEstimator:
    def __init__(self, rec, Ts, gamma=100.0, M=50, nu0=np.sqrt(3.0), theta_hat0=(0.0, 0.0, 0.0)):
        self.rec, self.Ts, self.gamma, self.M, self.nu0 = rec, Ts, gamma, M, nu0
        self.theta_hat = np.array(theta_hat0, dtype=float)
        self.E = 0.0
        self.sel = []
        self.next = 0
        self.tol = 1e-9

    def _admit(self, j):
        """Fill the stack to depth M; afterwards swap a record in only if that strictly increases lambda_min."""
        Y = self.rec["Y"]
        if len(self.sel) < self.M:
            self.sel.append(j)
            return
        best = (Y[self.sel] ** 2).sum(axis=0).min()
        bi = -1
        for i in range(self.M):
            cand = list(self.sel)
            cand[i] = j
            v = (Y[cand] ** 2).sum(axis=0).min()
            if v > best:
                best, bi = v, i
        if bi >= 0:
            self.sel[bi] = j

    def step(self, t_k):
        """Admit the records available at t_k, read out the values at t_k, then advance over [t_k, t_k + Ts)."""
        Y, D, Te = self.rec["Y"], self.rec["D"], self.rec["Te"]
        while self.next < len(Te) and Te[self.next] <= t_k + self.tol:
            self._admit(self.next)
            self.next += 1
        if self.sel:
            Lam = (Y[self.sel] ** 2).sum(axis=0)
            S = (Y[self.sel] * D[self.sel]).sum(axis=0)
        else:
            Lam = np.zeros(3)
            S = np.zeros(3)
        lmin = Lam.min()
        val = {"theta_hat": self.theta_hat.copy(), "nu": self.nu0 * np.exp(-self.gamma * self.E),
               "lambda_min": lmin, "E": self.E, "n_stack": len(self.sel)}
        self.E += lmin * self.Ts
        self.theta_hat = self.theta_hat + self.Ts * self.gamma * (S - Lam * self.theta_hat)
        return val

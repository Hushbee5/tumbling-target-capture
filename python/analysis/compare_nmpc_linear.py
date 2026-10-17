"""DEVELOPMENT comparison on the same old trials (development data): V3 with the NMPC upper layer (V3N...PHQAN) vs V3
with the frozen linear MPC (V3PHQA). Reads results/dev_v3/M_t###_V3NPHQAN.mat and M_t###_V3PHQA.mat; prints one line
per trial and writes results/dev_v3/NMPC_vs_LINEAR_dev.md (never overwrites). Not validation."""
import glob
import os
import re
import sys

import numpy as np
import scipy.io as sio

D = r"results\dev_v3"
out = os.path.join(D, "NMPC_vs_LINEAR_dev.md")
assert not os.path.exists(out), "exists"
L = ["# NMPC (V3n, RTI) vs linear MPC (V3) on old trials — DEVELOPMENT, not validation", "",
     "| trial | upper layer | status | D9 | prox | no viol | t milestone [s] | dV full [m/s] | min clearance [m] | "
     "filter active frac | NMPC solve median / p95 [s] | NMPC max slack keep-out / commit [m] | max lin. err |",
     "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
for fn in sorted(glob.glob(os.path.join(D, "M_t*_V3NPHQAN.mat"))):
    t = int(re.search(r"_t(\d+)_", fn).group(1))
    for f, lab in ((os.path.join(D, "M_t%03d_V3PHQA.mat" % t), "linear MPC"), (fn, "NMPC-RTI")):
        if not os.path.exists(f):
            continue
        M = sio.loadmat(f, squeeze_me=True, struct_as_record=False)
        S, H = M["S"], M["H"]
        act = float(np.mean(np.abs(np.asarray(H.Usafe) - np.asarray(H.Umpc)).max(axis=0) > 1e-6)) if hasattr(H, "Usafe") else float("nan")
        nm = ""
        if lab == "NMPC-RTI":
            nm = "%.3f / %.3f | %.2e / %.2e | %.2e" % (S.nmpc_solve_median, S.nmpc_solve_p95, S.nmpc_max_slack[0],
                                                       S.nmpc_max_slack[1], S.nmpc_max_lin_err)
        else:
            nm = "— | — | —"
        L.append("| %d | %s | %s | %s | %d | %d | %.1f | %.4g | %.4g | %.3f | %s |" % (
            t, lab, S.status, S.event, int(S.prox), int(S.no_viol), S.t_kstar, S.DeltaV_full, S.min_clear, act, nm))
open(out, "x", encoding="utf-8").write("\n".join(L) + "\n")
print("\n".join(L))

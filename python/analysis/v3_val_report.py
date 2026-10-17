"""Postflight report of the V3 validation (protocol V3_VALIDATION_PROTOCOL r2-approved; r2 adds the NMPC sub-arm). Written BEFORE any validation
result existed (2026-10-03 12:45 TR). Reads ONLY the run files O_t###_{V3,MPCP,APFP}.mat of a results folder; writes
<out>/V3_VALIDATION_RESULTS.md, <out>/v3_val_runs.csv and <out>/RUN_FILES_MANIFEST.txt (never overwrites).
Usage: python v3_val_report.py <results_dir> <N> <out_dir> [--dev]   (--dev labels every table DEVELOPMENT/DRY RUN)
Endpoints and criteria exactly as protocol sections 5 and 6: Wilson 95 % intervals; medians with n; paired 2x2 tables;
no pooling across arms; no p-values."""
import csv
import hashlib
import math
import os
import sys

import numpy as np
import scipy.io as sio

res_dir, N, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
dev = "--dev" in sys.argv
ARMS = ["V3", "MPCP", "APFP"]
os.makedirs(out_dir, exist_ok=True)
for f in ("V3_VALIDATION_RESULTS.md", "v3_val_runs.csv", "RUN_FILES_MANIFEST.txt"):
    assert not os.path.exists(os.path.join(out_dir, f)), "exists: " + f


def wilson(k, n, z=1.959963984540054):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n; den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (max(0.0, c - h), min(1.0, c + h))


def g(S, k, default=float("nan")):
    return getattr(S, k, default) if hasattr(S, k) else default


runs, manifest, missing = {}, [], []
speed_chk = []           # G lemma: per V3 run, max sampled |rho_dot| vs the bound (u_max - |a_drift|max)/(k1+k2)
N_ORB, U_MAX, K12 = 1.1314e-3, 0.01, 0.08
for t in range(1, N + 1):
    for a in ARMS:
        f = os.path.join(res_dir, "O_t%03d_%s.mat" % (t, a))
        if not os.path.exists(f):
            missing.append((t, a)); continue
        manifest.append("%s  %10d  %s" % (hashlib.sha256(open(f, "rb").read()).hexdigest(), os.path.getsize(f),
                                          os.path.basename(f)))
        M = sio.loadmat(f, squeeze_me=True, struct_as_record=False)
        runs[(t, a)] = M["S"]
        if a == "V3" and hasattr(M["H"], "X"):
            X = np.asarray(M["H"].X); r, v = X[:3], X[3:]
            rho = np.linalg.norm(r, axis=0); rdot = np.sum(r * v, axis=0) / rho
            vmax = float(np.max(np.linalg.norm(v, axis=0))); rmax = float(np.max(rho))
            bound = (U_MAX - (3 * N_ORB**2 * rmax + 2 * N_ORB * vmax)) / K12
            speed_chk.append((t, float(np.max(np.abs(rdot))), bound))

rows = []
for (t, a), S in sorted(runs.items()):
    rows.append({"trial": t, "arm": a, "status": str(g(S, "status", "")), "prox": int(bool(g(S, "prox", 0))),
                 "no_viol": int(bool(g(S, "no_viol", 0))), "safe_success": int(bool(g(S, "safe_success", 0))),
                 "t_kstar": float(g(S, "t_kstar")), "dV_full": float(g(S, "DeltaV_full")),
                 "dV_to_prox": float(g(S, "DeltaV_to_prox")), "rho_final": float(g(S, "rho_final")),
                 "min_clear": float(g(S, "min_clear")), "event": str(g(S, "event", "")),
                 "qp_level1": float(g(S, "qp_level1")), "qp_level2": float(g(S, "qp_level2")),
                 "handoff_t": float(g(S, "handoff_t")), "handoff_nu": float(g(S, "handoff_nu")),
                 "handoff_a_req": float(g(S, "handoff_a_req")), "min_clear_after_handoff": float(g(S, "min_clear_after_handoff")),
                 "w0_degps": float(g(S, "w0_degps")), "wall_s": float(g(S, "wall_s"))})
with open(os.path.join(out_dir, "v3_val_runs.csv"), "x", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else ["trial"]); w.writeheader(); w.writerows(rows)
with open(os.path.join(out_dir, "RUN_FILES_MANIFEST.txt"), "x", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(manifest) + "\n")

L = ["# V3 validation results%s" % (" — DEVELOPMENT / DRY RUN, NOT VALIDATION" if dev else ""), "",
     "Source: run files in `%s` (manifest `RUN_FILES_MANIFEST.txt`, %d files). Missing runs: %s." % (
         res_dir, len(manifest), missing or "none"), "",
     "## Per-arm endpoints (counts out of the runs present; Wilson 95 %)", "",
     "| Arm | runs | COMPLETE | no observed violation | proximity | safe success | median t to milestone [s] (n) | "
     "median dV full [m/s] (n) | median dV to milestone (n) | median range at 800 s, full-horizon [m] (n) | min clearance [m] |",
     "|---|---|---|---|---|---|---|---|---|---|---|"]
per = {}
for a in ARMS:
    R = [r for r in rows if r["arm"] == a]
    n = len(R); comp = sum(r["status"] == "COMPLETE" for r in R)
    def cnt(key):
        k = sum(r[key] for r in R); lo, hi = wilson(k, n)
        return k, "%d/%d [%.1f, %.1f]" % (k, n, 100 * lo, 100 * hi)
    nv = cnt("no_viol"); px = cnt("prox"); ss = cnt("safe_success")
    def med(key, cond=lambda r: True):
        v = [r[key] for r in R if cond(r) and not math.isnan(r[key])]
        return ("%.4g (%d)" % (np.median(v), len(v))) if v else "— (0)"
    per[a] = {"n": n, "no_viol": nv[0], "prox": px[0], "complete": comp}
    L.append("| %s | %d | %d | %s | %s | %s | %s | %s | %s | %s | %s |" % (
        a, n, comp, nv[1], px[1], ss[1], med("t_kstar", lambda r: r["prox"] == 1), med("dV_full"),
        med("dV_to_prox", lambda r: r["prox"] == 1), med("rho_final", lambda r: r["status"] == "COMPLETE"),
        ("%.4g" % min(r["min_clear"] for r in R)) if R else "—"))
V = [r for r in rows if r["arm"] == "V3"]
L += ["", "## V3-specific", "",
      "- GUARD_BREACH: %d; D9 events: %s" % (sum(r["event"] == "GUARD_BREACH" for r in V),
                                            {e: sum(r["event"] == e for r in V) for e in sorted(set(r["event"] for r in V))}),
      "- QP fallbacks: level 1 in %d runs (total %d steps), level 2 in %d runs (total %d steps)" % (
          sum(r["qp_level1"] > 0 for r in V), int(np.nansum([r["qp_level1"] for r in V])),
          sum(r["qp_level2"] > 0 for r in V), int(np.nansum([r["qp_level2"] for r in V]))),
      "- handoff: median nu %.3g, median a_req %.3g m/s^2, min clearance after handoff %.4g m (over %d NORMAL runs)" % (
          np.nanmedian([r["handoff_nu"] for r in V]) if V else float("nan"),
          np.nanmedian([r["handoff_a_req"] for r in V]) if V else float("nan"),
          np.nanmin([r["min_clear_after_handoff"] for r in V]) if any(r["event"] == "NORMAL" for r in V) else float("nan"),
          sum(r["event"] == "NORMAL" for r in V)),
      "- G lemma (body-row individual feasibility): max sampled |rho_dot| over V3 runs %.4f m/s; runs where it exceeds "
      "the per-run bound: %d of %d" % (max([c[1] for c in speed_chk] or [float("nan")]),
                                       sum(c[1] > c[2] for c in speed_chk), len(speed_chk)), ""]
# paired 2x2
L += ["## Paired 2×2 tables (same trials)", ""]
for b in ("MPCP", "APFP"):
    for key in ("prox", "no_viol"):
        pairs = [(runs_t, ) for runs_t in range(1, N + 1)]
        tab = {(1, 1): 0, (1, 0): 0, (0, 1): 0, (0, 0): 0}; excl = 0
        for t in range(1, N + 1):
            ra = next((r for r in rows if r["trial"] == t and r["arm"] == "V3"), None)
            rb = next((r for r in rows if r["trial"] == t and r["arm"] == b), None)
            if ra is None or rb is None:
                excl += 1; continue
            tab[(ra[key], rb[key])] += 1
        L.append("- %s, V3 vs %s: both %d | V3 only %d | %s only %d | neither %d | excluded (missing run) %d" % (
            key, b, tab[(1, 1)], tab[(1, 0)], b, tab[(0, 1)], tab[(0, 0)], excl))
L.append("")
# criteria (protocol §6), only meaningful for the approved validation
v = per.get("V3", {"n": 0, "no_viol": 0, "prox": 0})
k_need = next((k for k in range(0, v["n"] + 1) if wilson(k, v["n"])[0] > 0.198), None) if v["n"] else None
g2 = sum(r["event"] == "GUARD_BREACH" for r in V); l2 = int(np.nansum([r["qp_level2"] for r in V]))
c1 = v["n"] > 0 and v["no_viol"] >= v["n"] - 1 and g2 == 0 and l2 == 0
c2 = v["n"] > 0 and k_need is not None and v["prox"] >= k_need
L += ["## Protocol §6 criteria%s" % (" (shown for the pipeline check only)" if dev else ""), "",
      "1. no observed violation in >= N-1 V3 runs (%d/%d), zero GUARD_BREACH (%d), zero level-2 fallbacks (%d): **%s**" % (
          v["no_viol"], v["n"], g2, l2, "MET" if c1 else "NOT MET"),
      "2. V3 proximity >= %s of %d (Wilson lower bound > 0.198; got %d): **%s**" % (k_need, v["n"], v["prox"],
                                                                                   "MET" if c2 else "NOT MET"),
      "", "Overall: V3 **%s** its predeclared validation criteria on this envelope." % (
          "met" if (c1 and c2) else "did NOT meet"), "",
      "Comparisons with MPC-P and APF-P are descriptive; no superiority is claimed by the protocol.", ""]
# ---- protocol r2 sub-arm: NMPC (V3N) on the first trials, descriptive and paired with V3 (no criterion beyond §6b)
nm = {}
for t in range(1, N + 1):
    f = os.path.join(res_dir, "O_t%03d_V3N.mat" % t)
    if os.path.exists(f):
        manifest.append("%s  %10d  %s" % (hashlib.sha256(open(f, "rb").read()).hexdigest(), os.path.getsize(f),
                                          os.path.basename(f)))
        nm[t] = sio.loadmat(f, squeeze_me=True, struct_as_record=False)["S"]
if nm:
    L += ["## NMPC sub-arm (V3N) vs V3 on the same trials (descriptive, protocol r2 §1b/§6b)", "",
          "| trial | V3N status | V3N prox / no viol | V3 prox / no viol | t milestone V3N / V3 [s] | dV to milestone V3N / V3 "
          "| dV full V3N / V3 | min clearance V3N / V3 [m] | NMPC solve median / p95 [s] | NMPC failures | max slack keep-out / commit |",
          "|---|---|---|---|---|---|---|---|---|---|---|"]
    for t, S in sorted(nm.items()):
        r3v = next((r for r in rows if r["trial"] == t and r["arm"] == "V3"), None)
        def gv(r, k):
            return r[k] if r is not None else float("nan")
        L.append("| %d | %s | %d / %d | %s / %s | %.1f / %.1f | %.4g / %.4g | %.4g / %.4g | %.4g / %.4g | %.3f / %.3f | %d | %.1e / %.1e |" % (
            t, g(S, "status", ""), int(bool(g(S, "prox", 0))), int(bool(g(S, "no_viol", 0))),
            gv(r3v, "prox"), gv(r3v, "no_viol"), float(g(S, "t_kstar")), gv(r3v, "t_kstar"),
            float(g(S, "DeltaV_to_prox")), gv(r3v, "dV_to_prox"), float(g(S, "DeltaV_full")), gv(r3v, "dV_full"),
            float(g(S, "min_clear")), gv(r3v, "min_clear"), float(g(S, "nmpc_solve_median")), float(g(S, "nmpc_solve_p95")),
            int(g(S, "nmpc_failures", 0)), float(g(S, "nmpc_max_slack_keepout")), float(g(S, "nmpc_max_slack_commit"))))
    nv = sum(bool(g(S, "no_viol", 0)) for S in nm.values()); l2n = sum(float(g(S, "qp_level2", 0)) > 0 for S in nm.values())
    L += ["", "§6b (V3N): no observed violation in all %d runs (%d) and zero level-2 fallbacks (%d runs with level 2): **%s**. "
          "Real-time: not claimed (interpreted MATLAB)." % (len(nm), nv, l2n, "MET" if (nv == len(nm) and l2n == 0) else "NOT MET"), ""]
    with open(os.path.join(out_dir, "RUN_FILES_MANIFEST.txt"), "a", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(manifest[-len(nm):]) + "\n")
with open(os.path.join(out_dir, "V3_VALIDATION_RESULTS.md"), "x", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(L))
print("\n".join(L))

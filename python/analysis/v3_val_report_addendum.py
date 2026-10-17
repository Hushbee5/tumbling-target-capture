"""V3_VAL_REPORT_ADDENDUM (A1)  Reporting addendum to the frozen postflight of protocol r2.

Written 2026-10-03 (about 20:00 TR) BEFORE the postflight, with the remaining validation outcomes unseen, in response to
an independent read-only code audit (review/2026-10-03/AUDIT_V3_CODE_independent_2026-10-03.md). Rules: protocols/
V3_VALIDATION_PROTOCOL_r2_ADDENDUM_A1.md. The frozen report (v3_val_report.py, SHA-256 43f2d9d3...) stays the PRIMARY
output and is never edited; A1 only adds:
  G   completeness and settings gate (every expected file present; Tsim, nsub, table SHA, trial and arm per file;
      every run RETURNED), and a byte check against the frozen report's RUN_FILES_MANIFEST.txt when given;
  C   the section-6 criteria evaluated against N (not the runs present), with missing or non-returned V3 runs counted
      conservatively (they can only make "met" harder, never easier); agreement with the frozen verdict is shown;
  M1  V3 proximity-and-no-violation WITHOUT a guard breach;  M2  median dV over COMPLETE runs only;
  M3  baseline NUMERICAL_FAILURE runs reported as unknown;   m1  max KKT primal residual, handoff t / rho medians,
      V3N failed runs;  m2  NaN-safe minimum clearance;  S1  genuineness of every level-2 fallback step.
Usage: python v3_val_report_addendum.py <results_dir> <N> <out_dir> [--frozen-report <dir>] [--dev]
Writes <out_dir>/A1_ADDENDUM_RESULTS.md (never overwrites). Prints only a one-line summary."""
import hashlib
import math
import os
import re
import sys

import numpy as np
import scipy.io as sio

res_dir, N, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
dev = "--dev" in sys.argv
frozen_dir = sys.argv[sys.argv.index("--frozen-report") + 1] if "--frozen-report" in sys.argv else None
os.makedirs(out_dir, exist_ok=True)
OUT = os.path.join(out_dir, "A1_ADDENDUM_RESULTS.md")
assert not os.path.exists(OUT), "exists: " + OUT
TABLE_SHA = "5e9d03b3e08153b20c4cde1d15190c57718d3e33458be8c3ec496750d409ccb8"
TSIM, NSUB, U_MAX, R_SAFE = 800.0, 2.0, 0.01, 0.70
frozen_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "v3_val_report.py"), encoding="utf-8").read()
assert "N_ORB, U_MAX, K12 = 1.1314e-3, 0.01, 0.08" in frozen_src        # same u_max as the frozen report
ARMS, NV3N = ["V3", "MPCP", "APFP"], min(10, N)


def wilson(k, n, z=1.959963984540054):                                   # identical to the frozen report
    if n == 0:
        return float("nan"), float("nan")
    ph = k / n; den = 1 + z * z / n
    c = (ph + z * z / (2 * n)) / den; h = z * math.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n)) / den
    return max(0.0, c - h), min(1.0, c + h)


def g(S, k, d=float("nan")):
    v = getattr(S, k, d)
    if isinstance(v, np.ndarray) and v.size == 1:
        v = v.item()
    return d if (isinstance(v, np.ndarray) and v.size == 0) else v


def fnum(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return float("nan")


runs, files, issues = {}, {}, []
for a in ARMS + ["V3N"]:
    for t in range(1, (NV3N if a == "V3N" else N) + 1):
        f = os.path.join(res_dir, "O_t%03d_%s.mat" % (t, a))
        if not os.path.exists(f):
            issues.append("MISSING %s t%03d" % (a, t)); continue
        files[(t, a)] = f
        M = sio.loadmat(f, squeeze_me=True, struct_as_record=False)
        S = M["S"]; runs[(t, a)] = (S, M.get("H"))
        if int(g(S, "trial", -1)) != t or str(g(S, "arm", "")) != a:
            issues.append("IDENTITY %s t%03d (file says %s t%s)" % (a, t, g(S, "arm", "?"), g(S, "trial", "?")))
        if not dev:
            if fnum(g(S, "Tsim")) != TSIM: issues.append("TSIM %s t%03d = %s" % (a, t, g(S, "Tsim")))
            if str(g(S, "table_sha256", "")) != TABLE_SHA: issues.append("TABLE_SHA %s t%03d" % (a, t))
        if fnum(g(S, "nsub")) != NSUB: issues.append("NSUB %s t%03d = %s" % (a, t, g(S, "nsub")))
        if str(g(S, "guard", "")) != "RETURNED":
            issues.append("NOT_RETURNED %s t%03d: %s" % (a, t, g(S, "guard", "?")))

byte_check = "not requested"
if frozen_dir:
    man = {}
    for line in open(os.path.join(frozen_dir, "RUN_FILES_MANIFEST.txt"), encoding="utf-8"):
        p = line.split()
        if len(p) == 3: man[p[2]] = p[0]
    bad = [os.path.basename(f) for f in files.values()
           if man.get(os.path.basename(f)) != hashlib.sha256(open(f, "rb").read()).hexdigest()]
    byte_check = "all %d files identical to the frozen report's manifest" % len(files) if not bad else \
                 "MISMATCH or absent in the frozen manifest: %s" % ", ".join(bad[:10])

L = ["# A1 reporting addendum to the V3 validation%s" % (" — DEVELOPMENT / DRY RUN, NOT VALIDATION" if dev else ""), "",
     "Rules: `protocols/V3_VALIDATION_PROTOCOL_r2_ADDENDUM_A1.md`. The frozen report (`V3_VALIDATION_RESULTS.md`) is "
     "the primary output; this file adds to it and changes nothing in it.", "",
     "## G. Completeness and settings gate", "",
     "- expected files: %d per main arm (%d total) + %d V3N; present: %d; byte check vs frozen manifest: %s" % (
         N, 3 * N, NV3N, len(files), byte_check),
     "- gate issues: %s" % ("none" if not issues else "%d" % len(issues))]
L += ["  - %s" % s for s in issues[:40]]

# ---- criteria (A1): against N; missing or non-returned V3 runs counted conservatively
V = {t: runs[(t, "V3")][0] for t in range(1, N + 1) if (t, "V3") in runs}
v3_unobserved = [t for t in range(1, N + 1) if t not in V or str(g(V[t], "guard", "")) != "RETURNED"]
nv = sum(bool(g(S, "no_viol", 0)) for t, S in V.items() if t not in v3_unobserved)
px = sum(bool(g(S, "prox", 0)) for t, S in V.items() if t not in v3_unobserved)
gb = sum(str(g(S, "event", "")) == "GUARD_BREACH" for S in V.values())
l2 = int(np.nansum([fnum(g(S, "qp_level2", 0)) for S in V.values()]))
k_need = next((k for k in range(0, N + 1) if wilson(k, N)[0] > 0.198), None)
c1 = (not v3_unobserved) and nv >= N - 1 and gb == 0 and l2 == 0
c2 = k_need is not None and px >= k_need
# frozen-equivalent verdict (runs present, as v3_val_report.py computes it) for the agreement line
n_pres = len(V); nv_f = sum(bool(g(S, "no_viol", 0)) for S in V.values()); px_f = sum(bool(g(S, "prox", 0)) for S in V.values())
k_f = next((k for k in range(0, n_pres + 1) if wilson(k, n_pres)[0] > 0.198), None) if n_pres else None
c1_f = n_pres > 0 and nv_f >= n_pres - 1 and gb == 0 and l2 == 0
c2_f = n_pres > 0 and k_f is not None and px_f >= k_f
L += ["", "## C. Section-6 criteria under A1 (against N = %d)" % N, "",
      "1. all %d V3 runs present and RETURNED (%s), no observed violation >= %d (%d), zero GUARD_BREACH at control "
      "samples (%d), zero level-2 fallback steps (%d): **%s**" % (
          N, "yes" if not v3_unobserved else "NO: t" + ", t".join("%03d" % t for t in v3_unobserved), N - 1, nv, gb, l2,
          "MET" if c1 else "NOT MET"),
      "2. V3 proximity >= %s of %d, missing or non-returned runs counted as not reached (got %d): **%s**" % (
          k_need, N, px, "MET" if c2 else "NOT MET"),
      "", "A1 overall: V3 **%s** its predeclared criteria. Frozen-report logic on the same files: **%s**. Agreement: "
      "**%s**." % ("met" if (c1 and c2) else "did NOT meet", "met" if (c1_f and c2_f) else "did NOT meet",
                   "yes" if (c1 and c2) == (c1_f and c2_f) else "NO (A1 is the conservative reading; both are reported)")]

# ---- M1-M3, m1, m2 per arm
L += ["", "## M. Corrected and added quantities (A1)", "",
      "| Arm | runs present | COMPLETE | other statuses | prox & no viol & no guard breach (M1) | median dV whole run, "
      "COMPLETE only [m/s] (n) (M2) | NUMERICAL_FAILURE (M3: prox/no-viol unknown) | min clearance, NaN-safe [m] (m2) |",
      "|---|---|---|---|---|---|---|---|"]
for a in ARMS:
    R = [runs[(t, a)][0] for t in range(1, N + 1) if (t, a) in runs]
    st = [str(g(S, "status", "")) for S in R]
    comp = [S for S in R if str(g(S, "status", "")) == "COMPLETE"]
    other = {s: st.count(s) for s in sorted(set(st)) if s != "COMPLETE"}
    ss = sum(bool(g(S, "prox", 0)) and bool(g(S, "no_viol", 0)) and str(g(S, "event", "")) != "GUARD_BREACH" for S in R)
    lo, hi = wilson(ss, N)
    dv = [fnum(g(S, "DeltaV_full")) for S in comp]; dv = [x for x in dv if not math.isnan(x)]
    nf = st.count("NUMERICAL_FAILURE")
    mc = [fnum(g(S, "min_clear")) for S in R]; mc = [x for x in mc if not math.isnan(x)]
    L.append("| %s | %d | %d | %s | %d/%d [%.1f, %.1f] | %s | %d | %s |" % (
        a, len(R), len(comp), other or "none", ss, N, 100 * lo, 100 * hi,
        ("%.4g (%d)" % (np.median(dv), len(dv))) if dv else "— (0)", nf, ("%.4g" % min(mc)) if mc else "—"))
kkt = [fnum(g(S, "qp_max_primal")) for S in V.values()]; kkt = [x for x in kkt if not math.isnan(x)]
nrm = [S for S in V.values() if str(g(S, "event", "")) == "NORMAL"]
ht = [fnum(g(S, "handoff_t")) for S in nrm]; hr = [fnum(g(S, "handoff_rho")) for S in nrm]
L += ["", "- V3 max KKT primal residual over all runs: %s (m1)" % (("%.3g" % max(kkt)) if kkt else "—"),
      "- V3 handoff over %d NORMAL runs: median t %s s, median rho %s m (m1). Clearance after the handoff in the frozen "
      "report is sampled-only (m3)." % (len(nrm), ("%.1f" % np.median(ht)) if ht else "—",
                                        ("%.4g" % np.median(hr)) if hr else "—")]
VN = [runs[(t, "V3N")][0] for t in range(1, NV3N + 1) if (t, "V3N") in runs]
L.append("- V3N: %d of %d present; statuses %s; NMPC step failures summed over runs: %d. NMPC solve time = the whole "
         "RTI step (rollout, finite-difference Jacobians, condensing, QP) measured with 3 processes on 2 cores (m7)." % (
             len(VN), NV3N, {s: [str(g(S, "status", "")) for S in VN].count(s) for s in
                             sorted(set(str(g(S, "status", "")) for S in VN))},
             int(np.nansum([fnum(g(S, "nmpc_failures", 0)) for S in VN]))))

# ---- S1 level-2 genuineness (body row infeasible inside the box: b_body + u_max*||A_body||_1 < 0)
lv2 = []
for (t, a), (S, H) in sorted(runs.items()):
    if a not in ("V3", "V3N") or H is None or fnum(g(S, "qp_level2", 0)) <= 0:
        continue
    v3 = H.v3
    lev = np.atleast_1d(np.asarray(v3.qp_level, float)); A = np.asarray(v3.qp_A, float); b = np.asarray(v3.qp_b, float)
    for k in np.flatnonzero(lev == 2):
        Ab, bb = A[0, :, k], b[0, k]
        lv2.append((a, t, int(k), bb + U_MAX * np.sum(np.abs(Ab)) < 0))
L += ["", "## S1. Level-2 fallback steps", "",
      "- level-2 steps found: %d; genuine (body row infeasible inside the box): %d; NOT genuine: %d%s" % (
          len(lv2), sum(x[3] for x in lv2), sum(not x[3] for x in lv2),
          "" if all(x[3] for x in lv2) else " (" + ", ".join("%s t%03d k%d" % x[:3] for x in lv2 if not x[3])[:300] + ")"),
      "", "## Wording (S2)", "",
      "GUARD_BREACH is detected at control samples only; state \"no guard breach at the control samples\".", ""]
with open(OUT, "x", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(L))
print("A1 written: %s | gate issues %d | A1 verdict %s | agreement with frozen logic %s" % (
    OUT, len(issues), "met" if (c1 and c2) else "not met", "yes" if (c1 and c2) == (c1_f and c2_f) else "NO"))

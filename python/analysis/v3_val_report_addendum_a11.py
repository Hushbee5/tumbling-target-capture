"""V3_VAL_REPORT_ADDENDUM_A11 (A1.1)  Reporting addendum to the frozen postflight of protocol r2, revision 1 of A1.

A1 (v3_val_report_addendum.py, e65f377c..., frozen 2026-10-03 19:52 TR) is superseded by this file after a second
independent, blind audit (review/2026-10-04/AUDIT_PIPELINE_independent_2026-10-04.md); written 2026-10-04 about 12:10 TR,
BEFORE the postflight and with the remaining outcomes unseen. Rules: protocols/V3_VALIDATION_PROTOCOL_r2_ADDENDUM_A1.md,
section "A1.1". Changes relative to A1 (all make the gate stricter or the numbers more faithful; none touches a
threshold): the byte check against the frozen report's RUN_FILES_MANIFEST is REQUIRED and gating; N must be 60 outside
--dev; the frozen script's SHA-256 is verified; gate issues make the A1 verdict NOT EVALUABLE (= not met); agreement is
also checked against the frozen report's PRINTED verdict; M1 counts only COMPLETE runs; baseline counts over COMPLETE
runs with unknowns stated (M3); S1 robust to K = 1 and reports 1-based steps; NaN-safe medians; refusals are explicit
exits (not asserts). The frozen report stays the PRIMARY output; A1.1 adds to it.
Usage: python v3_val_report_addendum_a11.py <results_dir> <N> <out_dir> --frozen-report <dir> [--dev]
Writes <out_dir>/A1_1_ADDENDUM_RESULTS.md (never overwrites). Prints a one-line summary only."""
import hashlib
import math
import os
import re
import sys

import numpy as np
import scipy.io as sio


def stop(msg):
    sys.exit("STOP: " + msg)


res_dir, N, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
dev = "--dev" in sys.argv
if "--frozen-report" not in sys.argv:
    stop("--frozen-report <dir> is required (byte check against the frozen report's run manifest)")
frozen_dir = sys.argv[sys.argv.index("--frozen-report") + 1]
if not dev and N != 60:
    stop("N must be 60 for the validation (got %d)" % N)
os.makedirs(out_dir, exist_ok=True)
OUT = os.path.join(out_dir, "A1_1_ADDENDUM_RESULTS.md")
if os.path.exists(OUT):
    stop("exists: " + OUT)
HERE = os.path.dirname(os.path.abspath(__file__))
FROZEN_SHA = "43f2d9d3b0c22bca6f628370c558ebd50f9030e284f438f850270f7918ff07eb"
if hashlib.sha256(open(os.path.join(HERE, "v3_val_report.py"), "rb").read()).hexdigest() != FROZEN_SHA:
    stop("v3_val_report.py is not the frozen postflight script")
TABLE_SHA = "5e9d03b3e08153b20c4cde1d15190c57718d3e33458be8c3ec496750d409ccb8"
TSIM, NSUB, U_MAX = 800.0, 2.0, 0.01                     # u_max: params.m:64 and the frozen report's U_MAX
ARMS, NV3N = ["V3", "MPCP", "APFP"], min(10, N)


def wilson(k, n, z=1.959963984540054):                   # identical to the frozen report
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


def med(vals):
    v = [x for x in vals if not math.isnan(x)]
    return (float(np.median(v)), len(v)) if v else (float("nan"), 0)


runs, files, block, notes = {}, {}, [], []
for a in ARMS + ["V3N"]:
    for t in range(1, (NV3N if a == "V3N" else N) + 1):
        f = os.path.join(res_dir, "O_t%03d_%s.mat" % (t, a))
        if not os.path.exists(f):
            block.append("MISSING %s t%03d" % (a, t)); continue
        files[(t, a)] = f
        M = sio.loadmat(f, squeeze_me=True, struct_as_record=False)
        S = M["S"]; runs[(t, a)] = (S, M.get("H"))
        if int(fnum(g(S, "trial", -1))) != t or str(g(S, "arm", "")) != a:
            block.append("IDENTITY %s t%03d (file says %s t%s)" % (a, t, g(S, "arm", "?"), g(S, "trial", "?")))
        if not dev:
            if fnum(g(S, "Tsim")) != TSIM: block.append("TSIM %s t%03d = %s" % (a, t, g(S, "Tsim")))
            if str(g(S, "table_sha256", "")) != TABLE_SHA: block.append("TABLE_SHA %s t%03d" % (a, t))
        if fnum(g(S, "nsub")) != NSUB: block.append("NSUB %s t%03d = %s" % (a, t, g(S, "nsub")))
        if str(g(S, "guard", "")) != "RETURNED":
            (block if a == "V3" else notes).append("NOT_RETURNED %s t%03d: %s" % (a, t, g(S, "guard", "?")))

man = {}
for line in open(os.path.join(frozen_dir, "RUN_FILES_MANIFEST.txt"), encoding="utf-8"):
    p = line.split()
    if len(p) == 3: man[p[2]] = p[0]
bad = [os.path.basename(f) for f in files.values()
       if man.get(os.path.basename(f)) != hashlib.sha256(open(f, "rb").read()).hexdigest()]
extra = sorted(set(man) - {os.path.basename(f) for f in files.values()})
if bad: block.append("BYTES differ from / absent in the frozen manifest: %s" % ", ".join(bad[:10]))
if extra: block.append("frozen manifest lists files not analysed here: %s" % ", ".join(extra[:10]))
frozen_md = open(os.path.join(frozen_dir, "V3_VALIDATION_RESULTS.md"), encoding="utf-8").read()
mo = re.search(r"^Overall: V3 \*\*(met|did NOT meet)\*\* its predeclared validation criteria", frozen_md, flags=re.M)
if not mo: block.append("frozen report: printed verdict not found")
frozen_printed = mo.group(1) if mo else "?"
frozen_dry = "DRY RUN" in frozen_md.splitlines()[0]
if frozen_dry != dev: block.append("frozen report dry-run flag (%s) differs from this run's mode (dev=%s)" % (frozen_dry, dev))

title = "# A1.1 reporting addendum to the V3 validation (N = %d)%s" % (N, " — DEVELOPMENT / DRY RUN, NOT VALIDATION" if dev else "")
L = [title, "",
     "Rules: `protocols/V3_VALIDATION_PROTOCOL_r2_ADDENDUM_A1.md` (A1 and its revision A1.1). The frozen report "
     "(`V3_VALIDATION_RESULTS.md`) is the primary output; this file adds to it and changes nothing in it.", "",
     "## G. Completeness and settings gate", "",
     "- expected files: %d per main arm (%d) + %d V3N; present: %d; frozen manifest: %d files" % (
         N, 3 * N, NV3N, len(files), len(man)),
     "- gate issues: %s" % ("none" if not block else "%d (BLOCKING)" % len(block))]
L += ["  - %s" % s for s in block[:40]]
L += ["- non-blocking notes (baseline / V3N runs that did not return; reported as unknown below): %s" % (
    "none" if not notes else "; ".join(notes[:20]))]

V = {t: runs[(t, "V3")][0] for t in range(1, N + 1) if (t, "V3") in runs}
unobs = [t for t in range(1, N + 1) if t not in V or str(g(V[t], "guard", "")) != "RETURNED"]
nv = sum(bool(g(S, "no_viol", 0)) for t, S in V.items() if t not in unobs)
px = sum(bool(g(S, "prox", 0)) for t, S in V.items() if t not in unobs)
gb = sum(str(g(S, "event", "")) == "GUARD_BREACH" for S in V.values())
l2 = int(np.nansum([fnum(g(S, "qp_level2", 0)) for S in V.values()]))
k_need = next((k for k in range(0, N + 1) if wilson(k, N)[0] > 0.198), None)
c1 = (not unobs) and nv >= N - 1 and gb == 0 and l2 == 0
c2 = k_need is not None and px >= k_need
n_pres = len(V); nv_f = sum(bool(g(S, "no_viol", 0)) for S in V.values()); px_f = sum(bool(g(S, "prox", 0)) for S in V.values())
k_f = next((k for k in range(0, n_pres + 1) if wilson(k, n_pres)[0] > 0.198), None) if n_pres else None
logic_f = "met" if (n_pres > 0 and nv_f >= n_pres - 1 and gb == 0 and l2 == 0 and k_f is not None and px_f >= k_f) else "did NOT meet"
a1 = "NOT EVALUABLE" if block else ("met" if (c1 and c2) else "did NOT meet")
agree = (a1 == "met") == (frozen_printed == "met")
L += ["", "## C. Section-6 criteria under A1.1 (against N = %d)" % N, "",
      "1. all %d V3 runs present and RETURNED (%s), no observed violation >= %d (%d), no guard breach at the control "
      "samples (%d), zero level-2 fallback steps (%d): **%s**" % (
          N, "yes" if not unobs else "NO: t" + ", t".join("%03d" % t for t in unobs), N - 1, nv, gb, l2,
          "MET" if c1 else "NOT MET"),
      "2. V3 proximity >= %s of %d, missing or non-returned runs counted as not reached (got %d): **%s**" % (
          k_need, N, px, "MET" if c2 else "NOT MET"),
      "", "A1 overall: V3 **%s** its predeclared criteria%s." % (a1, " (gate issues above)" if block else ""),
      "Frozen report, printed verdict: **%s**; frozen logic re-computed on the same files: **%s**. Agreement of A1.1 "
      "with the printed verdict: **%s**%s." % (frozen_printed, logic_f, "yes" if agree else "NO",
                                              "" if agree else " (the A1.1 reading governs every claim; both are reported)")]

L += ["", "## M. Corrected and added quantities (A1.1)", "",
      "| Arm | present | COMPLETE | other statuses | proximity, COMPLETE runs | no observed violation, COMPLETE runs | "
      "unknown (not COMPLETE) | prox & no viol & COMPLETE & no guard breach (M1) | median dV whole run, COMPLETE only [m/s] (n) (M2) | "
      "min clearance, NaN-safe [m] (m2) |", "|---|---|---|---|---|---|---|---|---|---|"]
for a in ARMS:
    R = [runs[(t, a)][0] for t in range(1, N + 1) if (t, a) in runs]
    st = [str(g(S, "status", "")) for S in R]
    comp = [S for S in R if str(g(S, "status", "")) == "COMPLETE"]
    other = {s: st.count(s) for s in sorted(set(st)) if s != "COMPLETE"}
    pxc = sum(bool(g(S, "prox", 0)) for S in comp); nvc = sum(bool(g(S, "no_viol", 0)) for S in comp)
    ss = sum(bool(g(S, "prox", 0)) and bool(g(S, "no_viol", 0)) and str(g(S, "event", "")) != "GUARD_BREACH" for S in comp)
    lo, hi = wilson(ss, N)
    dv, ndv = med([fnum(g(S, "DeltaV_full")) for S in comp])
    mc = [fnum(g(S, "min_clear")) for S in R]; mc = [x for x in mc if not math.isnan(x)]
    L.append("| %s | %d | %d | %s | %d/%d | %d/%d | %d | %d/%d [%.1f, %.1f] | %s | %s |" % (
        a, len(R), len(comp), other or "none", pxc, N, nvc, N, N - len(comp), ss, N, 100 * lo, 100 * hi,
        ("%.4g (%d)" % (dv, ndv)) if ndv else "— (0)", ("%.4g" % min(mc)) if mc else "—"))
kkt = [fnum(g(S, "qp_max_primal")) for S in V.values()]; kkt = [x for x in kkt if not math.isnan(x)]
nrm = [S for S in V.values() if str(g(S, "event", "")) == "NORMAL"]
ht, nht = med([fnum(g(S, "handoff_t")) for S in nrm]); hr, nhr = med([fnum(g(S, "handoff_rho")) for S in nrm])
L += ["", "- V3 max KKT primal residual over all runs: %s (m1)" % (("%.3g" % max(kkt)) if kkt else "—"),
      "- V3 handoff over %d NORMAL runs: median t %s s (n %d), median rho %s m (n %d) (m1). Clearance after the handoff "
      "in the frozen report is sampled-only (m3)." % (len(nrm), ("%.1f" % ht) if nht else "—", nht,
                                                      ("%.4g" % hr) if nhr else "—", nhr)]
VN = [runs[(t, "V3N")][0] for t in range(1, NV3N + 1) if (t, "V3N") in runs]
vst = [str(g(S, "status", "")) for S in VN]
L.append("- V3N: %d of %d present; statuses %s; NMPC step failures summed over runs: %d; level-2 fallback runs: %d. "
         "NMPC solve time = the whole RTI step (rollout, finite-difference Jacobians, condensing, QP), measured with 3 "
         "processes on a 2-core laptop (m7)." % (len(VN), NV3N, {s: vst.count(s) for s in sorted(set(vst))},
                                                 int(np.nansum([fnum(g(S, "nmpc_failures", 0)) for S in VN])),
                                                 sum(fnum(g(S, "qp_level2", 0)) > 0 for S in VN)))

lv2 = []
for (t, a), (S, H) in sorted(runs.items()):
    if a not in ("V3", "V3N") or H is None or not (fnum(g(S, "qp_level2", 0)) > 0):
        continue
    v3 = H.v3
    lev = np.atleast_1d(np.asarray(v3.qp_level, float)).ravel()
    A = np.asarray(v3.qp_A, float); b = np.asarray(v3.qp_b, float)
    if A.ndim == 2: A = A[:, :, None]
    if b.ndim == 1: b = b[:, None]
    for k in np.flatnonzero(lev == 2):
        lv2.append((a, t, int(k) + 1, bool(b[0, k] + U_MAX * np.sum(np.abs(A[0, :, k])) < 0)))
L += ["", "## S1. Level-2 fallback steps", "",
      "- level-2 steps found: %d; genuine (body row infeasible inside the box): %d; NOT genuine: %d%s" % (
          len(lv2), sum(x[3] for x in lv2), sum(not x[3] for x in lv2),
          "" if all(x[3] for x in lv2) else " (" + ", ".join("%s t%03d step %d" % x[:3] for x in lv2 if not x[3])[:300] + ")"),
      "", "## Wording (S2)", "",
      "GUARD_BREACH is detected at control samples only; state \"no guard breach at the control samples\".", ""]
with open(OUT, "x", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(L))
print("A1.1 written: %s | blocking gate issues %d | A1.1 verdict %s | frozen printed %s | agreement %s" % (
    OUT, len(block), a1, frozen_printed, "yes" if agree else "NO"))

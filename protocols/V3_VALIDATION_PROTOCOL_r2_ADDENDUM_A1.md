# Addendum A1 to the V3 validation protocol r2 (reporting only), 2026-10-03, about 20:00 TR

**Status.** Written and frozen while the campaign was running, BEFORE the postflight.
- **Seen so far:** the outcome lines of trials 1–4 (17:27) and of t005/t006 MPC-P and APF-P plus t001 V3N (17:46), as logged in the technical report's integrity log.
- **Not seen:** no other outcome, no aggregate, no criterion value.
- **The approved protocol is unchanged:** `V3_VALIDATION_PROTOCOL_r2-approved.md`, `d7221cad…`. So are its arms, trials, settings, thresholds and the frozen postflight script `v3_val_report.py` (`43f2d9d3…`), which stays the PRIMARY output and is reported as it is.

**Why.** An independent, read-only, outcome-blind code audit (`review/2026-10-03/AUDIT_V3_CODE_independent_2026-10-03.md`) found that the frozen postflight:
- (C1) evaluates the §6 criteria against the runs present instead of N;
- (C2) lets a V3 run that returned no output contribute zero guard breaches and zero level-2 fallbacks;
- (M1) can count a guard-breach run as a safe success;
- (M2) takes the "dV full" median over truncated runs;
- (M3) gives baseline runs with a numerical failure a proximity and violation verdict from their truncated history.

The protocol is silent on these cases. The auditor recommended a documented addendum rather than editing the script.

## Rules (applied by `development/analysis/v3_val_report_addendum.py`, reported NEXT TO the frozen report)

**G. Completeness and settings gate.**
- Expected: 60 run files per main arm and 10 V3N files.
- Each must carry Tsim = 800, nsub = 2, the table SHA-256 `5e9d03b3…`, and the trial and arm of its file name.
- Each run must have returned (`S.guard = RETURNED`).
- The files analysed must be byte-identical to the frozen report's `RUN_FILES_MANIFEST.txt`.
- Every deviation is listed.

**C. Criteria under A1.**
- Criterion 1 additionally requires all 60 V3 runs to be present and RETURNED. A missing or non-returned V3 run is an unobserved run, and criterion 1 is then NOT MET.
- Criterion 2 is evaluated against N = 60, with missing or non-returned runs counted as not reaching the milestone.
- The rulings are conservative by construction: they can only turn "met" into "not met", never the reverse.
- Both verdicts are reported, the frozen one and A1's. If they differ, the difference is stated, and the A1 reading is the one used for any claim.

**M. Additional or corrected quantities, labelled A1:**
- (M1) proximity and no observed violation without a guard breach;
- (M2) the median Δv over the whole run, over COMPLETE runs only, with n;
- (M3) baseline NUMERICAL_FAILURE runs reported as unknown for proximity and violation, with their count;
- (m1) the V3 maximum KKT primal residual, the handoff t and ρ medians over NORMAL runs, and the V3N statuses and NMPC step failures;
- (m2) a NaN-safe minimum clearance.

**S1. Level-2 genuineness.** For every level-2 fallback step, the recorded body row (`H.v3.qp_A(1,:,k)`, `qp_b(1,k)`) is checked for infeasibility inside the box: b + u_max‖A‖₁ < 0. Any non-genuine step is listed.

**Wording.**
- (S2) "No guard breach" is stated as "at the control samples".
- (m3) Clearance after the handoff is sampled-only.
- (m7) The NMPC solve time is the whole real-time-iteration step, measured with 3 processes on 2 cores.

**What A1 does not do.** It changes no threshold, arm, trial, setting or run. It does not re-run anything. It does not replace the frozen report.

**Expected effect.** In the auditor's analysis there is none on a §6 verdict if all 180 main runs exist and returned an output. A1 then only adds quantities.

Script SHA-256 at freeze: see the line appended below.

Addendum script `development/analysis/v3_val_report_addendum.py` SHA-256 at freeze (2026-10-03 19:52 TR): e65f377c9317145d537dbe0bb3beb7e9ebf5eb5018967e3d6c20717f73f4ebdb

---

## Revision A1.1 (2026-10-04, 11:52 TR; written before the postflight, remaining outcomes still unseen)

**Why.** A second independent, blind, read-only audit (`review/2026-10-04/AUDIT_PIPELINE_independent_2026-10-04.md`) found that A1's refusal chain leaked:
- the byte check did not gate;
- N was not pinned to 60;
- gate issues did not affect the A1 verdict;
- agreement was checked only against a re-implementation;
- M1 and M3 were inconsistent;
- the S1 step was not robust when K = 1;
- the refusals were asserts.

**A1.1 replaces A1 for all reporting.** The A1 script (`e65f377c…`) is kept unchanged as history. A1.1 makes the gate stricter and the numbers more faithful. It changes no threshold, arm, trial, setting or run, and it can only make "met" harder.

**A1.1 rules (in addition to A1):**
- **Byte check:** the check against the frozen report's `RUN_FILES_MANIFEST.txt` is required and gating. Any differing, absent or extra file is a blocking issue.
- **N and script identity:** N must be 60, and the frozen postflight script must hash to `43f2d9d3…`.
- **Blocking issues:**
  - a missing file of any arm;
  - a settings or identity mismatch;
  - a V3 run that did not return.
  
  A baseline or V3N run that did not return is a non-blocking note and is reported as unknown.
- **Verdict:** with any blocking issue, the A1.1 verdict is NOT EVALUABLE, which counts as not met.
- **Agreement:** A1.1 is compared with the frozen report's PRINTED verdict. If they disagree, the A1.1 reading governs every claim, and both are reported.
- **Counts:**
  - baseline proximity and no-violation counts are reported over COMPLETE runs, with the unknowns stated (M3);
  - M1 counts only COMPLETE runs without a guard breach;
  - Δv medians use COMPLETE runs only (M2).
- **Robustness:** S1 is robust to K = 1 and reports 1-based steps, and medians are NaN-safe.

**Downstream:** `val_snippets.py` and `make_build_v8.py` take the A1.1 verdict. They refuse a dry-run or non-N = 60 A1.1 file, and they never build r4 unless BOTH the printed frozen verdict and A1.1 say "met" and the A1.1 gate is clean.

A1.1 script `development/analysis/v3_val_report_addendum_a11.py` SHA-256 at freeze: 81c26e5acda2a89f14366244f3774d42fb5d72ca71b3f5f930a29675f6ceb175

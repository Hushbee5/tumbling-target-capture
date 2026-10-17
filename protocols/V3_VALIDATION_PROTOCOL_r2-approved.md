# V3 validation protocol — DRAFT r2, for the user's approval (not frozen, not executed)

**r2 (2026-10-03, 14:00 TR) = r1 + an optional NMPC sub-arm (§1b, §6b, decision D6).** Nothing else changes.

**Disclosure:** when r2 was written, the author had seen one NMPC development run (old trial 1: milestone at 297 s against 477 s with the linear MPC, Δv to the milestone 1.31 against 2.06 m/s, no violation). The NMPC settings (RTI, one SQP iteration, slack weights 1e4 and 1e8) were fixed before that run and are not changed.

- **Written:** 2026-10-03, 11:40–11:50 TR.
- **What the author had seen at writing time:** two V3 development runs on old trials (seed 116075, consumed):
  - M t001 PHQA: NORMAL handoff at 476.5 s, proximity reached, no observed violation;
  - M t011 PHQ: NORMAL handoff at 337.7 s, proximity reached, no observed violation.

  Nothing else from V3 had been seen. The section 2 selection rule and the section 6 thresholds were fixed before the remaining development runs finished.
- **Status:** the new trial table does not exist yet. No seed has been consumed. Nothing may run before the user approves this text. The approved text is then frozen by SHA-256 as revision `r1-approved`, and any later change gets a new revision.

## 0. Question and scope

- **Question:** on fresh trials from the same predeclared engineering envelope, does V3 reach the proximity milestone at a useful rate while keeping the observed body-safety outcome and solving every hard QP? V3 is:
  - **P:** online re-anchored preview;
  - **H:** reachable-boundary handoff;
  - **A:** actuator-authority release gate;
  - **Q:** exact QP with an explicit fallback hierarchy.
- **Comparison:** V3 is compared with nominal MPC and APF that receive the SAME preview information (equal-information baselines).
- **What this does not do:**
  - It does not re-open or replace the frozen 600-run campaign.
  - It is not a capture validation: the point-mass model, the milestone and the handoff are unchanged in meaning.
  - It does not validate the NMPC, the arm, contact or ROS 2 work.
- **Development data:** all 100 rows of seed 116075 are development data and may not enter this validation.

## 1. Arms (all executed on every trial)

| Arm | Code | Description | Information |
|---|---|---|---|
| V3 (primary) | `simulate_task4_v3`, switches P, H, Q, A on, preview RK4 nsub = 2 | proposed architecture V3 | measured q, ω and θ̂ in the preview and in the safety layer |
| MPC-P | `simulate_baseline_v3`, nominal MPC, `v3_preview_online` on | frozen nominal MPC, no barrier | the same online preview (measured q, ω, θ̂) |
| APF-P | `simulate_baseline_v3`, APF with the frozen winner gains (cand. 95), `v3_preview_online` on | frozen APF law | the same online preview |

- **Remaining asymmetry:** only V3 has a safety layer, and that layer reads the measured state. The baselines receive identical preview information.
- **Decision D1:** optionally add an ablation arm V3-noGate (P, H, Q, without A). It isolates the release gate. Cost: one more run per trial.

### 1b. NMPC sub-arm (decision D6; proposed: yes)

- **What it is:** V3N = V3 with the NMPC-RTI upper layer (`simulate_task4_v3n`, `v3_nmpc` on, 1 SQP iteration per sample, settings as in the development source manifest).
- **Where it runs:** only on trials 1–10 of the new table, in its own shard. It costs about 1 h per run, so about 10 h in parallel with the main shards.
- **Status:** descriptive and paired with V3 on the same trials. It does not enter the §6 criteria of V3.

## 2. Variant selection on development data (rule fixed before the development results)

- V3 = **PHQA**, unless the development runs of PHQA on old trials 1–20 show any of the following:
  - an observed body violation;
  - a GUARD_BREACH;
  - a level-2 QP fallback;
  - an invocation failure.
- In that case V3 = **PHQ**, which must pass the same screen on its development runs (trials 11–20, plus V2-PH on 1–10 as context). If neither passes, no validation is run and the development results are reported.
- The milestone rate is NOT a selection criterion. The gate is a design element motivated by what the released row protected against, not by success counts.

## 3. Trials

| Item | Proposal |
|---|---|
| Generator | The frozen draw pattern (15 uniform draws per trial, same mappings and fixed quantities as the frozen protocol §3.3–3.4), via the frozen function `mc_fixture_trial_table(seed, N)`. It refuses seed 116075. |
| Seed | **Decision D2.** Proposal: **20261003**. It is used once, written into the freeze record before any run, and never reused for tuning or pilots. |
| N | **Decision D3.** Proposal: **60** physical trials, constrained by the compute budget of §8. |
| Table | Written with `mc_trial_csv_write`; SHA-256 recorded in `V3_TRIAL_TABLE_FREEZE.md` before the first run; never regenerated. |

## 4. Condition and settings

- **One condition, O (online preview).**
  - For all three arms the open-loop table is not used for control, so the frozen U/M distinction (the preview inertia) does not exist here. The V2 development runs showed U ≡ M bitwise once P is on.
  - Inputs are built with `mc_shared_tables(row, 'M', …)` only for table plumbing and the truth tables.
  - θ̂ starts at 0 (truth-independent) for all arms. The baselines get θ̂(t_k) from the same estimator (`v3_theta_hat_history`; V3 test T8: identical to the in-loop estimate).
- **Run settings:**
  - horizon 800 s, Ts = 0.1 s, α = 1e-3;
  - all gains and thresholds as frozen; γ_c = 1 − β = 0.7 (frozen β);
  - plant: nonlinear two-body relative dynamics, ode45 with RelTol 1e-10 (frozen);
  - exact state and attitude, as in r3.
- **Source identity:** the V3 source files are frozen by a SHA-256 manifest written at protocol freeze. The validation driver refuses to run if any hash differs.

## 5. Endpoints and definitions (frozen definitions: `mc_proposed_adapter` and `baseline_metrics`)

- **Safety, per arm:**
  - no observed body violation over the inspected union (8001 control samples + 72 000 intersample points per full run);
  - minimum clearance (sampled and intersample).
  - V3 only: GUARD_BREACH count; QP level-1 count (capture row softened) and level-2 count (best effort), each per run and in total; maximum KKT primal residual.
- **Progress:** the geometric proximity milestone (frozen definition: first control sample with range ≤ s_cap to the TRUE capture point, no observed violation before it).
- **Safe success:** proximity reached AND no observed violation over the whole run. This is reported next to the frozen proximity flag.
- **Completion and abort:** COMPLETE, GUARD_BREACH_ABORT (V3), INVOCATION_FAILED. V3 does not abort on a QP fallback; the fallback is counted.
- **Secondary endpoints:**
  - time to milestone: median over the runs that reached it, with n;
  - Δv to the milestone and over the full horizon: medians with n;
  - range at 800 s: median over full-horizon runs, with n;
  - V3 handoff statistics (t, ρ, ν, a_req) and minimum clearance after the handoff.
- **Reporting:**
  - counts out of N with Wilson 95 % intervals, per arm;
  - paired 2×2 concordance tables (V3 vs MPC-P, V3 vs APF-P) for proximity and for no-violation;
  - no p-values; no pooling across arms; development results reported separately and labelled.

## 6b. NMPC sub-arm (descriptive)

**Reported per trial:** proximity, no observed violation, time and Δv to the milestone, full-horizon Δv, minimum clearance, and NMPC solve-time statistics, failures and maximum slacks; each next to V3 on the same trial.

**Criterion:** "no observed violation in all V3N runs and zero level-2 fallbacks".

**Not claimed:** no superiority claim from 10 trials, and no real-time claim.

## 6. Criteria, fixed before any validation result

V3 is reported as **"met its predeclared validation criteria on this envelope"** only if all of the following hold.

1. No observed body violation in at least 59 of 60 V3 runs, zero GUARD_BREACH and zero level-2 QP fallbacks.
2. V3 proximity in at least **18 of 60** runs. At 18/60 the Wilson lower bound is 0.199, above 0.198, the Wilson upper bound of the frozen proposed method in its best condition (M, 12/100). The threshold is derived from the frozen campaign only.

**Otherwise:** V3 is reported as not validated, with every endpoint.

**Comparisons with MPC-P and APF-P are descriptive.** No "superior" claim is made. If a baseline reaches the milestone more often or with less Δv, that is reported as such. Development-run numbers never appear as validation numbers.

## 7. Harness and integrity

- **Driver:** `run_v3_val.m`, a new file modelled on the development drivers, with these properties:
  - it reads the new CSV through `mc_trial_csv_read` with its SHA-256;
  - it checks the source manifest before every run;
  - it writes one `.mat` per (trial, arm) and never overwrites;
  - it is resumable: existing outputs are skipped.
- **Shards:** two, detached through WMI (odd and even trials), each running the arms in the fixed order V3, MPC-P, APF-P per trial.
- **Interruptions:**
  - A run interrupted by a process loss is re-run from scratch; this is logged, and the partial file never exists, because the write happens only at the end.
  - Nothing is re-run because of its outcome.
- **Postflight:** `v3_val_report.py` computes every endpoint from the run files only, then writes the result table and a manifest of the run files with their SHA-256.

## 8. Budget

**Measured wall time per 800 s run.** Sources: the development runs, test T9 and the 30 s dry run of the driver with fixture seed 7. All were measured with 3–4 MATLAB processes sharing the 2 cores (i7-7500U).

| Arm | Wall time per 800 s run |
|---|---|
| V3 | about 10–12 min |
| MPC-P | about 5–6 min |
| APF-P | about 13–15 min (the frozen APF path is the slowest) |

**Per trial:** about 30 min of process time; with 2 shards, about 15 min of wall time.

| N | Wall time | Proximity threshold (§6) |
|---|---|---|
| **60 (proposed)** | about 15 h; start about 16:00 on 10-03, end about 07:00 on 10-04 | 18/60 |
| 50 | about 12.5 h | 16/50, the smallest k whose Wilson lower bound exceeds 0.198 |
| 40 | about 10 h | 13/40 |

**Decision D5:** approve a campaign longer than 12 h. The PC must stay on, on mains power and awake. Other heavy MATLAB work is kept off the machine during the campaign; MuJoCo and Python work is light.

**Driver check:** dry run `dry1` (fixture seed 7, trial 1, 30 s horizon, all 3 arms) completed. Outputs are in `results/dryrun_v3val/`. They are not validation results.

## 9. Use of the development data

- **May:** show that the mechanisms act as intended, and select the variant by the §2 rule.
- **May not:** set any threshold, gain or trial selection here (§6 uses the frozen campaign only).
- **Labelling:** development numbers are reported only as EXPLORATORY development evidence.

## 10. Open decisions for the user

| ID | Decision |
|---|---|
| D1 | Ablation arm V3-noGate: yes or no. |
| D2 | Seed: 20261003 or another value. |
| D3 | N = 60, or another value within budget. |
| D4 | §6 thresholds: 59/60 safety and 18/60 proximity, or other values. |
| D5 | Approval of a campaign longer than 12 h, if needed. |
| D6 | NMPC sub-arm on trials 1–10: yes or no. Proposal: yes. |


## Decision record (appended at freeze, 2026-10-03 16:39 TR)

No user reply by the 15:30 TR deadline (checked 16:38 TR); launched about 16:40 TR under the user's full authority given on 2026-10-02 ('tum yetkiyi sana veriyorum'). D1: no ablation arm (budget). D2: seed 20261003. D3: N = 60. D4: criteria as drafted (V3 no observed violation in >= 59/60, 0 GUARD_BREACH, 0 level-2 fallbacks; V3 proximity >= 18/60). D5: campaign longer than 12 h approved; the PC is kept awake by keep_awake.ps1 (PID 15736, transient power request, no setting changed). D6: NMPC sub-arm on trials 1-10: yes. Variant selection (section 2): PHQA SELECTED, see protocols/V3_SELECTION_RULE_RESULT.md (20/20 PHQA development runs passed the safety screen; proximity was not a criterion).

Draft SHA-256: d3baaa811832cf5c313131f64ea57ae68625fc26d248ae73f582d177c258a8c5
Postflight analysis script development/analysis/v3_val_report.py SHA-256 (frozen with the protocol, before any result): 43f2d9d3b0c22bca6f628370c558ebd50f9030e284f438f850270f7918ff07eb

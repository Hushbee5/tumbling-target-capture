# V3 validation results

Source: run files in `results/val_v3` (manifest `RUN_FILES_MANIFEST.txt`, 180 files). Missing runs: none.

## Per-arm endpoints (counts out of the runs present; Wilson 95 %)

| Arm | runs | COMPLETE | no observed violation | proximity | safe success | median t to milestone [s] (n) | median dV full [m/s] (n) | median dV to milestone (n) | median range at 800 s, full-horizon [m] (n) | min clearance [m] |
|---|---|---|---|---|---|---|---|---|---|---|
| V3 | 60 | 60 | 60/60 [94.0, 100.0] | 57/60 [86.3, 98.3] | 57/60 [86.3, 98.3] | 335.6 (57) | 1.43 (60) | 0.4648 (57) | 0.007336 (60) | 0.0001529 |
| MPCP | 60 | 60 | 45/60 [62.8, 84.2] | 45/60 [62.8, 84.2] | 45/60 [62.8, 84.2] | 188.6 (45) | 1.489 (60) | 0.3679 (45) | 0.007336 (60) | -0.4943 |
| APFP | 60 | 60 | 52/60 [75.8, 93.1] | 52/60 [75.8, 93.1] | 52/60 [75.8, 93.1] | 258.6 (52) | 1.566 (60) | 0.4953 (52) | 0.006921 (60) | -0.1217 |

## V3-specific

- GUARD_BREACH: 0; D9 events: {'NORMAL': 57, 'NO_EVENT': 3}
- QP fallbacks: level 1 in 0 runs (total 0 steps), level 2 in 0 runs (total 0 steps)
- handoff: median nu 1.3, median a_req 0.00254 m/s^2, min clearance after handoff 0.007371 m (over 57 NORMAL runs)
- G lemma (body-row individual feasibility): max sampled |rho_dot| over V3 runs 0.0985 m/s; runs where it exceeds the per-run bound: 0 of 60

## Paired 2×2 tables (same trials)

- prox, V3 vs MPCP: both 44 | V3 only 13 | MPCP only 1 | neither 2 | excluded (missing run) 0
- no_viol, V3 vs MPCP: both 45 | V3 only 15 | MPCP only 0 | neither 0 | excluded (missing run) 0
- prox, V3 vs APFP: both 52 | V3 only 5 | APFP only 0 | neither 3 | excluded (missing run) 0
- no_viol, V3 vs APFP: both 52 | V3 only 8 | APFP only 0 | neither 0 | excluded (missing run) 0

## Protocol §6 criteria

1. no observed violation in >= N-1 V3 runs (60/60), zero GUARD_BREACH (0), zero level-2 fallbacks (0): **MET**
2. V3 proximity >= 18 of 60 (Wilson lower bound > 0.198; got 57): **MET**

Overall: V3 **met** its predeclared validation criteria on this envelope.

Comparisons with MPC-P and APF-P are descriptive; no superiority is claimed by the protocol.

## NMPC sub-arm (V3N) vs V3 on the same trials (descriptive, protocol r2 §1b/§6b)

| trial | V3N status | V3N prox / no viol | V3 prox / no viol | t milestone V3N / V3 [s] | dV to milestone V3N / V3 | dV full V3N / V3 | min clearance V3N / V3 [m] | NMPC solve median / p95 [s] | NMPC failures | max slack keep-out / commit |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | COMPLETE | 1 / 1 | 1 / 1 | 312.2 / 432.2 | 0.6797 / 0.9983 | 1.98 / 1.991 | 0.03302 / 0.03852 | 0.244 / 0.691 | 0 | 6.5e-13 / 9.2e-11 |
| 2 | COMPLETE | 1 / 1 | 1 / 1 | 445.3 / 461.7 | 1.149 / 1.231 | 2.099 / 2.12 | 0.04031 / 0.06031 | 0.274 / 1.161 | 0 | 1.5e-12 / 9.0e-11 |
| 3 | COMPLETE | 1 / 1 | 1 / 1 | 442.9 / 443.0 | 0.2985 / 0.2975 | 0.3712 / 0.37 | 0.0007139 / 0.0003521 | 0.243 / 0.693 | 0 | 6.8e-11 / 9.9e-11 |
| 4 | COMPLETE | 1 / 1 | 1 / 1 | 376.9 / 218.0 | 0.2324 / 0.1941 | 0.3449 / 0.3331 | 0.01245 / 0.1044 | 0.185 / 0.852 | 1 | 3.3e-12 / 6.6e-11 |
| 5 | COMPLETE | 1 / 1 | 1 / 1 | 430.9 / 428.6 | 0.3117 / 0.3119 | 0.4788 / 0.4798 | 0.07518 / 0.06719 | 0.190 / 0.773 | 1 | 1.7e-12 / 1.0e-10 |
| 6 | COMPLETE | 1 / 1 | 1 / 1 | 351.7 / 352.8 | 0.8251 / 0.8294 | 2.085 / 2.084 | 0.04001 / 0.02413 | 0.297 / 0.717 | 0 | 6.1e-11 / 9.5e-11 |
| 7 | COMPLETE | 1 / 1 | 1 / 1 | 388.9 / 387.7 | 0.3348 / 0.3345 | 0.5862 / 0.5863 | 0.04978 / 0.04563 | 0.192 / 1.137 | 1 | 6.5e-13 / 9.9e-11 |
| 8 | COMPLETE | 1 / 1 | 1 / 1 | 445.0 / 452.2 | 1.372 / 1.397 | 2.723 / 2.711 | 0.06453 / 0.03401 | 0.178 / 0.519 | 2 | 4.8e-11 / 9.9e-11 |
| 9 | COMPLETE | 1 / 1 | 1 / 1 | 385.5 / 380.9 | 0.8179 / 0.8137 | 1.434 / 1.439 | 0.1039 / 0.1039 | 0.204 / 0.451 | 0 | 1.9e-12 / 9.9e-11 |
| 10 | COMPLETE | 1 / 1 | 1 / 1 | 242.1 / 242.1 | 0.3902 / 0.3902 | 1.307 / 1.307 | 0.1031 / 0.1031 | 0.146 / 0.466 | 0 | 6.5e-13 / 1.2e-11 |

§6b (V3N): no observed violation in all 10 runs (10) and zero level-2 fallbacks (0 runs with level 2): **MET**. Real-time: not claimed (interpreted MATLAB).

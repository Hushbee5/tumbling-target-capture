# Capture stress set r3: filter plus a post-grasp mode (frozen BEFORE any r3 run)

- **Written:** 2026-10-03, 14:10 TR.
- **Basis:**
  - In r1 (200 ms latency, w2_1) and in r2 (noise N1 with the filter, w3_1), the arm struck its own bus AFTER the grasp. In both cases the arm kept tracking the handle and the bus kept synchronizing with the target while the two were already one stack.
  - The r1 and r2 results stay reported unchanged. r3 is a new development iteration, labelled as such.

## Controller v3 = controller v2 (v1 + measurement filter) + post-grasp mode

From the first control sample at which HOLD begins:

| Component | Post-grasp behaviour |
|---|---|
| Arm | Joint position hold at the joint configuration measured at HOLD start. τ = K_p (q_hold − q) − K_d q̇ + bias, with K_p = 50 M_jj and K_d = 2·√(K_p M_jj), i.e. critical damping; M_jj is the joint's diagonal inertia at HOLD start. Torques clipped to the UR5e limits. |
| Bus | Thrusters and wheels OFF: the bus–arm–target stack floats freely. Detumbling is not part of this phase. |
| Gripper | Target unchanged (closed, 60 N limit). |

Before HOLD, nothing changes from v2.

## Runs and outcome rules

- **Runs:** the same 25 runs as r2: the nominal set (10, no noise) and B1, L1, L2, N1, N2 on det_r3, w2_1 and w3_1.
- **Outcome classes and thresholds:** capture protocol r2 §3, unchanged. In particular CAPTURED still requires both fingers in contact in ≥ 95 % of the hold samples, an end distance ≤ 2 cm and a relative velocity ≤ 1 cm/s.
- **No further changes after these runs.**

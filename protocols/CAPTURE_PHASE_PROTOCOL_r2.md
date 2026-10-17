# Capture-phase prototype: success definition and scenarios (r2, frozen BEFORE any capture run)

**Revision r2 (2026-10-03 12:25 TR).** Made after the first set-up attempt failed in inverse kinematics, before any capture simulation produced an outcome.

- **What changed:** the hold point moved from 2.0 û to 2.0 û + 0.30 e_z. With the r1 hold point the arm's wrist centre lies on the joint-1 axis, the UR shoulder singularity.
- **What did not change:** every threshold, outcome rule and scenario is unchanged. r1 is kept unmodified.

- **Written:** 2026-10-03, 12:10 TR, before `sim_capture.py` existed and before any capture simulation.
- **Status:** DEVELOPMENT. The model is GENERIC (`model_params.json`), the scenarios are development scenarios, and the outcome is at most IMPLEMENTED-UNVALIDATED (gaps D and E).

## 1. Phase decomposition (what is and is not simulated here)

**Phase 1: approach (MATLAB, point mass, V3).** The bus approaches. The point-mass geometry of r3 (r_safe = 0.70 m around a 0.12 m capture interface) is NOT the bus geometry. Connecting the two is an interface assumption, stated in §5.

**Phase 2: synchronized standoff and grasp (this prototype, MuJoCo).**
- **Start state:** the bus is at a body-fixed hold point of the target, r_hold = 2.0 û + 0.30 e_z, where û = p_b/|p_b| and e_z is the handle axis. This is r2: the lateral offset keeps the wrist centre off the joint-1 axis. Bus centre 2.02 m from the target centre; bus keep-out 0.5 + 0.866 = 1.37 m.
- **Synchronization:** the bus is already synchronized (velocity of the rotating hold point, attitude rate ω_T).
- **Arm:** pre-positioned by inverse kinematics at a pre-grasp pose 0.15 m outside the handle along û.

**Phase 3: hold.** The fingers close and the grasp is held for T_hold = 10 s. Post-capture detumbling is NOT simulated. Post-capture identification is a separate experiment (gap C).

## 2. Controllers (fixed before the runs)

**Bus**
- Translation: PD plus centripetal feed-forward on the rotating hold point, thrust saturated at 3 N per axis (0.01 m/s²).
- Attitude: PD plus gyroscopic term, saturated at 0.2 N m per axis.
- Inputs: the measured target attitude and rate. Measurement is exact, as in r3.

**Arm.** Task-space resolved-rate control with bus-motion compensation:
- q̇_cmd = J_mᵀ(J_m J_mᵀ + λ² I)⁻¹ (ξ_cmd − J_b ξ_b);
- ξ_cmd = [v_des + K_p e_p ; ω_des + K_o e_o];
- joint torque τ = K_v (q̇_cmd − q̇) + bias, clipped to the UR5e torque limits;
- q̇_cmd clipped to 0.5 rad/s.

**Sequence**

| Step | Action | Condition to advance |
|---|---|---|
| SYNC | Track the pre-grasp pose. | Advance to APPROACH after 1 s continuously with e_p < 1 cm, e_o < 5° and relative TCP–pre-grasp velocity < 1 cm/s. |
| APPROACH | Standoff s from 0.15 m to 0 at 0.01 m/s. | Advance to CLOSE when s = 0, e_p < 5 mm, e_o < 5° and relative velocity < 1 cm/s. |
| CLOSE | Finger target closed; force limit 60 N per finger. | Advance to HOLD when both fingers touch the handle. |
| HOLD | Hold the grasp. | 10 s. |

**Timeout:** T_max = 150 s.

## 3. Outcome classes and thresholds (the run is classified ONLY by these)

**Forbidden contact:** any contact of the target body or stalk with any servicer geom; any contact of the handle with a bus or arm-link geom; any self-contact between non-adjacent arm links; any arm–bus contact other than the excluded base pair.

**Allowed contact:** fingers or palm with the handle.

| Outcome | Rule |
|---|---|
| UNSAFE_CONTACT | Any forbidden contact at any time. Overrides every other class. |
| LOAD_EXCEEDED | Peak finger–handle normal force > 200 N, OR peak wrist force > 150 N, OR peak wrist torque > 28 N m (UR5e wrist joint limit). |
| CAPTURED | All of the following: (a) HOLD reached; (b) both fingers in contact with the handle in ≥ 95 % of the HOLD samples; (c) at the end of HOLD, TCP–handle distance ≤ 2 cm and relative velocity ≤ 1 cm/s; (d) no UNSAFE_CONTACT; (e) no LOAD_EXCEEDED. |
| GRASP_FAILED | HOLD reached but (b) or (c) fails. |
| NOT_REACHED | CLOSE or HOLD not reached by T_max. |
| SYNC_SATURATED | Informational flag, not an outcome: bus thrust saturated in > 50 % of the samples. |

**Threshold justification (engineering choices, not literature limits).**
- **Lateral tolerance:** the finger opening is 2 × 4 cm against a 2 cm handle radius, so the lateral capture range is about ±2 cm. A 5 mm close condition and a 2 cm hold tolerance leave margin.
- **Relative velocity:** 1 cm/s keeps the closing impact small for the 1 kg gripper.
- **Loads:** 200 N is about 3.3 times the 60 N grip force (impact allowance). 150 N and 28 N m are the UR5e wrist payload and torque scale.

## 4. Development scenario set (fixed now)

**Target set**
- the r3 deterministic rate ω0 = [2, −3, 1.5] deg/s (|ω| = 3.9 deg/s), attitude q0 = identity;
- 9 rates with |ω0| ∈ {1, 2, 3} deg/s, three directions each, drawn from `np.random.default_rng(2026)` (a TEST generator, not a campaign seed); attitude identity.

**Inertia and simulation**
- target inertia diag(20, 25, 30) kg m², mass 100 kg;
- MuJoCo RK4 at 1 ms; control at 100 Hz;
- Clohessy–Wiltshire translational terms applied to every body (n = 1.1314e-3 rad/s).

**Reporting**
- every run: outcome class, timeline, peak loads, minimum clearances (TCP–target sphere, arm–target), and bus saturation fractions;
- no aggregation beyond counts per |ω0|.

## 5. Stated limitations (part of the result)

- The arm is a terrestrial UR5e chain (kinematics and masses from the published DH table; approximated inertias) on a generic bus. It is not a space manipulator and not flight hardware.
- Contact uses MuJoCo's soft-contact model with the default contact parameters of the scene (solref 0.004 s, solimp 0.95/0.99) and friction 0.8. No gripper hardware or latch is modelled.
- Exact measurement; no sensor noise. No flexible modes, plume impingement, actuator dynamics or communication delay.
- The interface to phase 1 is assumed: the bus is placed at a synchronized standoff. Whether the V3 point-mass approach brings a real bus there is not shown.
- Synchronization with a fast tumbler needs centripetal acceleration ω²·|r_hold|. At 3.9 deg/s and 2.02 m this is 0.0094 m/s², close to the 0.01 m/s² thrust bound. Saturation is expected for the fastest scenario and is reported.

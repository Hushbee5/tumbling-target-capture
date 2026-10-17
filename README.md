# Safe terminal approach to a tumbling, non-cooperative target

Code and results for my IAC 2026 paper:

> H. B. Gürbüz, *Robust Autonomous Capture of Non-Cooperative Tumbling Targets: An Adaptive Control Barrier
> Function-Based Model Predictive Control Approach with Formal Safety Guarantees*, 77th International
> Astronautical Congress (IAC 2026), Antalya, Türkiye, paper IAC-26-A6.IP.162.

![Approach to the tumbling target](media/approach.gif)

## The problem

A servicer has to reach a handle on a tumbling satellite. The handle moves with the target, it sits only about
10 cm outside a 0.70 m keep-out sphere, and the target's inertia is not known exactly.

![Capture geometry](figures/capture_geometry.png)

## The controller

- **Upper layer:** a preview-based linear MPC on Clohessy–Wiltshire dynamics, re-solved every 0.1 s over a 10 s
  horizon.
- **Lower layer:** a high-order control barrier function (HOCBF) quadratic program. It keeps the servicer out of the
  keep-out sphere and holds a commitment distance to the handle until a handoff.
- **Estimator:** an online estimator of the target's scale-free inertia ratios feeds the commitment constraint.

![Architecture](figures/architecture.png)

## Formulation

**Relative motion.** Clohessy–Wiltshire equations in the target-centred LVLH frame, with mean motion $n$ and
commanded acceleration $u$:

$$
\ddot r_x = 3n^2 r_x + 2n\dot r_y + u_x,\qquad
\ddot r_y = -2n\dot r_x + u_y,\qquad
\ddot r_z = -n^2 r_z + u_z,\qquad |u_i| \le u_{\max}.
$$

**Tumbling target.** Torque-free rigid-body rotation:

$$
I\dot\omega + \omega\times(I\omega) = 0,\qquad \dot q = \tfrac12\,\Omega(\omega)\,q .
$$

The capture point $p_b$ is fixed in the body frame, so in LVLH it moves as $p_{cp,L} = R(q_L)\,p_b$.

**Upper layer: preview MPC.** Re-solved every $T_s = 0.1$ s over $N = 100$ steps, tracking the predicted
capture-point path:

$$
\min_{u}\;\sum_{j}\,(x[j]-x_{\mathrm{ref}}[j])^{\top}Q\,(x[j]-x_{\mathrm{ref}}[j]) + u[j]^{\top}R\,u[j]
\quad\text{s.t. discretised dynamics},\ |u_i|\le u_{\max}.
$$

**Lower layer: high-order CBF safety filter.** The keep-out barrier has relative degree two:

$$
h(x) = \lVert r\rVert^2 - r_{\mathrm{safe}}^2,\qquad
\psi_1 = \dot h + k_1 h,\qquad
\psi_2 = \dot\psi_1 + k_2\psi_1 \ge 0 .
$$

The applied command is the minimum-intervention correction of the MPC command:

$$
u_{\mathrm{safe}} = \arg\min_{u}\ \lVert u - u_{\mathrm{MPC}}\rVert^2
\quad\text{s.t.}\quad \psi_2(x,u)\ge 0,\ \ \text{capture row},\ \ |u_i|\le u_{\max}.
$$

**Adaptive capture-commitment row.** With the offset $d = r - p_{cp,L}$, the commitment barrier is

$$
h_{\mathrm{cap}} = d^{\top}d - s_{\mathrm{cap}}^2 .
$$

It is enforced robustly against the error of the estimated inertia ratios $\hat\theta$:

$$
\psi_{2,\mathrm{cap}}(x,\hat\theta) - \nu(t)\,\lVert L_Y\psi_{1,\mathrm{cap}}\rVert \ge 0,
\qquad
\nu(t) = \sqrt3\,\exp\!\Big(-\gamma\!\int_0^t\lambda_{\min}(\tau)\,d\tau\Big).
$$

**Handoff (V3).** The commitment row is released on the reachable boundary, with a braking reserve
$\beta = 0.3$:

$$
h_{\mathrm{cap}} \le h^{*} + \varepsilon_h,\quad \dot\rho \le 0,\qquad
h^{*} = \frac{\eta\,\nu}{\kappa_1\kappa_2},\qquad
a_{\mathrm{req}} \le (1-\beta)\,u_{\max}.
$$

Here $\rho = \lVert d\rVert$ is the distance to the capture point.

**Geometry.** $r_{\mathrm{safe}} = 0.70$ m, $\lVert p_b\rVert = 0.806$ m, $s_{\mathrm{cap}} = 0.106$ m.

## Results (simulation)

**600-run predeclared Monte Carlo stress test.**
- 100 random trials × 2 preview conditions × 3 controllers (proposed, nominal MPC, artificial potential field).
- The protocol was frozen before the trial table was drawn.

**Validation of the improved version (V3).**
- 60 new trials, protocol frozen in advance, all controllers given the same online preview.
- V3 had no observed keep-out violation in 60 of 60 runs and reached the capture zone in 57 of 60.
- The nominal MPC entered the keep-out sphere in 15 runs and the APF in 8.

![Validation on 60 trials](media/validation_60.gif)

**Beyond the paper (development prototypes):**
- a 6-DOF arm on a free-floating bus grasping the handle in MuJoCo;
- a two-process ROS 2 lockstep co-simulation;
- a real-time-iteration nonlinear MPC.

![Grasp prototype](media/grasp_prototype.gif)

## Repository layout

| Folder | Contents |
|---|---|
| `matlab/core` | dynamics, MPC, HOCBF filter, estimator, baselines, Monte Carlo campaign and verification code |
| `matlab/v3` | the improved architecture used in the 60-trial validation |
| `python/mujoco_capture` | MuJoCo model of the bus, arm and target; capture controller; stress tests |
| `python/ros2_capture` | ROS 2 plant and controller nodes |
| `python/rendering` | renders, animations and the figures above |
| `python/analysis` | validation report and analysis scripts |
| `protocols` | predeclared test protocols and the validation trial table |
| `results` | summary results (CSV, JSON, reports); raw run records are not included because of their size |
| `figures`, `media` | figures and animations |

**Tools used:** MATLAB (R2025b), Python 3.10 with MuJoCo 3.x and NumPy/SciPy, ROS 2 Humble.

## Notes

- All results are from simulation.
- Raw `.mat` run records (several hundred MB) are available on request.
- The Earth texture in the renders is NASA Visible Earth imagery (Blue Marble). It is not included here; download
  `land_shallow_topo_8192.tif` from NASA Visible Earth and convert it to PNG to re-render.
- The paper itself is not included (IAF copyright).

© 2026 Hasan Baran Gürbüz. All rights reserved.

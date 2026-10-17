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

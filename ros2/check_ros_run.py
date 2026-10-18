"""Compares a ROS 2 run of gnc_ros (plant_node + controller_node) with the in-process closed loop gnc.simulate.
Usage: python3 ros2/check_ros_run.py <run.json> <duration_s> <use_filter: true|false>   (python/ on PYTHONPATH)"""
import json
import sys

import numpy as np

import gnc

run = json.load(open(sys.argv[1]))
T = float(sys.argv[2])
use_filter = sys.argv[3].lower() == "true"
p = gnc.default_params()
ref = gnc.simulate(p, np.array([0.0, -10.0, 0.0, 0.0, 0.0, 0.0]), [0.0, 3.0, 0.0], T, use_filter=use_filter)
X, U = np.array(run["X"]), np.array(run["U"])
assert X.shape == ref["X"].shape, (X.shape, ref["X"].shape)
dx = np.abs(X - ref["X"]).max()
du = np.abs(U - ref["U"]).max()
rmin = np.linalg.norm(X[:, :3], axis=1).min()
ok = dx <= 1e-9 and du <= 1e-9 and (rmin > p["r_safe"]) == use_filter
print("ROS 2 lockstep vs in-process loop, %.0f s, filter %s: max |dX| %.1e m, max |du| %.1e m/s^2, "
      "minimum range %.3f m (r_safe %.2f m), %d stale commands -> %s"
      % (T, use_filter, dx, du, rmin, p["r_safe"], run["stale_commands"], "PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)

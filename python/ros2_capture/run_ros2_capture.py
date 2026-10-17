"""Headless launcher and check for the ROS 2 co-simulation (gap F). Run with the RoboStack environment's Python:
   micromamba run -p D:/iacr2 python run_ros2_capture.py <scenario> <out_dir> <reference_dir>
Starts the controller and plant nodes as separate processes (ROS_LOCALHOST_ONLY=1, a private ROS_DOMAIN_ID), waits,
then compares the plant-side histories with the in-process reference run of capture_core (same scenario):
  F1  every history field equal within 1e-9 (relative to the field's scale) and the same outcome
  F2  zero stamp mismatches and zero frame errors; thrust <= 3 N, wheel torque <= 0.2 N m, |qd_cmd| <= 0.5 rad/s
Prints PASS/FAIL lines; writes <out_dir>/<scenario>_ros2_check.json (never overwritten)."""
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
scn, out_dir, ref_dir = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out_dir, exist_ok=True)
env = dict(os.environ, ROS_LOCALHOST_ONLY="1", ROS_DOMAIN_ID="73", PYTHONUNBUFFERED="1")
py = sys.executable
ctl = subprocess.Popen([py, os.path.join(HERE, "ros2_capture_nodes.py"), "controller", out_dir], env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
plant = subprocess.Popen([py, os.path.join(HERE, "ros2_capture_nodes.py"), "plant", scn, out_dir], env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
po, _ = plant.communicate(timeout=3600)
co, _ = ctl.communicate(timeout=600)
print(po.strip()[-600:]); print(co.strip()[-400:])
S = json.load(open(os.path.join(out_dir, scn + "_ros2.json")))
Hr = np.load(os.path.join(out_dir, scn + "_ros2.npz"))
Ri = np.load(os.path.join(ref_dir, scn + ".npz"))
Si = json.load(open(os.path.join(ref_dir, scn + ".json")))
worst, bad = {}, []
for k in Ri.files:
    a, b = Hr[k], Ri[k]
    if a.shape != b.shape:
        bad.append(k); continue
    if a.dtype.kind in "fc":
        sc = max(1e-12, float(np.max(np.abs(b))))
        worst[k] = float(np.max(np.abs(a - b)) / sc)
        if worst[k] > 1e-9:
            bad.append(k)
    elif not np.array_equal(a, b):
        bad.append(k)
f1 = not bad and S["outcome"] == Si["outcome"] and S["timeline_s"] == Si["timeline_s"]
c = S["ros2_checks"]
f2 = c["stamp_mismatch"] == 0 and c["frame_errors"] == 0 and c["max_thrust_N"] <= 3.0 + 1e-12 \
     and c["max_wheel_Nm"] <= 0.2 + 1e-12 and c["max_qd_cmd"] <= 0.5 + 1e-12
res = {"scenario": scn, "F1_pass": f1, "F1_differing": bad, "F1_worst_rel": worst, "outcome_ros2": S["outcome"],
       "outcome_inprocess": Si["outcome"], "F2_pass": f2, "checks": c, "plant_tail": po.strip()[-300:],
       "controller_tail": co.strip()[-300:]}
with open(os.path.join(out_dir, scn + "_ros2_check.json"), "x", encoding="utf-8") as fh:
    json.dump(res, fh, indent=1)
print("F1 ROS 2 lockstep vs in-process, %s: differing fields %s, worst relative difference %.2e, outcome %s/%s -> %s"
      % (scn, bad or "none", max(worst.values()) if worst else float("nan"), S["outcome"], Si["outcome"],
         "PASS" if f1 else "FAIL"))
print("F2 stamps/frames/units: %s -> %s" % (c, "PASS" if f2 else "FAIL"))

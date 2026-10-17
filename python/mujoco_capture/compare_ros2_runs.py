"""F3: determinism of the ROS 2 co-simulation: two independent ROS 2 runs of the same scenario give bit-identical
plant-side histories and summaries. Also reports the absolute size of the F1 differences (ROS 2 vs in-process).
Usage: python compare_ros2_runs.py <run1_dir> <run2_dir> <inprocess_dir> <scenario>"""
import json
import os
import sys

import numpy as np

r1, r2, ri, sid = sys.argv[1:5]
A = np.load(os.path.join(r1, sid + "_ros2.npz")); B = np.load(os.path.join(r2, sid + "_ros2.npz"))
I = np.load(os.path.join(ri, sid + ".npz"))
diff = [k for k in A.files if not np.array_equal(A[k], B[k])]
SA = json.load(open(os.path.join(r1, sid + "_ros2.json"))); SB = json.load(open(os.path.join(r2, sid + "_ros2.json")))
same_summary = all(SA[k] == SB[k] for k in SA if k not in ("wall_s",))
print("F3 ROS 2 run 1 vs run 2 (%s): history fields differing: %s; summaries equal (wall time excluded): %s -> %s"
      % (sid, diff or "none", same_summary, "PASS" if not diff and same_summary else "FAIL"))
for k in ("e_o", "e_p", "v_rel", "bus_e", "wrist_f", "wrist_t", "f_pad"):
    a, b = A[k].astype(float), I[k].astype(float)
    print("   F1 detail %-8s max |ROS2 - in-process| = %.3e (field max %.3e)" % (k, np.max(np.abs(a - b)), np.max(np.abs(b))))

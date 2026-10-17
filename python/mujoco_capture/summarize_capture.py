"""Print one line per capture-run summary JSON in a results folder (read only)."""
import glob
import json
import os
import sys

d = sys.argv[1]
rows = []
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    S = json.load(open(f))
    rows.append(S)
    print("%-8s |w0| %.2f deg/s  %-15s timeline %s  hold %.2f  end d %.4f m  v %.4f m/s  pad %.0f N  wrist %.1f N / %.2f N m"
          "  bus_sat %.2f  arm_sat %.2f  min TCP clr %.3f m  forbidden %d  wall %.0f s"
          % (S["id"], S["w0_norm_deg"], S["outcome"], {k: round(v, 1) for k, v in S["timeline_s"].items()},
             S["hold_both_contact_fraction"], S["end_tcp_handle_dist_m"], S["end_rel_vel_mps"], S["peak_pad_force_N"],
             S["peak_wrist_force_N"], S["peak_wrist_torque_Nm"], S["bus_saturation_fraction"],
             S["arm_torque_saturation_fraction"], S["min_tcp_clearance_to_target_sphere_m"], S["n_forbidden_samples"],
             S["wall_s"]))
from collections import Counter
print("outcomes:", dict(Counter(S["outcome"] for S in rows)), "| runs:", len(rows))

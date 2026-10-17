"""R1: capture_core in-process (plant/controller split) reproduces sim_capture.py's histories bit for bit.
Usage: python test_core_identity.py <reference dir with sim_capture results> <scenario id>"""
import os
import sys

import numpy as np

import capture_core as CC
import sim_capture as SC

ref_dir, sid = sys.argv[1], sys.argv[2]
scn = [s for s in SC.scenarios() if s["id"] == sid][0]
S, H = CC.run_inprocess(scn)
R = np.load(os.path.join(ref_dir, sid + ".npz"))
bad = []
for k in H:
    a = np.array(H[k]); b = R[k]
    if a.shape != b.shape or not np.array_equal(a, b):
        bad.append(k)
print("R1 core split vs sim_capture.py, scenario %s: %d history fields, differing: %s; outcome %s -> %s"
      % (sid, len(H), bad or "none", S["outcome"], "PASS" if not bad else "FAIL"))
sys.exit(0 if not bad else 1)

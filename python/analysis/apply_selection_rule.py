"""Apply the variant-selection rule of protocol r2 §2 to the development runs (old trials 1-20, development data).
PHQA is selected unless any PHQA run on trials 1-20 has an observed body violation, a GUARD_BREACH, a level-2 QP fallback
or an invocation failure; the milestone rate is NOT a criterion. Writes protocols/V3_SELECTION_RULE_RESULT.md (never
overwrites)."""
import os
import sys

import numpy as np
import scipy.io as sio

D = r"results\dev_v3"
OUT = r"protocols\V3_SELECTION_RULE_RESULT.md"
assert not os.path.exists(OUT), "exists"
L = ["# Variant selection (protocol r2 §2) applied to the PHQA development runs, old trials 1-20", "",
     "| trial | status | event | no observed violation | level-2 fallback steps | guard | proximity (info only) |",
     "|---|---|---|---|---|---|---|"]
bad = []
for t in range(1, 21):
    f = os.path.join(D, "M_t%03d_V3PHQA.mat" % t)
    if not os.path.exists(f):
        bad.append((t, "missing")); L.append("| %d | MISSING | | | | | |" % t); continue
    S = sio.loadmat(f, squeeze_me=True, struct_as_record=False)["S"]
    st = str(getattr(S, "status", "")); ev = str(getattr(S, "event", "")); g = str(getattr(S, "guard", ""))
    nv = bool(getattr(S, "no_viol", False)); l2 = float(getattr(S, "qp_level2", np.nan)); px = bool(getattr(S, "prox", False))
    L.append("| %d | %s | %s | %d | %g | %s | %d |" % (t, st, ev, nv, l2, g, px))
    if not nv: bad.append((t, "observed violation"))
    if ev == "GUARD_BREACH": bad.append((t, "GUARD_BREACH"))
    if not (l2 == 0): bad.append((t, "level-2 fallback"))
    if g != "RETURNED" or st not in ("COMPLETE",): bad.append((t, "invocation/status %s/%s" % (g, st)))
verdict = "PHQA SELECTED" if not bad else "PHQA NOT SELECTED: %s" % bad
L += ["", "Screen failures: %s" % (bad or "none"), "", "**%s**" % verdict, ""]
open(OUT, "x", encoding="utf-8", newline="\n").write("\n".join(L))
print("\n".join(L))

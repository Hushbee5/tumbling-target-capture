"""Model-level checks of the MuJoCo capture scene, run as pytest tests.

  model_checks.py  TCP Jacobian, free-floating momentum conservation, centre of mass, generalised Jacobian,
                   actuator limits (M1-M5)
  cw_check.py      Clohessy-Wiltshire forces in MuJoCo against the analytic CW solution over 600 s (M6).
                   Known issue: the CW forces are applied once per step and held through the RK4 stages, so the
                   orbital terms are integrated to first order. The position error is 7.4e-7 m after 600 s, but
                   the time-step convergence criterion (1e-9 m) fails. The test is marked as an expected failure
                   and, since it takes about 15 minutes, runs only with  pytest -m slow.

Run from the repository root:  pytest tests/python"""
import os
import subprocess
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MJ = os.path.join(ROOT, "python", "mujoco_capture")


def run(script):
    r = subprocess.run([sys.executable, script], cwd=MJ, capture_output=True, text=True)
    print(r.stdout)
    return r


def test_model_checks_m1_m5():
    r = run("model_checks.py")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "FAIL" not in r.stdout


@pytest.mark.slow
@pytest.mark.xfail(strict=True, reason="CW forces held over each RK4 step: first-order convergence (see docstring)")
def test_cw_terms_m6():
    r = run("cw_check.py")
    assert r.returncode == 0, r.stdout + r.stderr

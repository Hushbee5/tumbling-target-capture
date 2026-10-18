"""Parity of the Python port (python/gnc) with the MATLAB reference implementation.

The reference values in tests/data/gnc_reference.json were recorded from the MATLAB code with
tests/parity/make_gnc_reference.m (see that file for the cases)."""
import json
import os
import sys

import numpy as np
import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python"))
import gnc  # noqa: E402

REF = json.load(open(os.path.join(ROOT, "tests", "data", "gnc_reference.json")))
P = gnc.default_params()


@pytest.fixture(scope="module")
def mpc():
    return gnc.CondensedMPC(P)


def test_params_match_matlab():
    for k, v in REF["params"].items():
        assert P[k] == pytest.approx(v, rel=1e-14, abs=0), k


def test_cw_discretisation():
    _, _, Ad, Bd = gnc.cw_matrices(P["n"], P["Ts"])
    np.testing.assert_allclose(Ad, REF["cw"]["Ad"], rtol=1e-12, atol=1e-15)
    np.testing.assert_allclose(Bd, REF["cw"]["Bd"], rtol=1e-12, atol=1e-15)


def test_mpc_matrices(mpc):
    np.testing.assert_allclose(mpc.P, REF["mpc"]["P"], rtol=1e-8, atol=1e-10 * np.abs(mpc.P).max())
    np.testing.assert_allclose(np.diag(mpc.H), REF["mpc"]["H_diag"], rtol=1e-9)
    np.testing.assert_allclose(mpc.H[0], REF["mpc"]["H_row1"], rtol=1e-9, atol=1e-9 * np.abs(mpc.H).max())
    assert np.linalg.norm(mpc.H) == pytest.approx(REF["mpc"]["H_fro"], rel=1e-9)


def test_hocbf_filter_cases():
    n_active = 0
    for c in REF["filter_cases"]:
        u, info = gnc.cbf_qp_filter(np.array(c["x"]), np.array(c["u_nom"]), P)
        assert info["status"] == c["status"]
        np.testing.assert_allclose(u, c["u_safe"], rtol=0, atol=1e-13)
        assert info["lam"] == pytest.approx(c["lambda"], rel=1e-9, abs=1e-12)
        if c["psi2"] != "NaN":
            assert info["psi2"] == pytest.approx(c["psi2"], rel=1e-9, abs=1e-15)
            assert info["psi2"] >= -1e-15                      # the HOCBF condition holds at the returned command
        n_active += c["status"] == 1
    assert n_active > 20                                         # the safety row is actually exercised


def test_mpc_step_cases(mpc):
    for c in REF["mpc_cases"]:
        Pref = np.tile(np.reshape(c["r_ref"], (3, 1)), (1, mpc.N + 1))
        u, info = mpc.step(np.array(c["x"]), Pref, np.zeros_like(Pref))
        np.testing.assert_allclose(info["U"], c["U"], rtol=0, atol=1e-10)


@pytest.mark.parametrize("i", [0, 1], ids=["with_filter", "without_filter"])
def test_closed_loop(i):
    L = REF["loops"][i]
    out = gnc.simulate(P, np.array(L["x0"]), L["r_ref"], L["T"], use_filter=L["use_filter"])
    X, Xm = out["X"], np.array(L["X"])
    np.testing.assert_allclose(X, Xm, rtol=0, atol=1e-9)
    np.testing.assert_allclose(out["U"], L["U"], rtol=0, atol=1e-10)
    rmin = np.linalg.norm(X[:, :3], axis=1).min()
    if L["use_filter"]:
        assert rmin > P["r_safe"]                               # never inside the keep-out sphere
    else:
        assert rmin < P["r_safe"]                               # the unfiltered MPC cuts through it


def test_filter_bracket_with_vanishing_component():
    """A position component of 1e-74 (left by an integrator in an unused axis) must not change the filtered command."""
    x = np.array([-1.25626564e-05, -9.99996020e+00, -2.25e-74, -2.51223105e-04, 7.96108426e-04, 1.1e-70])
    u_nom = np.array([-2.44893230e-03, 1.0e-02, -2.7e-71])
    u_tiny, _ = gnc.cbf_qp_filter(x, u_nom, P)
    x0, u0 = x.copy(), u_nom.copy()
    x0[[2, 5]] = 0.0
    u0[2] = 0.0
    u_zero, _ = gnc.cbf_qp_filter(x0, u0, P)
    np.testing.assert_allclose(u_tiny, u_zero, rtol=0, atol=1e-15)


def test_mujoco_plant_matches_cw_loop():
    """The controller flying a MuJoCo free body (CW terms at every RK4 stage) reproduces the exact-ZOH CW loop."""
    from gnc.mujoco_loop import run
    x0 = np.array([0.0, -10.0, 0.0, 0.0, 0.0, 0.0])
    a = run(P, x0, [0.0, 3.0, 0.0], 30.0)
    b = gnc.simulate(P, x0, [0.0, 3.0, 0.0], 30.0)
    np.testing.assert_allclose(a["X"], b["X"], rtol=0, atol=1e-10)
    assert a["r_min_fine"] > P["r_safe"]


def test_inertia_ratio_estimator():
    """Concurrent-learning estimator over the 800 s target rate history recorded from MATLAB (simulate_task4 grid)."""
    from gnc.estimator import CLEstimator, cl_records
    E = json.load(open(os.path.join(ROOT, "tests", "data", "estimator_reference.json")))
    t, w = np.array(E["t"]), np.array(E["w"])
    rec = cl_records(t, w, E["Tw"], E["Ts"])
    assert len(rec["Te"]) == E["n_records"]
    resid = np.linalg.norm(rec["D"] - rec["Y"] * np.array(E["theta_true"]), axis=1).max()
    assert resid == pytest.approx(E["rec_resid"], rel=1e-6)
    est = CLEstimator(rec, E["Ts"], gamma=E["gamma"], M=E["M"], nu0=E["nu0"])
    keep = set(E["k"])
    th, nu, lm, ns = [], [], [], []
    for k in range(len(t) - 1):
        v = est.step(t[k])
        if k in keep:
            th.append(v["theta_hat"]); nu.append(v["nu"]); lm.append(v["lambda_min"]); ns.append(v["n_stack"])
    np.testing.assert_allclose(th, E["theta_hat"], rtol=0, atol=1e-12)
    np.testing.assert_allclose(nu, E["nu"], rtol=1e-10)
    np.testing.assert_allclose(lm, E["lambda_min"], rtol=1e-10, atol=1e-15)
    np.testing.assert_array_equal(ns, E["n_stack"])
    assert nu[-1] == pytest.approx(1.23e-3, rel=5e-3)                  # the value reported for the 800 s run

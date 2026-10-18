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

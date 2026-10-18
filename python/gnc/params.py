"""Parameters of the approach controller, mirroring matlab/core/config/params.m (the subset the controller uses).

Units: metres, seconds, m/s^2. The parity tests compare these values with the MATLAB configuration."""
import math

MU_KM = 398600.4418           # Earth gravitational parameter [km^3/s^2]
RE_KM = 6378.137              # Earth mean radius [km]
ALT_KM = 400.0                # circular orbit altitude [km]


def default_params():
    a_km = RE_KM + ALT_KM
    p = {
        "n": math.sqrt(MU_KM / a_km ** 3),          # mean motion [rad/s]
        "a_m": a_km * 1e3,                            # orbit radius [m]
        "mu_m": MU_KM * 1e9,                          # gravitational parameter [m^3/s^2]
        "r_safe": 0.50 + 0.12 + 0.08,                 # keep-out radius: target + chaser extent + margin [m]
        "u_max": 0.01,                                # per-axis acceleration limit [m/s^2]
        "Ts": 0.1,                                    # controller sample time [s]
        "k1": 0.04, "k2": 0.04,                       # HOCBF class-K gains [1/s]
        "delta": 0.0,                                 # sampled-data tightening of the HOCBF row
        "act_thresh": 1e-6,                           # "filter active" threshold [m/s^2]
        "N": 100,                                     # MPC horizon [steps]
        "sigma_p": 1.0, "sigma_v": 0.05,              # MPC error scales [m], [m/s]
        "rho": 1.0,                                   # MPC control-effort weight
        "use_dlqr_terminal": True,                    # terminal weight from the discrete LQR
    }
    return p

function p = params()
% PARAMS  Central configuration for the IAC 2026 capture simulation.
%   p = params() returns a struct holding every constant used across the
%   project (orbit, target, geometry, chaser, control, scenario, sim). Keep ALL
%   magic numbers here so scenarios are reproducible and easy to sweep in Monte
%   Carlo.
%
%   Conventions (notes/conventions.md):
%     - quaternions are Hamilton, SCALAR-FIRST, unit norm: q = [q0;q1;q2;q3]
%     - angular velocity w is expressed in the target BODY frame
%     - LVLH: +x radial outward, +y along-track, +z = x cross y
%     - kilometres appear ONLY in the p.orbit block; everything downstream of
%       src/dynamics works in metres, m/s, m/s^2, rad, rad/s

% ----- Orbit (target reference orbit) -----
p.orbit.mu = 398600.4418;            % Earth gravitational parameter [km^3/s^2]
p.orbit.alt = 400;                   % circular orbit altitude [km]
p.orbit.Re  = 6378.137;              % Earth mean radius [km]
p.orbit.a   = p.orbit.Re + p.orbit.alt;          % semi-major axis [km]
p.orbit.n   = sqrt(p.orbit.mu / p.orbit.a^3);    % mean motion [rad/s]
p.orbit.T   = 2*pi / p.orbit.n;                  % orbital period [s]

% SI mirrors, used by the nonlinear relative dynamics (metres)
p.orbit.a_m  = p.orbit.a  * 1e3;     % semi-major axis [m]
p.orbit.mu_m = p.orbit.mu * 1e9;     % gravitational parameter [m^3/s^2]

% ----- Target rigid body -----
p.target.m  = 100;                   % target mass [kg]
p.target.I  = diag([20, 25, 30]);    % inertia tensor (body frame) [kg m^2]
                                     % asymmetric -> richer tumbling

% Initial attitude (scalar-first quaternion) and body angular velocity
p.target.q0 = [1; 0; 0; 0];                       % aligned with LVLH at t=0
p.target.w0 = deg2rad([2.0; -3.0; 1.5]);          % tumbling rate [rad/s]

% Capture point, fixed in the target BODY frame
p.target.p_cp_body = [0.8; 0.1; 0.0];             % [m]
% Capture AXIS in the target BODY frame. MODELLING ASSUMPTION, not a physical
% fact: the baseline takes the axis to be radially outward from the target
% centre of mass, i.e. the normalised capture-point position. A real grapple
% fixture has its own mounting orientation, which need not be radial. It is
% kept as a separate field so the assumption can be replaced without touching
% the geometry, and so that nothing in the code silently equates the two.
p.target.n_cp_body = p.target.p_cp_body / norm(p.target.p_cp_body);

% ----- Capture / keep-out geometry (notes/problem_formulation.md) -----
% Safety radius uses Minkowski inflation of the target body by the chaser
% extent plus an explicit margin (decision S3):
%     r_safe = r_target + r_chaser + margin
p.geom.r_target = 0.50;              % target bounding-sphere radius [m]
p.geom.r_chaser = 0.12;              % PROVISIONAL: chaser/end-effector bounding
                                     % radius [m]. Replace once the servicer
                                     % geometry is fixed; do not treat as final.
p.geom.margin   = 0.08;              % PROVISIONAL: safety margin [m]. The
                                     % adaptive layer (Task 6) will grow this
                                     % term; it must never reach r_grapple.
p.geom.r_safe   = p.geom.r_target + p.geom.r_chaser + p.geom.margin;

p.geom.r_grapple  = norm(p.target.p_cp_body);     % capture-point radius [m]
p.geom.theta_c    = deg2rad(20);     % approach-corridor half-angle [rad]
p.geom.L_corridor = 1.0;             % corridor length [m]

% ----- Chaser actuation (decision S6) -----
p.chaser.u_max = 0.01;               % per-axis acceleration limit [m/s^2],
                                     % applied component-wise: -u_max <= u_i <= u_max
p.chaser.m     = 100;                % chaser mass [kg], used only to convert
                                     % commanded acceleration into thrust/fuel

% ----- Control sampling (decision S4) -----
p.ctrl.Ts = 0.1;                     % controller sample time [s] (10 Hz)

% ----- HOCBF safety filter (Task 2, notes/task2_spec_hocbf_qp.md) -----
% Double pole, FIXED LITERALS (decision R1 / spec Sec. 2.3-2.4). These are
% deliberately NOT recomputed from u_max: the planned sensitivity sweep varies
% u_max over 0.005/0.01/0.02 and must change actuator authority alone, otherwise
% the experiment is confounded. cbf_gain_design.m reports the sizing heuristic
% (k <= sqrt(2*u_max/d_max) = 0.046 1/s at baseline) but never feeds back here.
p.cbf.k1 = 0.04;                     % class-K gain on h        [1/s]
p.cbf.k2 = 0.04;                     % class-K gain on psi1     [1/s]
p.cbf.delta = 0;                     % sampled-data tightening (R2: 0 in baseline)
p.cbf.W = eye(3);                    % QP weighting (R4: minimal Euclidean change)
p.cbf.act_thresh = 1e-6;             % "filter active" threshold on
                                     % ||u_safe - u_nom||_inf [m/s^2] (R5)

% ----- Nominal PD guidance used to isolate the filter (Task 2, spec Sec. 6) -----
% Kp is sized so the initial 10 m error does not by itself saturate the actuator
% (Kp*10 <= u_max), and Kd gives a critically damped response. Fixed literals for
% the same non-confounding reason as the CBF gains.
p.nominal.Kp = 0.001;                % [1/s^2]
p.nominal.Kd = 2*sqrt(0.001);        % [1/s]  (zeta = 1 -> 0.0632)

% ----- Baseline deterministic scenario (decision S5) -----
p.scenario.r0   = [0; -10; 0];       % start on the -V-bar [m]
p.scenario.v0   = [0; 0; 0];         % initially station-keeping [m/s]
p.scenario.Tsim = 120;               % scenario horizon [s]
% Capture runs need longer than the 120 s baseline: traversing the 9.3 m of
% initial clearance at the transit speed the geometry and actuator permit
% (v_cruise = 0.1 m/s, then the terminal braking profile) takes ~150 s.
p.scenario.Tcapture = 200;           % capture-scenario horizon [s]

% ----- Preview-based linear MPC (Task 3 A-core) -----
% notes/task3_spec_acore.md. Horizon from N*Ts >= v_typ/u_max = 10 s, where
% v_typ = 0.1 m/s is the representative peak closing speed of the transit phase
% (measured 0.12 m/s for the Task 2 PD; ~2x the 0.05 m/s mean needed to cross
% 9.3 m in ~200 s). Weights are normalised by physical scales so that rho is the
% only free knob.
p.mpc.N       = 100;                 % prediction horizon [steps] (10 s at Ts)
p.mpc.N_sweep = [50 100 200];        % pre-declared sensitivity sweep
p.mpc.sigma_p = 1.0;                 % position error scale [m]
p.mpc.sigma_v = 0.05;                % velocity error scale [m/s]
p.mpc.rho     = 1.0;                 % control-effort weight knob (NOT fuel)
p.mpc.rho_sweep = [0.1 1 10];
p.mpc.use_dlqr_terminal = true;      % terminal weight P from dlqr(Ad,Bd,Q,R)

% ----- Terminal-approach heuristic and capture reporting (Task 3) -----
% v_close <= min(v_cruise, sqrt(2*beta*u_max*s)), s = distance to the MOVING
% capture point. Heuristic only - not a feasibility or safety guarantee; see
% spec Sec. 6. beta reserves authority because following the tumbling capture
% point already costs 31-37% of u_max.
p.capture.beta     = 0.3;            % fraction of u_max reserved for braking
p.capture.v_cruise = 0.1;            % transit speed cap [m/s]
% Reference-shaping margin against the psi1 envelope. The reference commands at
% most gamma_env of the admissible INWARD RADIAL rate, so it stays inside the
% envelope instead of riding its boundary. This is reference compatibility
% logic, not a safety parameter: the guarantee remains the HOCBF's alone, and
% the CBF gains k1, k2 are untouched.
p.capture.gamma_env = 0.9;
p.capture.report_radii = [1.0 0.5 0.2 0.1];   % convergence-time reporting radii [m]
% Conditioning threshold for the approach-direction angle. The angle is formed
% from d = r - p_cp, whose DIRECTION becomes undefined as ||d|| -> 0, which is
% exactly the capture condition. Below this distance the angle is reported as
% NaN (undefined) and excluded from statistics rather than being reported as 0.
p.capture.align_min_dist = 0.05;             % [m]
% PROVISIONAL diagnostics only - D8 is NOT frozen, these are NOT success criteria
% and must not appear in the manuscript as such.
p.capture.eps_p_provisional     = 0.05;          % [m]
p.capture.eps_v_provisional     = 0.02;          % [m/s]
p.capture.theta_cap_provisional = deg2rad(20);   % [rad]

% ----- Simulation (target propagation, H1) -----
p.sim.dt      = 0.1;                 % output step [s]
p.sim.T_final = 120;                 % total sim time [s]

% ----- Consistency assertions -----
% The capture point must lie outside the bare target body...
assert(p.geom.r_grapple > p.geom.r_target, ...
    'params: capture point is inside the target body (r_grapple <= r_target).');
% ...and outside the inflated keep-out sphere, otherwise the safety constraint
% would make the mission objective unreachable.
assert(p.geom.r_safe < p.geom.r_grapple, ...
    ['params: keep-out radius swallows the capture point ' ...
     '(r_safe = %.3f m >= r_grapple = %.3f m). Reduce r_chaser/margin.'], ...
    p.geom.r_safe, p.geom.r_grapple);

end

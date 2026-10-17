function p = baseline_config()
% BASELINE_CONFIG  The parameter set every baseline run is executed under.
%
%   p = baseline_config() returns the Task 3 production configuration params()
%   with an ADDITIVE p.bl block holding the frozen baseline quantities of
%   protocol Sec. 2.1, 8 and 10. It modifies nothing that params() produced.
%
%   WHY params() AND NOT params_task4(). Protocol Sec. 9 removes D9 and alpha
%   from every baseline controller, harness and classification, and V11e
%   requires that NO artifact field is named or aliased 'alpha'. params_task4()
%   adds p.t4.alpha, p.t4.alpha_set, p.t4.alpha_status, p.t4.eps_rho and
%   p.t4.eps_h. Carrying p.t4 into a baseline run configuration would put those
%   names inside every saved artifact through the config field, so the whole
%   p.t4 block is deliberately NOT propagated.
%
%   s_cap IS STILL READ FROM THE FROZEN PRODUCTION CONFIGURATION, not re-typed
%   as a literal: params_task4() is called here for exactly two purposes -
%   reading p.t4.s_cap and running the frozen parameter-drift gate - and the
%   struct it returns is then discarded. Re-declaring 0.106226 locally would
%   create a second copy that could silently drift from the production one.
%
%   s_cap WORDING IS MANDATORY (protocol Sec. 2.1) and is carried in the config
%   so it reaches every artifact: s_cap is the frozen PROXIMITY THRESHOLD
%   derived by rounding a geometric standoff. It is NOT a physical capture or
%   grasp tolerance and must never be reported as one.
%
%   Nothing here is tuned. Every value is either read from the frozen
%   configuration, asserted against it, or derived from protocol constants by
%   BASELINE_CONSTANTS.

    p_frozen = params_task4();     % READ ONLY: s_cap source + drift gate subject

    % ---- frozen parameter-drift gate ---------------------------------------
    % Reproduced UNCHANGED from src/sim/task4_final_800s.m: identical fields,
    % identical values. Its purpose is to refuse to run if anything
    % result-relevant moved since the Task 4 freeze. It is not a new decision.
    drift_ok = p_frozen.t4.s_cap == 0.106226 && p_frozen.t4.kappa1 == 0.20 ...
        && p_frozen.t4.kappa2 == 0.20 ...
        && p_frozen.t4.Tw == 1.0 && p_frozen.t4.M == 50 && p_frozen.t4.gamma == 100 ...
        && abs(p_frozen.t4.nu0 - sqrt(3)) < 1e-15 && all(p_frozen.t4.theta_hat0 == 0) ...
        && p_frozen.t4.dwell_samples == 0 ...
        && p_frozen.cbf.k1 == 0.04 && p_frozen.cbf.k2 == 0.04 && p_frozen.cbf.delta == 0 ...
        && p_frozen.chaser.u_max == 0.01 && p_frozen.ctrl.Ts == 0.1 && p_frozen.mpc.N == 100 ...
        && abs(p_frozen.geom.r_safe - 0.70) < 1e-15;
    assert(drift_ok, 'baseline_config:drift', ...
        ['A frozen parameter differs from the Task 4 freeze record. Refusing ' ...
         'to build a baseline configuration.']);

    s_cap = p_frozen.t4.s_cap;
    clear p_frozen                 % p.t4, and therefore alpha, ends here

    % ---- Task 3 production base --------------------------------------------
    p = params();
    assert(~isfield(p, 't4'), 'baseline_config:t4_leak', ...
        'params() unexpectedly carries a t4 block; the alpha exclusion would leak.');

    % ---- additive baseline block -------------------------------------------
    p.bl.s_cap = s_cap;                                        % [m]
    assert(p.bl.s_cap == 0.106226, 'baseline_config:s_cap', ...
        's_cap = %.17g m is not the frozen 0.106226 m.', p.bl.s_cap);
    p.bl.s_cap_wording = ['the frozen proximity threshold s_cap = 0.106226 m, ' ...
        'derived by rounding the geometric standoff ||p_cp_body|| - r_safe ' ...
        '~ 0.106225774829855 m; it is not a physical capture/grasp tolerance'];
    p.bl.s_cap_source = 'params_task4().t4.s_cap (read, never re-declared)';

    % Derived frozen geometry and horizon bookkeeping.
    p.bl.geom = baseline_constants(p);
    p.bl.T_eval = p.bl.geom.T_eval;
    p.bl.n_sub  = p.bl.geom.n_sub;
    p.bl.N      = p.mpc.N;             % preview/prediction horizon, frozen at 100

    % ---- shared numerical execution contract (protocol Sec. 8) -------------
    p.bl.ode_reltol = 1e-10;
    p.bl.ode_abstol = 1e-12;
    p.bl.plant_mode = 'nonlinear';     % truth plant for EVERY method
    p.bl.drift_mode = 'cw';            % a_CW compensation and h_body Lie terms

    % Dimensionless utilisation threshold of Sec. 10.4. The 1e-9 is NUMERICAL,
    % not scientific: it exists so that a ratio landing on 1 to within double
    % round-off is counted as saturated. No acceleration-valued quantity is ever
    % subtracted from the number 1.
    p.bl.util_eps = 1e-9;

    % ---- the FORBIDDEN evaluation initial condition -------------------------
    % Recorded here once so every development and verification entry point can
    % refuse it from a single authoritative copy (protocol Sec. 5 and 14.0).
    p.bl.eval_x0 = [0; -10; 0; 0; 0; 0];
    p.bl.eval_x0_status = ['FORBIDDEN outside the frozen evaluation stage. It ' ...
        'may not appear in development scenarios D1-D5 or in V1-V11.'];

    % ---- provenance --------------------------------------------------------
    % The protocol record hash is an EXTERNAL identity. It is recorded so every
    % artifact names the contract it was produced under; it is verified against
    % the file by BASELINE_PREFLIGHT, not here.
    p.bl.protocol_file   = 'notes/task4_baseline_protocol_record.md';
    p.bl.protocol_sha256 = '07acf575652d7c182b0696689c19a5f0ef30dbd314c7c1f3fbbbd07cdd8be6e2';
    p.bl.d9_status = ['D9 and alpha are EXCLUDED from every baseline controller, ' ...
        'harness and classification (protocol Sec. 9). Baselines use only the ' ...
        'method-neutral proximity milestone.'];
end

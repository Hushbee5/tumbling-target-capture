function p = params_task4(p)
% PARAMS_TASK4  Append the frozen Task 4 parameter block to a Task 3 parameter set.
%   p = params_task4()  builds params() first and then appends.
%   p = params_task4(p) appends to a caller-supplied set.
%
%   Task 3 is FROZEN at commit fb4ff84. This function NEVER modifies any field
%   produced by params(); it only adds the p.t4.* block. Every value below is
%   taken verbatim from notes/task4_freeze_record.md, which is the authoritative
%   Task 4 specification. Nothing here is invented, tuned or derived from a run.
%
%   Provenance, field by field:
%     s_cap            freeze record Sec. 2.2 and Sec. 7 decision table  FROZEN
%     kappa1, kappa2   freeze record Sec. 3 (T4-D3-B)                    FROZEN
%     Tw, M, gamma     freeze record Sec. 1.2 configuration line         FROZEN
%     nu0              freeze record Sec. 1.1 (nu_0 = sqrt(3))           FROZEN
%     theta_hat0       freeze record Sec. 1.2 (theta_hat(0) = 0)         FROZEN
%     alpha            freeze record Sec. 8.5 development default    NOT FROZEN
%     eps_rho          derived: alpha * s_cap                            derived
%
%   See also PARAMS, SIMULATE_TASK4.

    if nargin < 1 || isempty(p), p = params(); end

    % ---- T4-D8: terminal commitment standoff (FROZEN) ---------------------
    % AUTHORITATIVE PRODUCTION VALUE: s_cap = 0.106226 m. This is the value in
    % the Task 4 decision table and the value the D3-A / D3-B screens were run
    % against, and it is the ONLY operative standoff parameter.
    %
    % Its provenance is the geometric subtraction ||p_b|| - r_safe, whose
    % unrounded result is 0.10622577482985..., i.e. 2.25e-07 m lower. That
    % unrounded value is PROVENANCE ONLY. It is deliberately NOT stored as a
    % number, so that no controller, detector, classifier or sweep can consume it
    % as an alternative operative parameter.
    p.t4.s_cap = 0.106226;                        % [m]   FROZEN, authoritative
    p.t4.s_cap_provenance = ['||p_cp_body|| - r_safe = 0.806226 - 0.70 ; the ' ...
        'unrounded 0.10622577482985... is PROVENANCE ONLY and is deliberately ' ...
        'not stored as a number so it cannot be consumed as a parameter'];
    p.t4.s_cap_sens   = 0.050;                    % [m]   frozen sensitivity case

    % ---- T4-D3-B: capture-chain class-K gains (FROZEN) --------------------
    p.t4.kappa1 = 0.20;                           % [1/s] FROZEN
    p.t4.kappa2 = 0.20;                           % [1/s] FROZEN

    % ---- T4-D4: concurrent-learning estimator (FROZEN) --------------------
    p.t4.Tw         = 1.0;                        % [s]   record window   FROZEN
    p.t4.M          = 50;                         %       stack depth     FROZEN
    p.t4.gamma      = 100;                        %       adaptation gain FROZEN
    p.t4.nu0        = sqrt(3);                    %       nu_sp(0)        FROZEN
    p.t4.theta_hat0 = zeros(3,1);                 %       initial estimate FROZEN
    % No projection rule. Freeze record Sec. 1 / D4-B established theta-invariance
    % of this estimator (theta_hat_i(t) = theta_i * (1 - s_i(t)) with s_i in (0,1]),
    % so the estimate never leaves the segment [0, theta_i) and projection is not
    % required. Do not add one.

    % ---- T4-D9: handoff detection (alpha NOT FROZEN) ----------------------
    p.t4.alpha     = 1e-3;                        % development default, NOT FROZEN
    p.t4.alpha_set = [1e-2, 1e-3, 1e-4];          % predeclared sweep set   FROZEN
    p.t4.eps_rho   = p.t4.alpha * p.t4.s_cap;     % [m]   derived
    p.t4.eps_h     = (p.t4.s_cap + p.t4.eps_rho)^2 - p.t4.s_cap^2;  % [m^2] derived
    p.t4.alpha_status = 'NOT FROZEN - numerical event-detection parameter only';
    % No dwell (freeze record Sec. 8.3). Do not add a dwell constant.
    p.t4.dwell_samples = 0;                       %       FROZEN: no dwell

    % ---- true inertia ratios, for the truth model and for diagnostics -----
    % theta = [(I2-I3)/I1, (I3-I1)/I2, (I1-I2)/I3]   (freeze record Sec. 1 context)
    I = p.target.I;
    p.t4.theta_true = [ (I(2,2)-I(3,3))/I(1,1);
                        (I(3,3)-I(1,1))/I(2,2);
                        (I(1,1)-I(2,2))/I(3,3) ];

    % ---- consistency assertions (no new decisions, just guards) -----------
    assert(p.t4.s_cap > 0, 'params_task4:s_cap', 's_cap must be positive.');
    assert(p.t4.s_cap <= norm(p.target.p_cp_body) - p.geom.r_safe + 1e-6, ...
        'params_task4:reach', ...
        ['s_cap = %.9f m exceeds the reachable clearance %.9f m; the commitment ' ...
         'surface would intersect the keep-out sphere.'], ...
        p.t4.s_cap, norm(p.target.p_cp_body) - p.geom.r_safe);
    % NON-SCIENTIFIC IMPLEMENTATION SANITY CHECK. This is a coarse guard against a
    % grossly mis-specified gain/step combination, e.g. a typo in kappa1 or Ts.
    % It is NOT a sampled-data adequacy criterion: no theorem establishes
    % kappa1*Ts < 1 as a condition for anything here, and PASSING IT CARRIES NO
    % SAMPLED-DATA OR INTERSAMPLE GUARANTEE WHATSOEVER. Do not cite it as one.
    assert(p.t4.kappa1*p.ctrl.Ts < 1, 'params_task4:sanity_kTs', ...
        ['kappa1*Ts = %.4f >= 1, which indicates a mis-specified gain or step ' ...
         'size. This is an implementation sanity check only.'], ...
        p.t4.kappa1*p.ctrl.Ts);
end

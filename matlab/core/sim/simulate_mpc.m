function out = simulate_mpc(p, opt)
% SIMULATE_MPC  Closed loop: preview-based linear MPC + HOCBF-QP safety filter.
%   out = simulate_mpc(p, opt) runs the A-core architecture of
%   notes/task3_spec_acore.md:
%
%     x -> [reference preview] -> [MPC QP] -> u_mpc -> [HOCBF-QP] -> u_safe -> plant
%
%   The MPC is not warm-started from the filtered command and is not told about
%   the filter: it re-solves from the measured state, which already reflects
%   whatever the filter did previously (spec Sec. 7). The disagreement
%   ||u_safe - u_mpc||_inf is recorded as the primary escalation signal.
%
%   opt fields (optional):
%     x0          initial state (default scenario)
%     Tsim        horizon [s] (default p.scenario.Tcapture)
%     use_filter  default true
%     N           prediction horizon override
%     n_sub       intersample evaluation points per step (default 10)
%     targetEst   estimated target state for the preview (default = truth)
%
%   Truth model is the nonlinear relative dynamics; the MPC and the filter both
%   use the CW model (decision S1).

    if nargin < 2, opt = struct(); end
    if ~isfield(opt,'x0'),         opt.x0 = [p.scenario.r0; p.scenario.v0]; end
    if ~isfield(opt,'Tsim'),       opt.Tsim = p.scenario.Tcapture;          end
    if ~isfield(opt,'use_filter'), opt.use_filter = true;                   end
    if ~isfield(opt,'N'),          opt.N = p.mpc.N;                         end
    if ~isfield(opt,'n_sub'),      opt.n_sub = 10;                          end
    if ~isfield(opt,'targetEst')
        opt.targetEst = struct('q', p.target.q0, 'w', p.target.w0, 'I', p.target.I);
    end

    Ts = p.ctrl.Ts;
    N  = opt.N;
    K  = round(opt.Tsim / Ts);
    t  = (0:K) * Ts;

    % capture-point table must cover the horizon beyond the last control step
    if isfield(opt, 'tbl') && ~isempty(opt.tbl)
        tbl = opt.tbl;               % injected table, used by the validation tests
    else
        tbl = capture_table_build(p, opt.targetEst, opt.Tsim + (N+2)*Ts);
    end
    M   = mpc_condensed(p, N);

    X      = zeros(6, K+1);  X(:,1) = opt.x0(:);
    Umpc   = zeros(3, K);    Usafe  = zeros(3, K);
    Pcp    = zeros(3, K+1);  Vcp    = zeros(3, K+1);  Ncp = zeros(3, K+1);
    hH     = zeros(1, K+1);  dSafe  = zeros(1, K+1);  ps1 = zeros(1, K+1);
    ps2    = nan(1, K);      devH   = zeros(1, K);    actH = false(1, K);
    feasM  = zeros(1, K);    statH  = zeros(1, K);
    mpcFlag= zeros(1, K);    tSolve = zeros(1, K);    sCp  = zeros(1, K+1);
    vClose = zeros(1, K+1);  algn   = zeros(1, K+1);
    % radial/tangential diagnostics (spec correction: the psi1 envelope bounds
    % the radial component only, never the full velocity norm)
    vRad   = zeros(1, K+1);  vTan   = zeros(1, K+1);
    vCpTan = zeros(1, K+1);  vTrack = zeros(1, K+1);
    vRadRaw= zeros(1, K);    vRadShp= zeros(1, K);
    vRadEnv= zeros(1, K);    radLim = false(1, K);
    % nominal (pre-filter) HOCBF residual diagnostic - reporting only
    ps2Nom = zeros(1, K);    devRad = zeros(1, K);    devTan = zeros(1, K);
    cRaw   = zeros(1, K);    cShp   = zeros(1, K);    envInf = false(1, K);
    % reference-kinematics consistency data (W17): D = Pref - Pcp over the horizon
    refKinErr = zeros(1, K);

    interT = []; interH = []; interP = [];
    odeOpt = odeset('RelTol', 1e-10, 'AbsTol', 1e-12);

    for k = 1:K
        xk = X(:,k);

        [Pref, Vref, rinfo] = capture_reference_preview(t(k), xk, N, p, tbl);
        Pcp(:,k) = rinfo.p_cp;  Vcp(:,k) = rinfo.v_cp;  Ncp(:,k) = rinfo.n_cp;
        sCp(k)   = rinfo.s_cp;  vClose(k) = rinfo.v_close;
        algn(k)  = alignment_angle(xk(1:3), rinfo.p_cp, rinfo.n_cp, p.capture.align_min_dist);
        vRadRaw(k) = rinfo.v_rad_raw;  vRadShp(k) = rinfo.v_rad_shaped;
        vRadEnv(k) = rinfo.v_rad_env;  radLim(k)  = rinfo.rad_limited;
        cRaw(k)    = rinfo.c_raw;      cShp(k)    = rinfo.c_shaped;
        envInf(k)  = rinfo.env_infeasible;
        % W17: (D_{j+1} - D_j)/Ts must equal Vref_j - Vcp_j along the horizon
        refKinErr(k) = reference_kinematics_error(t(k), N, p, tbl, Pref, Vref);
        [vRad(k), vTan(k)] = radial_tangential(xk(1:3), xk(4:6));
        [~, vCpTan(k)]     = radial_tangential(rinfo.p_cp, rinfo.v_cp);
        vTrack(k)          = norm(xk(4:6) - rinfo.v_cp);

        [u_mpc, minfo] = mpc_step(xk, Pref, Vref, M, p);
        mpcFlag(k) = minfo.exitflag;
        tSolve(k)  = minfo.solve_time;

        if opt.use_filter
            [u_app, finfo] = cbf_qp_filter(xk, u_mpc, p);
            if ~finfo.feasible
                out = finish(t, X, Umpc, Usafe, Pcp, Vcp, Ncp, hH, dSafe, ps1, ps2, ...
                             devH, actH, feasM, statH, mpcFlag, tSolve, sCp, ...
                             vClose, algn, vRad, vTan, vCpTan, vTrack, ...
                             vRadRaw, vRadShp, vRadEnv, radLim, ps2Nom, devRad, devTan, ...
                             cRaw, cShp, envInf, refKinErr, interT, interH, interP, k, N);
                out.aborted = true;
                out.abort_reason = sprintf('QP infeasible at k = %d (t = %.2f s)', k, t(k));
                return
            end
        else
            finfo = filter_diagnostics(xk, u_mpc, p);
            u_app = u_mpc;
        end

        % --- diagnostics: HOCBF residual of the UNFILTERED MPC command, and the
        %     radial/tangential split of the correction (reporting only) ---
        [hk, ~, hdk, Lf2k, Lgk] = safety_function(xk, p, 'cw');
        ps2Nom(k) = (Lf2k + Lgk*u_mpc) + (p.cbf.k1 + p.cbf.k2)*hdk ...
                    + p.cbf.k1*p.cbf.k2*hk;
        [devRad(k), devTan(k)] = radial_tangential(xk(1:3), u_app - u_mpc);

        Umpc(:,k)  = u_mpc;   Usafe(:,k) = u_app;
        hH(k)  = finfo.h;     dSafe(k) = finfo.d_safe;  ps1(k) = finfo.psi1;
        ps2(k) = finfo.psi2;  devH(k) = finfo.dev_inf;  actH(k) = finfo.active;
        feasM(k) = finfo.feas_margin;  statH(k) = finfo.status;

        tsub = linspace(t(k), t(k+1), opt.n_sub + 1);
        [~, Xs] = ode45(@(tt, xx) rel_translational_dynamics(xx, u_app, p, 'nonlinear'), ...
                        tsub, xk, odeOpt);
        X(:,k+1) = Xs(end,:).';

        for j = 2:opt.n_sub
            xj = Xs(j,:).';
            [hj, ~, hdj, Lf2j, Lgj] = safety_function(xj, p, 'cw');
            interT(end+1) = tsub(j);  %#ok<AGROW>
            interH(end+1) = hj;       %#ok<AGROW>
            interP(end+1) = (Lf2j + Lgj*u_app) + (p.cbf.k1 + p.cbf.k2)*hdj ...
                            + p.cbf.k1*p.cbf.k2*hj;   %#ok<AGROW>
        end
    end

    % terminal bookkeeping
    [~, ~, rinfoEnd] = capture_reference_preview(t(K+1), X(:,K+1), 1, p, tbl);
    Pcp(:,K+1) = rinfoEnd.p_cp;  Vcp(:,K+1) = rinfoEnd.v_cp;  Ncp(:,K+1) = rinfoEnd.n_cp;
    sCp(K+1)   = rinfoEnd.s_cp;  vClose(K+1) = rinfoEnd.v_close;
    algn(K+1)  = alignment_angle(X(1:3,K+1), rinfoEnd.p_cp, rinfoEnd.n_cp, p.capture.align_min_dist);
    [vRad(K+1), vTan(K+1)] = radial_tangential(X(1:3,K+1), X(4:6,K+1));
    [~, vCpTan(K+1)]       = radial_tangential(rinfoEnd.p_cp, rinfoEnd.v_cp);
    vTrack(K+1)            = norm(X(4:6,K+1) - rinfoEnd.v_cp);
    [hH(K+1), dSafe(K+1), hdEnd] = safety_function(X(:,K+1), p, 'cw');
    ps1(K+1) = hdEnd + p.cbf.k1*hH(K+1);

    out = finish(t, X, Umpc, Usafe, Pcp, Vcp, Ncp, hH, dSafe, ps1, ps2, ...
                 devH, actH, feasM, statH, mpcFlag, tSolve, sCp, ...
                 vClose, algn, vRad, vTan, vCpTan, vTrack, ...
                 vRadRaw, vRadShp, vRadEnv, radLim, ps2Nom, devRad, devTan, ...
                 cRaw, cShp, envInf, refKinErr, interT, interH, interP, K, N);
    out.aborted = false;
    out.abort_reason = '';
end

% ===== local functions ====================================================
function ang = alignment_angle(r, p_cp, n_cp, dmin)
% APPROACH-DIRECTION diagnostic: angle between d = r - p_cp and the capture axis
% n_cp, both in LVLH. This is NOT an end-effector orientation: the chaser is a
% point in this model and has no modelled attitude.
%
% The DIRECTION of d is undefined as ||d|| -> 0, which is exactly the capture
% condition, so below the documented conditioning threshold the angle is
% returned as NaN (undefined) rather than as a spurious 0. NaN values must be
% excluded from angle statistics.
    d  = r - p_cp;
    nd = norm(d);
    if nd < dmin || norm(n_cp) < 1e-12
        ang = NaN;
    else
        ang = acos( max(-1, min(1, (d.'*n_cp)/(nd*norm(n_cp)) )) );
    end
end

function e = reference_kinematics_error(tk, N, p, tbl, Pref, Vref)
% W17: verify Vref_j - Vcp_j == d(Pref_j - Vcp_j)/dt for the scheduled offset.
%   D_j = Pref_j - Pcp_j ;  the piecewise-constant schedule must satisfy
%   (D_{j+1} - D_j)/Ts = Vref_j - Vcp_j.
% The old vector-shaping implementation violates this whenever u_r is not
% parallel to e_hat; the corrected scalar-c construction satisfies it exactly.
    Ts   = p.ctrl.Ts;
    idx0 = round(tk / tbl.Ts) + 1;
    idx  = idx0 + (0:N);
    Pcp  = tbl.pL(:, idx);
    Vcp  = tbl.vL(:, idx);
    D    = Pref - Pcp;
    lhs  = (D(:, 2:end) - D(:, 1:end-1)) / Ts;
    rhs  = Vref(:, 1:end-1) - Vcp(:, 1:end-1);
    e    = max(vecnorm(lhs - rhs));
end

function [v_rad, v_tan] = radial_tangential(r, v)
% Decompose a velocity into radial and tangential components about the target COM.
%   v_rad is signed (negative = inward); v_tan is the magnitude of the remainder.
    rho = norm(r);
    if rho < eps
        v_rad = 0;  v_tan = norm(v);  return
    end
    u_r   = r / rho;
    v_rad = v.' * u_r;
    v_tan = norm(v - v_rad*u_r);
end

function info = filter_diagnostics(x, u, p)
% Barrier diagnostics for an unfiltered run (the command is applied unchanged).
    [h, d_safe, hdot, Lf2h, Lgh] = safety_function(x, p, 'cw');
    k1 = p.cbf.k1;  k2 = p.cbf.k2;
    info.h = h;  info.d_safe = d_safe;
    info.psi1 = hdot + k1*h;
    info.psi2 = (Lf2h + Lgh*u) + (k1 + k2)*hdot + k1*k2*h;
    info.feasible    = true;
    info.feas_margin = (Lf2h + (k1+k2)*hdot + k1*k2*h - p.cbf.delta) ...
                       + p.chaser.u_max*norm(2*x(1:3), 1);
    info.dev_inf = 0;  info.active = false;  info.status = 0;
end

function out = finish(t, X, Umpc, Usafe, Pcp, Vcp, Ncp, hH, dSafe, ps1, ps2, ...
                      devH, actH, feasM, statH, mpcFlag, tSolve, sCp, ...
                      vClose, algn, vRad, vTan, vCpTan, vTrack, ...
                      vRadRaw, vRadShp, vRadEnv, radLim, ps2Nom, devRad, devTan, ...
                      cRaw, cShp, envInf, refKinErr, interT, interH, interP, kEnd, N)
    idx  = 1:kEnd;
    idxS = 1:min(kEnd+1, numel(t));
    out.t = t(idxS);   out.X = X(:, idxS);
    out.Pcp = Pcp(:, idxS);  out.Vcp = Vcp(:, idxS);  out.Ncp = Ncp(:, idxS);
    out.Umpc = Umpc(:, idx); out.Usafe = Usafe(:, idx);
    out.h = hH(idxS);  out.d_safe = dSafe(idxS);
    out.psi1 = ps1(idxS);  out.psi2 = ps2(idx);
    out.dev_inf = devH(idx);  out.active = actH(idx);
    out.feas_margin = feasM(idx);  out.status = statH(idx);
    out.mpc_exitflag = mpcFlag(idx);  out.solve_time = tSolve(idx);
    out.s_cp = sCp(idxS);  out.v_close = vClose(idxS);  out.align = algn(idxS);
    out.v_rad = vRad(idxS);      out.v_tan = vTan(idxS);
    out.v_cp_tan = vCpTan(idxS); out.v_track = vTrack(idxS);
    out.v_rad_raw = vRadRaw(idx);  out.v_rad_shaped = vRadShp(idx);
    out.v_rad_env = vRadEnv(idx);  out.rad_limited = radLim(idx);
    out.psi2_nom  = ps2Nom(idx);
    out.dev_rad   = devRad(idx);   out.dev_tan = devTan(idx);
    out.c_raw = cRaw(idx);  out.c_shaped = cShp(idx);
    out.env_infeasible = envInf(idx);
    out.ref_kin_err = refKinErr(idx);
    out.N = N;
    out.inter.t = interT;  out.inter.h = interH;  out.inter.psi2 = interP;
    if isempty(interH)
        out.inter.h_min = NaN;  out.inter.psi2_min = NaN;
    else
        out.inter.h_min = min(interH);  out.inter.psi2_min = min(interP);
    end
    % performance metrics (spec Sec. 4.1: effort is NOT fuel)
    Ts = t(2) - t(1);
    out.effort_quadratic = sum(sum(out.Usafe.^2, 1)) * Ts;      % [m^2/s^3]
    out.delta_v          = sum(vecnorm(out.Usafe)) * Ts;        % [m/s]
end

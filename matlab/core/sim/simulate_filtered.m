function out = simulate_filtered(p, opt)
% SIMULATE_FILTERED  Closed-loop run of nominal guidance with/without the filter.
%   out = simulate_filtered(p, opt) runs the sampled-data loop of
%   notes/task2_spec_hocbf_qp.md: at each control instant the nominal PD command
%   is computed, optionally passed through the HOCBF-QP safety filter, then held
%   constant while the TRUTH model ('nonlinear' relative dynamics) is integrated
%   over one sample.
%
%   opt fields (all optional unless noted):
%     x0          initial state [r;v] (default p.scenario.r0/v0)
%     Tsim        horizon [s] (default p.scenario.Tsim)
%     use_filter  logical, default true
%     ref_mode    'origin'  : r_ref = 0        (structurally unsafe, scenario N2)
%                 'point'   : r_ref = opt.r_ref (benign standoff, scenario N1)
%                 'capture' : r_ref = tumbling capture point in LVLH (N1b)
%     r_ref       required for ref_mode 'point'
%     n_sub       intersample evaluation points per step (default 10)
%
%   Returned (per control instant k = 1..N):
%     t, X (6xN), Unom (3xN), Usafe (3xN), Rref (3xN)
%     h, d, psi1, psi2, dev_inf, active, feas_margin, status, lambda   (1xN)
%     inter.h_min, inter.psi2_min   worst values found BETWEEN control instants
%     inter.t, inter.h, inter.psi2  the full intersample traces
%
%   The filter evaluates the HOCBF with the 'cw' prediction model while the plant
%   is propagated with the 'nonlinear' truth model, which is the truth/prediction
%   split fixed by decision S1.

    if nargin < 2, opt = struct(); end
    if ~isfield(opt, 'x0'),         opt.x0 = [p.scenario.r0; p.scenario.v0]; end
    if ~isfield(opt, 'Tsim'),       opt.Tsim = p.scenario.Tsim;              end
    if ~isfield(opt, 'use_filter'), opt.use_filter = true;                   end
    if ~isfield(opt, 'ref_mode'),   opt.ref_mode = 'origin';                 end
    if ~isfield(opt, 'n_sub'),      opt.n_sub = 10;                          end

    Ts = p.ctrl.Ts;
    N  = round(opt.Tsim / Ts);
    t  = (0:N) * Ts;

    % --- reference trajectory ------------------------------------------------
    [Rref, Vref] = build_reference(t, p, opt);

    % --- allocation ----------------------------------------------------------
    X     = zeros(6, N+1);   X(:,1) = opt.x0(:);
    Unom  = zeros(3, N);     Usafe  = zeros(3, N);
    hH    = zeros(1, N+1);   dH     = zeros(1, N+1);
    ps1   = zeros(1, N+1);   ps2    = nan(1, N);
    devH  = zeros(1, N);     actH   = false(1, N);
    feasM = zeros(1, N);     statH  = zeros(1, N);   lamH = zeros(1, N);

    interT = []; interH = []; interP = [];
    odeOpt = odeset('RelTol', 1e-10, 'AbsTol', 1e-12);

    for k = 1:N
        xk = X(:, k);

        u_nom = nominal_pd(xk, Rref(:,k), Vref(:,k), p);
        [~, ~, ~, info0] = deal([], [], [], []);                    %#ok<ASGLU>

        if opt.use_filter
            [u_app, info] = cbf_qp_filter(xk, u_nom, p);
            if ~info.feasible
                out = finish(t, X, Unom, Usafe, Rref, hH, dH, ps1, ps2, devH, ...
                             actH, feasM, statH, lamH, interT, interH, interP, k);
                out.aborted = true;
                out.abort_reason = sprintf('QP infeasible at k = %d (t = %.2f s)', k, t(k));
                return
            end
        else
            % unfiltered baseline: still evaluate diagnostics for reporting
            info  = diagnostics_only(xk, u_nom, p);
            u_app = u_nom;
        end

        Unom(:,k)  = u_nom;
        Usafe(:,k) = u_app;
        hH(k)      = info.h;      dH(k)   = info.d_safe;
        ps1(k)     = info.psi1;   ps2(k)  = info.psi2;
        devH(k)    = info.dev_inf; actH(k) = info.active;
        feasM(k)   = info.feas_margin;
        statH(k)   = info.status; lamH(k) = info.lambda;

        % --- propagate the TRUTH model over one hold interval -----------------
        tsub = linspace(t(k), t(k+1), opt.n_sub + 1);
        [~, Xs] = ode45(@(tt, xx) rel_translational_dynamics(xx, u_app, p, 'nonlinear'), ...
                        tsub, xk, odeOpt);
        X(:, k+1) = Xs(end, :).';

        % --- intersample diagnostics (exclude the sample points themselves) ---
        for j = 2:opt.n_sub
            xj = Xs(j, :).';
            [hj, ~, hdj, Lf2j, Lgj] = safety_function(xj, p, 'cw');
            p2j = (Lf2j + Lgj*u_app) + (p.cbf.k1 + p.cbf.k2)*hdj + p.cbf.k1*p.cbf.k2*hj;
            interT(end+1) = tsub(j);   %#ok<AGROW>
            interH(end+1) = hj;        %#ok<AGROW>
            interP(end+1) = p2j;       %#ok<AGROW>
        end
    end

    % terminal-state barrier values
    [hH(N+1), dH(N+1), hdotEnd] = safety_function(X(:,N+1), p, 'cw');
    ps1(N+1) = hdotEnd + p.cbf.k1*hH(N+1);

    out = finish(t, X, Unom, Usafe, Rref, hH, dH, ps1, ps2, devH, ...
                 actH, feasM, statH, lamH, interT, interH, interP, N);
    out.aborted = false;
    out.abort_reason = '';
end

% ===== local functions =====================================================
function [Rref, Vref] = build_reference(t, p, opt)
    N1 = numel(t);
    switch lower(opt.ref_mode)
        case 'origin'
            Rref = zeros(3, N1);  Vref = zeros(3, N1);
        case 'point'
            Rref = repmat(opt.r_ref(:), 1, N1);  Vref = zeros(3, N1);
        case 'capture'
            pt = p;  pt.sim.dt = p.ctrl.Ts;  pt.sim.T_final = t(end);
            [tt, qH, wH]      = target_tumbling_model(pt);
            [pI, vI, nI]      = capture_point_trajectory(qH, wH, pt);
            [pL, vL, ~]       = capture_point_lvlh(tt, pI, vI, nI, pt);
            Rref = pL(:, 1:N1);  Vref = vL(:, 1:N1);
        otherwise
            error('simulate_filtered:ref_mode', 'unknown ref_mode "%s"', opt.ref_mode);
    end
end

function info = diagnostics_only(x, u_nom, p)
% Barrier diagnostics for an unfiltered run: the command is applied unchanged.
    [h, d_safe, hdot, Lf2h, Lgh] = safety_function(x, p, 'cw');
    k1 = p.cbf.k1;  k2 = p.cbf.k2;
    info.h    = h;
    info.d_safe = d_safe;
    info.hdot = hdot;
    info.psi1 = hdot + k1*h;
    info.psi2 = (Lf2h + Lgh*u_nom) + (k1 + k2)*hdot + k1*k2*h;
    info.feasible    = true;
    info.feas_margin = (Lf2h + (k1+k2)*hdot + k1*k2*h - p.cbf.delta) ...
                       + p.chaser.u_max*norm(2*x(1:3), 1);
    info.dev_inf = 0;
    info.active  = false;
    info.status  = 0;
    info.lambda  = 0;
end

function out = finish(t, X, Unom, Usafe, Rref, hH, dH, ps1, ps2, devH, ...
                      actH, feasM, statH, lamH, interT, interH, interP, kEnd)
    idx  = 1:kEnd;
    idxS = 1:min(kEnd+1, numel(t));
    out.t     = t(idxS);
    out.X     = X(:, idxS);
    out.Rref  = Rref(:, idxS);
    out.Unom  = Unom(:, idx);
    out.Usafe = Usafe(:, idx);
    out.h     = hH(idxS);
    out.d_safe = dH(idxS);
    out.psi1  = ps1(idxS);
    out.psi2  = ps2(idx);
    out.dev_inf     = devH(idx);
    out.active      = actH(idx);
    out.feas_margin = feasM(idx);
    out.status      = statH(idx);
    out.lambda      = lamH(idx);
    out.inter.t     = interT;
    out.inter.h     = interH;
    out.inter.psi2  = interP;
    if isempty(interH)
        out.inter.h_min = NaN;  out.inter.psi2_min = NaN;
    else
        out.inter.h_min    = min(interH);
        out.inter.psi2_min = min(interP);
    end
end

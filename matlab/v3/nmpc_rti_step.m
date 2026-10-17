function [u, st, info] = nmpc_rti_step(x, Pref, Vref, Pcp, commit_on, NM, st)
% NMPC_RTI_STEP  V3n (DEVELOPMENT): nonlinear MPC by sequential quadratic programming in the real-time-
%   iteration form (one SQP iteration per sample when NM.iters = 1; more iterations = converged SQP).
%
%   PREDICTION MODEL. The nonlinear two-body relative dynamics in LVLH (the truth model of r3, eq. 2:
%   REL_TRANSLATIONAL_DYNAMICS 'nonlinear'), discretised by RK4 over Ts with the command held constant. It is
%   NOT the CW model: the linearisation used inside each SQP iteration is recomputed along the current
%   nominal trajectory of the nonlinear model (time-varying A_i, B_i by finite differences of the RK4 map).
%
%   STATE CONSTRAINTS (the reason an NMPC is used here). At every node i = 1..N:
%     keep-out sphere      ||r_i|| >= r_safe                    (non-convex)
%     commitment sphere    ||r_i - p_cp,i|| >= s_cap            (non-convex; only while commit_on, i.e. before
%                                                               the handoff), p_cp,i from the online preview
%   Each is replaced in the QP by the half-space tangent to the sphere at the projection of the nominal node
%   (an INNER approximation of the admissible exterior), and softened by a non-negative slack with an exact
%   L1 penalty plus a quadratic term, so the QP is always feasible. The slacks are reported; the CBF safety
%   filter below stays the hard safety layer.
%   COST (identical to the frozen linear MPC, MPC_CONDENSED): sum_i (x_i - x_ref,i)'Q(x_i - x_ref,i), terminal P,
%   + u'Ru; input box |u_j| <= u_max.
%
%   st: warm start (st.U, 3N x 1). info: exitflag, iters, solve_time, max slack (keep-out / commitment),
%   linearisation error (nonlinear rollout of U* vs the QP's prediction), n_active state constraints.

    N = NM.N;  nx = 6;  nu = 3;  Ts = NM.Ts;
    if isempty(st) || ~isfield(st, 'U') || numel(st.U) ~= nu*N
        Ubar = zeros(nu*N, 1);
    else
        Ubar = [st.U(nu+1:end); st.U(end-nu+1:end)];             % shift
    end
    Xr = reshape([Pref(:, 2:N+1); Vref(:, 2:N+1)], [], 1);
    qpo = optimoptions('quadprog', 'Display', 'none', 'Algorithm', 'interior-point-convex', ...
                       'OptimalityTolerance', 1e-10, 'ConstraintTolerance', 1e-10, 'MaxIterations', 400);
    tS = tic;  iters = 0;  exitflag = NaN;  Uopt = Ubar;  slk = zeros(0,1);  nAct = 0;
    for it = 1:NM.iters
        iters = it;
        Ulin = Ubar;                       % linearisation point of this iteration (diagnostic below)
        % ---- nominal rollout and time-varying sensitivities --------------------------------------
        Xb = zeros(nx, N+1);  Xb(:, 1) = x(:);
        A = zeros(nx, nx, N);  B = zeros(nx, nu, N);
        for i = 1:N
            ui = Ubar((i-1)*nu + (1:nu));
            hx = 1e-6 * max(1, abs(Xb(:, i)));  hu = 1e-9 * ones(nu, 1);
            Xs = [Xb(:, i), Xb(:, i) + diag(hx), repmat(Xb(:, i), 1, nu)];
            Us = [repmat(ui, 1, nx + 1), ui + diag(hu)];
            Fs = rk4_batch(Xs, Us, Ts, NM);
            Xb(:, i+1) = Fs(:, 1);
            A(:, :, i) = (Fs(:, 2:nx+1) - Fs(:, 1)) ./ hx.';
            B(:, :, i) = (Fs(:, nx+2:end) - Fs(:, 1)) ./ hu.';
        end
        % ---- condensed time-varying prediction  X = Xbar + Su (U - Ubar) -------------------------
        Su = zeros(nx*N, nu*N);
        for i = 1:N
            ri = (i-1)*nx + (1:nx);
            if i > 1
                Su(ri, 1:nu*(i-1)) = A(:, :, i) * Su(ri - nx, 1:nu*(i-1));
            end
            Su(ri, (i-1)*nu + (1:nu)) = B(:, :, i);
        end
        Xbv = reshape(Xb(:, 2:N+1), [], 1);
        H = 2 * (Su.' * NM.Qbar * Su + NM.Rbar);  H = (H + H.') / 2;
        f = 2 * Su.' * (NM.Qbar * (Xbv - Su * Ubar - Xr));
        % ---- linearised state constraints with slacks ----------------------------------------------
        Ain = zeros(0, nu*N);  bin = zeros(0, 1);  rowsN = 0;
        for i = 1:N
            ri = (i-1)*nx + (1:3);
            rb = Xb(1:3, i+1);  Sp = Su(ri, :);
            n_i = rb / max(norm(rb), 1e-9);
            Ain(end+1, :) = -n_i.' * Sp;                                       %#ok<AGROW>
            bin(end+1, 1) = n_i.' * (rb - Sp * Ubar) - NM.r_safe;              %#ok<AGROW>
            rowsN = rowsN + 1;
        end
        nKeep = rowsN;
        if commit_on
            for i = 1:N
                ri = (i-1)*nx + (1:3);
                rb = Xb(1:3, i+1);  Sp = Su(ri, :);  dcp = rb - Pcp(:, i+1);
                m_i = dcp / max(norm(dcp), 1e-9);
                Ain(end+1, :) = -m_i.' * Sp;                                   %#ok<AGROW>
                bin(end+1, 1) = m_i.' * (rb - Sp * Ubar - Pcp(:, i+1)) - NM.s_cap;   %#ok<AGROW>
            end
        end
        nS = size(Ain, 1);
        Haug = blkdiag(H, NM.w_s2 * eye(nS));
        faug = [f; NM.w_s1 * ones(nS, 1)];
        Aaug = [Ain, -eye(nS)];
        lb = [-NM.u_max * ones(nu*N, 1); zeros(nS, 1)];
        ub = [ NM.u_max * ones(nu*N, 1); inf(nS, 1)];
        [z, ~, exitflag] = quadprog(Haug, faug, Aaug, bin, [], [], lb, ub, [], qpo);
        if isempty(z) || exitflag <= 0
            break
        end
        Unew = z(1:nu*N);  slk = z(nu*N+1:end);
        nAct = sum(abs(Aaug * z - bin) <= 1e-8);
        dU = norm(Unew - Ubar, inf);
        Ubar = Unew;  Uopt = Unew;
        if dU < NM.tol_sqp
            break
        end
    end
    info.solve_time = toc(tS);
    info.exitflag = exitflag;  info.iters = iters;  info.n_active = nAct;
    if isempty(slk)
        info.max_slack_keepout = NaN;  info.max_slack_commit = NaN;
    else
        info.max_slack_keepout = max(slk(1:nKeep));
        info.max_slack_commit = max([slk(nKeep+1:end); 0]);
    end
    if ~(exitflag > 0)
        % QP failure: shifted warm start (best effort), reported
        Uopt = Ubar;
        info.failed = true;
    else
        info.failed = false;
    end
    % linearisation error: nonlinear rollout of Uopt vs the last QP prediction (diagnostic)
    Xn = zeros(nx, N+1);  Xn(:, 1) = x(:);
    for i = 1:N
        Xn(:, i+1) = rk4_batch(Xn(:, i), Uopt((i-1)*nu + (1:nu)), Ts, NM);
    end
    if exist('Su', 'var') && exist('Xbv', 'var')
        info.lin_err = max(abs(reshape(Xn(:, 2:N+1), [], 1) - (Xbv + Su * (Uopt - Ulin))));
    else
        info.lin_err = NaN;
    end
    info.min_pred_range = min(vecnorm(Xn(1:3, 2:end)));
    u = Uopt(1:nu);
    st.U = Uopt;
end

function Xn = rk4_batch(X, U, Ts, NM)
    k1 = nmpc_f_nl(X, U, NM);
    k2 = nmpc_f_nl(X + 0.5*Ts*k1, U, NM);
    k3 = nmpc_f_nl(X + 0.5*Ts*k2, U, NM);
    k4 = nmpc_f_nl(X + Ts*k3, U, NM);
    Xn = X + Ts/6 * (k1 + 2*k2 + 2*k3 + k4);
end

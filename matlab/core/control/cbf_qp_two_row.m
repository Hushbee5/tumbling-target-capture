function [u_safe, info] = cbf_qp_two_row(rows, u_nom, p)
% CBF_QP_TWO_ROW  Production multi-row HOCBF-QP safety filter for Task 4.
%   [u_safe, info] = cbf_qp_two_row(rows, u_nom, p) solves
%
%       min   0.5*||u - u_nom||^2
%       s.t.  A_i * u <= b_i        for every row i in `rows`
%             -u_max <= u_j <= u_max
%
%   `rows` is a struct array with fields
%       A     1x3 constraint normal   (A = -Lgh for a HOCBF row)
%       b     scalar right-hand side  (b = Lf2h + (k1+k2) hdot + k1 k2 h - tightening)
%       name  char, e.g. 'body' or 'cap'
%
%   ROW SET. Before a NORMAL D9 handoff the caller passes BOTH the body row and
%   the capture row. After a NORMAL handoff the caller passes the body row only,
%   permanently, for the remainder of that run (freeze record Sec. 8.2).
%
%   SOLVER. The frozen Task 3 filter CBF_QP_FILTER solves the single-row problem
%   through an exact scalar dual, a construction that is specific to one halfspace
%   and does not extend to two. quadprog is used here instead, with the same
%   tolerances the frozen MPC path already uses in MPC_STEP, so the two Task 4
%   QPs are solved to consistent accuracy. This is an implementation choice, not
%   a design parameter: with a single row the two solvers agree to solver
%   tolerance, which SMOKE_TASK4 check S2 verifies against CBF_QP_FILTER directly.
%
%   FEASIBILITY. Each row's exact individual feasibility margin over the
%   componentwise box uses the exact support of a linear functional,
%       min_u A_i u = -u_max * ||A_i||_1,
%   so the row is individually feasible iff  b_i + u_max*||A_i||_1 >= 0.
%   No Cauchy-Schwarz relaxation is used anywhere. Individual feasibility of
%   every row is necessary but NOT sufficient for joint feasibility, which is
%   decided by the QP itself.
%
%   info fields:
%     feasible        logical, joint feasibility
%     feas_margin     per-row exact individual margins  b_i + u_max*||A_i||_1
%     joint_margin    max over the box of min_i (b_i - A_i u), >= 0 iff feasible
%     row_active      per-row, constraint tight at the solution
%     lambda          per-row multipliers from the QP
%     dev_inf         ||u_safe - u_nom||_inf
%     active          dev_inf > p.cbf.act_thresh
%     exitflag        quadprog exit flag
%     names           row names, in the order supplied
%     status           1 solved, 0 unconstrained-optimal, -1 infeasible

    umax = p.chaser.u_max;
    nR   = numel(rows);
    A    = reshape([rows.A], 3, nR).';        % nR x 3
    b    = [rows.b].';                        % nR x 1

    lb = -umax*ones(3,1);
    ub =  umax*ones(3,1);

    % --- exact per-row individual feasibility over the box ------------------
    feas_margin = zeros(1, nR);
    for i = 1:nR
        feas_margin(i) = b(i) + umax*norm(A(i,:), 1);
    end

    info.names       = {rows.name};
    info.feas_margin = feas_margin;

    % --- joint feasibility margin: max t s.t. A u + t <= b, u in box --------
    % Solved as an LP so that infeasibility is diagnosed with a signed margin
    % rather than only a flag. t* >= 0 iff the row set is jointly satisfiable.
    lpOpt = optimoptions('linprog', 'Display', 'none', 'Algorithm', 'dual-simplex');
    [~, fv, lpFlag] = linprog([0;0;0;-1], [A, ones(nR,1)], b, [], [], ...
                              [lb; -inf], [ub; inf], lpOpt);
    if lpFlag == 1
        info.joint_margin = -fv;
    else
        info.joint_margin = NaN;
    end

    % --- unconstrained (box-only) optimum: is any row even active? ----------
    u0 = min(max(u_nom, lb), ub);
    if all(A*u0 - b <= 0)
        u_safe = u0;
        info.feasible   = true;
        info.row_active = false(1, nR);
        info.lambda     = zeros(1, nR);
        info.exitflag   = 0;
        info.status     = 0;
        info = finish_info(info, u_safe, u_nom, A, b, p);
        return
    end

    % --- constrained solve ---------------------------------------------------
    qpOpt = optimoptions('quadprog', 'Display', 'none', ...
        'OptimalityTolerance', 1e-12, 'ConstraintTolerance', 1e-12, ...
        'StepTolerance', 1e-14);
    [u, ~, exitflag, ~, lam] = quadprog(eye(3), -u_nom(:), A, b, [], [], ...
                                        lb, ub, u0, qpOpt);

    info.exitflag = exitflag;
    if isempty(u) || exitflag <= 0
        u_safe = u0;                              % best effort, reported as failed
        info.feasible   = false;
        info.row_active = false(1, nR);
        info.lambda     = zeros(1, nR);
        info.status     = -1;
        info = finish_info(info, u_safe, u_nom, A, b, p);
        return
    end

    u_safe = u;
    info.feasible = true;
    info.status   = 1;
    if isfield(lam, 'ineqlin') && numel(lam.ineqlin) == nR
        info.lambda = lam.ineqlin(:).';
    else
        info.lambda = nan(1, nR);
    end
    info.row_active = abs(A*u_safe - b).' <= 1e-9 * max(1, max(abs(b)));
    info = finish_info(info, u_safe, u_nom, A, b, p);
end

% ----- local functions -----
function info = finish_info(info, u_safe, u_nom, A, b, p)
    info.dev_inf  = norm(u_safe - u_nom, inf);
    info.active   = info.dev_inf > p.cbf.act_thresh;
    info.residual = (b - A*u_safe).';       % >= 0 means the row is satisfied
end

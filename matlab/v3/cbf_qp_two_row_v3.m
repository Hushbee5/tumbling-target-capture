function [u_safe, info] = cbf_qp_two_row_v3(rows, u_nom, p)
% CBF_QP_TWO_ROW_V3  V3 (DEVELOPMENT): two-row HOCBF-QP with an exact solver, an explicit
%   fallback hierarchy and a full per-call record. Same interface as the frozen
%   CBF_QP_TWO_ROW; the frozen function is not modified.
%
%   PROBLEM (identical to the frozen filter):
%       min 0.5*||u - u_nom||^2   s.t.  A_i u <= b_i (rows: body, and cap before the handoff),
%                                       -u_max <= u_j <= u_max.
%
%   SOLVER. QP_SMALL_EXACT (active-set enumeration with a recomputed KKT certificate) replaces
%   quadprog: with n = 3 and at most 8 constraints the enumeration is exact and has no
%   iteration limit, which removes the frozen failure mode "exit flag 0 / -2 on a problem that
%   the LP shows to be feasible" (QP_CAPTURE_REPORT_r2). The LP joint margin of the frozen
%   filter is kept as an independent feasibility check of the HARD problem.
%
%   FALLBACK HIERARCHY. The hard problem is never reported as solved when it was not.
%     level 0  hard problem solved (all rows + box)                      info.hard_solved = true
%     level 1  hard problem infeasible: the CAP row is softened,
%                  min 0.5||u-u_nom||^2 + 0.5*w_s*s^2,  A_cap u <= b_cap + s,
%              the BODY row and the box stay hard                         info.hard_solved = false
%     level 2  body row + box infeasible: best-effort u = argmin_box A_body u
%              (u_j = -u_max*sign(A_body_j)), i.e. the largest admissible push in the
%              barrier-increasing direction; no constraint is claimed      info.hard_solved = false
%   The caller decides what a level-1/2 event means for the run (V3 protocol: counted and
%   reported, never pooled with level 0). w_s is fixed (1e6) so the slack is used only when
%   needed; its value does not change level-0 solutions.
%
%   info fields (in addition to those of the frozen filter where meaningful):
%     level, hard_solved, slack, kkt, n_candidates, A, b, u_nom, solver = 'exact-enum'

    umax = p.chaser.u_max;
    nR   = numel(rows);
    A    = reshape([rows.A], 3, nR).';
    b    = [rows.b].';
    lb   = -umax*ones(3,1);  ub = umax*ones(3,1);

    info.names = {rows.name};
    info.A = A;  info.b = b;  info.u_nom = u_nom(:);
    info.solver = 'exact-enum';
    info.feas_margin = (b + umax*sum(abs(A), 2)).';

    % --- independent LP joint margin of the HARD problem (as in the frozen filter) ---------------
    lpOpt = optimoptions('linprog', 'Display', 'none', 'Algorithm', 'dual-simplex');
    [~, fv, lpFlag] = linprog([0;0;0;-1], [A, ones(nR,1)], b, [], [], [lb; -inf], [ub; inf], lpOpt);
    if lpFlag == 1, info.joint_margin = -fv; else, info.joint_margin = NaN; end

    Gbox = [eye(3); -eye(3)];  hbox = [ub; -lb];

    % --- level 0: hard problem ----------------------------------------------------------------
    [u, s0] = qp_small_exact(eye(3), -u_nom(:), [A; Gbox], [b; hbox]);
    info.n_candidates = s0.n_candidates;
    if s0.status == 1
        u_safe = u;
        info.level = 0;  info.hard_solved = true;  info.slack = 0;
        info.kkt = s0.kkt;
        info.lambda = s0.lam(1:nR).';
        info.row_active = (abs(A*u_safe - b) <= 1e-9*max(1, max(abs(b)))).';
        info = finish(info, u_safe, u_nom, A, b, p, 1);
        return
    end

    % --- level 1: soften the capture row only --------------------------------------------------
    iCap = find(strcmp(info.names, 'cap'));
    iBody = find(strcmp(info.names, 'body'));
    if ~isempty(iCap)
        w_s = 1e6;
        H = blkdiag(eye(3), w_s);
        f = [-u_nom(:); 0];
        G = [A(iBody, :), zeros(numel(iBody), 1);
             A(iCap, :),  -1;
             Gbox,        zeros(6, 1)];
        hh = [b(iBody); b(iCap); hbox];
        [z, s1] = qp_small_exact(H, f, G, hh);
        if s1.status == 1
            u_safe = z(1:3);
            info.level = 1;  info.hard_solved = false;  info.slack = max(z(4), 0);
            info.kkt = s1.kkt;
            info.lambda = nan(1, nR);
            info.row_active = (abs(A*u_safe - b) <= 1e-9*max(1, max(abs(b)))).';
            info = finish(info, u_safe, u_nom, A, b, p, -1);
            return
        end
    end

    % --- level 2: body row infeasible over the box: best-effort push ---------------------------
    a = A(iBody, :);
    u_safe = -umax * sign(a(:));
    info.level = 2;  info.hard_solved = false;  info.slack = NaN;
    info.kkt = struct('primal_viol', NaN, 'min_lam', NaN, 'stationarity', NaN, 'complementarity', NaN);
    info.lambda = nan(1, nR);
    info.row_active = false(1, nR);
    info = finish(info, u_safe, u_nom, A, b, p, -2);
end

function info = finish(info, u_safe, u_nom, A, b, p, status)
    info.status   = status;                     % 1 hard solved, -1 cap softened, -2 best effort
    info.feasible = info.hard_solved;           % frozen field meaning: the HARD problem was solved
    info.exitflag = status;
    info.dev_inf  = norm(u_safe - u_nom(:), inf);
    info.active   = info.dev_inf > p.cbf.act_thresh;
    info.residual = (b - A*u_safe).';           % >= 0 means the row is satisfied
    info.box_ok   = all(abs(u_safe) <= p.chaser.u_max*(1 + 1e-12));
end

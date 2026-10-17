function [u_safe, info] = cbf_qp_filter(x, u_nom, p)
% CBF_QP_FILTER  High-order CBF safety filter for the keep-out sphere.
%   [u_safe, info] = cbf_qp_filter(x, u_nom, p) minimally modifies the nominal
%   acceleration command so that the high-order control barrier function
%   condition holds at this instant, subject to the per-axis actuator box.
%
%   Problem solved (notes/task2_spec_hocbf_qp.md Sec. 3):
%       min   0.5*(u - u_nom)' * W * (u - u_nom)
%       s.t.  A_cbf * u <= b_cbf
%             -u_max <= u_i <= u_max
%   with
%       A_cbf = -Lgh = -2*r'
%       b_cbf =  Lf2h + (k1+k2)*h_dot + k1*k2*h - delta
%   which is the HOCBF condition psi2 >= delta written as a linear inequality:
%       psi2 = h_ddot + (k1+k2)*h_dot + k1*k2*h,   h_ddot = Lf2h + Lgh*u.
%
%   Solver (Sec. 3.1): this exact projection solver is the BASELINE solver. It
%   was written while the Optimization Toolbox was unavailable; the toolbox has
%   since been installed (quadprog 25.2) and is used only as an independent
%   cross-check in validation (Task 2 V19a-f), not as the production path.
%
%   VALIDITY LIMIT: the dual construction below assumes W = I. For a general
%   weighting the stationarity condition gives u = u_nom - lam*W^{-1}*A_cbf',
%   not u_nom - lam*A_cbf', so the solver would be wrong. An assertion enforces
%   W = I rather than silently reading it.
%
%   With W = I the problem is the Euclidean projection of u_nom onto one halfspace
%   intersected with a box. It is solved exactly through the scalar dual:
%       u(lam) = clip(u_nom - lam*A_cbf', -u_max, u_max),  lam >= 0
%       g(lam) = A_cbf*u(lam) - b_cbf   is continuous and non-increasing,
%   so u = u(0) when g(0) <= 0, otherwise the unique root of g is bracketed and
%   bisected. The limit g(inf) = -u_max*||A_cbf||_1 - b_cbf reproduces the
%   analytic infeasibility criterion of Sec. 4.1 exactly.
%
%   info fields:
%     h, d_safe, hdot, psi1, psi2 barrier quantities (d_safe = keep-out clearance, at the returned command
%                                 NEVER the distance to the capture point)
%     A_cbf, b_cbf                constraint row actually used
%     feasible                    logical
%     feas_margin                 b_cbf + u_max*||A_cbf||_1  (>= 0 iff feasible)
%     active                      ||u_safe - u_nom||_inf > p.cbf.act_thresh
%     dev_inf                     ||u_safe - u_nom||_inf
%     lambda                      dual variable of the safety row
%     status                       1 solved, 0 unconstrained-optimal, -1 infeasible
%
%   The command is NOT clipped after the fact: the box is part of the QP.

    r = x(1:3);
    umax = p.chaser.u_max;

    % The exact dual solver below is valid only for an identity weighting.
    assert(norm(p.cbf.W - eye(3), 'fro') <= 1e-12, 'cbf_qp_filter:W', ...
        ['This solver implements the Euclidean projection and is valid only for ' ...
         'W = I (got ||W - I||_F = %.3e). Use a general weighted projection, ' ...
         'or quadprog, if a non-identity weighting is ever required.'], ...
        norm(p.cbf.W - eye(3), 'fro'));

    [h, d_safe, hdot, Lf2h, Lgh] = safety_function(x, p, 'cw');

    k1 = p.cbf.k1;
    k2 = p.cbf.k2;
    psi1 = hdot + k1*h;

    A_cbf = -Lgh;                                      % 1x3
    b_cbf = Lf2h + (k1 + k2)*hdot + k1*k2*h - p.cbf.delta;

    a = A_cbf(:);                                      % 3x1 column form
    lb = -umax*ones(3,1);
    ub =  umax*ones(3,1);

    % --- feasibility (exact, Sec. 4.1) -------------------------------------
    % min over the box of A_cbf*u equals -u_max*||A_cbf||_1
    feas_margin = b_cbf + umax*norm(a, 1);
    feasible    = feas_margin >= 0;

    if ~feasible
        u_safe = clip_box(u_nom, lb, ub);              % best effort, reported as failed
        info = pack(h, d_safe, hdot, psi1, NaN, A_cbf, b_cbf, false, feas_margin, ...
                    u_safe, u_nom, 0, -1, p);
        return
    end

    % --- lambda = 0 : the safety row is inactive ---------------------------
    u0 = clip_box(u_nom, lb, ub);
    if a.'*u0 - b_cbf <= 0
        info = pack(h, d_safe, hdot, psi1, [], A_cbf, b_cbf, true, feas_margin, ...
                    u0, u_nom, 0, 0, p);
        info.psi2 = psi2_of(u0, Lf2h, Lgh, hdot, h, k1, k2);
        u_safe = u0;
        return
    end

    % --- bracket and bisect the monotone dual -------------------------------
    nz = abs(a) > 0;
    lam_hi = max( (abs(u_nom(nz)) + umax) ./ abs(a(nz)) );
    if isempty(lam_hi) || ~isfinite(lam_hi), lam_hi = 1; end
    lam_hi = max(lam_hi, eps);
    while g_of(lam_hi, u_nom, a, b_cbf, lb, ub) > 0     % guarantee a bracket
        lam_hi = 2*lam_hi;
    end

    lam_lo = 0;
    for it = 1:200                                      % fixed count -> deterministic
        lam_mid = 0.5*(lam_lo + lam_hi);
        if g_of(lam_mid, u_nom, a, b_cbf, lb, ub) > 0
            lam_lo = lam_mid;
        else
            lam_hi = lam_mid;
        end
    end
    lam = lam_hi;                                       % endpoint with g <= 0: feasible
    u_safe = clip_box(u_nom - lam*a, lb, ub);

    info = pack(h, d_safe, hdot, psi1, [], A_cbf, b_cbf, true, feas_margin, ...
                u_safe, u_nom, lam, 1, p);
    info.psi2 = psi2_of(u_safe, Lf2h, Lgh, hdot, h, k1, k2);
end

% ----- local functions -----
function u = clip_box(u, lb, ub)
    u = min(max(u, lb), ub);
end

function g = g_of(lam, u_nom, a, b_cbf, lb, ub)
    g = a.' * clip_box(u_nom - lam*a, lb, ub) - b_cbf;
end

function ps2 = psi2_of(u, Lf2h, Lgh, hdot, h, k1, k2)
    ps2 = (Lf2h + Lgh*u) + (k1 + k2)*hdot + k1*k2*h;
end

function info = pack(h, d_safe, hdot, psi1, psi2, A_cbf, b_cbf, feasible, feas_margin, ...
                     u_safe, u_nom, lam, status, p)
    info.h           = h;
    info.d_safe      = d_safe;
    info.hdot        = hdot;
    info.psi1        = psi1;
    info.psi2        = psi2;
    info.A_cbf       = A_cbf;
    info.b_cbf       = b_cbf;
    info.feasible    = feasible;
    info.feas_margin = feas_margin;
    info.lambda      = lam;
    info.status      = status;
    info.dev_inf     = norm(u_safe - u_nom, inf);
    info.active      = info.dev_inf > p.cbf.act_thresh;
end

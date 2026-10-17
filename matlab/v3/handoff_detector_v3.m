function [ev, d] = handoff_detector_v3(cb, nu, x, handoff_done, p)
% HANDOFF_DETECTOR_V3  V3 (DEVELOPMENT): handoff on the reachable boundary of the tightened
%   commitment row, gated by an ACTUATOR-AUTHORITY condition on the remaining capture-point
%   uncertainty. Written before any V3 run; the frozen and V2 detectors are not modified.
%
%   WHAT THE RELEASED ROW PROTECTED AGAINST. The capture row is tightened by eta*nu, the
%   worst-case effect of the parameter error ||theta - theta_hat|| <= nu on the capture-point
%   acceleration (manuscript eqs. 21-23). Releasing it is justified only when that remaining
%   uncertainty no longer matters for the next phase, in which the servicer must FOLLOW the
%   capture point. The worst-case acceleration needed to co-move with it is
%       a_req = || a_cp_hat - a_drift(x) ||  +  nu * sigma_a,
%       sigma_a = || [p_b]x * diag(Y_omega(w)) ||_2 = || d a_cp / d theta ||_2 ,
%   (R is orthogonal, so the LVLH rotation drops out of the norm).
%
%   V3 RULE (gamma_c = 1 - beta, beta = p.capture.beta = 0.3, the FROZEN fraction of u_max that
%   the reference generator already reserves for braking; no new tuned parameter):
%     GUARD_BREACH  handoff_done == false AND rho < s_cap                         (unchanged)
%     NORMAL        handoff_done == false AND 0 <= h_cap <= h_star + eps_h AND rho_dot <= 0
%                   AND a_req <= gamma_c * u_max
%     NONE          otherwise
%   The first two NORMAL conjuncts are the V2 reachable-boundary rule. The third keeps the row
%   enforced while the uncertainty it carries exceeds the following authority. With
%   gamma_c = inf the rule is IDENTICAL to HANDOFF_DETECTOR_V2 (test T4).
%
%   d (diagnostics at this sample): h_star, a_req, sigma_a, a_follow, gate (logical), gamma_c.

    k12 = p.t4.kappa1 * p.t4.kappa2;
    h_star = cb.eta * nu / k12;
    pb = p.target.p_cp_body(:);
    Sb = [0 -pb(3) pb(2); pb(3) 0 -pb(1); -pb(2) pb(1) 0];
    sigma_a = norm(Sb * diag(cb.Y_omega));
    [~, aDrift] = rel_translational_dynamics(x, zeros(3,1), p, 'cw');
    a_follow = norm(cb.a_cp_hat - aDrift);
    a_req = a_follow + nu * sigma_a;
    if isfield(p, 'v3') && isfield(p.v3, 'gamma_c')
        gamma_c = p.v3.gamma_c;
    else
        gamma_c = 1 - p.capture.beta;
    end
    gate = a_req <= gamma_c * p.chaser.u_max;
    d = struct('h_star', h_star, 'a_req', a_req, 'sigma_a', sigma_a, 'a_follow', a_follow, ...
               'gate', gate, 'gamma_c', gamma_c);
    if handoff_done
        ev = 'NONE';
        return
    end
    if cb.rho < p.t4.s_cap
        ev = 'GUARD_BREACH';
    elseif cb.h <= h_star + p.t4.eps_h && cb.rho_dot <= 0 && gate
        ev = 'NORMAL';
    else
        ev = 'NONE';
    end
end

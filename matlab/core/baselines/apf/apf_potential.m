function [U, gradU, parts] = apf_potential(r, p_cp, gains, r_safe)
% APF_POTENTIAL  Candidate-A artificial potential and its analytic gradient.
%   [U, gradU, parts] = apf_potential(r, p_cp, gains, r_safe) evaluates protocol
%   Sec. 3.1 at the chaser position r (LVLH, metres) for the capture point p_cp
%   at the same instant:
%
%       e      = r - p_cp_preview(t)
%       h      = ||r||^2 - r_safe^2
%       P      = I ,  K_a = k_a*I ,  K_d = k_d*I
%
%       U      = 0.5*||e||^2 * [ k_a + k_r*exp(-beta*h) ]
%       grad U = k_a*e + k_r*exp(-beta*h) * [ e - beta*||e||^2 * r ]
%
%   PROVENANCE. A direct specialisation of Cao, Qiao and Xu, Acta Astronautica
%   143:133-146, 2018, Eq. (9) with N = I and r_obs = 0; the goal-vanishing
%   factor matches Li et al., ISA Transactions 95:173-184, 2019 and Zhao and
%   Zhang, Aerospace Science and Technology 114:106739, 2021, Eqs. (9)-(10).
%
%   RECORDED PROPERTY, NOT A DEFECT. The repulsion is a target-COM-centred
%   exponential in ||r||^2 in which r_safe does not appear: it is absorbed into
%   k_r. r_safe enters only the SAFETY EVALUATION. This is a property of the
%   published Gaussian-APF family, and the adaptation does not repair it.
%
%   EXACT AT THE GOAL. With e exactly zero, ||e||^2 is exactly 0, so U is
%   exactly 0 and grad U is exactly [0;0;0] - by the formula, with no special
%   case. V1c-A tests that property rather than a branch written to satisfy it.
%
%   NO CONVERGENCE CLAIM. U(r,t) is explicitly time-varying through p_cp(t), the
%   plant is second order and the command is box-saturated. No closed-loop
%   convergence theorem is derived or claimed anywhere.
%
%   The caller supplies p_cp; this function never chooses between preview and
%   truth geometry. The APF control law passes the PREVIEW capture point
%   (protocol Sec. 7); truth geometry is reserved for evaluation metrics.
%
%   parts (diagnostics): e, h, G = k_r*exp(-beta*h), e2 = ||e||^2, attractive
%   and repulsive gradient contributions.

    r    = r(:);
    p_cp = p_cp(:);
    assert(numel(r) == 3 && numel(p_cp) == 3, 'apf_potential:shape', ...
        'r and p_cp must both be 3-vectors.');

    k_a  = gains.k_a;
    k_r  = gains.k_r;
    beta = gains.beta;

    e  = r - p_cp;
    e2 = e.' * e;                       % ||e||^2 ; exactly 0 at the goal
    h  = (r.' * r) - r_safe^2;
    G  = k_r * exp(-beta * h);          % repulsive amplitude, > 0 everywhere

    assert(isfinite(G), 'apf_potential:overflow', ...
        ['k_r*exp(-beta*h) overflowed at ||r|| = %g m (h = %g m^2, beta = %g, ' ...
         'k_r = %g).'], norm(r), h, beta, k_r);

    U     = 0.5 * e2 * (k_a + G);
    gradU = k_a*e + G * ( e - beta*e2*r );

    if nargout > 2
        parts.e           = e;
        parts.e2          = e2;
        parts.h           = h;
        parts.G           = G;
        parts.grad_attract = k_a * e;
        parts.grad_repel   = G * ( e - beta*e2*r );
        parts.note = ['G = k_r*exp(-beta*h) is the target-COM-centred ' ...
            'repulsive amplitude; r_safe is absorbed into k_r and enters only ' ...
            'the safety evaluation.'];
    end
end

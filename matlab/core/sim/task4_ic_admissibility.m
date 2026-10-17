function ic = task4_ic_admissibility(x0, q0, w0, theta_hat0, t0, p)
% TASK4_IC_ADMISSIBILITY  Initial HOCBF admissibility gate for a production run.
%   ic = task4_ic_admissibility(x0, q0, w0, theta_hat0, t0, p) evaluates, at the
%   production entry point and BEFORE any control step is taken:
%
%       BODY    h_body(0)   and  psi1_body(0) = hdot_body(0) + k1 * h_body(0)
%       CAPTURE h_cap(0)    and  psi1_cap(0)  = hdot_cap(0)  + kappa1 * h_cap(0)
%
%   WHY THIS GATE EXISTS. The HOCBF construction certifies forward invariance of
%   C_0 intersect C_1 = {h >= 0} intersect {psi1 >= 0}. Started outside that set,
%   the enforced row carries no invariance claim, so whatever the run then does
%   is evidence about neither safety nor the detector. Such a run must never be
%   counted as a safety-validation success OR failure.
%
%   THIS IS A PRE-RUN VALIDATION-ELIGIBILITY GATE, NOT A D9 OUTCOME. D9 remains
%   frozen with exactly three outcomes - NORMAL, GUARD_BREACH, NO_EVENT. A run
%   refused here has NONE of them, because the detector never ran; the run is
%   recorded as eligibility = 'INELIGIBLE_IC' with d9_evaluated = false and the
%   marker event = 'NOT_EVALUATED'. Nothing in this file adds a fourth D9
%   outcome and nothing here reopens D9.
%
%   The capture row is treated as active at entry because handoff_done is false
%   there by construction; its admissibility is checked and recorded even if the
%   D9 detector happens to fire at the first control step.
%
%   These are the SAME frozen quantities the run itself uses, evaluated through
%   the frozen Task 3 SAFETY_FUNCTION and the Task 4 CAPTURE_BARRIER. This is a
%   gate, not an independent mathematical verification of the barrier algebra;
%   that is VERIFY_CAPTURE_BARRIER.
%
%   Fields:
%     h_body, psi1_body, h_cap, psi1_cap    the four recorded quantities
%     cap_active_initially                  logical, true at a production entry
%     admissible                            logical, all applicable tests pass
%     reasons                               cellstr, one entry per failed test
%     tol                                   the >= 0 comparison tolerance used

    % Comparison tolerance. This is a NUMERICAL sign test on quantities of order
    % 1e-2 to 1e2, not a design margin and not a safety margin: it exists only so
    % that a value that is zero up to round-off is not read as negative. No
    % control law, threshold or reported result depends on it.
    ic.tol = 1e-12;

    [hb, ~, hdb] = safety_function(x0, p, 'cw');
    ic.h_body    = hb;
    ic.psi1_body = hdb + p.cbf.k1 * hb;

    cb = capture_barrier(x0, q0, w0, theta_hat0, t0, p);
    ic.h_cap    = cb.h;
    ic.psi1_cap = cb.psi1;
    ic.rho      = cb.rho;
    ic.rho_dot  = cb.rho_dot;

    ic.cap_active_initially = true;   % handoff_done is false at a production entry

    reasons = {};
    if ~(ic.h_body >= -ic.tol)
        reasons{end+1} = sprintf('h_body(0) = %.6e < 0 (chaser starts inside the keep-out sphere)', ic.h_body);
    end
    if ~(ic.psi1_body >= -ic.tol)
        reasons{end+1} = sprintf('psi1_body(0) = %.6e < 0 (outside the body HOCBF set C_1)', ic.psi1_body);
    end
    if ic.cap_active_initially
        if ~(ic.h_cap >= -ic.tol)
            reasons{end+1} = sprintf('h_cap(0) = %.6e < 0 (chaser starts inside the commitment sphere)', ic.h_cap);
        end
        if ~(ic.psi1_cap >= -ic.tol)
            reasons{end+1} = sprintf('psi1_cap(0) = %.6e < 0 (outside the capture HOCBF set C_1)', ic.psi1_cap);
        end
    end

    ic.reasons    = reasons;
    ic.admissible = isempty(reasons);
end

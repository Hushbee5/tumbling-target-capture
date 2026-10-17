function est = cl_estimator_init(p)
% CL_ESTIMATOR_INIT  Initial state of the frozen T4-D4 concurrent-learning estimator.
%   est = cl_estimator_init(p) returns the estimator state expected by
%   CL_ESTIMATOR_STEP. All initial values are frozen:
%
%       theta_hat(0) = 0            (freeze record Sec. 1.2)
%       E(0)         = 0            (integral of lambda_min from 0)
%       empty history stack         (no record exists before t = Tw)
%
%   With an empty stack Lambda = 0 and lambda_min = 0, so nu_sp(t) = nu_0 for
%   t < Tw. That is the correct causal behaviour, not a special case.

    est.theta_hat = p.t4.theta_hat0(:);
    est.E         = 0;
    est.sel       = [];          % indices of the records currently in the stack
    est.next      = 1;           % next record not yet considered for admission
    est.tol       = 1e-9;        % grid comparison tolerance for Te <= t_k
end

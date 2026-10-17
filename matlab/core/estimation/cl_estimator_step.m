function [est, val] = cl_estimator_step(est, t_k, rec, p)
% CL_ESTIMATOR_STEP  One control-step advance of the frozen T4-D4 estimator.
%   [est, val] = cl_estimator_step(est, t_k, rec, p)
%
%   Call CL_ESTIMATOR_INIT once, then call this once per control step, in order.
%
%   CANONICAL CAUSAL CONVENTION (freeze record Sec. 1.1), implemented literally:
%
%     1. admit every record with  Te <= t_k   (a record may never be used before
%        its own window is complete);
%     2. READ OUT the values AT t_k:
%            val.theta_hat = theta_hat(t_k)   after all updates over [0, t_k)
%            val.nu        = nu_0 * exp(-gamma * E(t_k))
%            E(t_k)        = sum_{i=1}^{k-1} lambda_min(S(t_i)) * Ts
%     3. THEN advance across [t_k, t_k + Ts):
%            E          += lambda_min * Ts
%            theta_hat  += Ts * gamma * (S - Lambda .* theta_hat)
%
%   The read-before-update ordering in steps 2-3 is what makes E(t_k) carry
%   exactly k-1 terms. Reversing it reproduces the superseded non-causal values.
%
%   Because Y_omega is diagonal at every instant, Ybar_j is diagonal, so
%       Lambda = sum_j Ybar_j' Ybar_j  = diag( sum_j Ybar_j.^2 )
%   is diagonal and the componentwise form below is exact, not an approximation.
%
%   NO PROJECTION is applied. Freeze record Sec. 1 / D4-B established
%   theta-invariance of this estimator, so theta_hat never leaves the segment
%   [0, theta_i) and a projection operator is not required. Do not add one.
%
%   val fields: theta_hat, nu, lambda_min, E, n_stack

    Ts = p.ctrl.Ts;

    % --- 1. causal admission ------------------------------------------------
    while est.next <= rec.n && rec.Te(est.next) <= t_k + est.tol
        est = admit(est, est.next, rec, p.t4.M);
        est.next = est.next + 1;
    end

    if isempty(est.sel)
        Lam = zeros(3,1);
        S   = zeros(3,1);
    else
        Lam = sum(rec.Y(:, est.sel).^2, 2);
        S   = sum(rec.Y(:, est.sel) .* rec.D(:, est.sel), 2);
    end
    lmin = min(Lam);

    % --- 2. read out the values AT t_k -------------------------------------
    val.theta_hat  = est.theta_hat;
    val.nu         = p.t4.nu0 * exp(-p.t4.gamma * est.E);
    val.lambda_min = lmin;
    val.E          = est.E;
    val.n_stack    = numel(est.sel);

    % --- 3. advance across [t_k, t_k + Ts) ---------------------------------
    est.E         = est.E + lmin * Ts;
    est.theta_hat = est.theta_hat + Ts * p.t4.gamma * (S - Lam .* est.theta_hat);
end

% ----- local functions -----
function est = admit(est, j, rec, M)
% History-stack admission: fill to depth M, then swap in only when the swap
% strictly increases the minimum eigenvalue of Lambda. Lambda is diagonal, so
% its minimum eigenvalue is min over the three diagonal entries.
    if numel(est.sel) < M
        est.sel(end+1) = j;
        return
    end
    cur  = min(sum(rec.Y(:, est.sel).^2, 2));
    best = cur;
    bi   = 0;
    for i = 1:M
        cand    = est.sel;
        cand(i) = j;
        v = min(sum(rec.Y(:, cand).^2, 2));
        if v > best
            best = v;
            bi   = i;
        end
    end
    if bi > 0
        est.sel(bi) = j;
    end
end

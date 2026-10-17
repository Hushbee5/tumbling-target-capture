function [thH, nuH] = v3_theta_hat_history(pT4, Tsim, n_sub)
% V3_THETA_HAT_HISTORY  The online estimate theta_hat(t_k) and bound nu(t_k) at every control sample
%   k = 1..K, computed exactly as SIMULATE_TASK4 computes them in the loop:
%       fine truth history  ->  control-grid (t, w)  ->  rec = cl_records(tT, wT, p)
%       est = cl_estimator_init(p);  [est, ev] = cl_estimator_step(est, t(k), rec, p)
%   The estimator reads only the target's angular-velocity history, so the result does not depend on
%   any servicer trajectory and can be handed to the equal-information baselines
%   (SIMULATE_BASELINE_V3). V3 test T8 checks equality with the proposed run's out.theta_hat.

    Ts = pT4.ctrl.Ts;
    K  = round(Tsim / Ts);
    pt = pT4;  pt.sim.dt = Ts / n_sub;  pt.sim.T_final = Tsim;
    [tF, ~, wF] = target_tumbling_model(pt);
    ctrlIdx = 1 : n_sub : numel(tF);
    tT = tF(ctrlIdx);  wT = wF(:, ctrlIdx);
    assert(numel(tT) == K + 1, 'v3_theta_hat_history:grid', 'grid mismatch');
    rec = cl_records(tT, wT, pT4);
    est = cl_estimator_init(pT4);
    t = (0:K) * Ts;
    thH = nan(3, K);  nuH = nan(1, K);
    for k = 1:K
        [est, ev] = cl_estimator_step(est, t(k), rec, pT4);
        thH(:, k) = ev.theta_hat;  nuH(k) = ev.nu;
    end
end

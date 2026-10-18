function make_estimator_reference(out_file)
% MAKE_ESTIMATOR_REFERENCE  Records the inertia-ratio estimator of the MATLAB code for the parity test of the Python
%   port (python/gnc/estimator.py).
%   make_estimator_reference('tests/data/estimator_reference.json'), from the repository root.
%   The target rate history is generated as in simulate_task4 (fine grid Ts/10, subsampled to the control grid) over
%   800 s; the estimator is then advanced once per control step. Outputs are stored at every 10th step.

    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    addpath(genpath(fullfile(root, 'matlab', 'core')));
    p = params_task4(params());
    Ts = p.ctrl.Ts;  T = 800;  n_sub = 10;  K = round(T / Ts);

    pt = p;  pt.sim.dt = Ts / n_sub;  pt.sim.T_final = T;
    [tF, ~, wF] = target_tumbling_model(pt);
    idx = 1:n_sub:numel(tF);
    tT = tF(idx);  wT = wF(:, idx);
    assert(numel(tT) == K + 1);

    rec = cl_records(tT, wT, p);
    est = cl_estimator_init(p);
    th = zeros(3, K);  nu = zeros(1, K);  lm = zeros(1, K);  ns = zeros(1, K);
    for k = 1:K
        [est, val] = cl_estimator_step(est, tT(k), rec, p);
        th(:, k) = val.theta_hat;  nu(k) = val.nu;  lm(k) = val.lambda_min;  ns(k) = val.n_stack;
    end
    keep = [1:10:K, K];

    R.Ts = Ts;  R.Tw = p.t4.Tw;  R.M = p.t4.M;  R.gamma = p.t4.gamma;  R.nu0 = p.t4.nu0;
    R.theta_true = p.t4.theta_true';
    R.t = tT;  R.w = wT';
    R.rec_resid = rec.resid;  R.n_records = rec.n;
    R.k = keep - 1;                                   % zero-based step index
    R.theta_hat = th(:, keep)';  R.nu = nu(keep);  R.lambda_min = lm(keep);  R.n_stack = ns(keep);

    fid = fopen(out_file, 'w');
    fwrite(fid, jsonencode(R), 'char');
    fclose(fid);
    fprintf('written %s; nu at the last step %.6g, theta_hat error %.3g\n', out_file, nu(K), ...
        norm(th(:, K) - p.t4.theta_true));
end

function make_gnc_reference(out_file)
% MAKE_GNC_REFERENCE  Records outputs of the MATLAB controller for the parity tests of the Python port (python/gnc).
%   make_gnc_reference('tests/data/gnc_reference.json'), from the repository root.
%   Contents:
%     params        the configuration values the Python port hard-codes
%     cw            discrete CW model at Ts (cw_matrices)
%     mpc           terminal weight P (dlqr) and summary values of the condensed Hessian (mpc_condensed)
%     filter_cases  300 random states and nominal commands through cbf_qp_filter
%     mpc_cases     20 random states and set points through mpc_step (quadprog)
%     loops         200 s closed loops, MPC -> filter -> exact ZOH CW plant, with and without the filter

    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    addpath(genpath(fullfile(root, 'matlab', 'core')));
    p = params();
    rng(20261018, 'twister');

    R.params = struct('n', p.orbit.n, 'r_safe', p.geom.r_safe, 'u_max', p.chaser.u_max, 'Ts', p.ctrl.Ts, ...
        'k1', p.cbf.k1, 'k2', p.cbf.k2, 'delta', p.cbf.delta, 'N', p.mpc.N, 'sigma_p', p.mpc.sigma_p, ...
        'sigma_v', p.mpc.sigma_v, 'rho', p.mpc.rho);

    [~, ~, Ad, Bd] = cw_matrices(p, p.ctrl.Ts);
    R.cw = struct('Ad', Ad, 'Bd', Bd);

    M = mpc_condensed(p, p.mpc.N);
    R.mpc = struct('P', M.P, 'H_diag', diag(M.H)', 'H_row1', M.H(1, :), 'H_fro', norm(M.H, 'fro'));

    nF = 300;
    F = repmat(struct('x', [], 'u_nom', [], 'u_safe', [], 'status', [], 'lambda', [], 'psi2', []), 1, nF);
    for i = 1:nF
        d = randn(3, 1);  d = d / norm(d);
        x = [d * (0.72 + 4 * rand); 0.1 * (2 * rand(3, 1) - 1)];
        u_nom = 0.012 * (2 * rand(3, 1) - 1);
        [u, info] = cbf_qp_filter(x, u_nom, p);
        F(i).x = x';  F(i).u_nom = u_nom';  F(i).u_safe = u';  F(i).status = info.status;
        F(i).lambda = info.lambda;  F(i).psi2 = info.psi2;
        if isempty(F(i).psi2) || isnan(F(i).psi2), F(i).psi2 = 'NaN'; end
    end
    R.filter_cases = F;

    nM = 20;
    C = repmat(struct('x', [], 'r_ref', [], 'U', [], 'exitflag', []), 1, nM);
    for i = 1:nM
        x = [10 * (2 * rand(3, 1) - 1); 0.05 * (2 * rand(3, 1) - 1)];
        r_ref = 5 * (2 * rand(3, 1) - 1);
        [~, minfo] = mpc_step(x, repmat(r_ref, 1, M.N + 1), zeros(3, M.N + 1), M, p);
        C(i).x = x';  C(i).r_ref = r_ref';  C(i).U = minfo.U';  C(i).exitflag = minfo.exitflag;
    end
    R.mpc_cases = C;

    x0 = [0; -10; 0; 0; 0; 0];  r_ref = [0; 3; 0];  T = 200;
    R.loops = [run_loop(p, M, x0, r_ref, T, true), run_loop(p, M, x0, r_ref, T, false)];

    fid = fopen(out_file, 'w');
    fwrite(fid, jsonencode(R), 'char');
    fclose(fid);
    fprintf('written %s\n', out_file);
end

function L = run_loop(p, M, x0, r_ref, T, use_filter)
    K = round(T / p.ctrl.Ts);
    X = zeros(6, K + 1);  X(:, 1) = x0;  U = zeros(3, K);
    Pref = repmat(r_ref, 1, M.N + 1);  Vref = zeros(3, M.N + 1);
    for k = 1:K
        u_mpc = mpc_step(X(:, k), Pref, Vref, M, p);
        if use_filter
            [u, info] = cbf_qp_filter(X(:, k), u_mpc, p);
            assert(info.feasible);
        else
            u = u_mpc;
        end
        U(:, k) = u;
        X(:, k + 1) = M.Ad * X(:, k) + M.Bd * u;
    end
    L = struct('use_filter', use_filter, 'x0', x0', 'r_ref', r_ref', 'T', T, 'X', X', 'U', U');
end

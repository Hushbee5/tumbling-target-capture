function res = v06_bookkeeping_indexing(p, V, run)
% V06_BOOKKEEPING_INDEXING  V6: MATLAB/physical indexing and array bookkeeping.
%
%   PASS  the MATLAB/physical mapping of Sec. 3.5 holds exactly
%             X(:, k+1)  stores physical state   x_k        for k = 0..K
%             U(:, k+1)  stores physical control u_k        for k = 0..K-1
%             X(:, k+2)  is produced by applying U(:, k+1) over [t_k, t_k + Ts)
%             t(k+1)     = k*Ts
%   PASS  size(X,2) == K+1 ; size(U,2) == K ; numel(t) == K+1
%   PASS  size(a_cp_ff_ctrl,2) == K
%   PASS  at Tsim_V = 5.0 : K_V == 50 , states 51 , controls 50 , interior 450
%   PASS  SYMBOLIC assertion for Tsim = 800 : K = 8000 , states 8001 ,
%         controls 8000 , interior 72000   (asserted FROM THE FORMULAS, NOT
%         EXECUTED - no 800 s run happens in the verification gate)
%   PASS  K == round(Tsim/Ts)
%
%   THE PRODUCTION CLAUSE IS TESTED, NOT ASSUMED. "X(:,k+2) is produced by
%   applying U(:,k+1)" is checked by INDEPENDENTLY re-integrating the interval
%   with ode45 under the same tolerances and comparing, at the first, a middle
%   and the last interval. A shape check alone would pass on an off-by-one that
%   applied the wrong column.

    Ts     = p.ctrl.Ts;
    K      = run.K;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    % ---- shapes -------------------------------------------------------------
    okShape = size(run.X, 2) == K+1 && size(run.u_applied, 2) == K ...
           && numel(run.t) == K+1;
    checks(end+1) = baseline_check('V6 array shapes: X is K+1, U is K, t is K+1', ...
        okShape, 'size(X,2) = %d, size(U,2) = %d, numel(t) = %d, K = %d', ...
        size(run.X, 2), size(run.u_applied, 2), numel(run.t), K);

    checks(end+1) = baseline_check('V6 size(a_cp_ff_ctrl,2) == K', ...
        size(run.a_cp_ff_ctrl, 2) == K, 'size = %s, K = %d', ...
        mat2str(size(run.a_cp_ff_ctrl)), K);

    % ---- time grid ----------------------------------------------------------
    tRef = (0:K) * Ts;
    eT   = max(abs(run.t - tRef));
    checks(end+1) = baseline_check('V6 t(k+1) == k*Ts', eT <= 1e-12, ...
        'max |t - k*Ts| = %.3e over %d samples', eT, numel(run.t));

    % ---- K == round(Tsim/Ts) ------------------------------------------------
    checks(end+1) = baseline_check('V6 K == round(Tsim/Ts)', ...
        K == round(run.Tsim / Ts), 'K = %d, round(%g/%g) = %d', ...
        K, run.Tsim, Ts, round(run.Tsim / Ts));

    % ---- the production clause, re-integrated independently ---------------
    odeOpt = odeset('RelTol', p.bl.ode_reltol, 'AbsTol', p.bl.ode_abstol);
    kTest  = unique([1, max(1, floor(K/2)), K]);
    worst  = 0;  worstTol = 0;
    okProd = true;
    for i = 1:numel(kTest)
        k    = kTest(i);
        tsub = linspace(run.t(k), run.t(k+1), p.bl.n_sub + 1);
        [~, Xs] = ode45(@(tt, xx) rel_translational_dynamics(xx, ...
                        run.u_applied(:, k), p, p.bl.plant_mode), ...
                        tsub, run.X(:, k), odeOpt);
        e   = norm(Xs(end, :).' - run.X(:, k+1), Inf);
        tol = 1e-12 * max(1, norm(run.X(:, k+1), Inf));
        if e > tol, okProd = false; end
        if e - tol > worst - worstTol, worst = e; worstTol = tol; end
    end
    checks(end+1) = baseline_check( ...
        'V6 X(:,k+2) is produced by applying U(:,k+1) over [t_k, t_k+Ts)', ...
        okProd, ['re-integrated intervals k = %s (zero-based %s); worst ' ...
        '|err|_inf = %.6e against tol = %.6e'], mat2str(kTest), ...
        mat2str(kTest-1), worst, worstTol);

    % ---- the verification horizon ------------------------------------------
    okV = (K == V.K_V) && (size(run.X, 2) == V.n_states_V) ...
       && (size(run.u_applied, 2) == V.K_V) ...
       && (numel(run.inter_t) == V.n_interior_V);
    checks(end+1) = baseline_check('V6 Tsim_V = 5.0 s gives 50 / 51 / 50 / 450', ...
        okV, 'K_V = %d, states = %d, controls = %d, interior = %d', ...
        K, size(run.X, 2), size(run.u_applied, 2), numel(run.inter_t));

    % ---- SYMBOLIC 800 s assertion, NOT EXECUTED ----------------------------
    K800  = round(800 / Ts);
    st800 = K800 + 1;
    ct800 = K800;
    in800 = (p.bl.n_sub - 1) * K800;
    ok800 = (K800 == 8000) && (st800 == 8001) && (ct800 == 8000) && (in800 == 72000);
    checks(end+1) = baseline_check( ...
        'V6 symbolic 800 s bookkeeping: 8000 / 8001 / 8000 / 72000 (NOT executed)', ...
        ok800, ['from the formulas at Ts = %g s: K = %d, states = %d, ' ...
        'controls = %d, interior = %d. No 800 s run is performed in the ' ...
        'verification gate.'], Ts, K800, st800, ct800, in800);

    res.name   = 'V6 - bookkeeping and indexing';
    res.checks = checks;
    res.pass   = all([checks.pass]);
end

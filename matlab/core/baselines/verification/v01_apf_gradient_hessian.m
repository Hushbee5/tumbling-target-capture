function res = v01_apf_gradient_hessian(p, V, tabs)
% V01_APF_GRADIENT_HESSIAN  V1: APF gradient and goal Hessian.
%   res = v01_apf_gradient_hessian(p, V, tabs)
%
%   V1a  GRADIENT vs INDEPENDENT CENTRAL FD
%        step   Delta = 1e-5 m
%        points VP1..VP4  x  t_V
%        PASS   || gradU_an - gradU_fd ||_inf  <=  1e-6*||gradU_an||_inf + 1e-14
%
%   V1c-A  EXACT GOAL TEST
%        PASS   U(e=0) == 0 exactly ;  gradU(e=0) == [0;0;0] exactly
%
%   V1c-B  GOAL-HESSIAN TEST
%        At each t in t_V, an INDEPENDENT central-difference Jacobian of the
%        ANALYTIC gradient at r = p_cp(t):
%            H_fd(:,i) = [ gradU(p_cp + dH*e_i) - gradU(p_cp - dH*e_i) ]/(2*dH)
%        frozen   dH = 1e-4 m
%        expected H_goal = k_a*(1+kappa)*I
%        PASS     || H_fd - H_goal ||_inf <= 1e-5 * max( 1e-12 , ||H_goal||_inf )
%
%   V1b IS WITHDRAWN by the protocol and is NOT run. The reason is recorded in
%   BASELINE_VERIFY_INPUTS and repeated in res.withdrawn: the frozen test points
%   sit where the repulsive term has underflowed to nothing and the potential is
%   locally the exactly quadratic attractive term, whose third derivative
%   vanishes, so a second-order truncation ratio is not a valid expectation.
%   The PASS rules above are authoritative and no numerical margin is claimed.
%
%   THE FINITE DIFFERENCE IS INDEPENDENT OF THE ANALYTIC GRADIENT: it is built
%   from U alone, evaluated through APF_POTENTIAL's first output, so an error
%   shared between U and grad U cannot cancel out of the comparison.
%
%   MATRIX INF-NORM. ||.||_inf on the 3x3 Hessian difference is MATLAB's
%   norm(.,Inf), the maximum absolute ROW SUM. That is at least the largest
%   single entry, so this is the stricter of the two common readings.

    gains  = V.gains;
    r_safe = p.geom.r_safe;
    dG     = V.fd.delta_grad;
    dH     = V.fd.delta_hessian;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    % ---- V1a ----------------------------------------------------------------
    % WORST-EVIDENCE SELECTION, initialised at -Inf.
    % The ordering criterion is unchanged - the reported pair is the one with the
    % largest (err - tol) margin - but the accumulator previously started at
    % worstAbs - worstTol = 0 - 0 = 0. Every passing pair has err - tol <= 0, so
    % on a fully passing data set the update never fired and the check reported
    % the initial placeholder 'worst error = 0 against tol = 0' at no point-time
    % pair at all. Starting the margin at -Inf guarantees that one of the 16 real
    % pairs is always recorded.
    %
    % THE PASS PREDICATE AND THE TOLERANCE FORMULA ARE UNCHANGED. This is a
    % reporting fix only: err <= tol still decides, with
    % tol = grad_rel_tol*||gradU_an||_inf + grad_abs_tol, and the FD step, the
    % test points and the test times are untouched.
    worstMargin = -Inf;
    worstAbs = NaN;  worstTol = NaN;  worstAt = '';
    okA = true;
    for ip = 1:size(V.VP, 2)
        r = V.VP(1:3, ip);
        for it = 1:numel(V.t_V)
            pcp = tabs.p_cp_preview(:, V.k_V(it) + 1);
            [~, gAn] = apf_potential(r, pcp, gains, r_safe);

            gFd = zeros(3, 1);
            for i = 1:3
                e = zeros(3, 1);  e(i) = dG;
                Up = apf_potential(r + e, pcp, gains, r_safe);
                Um = apf_potential(r - e, pcp, gains, r_safe);
                gFd(i) = (Up - Um) / (2*dG);
            end

            err = norm(gAn - gFd, Inf);
            tol = V.fd.grad_rel_tol * norm(gAn, Inf) + V.fd.grad_abs_tol;
            if err > tol, okA = false; end
            if err - tol > worstMargin
                worstMargin = err - tol;
                worstAbs = err;  worstTol = tol;
                worstAt  = sprintf('%s at t = %g s', V.VP_names{ip}, V.t_V(it));
            end
        end
    end
    checks(end+1) = baseline_check('V1a gradient vs independent central FD', okA, ...
        ['%d point-time pairs, Delta = %g m; worst |err| = %.6e against ' ...
         'tol = %.6e (margin %.6e) at %s'], size(V.VP, 2)*numel(V.t_V), dG, ...
        worstAbs, worstTol, worstMargin, worstAt);

    % ---- V1c-A --------------------------------------------------------------
    okU = true;  okG = true;
    for it = 1:numel(V.t_V)
        pcp = tabs.p_cp_preview(:, V.k_V(it) + 1);
        [U0, g0] = apf_potential(pcp, pcp, gains, r_safe);
        okU = okU && (U0 == 0);
        okG = okG && isequal(g0, [0; 0; 0]);
    end
    checks(end+1) = baseline_check('V1c-A exact goal: U(e=0) == 0', okU, ...
        'exact zero at all %d test times', numel(V.t_V));
    checks(end+1) = baseline_check('V1c-A exact goal: gradU(e=0) == [0;0;0]', okG, ...
        'exact zero vector at all %d test times', numel(V.t_V));

    % ---- V1c-B --------------------------------------------------------------
    Hgoal = gains.H_goal;
    tolH  = V.fd.hessian_rel_tol * max(1e-12, norm(Hgoal, Inf));
    worstH = 0;  worstHat = '';
    okB = true;
    for it = 1:numel(V.t_V)
        pcp = tabs.p_cp_preview(:, V.k_V(it) + 1);
        Hfd = zeros(3, 3);
        for i = 1:3
            e = zeros(3, 1);  e(i) = dH;
            [~, gp] = apf_potential(pcp + e, pcp, gains, r_safe);
            [~, gm] = apf_potential(pcp - e, pcp, gains, r_safe);
            Hfd(:, i) = (gp - gm) / (2*dH);
        end
        err = norm(Hfd - Hgoal, Inf);
        if err > tolH, okB = false; end
        if err > worstH
            worstH = err;  worstHat = sprintf('t = %g s', V.t_V(it));
        end
    end
    checks(end+1) = baseline_check('V1c-B goal Hessian vs k_a*(1+kappa)*I', okB, ...
        ['dH = %g m; ||H_goal||_inf = %.6e; worst ||H_fd - H_goal||_inf = ' ...
         '%.6e against tol = %.6e (%s)'], dH, norm(Hgoal, Inf), worstH, tolH, worstHat);

    res.name      = 'V1 - APF gradient and goal Hessian';
    res.checks    = checks;
    res.pass      = all([checks.pass]);
    res.withdrawn = V.withdrawn(1, :);
end

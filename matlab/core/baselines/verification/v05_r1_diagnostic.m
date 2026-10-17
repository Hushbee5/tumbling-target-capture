function res = v05_r1_diagnostic(p, V)
% V05_R1_DIAGNOSTIC  V5: R1 domain, maximum, tails, roots and non-participation.
%
%   V5a  CLOSED FORM at x in { -20, -3, -1.5, -r_safe, r_safe, c+1e-3, 1, 3, 20 }
%        (branch ENDPOINTS +/- r_safe included EXPLICITLY), under the FROZEN
%        MIXED ABSOLUTE/RELATIVE test applied at EVERY point:
%            | Phi_impl - Phi_ref |  <=  1e-12 * max( k_a , |Phi_ref| )
%        A pure relative test is UNDEFINED where Phi_ref == 0, which DOES occur
%        at x = +/-20 because the exponential underflows IEEE double. The k_a
%        floor makes the test well posed there instead of degenerate.
%
%   V5b  REFERENCE MAXIMUM over the FROZEN FINITE REFERENCE DOMAIN, rebuilt here
%        INDEPENDENTLY: dense scan at step 1e-4 to bracket candidates, each
%        interior candidate refined with a bounded scalar optimiser at
%        TolX = 1e-10, then M_ref = max(branch endpoints, refined interior maxima).
%        PASS | M_impl - M_ref | <= 1e-8 * max( 1e-30 , |M_ref| )
%        1e-8 is an a-priori realistic double-precision agreement level for two
%        independent evaluations of the same closed form after TolX = 1e-10
%        refinement. It is NOT derived from the scan step.
%
%   V5b-TAIL  the envelope |Phi(x)|/k_a <= kappa*exp(beta*(c^2-x^2))*(beta*|x|*(|x|+c)+1)
%        evaluated at |x| = 20 at the WORST bracket corner (beta = 3.125,
%        kappa = 10) and at (12.5,10), (3.125,0.1), (12.5,0.1), against the
%        PREDECLARED NEGLIGIBLE LEVEL 1e-30. The scope is the FULL FROZEN
%        REFINEMENT ENVELOPE beta in [3.125, 12.5], kappa in [0.1, 10] - not the
%        coarse levels - because refinement adds intermediate integer-lattice
%        values inside that bracket and the envelope is never widened.
%        CONSEQUENCE: no omitted tail maximum can affect M, and since a
%        stationary root needs Phi/k_a = 1 >> 1e-30, NO ROOT CAN LIE IN THE TAIL.
%        This is a numerical-domain justification for a DIAGNOSTIC, not a theorem.
%
%   V5c  REFERENCE VALUE at (beta*h_goal, kappa) = (1,1):
%            Phi(-r_safe)/k_a = kappa*exp(beta*h_goal)*[ beta*r_safe*(r_safe+c) - 1 ]
%        PASS | value - 15.194482592 | <= 1e-6 * 15.194482592
%
%   V5d  ANTIPODAL DOMINANCE   PASS  M_minus > M_plus at theta_V
%
%   V5e  DIAGNOSTIC ONLY       PASS  static inspection shows apf_r1_margin is
%        NOT referenced by the ordering computation. Implemented as a real
%        dependency-closure query over BASELINE_SELECTION and
%        BASELINE_ORDER_BETTER, not as a text search for a comment.
%
%   V5f  STATIONARY LOCATIONS, required when the R1 margin is NEGATIVE:
%        every returned root lies on a SAFE signed branch inside the reference
%        domain; residual |Phi(x_i) - k_a| <= 1e-9*k_a; the returned root COUNT
%        per branch equals the sign-change count of g = Phi - k_a on an
%        independent dense scan of that branch; and the V5b-TAIL bound certifies
%        no root outside the domain.
%        DIAGNOSTIC CAVEAT, stated rather than certified away: a tangential
%        (double) root produces no sign change and can evade the scan. min|g| is
%        reported for every no-sign-change segment and any segment with
%        min|g| < 1e-6*k_a is FLAGGED, not failed. Absence of tangential roots is
%        NOT certified.

    g      = p.bl.geom;
    gains  = V.gains;
    c      = g.c;
    r_safe = g.r_safe;
    k_a    = gains.k_a;
    k_r    = gains.k_r;
    beta   = gains.beta;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    r1 = apf_r1_margin(gains, p);

    % ---- V5a ----------------------------------------------------------------
    xs = [-20, -3, -1.5, -r_safe, r_safe, c + 1e-3, 1, 3, 20];
    okA = true;  worstA = 0;  worstAtolA = 0;  worstAx = NaN;
    for i = 1:numel(xs)
        x = xs(i);
        % INDEPENDENT TRANSCRIPTION, written out here from the protocol text.
        phiRef  = k_r * exp(-beta * (x^2 - r_safe^2)) * ( beta * x * (x - c) - 1 );
        phiImpl = apf_r1_phi(x, k_r, beta, r_safe, c);
        e   = abs(phiImpl - phiRef);
        tol = V.fd.v5a_tol * max(k_a, abs(phiRef));
        if e > tol, okA = false; end
        if e - tol > worstA - worstAtolA
            worstA = e;  worstAtolA = tol;  worstAx = x;
        end
    end
    checks(end+1) = baseline_check('V5a Phi matches an independent transcription', okA, ...
        ['%d points including the branch endpoints +/-r_safe; worst |err| = ' ...
         '%.6e against tol = %.6e at x = %g'], numel(xs), worstA, worstAtolA, worstAx);

    % ---- V5b : an INDEPENDENT reference maximum ----------------------------
    Mp = ref_branch_max(k_r, beta, r_safe, c,  r_safe,  20);
    Mm = ref_branch_max(k_r, beta, r_safe, c, -20, -r_safe);
    Mref = max(Mp, Mm);
    eB   = abs(r1.M - Mref);
    tB   = V.fd.v5b_tol * max(1e-30, abs(Mref));
    checks(end+1) = baseline_check('V5b maximum vs an independent reference', ...
        eB <= tB, ['M_impl = %.12e, M_ref = %.12e, |err| = %.6e against ' ...
        'tol = %.6e'], r1.M, Mref, eB, tB);

    % ---- V5b-TAIL -----------------------------------------------------------
    corners = [3.125, 10; 12.5, 10; 3.125, 0.1; 12.5, 0.1];
    bounds  = zeros(1, 4);
    for i = 1:4
        bounds(i) = apf_r1_tail_envelope(20, corners(i, 1), corners(i, 2), c);
    end
    okT = all(bounds < 1e-30);
    checks(end+1) = baseline_check('V5b-TAIL envelope below the predeclared 1e-30 at |x| = 20', ...
        okT, ['corners (beta,kappa) = (3.125,10) worst, (12.5,10), (3.125,0.1), ' ...
        '(12.5,0.1) give [%.3e %.3e %.3e %.3e]; scope is the FULL refinement ' ...
        'envelope beta in [3.125,12.5], kappa in [0.1,10]'], bounds);

    % ---- V5c ----------------------------------------------------------------
    okC5 = abs(beta * g.h_goal - 1) <= 1e-12 && abs(gains.kappa - 1) <= 1e-15;
    valC = gains.kappa * exp(beta * g.h_goal) * ( beta * r_safe * (r_safe + c) - 1 );
    eC   = abs(valC - V.fd.v5c_ref);
    tC   = V.fd.v5c_tol * V.fd.v5c_ref;
    checks(end+1) = baseline_check('V5c reference value at (beta*h_goal, kappa) = (1,1)', ...
        okC5 && eC <= tC, ...
        ['beta*h_goal = %.15g, kappa = %g; Phi(-r_safe)/k_a = %.12f, ' ...
         'reference %.9f, |err| = %.3e against tol = %.3e'], ...
        beta*g.h_goal, gains.kappa, valC, V.fd.v5c_ref, eC, tC);
    % The same quantity read out of the implementation, as a cross-check.
    valImpl = apf_r1_phi(-r_safe, k_r, beta, r_safe, c) / k_a;
    checks(end+1) = baseline_check('V5c implementation reproduces the reference value', ...
        abs(valImpl - V.fd.v5c_ref) <= tC, ...
        'Phi(-r_safe)/k_a from the implementation = %.12f', valImpl);

    % ---- V5d ----------------------------------------------------------------
    checks(end+1) = baseline_check('V5d antipodal dominance M_minus > M_plus at theta_V', ...
        r1.M_minus > r1.M_plus, 'M_minus = %.12e at x = %.6f, M_plus = %.12e at x = %.6f', ...
        r1.M_minus, r1.x_at_M_minus, r1.M_plus, r1.x_at_M_plus);

    % ---- V5e : static, over the real dependency closure ---------------------
    [okE, detE] = ordering_excludes_r1();
    checks(end+1) = baseline_check('V5e apf_r1_margin is NOT in the ordering closure', ...
        okE, '%s', detE);

    % ---- V5f ----------------------------------------------------------------
    if r1.r1_margin < 0
        loc  = r1.stationary_locations;
        onBr = all((loc >= r_safe & loc <= 20) | (loc <= -r_safe & loc >= -20));
        resid = abs(apf_r1_phi(loc, k_r, beta, r_safe, c) - k_a);
        okRes = all(resid <= 1e-9 * k_a);

        nP = independent_sign_changes(k_r, beta, r_safe, c, k_a,  r_safe,  20);
        nM = independent_sign_changes(k_r, beta, r_safe, c, k_a, -20, -r_safe);
        okCnt = (nP == r1.sign_change_count_plus) && (nM == r1.sign_change_count_minus);

        checks(end+1) = baseline_check('V5f roots lie on safe branches in the reference domain', ...
            onBr, '%d root(s): %s', numel(loc), mat2str(loc, 8));
        checks(end+1) = baseline_check('V5f root residual |Phi(x_i) - k_a| <= 1e-9*k_a', ...
            okRes, 'worst residual %.6e against tol %.6e', max([resid, 0]), 1e-9*k_a);
        checks(end+1) = baseline_check('V5f root count matches an independent dense scan', ...
            okCnt, ['implementation [+%d, -%d] vs independent scan [+%d, -%d] ' ...
            'at step 1e-4'], r1.sign_change_count_plus, r1.sign_change_count_minus, nP, nM);
        checks(end+1) = baseline_check('V5f the V5b-TAIL bound certifies no root outside the domain', ...
            okT, ['|Phi|/k_a < 1e-30 for |x| >= 20 while a root needs ' ...
            'Phi/k_a = 1, so the finite reference domain is sufficient']);
    else
        checks(end+1) = baseline_check('V5f not applicable: r1_margin >= 0', true, ...
            ['r1_margin = %.12e >= 0, so no off-goal stationary point exists on ' ...
             'the safe branches and no locations are required'], r1.r1_margin);
    end

    res.name   = 'V5 - R1 diagnostic: domain, maximum, tails, roots';
    res.checks = checks;
    res.pass   = all([checks.pass]);
    res.r1     = r1;
    res.tangential_caveat = ['A tangential (double) root produces no sign ' ...
        'change and can evade the scan. min|g| over each no-sign-change ' ...
        'segment is reported and a segment below 1e-6*k_a is FLAGGED, not ' ...
        'failed. Absence of tangential roots is NOT certified.'];
    res.tangential_flag        = r1.tangential_flag;
    res.tangential_min_abs_g   = r1.tangential_min_abs_g;
end

% =====================================================================
function M = ref_branch_max(k_r, beta, r_safe, c, a, b)
% The V5b reference procedure, rebuilt independently of APF_R1_MARGIN:
% dense scan at 1e-4 to bracket, bounded refinement at TolX = 1e-10, then the
% maximum of the refined interior candidates and BOTH branch endpoints. The far
% endpoint is negligible by the V5b-TAIL bound, so including it removes an
% ambiguity without being able to change the answer.
    phi = @(x) k_r .* exp(-beta .* (x.^2 - r_safe^2)) .* ( beta .* x .* (x - c) - 1 );
    xs = a : 1e-4 : b;
    if xs(end) < b, xs = [xs, b]; end
    fv = phi(xs);
    M  = max(fv(1), fv(end));

    n = numel(fv);
    idx = find(fv(2:end-1) >= fv(1:end-2) & fv(2:end-1) >= fv(3:end)) + 1;
    opts = optimset('TolX', 1e-10);
    for i = 1:numel(idx)
        j  = idx(i);
        lo = xs(max(j-1, 1));
        hi = xs(min(j+1, n));
        if hi <= lo, continue, end
        [~, negf] = fminbnd(@(z) -phi(z), lo, hi, opts);
        M = max(M, -negf);
    end
end

% =====================================================================
function n = independent_sign_changes(k_r, beta, r_safe, c, k_a, a, b)
% Sign changes of g(x) = Phi(x) - k_a on one branch, from an independent dense
% scan at step 1e-4.
    phi = @(x) k_r .* exp(-beta .* (x.^2 - r_safe^2)) .* ( beta .* x .* (x - c) - 1 );
    xs = a : 1e-4 : b;
    if xs(end) < b, xs = [xs, b]; end
    s = sign(phi(xs) - k_a);
    n = sum(s(1:end-1) .* s(2:end) < 0);
end

% =====================================================================
function [ok, detail] = ordering_excludes_r1()
% V5e as a real static test: the transitive dependency closure of the ordering
% computation must not contain apf_r1_margin.m. A comment claiming independence
% would prove nothing; this queries what the code actually reaches.
    targets = {'baseline_selection.m', 'baseline_order_better.m'};
    closure = {};
    for i = 1:numel(targets)
        f = which(targets{i});
        if isempty(f)
            ok = false;
            detail = sprintf('could not resolve %s on the path', targets{i});
            return
        end
        closure = [closure(:); matlab.codetools.requiredFilesAndProducts(f)'];
    end
    names = cell(numel(closure), 1);
    for i = 1:numel(closure)
        [~, nm] = fileparts(closure{i});
        names{i} = nm;
    end
    hit = any(strcmp(names, 'apf_r1_margin')) || any(strcmp(names, 'apf_r1_phi')) ...
       || any(strcmp(names, 'apf_r1_tail_envelope'));
    ok = ~hit;
    detail = sprintf(['closure of {%s} has %d file(s); R1 present = %d. R1 is ' ...
        'DIAGNOSTIC ONLY and does not appear in the T1-T7 ordering.'], ...
        strjoin(targets, ', '), numel(closure), hit);
end

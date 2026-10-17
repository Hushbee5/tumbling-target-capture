function r1 = apf_r1_margin(gains, p)
% APF_R1_MARGIN  R1 stationary-locus diagnostic. DIAGNOSTIC ONLY.
%   r1 = apf_r1_margin(gains, p) evaluates the signed-axis stationary condition
%   of protocol Sec. 3.2 over the frozen finite reference domain.
%
%   STATIONARY LOCUS. Off-goal stationary points of the frozen-time landscape
%   require collinearity of e and r, i.e. r = x*n_hat on the SIGNED line
%   n_hat = p_cp/c, x in R (both signs), and there
%
%       k_a = Phi(x) ,   Phi(x) = k_r*exp(-beta*(x^2 - r_safe^2))*[ beta*x*(x-c) - 1 ]
%
%   No off-goal stationary point exists for 0 < x < c, hence none between the
%   keep-out sphere and the capture point. The ANTIPODAL branch x <= -r_safe
%   dominates the positive branch pointwise (checked as V5d).
%
%   MARGIN SIGN CONVENTION - RECORDED, NOT FROZEN BY THE PROTOCOL.
%       M          = max( M_plus , M_minus )        over the SAFE branches
%       r1_margin  = k_a - M
%   so r1_margin > 0 means Phi < k_a everywhere on the safe branches and NO
%   off-goal stationary point exists there; r1_margin < 0 means at least one
%   does. The protocol states the condition (k_a = Phi) but not the sign of the
%   reported margin, so k_a, M, M_plus and M_minus are ALL returned beside it
%   and the convention is auditable rather than implicit.
%
%   R1 DOES NOT APPEAR IN THE ORDERING. The T1 -> T7 total order of Sec. 6.4
%   never reads this function's output; BASELINE_SELECTION must not call it, and
%   V5e verifies that by static inspection. The margin and, when negative, the
%   stationary locations are logged for every candidate as diagnostics only.
%
%   REFERENCE DOMAIN AND PROCEDURE (Sec. 14, V5b):
%       domain   positive branch [ r_safe , 20 ] , negative branch [ -20 , -r_safe ]
%       stage 1  dense scan, step 1e-4, used ONLY to bracket candidate extrema
%       stage 2  each interior candidate refined INDEPENDENTLY with a bounded
%                scalar optimiser at TolX = 1e-10
%       stage 3  M_ref(branch) = max( Phi at the branch ENDPOINTS , refined
%                interior maxima )
%   BOTH endpoints of each branch are included. The far endpoint at |x| = 20 is
%   negligible by the V5b-TAIL envelope (|Phi|/k_a < 1e-30 there), so including
%   it cannot change M; it is included so that "the branch endpoint" carries no
%   ambiguity between this implementation and the independent V5b reference.
%
%   The finite domain is sufficient for BOTH the maximum and the root count,
%   because APF_R1_TAIL_ENVELOPE bounds |Phi|/k_a below 1e-30 for all |x| >= 20
%   across the full frozen refinement envelope, and a root needs Phi/k_a = 1.
%
%   TANGENTIAL ROOTS ARE NOT CERTIFIED AWAY. A double root produces no sign
%   change and can evade the scan. min|g| is reported for every scan segment
%   containing no sign change, and any segment with min|g| < 1e-6*k_a is FLAGGED
%   (not failed). Absence of tangential roots is NOT certified.
%
%   r1 fields:
%       k_a, beta, kappa, k_r, c, r_safe
%       M_plus, M_minus, M, r1_margin, antipodal_dominates
%       x_at_M_plus, x_at_M_minus
%       has_stationary, stationary_locations, stationary_residual
%       sign_change_count_plus/minus, tangential_flag, tangential_min_abs_g
%       tail_bound_at_20, domain, is_diagnostic_only, note

    if isfield(p, 'bl') && isfield(p.bl, 'geom')
        g = p.bl.geom;
    else
        g = baseline_constants(p);
    end

    k_a    = gains.k_a;
    k_r    = gains.k_r;
    beta   = gains.beta;
    kappa  = gains.kappa;
    c      = g.c;
    r_safe = g.r_safe;

    XMAX = 20;                    % frozen finite reference domain half-width
    STEP = 1e-4;                  % frozen stage-1 scan step
    TOLX = 1e-10;                 % frozen stage-2 optimiser tolerance
    RESID_TOL = 1e-9;             % frozen root residual tolerance, relative to k_a
    TANG_TOL  = 1e-6;             % frozen tangential-root FLAG level, rel. to k_a

    % The SINGLE implementation of Phi lives in APF_R1_PHI, which V5a compares
    % against an independent transcription. Keeping a private copy here would
    % let the tested function and the used function drift apart.
    phi = @(x) apf_r1_phi(x, k_r, beta, r_safe, c);

    % ---- positive branch [ r_safe , 20 ] -----------------------------------
    [Mp, xMp, xsP, gP] = branch_scan(phi, r_safe, XMAX, STEP, TOLX, k_a);
    % ---- antipodal branch [ -20 , -r_safe ] --------------------------------
    [Mm, xMm, xsM, gM] = branch_scan(phi, -XMAX, -r_safe, STEP, TOLX, k_a);

    M = max(Mp, Mm);
    r1.k_a    = k_a;
    r1.beta   = beta;
    r1.kappa  = kappa;
    r1.k_r    = k_r;
    r1.c      = c;
    r1.r_safe = r_safe;

    r1.M_plus       = Mp;
    r1.M_minus      = Mm;
    r1.x_at_M_plus  = xMp;
    r1.x_at_M_minus = xMm;
    r1.M            = M;
    r1.r1_margin    = k_a - M;
    r1.antipodal_dominates = Mm > Mp;

    % ---- roots of g(x) = Phi(x) - k_a, only when the margin is NEGATIVE ----
    [rootsP, nSignP, tangP, minAbsP, nSegP] = branch_roots(phi, xsP, gP, k_a, RESID_TOL, TANG_TOL);
    [rootsM, nSignM, tangM, minAbsM, nSegM] = branch_roots(phi, xsM, gM, k_a, RESID_TOL, TANG_TOL);

    r1.sign_change_count_plus  = nSignP;
    r1.sign_change_count_minus = nSignM;
    r1.tangential_flag         = tangP || tangM;
    r1.tangential_min_abs_g    = min(minAbsP, minAbsM);
    % Number of no-sign-change segments actually inspected per branch. Under the
    % exact partition this is always (sign changes + 1), so it is a cheap audit
    % that no stretch of the scan was dropped from the tangential diagnostic.
    r1.tangential_segments_plus  = nSegP;
    r1.tangential_segments_minus = nSegM;

    r1.has_stationary = r1.r1_margin < 0;
    if r1.has_stationary
        loc = [rootsM(:).', rootsP(:).'];            % antipodal branch first
        r1.stationary_locations = loc;
        r1.stationary_residual  = abs(phi(loc) - k_a);
        r1.stationary_residual_ok = all(r1.stationary_residual <= RESID_TOL * k_a);
    else
        % Sec. 6.4 asks for locations only when the margin is negative. An empty
        % row vector records "not applicable", never "none found after looking".
        r1.stationary_locations   = zeros(1, 0);
        r1.stationary_residual    = zeros(1, 0);
        r1.stationary_residual_ok = true;
    end

    r1.tail_bound_at_20 = apf_r1_tail_envelope(XMAX, beta, kappa, c);
    r1.domain = struct('x_max', XMAX, 'scan_step', STEP, 'tol_x', TOLX, ...
        'residual_tol_rel_ka', RESID_TOL, 'tangential_flag_tol_rel_ka', TANG_TOL, ...
        'positive_branch', [r_safe, XMAX], 'negative_branch', [-XMAX, -r_safe]);
    r1.is_diagnostic_only = true;
    r1.note = ['R1 is DIAGNOSTIC ONLY and does not appear in the T1-T7 ' ...
        'ordering. r1_margin = k_a - M with M the maximum of Phi over the two ' ...
        'SAFE signed branches; positive means no off-goal stationary point on ' ...
        'those branches. Tangential (double) roots are not certified absent.'];
end

% =====================================================================
function [M, xM, xs, gvals] = branch_scan(phi, a, b, step, tolx, k_a)
% Stage 1 dense scan + stage 2 bounded refinement + stage 3 endpoint comparison,
% over one signed branch [a, b]. Returns the branch maximum M, its location, and
% the scan grid with g = Phi - k_a for the root pass.
    xs = a : step : b;
    if xs(end) < b, xs = [xs, b]; end               % never truncate the endpoint
    fv = phi(xs);
    gvals = fv - k_a;

    % --- stage 3 seed: BOTH branch endpoints --------------------------------
    [M, iE] = max([fv(1), fv(end)]);
    ends    = [xs(1), xs(end)];
    xM      = ends(iE);

    % --- stage 1: bracket interior local maxima -----------------------------
    n = numel(fv);
    if n >= 3
        isPeak = fv(2:end-1) >= fv(1:end-2) & fv(2:end-1) >= fv(3:end);
        idx = find(isPeak) + 1;
    else
        idx = [];
    end

    % --- stage 2: refine each candidate independently ------------------------
    opts = optimset('TolX', tolx);
    for i = 1:numel(idx)
        j  = idx(i);
        lo = xs(max(j-1, 1));
        hi = xs(min(j+1, n));
        if hi <= lo, continue, end
        [xr, negf] = fminbnd(@(z) -phi(z), lo, hi, opts);
        fr = -negf;
        if fr > M
            M  = fr;
            xM = xr;
        end
    end
end

% =====================================================================
function [roots_, nSign, tangFlag, minAbsG, nSeg] = branch_roots(phi, xs, gvals, k_a, residTol, tangTol)
% Roots of g(x) = Phi(x) - k_a on one branch, from sign changes of the same
% dense scan the maximum used, refined with FZERO.
%
% TANGENTIAL CAVEAT. Segments of the scan that contain NO sign change are
% inspected for near-touches: min|g| over each such segment is reported and any
% segment with min|g| < tangTol*k_a is FLAGGED. A flag is not a failure - it
% records that a double root cannot be excluded there.
%
% THE PARTITION IS EXACT, AND THAT MATTERS. A sign change detected at scan index
% i straddles the PAIR (i, i+1), so the no-sign-change regions are
%     [1 .. i1] , [i1+1 .. i2] , ... , [i_last+1 .. n]
% An earlier spelling built inclusive segments from edges = [1, idx+1, n], so a
% segment ENDED at idx+1 and therefore CONTAINED the straddling pair; it was
% then skipped as "this segment has a root", and with at least one sign change
% that silently dropped genuine no-sign-change stretches out of the frozen V5f
% tangential diagnostic. Cutting at
%     starts = [1, idx+1]        stops = [idx, n]
% puts every scan point in exactly one segment and no segment across a detected
% pair, so zero, one, adjacent and end-of-branch sign changes are all handled
% without a special case. Single-point segments are legitimate and are inspected.
%
% Nothing else changes: Phi, the root finding, the R1 margin, the residual
% tolerance, the tangential threshold, the diagnostic-only status and the
% T1-T7 ordering are all untouched.
    s   = sign(gvals);
    idx = find(s(1:end-1) .* s(2:end) < 0);          % strict sign changes only
    nSign = numel(idx);

    roots_ = zeros(1, nSign);
    for i = 1:nSign
        j = idx(i);
        roots_(i) = fzero(@(z) phi(z) - k_a, [xs(j), xs(j+1)]);
    end

    % Residual check on every returned root, against the frozen tolerance.
    if nSign > 0
        resid = abs(phi(roots_) - k_a);
        assert(all(resid <= residTol * k_a), 'apf_r1_margin:root_residual', ...
            ['A refined R1 root has residual %.3e, above the frozen tolerance ' ...
             '%.3e (= %.1e * k_a).'], max(resid), residTol * k_a, residTol);
    end

    % The no-sign-change regions, partitioned EXACTLY (see the header):
    %     starts = [1, idx+1]        stops = [idx, n]
    % Every scan point lies in exactly one segment and no segment spans a
    % detected sign-change pair, so no segment has to be skipped.
    idxRow = idx(:).';
    starts = [1, idxRow + 1];
    stops  = [idxRow, numel(xs)];
    tangFlag = false;
    minAbsG  = Inf;
    nSeg     = 0;
    for i = 1:numel(starts)
        a = starts(i);
        b = stops(i);
        if b < a
            continue            % defensive only; cannot arise for valid indices
        end
        m = min(abs(gvals(a:b)));
        minAbsG = min(minAbsG, m);
        nSeg    = nSeg + 1;
        if m < tangTol * k_a
            tangFlag = true;
        end
    end
    if ~isfinite(minAbsG), minAbsG = NaN; end
end

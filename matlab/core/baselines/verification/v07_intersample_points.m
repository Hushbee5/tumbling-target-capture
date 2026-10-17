function res = v07_intersample_points(p, V, run)
% V07_INTERSAMPLE_POINTS  V7: n_sub = 10 gives 9 STRICT-interior points.
%
%   PASS  n_sub == 10 means 10 subintervals per control interval
%   PASS  strict-interior diagnostic points per interval == 9
%   PASS  total strict-interior points == 9*K  (450 at Tsim_V; 72000 at 800 s,
%         asserted SYMBOLICALLY, not executed)
%   PASS  every strict-interior time t satisfies  t_k < t < t_k + Ts
%         (STRICT ON BOTH SIDES; no endpoint duplication with the control-state
%         samples)
%   PASS  the inspected union has exactly (K+1) + 9*K elements
%
%   WHY STRICTNESS MATTERS. The inspected union of Sec. 6.2 is the basis of
%   NO_OBSERVED_BODY_VIOLATION, T1, T2 and t_viol. If an interior point
%   coincided with a control-state sample, that sample would be counted twice
%   and t_viol could be attributed to the wrong interval - which would then move
%   the selection horizon and change T5/T6. The strictness is therefore a
%   correctness property of the ordering, not a tidiness preference.

    Ts     = p.ctrl.Ts;
    n_sub  = p.bl.n_sub;
    K      = run.K;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    checks(end+1) = baseline_check('V7 n_sub == 10 subintervals per control interval', ...
        n_sub == 10, 'n_sub = %d', n_sub);

    perInterval = n_sub - 1;
    checks(end+1) = baseline_check('V7 strict-interior points per interval == 9', ...
        perInterval == 9, 'n_sub - 1 = %d', perInterval);

    nInt = numel(run.inter_t);
    checks(end+1) = baseline_check('V7 total strict-interior points == 9*K', ...
        nInt == 9*K, 'observed %d, expected 9*%d = %d (450 at Tsim_V)', ...
        nInt, K, 9*K);

    % ---- strictness on BOTH sides, interval by interval ---------------------
    okStrict = true;
    worstLo  = Inf;  worstHi = Inf;
    for k = 1:K
        seg = run.inter_t((k-1)*perInterval + (1:perInterval));
        lo  = run.t(k);
        hi  = run.t(k) + Ts;
        okStrict = okStrict && all(seg > lo) && all(seg < hi);
        worstLo  = min(worstLo, min(seg - lo));
        worstHi  = min(worstHi, min(hi - seg));
    end
    checks(end+1) = baseline_check('V7 every interior time satisfies t_k < t < t_k + Ts', ...
        okStrict, ['strict on both sides over all %d intervals; smallest ' ...
        'margins are %.6e s above t_k and %.6e s below t_k + Ts'], ...
        K, worstLo, worstHi);

    % No interior time may coincide with a control-state sample.
    okNoDup = ~any(ismember(run.inter_t, run.t));
    checks(end+1) = baseline_check('V7 no interior time duplicates a control-state sample', ...
        okNoDup, '%d interior times against %d control-state samples', ...
        nInt, numel(run.t));

    nUnion = numel(run.t) + nInt;
    checks(end+1) = baseline_check('V7 inspected union has exactly (K+1) + 9*K elements', ...
        nUnion == (K+1) + 9*K, 'observed %d, expected %d + %d = %d', ...
        nUnion, K+1, 9*K, (K+1) + 9*K);

    % ---- SYMBOLIC 800 s statement, NOT executed ----------------------------
    K800 = round(800 / Ts);
    checks(end+1) = baseline_check('V7 symbolic 800 s interior count == 72000 (NOT executed)', ...
        9*K800 == 72000, '9 * %d = %d, and the union would hold %d elements', ...
        K800, 9*K800, (K800+1) + 9*K800);

    res.name   = 'V7 - intersample diagnostic points';
    res.checks = checks;
    res.pass   = all([checks.pass]);
    res.n_interior_expected_at_verify = V.n_interior_V;
end

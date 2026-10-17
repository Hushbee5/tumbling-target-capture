function res = v02_acp_ff_and_preview_truth(p, V, tabs)
% V02_ACP_FF_AND_PREVIEW_TRUTH  V2: a_cp_ff stencil and preview/truth audit.
%
%   V2a  INDEXING / ENDPOINTS
%        PASS  size(a_cp_ff_ctrl) == [3, K_V]                (exactly K columns)
%        FROZEN NUMERICAL TOLERANCE for BOTH stencil comparisons:
%              || a_impl - a_ref ||_inf <= 1e-14 * max( 1 , || a_ref ||_inf )
%              Frozen before any execution; no tolerance is chosen afterwards.
%        PASS  the k = 0 column equals an INDEPENDENTLY RECODED forward
%              three-point formula, within that tolerance
%        PASS  the column at the EXACT DETERMINISTIC physical zero-based index
%              k = 17 equals an INDEPENDENTLY RECODED central formula, within
%              that tolerance. k = 17 lies strictly inside the K_V = 50 grid
%              (k = 0..49), so both neighbours 16 and 18 exist.
%              NO RNG AND NO SEED ENTERS V2a.
%        PASS  no controller column reads a preview index outside 0..K_V
%        PASS  a_cp_ff[K], if stored, is tagged DIAGNOSTIC_ONLY and is NOT an
%              element of a_cp_ff_ctrl
%
%   V2b  SECOND-ORDER CONVERGENCE on the analytic surrogate f(t) = sin(w0*t),
%        w0 = 0.05 rad/s, sampled at Ts in {0.1, 0.05, 0.025}
%        PASS  err(Ts)/err(Ts/2) in [3.5, 4.5] for BOTH stencils
%        The surrogate is analytic and non-degenerate, unlike the withdrawn V1b
%        setting, so a truncation ratio IS a valid expectation here. The sampled
%        time span is held fixed while Ts is refined, so the three errors are
%        measured over the same continuous domain.
%
%   V2c  PREVIEW / TRUTH CONSISTENCY, FULL DETERMINISTIC TARGET HORIZON
%        grid    t = 0 : Ts : 800 s   (8001 target-grid samples)
%        scope   TARGET-ONLY propagation. No chaser state, no evaluation IC, no
%                scientific baseline run.
%        measure Ep = max || p_cp_preview - p_cp_truth ||_inf   [m]
%                Ev = max || v_cp_preview - v_cp_truth ||_inf   [m/s]
%        PASS    Ep <= 1e-6 m  AND  Ev <= 1e-6 m/s
%        REPORT  Ep, Ev and their argmax indices/times are reported regardless
%                of PASS/FAIL.
%
%   V2c TOLERANCE STATUS, stated rather than implied. 1e-6 is an A-PRIORI
%   ENGINEERING numerical-consistency tolerance. ODE RelTol/AbsTol are LOCAL
%   error controls and do NOT mathematically guarantee any global error bound;
%   no such guarantee is asserted. The value is an engineering judgement: five
%   decades below s_cap, hence far too tight to mask any physically meaningful
%   discrepancy, while loose enough to tolerate output-grid and step-partition
%   effects of the kind already measured in the frozen Channel-A/Channel-B audits.
%
%   V2c PRECONDITION, CONFIRMED BY SOURCE INSPECTION BEFORE EXECUTION: both
%   quantities are LVLH-frame capture-point position [m] and velocity [m/s],
%   produced through the same capture_point_lvlh transport formula and sampled
%   on the same t = 0 : Ts : 800 grid. They are dimensionally and semantically
%   comparable. (See the header of BASELINE_CAPTURE_TABLES.)

    Ts     = p.ctrl.Ts;
    K_V    = V.K_V;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    % ---- V2a ----------------------------------------------------------------
    vprev = tabs.v_cp_preview(:, 1:K_V+1);         % v_cp_preview[0..K_V]
    ff    = baseline_acp_ff(vprev, Ts);

    okSize = isequal(size(ff.a_ctrl), [3, K_V]);
    checks(end+1) = baseline_check('V2a size(a_cp_ff_ctrl) == [3, K_V]', okSize, ...
        'size = %s, required [3 %d]', mat2str(size(ff.a_ctrl)), K_V);

    % INDEPENDENTLY RECODED forward three-point rule at k = 0. Written out here
    % from the protocol text, not called from the implementation.
    a0_ref = ( -3*vprev(:, 1) + 4*vprev(:, 2) - vprev(:, 3) ) / (2*Ts);
    e0     = norm(ff.a_ctrl(:, 1) - a0_ref, Inf);
    t0     = V.fd.stencil_tol * max(1, norm(a0_ref, Inf));
    checks(end+1) = baseline_check('V2a k = 0 forward stencil vs recoded reference', ...
        e0 <= t0, '|err|_inf = %.6e against tol = %.6e', e0, t0);

    % INDEPENDENTLY RECODED central rule at the EXACT physical index k = 17.
    kC = V.fd.v2a_central_k;
    assert(kC >= 1 && kC <= K_V-1, 'v02:central_index', ...
        'The frozen central index k = %d is not strictly inside 0..%d.', kC, K_V);
    aC_ref = ( vprev(:, kC+2) - vprev(:, kC) ) / (2*Ts);
    eC     = norm(ff.a_ctrl(:, kC+1) - aC_ref, Inf);
    tC     = V.fd.stencil_tol * max(1, norm(aC_ref, Inf));
    checks(end+1) = baseline_check( ...
        sprintf('V2a k = %d central stencil vs recoded reference', kC), ...
        eC <= tC, ['|err|_inf = %.6e against tol = %.6e; neighbours k-1 = %d ' ...
        'and k+1 = %d both exist; no RNG and no seed entered this test'], ...
        eC, tC, kC-1, kC+1);

    % ---- no-overread evidence, from the TRUNCATED INPUT, not from a claim ----
    % BASELINE_ACP_FF was called above with vprev = v_cp_preview(:, 1:K_V+1),
    % i.e. EXACTLY the physical preview indices 0..K_V and no extra column. Had
    % any applied-column computation tried to index beyond K_V, that call would
    % have raised an out-of-bounds error instead of returning - so the fact that
    % it returned at all is INDEPENDENT RUNTIME EVIDENCE of no overread, rather
    % than trust in a number the implementation reports about itself.
    % ff.max_preview_index_read is kept as corroborating evidence only.
    okCols  = isequal(size(vprev), [3, K_V+1]);
    okOut   = size(ff.a_ctrl, 2) == K_V;
    okIdx   = ff.max_preview_index_read <= K_V;
    checks(end+1) = baseline_check('V2a no controller column reads past the state grid', ...
        okCols && okOut && okIdx, ...
        ['the call was made on a preview truncated to exactly %s (physical ' ...
         'indices 0..%d) and RETURNED, which is runtime evidence that no ' ...
         'applied column indexed beyond %d; it produced %d applied column(s) ' ...
         'for K_V = %d; the implementation additionally reports a largest read ' ...
         'index of %d (corroborating). No RNG and no seed entered this test.'], ...
        mat2str(size(vprev)), K_V, K_V, size(ff.a_ctrl, 2), K_V, ...
        ff.max_preview_index_read);

    okTerm = strcmp(ff.terminal_tag, 'DIAGNOSTIC_ONLY') && size(ff.a_ctrl, 2) == K_V;
    checks(end+1) = baseline_check('V2a terminal column is DIAGNOSTIC_ONLY and excluded', ...
        okTerm, ['tag = ''%s''; a_cp_ff_ctrl has %d columns so the terminal ' ...
        'value is not an element of it'], ff.terminal_tag, size(ff.a_ctrl, 2));

    % ---- V2b ----------------------------------------------------------------
    w0    = V.fd.v2b_w0;
    TsSet = V.fd.v2b_Ts;
    span  = V.Tsim_V;                              % fixed continuous domain
    errF  = zeros(1, numel(TsSet));
    errC  = zeros(1, numel(TsSet));
    for i = 1:numel(TsSet)
        h  = TsSet(i);
        Ki = round(span / h);
        tt = (0:Ki) * h;
        f  = zeros(3, Ki+1);
        f(1, :) = sin(w0 * tt);                    % the surrogate "velocity"
        fs = baseline_acp_ff(f, h);
        dref = w0 * cos(w0 * tt);                  % analytic derivative

        errF(i) = abs(fs.a_ctrl(1, 1) - dref(1));                  % k = 0 forward
        kk      = 2:Ki;                                            % k = 1..Ki-1
        errC(i) = max(abs(fs.a_ctrl(1, kk) - dref(kk)));           % central
    end
    rF = errF(1:end-1) ./ errF(2:end);
    rC = errC(1:end-1) ./ errC(2:end);
    lo = V.fd.v2b_ratio(1);  hi = V.fd.v2b_ratio(2);
    okF = all(rF >= lo & rF <= hi);
    okC = all(rC >= lo & rC <= hi);
    checks(end+1) = baseline_check('V2b forward stencil is second order', okF, ...
        'err = [%.3e %.3e %.3e], ratios = [%.4f %.4f], window [%.1f %.1f]', ...
        errF(1), errF(2), errF(3), rF(1), rF(2), lo, hi);
    checks(end+1) = baseline_check('V2b central stencil is second order', okC, ...
        'err = [%.3e %.3e %.3e], ratios = [%.4f %.4f], window [%.1f %.1f]', ...
        errC(1), errC(2), errC(3), rC(1), rC(2), lo, hi);

    % ---- V2c ----------------------------------------------------------------
    % Computed by the SHARED audit, the same function BASELINE_EVALUATE attaches
    % to every deterministic artifact as meta.v2c (V11b). A private copy here
    % could report a different number for the same tables.
    v2c = baseline_preview_truth_audit(tabs, V.fd.v2c_tol_p, V.fd.v2c_tol_v);

    checks(end+1) = baseline_check('V2c preview/truth position consistency', ...
        v2c.pass_p, ['Ep = %.6e m at sample %d (t = %.4f s), tolerance %.1e m; ' ...
         '%d target-grid samples compared'], v2c.Ep, v2c.argmax_index_p, ...
        v2c.argmax_t_p, v2c.tol_p, v2c.n_samples);
    checks(end+1) = baseline_check('V2c preview/truth velocity consistency', ...
        v2c.pass_v, 'Ev = %.6e m/s at sample %d (t = %.4f s), tolerance %.1e m/s', ...
        v2c.Ev, v2c.argmax_index_v, v2c.argmax_t_v, v2c.tol_v);

    res.name   = 'V2 - a_cp_ff stencil and preview/truth audit';
    res.checks = checks;
    res.pass   = all([checks.pass]);
    res.v2c    = v2c;
end

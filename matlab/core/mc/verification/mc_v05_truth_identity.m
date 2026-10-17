function R = mc_v05_truth_identity(~)
% MC_V05_TRUTH_IDENTITY  Truth identity for ONE non-scientific target (Sec. 10.2). NON-SCIENTIFIC.
%   With the hand-written fixture target of MC_VT_FIXTURE_TARGET and a 10 s
%   horizon: the two table builds of Condition U (nominal preview inertia) and
%   Condition M (matched) share a BITWISE-identical truth; and the proposed
%   method's internally propagated truth qT/wT equals the baseline_capture_tables
%   output bitwise, through the real MC invocation path (MC_INVOKE_PROPOSED,
%   inside the R18 guard, with the POST-RUN table assertion).

    R.name = 'V05 truth identity (fixture target, 10 s)';
    ch = {};
    c = mc_constants();
    pBL = baseline_config();
    fx = mc_vt_fixture_target();
    row = fx.row;
    Tsim = 10;

    AU = mc_shared_tables(row, 'U', pBL, Tsim);
    AM = mc_shared_tables(row, 'M', pBL, Tsim);
    ch{end+1} = mc_vt_check('shared table builds returned (U and M)', ...
        strcmp(AU.guard_status, 'RETURNED') && strcmp(AM.guard_status, 'RETURNED'), ...
        [AU.status ' / ' AM.status]);

    f = {'qT', 'wT', 'p_cp_truth', 'v_cp_truth', 'n_cp_truth'};
    for k = 1:numel(f)
        [eq, where] = mc_vt_bitwise_equal(AU.tabs.(f{k}), AM.tabs.(f{k}));
        ch{end+1} = mc_vt_check(['U and M truth ' f{k} ' bitwise identical'], ...
            eq && strcmp(AU.hash.(f{k}), AM.hash.(f{k})), where); %#ok<AGROW>
    end
    ch{end+1} = mc_vt_check('informational: the U and M previews differ (I_nom vs I_true)', true, ...
        sprintf('max |p_cp_preview_U - p_cp_preview_M| = %.3g m', ...
        max(abs(AU.tabs.p_cp_preview(:) - AM.tabs.p_cp_preview(:)))));

    P = mc_invoke_proposed(row, AU, Tsim);
    [okPost, gotPost] = mc_vt_throws(@() mc_postrun_check('proposed', ...
        struct('out', P.out, 'act_thresh', P.act_thresh), AU, row), 'NO_ERROR');
    ch{end+1} = mc_vt_check('proposed run returned through the R18 guard; POST-RUN table assertion passes', ...
        strcmp(P.guard.status, 'RETURNED') && ~isempty(P.out) && okPost, [P.guard.status ' ' gotPost]);
    out = P.out;
    ns = numel(out.t);
    [e1, w1] = mc_vt_bitwise_equal(out.qT, AU.tabs.qT(:, 1:ns));
    [e2, w2] = mc_vt_bitwise_equal(out.wT, AU.tabs.wT(:, 1:ns));
    ch{end+1} = mc_vt_check('proposed internal truth qT equals the shared table bitwise', e1, w1);
    ch{end+1} = mc_vt_check('proposed internal truth wT equals the shared table bitwise', e2, w2);
    [ok, got] = mc_vt_throws(@() mc_proposed_integrity(out, AU.tabs), 'NO_ERROR');
    ch{end+1} = mc_vt_check('MC per-run integrity assertions pass', ok || strcmp(got, 'NO_ERROR'), got);
    st = mc_classify_proposed(P.guard.status, out, round(Tsim / c.design.Ts));
    ch{end+1} = mc_vt_check('short fixture run classifies as COMPLETE', strcmp(st, 'COMPLETE'), st);

    if strcmp(AM.status, 'TABLES_OK')
        PM = mc_invoke_proposed(row, AM, Tsim);
        e3 = strcmp(PM.guard.status, 'RETURNED') && isequal(PM.out.qT, AM.tabs.qT(:, 1:numel(PM.out.t))) ...
             && isequal(PM.out.qT, out.qT) && isequal(PM.out.wT, out.wT);
        ch{end+1} = mc_vt_check('Condition-M proposed run sees the same truth as Condition U', e3);
    else
        ch{end+1} = mc_vt_check('Condition-M proposed run sees the same truth as Condition U', false, ...
            ['matched build did not pass V2c: ' AM.status]);
    end
    R.checks = [ch{:}];
end

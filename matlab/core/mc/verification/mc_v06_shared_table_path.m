function R = mc_v06_shared_table_path(~)
% MC_V06_SHARED_TABLE_PATH  Shared-table path equivalence, R21 (Sec. 10.2). NON-SCIENTIFIC.
%   For the non-scientific fixture target and a 10 s horizon, with the
%   Condition-U preview (nominal inertia, so preview ~= truth):
%     simulate_task4 run WITH opt.tbl = tabs.tbl_preview and run WITHOUT opt.tbl
%     (same targetEst) must produce bitwise-identical trajectories and
%     diagnostics - every field except config - and configs that differ ONLY
%     in the provenance fields config.custom_tbl and config.opt.tbl;
%     out.config.opt.tbl must equal the supplied table.
%   The table simulate_task4 would build internally is also rebuilt directly
%   and compared with the shared table bitwise.

    R.name = 'V06 shared-table path equivalence (R21)';
    ch = {};
    pBL = baseline_config();
    fx = mc_vt_fixture_target();
    row = fx.row;
    Tsim = 10;
    A = mc_shared_tables(row, 'U', pBL, Tsim);

    p_trial = params();
    p_trial.target.q0 = row.q0;
    p_trial.target.w0 = row.w0;
    p_trial.target.I  = row.I_true;
    pT4 = params_task4(p_trial);

    tblInternal = capture_table_build(pT4, A.prevIC, Tsim + (pT4.mpc.N + 2) * pT4.ctrl.Ts);
    [eq, where] = mc_vt_bitwise_equal(tblInternal, A.tabs.tbl_preview);
    ch{end+1} = mc_vt_check('the internal preview build equals the shared tbl_preview bitwise', eq, where);

    optA = struct('Tsim', Tsim, 'alpha', 1e-3, 'x0', row.x0, 'targetEst', A.prevIC, ...
                  'tbl', A.tabs.tbl_preview);
    optB = struct('Tsim', Tsim, 'alpha', 1e-3, 'x0', row.x0, 'targetEst', A.prevIC);
    outA = simulate_task4(pT4, optA);
    outB = simulate_task4(pT4, optB);

    [eq, where] = mc_vt_bitwise_equal(rmfield(outA, 'config'), rmfield(outB, 'config'));
    ch{end+1} = mc_vt_check('with vs without opt.tbl: every non-config field bitwise identical', eq, where);
    ch{end+1} = mc_vt_check('provenance: custom_tbl true with the table, false without', ...
        isequal(outA.config.custom_tbl, true) && isequal(outB.config.custom_tbl, false));
    ch{end+1} = mc_vt_check('out.config.opt.tbl equals the supplied table; absent without it', ...
        isequal(outA.config.opt.tbl, A.tabs.tbl_preview) && ~isfield(outB.config.opt, 'tbl'));
    cA = rmfield(outA.config, 'custom_tbl');
    cA.opt = rmfield(cA.opt, 'tbl');
    cB = rmfield(outB.config, 'custom_tbl');
    [eq, where] = mc_vt_bitwise_equal(cA, cB);
    ch{end+1} = mc_vt_check('configs differ ONLY in custom_tbl and opt.tbl', eq, where);
    ch{end+1} = mc_vt_check('informational: run length and event', true, ...
        sprintf('K_applied %d, event %s', outA.K_applied, outA.event));
    R.checks = [ch{:}];
end

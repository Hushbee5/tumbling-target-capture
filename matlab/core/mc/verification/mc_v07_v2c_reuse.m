function R = mc_v07_v2c_reuse(~)
% MC_V07_V2C_REUSE  V2c reuse and the Condition-M gate (Sec. 4.2, 10.2). NON-SCIENTIFIC.
%   The frozen baseline_preview_truth_audit, applied to a NON-SCIENTIFIC matched
%   pair (and to a mismatched one), returns every frozen field and PASS/FAIL
%   without throwing; its Ep is the INFINITY norm (recomputed independently);
%   the MC gate uses it only for Condition M, never for Condition U; and an
%   M_CONSISTENCY_FAILURE records every quantity as NOT_EXECUTED - never false,
%   never zero.

    R.name = 'V07 V2c reuse and the Condition-M gate';
    ch = {};
    pBL = baseline_config();
    fx = mc_vt_fixture_target();
    Tsim = 10;
    AM = mc_shared_tables(fx.row, 'M', pBL, Tsim);
    AU = mc_shared_tables(fx.row, 'U', pBL, Tsim);

    want = {'Ep', 'Ev', 'argmax_index_p', 'argmax_t_p', 'argmax_index_v', 'argmax_t_v', ...
            'n_samples', 'tol_p', 'tol_v', 'pass_p', 'pass_v', 'pass', 'tolerance_status', 'scope'};
    ch{end+1} = mc_vt_check('matched pair: every frozen V2c field returned, tolerances 1e-6', ...
        all(isfield(AM.v2c, want)) && AM.v2c.tol_p == 1e-6 && AM.v2c.tol_v == 1e-6);
    ch{end+1} = mc_vt_check('matched pair passes V2c -> TABLES_OK', ...
        AM.v2c.pass && strcmp(AM.status, 'TABLES_OK'), ...
        sprintf('Ep %.3g m, Ev %.3g m/s', AM.v2c.Ep, AM.v2c.Ev));
    ch{end+1} = mc_vt_check('mismatched pair: V2c returned without throwing', ...
        all(isfield(AU.v2c, want)), sprintf('pass %d, Ep %.3g m, Ev %.3g m/s', ...
        AU.v2c.pass, AU.v2c.Ep, AU.v2c.Ev));
    ch{end+1} = mc_vt_check('Condition U never gates on V2c', strcmp(AU.status, 'TABLES_OK'), AU.status);

    EpInf = max(max(abs(AM.tabs.p_cp_preview - AM.tabs.p_cp_truth), [], 1));
    ch{end+1} = mc_vt_check('V2c Ep is the infinity norm (independent recomputation, bitwise)', ...
        isequal(typecast(EpInf, 'uint64'), typecast(AM.v2c.Ep, 'uint64')), ...
        sprintf('Ep_inf %.6g vs Euclidean max_e_p_cp %.6g', EpInf, AM.diag.max_e_p_cp));

    v2cFail = AU.v2c;
    if v2cFail.pass
        v2cFail.pass = false;                      % synthetic failing audit
    end
    ch{end+1} = mc_vt_check('gate: Condition M with a failing V2c -> M_CONSISTENCY_FAILURE', ...
        strcmp(mc_condition_gate('M', 'RETURNED', v2cFail), 'M_CONSISTENCY_FAILURE'));
    ch{end+1} = mc_vt_check('gate: Condition U with the same failing V2c -> TABLES_OK', ...
        strcmp(mc_condition_gate('U', 'RETURNED', v2cFail), 'TABLES_OK'));

    c = mc_constants();
    allNE = true;
    for mi = 1:numel(c.design.methods)
        Ro = mc_run_outputs(c.design.methods{mi}, 'M', 'M_CONSISTENCY_FAILURE', [], [], pBL);
        mk = cellfun(@(n) Ro.metrics.(n).marker, fieldnames(Ro.metrics), 'UniformOutput', false);
        allNE = allNE && all(strcmp(mk, 'NOT_EXECUTED')) ...
            && strcmp(Ro.flags.geometric_proximity_achieved.marker, 'NOT_EXECUTED') ...
            && isempty(Ro.flags.geometric_proximity_achieved.value) ...
            && isequal(Ro.flags.m_consistency_failure.value, true);
    end
    ch{end+1} = mc_vt_check('M_CONSISTENCY_FAILURE: every metric and outcome NOT_EXECUTED, no value stored', allNE);
    R.checks = [ch{:}];
end

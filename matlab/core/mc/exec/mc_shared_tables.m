function A = mc_shared_tables(row, condition, pBL, Tsim)
% MC_SHARED_TABLES  Level A of one (trial, condition): the ONE shared table build.
%   A = mc_shared_tables(row, condition, pBL, Tsim) implements the shared block
%   of protocol Sec. 5:
%
%       truthIC_i  = struct('q', q0_i, 'w', w0_i, 'I', I_true_i);
%       prevIC_ic  = struct('q', q0_i, 'w', w0_i, 'I', I_prev);
%       tabs_ic    = baseline_capture_tables(pBL, truthIC_i, prevIC_ic, Tsim);
%       v2c_ic     = baseline_preview_truth_audit(tabs_ic, 1e-6, 1e-6);
%
%   with I_prev = I_nom (U) or I_true_i (M). The table build - the only
%   integration in this block - runs inside the R18 guard (C1, Sec. 12.3).
%
%   A.status
%     'TABLES_OK'                         all three methods may run
%     'TARGET_MODEL_INTEGRATION_FAILURE'  A1: promoted ode45 exception in the
%                                         build; no method of (i, c) runs
%     'M_CONSISTENCY_FAILURE'             A2: Condition M and ~v2c.pass; no
%                                         method of (i, M) runs
%     'HARNESS_ERROR'                     A0: any other exception in the build;
%                                         the campaign STOPS
%   Any exception thrown by this function outside the guarded build (V2c,
%   diagnostics, identity assertions) is also A0 and is left to propagate.
%
%   A.tabs is the in-memory table set consumed by all three methods; records
%   store only its SHA-256 identities (A.hash) and the Sec. 6.2 diagnostics.

    c = mc_constants();
    assert(any(strcmp(condition, c.design.conditions)), 'mc:tables:condition', ...
        'Unknown condition ''%s''.', condition);

    truthIC = struct('q', row.q0, 'w', row.w0, 'I', row.I_true);
    switch condition
        case 'U', I_prev = c.design.I_nom;
        case 'M', I_prev = row.I_true;
    end
    prevIC = struct('q', row.q0, 'w', row.w0, 'I', I_prev);

    A = struct('condition', condition, 'trial_id', row.trial_id, 'Tsim', Tsim, ...
               'truthIC', truthIC, 'prevIC', prevIC, 'status', '', ...
               'guard_status', '', 'exception_info', mc_exception_summary([]), ...
               'tabs', [], 'v2c', [], 'diag', [], 'hash', [], 'wall_s', NaN);

    t0 = tic;
    r = mc_r18_invoke(@() baseline_capture_tables(pBL, truthIC, prevIC, Tsim));
    A.wall_s = toc(t0);
    A.guard_status   = r.status;
    A.exception_info = r.exception_info;
    if ~strcmp(r.status, 'RETURNED')
        A.status = mc_condition_gate(condition, r.status, []);   % A0 or A1
        return
    end
    tabs = r.value;

    % The build must carry exactly the requested identities (Sec. 5 PRE-RUN).
    id = tabs.identity;
    assert(isequal(id.truth.q, truthIC.q(:)) && isequal(id.truth.w, truthIC.w(:)) ...
        && isequal(id.truth.I, truthIC.I) && isequal(id.preview.q, prevIC.q(:)) ...
        && isequal(id.preview.w, prevIC.w(:)) && isequal(id.preview.I, prevIC.I), ...
        'mc:tables:identity', 'The shared table set carries the wrong target identities.');
    assert(tabs.K == round(Tsim / pBL.ctrl.Ts) && abs(tabs.Tsim - Tsim) == 0, ...
        'mc:tables:horizon', 'The shared table set was built for another horizon.');

    v2c = baseline_preview_truth_audit(tabs, c.v2c.tol_p, c.v2c.tol_v);

    % Sec. 6.2 descriptive preview diagnostics, from the very tables consumed.
    e = sqrt(sum((tabs.p_cp_truth - tabs.p_cp_preview).^2, 1));
    k = find(e > pBL.bl.s_cap, 1, 'first');
    if isempty(k), tEx = Inf; else, tEx = tabs.t(k); end
    A.diag = struct('max_e_p_cp', max(e), 'rms_e_p_cp', sqrt(mean(e.^2)), ...
                    't_exceed', tEx, 'n_samples', numel(e), 's_cap', pBL.bl.s_cap, ...
                    'Ep', v2c.Ep, 'Ev', v2c.Ev, ...
                    'argmax_index_p', v2c.argmax_index_p, 'argmax_t_p', v2c.argmax_t_p, ...
                    'argmax_index_v', v2c.argmax_index_v, 'argmax_t_v', v2c.argmax_t_v, ...
                    'v2c_pass', v2c.pass, 'v2c_pass_p', v2c.pass_p, 'v2c_pass_v', v2c.pass_v);

    % Bitwise identities of what the three methods consume and of the truth
    % that both conditions of a trial must share (Sec. 6.1).
    A.hash = struct( ...
        'qT',          mc_array_sha256(tabs.qT), ...
        'wT',          mc_array_sha256(tabs.wT), ...
        'p_cp_truth',  mc_array_sha256(tabs.p_cp_truth), ...
        'v_cp_truth',  mc_array_sha256(tabs.v_cp_truth), ...
        'n_cp_truth',  mc_array_sha256(tabs.n_cp_truth), ...
        'tbl_t',       mc_array_sha256(tabs.tbl_preview.t), ...
        'tbl_pL',      mc_array_sha256(tabs.tbl_preview.pL), ...
        'tbl_vL',      mc_array_sha256(tabs.tbl_preview.vL), ...
        'tbl_nL',      mc_array_sha256(tabs.tbl_preview.nL));

    A.v2c    = v2c;
    A.tabs   = tabs;
    A.status = mc_condition_gate(condition, 'RETURNED', v2c);   % TABLES_OK or A2
end

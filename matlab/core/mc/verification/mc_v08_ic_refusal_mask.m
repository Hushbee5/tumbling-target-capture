function R = mc_v08_ic_refusal_mask(~)
% MC_V08_IC_REFUSAL_MASK  IC-refusal and mask fixture (Sec. 7.2.1, 10.2). NON-SCIENTIFIC.
%   (a) a short simulate_task4 call with a SYNTHETIC INADMISSIBLE initial
%       condition - neither a trial row nor the evaluation IC - through the
%       real MC invocation path returns at the entry gate before any plant
%       integration and is classified IC_REFUSED (B3), NOT NUMERICAL_FAILURE,
%       although its output carries NaN-valued not-applicable fields (which a
%       blanket isfinite WOULD have flagged);
%   (b) every structurally not-applicable class of the mask does NOT trigger
%       B4 - including one real short run whose horizon is shorter than one
%       estimator window (estimator.resid empty);
%   (c) negative controls: a non-finite value injected into EVERY required-finite
%       field DOES trigger B4, as do +-Inf in a FINITE_OR_NAN field and NaN on an
%       enforced capture step;
%   (d) contract STRUCTURE violations are an unexpected state (HARNESS_ERROR);
%   (e) the B3 -> B4 -> B5 -> B6 -> B7 precedence.

    R.name = 'V08 IC refusal and finite-mask contract';
    ch = {};
    c = mc_constants();
    pBL = baseline_config();
    fx = mc_vt_fixture_target();
    Ts = c.design.Ts;

    % ---- (a) IC refusal ----------------------------------------------------------
    Tbad = 2;
    A = mc_shared_tables(fx.row_bad, 'U', pBL, Tbad);
    P = mc_invoke_proposed(fx.row_bad, A, Tbad);
    out = P.out;
    [st, info] = mc_classify_proposed(P.guard.status, out, round(Tbad / Ts));
    ch{end+1} = mc_vt_check('(a) synthetic inadmissible IC -> IC_REFUSED by rule B3', ...
        strcmp(st, 'IC_REFUSED') && strcmp(info.rule, 'B3'), [st ' ' info.rule]);
    ch{end+1} = mc_vt_check('(a) refused at the entry gate: no D9, no control step, no plant step', ...
        strcmp(out.eligibility, 'INELIGIBLE_IC') && isequal(out.d9_evaluated, false) ...
        && strcmp(out.event, 'NOT_EVALUATED') && isequal(out.aborted, true) ...
        && out.K_applied == 0 && isempty(out.inter.t) && size(out.Usafe, 2) == 0);
    nf = nonfinite_leaves(rmfield(out, 'config'), 'out');
    ch{end+1} = mc_vt_check('(a) a blanket isfinite WOULD flag the refusal record', ...
        all(ismember({'out.d_safe', 'out.v_rel_cp', 'out.estimator.resid'}, nf)), strjoin(nf, ', '));
    Ro = mc_run_outputs('proposed', 'U', 'IC_REFUSED', struct('out', out, 'act_thresh', P.act_thresh), ...
                        A.tabs, pBL);
    ch{end+1} = mc_vt_check('(a) IC_REFUSED is NOT_EXECUTED; formal_domain_ic_refusal TRUE; D9 NOT_EVALUATED', ...
        isequal(Ro.flags.formal_domain_ic_refusal.value, true) ...
        && strcmp(Ro.metrics.t_kstar.marker, 'NOT_EXECUTED') ...
        && strcmp(Ro.flags.geometric_proximity_achieved.marker, 'NOT_EXECUTED') ...
        && strcmp(Ro.flags.hocbf_qp_failure.marker, 'NOT_EXECUTED') ...
        && strcmp(Ro.d9_outcome, 'NOT_EVALUATED'));

    % ---- (b) not-applicable classes -----------------------------------------------
    Tok = 5;  K = round(Tok / Ts);
    A2 = mc_shared_tables(fx.row, 'U', pBL, Tok);
    P2 = mc_invoke_proposed(fx.row, A2, Tok);
    o0 = P2.out;
    [st, info] = mc_classify_proposed('RETURNED', o0, K);
    ch{end+1} = mc_vt_check('(b) the real 5 s ELIGIBLE output is COMPLETE with no mask violation', ...
        strcmp(st, 'COMPLETE') && isempty(info.mask.nonfinite) && isempty(info.mask.structure), ...
        [st ' ' strjoin([info.mask.nonfinite, info.mask.structure], '; ')]);

    o = o0;  j = (K-4):K;
    o.cap_enforced(j) = false;  o.feas_cap(j) = NaN;  o.row_active_cap(j) = false;
    ch{end+1} = expect(o, K, 'COMPLETE', '(b) feas_cap NaN where cap_enforced is false: no B4');
    o = o0;  o.feas_joint(3) = NaN;
    ch{end+1} = expect(o, K, 'COMPLETE', '(b) feas_joint NaN (LP margin not available): no B4');
    o = o0;  o.estimator.records = 0;  o.estimator.resid = [];
    ch{end+1} = expect(o, K, 'COMPLETE', '(b) estimator.resid empty with zero records: no B4');
    o = o0;  o.aborted = true;
    o.qp_failure = struct('occurred', true, 'k', 3, 't', 0.2, 'cap_active', true, 'status', -1, ...
        'exitflag', -2, 'feasible', false, 'feas_margin', [0.1 -0.2], 'joint_margin', NaN, ...
        'row_names', {{'body', 'cap'}});
    ch{end+1} = expect(o, K, 'QP_INFEASIBLE_ABORT', '(b) qp_failure.joint_margin NaN: no B4 (B5)');
    ch{end+1} = mc_vt_check('(b) event NO_EVENT with event_log [] and handoff []', ...
        strcmp(o0.event, 'NO_EVENT') && isempty(o0.event_log) && isempty(o0.handoff), o0.event);

    Tshort = 0.5;
    A3 = mc_shared_tables(fx.row, 'U', pBL, Tshort);
    P3 = mc_invoke_proposed(fx.row, A3, Tshort);
    [st, info] = mc_classify_proposed(P3.guard.status, P3.out, round(Tshort / Ts));
    ch{end+1} = mc_vt_check('(b) real run shorter than one Tw window: resid empty, records 0, COMPLETE', ...
        strcmp(st, 'COMPLETE') && P3.out.estimator.records == 0 && isempty(P3.out.estimator.resid), ...
        sprintf('%s; records %d; %s', st, P3.out.estimator.records, strjoin(info.mask.nonfinite, '; ')));

    % ---- (c) negative controls on EVERY required-finite field ----------------------
    C = mc_mask_contract();
    bad = {};  nTested = 0;
    for i = 1:numel(C)
        if ~strcmp(C(i).rule, 'FINITE')
            continue
        end
        v = get_path(o0, C(i).path);
        if isempty(v)
            continue
        end
        v(1) = NaN;
        o = mc_vt_set_path(o0, C(i).path, v);
        st = mc_classify_proposed('RETURNED', o, K);
        if any(strcmp(C(i).path, {'K_applied', 'K'}))
            want = 'HARNESS_ERROR';          % bookkeeping counters: a structure violation
        else
            want = 'NUMERICAL_FAILURE';
        end
        nTested = nTested + 1;
        if ~strcmp(st, want)
            bad{end+1} = sprintf('%s -> %s', C(i).path, st); %#ok<AGROW>
        end
    end
    ch{end+1} = mc_vt_check('(c) NaN in EVERY required-finite field triggers B4 (counters: HARNESS_ERROR)', ...
        isempty(bad), sprintf('%d fields injected; %s', nTested, strjoin(bad, '; ')));
    minimum = {'t', 'X', 'Usafe', 'h_body', 'rho', 'qT', 'wT', 'inter.t', 'inter.r', 'inter.h_body'};
    okMin = true;
    for i = 1:numel(minimum)
        v = get_path(o0, minimum{i});  v(end) = Inf;
        okMin = okMin && strcmp(mc_classify_proposed('RETURNED', mc_vt_set_path(o0, minimum{i}, v), K), ...
                                'NUMERICAL_FAILURE');
    end
    ch{end+1} = mc_vt_check('(c) +Inf in each protocol-minimum field triggers B4', okMin);
    o = o0;  o.feas_joint(2) = Inf;
    ch{end+1} = expect(o, K, 'NUMERICAL_FAILURE', '(c) feas_joint +Inf triggers B4');
    o = o0;  kEn = find(o0.cap_enforced, 1);  o.feas_cap(kEn) = NaN;
    ch{end+1} = expect(o, K, 'NUMERICAL_FAILURE', '(c) feas_cap NaN on an ENFORCED step triggers B4');
    o = o0;  o.estimator.resid = NaN;
    ch{end+1} = expect(o, K, 'NUMERICAL_FAILURE', '(c) estimator.resid NaN with records >= 1 triggers B4');
    o = o0;  o.ic.h_body = NaN;
    ch{end+1} = expect(o, K, 'NUMERICAL_FAILURE', '(c) ic.h_body NaN triggers B4');

    % ---- (d) structure violations ------------------------------------------------------
    ch{end+1} = expect(rmfield(o0, 'rho'), K, 'HARNESS_ERROR', '(d) a missing field is HARNESS_ERROR');
    o = o0;  o.extra_field = 1;
    ch{end+1} = expect(o, K, 'HARNESS_ERROR', '(d) an unclassified extra field is HARNESS_ERROR');
    o = o0;  o.X = o.X(:, 1:end-1);
    ch{end+1} = expect(o, K, 'HARNESS_ERROR', '(d) a mis-sized history is HARNESS_ERROR');

    % ---- (e) precedence ------------------------------------------------------------------
    o = o0;  o.X(1, 1) = NaN;  o.aborted = true;
    o.qp_failure = struct('occurred', true, 'k', 3, 't', 0.2, 'cap_active', true, 'status', -1, ...
        'exitflag', -2, 'feasible', false, 'feas_margin', [0.1 0.2], 'joint_margin', 0.01, ...
        'row_names', {{'body', 'cap'}});
    ch{end+1} = expect(o, K, 'NUMERICAL_FAILURE', '(e) B4 precedes B5');
    o = o0;  o.aborted = true;  o.event = 'GUARD_BREACH';  o.guard_validation = 'FAILED';
    o.event_log = struct('t', 1.0, 'k', 11, 'event', 'GUARD_BREACH', 'rho', 0.1, 'rho_dot', -0.01, ...
        'v_rel_cp', 0.02, 'nu', 1.0, 'h_body', 80, 'psi1_body', 3, 'h_cap', -0.001, ...
        'psi1_cap', 0.5, 'alpha', 1e-3, 'eps_rho', 1e-4, 'theta_hat', [0; 0; 0], 'eta', 0.1, ...
        's_cap', 0.106226);
    ch{end+1} = expect(o, K, 'GUARD_BREACH_ABORT', '(e) in-loop GUARD_BREACH -> B6');
    ch{end+1} = expect(o0, K + 1, 'HARNESS_ERROR', '(e) ~aborted with K_applied ~= K_expected -> unexpected');
    o = o0;  o.eligibility = 'SOMETHING_ELSE';
    ch{end+1} = expect(o, K, 'HARNESS_ERROR', '(e) an unknown eligibility -> unexpected');
    [ok, got] = mc_vt_throws(@() mc_mask_check(out), 'mc:mask:not_eligible');
    ch{end+1} = mc_vt_check('(e) the B4 contract refuses to evaluate an IC-refusal record', ok, got);
    R.checks = [ch{:}];
end

% =====================================================================
function c = expect(o, K, want, name)
    [st, info] = mc_classify_proposed('RETURNED', o, K);
    c = mc_vt_check(name, strcmp(st, want), sprintf('%s (%s)', st, info.reason));
end

% =====================================================================
function v = get_path(s, path)
    parts = strsplit(path, '.');
    v = s;
    for k = 1:numel(parts)
        v = v.(parts{k});
    end
end

% =====================================================================
function L = nonfinite_leaves(s, prefix)
% Every numeric leaf holding a non-finite value: what a blanket scan would see.
    L = {};
    if isstruct(s)
        f = fieldnames(s);
        for k = 1:numel(f)
            for i = 1:numel(s)
                L = [L, nonfinite_leaves(s(i).(f{k}), [prefix '.' f{k}])]; %#ok<AGROW>
            end
        end
    elseif iscell(s)
        for i = 1:numel(s)
            L = [L, nonfinite_leaves(s{i}, prefix)]; %#ok<AGROW>
        end
    elseif isnumeric(s) && ~isempty(s) && ~all(isfinite(s(:)))
        L = {prefix};
    end
end

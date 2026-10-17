function R = mc_run_outputs(method, condition, status, obj, tabs, pBL)
% MC_RUN_OUTPUTS  Metrics, flags and diagnostics of one run, with availability.
%   R = mc_run_outputs(method, condition, status, obj, tabs, pBL)
%
%   method     'proposed' | 'nominal_mpc' | 'apf'
%   status     the final execution status (Level A or Level B, Sec. 7.2);
%              HARNESS_ERROR is never recorded and is refused here
%   obj        proposed: struct('out', out, 'act_thresh', a); baselines: the run
%              ([] whenever nothing was returned)
%   tabs       the shared table set (needed by the proposed adapter)
%
%   Every reported quantity is a struct('marker', M, 'value', V, 'reason', R)
%   with M one of the protocol Sec. 7.1 markers
%       AVAILABLE | NOT_EXECUTED | UNKNOWN | NOT_APPLICABLE
%   and V stored ONLY when M is AVAILABLE. A missing quantity is never zero and
%   never false.
%
%   BASE AVAILABILITY BY STATUS (Sec. 7.3 table, 7.4, 7.5):
%     COMPLETE, QP_INFEASIBLE_ABORT, GUARD_BREACH_ABORT     AVAILABLE (aborts: prefix)
%     IC_REFUSED, TARGET_MODEL_INTEGRATION_FAILURE,
%     M_CONSISTENCY_FAILURE                                NOT_EXECUTED
%     INTEGRATOR_EXCEPTION, NUMERICAL_FAILURE               UNKNOWN
%   Refinements:
%     DeltaV_full, rho_truth_final   NOT_APPLICABLE on aborts (complete horizon only)
%     t_kstar, DeltaV_to_proximity, rho_dot_truth_kstar
%                                    NOT_APPLICABLE when no proximity milestone was
%                                    achieved (Sec. 8.3 conditions them on
%                                    geometric proximity AVAILABLE and TRUE); the raw
%                                    frozen baseline_metrics values are kept under
%                                    R.raw for audit.
%     rho_dot_truth_kstar            NOT_APPLICABLE / UNDEFINED_AT_ZERO_SEPARATION
%                                    ONLY in the frozen zero-separation branch
%                                    (baseline_metrics.m:119-128, nd == 0); any other
%                                    nonfinite payload is an integrity failure
%                                    ('mc:outputs:metric_payload' -> HARNESS_ERROR).
%
%   Execution flags follow Sec. 7.3 literally, including
%     formal_domain_ic_refusal  proposed: TRUE on IC_REFUSED; FALSE on B2 and
%                               B4-B7 (the gate admitted the IC); NOT_EXECUTED on
%                               Level-A statuses; baselines NOT_APPLICABLE.
%   hocbf_qp_failure and d9_guard_breach read the returned output and are
%   therefore UNKNOWN on INTEGRATOR_EXCEPTION and NUMERICAL_FAILURE (Sec. 7.4).

    assert(~strcmp(status, 'HARNESS_ERROR'), 'mc:outputs:harness', ...
        'HARNESS_ERROR is never recorded; it stops the campaign.');
    isProp = strcmp(method, 'proposed');
    base   = base_marker(status);
    isAbort = any(strcmp(status, {'QP_INFEASIBLE_ABORT', 'GUARD_BREACH_ABORT'}));

    out = [];  run = [];
    if isProp && ~isempty(obj), out = obj.out; end
    if ~isProp, run = obj; end

    % ---- method-neutral metrics (Sec. 6.1) ---------------------------------
    m = [];
    tEnd = [];
    kApplied = NaN;
    if strcmp(base, 'AVAILABLE')
        if isProp
            mc_proposed_integrity(out, tabs);
            m = mc_proposed_adapter(out, tabs, pBL);
            tEnd = out.t(end);
            kApplied = out.K_applied;
        else
            m = baseline_metrics(run, pBL);
            tEnd = run.t(end);
            kApplied = run.K;
        end
    end
    R.status = status;
    R.base_marker = base;
    R.prefix = isAbort;
    R.metrics = metric_block(m, base, status, isAbort, pBL, tEnd, kApplied);
    R.raw = raw_block(m);

    % ---- flags (Sec. 7.3) ---------------------------------------------------
    R.flags = flag_block(method, condition, status, base, out, run, m);

    % ---- D9 outcome category (Sec. 8.2) ---------------------------------------
    if isProp
        R.d9_outcome = d9_category(status, out);
    else
        R.d9_outcome = 'NOT_APPLICABLE';
    end

    % ---- method-specific diagnostics (Sec. 6.3, 6.4) --------------------------
    if isProp
        R.diagnostics = proposed_diag(status, base, out, obj);
    else
        R.diagnostics = baseline_diag(method, status, run, m);
    end
end

% =====================================================================
function b = base_marker(status)
    switch status
        case {'COMPLETE', 'QP_INFEASIBLE_ABORT', 'GUARD_BREACH_ABORT'}
            b = 'AVAILABLE';
        case {'IC_REFUSED', 'TARGET_MODEL_INTEGRATION_FAILURE', 'M_CONSISTENCY_FAILURE'}
            b = 'NOT_EXECUTED';
        case {'INTEGRATOR_EXCEPTION', 'NUMERICAL_FAILURE'}
            b = 'UNKNOWN';
        otherwise
            error('mc:outputs:status', 'Unknown execution status ''%s''.', status);
    end
end

% =====================================================================
function e = q(marker, value, reason)
    if nargin < 3, reason = ''; end
    if ~strcmp(marker, 'AVAILABLE'), value = []; end
    e = struct('marker', marker, 'value', value, 'reason', reason);
end

% =====================================================================
function M = metric_block(m, base, status, isAbort, pBL, tEnd, kApplied)
% Every continuous metric of MC_METRIC_REGISTRY, plus three bookkeeping
% diagnostics, each with its availability marker. An AVAILABLE payload is ALWAYS
% a real numeric scalar, finite - except t_viol, whose +Inf is the frozen
% "no violation observed" value; NaN is never AVAILABLE ('mc:outputs:metric_payload').
    reg = mc_metric_registry();
    extras = {'n_inspected', 'min_clearance_control_grid', 'executed_horizon_s'};
    if ~strcmp(base, 'AVAILABLE')
        for k = 1:numel(reg)
            M.(reg(k).name) = q(base, [], status);
        end
        for k = 1:numel(extras)
            M.(extras{k}) = q(base, [], status);
        end
        return
    end
    assert(strcmp(status, 'COMPLETE') || isAbort, 'mc:outputs:status', ...
        'Unexpected status with available metrics.');
    prox = logical(m.proximity_achieved);
    rs = pBL.geom.r_safe;
    val = struct('t_kstar', m.t_kstar, 'DeltaV_to_proximity', m.DeltaV_to_proximity, ...
        'rho_dot_truth_kstar', m.rho_dot_truth_kstar, 'DeltaV_full', m.DeltaV_full, ...
        'rho_truth_final', m.rho_truth_final, 'min_h_body', m.min_h_body, ...
        'min_clearance_union', sqrt(m.min_h_body + rs^2) - rs, 't_viol', m.t_viol, ...
        'utilisation_max_ratio', m.utilisation.max_ratio, ...
        'utilisation_mean_ratio', m.utilisation.mean_ratio, ...
        'utilisation_fraction', m.utilisation.fraction);
    for k = 1:numel(reg)
        nm = reg(k).name;
        switch reg(k).domain
            case 'PROXIMITY_TRUE'
                if prox, e = q('AVAILABLE', val.(nm));
                else,    e = q('NOT_APPLICABLE', [], 'NO_PROXIMITY_MILESTONE');
                end
            case 'COMPLETE_ONLY'
                if strcmp(status, 'COMPLETE'), e = q('AVAILABLE', val.(nm));
                else,                          e = q('NOT_APPLICABLE', [], 'NOT_COMPLETE_HORIZON');
                end
            case 'AVAILABLE'
                e = q('AVAILABLE', val.(nm));
            case 'APPLIED_STEPS'
                if kApplied > 0, e = q('AVAILABLE', val.(nm));
                else,            e = q('NOT_APPLICABLE', [], 'NO_APPLIED_STEP');
                end
            otherwise
                error('mc:outputs:registry', 'Unknown metric domain %s.', reg(k).domain);
        end
        if strcmp(nm, 'rho_dot_truth_kstar') && strcmp(e.marker, 'AVAILABLE') && isnan(e.value) ...
                && strcmp(m.rho_dot_truth_kstar_note, 'undefined at zero separation')
            % ONLY the frozen zero-separation branch of baseline_metrics (lines
            % 119-128: nd == 0 at kstar, note 'undefined at zero separation') is
            % NOT_APPLICABLE. Any other nonfinite value is an integrity failure
            % (check_payload below). The raw value and note stay in R.raw.
            e = q('NOT_APPLICABLE', [], 'UNDEFINED_AT_ZERO_SEPARATION');
        end
        M.(nm) = check_payload(nm, e, reg(k).inf_allowed);
    end
    M.n_inspected                = check_payload('n_inspected', q('AVAILABLE', m.n_inspected), false);
    M.min_clearance_control_grid = check_payload('min_clearance_control_grid', ...
                                                 q('AVAILABLE', m.min_clearance), false);
    M.executed_horizon_s         = check_payload('executed_horizon_s', q('AVAILABLE', tEnd), false);
end

% =====================================================================
function e = check_payload(name, e, infAllowed)
    if ~strcmp(e.marker, 'AVAILABLE')
        return
    end
    v = e.value;
    ok = isnumeric(v) && isreal(v) && isscalar(v) && ~isnan(v) && (isfinite(v) || (infAllowed && v == Inf));
    assert(ok, 'mc:outputs:metric_payload', ...
        'INTEGRITY: AVAILABLE metric %s has no finite scalar payload.', name);
end

% =====================================================================
function r = raw_block(m)
    r = struct();
    if isempty(m), return, end
    r.kstar = m.kstar;  r.t_kstar = m.t_kstar;  r.p_safe = m.p_safe;
    r.K_safe_count = m.K_safe_count;  r.I_sel_case = m.I_sel_case;
    r.I_sel_count = m.I_sel_count;  r.control_effort = m.control_effort;
    r.DeltaV_Isel = m.DeltaV_Isel;  r.min_clearance_to_kstar = m.min_clearance_to_kstar;
    r.clip_fraction_full = m.clip_fraction_full;  r.clip_fraction_Isel = m.clip_fraction_Isel;
    r.rho_dot_truth_kstar = m.rho_dot_truth_kstar;              % raw frozen value (NaN kept)
    r.rho_dot_truth_kstar_note = m.rho_dot_truth_kstar_note;    % and its frozen provenance note
end

% =====================================================================
function F = flag_block(method, condition, status, base, out, run, m)
    isProp = strcmp(method, 'proposed');
    levelA = any(strcmp(status, {'TARGET_MODEL_INTEGRATION_FAILURE', 'M_CONSISTENCY_FAILURE'}));
    valid  = strcmp(base, 'AVAILABLE');

    F.full_horizon_complete = q('AVAILABLE', strcmp(status, 'COMPLETE'));
    F.observable_numerical_failure = q('AVAILABLE', ...
        any(strcmp(status, {'INTEGRATOR_EXCEPTION', 'NUMERICAL_FAILURE'})));
    F.target_model_integration_failure = q('AVAILABLE', ...
        strcmp(status, 'TARGET_MODEL_INTEGRATION_FAILURE'));
    if strcmp(condition, 'M')
        F.m_consistency_failure = q('AVAILABLE', strcmp(status, 'M_CONSISTENCY_FAILURE'));
    else
        F.m_consistency_failure = q('NOT_APPLICABLE', [], 'CONDITION_U');
    end

    if isProp
        if levelA
            F.formal_domain_ic_refusal = q('NOT_EXECUTED', [], status);
        else
            F.formal_domain_ic_refusal = q('AVAILABLE', strcmp(status, 'IC_REFUSED'));
        end
        if valid
            F.hocbf_qp_failure = q('AVAILABLE', logical(out.qp_failure.occurred));
            F.d9_guard_breach  = q('AVAILABLE', strcmp(out.event, 'GUARD_BREACH'));
        elseif strcmp(status, 'IC_REFUSED') || levelA
            F.hocbf_qp_failure = q('NOT_EXECUTED', [], status);
            F.d9_guard_breach  = q('NOT_EXECUTED', [], status);
        else
            F.hocbf_qp_failure = q('UNKNOWN', [], status);
            F.d9_guard_breach  = q('UNKNOWN', [], status);
        end
        F.observed_upper_mpc_solver_failure = q('NOT_APPLICABLE', [], 'NOT_OBSERVABLE_R5');
    else
        F.formal_domain_ic_refusal = q('NOT_APPLICABLE', [], 'ARCHITECTURE');
        F.hocbf_qp_failure         = q('NOT_APPLICABLE', [], 'ARCHITECTURE');
        F.d9_guard_breach          = q('NOT_APPLICABLE', [], 'ARCHITECTURE');
        if strcmp(method, 'nominal_mpc')
            if levelA
                F.observed_upper_mpc_solver_failure = q('NOT_EXECUTED', [], status);
            else
                % over the EXECUTED steps, also for a partial numerical failure
                F.observed_upper_mpc_solver_failure = q('AVAILABLE', ...
                    run.mpc_solver_status.n_failed > 0);
                F.observed_upper_mpc_solver_failure.count = run.mpc_solver_status.n_failed;
                F.observed_upper_mpc_solver_failure.executed_steps = run.K;
            end
        else
            F.observed_upper_mpc_solver_failure = q('NOT_APPLICABLE', [], 'ARCHITECTURE');
        end
    end

    % ---- scientific outcome flags -------------------------------------------
    if valid
        F.geometric_proximity_achieved = q('AVAILABLE', logical(m.proximity_achieved));
        F.no_observed_body_violation   = q('AVAILABLE', logical(m.no_observed_body_violation));
    else
        F.geometric_proximity_achieved = q(base, [], status);
        F.no_observed_body_violation   = q(base, [], status);
    end
    if isProp
        if valid
            prox = logical(m.proximity_achieved);
            breach = strcmp(out.event, 'GUARD_BREACH');
            v = prox;
            if prox && breach
                k_breach = out.event_log.k - 1;       % zero-based detector sample
                v = ~(k_breach <= m.kstar);           % kstar is zero-based
            end
            F.proximity_without_guard_breach = q('AVAILABLE', v);
        else
            F.proximity_without_guard_breach = q(base, [], status);
        end
    else
        F.proximity_without_guard_breach = q('NOT_APPLICABLE', [], 'ARCHITECTURE');
    end

    % every AVAILABLE flag carries a logical scalar - never an empty or numeric payload
    fn = fieldnames(F);
    for k = 1:numel(fn)
        e = F.(fn{k});
        if strcmp(e.marker, 'AVAILABLE')
            assert(islogical(e.value) && isscalar(e.value), 'mc:outputs:flag_payload', ...
                'INTEGRITY: AVAILABLE flag %s has no logical scalar payload.', fn{k});
        end
    end
end

% =====================================================================
function c = d9_category(status, out)
    switch status
        case {'COMPLETE', 'QP_INFEASIBLE_ABORT', 'GUARD_BREACH_ABORT'}
            c = out.event;                          % NORMAL | GUARD_BREACH | NO_EVENT
        case 'IC_REFUSED'
            c = 'NOT_EVALUATED';
        case {'TARGET_MODEL_INTEGRATION_FAILURE', 'M_CONSISTENCY_FAILURE'}
            c = 'NOT_EXECUTED';
        otherwise
            c = 'UNKNOWN';
    end
end

% =====================================================================
function D = proposed_diag(status, base, out, obj)
    D = struct();
    if strcmp(status, 'IC_REFUSED')
        D.ic = out.ic;
        D.event = out.event;
        D.guard_validation = out.guard_validation;
        D.abort_reason = out.abort_reason;
        return
    end
    if ~strcmp(base, 'AVAILABLE')
        return                                     % UNKNOWN / NOT_EXECUTED: nothing read
    end
    ka = out.K_applied;
    en = logical(out.cap_enforced);
    D.event            = out.event;
    D.guard_validation = out.guard_validation;
    if strcmp(out.event, 'NORMAL')
        D.handoff_t = q('AVAILABLE', out.handoff.t);
    else
        D.handoff_t = q('NOT_APPLICABLE', [], 'NO_NORMAL_HANDOFF');
    end
    qf = out.qp_failure;
    D.qp_failure = struct('occurred', qf.occurred, 'k', qf.k, 't', qf.t, ...
                          'cap_active', qf.cap_active, 'exitflag', qf.exitflag);
    D.act_thresh = obj.act_thresh;
    if ka > 0
        D.intervention_fraction = q('AVAILABLE', mean(out.active));
        D.lambda_min_min   = q('AVAILABLE', min(out.lambda_min));
        D.lambda_min_final = q('AVAILABLE', out.lambda_min(end));
        D.min_psi2_body    = q('AVAILABLE', min(out.psi2_body));
    else
        D.intervention_fraction = q('NOT_APPLICABLE', [], 'NO_APPLIED_STEP');
        D.lambda_min_min   = q('NOT_APPLICABLE', [], 'NO_APPLIED_STEP');
        D.lambda_min_final = q('NOT_APPLICABLE', [], 'NO_APPLIED_STEP');
        D.min_psi2_body    = q('NOT_APPLICABLE', [], 'NO_APPLIED_STEP');
    end
    th  = out.theta_true(:);
    the = out.estimator.theta_hat_end(:);
    err = the - th;
    D.theta_true    = th;
    D.theta_hat_end = the;
    D.t_end         = out.estimator.t_end;
    D.abs_error     = abs(err);
    D.abs_error_norm = norm(err);
    D.normalised_error = norm(err) / norm(th);   % vector-normalised (Sec. 6.3)
    D.E_end  = out.estimator.E_end;
    D.nu_end = out.estimator.nu_end;
    D.min_psi1_body = min(out.psi1_body);
    % C1 (final-800 record Sec. 7): psi1_cap on the samples at which the capture
    % row was IN THE QP, i.e. cap_enforced over the applied steps.
    psi1c = out.psi1_cap(1:ka);
    D.c1_enforced_samples = sum(en);
    D.c1_negative_count   = sum(psi1c(en) < 0);
    if any(en)
        D.c1_min_psi1_cap = q('AVAILABLE', min(psi1c(en)));
    else
        D.c1_min_psi1_cap = q('NOT_APPLICABLE', [], 'NO_ENFORCED_SAMPLE');
    end
    % F-trigger conditions, exactly as the frozen classifier and scan define them.
    D.F1 = 'UNDEFINED for single-alpha runs';
    D.F2_guard_breach = strcmp(out.event, 'GUARD_BREACH');
    % F3: task4_classify.m:147-149 - BOTH sources
    D.F3_qp_infeasible_cap = any(out.qp_infeasible & out.cap_enforced) ...
        || (logical(qf.occurred) && isequal(qf.cap_active, true));
    % F4: task4_classify.m:150
    D.F4_sampled_h_body_neg = any(out.h_body(~isnan(out.h_body)) < 0);
    % F5a = branch (1) of the frozen F5 rule over the frozen ENFORCEMENT WINDOW,
    % f5_hcap_scan.m:133-138 (freeze record Sec. 8.6): every STATE sample from
    % the start up to and INCLUDING the NORMAL handoff sample, or the sample at
    % which the run terminated (in-loop breach or QP-abort sample, or the
    % terminal sample). It is not derived from K_applied. Branch (2) (F5b,
    % detector / post-hoc disagreement) is not computed here.
    nS = numel(out.t);
    if strcmp(out.event, 'NORMAL') && ~isempty(out.handoff)
        kEnd = min(out.handoff.k, nS);
    else
        kEnd = nS;
    end
    D.F5a_window_end_k = kEnd;
    D.F5a_sampled_h_cap_neg_window = any(out.h_cap(1:kEnd) < 0);
    D.ic = out.ic;
    D.K_applied = out.K_applied;  D.K_evaluated = out.K_evaluated;
    D.K_detector = out.K_detector;
    D.truncated = ~strcmp(status, 'COMPLETE');
end

% =====================================================================
function D = baseline_diag(method, status, run, m)
    D = struct();
    if isempty(run)
        return
    end
    D.K_executed = run.K;
    if strcmp(status, 'NUMERICAL_FAILURE')
        % diagnostic evidence only, never scientific metrics (Sec. 7.5)
        D.failure_reason   = run.failure_reason;
        D.failure_k        = run.failure_k;
        D.nonfinite_fields = run.nonfinite_fields;
    end
    switch method
        case 'apf'
            D.clip_per_axis_counts = sum(run.apf.clip_per_axis, 2).';
            D.angle_stats          = run.apf.angle_stats;
            D.excluded_angle_count = run.apf.excluded_angle_count;
            if ~isempty(m)
                D.clip_fraction_Isel = m.clip_fraction_Isel;
                D.clip_fraction_full = m.clip_fraction_full;
            end
        case 'nominal_mpc'
            ss = run.mpc_solver_status;
            flags = ss.exitflag;
            u = unique(flags(~isnan(flags)));
            D.exitflag_values = u;
            D.exitflag_counts = arrayfun(@(x) sum(flags == x), u);
            D.n_failed = ss.n_failed;
            st = ss.solve_time;
            if isempty(st)
                D.solve_time = struct('n', 0);
            else
                D.solve_time = struct('n', numel(st), 'min', min(st), 'median', median(st), ...
                    'mean', mean(st), 'max', max(st), 'total', sum(st), ...
                    'note', 'WALL-CLOCK; operational diagnostic only (Sec. 6.4)');
            end
    end
end

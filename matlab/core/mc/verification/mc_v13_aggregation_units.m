function R = mc_v13_aggregation_units(~)
% MC_V13_AGGREGATION_UNITS  Unit tests of the Sec. 8 statistics on SYNTHETIC records.
%   NON-SCIENTIFIC: no simulation, no RNG. Wilson intervals against the values
%   the protocol states before results (Sec. 9.1); Hyndman-Fan type-7
%   quantiles against hand-computed values; and a synthetic 100-trial record
%   set with a known status plan checks the status distribution, the
%   TRUE / FALSE / NOT_EXECUTED / UNKNOWN breakdown, the confirmed and evaluated
%   rates and their denominators, the D9 distribution, the continuous-metric
%   denominators, the paired comparison counts, the barrier, the duplicate
%   and pooling refusals, and the cross-condition 2x2. F10/F11: one metric
%   authority (MC_METRIC_REGISTRY) for the run outputs, the summaries, the
%   within-condition pairs and the U-versus-M pairs; exclusion counts WITH
%   reasons; a nonfinite AVAILABLE payload counted as an integrity anomaly,
%   never dropped silently; a NO_APPLIED_STEP run is NOT_APPLICABLE in the
%   utilisation summaries. R-F: t_viol = +Inf is an AVAILABLE value in the
%   Sec. 8.3 order statistics (extended-real type 7); finite / +Inf pairs have
%   defined differences; a +Inf / +Inf pair has none, and the median paired
%   difference is then reported UNRESOLVED, never imputed; rho_dot_truth_kstar
%   is NOT_APPLICABLE only in the frozen zero-separation branch, and any other
%   nonfinite payload is an integrity failure. All through
%   MC_AGGREGATE('NON_SCIENTIFIC', ...) and MC_RUN_OUTPUTS.

    R.name = 'V13 aggregation units (synthetic records)';
    ch = {};

    w0 = mc_wilson(0, 100);  w100 = mc_wilson(100, 100);  w50 = mc_wilson(50, 100);
    ch{end+1} = mc_vt_check('Wilson 0/100 upper bound 3.70 % and lower bound 0', ...
        round(100 * w0.hi, 2) == 3.70 && abs(w0.lo) < 1e-15, sprintf('%.6f %%', 100 * w0.hi));
    ch{end+1} = mc_vt_check('Wilson 100/100 lower bound 96.30 %', round(100 * w100.lo, 2) == 96.30, ...
        sprintf('%.6f %%', 100 * w100.lo));
    ch{end+1} = mc_vt_check('Wilson worst-case half-width 9.62 pp at n = 100', ...
        round(100 * w50.half_width, 2) == 9.62, sprintf('%.6f pp', 100 * w50.half_width));
    w200 = mc_wilson(100, 200);  z200 = mc_wilson(0, 200);  f200 = mc_wilson(200, 200);
    ch{end+1} = mc_vt_check('Wilson n = 200 reference row of Sec. 9.1 (6.86 pp, 1.88 %, 98.12 %)', ...
        round(100 * w200.half_width, 2) == 6.86 && round(100 * z200.hi, 2) == 1.88 ...
        && round(100 * f200.lo, 2) == 98.12);
    w00 = mc_wilson(0, 0);
    ch{end+1} = mc_vt_check('Wilson with n = 0 is undefined, never a zero rate', ...
        ~w00.defined && isnan(w00.p_hat));

    q1 = mc_quantile7(1:5, [0.05 0.25 0.5 0.75 1]);
    q2 = mc_quantile7([4 1 3 2], [0.25 0.5 0.75]);
    ch{end+1} = mc_vt_check('type-7 quantiles: 1..5 -> [1.2 2 3 4 5]; {4,1,3,2} -> [1.75 2.5 3.25]', ...
        max(abs(q1 - [1.2 2 3 4 5])) < 1e-15 && max(abs(q2 - [1.75 2.5 3.25])) < 1e-15);
    ch{end+1} = mc_vt_check('type-7 quantile of an empty set is NaN; of one value, that value', ...
        isnan(mc_quantile7([], 0.5)) && mc_quantile7(7, 0.3) == 7);
    [qe, ue] = mc_quantile7([1 3 5 Inf Inf], [0.05 0.25 0.5 0.75 1], 'extended');
    [qo, uo] = mc_quantile7([-Inf Inf], 0.5, 'extended');
    [qn, un] = mc_quantile7([-Inf -1 -1 0 Inf], 0.5, 'extended');
    ch{end+1} = mc_vt_check(['extended type 7: {1,3,5,+Inf,+Inf} -> [1.4 3 5 +Inf +Inf]; ' ...
        '{-Inf,+Inf} median UNDEFINED; {-Inf,-1,-1,0,+Inf} median -1'], ...
        max(abs(qe(1:3) - [1.4 3 5])) < 1e-12 && all(qe(4:5) == Inf) && ~any(ue) ...
        && isnan(qo) && uo && qn == -1 && ~un, mat2str(qe));
    [ok, got] = mc_vt_throws(@() mc_quantile7([1 Inf], 0.5), 'mc:quantile:nonfinite');
    ch{end+1} = mc_vt_check('the default (finite) mode still refuses an infinite value', ok, got);

    recsU = synth_set('U');
    G = agg_condition(recsU, 1:100);
    sp = G.status.proposed;
    ch{end+1} = mc_vt_check('status distribution per method matches the plan', ...
        sp.COMPLETE == 88 && sp.GUARD_BREACH_ABORT == 4 && sp.INTEGRATOR_EXCEPTION == 3 ...
        && sp.IC_REFUSED == 2 && sp.NUMERICAL_FAILURE == 3 && G.status.nominal_mpc.COMPLETE == 100 ...
        && G.status.apf.COMPLETE == 97 && G.status.apf.NUMERICAL_FAILURE == 3);
    s = G.outcome_flags.proposed.geometric_proximity_achieved;
    ch{end+1} = mc_vt_check('breakdown TRUE 84 + FALSE 8 + NOT_EXECUTED 2 + UNKNOWN 6 = 100', ...
        s.TRUE == 84 && s.FALSE == 8 && s.NOT_EXECUTED == 2 && s.UNKNOWN == 6 && s.breakdown_sum == 100);
    ch{end+1} = mc_vt_check('confirmed rate 84/100 and evaluated rate 84/92, with 8 excluded runs', ...
        s.confirmed.n == 100 && s.confirmed.x == 84 && s.evaluated.n == 92 && s.evaluated.x == 84 ...
        && numel(s.excluded) == 8);
    e = G.exec_flags.proposed.full_horizon_complete;
    ch{end+1} = mc_vt_check('execution flag: full_horizon_complete 88/100 with its Wilson interval', ...
        e.TRUE == 88 && e.rate.n == 100 && abs(e.pct - 88) < 1e-12);
    ch{end+1} = mc_vt_check('D9 distribution over 100 including NOT_EVALUATED and UNKNOWN', ...
        G.d9.NO_EVENT == 60 && G.d9.NORMAL == 28 && G.d9.GUARD_BREACH == 4 ...
        && G.d9.NOT_EVALUATED == 2 && G.d9.UNKNOWN == 6 && G.d9.NOT_EXECUTED == 0);
    ch{end+1} = mc_vt_check('continuous denominators: t_kstar over proximity TRUE, DeltaV_full over COMPLETE', ...
        G.continuous.proposed.t_kstar.n == 84 && G.continuous.proposed.DeltaV_full.n == 88 ...
        && G.continuous.proposed.min_h_body.n == 92 && G.continuous.proposed.min_h_body_COMPLETE.n == 88);
    p = G.paired.proposed_vs_apf.DeltaV_full;
    ch{end+1} = mc_vt_check('paired DeltaV_full proposed vs APF: n 88, ties 10, first<second 78', ...
        p.n == 88 && p.n_tie == 10 && p.n_first_lt_second == 78 && p.n_first_gt_second == 0);
    ch{end+1} = mc_vt_check('estimator errors reported separately for COMPLETE and prefix runs', ...
        G.estimator.COMPLETE.normalised_error.n == 88 && G.estimator.PREFIX.normalised_error.n == 4);
    ch{end+1} = mc_vt_check('preview diagnostics over the 100 (trial, condition) tables', ...
        G.preview.n_tables_available == 100);

    [ok, got] = mc_vt_throws(@() agg_condition(recsU(2:end), 1:100), 'mc:aggregate:barrier');
    ch{end+1} = mc_vt_check('barrier: one missing record -> no aggregate', ok, got);
    [ok, got] = mc_vt_throws(@() agg_condition([recsU, recsU(1)], 1:100), 'mc:aggregate:duplicate');
    ch{end+1} = mc_vt_check('a duplicate record is refused', ok, got);

    recsM = synth_set('M');
    X = mc_aggregate('NON_SCIENTIFIC', 'cross', recsU, recsM, 1:100);
    x = X.proximity_2x2.proposed;
    ch{end+1} = mc_vt_check('cross-condition 2x2 (proposed): 70 / 14 / 0 / 8, 8 excluded', ...
        x.US_MS == 70 && x.US_MF == 14 && x.UF_MS == 0 && x.UF_MF == 8 && numel(x.excluded) == 8);
    [ok, got] = mc_vt_throws(@() mc_aggregate('NON_SCIENTIFIC', 'cross', recsM, recsU, 1:100), ...
        'mc:cross:conditions');
    ch{end+1} = mc_vt_check('cross-condition inputs must be U then M', ok, got);

    % ---- F11: ONE metric authority for summaries, pairs and U-versus-M ------------
    RG = mc_metric_registry();
    reg = {RG.name};
    pBL = baseline_config();
    Ro = mc_run_outputs('apf', 'M', 'M_CONSISTENCY_FAILURE', [], [], pBL);
    ch{end+1} = mc_vt_check('MC_RUN_OUTPUTS emits exactly the registry metrics (+3 bookkeeping extras)', ...
        isempty(setxor(fieldnames(Ro.metrics), [reg, {'n_inspected', 'min_clearance_control_grid', ...
        'executed_horizon_s'}])), strjoin(fieldnames(Ro.metrics), ', '));
    methods = {'proposed', 'nominal_mpc', 'apf'};
    pairs = {'proposed_vs_nominal_mpc', 'proposed_vs_apf', 'nominal_mpc_vs_apf'};
    okC = true;  okP = true;  okX = true;
    for i = 1:numel(methods)
        okC = okC && all(isfield(G.continuous.(methods{i}), reg));
        okX = okX && isempty(setxor(fieldnames(X.paired_U_minus_M.(methods{i})), reg));
    end
    for i = 1:numel(pairs)
        okP = okP && isempty(setxor(fieldnames(G.paired.(pairs{i})), reg));
    end
    ch{end+1} = mc_vt_check('every registry metric is summarised for every method', okC);
    ch{end+1} = mc_vt_check('within-condition pairs cover exactly the registry metrics', okP);
    ch{end+1} = mc_vt_check('U-versus-M pairs cover exactly the registry metrics (utilisation_*, rho_dot_truth_kstar included)', ...
        okX && isfield(X.paired_U_minus_M.proposed, 'utilisation_max_ratio') ...
        && isfield(X.paired_U_minus_M.proposed, 'rho_dot_truth_kstar'));
    xr = X.paired_U_minus_M.proposed.rho_dot_truth_kstar;
    xu = X.paired_U_minus_M.proposed.utilisation_max_ratio;
    ch{end+1} = mc_vt_check('U-versus-M rho_dot_truth_kstar n 70 (30 excluded); utilisation n 92 (8 excluded)', ...
        xr.n == 70 && numel(xr.excluded) == 30 && xu.n == 92 && numel(xu.excluded) == 8, ...
        sprintf('rho_dot n %d excl %d; util n %d excl %d', xr.n, numel(xr.excluded), xu.n, numel(xu.excluded)));

    % ---- F11: exclusion counts AND reasons -------------------------------------------------
    ex = p.excluded;
    want = {'NOT_APPLICABLE/AVAILABLE', 4; 'NOT_EXECUTED/AVAILABLE', 2; 'UNKNOWN/AVAILABLE', 3; ...
            'UNKNOWN/UNKNOWN', 3};
    okE = isequal([ex.trial_id], 89:100) && numel(p.excluded_counts) == size(want, 1);
    for i = 1:size(want, 1)
        k = find(strcmp({p.excluded_counts.combination}, want{i, 1}), 1);
        okE = okE && ~isempty(k) && p.excluded_counts(k).count == want{i, 2};
    end
    okE = okE && strcmp(ex(1).first_reason, 'GUARD_BREACH_ABORT') && strcmp(ex(end).second_reason, 'NUMERICAL_FAILURE');
    ch{end+1} = mc_vt_check('paired exclusions carry trial ids, markers, reasons and combination counts', ...
        okE, strjoin(arrayfun(@(e) sprintf('%s=%d', e.combination, e.count), p.excluded_counts, ...
        'UniformOutput', false), ', '));
    tv = G.continuous.proposed.t_viol;
    ch{end+1} = mc_vt_check('t_viol +Inf (no violation observed) is an AVAILABLE value: in n and in the order statistics', ...
        tv.n == 92 && tv.n_posinf == 92 && tv.integrity_anomalies.n == 0 && tv.median == Inf ...
        && tv.min == Inf && tv.max == Inf);
    pt = G.paired.proposed_vs_apf.t_viol;
    ch{end+1} = mc_vt_check('all-(+Inf) t_viol pairs: n 92 and 92 ties counted; median difference UNRESOLVED, never imputed', ...
        pt.n == 92 && pt.n_tie == 92 && pt.n_difference_undefined == 92 && pt.n_difference_defined == 0 ...
        && isnan(pt.median_difference) && strcmp(pt.median_difference_status, 'UNRESOLVED_UNDEFINED_DIFFERENCE'));

    % ---- R-F: finite / +Inf and +Inf / +Inf t_viol, explicit denominators ----------------
    % proposed AVAILABLE on trials 1..92 (89..92 are prefix runs, t_viol +Inf), APF on 1..97.
    tvr = recsU;
    for id = 1:92
        tvr{find_rec(tvr, id, 'apf')}.outputs.metrics.t_viol.value = 200 + id;
        if id <= 88
            tvr{find_rec(tvr, id, 'proposed')}.outputs.metrics.t_viol.value = 100 + id;
        end
    end
    tvr{find_rec(tvr, 1, 'proposed')}.outputs.metrics.t_viol.value = Inf;   % +Inf / finite
    tvr{find_rec(tvr, 2, 'apf')}.outputs.metrics.t_viol.value = Inf;        % finite / +Inf
    tvr{find_rec(tvr, 3, 'proposed')}.outputs.metrics.t_viol.value = Inf;   % +Inf / +Inf
    tvr{find_rec(tvr, 3, 'apf')}.outputs.metrics.t_viol.value = Inf;
    Gt = agg_condition(tvr, 1:100);
    s1 = Gt.continuous.proposed.t_viol;
    ch{end+1} = mc_vt_check(['t_viol summary over ALL 92 AVAILABLE values (86 finite, 6 +Inf): median 148.5, ' ...
        'Q1 125.75, Q3 171.25, p05 107.55, min 102, max +Inf'], ...
        s1.n == 92 && s1.n_posinf == 6 && s1.n_finite == 86 && abs(s1.median - 148.5) < 1e-12 ...
        && abs(s1.q1 - 125.75) < 1e-12 && abs(s1.q3 - 171.25) < 1e-12 && abs(s1.p05 - 107.55) < 1e-12 ...
        && s1.min == 102 && s1.max == Inf, sprintf('median %.6g q1 %.6g q3 %.6g p05 %.6g', ...
        s1.median, s1.q1, s1.q3, s1.p05));
    p1 = Gt.paired.proposed_vs_apf.t_viol;
    ch{end+1} = mc_vt_check(['paired t_viol with one +Inf/+Inf pair: n 92 (lt 86, tie 1, gt 5), 91 defined ' ...
        'differences, 1 undefined (trial 3), median UNRESOLVED; 8 exclusions with reasons'], ...
        p1.n == 92 && p1.n_first_lt_second == 86 && p1.n_tie == 1 && p1.n_first_gt_second == 5 ...
        && p1.n_difference_defined == 91 && p1.n_difference_undefined == 1 ...
        && isequal(p1.difference_undefined_trial_ids, 3) && isnan(p1.median_difference) ...
        && strcmp(p1.median_difference_status, 'UNRESOLVED_UNDEFINED_DIFFERENCE') ...
        && isequal([p1.excluded.trial_id], 93:100) && ~isempty(p1.excluded(1).first_reason), ...
        sprintf('n %d lt %d tie %d gt %d def %d undef %d excl %d', p1.n, p1.n_first_lt_second, ...
        p1.n_tie, p1.n_first_gt_second, p1.n_difference_defined, p1.n_difference_undefined, ...
        numel(p1.excluded)));
    tvr{find_rec(tvr, 3, 'proposed')}.outputs.metrics.t_viol.value = 103;
    tvr{find_rec(tvr, 3, 'apf')}.outputs.metrics.t_viol.value = 203;
    p2 = agg_condition(tvr, 1:100).paired.proposed_vs_apf.t_viol;
    ch{end+1} = mc_vt_check(['finite/+Inf pairs only: the -Inf and +Inf differences are defined; ' ...
        'median -100 over all 92 (lt 87, gt 5)'], ...
        p2.n == 92 && p2.n_difference_defined == 92 && p2.n_difference_undefined == 0 ...
        && p2.n_first_lt_second == 87 && p2.n_first_gt_second == 5 ...
        && p2.median_difference == -100 && strcmp(p2.median_difference_status, 'DEFINED'), ...
        sprintf('median %g, %s', p2.median_difference, p2.median_difference_status));

    % ---- R-F: rho_dot_truth_kstar - the frozen zero-separation branch only ------------------
    R0 = mc_run_outputs('nominal_mpc', 'U', 'COMPLETE', synth_run(pBL0(), 0, false), [], pBL0());
    ch{end+1} = mc_vt_check('true zero separation at kstar: NOT_APPLICABLE / UNDEFINED_AT_ZERO_SEPARATION, raw kept', ...
        strcmp(R0.metrics.rho_dot_truth_kstar.marker, 'NOT_APPLICABLE') ...
        && strcmp(R0.metrics.rho_dot_truth_kstar.reason, 'UNDEFINED_AT_ZERO_SEPARATION') ...
        && isnan(R0.raw.rho_dot_truth_kstar) ...
        && strcmp(R0.raw.rho_dot_truth_kstar_note, 'undefined at zero separation'));
    [ok, got] = mc_vt_throws(@() mc_run_outputs('nominal_mpc', 'U', 'COMPLETE', ...
        synth_run(pBL0(), 1e-3, true), [], pBL0()), 'mc:outputs:metric_payload');
    ch{end+1} = mc_vt_check('an unrelated NaN rho_dot payload (nonzero separation) is an integrity failure', ok, got);
    R2 = mc_run_outputs('nominal_mpc', 'U', 'COMPLETE', synth_run(pBL0(), 1e-3, false), [], pBL0());
    ch{end+1} = mc_vt_check('a valid nonzero separation: rho_dot AVAILABLE, finite, signed', ...
        strcmp(R2.metrics.rho_dot_truth_kstar.marker, 'AVAILABLE') ...
        && isfinite(R2.metrics.rho_dot_truth_kstar.value));

    % ---- F11: a nonfinite AVAILABLE payload is an integrity anomaly, never dropped -------------
    bad = recsU;
    k1 = find_rec(bad, 5, 'proposed');   bad{k1}.outputs.metrics.min_h_body.value = NaN;
    k2 = find_rec(bad, 6, 'proposed');   bad{k2}.outputs.metrics.DeltaV_full.value = Inf;
    k3 = find_rec(bad, 7, 'apf');        bad{k3}.outputs.metrics.min_h_body.value = -Inf;
    Gb = agg_condition(bad, 1:100);
    mh = Gb.continuous.proposed.min_h_body;
    dv = Gb.continuous.proposed.DeltaV_full;
    pa = Gb.paired.proposed_vs_apf.min_h_body;
    ch{end+1} = mc_vt_check('NaN AVAILABLE min_h_body: integrity anomaly (trial 5), n 92 -> 91', ...
        mh.integrity_anomalies.n == 1 && isequal(mh.integrity_anomalies.trial_ids, 5) && mh.n == 91);
    ch{end+1} = mc_vt_check('+Inf AVAILABLE DeltaV_full (Inf not allowed): anomaly (trial 6), n 88 -> 87', ...
        dv.integrity_anomalies.n == 1 && isequal(dv.integrity_anomalies.trial_ids, 6) && dv.n == 87);
    ch{end+1} = mc_vt_check('paired comparison counts anomalous pairs (trials 5 and 7), never compares them', ...
        pa.integrity_anomalies.n == 2 && isequal(sort(pa.integrity_anomalies.trial_ids), [5 7]) ...
        && pa.n == G.paired.proposed_vs_apf.min_h_body.n - 2);

    % ---- F10 in the aggregate: NO_APPLIED_STEP is NOT_APPLICABLE, not a value --------------------
    na = recsU;
    k4 = find_rec(na, 8, 'proposed');
    for u = {'utilisation_max_ratio', 'utilisation_mean_ratio', 'utilisation_fraction'}
        na{k4}.outputs.metrics.(u{1}) = struct('marker', 'NOT_APPLICABLE', 'value', [], 'reason', 'NO_APPLIED_STEP');
    end
    Gn = agg_condition(na, 1:100);
    um = Gn.continuous.proposed.utilisation_max_ratio;
    ch{end+1} = mc_vt_check('a NO_APPLIED_STEP run is NOT_APPLICABLE in the utilisation summary (n 92 -> 91)', ...
        um.n == 91 && um.not_available.NOT_APPLICABLE == 1 && um.integrity_anomalies.n == 0);
    R.checks = [ch{:}];
end

% =====================================================================
function G = agg_condition(recs, ids)
    G = mc_aggregate('NON_SCIENTIFIC', 'condition', recs, ids);
end

% =====================================================================
function k = find_rec(recs, id, method)
    k = find(cellfun(@(r) r.trial_id == id && strcmp(r.method, method), recs), 1);
end

% =====================================================================
function p = pBL0()
    persistent P
    if isempty(P), P = baseline_config(); end
    p = P;
end

% =====================================================================
function run = synth_run(pBL, sep, nanVel)
% A 2-step SYNTHETIC nominal-MPC run through the frozen baseline_metrics: the
% chaser 5 m from the target centre (no body violation), the truth capture
% point 1 m away except at sample 2, where the separation is sep (<= s_cap), so
% the proximity milestone is sample 2; nanVel puts NaN in the truth velocity
% there (an unrelated invalid payload).
    K = 2;
    X = [zeros(1, 3); -5 * ones(1, 3); zeros(1, 3); zeros(3, 3)];
    p_cp = X(1:3, :) + [1; 0; 0];
    p_cp(:, 2) = X(1:3, 2) + [sep; 0; 0];
    v_cp = zeros(3, 3);
    if ~nanVel && sep > 0
        v_cp(:, 2) = [0.01; 0; 0];
    end
    if nanVel, v_cp(:, 2) = [NaN; 0; 0]; end
    assert(sep < pBL.bl.s_cap, 'mc:vt:synth', 'The fixture separation must be within s_cap.');
    run = struct('t', [0 0.1 0.2], 'X', X, 'u_applied', zeros(3, K), 'u_cmd', zeros(3, K), ...
        'clip_flags', [], 'p_cp_truth', p_cp, 'v_cp_truth', v_cp, ...
        'inter_t', [0.01:0.01:0.09, 0.11:0.01:0.19], 'inter_h_body', ones(1, 9 * K), ...
        'inter_r', zeros(3, 9 * K), 'K', K, ...
        'mpc_solver_status', struct('n_failed', 0, 'exitflag', [1 1], 'solve_time', [0.01 0.01]));
end

% =====================================================================
function recs = synth_set(cond)
    recs = cell(1, 300);
    k = 0;
    for id = 1:100
        % proposed
        if strcmp(cond, 'U')
            if id <= 80,      st = 'COMPLETE';             px = true;
            elseif id <= 88,  st = 'COMPLETE';             px = false;
            elseif id <= 92,  st = 'GUARD_BREACH_ABORT';   px = true;
            elseif id <= 95,  st = 'INTEGRATOR_EXCEPTION'; px = [];
            elseif id <= 97,  st = 'IC_REFUSED';           px = [];
            else,             st = 'NUMERICAL_FAILURE';    px = [];
            end
        else
            st = 'COMPLETE';  px = id <= 70;
        end
        if strcmp(st, 'COMPLETE')
            if id <= 60, d9 = 'NO_EVENT'; else, d9 = 'NORMAL'; end
        elseif strcmp(st, 'GUARD_BREACH_ABORT'), d9 = 'GUARD_BREACH';
        elseif strcmp(st, 'IC_REFUSED'),         d9 = 'NOT_EVALUATED';
        else,                                    d9 = 'UNKNOWN';
        end
        k = k + 1;  recs{k} = synth(cond, 'proposed', id, st, px, d9, 2 + id/1000);
        % nominal MPC
        k = k + 1;  recs{k} = synth(cond, 'nominal_mpc', id, 'COMPLETE', id <= 95, 'NOT_APPLICABLE', 2.5 - id/1000);
        % APF
        if id <= 97
            if id <= 10, dv = 2 + id/1000; else, dv = 3; end
            k = k + 1;  recs{k} = synth(cond, 'apf', id, 'COMPLETE', id <= 90, 'NOT_APPLICABLE', dv);
        else
            k = k + 1;  recs{k} = synth(cond, 'apf', id, 'NUMERICAL_FAILURE', [], 'NOT_APPLICABLE', NaN);
        end
    end
end

% =====================================================================
function r = synth(cond, method, id, status, prox, d9, dv)
    switch status
        case {'COMPLETE', 'QP_INFEASIBLE_ABORT', 'GUARD_BREACH_ABORT'}, base = 'AVAILABLE';
        case {'IC_REFUSED', 'TARGET_MODEL_INTEGRATION_FAILURE', 'M_CONSISTENCY_FAILURE'}, base = 'NOT_EXECUTED';
        otherwise, base = 'UNKNOWN';
    end
    av = strcmp(base, 'AVAILABLE');
    isProp = strcmp(method, 'proposed');
    F.full_horizon_complete = q('AVAILABLE', strcmp(status, 'COMPLETE'));
    F.observable_numerical_failure = q('AVAILABLE', any(strcmp(status, {'INTEGRATOR_EXCEPTION', 'NUMERICAL_FAILURE'})));
    F.target_model_integration_failure = q('AVAILABLE', false);
    if strcmp(cond, 'M'), F.m_consistency_failure = q('AVAILABLE', false);
    else, F.m_consistency_failure = q('NOT_APPLICABLE', []); end
    if isProp
        F.formal_domain_ic_refusal = q('AVAILABLE', strcmp(status, 'IC_REFUSED'));
        if av
            F.hocbf_qp_failure = q('AVAILABLE', false);
            F.d9_guard_breach  = q('AVAILABLE', strcmp(status, 'GUARD_BREACH_ABORT'));
        else
            F.hocbf_qp_failure = q(base, []);
            F.d9_guard_breach  = q(base, []);
        end
        F.observed_upper_mpc_solver_failure = q('NOT_APPLICABLE', []);
    else
        F.formal_domain_ic_refusal = q('NOT_APPLICABLE', []);
        F.hocbf_qp_failure = q('NOT_APPLICABLE', []);
        F.d9_guard_breach  = q('NOT_APPLICABLE', []);
        if strcmp(method, 'nominal_mpc')
            F.observed_upper_mpc_solver_failure = q('AVAILABLE', false);
        else
            F.observed_upper_mpc_solver_failure = q('NOT_APPLICABLE', []);
        end
    end
    if av
        F.geometric_proximity_achieved = q('AVAILABLE', logical(prox));
        F.no_observed_body_violation   = q('AVAILABLE', true);
    else
        F.geometric_proximity_achieved = q(base, []);
        F.no_observed_body_violation   = q(base, []);
    end
    if isProp && av
        F.proximity_without_guard_breach = q('AVAILABLE', logical(prox) && ~strcmp(status, 'GUARD_BREACH_ABORT'));
    elseif isProp
        F.proximity_without_guard_breach = q(base, []);
    else
        F.proximity_without_guard_breach = q('NOT_APPLICABLE', []);
    end

    names = {'t_kstar', 'DeltaV_to_proximity', 'rho_dot_truth_kstar', 'DeltaV_full', ...
             'rho_truth_final', 'min_h_body', 'n_inspected', 'min_clearance_union', ...
             'min_clearance_control_grid', 't_viol', 'utilisation_max_ratio', ...
             'utilisation_mean_ratio', 'utilisation_fraction', 'executed_horizon_s'};
    for i = 1:numel(names)
        M.(names{i}) = q(base, []);
    end
    if av
        vals = struct('min_h_body', 0.1 + id/1e4, 'n_inspected', 80001, ...
            'min_clearance_union', 0.06 + id/1e5, 'min_clearance_control_grid', 0.07, ...
            't_viol', Inf, 'utilisation_max_ratio', 1, 'utilisation_mean_ratio', 0.3, ...
            'utilisation_fraction', 0.01, 'executed_horizon_s', 800);
        vf = fieldnames(vals);
        for i = 1:numel(vf)
            M.(vf{i}) = q('AVAILABLE', vals.(vf{i}));
        end
        if prox
            M.t_kstar = q('AVAILABLE', 100 + id);
            M.DeltaV_to_proximity = q('AVAILABLE', 1 + id/1000);
            M.rho_dot_truth_kstar = q('AVAILABLE', -0.003);
        else
            M.t_kstar = q('NOT_APPLICABLE', []);
            M.DeltaV_to_proximity = q('NOT_APPLICABLE', []);
            M.rho_dot_truth_kstar = q('NOT_APPLICABLE', []);
        end
        if strcmp(status, 'COMPLETE')
            M.DeltaV_full = q('AVAILABLE', dv);
            M.rho_truth_final = q('AVAILABLE', 0.02);
        else
            M.DeltaV_full = q('NOT_APPLICABLE', []);
            M.rho_truth_final = q('NOT_APPLICABLE', []);
        end
    end
    D = struct();
    if isProp && av
        D.normalised_error = 0.1 + id/1000;
        D.abs_error_norm   = 0.01 + id/1e4;
    end
    r.condition = cond;
    r.trial_id  = id;
    r.method    = method;
    r.status    = status;
    r.outputs   = struct('status', status, 'flags', F, 'metrics', M, 'd9_outcome', d9, 'diagnostics', D);
    r.level_a   = struct('diag', struct('max_e_p_cp', 0.01 * id, 'rms_e_p_cp', 0.005 * id, ...
                                        'Ep', 0.008 * id, 'Ev', 1e-5 * id, 't_exceed', Inf));
end

% =====================================================================
function e = q(marker, value)
    if ~strcmp(marker, 'AVAILABLE'), value = []; end
    e = struct('marker', marker, 'value', value, 'reason', '');
end

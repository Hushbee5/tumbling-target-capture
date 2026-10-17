function G = mc_aggregate(scope, varargin)
% MC_AGGREGATE  Predeclared descriptive statistics (protocol Sec. 8) - two scopes.
%
%   SCIENTIFIC (the only way to aggregate scientific records)
%     G = mc_aggregate('SCIENTIFIC', ctx, 'U')      Condition U
%     G = mc_aggregate('SCIENTIFIC', ctx, 'M')      Condition M
%     G = mc_aggregate('SCIENTIFIC', ctx, 'cross')  Sec. 8.5 U-versus-M
%   ctx must be a sealed SCIENTIFIC context; MC_CAMPAIGN_GUARD re-derives it
%   from live repository state. The records are NOT supplied by the caller:
%   they are loaded from the checkpoint after MC_CLOSE_CONDITION 'verify' has
%   re-proven the COMPLETE closed condition from scratch (for 'cross', both
%   closures). The trial set is exactly 1:100 (Sec. 8.1 barrier) and the
%   canonical trial table is the one bound by the committed freeze record.
%   A partial or /1 scientific summary is therefore impossible.
%
%   NON-SCIENTIFIC (fixtures and verification only)
%     G = mc_aggregate('NON_SCIENTIFIC', 'condition', recs, trialIds)
%     G = mc_aggregate('NON_SCIENTIFIC', 'cross', recsU, recsM, trialIds)
%   Refuses any record bound SCIENTIFIC ('mc:aggregate:scientific_records');
%   every output is stamped scope = 'NON_SCIENTIFIC'.
%
%   The computational core is LOCAL to this file and unreachable otherwise.
%   The continuous-metric set comes from MC_METRIC_REGISTRY, the one authority
%   shared with MC_RUN_OUTPUTS. Descriptive only: no p-value, test, ranking or
%   composite score (Sec. 8.6); counts are never pooled across conditions.

    switch scope
        case 'SCIENTIFIC'
            assert(numel(varargin) == 2, 'mc:aggregate:usage', ...
                'Usage: mc_aggregate(''SCIENTIFIC'', ctx, ''U''|''M''|''cross'').');
            [ctx, what] = varargin{:};
            assert(isstruct(ctx) && isfield(ctx, 'kind') && strcmp(ctx.kind, 'scientific'), ...
                'mc:aggregate:not_scientific', 'REFUSED: scientific aggregation needs a scientific context.');
            gAgg = mc_campaign_guard(ctx, 'aggregate'); %#ok<NASGU>
            switch what
                case {'U', 'M'}
                    C = mc_close_condition(ctx, what, 'verify');
                    G = condition_core(load_manifest(ctx, C), ctx.trial_ids);
                    G.provenance = provenance(ctx, {C});
                case 'cross'
                    CU = mc_close_condition(ctx, 'U', 'verify');
                    CM = mc_close_condition(ctx, 'M', 'verify');
                    G = cross_core(load_manifest(ctx, CU), load_manifest(ctx, CM), ctx.trial_ids);
                    G.provenance = provenance(ctx, {CU, CM});
                otherwise
                    error('mc:aggregate:usage', 'Unknown scientific aggregate ''%s''.', what);
            end
            G.scope = 'SCIENTIFIC';
        case 'NON_SCIENTIFIC'
            what = varargin{1};
            switch what
                case 'condition'
                    [recs, trialIds] = varargin{2:3};
                    refuse_scientific(recs);
                    G = condition_core(recs, trialIds);
                case 'cross'
                    [recsU, recsM, trialIds] = varargin{2:4};
                    refuse_scientific([recsU, recsM]);
                    G = cross_core(recsU, recsM, trialIds);
                otherwise
                    error('mc:aggregate:usage', 'Unknown non-scientific aggregate ''%s''.', what);
            end
            G.scope = 'NON_SCIENTIFIC';
            G.scope_note = 'NON-SCIENTIFIC fixture aggregate; never a scientific result.';
        otherwise
            error('mc:aggregate:scope', 'Unknown aggregation scope ''%s''.', scope);
    end
end

% =====================================================================
function refuse_scientific(recs)
    assert(iscell(recs), 'mc:aggregate:usage', 'Records must be supplied as a cell array.');
    for k = 1:numel(recs)
        r = recs{k};
        sci = (isfield(r, 'kind') && strcmp(r.kind, 'SCIENTIFIC')) || ...
              (isfield(r, 'binding') && isstruct(r.binding) && isfield(r.binding, 'mode') ...
               && strcmp(r.binding.mode, 'SCIENTIFIC'));
        assert(~sci, 'mc:aggregate:scientific_records', ...
            'REFUSED: scientific records are aggregated only by mc_aggregate(''SCIENTIFIC'', ...).');
    end
end

% =====================================================================
function recs = load_manifest(ctx, C)
    recs = cell(1, numel(C.manifest));
    for i = 1:numel(C.manifest)
        f = fullfile(ctx.root, strrep(C.manifest(i).file, '/', filesep));
        assert(strcmp(baseline_sha256(f), C.manifest(i).sha256), 'mc:aggregate:changed', ...
            'ABORT: record %s changed after the closure was re-proven.', C.manifest(i).file);
        recs{i} = mc_record_read(f, ctx.binding);
    end
end

% =====================================================================
function p = provenance(ctx, closures)
    p = struct('binding', ctx.binding, 'canonical_csv_sha256', ctx.binding.trial_csv_sha256, ...
        'closure_manifest_sha256', {cellfun(@(C) C.manifest_sha256, closures, 'UniformOutput', false)}, ...
        'created_utc', mc_utc_now());
end

% =====================================================================
function G = condition_core(recs, trialIds)
    c = mc_constants();
    methods = c.design.methods;
    reg = mc_metric_registry();
    trialIds = trialIds(:).';
    n = numel(trialIds);
    R = index_records(recs, trialIds, methods);
    G.condition = R{1, 1}.condition;
    G.n = n;
    G.trial_ids = trialIds;
    G.methods = methods;
    G.metric_registry = {reg.name};

    statuses = {'COMPLETE', 'QP_INFEASIBLE_ABORT', 'GUARD_BREACH_ABORT', 'IC_REFUSED', ...
                'INTEGRATOR_EXCEPTION', 'NUMERICAL_FAILURE', ...
                'TARGET_MODEL_INTEGRATION_FAILURE', 'M_CONSISTENCY_FAILURE'};
    execFlags = {'full_horizon_complete', 'observable_numerical_failure', ...
                 'target_model_integration_failure', 'm_consistency_failure', ...
                 'formal_domain_ic_refusal', 'hocbf_qp_failure', 'd9_guard_breach', ...
                 'observed_upper_mpc_solver_failure'};
    outFlags  = {'geometric_proximity_achieved', 'no_observed_body_violation', ...
                 'proximity_without_guard_breach'};

    for mi = 1:numel(methods)
        m = methods{mi};
        st = cellfun(@(r) r.status, R(:, mi), 'UniformOutput', false);
        for s = 1:numel(statuses)
            G.status.(m).(statuses{s}) = sum(strcmp(st, statuses{s}));
        end
        assert(sum(cellfun(@(s) G.status.(m).(s), statuses)) == n, 'mc:aggregate:status', ...
            'An unknown status is present among the %s records.', m);
        for f = 1:numel(execFlags)
            G.exec_flags.(m).(execFlags{f}) = flag_summary(R(:, mi), execFlags{f}, n, false);
        end
        for f = 1:numel(outFlags)
            G.outcome_flags.(m).(outFlags{f}) = flag_summary(R(:, mi), outFlags{f}, n, true);
        end
        for k = 1:numel(reg)
            G.continuous.(m).(reg(k).name) = cont_summary(R(:, mi), reg(k), 'ALL');
            if reg(k).complete_scope
                G.continuous.(m).([reg(k).name '_COMPLETE']) = cont_summary(R(:, mi), reg(k), 'COMPLETE');
            end
        end
    end

    pc = find(strcmp(methods, 'proposed'));
    cats = {'NORMAL', 'GUARD_BREACH', 'NO_EVENT', 'NOT_EVALUATED', 'NOT_EXECUTED', 'UNKNOWN'};
    d9 = cellfun(@(r) r.outputs.d9_outcome, R(:, pc), 'UniformOutput', false);
    for k = 1:numel(cats)
        G.d9.(cats{k}) = sum(strcmp(d9, cats{k}));
    end
    assert(sum(cellfun(@(s) G.d9.(s), cats)) == n, 'mc:aggregate:d9', 'Unknown D9 category.');
    G.estimator.COMPLETE = diag_summary(R(:, pc), {'COMPLETE'});
    G.estimator.PREFIX   = diag_summary(R(:, pc), {'QP_INFEASIBLE_ABORT', 'GUARD_BREACH_ABORT'});
    G.preview = preview_summary(R(:, pc));

    pairs = {'proposed', 'nominal_mpc'; 'proposed', 'apf'; 'nominal_mpc', 'apf'};
    for p = 1:size(pairs, 1)
        a = find(strcmp(methods, pairs{p, 1}));
        b = find(strcmp(methods, pairs{p, 2}));
        nm = sprintf('%s_vs_%s', pairs{p, 1}, pairs{p, 2});
        for k = 1:numel(reg)
            G.paired.(nm).(reg(k).name) = paired_cont(R(:, a), R(:, b), reg(k), trialIds);
        end
        for f = 1:2
            G.paired_binary.(nm).(outFlags{f}) = paired_bin(R(:, a), R(:, b), outFlags{f}, trialIds);
        end
    end
    G.note = ['Descriptive only: no p-value, no hypothesis test, no composite score, no ' ...
              'ranking (Sec. 8.6). Counts are over this condition''s denominator only.'];
end

% =====================================================================
function X = cross_core(recsU, recsM, trialIds)
    c = mc_constants();
    methods = c.design.methods;
    reg = mc_metric_registry();
    trialIds = trialIds(:).';
    GU = condition_core(recsU, trialIds);             % enforces the U barrier
    GM = condition_core(recsM, trialIds);             % enforces the M barrier
    assert(strcmp(GU.condition, 'U') && strcmp(GM.condition, 'M'), 'mc:cross:conditions', ...
        'recsU must be Condition U and recsM Condition M.');
    RU = index_records(recsU, trialIds, methods);
    RM = index_records(recsM, trialIds, methods);
    X.metric_registry = {reg.name};
    for mi = 1:numel(methods)
        m = methods{mi};
        s = struct('US_MS', 0, 'US_MF', 0, 'UF_MS', 0, 'UF_MF', 0);
        ex = struct('trial_id', {}, 'marker_U', {}, 'reason_U', {}, 'status_U', {}, ...
                    'marker_M', {}, 'reason_M', {}, 'status_M', {});
        for i = 1:numel(trialIds)
            eu = RU{i, mi}.outputs.flags.geometric_proximity_achieved;
            em = RM{i, mi}.outputs.flags.geometric_proximity_achieved;
            if strcmp(eu.marker, 'AVAILABLE') && strcmp(em.marker, 'AVAILABLE')
                u = logical(eu.value);  v = logical(em.value);
                if u && v, s.US_MS = s.US_MS + 1;
                elseif u,  s.US_MF = s.US_MF + 1;
                elseif v,  s.UF_MS = s.UF_MS + 1;
                else,      s.UF_MF = s.UF_MF + 1;
                end
            else
                ex(end+1) = struct('trial_id', trialIds(i), 'marker_U', eu.marker, 'reason_U', ...
                    reason_of(eu, RU{i, mi}), 'status_U', RU{i, mi}.status, 'marker_M', em.marker, ...
                    'reason_M', reason_of(em, RM{i, mi}), 'status_M', RM{i, mi}.status); %#ok<AGROW>
            end
        end
        s.n = s.US_MS + s.US_MF + s.UF_MS + s.UF_MF;
        s.excluded = ex;
        s.excluded_counts = count_reasons(ex, 'marker_U', 'marker_M');
        X.proximity_2x2.(m) = s;
        for k = 1:numel(reg)
            X.paired_U_minus_M.(m).(reg(k).name) = paired_cont(RU(:, mi), RM(:, mi), reg(k), trialIds);
        end
    end
    X.note = 'Paired within each method over the SAME physical trials; never pooled to /200.';
end

% =====================================================================
function R = index_records(recs, trialIds, methods)
    assert(iscell(recs) && ~isempty(recs), 'mc:aggregate:barrier', ...
        'Sec. 8.1 barrier: no records were supplied.');
    R = cell(numel(trialIds), numel(methods));
    cond = recs{1}.condition;
    for k = 1:numel(recs)
        r = recs{k};
        assert(strcmp(r.condition, cond), 'mc:aggregate:pooled', ...
            'Records of different conditions are never pooled.');
        ti = find(trialIds == r.trial_id, 1);
        mi = find(strcmp(methods, r.method), 1);
        assert(~isempty(ti) && ~isempty(mi), 'mc:aggregate:outside', ...
            'Record %s t%d is outside the intended set.', r.method, r.trial_id);
        assert(isempty(R{ti, mi}), 'mc:aggregate:duplicate', ...
            'Two records exist for trial %d, method %s.', r.trial_id, r.method);
        R{ti, mi} = r;
    end
    missing = cellfun(@isempty, R);
    assert(~any(missing(:)), 'mc:aggregate:barrier', ...
        ['Sec. 8.1 barrier: %d of %d intended runs have no frozen record; no ' ...
         'aggregate is produced.'], nnz(missing), numel(R));
end

% =====================================================================
function s = flag_summary(col, name, n, isOutcome)
    mk = cellfun(@(r) r.outputs.flags.(name).marker, col, 'UniformOutput', false);
    val = false(numel(col), 1);
    for i = 1:numel(col)
        if strcmp(mk{i}, 'AVAILABLE')
            val(i) = logical(col{i}.outputs.flags.(name).value);
        end
    end
    av = strcmp(mk, 'AVAILABLE');
    s.TRUE           = sum(av & val);
    s.FALSE          = sum(av & ~val);
    s.NOT_EXECUTED   = sum(strcmp(mk, 'NOT_EXECUTED'));
    s.UNKNOWN        = sum(strcmp(mk, 'UNKNOWN'));
    s.NOT_APPLICABLE = sum(strcmp(mk, 'NOT_APPLICABLE'));
    assert(s.TRUE + s.FALSE + s.NOT_EXECUTED + s.UNKNOWN + s.NOT_APPLICABLE == n, ...
        'mc:aggregate:marker', 'Unknown availability marker for %s.', name);
    s.n = n;
    s.applicable = s.NOT_APPLICABLE < n;
    if ~s.applicable
        return
    end
    if isOutcome
        s.breakdown_sum = s.TRUE + s.FALSE + s.NOT_EXECUTED + s.UNKNOWN;
        s.confirmed = mc_wilson(s.TRUE, n);                 % intention-to-treat, n
        s.evaluated = mc_wilson(s.TRUE, s.TRUE + s.FALSE);  % over evaluable runs
        ex = find(~av);
        s.excluded = struct('trial_id', num2cell(cellfun(@(r) r.trial_id, col(ex))), ...
            'marker', mk(ex), ...
            'reason', cellfun(@(r) reason_of(r.outputs.flags.(name), r), col(ex), 'UniformOutput', false), ...
            'status', cellfun(@(r) r.status, col(ex), 'UniformOutput', false));
    else
        s.pct   = 100 * s.TRUE / n;
        s.rate  = mc_wilson(s.TRUE, n);
    end
end

% =====================================================================
function s = cont_summary(col, reg, scope)
% Order statistics over ALL valid AVAILABLE values (Sec. 8.3). A NaN - or an
% infinite value where the registry does not define one - is an INTEGRITY
% ANOMALY: counted with its trial ids, never silently dropped from n. For
% t_viol, +Inf ("no violation observed", Sec. 6.1) IS an AVAILABLE value: it
% stays in n and in the order statistics, which are then evaluated in the
% extended reals (MC_QUANTILE7 'extended'); n_posinf reports how many there are.
    v = [];  ids = [];
    nMarker = struct('NOT_EXECUTED', 0, 'UNKNOWN', 0, 'NOT_APPLICABLE', 0, 'OUT_OF_SCOPE', 0);
    for i = 1:numel(col)
        r = col{i};
        if strcmp(scope, 'COMPLETE') && ~strcmp(r.status, 'COMPLETE')
            nMarker.OUT_OF_SCOPE = nMarker.OUT_OF_SCOPE + 1;
            continue
        end
        e = r.outputs.metrics.(reg.name);
        if strcmp(e.marker, 'AVAILABLE')
            v(end+1) = e.value;      %#ok<AGROW>
            ids(end+1) = r.trial_id; %#ok<AGROW>
        else
            nMarker.(e.marker) = nMarker.(e.marker) + 1;
        end
    end
    s = stats_of(v, ids, reg.inf_allowed, scope);
    s.not_available = nMarker;
end

% =====================================================================
function s = stats_of(v, ids, infAllowed, scope)
    bad = isnan(v) | (isinf(v) & ~infAllowed) | (v == -Inf);
    s.scope = scope;
    s.integrity_anomalies = struct('n', sum(bad), 'trial_ids', ids(bad));
    v = v(~bad);
    s.n = numel(v);
    s.n_posinf = sum(v == Inf);
    s.n_finite = s.n - s.n_posinf;
    q = mc_quantile7(v, [0.05 0.25 0.5 0.75], 'extended');   % -Inf excluded above: always defined
    s.p05 = q(1);  s.q1 = q(2);  s.median = q(3);  s.q3 = q(4);
    if isempty(v)
        s.min = NaN;  s.max = NaN;
    else
        s.min = min(v);  s.max = max(v);
    end
end

% =====================================================================
function s = diag_summary(col, statuses)
    ne = [];  ae = [];  ids = [];
    for i = 1:numel(col)
        r = col{i};
        if any(strcmp(r.status, statuses))
            ne(end+1) = r.outputs.diagnostics.normalised_error; %#ok<AGROW>
            ae(end+1) = r.outputs.diagnostics.abs_error_norm;   %#ok<AGROW>
            ids(end+1) = r.trial_id;                           %#ok<AGROW>
        end
    end
    s.statuses = statuses;
    s.normalised_error = stats_of(ne, ids, false, strjoin(statuses, '+'));
    s.abs_error_norm   = stats_of(ae, ids, false, strjoin(statuses, '+'));
end

% =====================================================================
function s = preview_summary(col)
    f = {'max_e_p_cp', 'rms_e_p_cp', 'Ep', 'Ev'};
    vals = struct();  ids = [];
    for k = 1:numel(f), vals.(f{k}) = []; end
    nEx = 0;  nAv = 0;
    for i = 1:numel(col)
        d = col{i}.level_a.diag;
        if isempty(d), continue, end
        nAv = nAv + 1;
        ids(end+1) = col{i}.trial_id; %#ok<AGROW>
        for k = 1:numel(f)
            vals.(f{k})(end+1) = d.(f{k});
        end
        nEx = nEx + isfinite(d.t_exceed);
    end
    for k = 1:numel(f)
        s.(f{k}) = stats_of(vals.(f{k}), ids, false, 'TABLES_AVAILABLE');
    end
    s.n_tables_available = nAv;
    s.n_t_exceed_finite  = nEx;
end

% =====================================================================
function s = paired_cont(ca, cb, reg, trialIds)
% Common physical trials where the metric is AVAILABLE for BOTH (Sec. 8.4 /
% 8.5): n, win / tie / loss counts on the values themselves (tie = exact
% equality; +Inf = no violation observed orders above every finite time and
% ties with +Inf), and the median paired difference, first minus second, in the
% extended reals: a finite / +Inf pair has the defined difference -Inf (+Inf
% for +Inf / finite). A +Inf / +Inf pair has NO defined difference (+Inf - Inf):
% the frozen Sec. 8.4 / 8.5 text does not say how such a pair enters a median
% paired difference. Such pairs are counted with their trial ids, and while
% any exists the median difference is NOT computed (status
% 'UNRESOLVED_UNDEFINED_DIFFERENCE', for reviewer resolution) - no value is
% imputed and no pair is silently dropped. A median falling between -Inf and
% +Inf is likewise undefined ('UNDEFINED_OPPOSITE_INFINITIES'). Every excluded
% trial keeps its markers, reasons and statuses; anomalous AVAILABLE values are
% counted, never dropped.
    d = [];  nLt = 0;  nTie = 0;  nGt = 0;  nPair = 0;
    anomalies = [];  undef = [];
    ex = struct('trial_id', {}, 'first_marker', {}, 'first_reason', {}, 'first_status', {}, ...
                'second_marker', {}, 'second_reason', {}, 'second_status', {});
    for i = 1:numel(ca)
        ea = ca{i}.outputs.metrics.(reg.name);
        eb = cb{i}.outputs.metrics.(reg.name);
        if strcmp(ea.marker, 'AVAILABLE') && strcmp(eb.marker, 'AVAILABLE')
            a = ea.value;  b = eb.value;
            if anomalous(a, reg) || anomalous(b, reg)
                anomalies(end+1) = trialIds(i); %#ok<AGROW>
                continue
            end
            nPair = nPair + 1;
            if a < b, nLt = nLt + 1; elseif a == b, nTie = nTie + 1; else, nGt = nGt + 1; end
            if isinf(a) && isinf(b)
                undef(end+1) = trialIds(i); %#ok<AGROW>     % +Inf - (+Inf): undefined
            else
                d(end+1) = a - b; %#ok<AGROW>               % finite, or +-Inf against a finite value
            end
        else
            ex(end+1) = struct('trial_id', trialIds(i), 'first_marker', ea.marker, ...
                'first_reason', reason_of(ea, ca{i}), 'first_status', ca{i}.status, ...
                'second_marker', eb.marker, 'second_reason', reason_of(eb, cb{i}), ...
                'second_status', cb{i}.status); %#ok<AGROW>
        end
    end
    s.n = nPair;
    s.n_first_lt_second = nLt;
    s.n_tie             = nTie;
    s.n_first_gt_second = nGt;
    s.n_difference_defined   = numel(d);
    s.n_difference_undefined = numel(undef);
    s.difference_undefined_trial_ids = undef;
    if ~isempty(undef)
        s.median_difference = NaN;
        s.median_difference_status = 'UNRESOLVED_UNDEFINED_DIFFERENCE';
    else
        [m, u] = mc_quantile7(d, 0.5, 'extended');
        s.median_difference = m;
        if u
            s.median_difference_status = 'UNDEFINED_OPPOSITE_INFINITIES';
        elseif isempty(d)
            s.median_difference_status = 'NO_COMMON_PAIR';
        else
            s.median_difference_status = 'DEFINED';
        end
    end
    s.excluded          = ex;
    s.excluded_counts   = count_reasons(ex, 'first_marker', 'second_marker');
    s.integrity_anomalies = struct('n', numel(anomalies), 'trial_ids', anomalies);
    s.note = ['difference = first minus second, in the extended reals; tie = exact equality; ' ...
              'a +Inf / +Inf pair has no defined difference (see median_difference_status)'];
end

% =====================================================================
function tf = anomalous(v, reg)
    tf = ~(isnumeric(v) && isscalar(v)) || isnan(v) || v == -Inf || (v == Inf && ~reg.inf_allowed);
end

% =====================================================================
function s = reason_of(e, r)
    if isfield(e, 'reason') && ~isempty(e.reason)
        s = e.reason;
    else
        s = r.status;
    end
end

% =====================================================================
function C = count_reasons(ex, fa, fb)
    C = struct('combination', {}, 'count', {});
    if isempty(ex), return, end
    keys = arrayfun(@(x) sprintf('%s/%s', x.(fa), x.(fb)), ex, 'UniformOutput', false);
    u = unique(keys);
    for i = 1:numel(u)
        C(end+1) = struct('combination', u{i}, 'count', sum(strcmp(keys, u{i}))); %#ok<AGROW>
    end
end

% =====================================================================
function s = paired_bin(ca, cb, name, trialIds)
    s.TT = 0;  s.TF = 0;  s.FT = 0;  s.FF = 0;
    ex = struct('trial_id', {}, 'first_marker', {}, 'first_reason', {}, 'first_status', {}, ...
                'second_marker', {}, 'second_reason', {}, 'second_status', {});
    for i = 1:numel(ca)
        ea = ca{i}.outputs.flags.(name);
        eb = cb{i}.outputs.flags.(name);
        if strcmp(ea.marker, 'AVAILABLE') && strcmp(eb.marker, 'AVAILABLE')
            a = logical(ea.value);  b = logical(eb.value);
            if a && b, s.TT = s.TT + 1;
            elseif a,  s.TF = s.TF + 1;
            elseif b,  s.FT = s.FT + 1;
            else,      s.FF = s.FF + 1;
            end
        else
            ex(end+1) = struct('trial_id', trialIds(i), 'first_marker', ea.marker, ...
                'first_reason', reason_of(ea, ca{i}), 'first_status', ca{i}.status, ...
                'second_marker', eb.marker, 'second_reason', reason_of(eb, cb{i}), ...
                'second_status', cb{i}.status); %#ok<AGROW>
        end
    end
    s.n = s.TT + s.TF + s.FT + s.FF;
    s.excluded = ex;
    s.excluded_counts = count_reasons(ex, 'first_marker', 'second_marker');
end

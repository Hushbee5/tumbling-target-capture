function res = mc_mask_check(out)
% MC_MASK_CHECK  Evaluate the B4 contract of MC_MASK_CONTRACT on an ELIGIBLE out.
%   res = mc_mask_check(out)
%
%   res.nonfinite  cellstr, one entry per violated finiteness rule   -> B4
%   res.structure  cellstr, one entry per missing / extra / mis-sized /
%                  mis-typed field or inconsistent bookkeeping      -> the
%                  output is in an UNEXPECTED STATE (HARNESS_ERROR)
%   res.domain     struct(ns, ka, ni) used for the evaluation
%
%   The caller must have established strcmp(out.eligibility, 'ELIGIBLE');
%   this function refuses anything else, so it can never be applied to an
%   IC-refusal record.

    res = struct('nonfinite', {{}}, 'structure', {{}}, 'domain', struct());
    assert(isstruct(out) && isscalar(out) && isfield(out, 'eligibility') ...
        && strcmp(out.eligibility, 'ELIGIBLE'), 'mc:mask:not_eligible', ...
        'The B4 contract applies ONLY to an ELIGIBLE returned output.');

    C = mc_mask_contract();

    % ---- exact field sets -------------------------------------------------
    top = {C(~contains({C.path}, '.')).path};
    res = field_set(res, out, top, 'out');
    if ~isempty(res.structure)
        return
    end
    for s = {'estimator', 'inter'}
        subs = {C(startsWith({C.path}, [s{1} '.'])).path};
        subs = cellfun(@(p) p(numel(s{1}) + 2:end), subs, 'UniformOutput', false);
        res = field_set(res, out.(s{1}), subs, ['out.' s{1}]);
    end
    if ~isempty(res.structure)
        return
    end

    % ---- domains ------------------------------------------------------------
    if ~(isnumeric(out.K_applied) && isscalar(out.K_applied) && isfinite(out.K_applied) ...
            && out.K_applied >= 0 && out.K_applied == round(out.K_applied))
        res.structure{end+1} = 'K_applied is not a non-negative integer scalar';
        return
    end
    ka = out.K_applied;
    ns = numel(out.t);
    nsub = NaN;
    if isfield(out.config, 'opt') && isfield(out.config.opt, 'n_sub')
        nsub = out.config.opt.n_sub;
    end
    if ~(isscalar(nsub) && isfinite(nsub) && nsub >= 1)
        res.structure{end+1} = 'config.opt.n_sub is unavailable';
        return
    end
    ni = (nsub - 1) * ka;
    res.domain = struct('ns', ns, 'ka', ka, 'ni', ni);
    if ns ~= ka + 1
        res.structure{end+1} = sprintf('numel(t) = %d ~= K_applied + 1 = %d', ns, ka + 1);
    end
    if ~isequal(out.K, ka)
        res.structure{end+1} = 'out.K ~= out.K_applied';
    end
    if ~isempty(res.structure)
        return
    end

    % ---- per-field rules ------------------------------------------------------
    for i = 1:numel(C)
        v = get_path(out, C(i).path);
        res = apply_rule(res, out, C(i), v, ns, ka, ni);
    end
end

% =====================================================================
function res = field_set(res, s, want, label)
    if ~isstruct(s) || ~isscalar(s)
        res.structure{end+1} = sprintf('%s is not a scalar struct', label);
        return
    end
    have = fieldnames(s);
    missing = setdiff(want, have);
    extra   = setdiff(have, want);
    for k = 1:numel(missing)
        res.structure{end+1} = sprintf('%s.%s is missing', label, missing{k});
    end
    for k = 1:numel(extra)
        res.structure{end+1} = sprintf('%s.%s is not classified by the contract', label, extra{k});
    end
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
function res = apply_rule(res, out, e, v, ns, ka, ni)
    p = e.path;
    switch e.rule
        case 'FINITE'
            if ~size_ok(v, e.domain, ns, ka, ni) || ~(isnumeric(v) && isreal(v))
                res.structure{end+1} = sprintf('%s: wrong size or type %s', p, mat2str(size(v)));
            elseif ~all(isfinite(v(:)))
                res.nonfinite{end+1} = sprintf('%s: %d non-finite value(s)', p, sum(~isfinite(v(:))));
            end
        case 'FINITE_WHERE_ENFORCED'
            en = out.cap_enforced;
            if ~size_ok(v, e.domain, ns, ka, ni) || ~isnumeric(v) || numel(en) ~= numel(v)
                res.structure{end+1} = sprintf('%s: wrong size or type', p);
            elseif ~all(isfinite(v(logical(en))))
                res.nonfinite{end+1} = sprintf('%s: non-finite value on an ENFORCED step', p);
            end
        case 'FINITE_OR_NAN'
            if ~size_ok(v, e.domain, ns, ka, ni) || ~(isnumeric(v) && isreal(v))
                res.structure{end+1} = sprintf('%s: wrong size or type', p);
            elseif any(isinf(v(:)))
                res.nonfinite{end+1} = sprintf('%s: +-Inf is not a permitted value', p);
            end
        case 'FINITE_OR_EMPTY_NO_RECORDS'
            nrec = out.estimator.records;
            if isempty(v) && isequal(nrec, 0)
                % permitted empty: no complete Tw window (cl_records.m:50-51, 73)
            elseif ~(isnumeric(v) && isscalar(v))
                res.structure{end+1} = sprintf('%s: must be a scalar when records >= 1', p);
            elseif ~isfinite(v)
                res.nonfinite{end+1} = sprintf('%s: non-finite with %d record(s)', p, nrec);
            end
        case 'LOGICAL'
            if ~islogical(v) || ~size_ok(v, e.domain, ns, ka, ni)
                res.structure{end+1} = sprintf('%s: must be a logical %s', p, e.domain);
            end
        case 'LOGICAL_SCALAR'
            if ~(islogical(v) && isscalar(v))
                res.structure{end+1} = sprintf('%s: must be a logical scalar', p);
            end
        case 'CHAR'
            if ~ischar(v)
                res.structure{end+1} = sprintf('%s: must be char', p);
            end
        case 'TRUE'
            if ~isequal(v, true)
                res.structure{end+1} = sprintf('%s: must be true', p);
            end
        case 'FALSE'
            if ~isequal(v, false)
                res.structure{end+1} = sprintf('%s: must be false', p);
            end
        case 'ELIGIBLE'
            if ~strcmp(v, 'ELIGIBLE')
                res.structure{end+1} = sprintf('%s: must be ELIGIBLE', p);
            end
        case 'EVENT'
            if ~(ischar(v) && any(strcmp(v, {'NORMAL', 'GUARD_BREACH', 'NO_EVENT'})))
                res.structure{end+1} = sprintf('%s: not a D9 outcome of an evaluated run', p);
            end
        case 'EVENTS'
            if ~iscell(v) || ~size_ok(v, e.domain, ns, ka, ni) ...
                    || ~all(cellfun(@(x) ischar(x) && any(strcmp(x, {'NONE', 'NORMAL', 'GUARD_BREACH'})), v))
                res.structure{end+1} = sprintf('%s: must be a 1 x ka cell of detector outputs', p);
            end
        case 'IC'
            res = check_ic(res, v);
        case 'EVENT_LOG'
            res = check_event_log(res, out, v);
        case 'HANDOFF'
            if strcmp(out.event, 'NORMAL')
                if ~isequal(v, out.event_log)
                    res.structure{end+1} = 'handoff: must equal event_log for a NORMAL event';
                end
            elseif ~isempty(v)
                res.structure{end+1} = 'handoff: must be empty unless the event is NORMAL';
            end
        case 'QP_FAILURE'
            res = check_qp_failure(res, v);
        case {'STRUCT', 'PROVENANCE'}
            if ~(isstruct(v) && isscalar(v))
                res.structure{end+1} = sprintf('%s: must be a scalar struct', p);
            end
        otherwise
            res.structure{end+1} = sprintf('%s: unknown contract rule %s', p, e.rule);
    end
end

% =====================================================================
function ok = size_ok(v, domain, ns, ka, ni)
    tok = strsplit(domain, ':');
    switch tok{1}
        case 'STATE'
            ok = isequal(size(v), [str2double(tok{2}), ns]);
        case 'APPLIED'
            ok = isequal(size(v), [str2double(tok{2}), ka]);
        case 'INTER'
            r = str2double(tok{2});
            ok = isequal(size(v), [r, ni]) || (ni == 0 && isempty(v));
        case 'FIXED'
            dims = str2double(strsplit(tok{2}, 'x'));
            ok = isequal(size(v), dims);
        case 'SCALAR'
            ok = isscalar(v);
        otherwise
            ok = false;
    end
end

% =====================================================================
function res = check_ic(res, ic)
    want = {'tol', 'h_body', 'psi1_body', 'h_cap', 'psi1_cap', 'rho', 'rho_dot', ...
            'cap_active_initially', 'reasons', 'admissible'};
    res = field_set(res, ic, want, 'out.ic');
    if ~isstruct(ic) || ~all(isfield(ic, want))
        return
    end
    num = {'tol', 'h_body', 'psi1_body', 'h_cap', 'psi1_cap', 'rho', 'rho_dot'};
    for k = 1:numel(num)
        x = ic.(num{k});
        if ~(isnumeric(x) && isscalar(x))
            res.structure{end+1} = sprintf('ic.%s: must be a numeric scalar', num{k});
        elseif ~isfinite(x)
            res.nonfinite{end+1} = sprintf('ic.%s: non-finite', num{k});
        end
    end
    if ~isequal(ic.admissible, true)
        res.structure{end+1} = 'ic.admissible: an ELIGIBLE run must have an admissible IC';
    end
end

% =====================================================================
function res = check_event_log(res, out, v)
    if strcmp(out.event, 'NO_EVENT')
        if ~isempty(v)
            res.structure{end+1} = 'event_log: must be empty when the event is NO_EVENT';
        end
        return
    end
    want = {'t', 'k', 'event', 'rho', 'rho_dot', 'v_rel_cp', 'nu', 'h_body', 'psi1_body', ...
            'h_cap', 'psi1_cap', 'alpha', 'eps_rho', 'theta_hat', 'eta', 's_cap'};
    res = field_set(res, v, want, 'out.event_log');
    if ~isstruct(v) || ~all(isfield(v, want))
        return
    end
    if ~strcmp(v.event, out.event)
        res.structure{end+1} = 'event_log.event: disagrees with out.event';
    end
    num = setdiff(want, {'event'});
    for k = 1:numel(num)
        x = v.(num{k});
        if ~(isnumeric(x) && isreal(x) && ~isempty(x))
            res.structure{end+1} = sprintf('event_log.%s: must be numeric', num{k});
        elseif ~all(isfinite(x(:)))
            res.nonfinite{end+1} = sprintf('event_log.%s: non-finite', num{k});
        end
    end
end

% =====================================================================
function res = check_qp_failure(res, q)
    want = {'occurred', 'k', 't', 'cap_active', 'status', 'exitflag', 'feasible', ...
            'feas_margin', 'joint_margin', 'row_names'};
    res = field_set(res, q, want, 'out.qp_failure');
    if ~isstruct(q) || ~all(isfield(q, want))
        return
    end
    if ~(islogical(q.occurred) && isscalar(q.occurred))
        res.structure{end+1} = 'qp_failure.occurred: must be a logical scalar';
        return
    end
    if ~q.occurred
        % PERMITTED EMPTY: the no-failure record of simulate_task4.m:210-212.
        emp = setdiff(want, {'occurred'});
        for k = 1:numel(emp)
            if ~isempty(q.(emp{k}))
                res.structure{end+1} = sprintf('qp_failure.%s: must be empty when no failure occurred', emp{k});
            end
        end
        return
    end
    sc = {'k', 't', 'status', 'exitflag'};
    for k = 1:numel(sc)
        x = q.(sc{k});
        if ~(isnumeric(x) && isscalar(x))
            res.structure{end+1} = sprintf('qp_failure.%s: must be a numeric scalar', sc{k});
        elseif ~isfinite(x)
            res.nonfinite{end+1} = sprintf('qp_failure.%s: non-finite', sc{k});
        end
    end
    if ~(islogical(q.cap_active) && isscalar(q.cap_active))
        res.structure{end+1} = 'qp_failure.cap_active: must be a logical scalar';
    end
    if ~isequal(q.feasible, false)
        res.structure{end+1} = 'qp_failure.feasible: must be false when a failure occurred';
    end
    fm = q.feas_margin;
    if ~(isnumeric(fm) && isrow(fm) && any(numel(fm) == [1 2]))
        res.structure{end+1} = 'qp_failure.feas_margin: must be a 1 x nR row, nR in {1, 2}';
    elseif ~all(isfinite(fm))
        res.nonfinite{end+1} = 'qp_failure.feas_margin: non-finite';
    end
    jm = q.joint_margin;
    if ~(isnumeric(jm) && isscalar(jm))
        res.structure{end+1} = 'qp_failure.joint_margin: must be a numeric scalar';
    elseif isinf(jm)
        res.nonfinite{end+1} = 'qp_failure.joint_margin: +-Inf is not permitted (NaN is)';
    end
    if ~(iscell(q.row_names) && numel(q.row_names) == numel(fm))
        res.structure{end+1} = 'qp_failure.row_names: must name every row';
    end
end

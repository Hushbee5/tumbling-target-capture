function L = mc_attempt_ledger(action, ctx, condition, trialId, method, varargin)
% MC_ATTEMPT_LEDGER  Durable evidence of every method invocation; THE strict history validator.
%   L = mc_attempt_ledger('state',   ctx, cond, trial, method)
%   L = mc_attempt_ledger('start',   ctx, cond, trial, method, k, shardId)
%   L = mc_attempt_ledger('post',    ctx, cond, trial, method, k, postInfo)
%   L = mc_attempt_ledger('outcome', ctx, cond, trial, method, k, outcome)
%
%   FILES (immutable, atomic, never overwritten) under <root>/attempts, unit =
%   <cond>_t<NNN>_<method>:
%     <unit>_a<k>_STARTED.mat  written IMMEDIATELY BEFORE the controller is
%         invoked: binding, unit, attempt k, shard, process, UTC
%     <unit>_a<k>_POST.mat     written IMMEDIATELY AFTER the invocation returns,
%         before any fallible step: guard status, exception summary, wall time,
%         the SHA-256 of its STARTED - the durable knowledge that it executed
%     <unit>_a<k>_OUTCOME.mat  written after the post-run assertions, the
%         classification and the outputs, BEFORE the record write: status,
%         rule, reason, mask, the complete outputs block, guard, wall time, the
%         Level-A hash and the SHA-256 of STARTED and POST. The terminal record
%         is rebuilt from it without invoking anything.
%   Operator rulings: <root>/decisions/ADJUDICATE_<unit>_a<k>.mat
%   (MC_OPERATOR_ADJUDICATE_ATTEMPT).
%
%   'state' IS THE ONE STRICT HISTORY VALIDATOR. It is used at every restart
%   (MC_RUN_CONDITION), by every operator ruling and by the closure re-proof
%   (MC_CONDITION_REPROOF), and refuses ('mc:ledger:history') unless:
%     - every ledger entry of the unit carries an exact name (an interrupted
%       write's '.tmp-' residue carries no state); attempts are CONTIGUOUS 1..n;
%       every attempt has its STARTED, POST only with STARTED, OUTCOME only with
%       POST;
%     - every file's CONTENT matches its name - schema, state, unit, attempt -,
%       this campaign's binding and the planned shard of the trial; POST binds
%       the SHA-256 of its STARTED; OUTCOME binds STARTED and POST and its
%       status is one the POST guard status permits;
%     - every SUPERSEDED attempt j < n carries a valid AUTHORISE_NEW_ATTEMPT
%       ruling bound to the SHA-256 of its STARTED, and its evidence was, and
%       still is, INTERRUPTED_BEFORE_POST (no POST, no OUTCOME);
%     - a terminal record links to the LATEST attempt: Level B - attempt n,
%       carrying the SHA-256 of its STARTED, POST and OUTCOME (a recovered
%       record also its RECOVER_RECORD ruling); Level A - attempt 0, no ledger
%       file, no ruling;
%     - no ruling exists for any other attempt.
%
%   L.status   'TERMINAL' | 'FRESH' | 'AUTHORISED_NEW' | 'RECOVER_AUTHORISED' |
%              'AMBIGUOUS'
%   L.evidence the evidence class of the latest attempt without a record:
%     INTERRUPTED_BEFORE_POST    STARTED only, and NO incident of this attempt:
%                                nothing durable says the controller ran to any
%                                outcome - an OS / process interruption. Permitted
%                                ruling AUTHORISE_NEW_ATTEMPT: the interrupted run,
%                                having no record, is rerun from scratch (10.4)
%     INVOCATION_INCIDENT        STARTED only, but a HARNESS_ERROR incident of THIS
%                                attempt is on disk (e.g. the POST ledger write
%                                failed after the invocation had returned). The
%                                absence of POST is then NOT evidence of an
%                                interruption: the controller may have run to an
%                                outcome - possibly a failure - that was never made
%                                durable. NO ruling: acknowledging the incident is
%                                not authority to run anything again (10.4, 10.5);
%                                stopped for the reviewer
%     PROMOTED_FAILURE_OBSERVED  POST of the PROPOSED method with the promoted
%                                ode45 exception: INTEGRATOR_EXCEPTION (B2) follows
%                                from POST alone. Permitted ruling RECOVER_RECORD;
%                                never retried (10.5)
%     OUTCOME_DURABLE            OUTCOME present: the status and outputs are
%                                durable. Permitted ruling RECOVER_RECORD; never
%                                re-executed
%     RETURNED_UNCLASSIFIED      POST RETURNED, no OUTCOME: RETURNED is not proof
%                                of scientific success and the outcome was never
%                                made durable. NO ruling: stopped for the reviewer
%     HARNESS_OBSERVED           POST with an exception that is HARNESS_ERROR (B1):
%                                any OTHER_EXCEPTION, or the promoted exception
%                                escaping a baseline. NO ruling: a new run needs
%                                new protocol authority (10.4); stopped for the
%                                reviewer
%   L.permitted  the rulings the evidence permits
%   L also: attempt (latest k), next_attempt, attempts, started / post / outcome
%   (SHA-256 of the latest attempt's files, '' if absent) and their files,
%   decision_file / decision_sha256 (a ruling on the latest attempt), terminal
%   (record path), record (the terminal record, read under the binding), files
%   (n x 2 cell: every ledger and ruling file of the unit, root-relative, with
%   its SHA-256, in attempt order).

    unit = sprintf('%s_t%03d_%s', condition, trialId, method);
    folder = fullfile(ctx.root, 'attempts');
    switch action
        case 'state'
            L = state(ctx, unit, condition, trialId, method);
        case 'start'
            [k, shardId] = varargin{:};
            mc_campaign_guard(ctx, 'write');
            mc_reservation('assert_owned', ctx, condition, trialId);
            st = state(ctx, unit, condition, trialId, method);
            assert(any(strcmp(st.status, {'FRESH', 'AUTHORISED_NEW'})) && k == st.next_attempt, ...
                'mc:campaign:attempt_order', 'REFUSED: attempt %d of %s may not start (%s).', ...
                k, unit, st.status);
            if ~isfolder(folder), mkdir(folder); end
            rec = struct('schema', 'task4_mc_attempt_v1', 'state', 'STARTED', 'binding', ctx.binding, ...
                'condition', condition, 'trial_id', trialId, 'method', method, 'attempt', k, ...
                'shard_id', shardId, 'process', mc_process_identity(), 'utc', mc_utc_now());
            info = mc_atomic_write(fullfile(folder, sprintf('%s_a%d_STARTED.mat', unit, k)), ...
                struct('attempt', rec), 'mat', struct('ctx', ctx));
            L = struct('file', info.path, 'sha256', info.sha256);
        case 'post'
            [k, postInfo] = varargin{:};
            mc_campaign_guard(ctx, 'write');
            mc_reservation('assert_owned', ctx, condition, trialId);
            fS = fullfile(folder, sprintf('%s_a%d_STARTED.mat', unit, k));
            assert(isfile(fS), 'mc:campaign:attempt_order', 'REFUSED: POST without STARTED for %s.', unit);
            rec = struct('schema', 'task4_mc_attempt_v1', 'state', 'POST_EXECUTION', ...
                'binding', ctx.binding, 'condition', condition, 'trial_id', trialId, ...
                'method', method, 'attempt', k, 'started_sha256', baseline_sha256(fS), ...
                'guard_status', postInfo.guard_status, 'exception', postInfo.exception, ...
                'wall_s', postInfo.wall_s, 'process', mc_process_identity(), 'utc', mc_utc_now());
            info = mc_atomic_write(fullfile(folder, sprintf('%s_a%d_POST.mat', unit, k)), ...
                struct('attempt', rec), 'mat', struct('ctx', ctx));
            L = struct('file', info.path, 'sha256', info.sha256);
        case 'outcome'
            [k, oc] = varargin{:};
            mc_campaign_guard(ctx, 'write');
            mc_reservation('assert_owned', ctx, condition, trialId);
            fS = fullfile(folder, sprintf('%s_a%d_STARTED.mat', unit, k));
            fP = fullfile(folder, sprintf('%s_a%d_POST.mat', unit, k));
            assert(isfile(fS) && isfile(fP), 'mc:campaign:attempt_order', ...
                'REFUSED: OUTCOME without STARTED and POST for %s.', unit);
            rec = struct();
            rec.schema = 'task4_mc_attempt_v1';
            rec.state = 'OUTCOME';
            rec.binding = ctx.binding;
            rec.condition = condition;
            rec.trial_id = trialId;
            rec.method = method;
            rec.attempt = k;
            rec.started_sha256 = baseline_sha256(fS);
            rec.post_sha256 = baseline_sha256(fP);
            rec.status = oc.status;
            rec.status_rule = oc.rule;
            rec.status_reason = oc.reason;
            rec.mask = oc.mask;
            rec.outputs = oc.outputs;
            rec.guard = oc.guard;
            rec.wall_s = oc.wall_s;
            rec.level_a_hash = oc.level_a_hash;
            rec.recovered_from = oc.recovered_from;
            rec.recovery_decision_sha256 = oc.recovery_decision_sha256;
            rec.process = mc_process_identity();
            rec.utc = mc_utc_now();
            info = mc_atomic_write(fullfile(folder, sprintf('%s_a%d_OUTCOME.mat', unit, k)), ...
                struct('attempt', rec), 'mat', struct('ctx', ctx));
            L = struct('file', info.path, 'sha256', info.sha256);
        otherwise
            error('mc:ledger:action', 'Unknown ledger action ''%s''.', action);
    end
end

% =====================================================================
function L = state(ctx, unit, condition, trialId, method)
    att = fullfile(ctx.root, 'attempts');
    dec = fullfile(ctx.root, 'decisions');
    L = struct('unit', unit, 'status', '', 'evidence', '', 'permitted', {{}}, 'attempt', 0, ...
        'next_attempt', NaN, 'attempts', [], 'started', '', 'post', '', 'outcome', '', ...
        'started_file', '', 'post_file', '', 'outcome_file', '', 'decision_file', '', ...
        'decision_sha256', '', 'terminal', '', 'record', [], 'files', {cell(0, 2)}, ...
        'incident_file', '', 'incident_returned', false, 'incident_guard_status', '');
    incs = unit_incidents(ctx, unit);

    % ---- the unit's ledger entries, by exact name -----------------------------
    ents = entries(att, [unit '_a'], ['^' unit '_a(\d+)_(STARTED|POST|OUTCOME)\.mat$'], unit);
    ks = unique([ents.k]);
    n = 0;
    if ~isempty(ks), n = max(ks); end
    need(n == 0 || isequal(ks(:).', 1:n), unit, 'the attempt numbers are not contiguous from 1');
    L.attempts = ks;
    shard = '';
    if n > 0
        [~, shardOf] = mc_shard_plan_read(ctx, condition);
        shard = shardOf(trialId);
    end

    ev = struct('fS', {}, 'fP', {}, 'fO', {}, 'sS', {}, 'sP', {}, 'sO', {}, 'P', {}, 'O', {}, 'cls', {});
    for j = 1:n
        fS = fullfile(att, sprintf('%s_a%d_STARTED.mat', unit, j));
        fP = fullfile(att, sprintf('%s_a%d_POST.mat', unit, j));
        fO = fullfile(att, sprintf('%s_a%d_OUTCOME.mat', unit, j));
        need(isfile(fS), unit, sprintf('attempt %d has no STARTED', j));
        A = load_one(fS, 'attempt', unit);
        need(same_unit(A, 'STARTED', ctx, condition, trialId, method, j) && isfield(A, 'shard_id') ...
            && strcmp(A.shard_id, shard), ...
            unit, sprintf('the STARTED of attempt %d does not describe this unit, binding and shard', j));
        e = struct('fS', fS, 'fP', '', 'fO', '', 'sS', baseline_sha256(fS), 'sP', '', 'sO', '', ...
                   'P', [], 'O', [], 'cls', '');
        if isfile(fP)
            P = load_one(fP, 'attempt', unit);
            need(same_unit(P, 'POST_EXECUTION', ctx, condition, trialId, method, j) ...
                && all(isfield(P, {'started_sha256', 'guard_status', 'exception', 'wall_s'})) ...
                && strcmp(P.started_sha256, e.sS) ...
                && any(strcmp(P.guard_status, {'RETURNED', 'PROMOTED_ODE45_FAILURE', 'OTHER_EXCEPTION'})), ...
                unit, sprintf('the POST of attempt %d is not bound to its STARTED', j));
            e.fP = fP;  e.sP = baseline_sha256(fP);  e.P = P;
        end
        if isfile(fO)
            need(~isempty(e.P), unit, sprintf('attempt %d has an OUTCOME without POST', j));
            O = load_one(fO, 'attempt', unit);
            need(same_unit(O, 'OUTCOME', ctx, condition, trialId, method, j) ...
                && all(isfield(O, {'started_sha256', 'post_sha256', 'status', 'status_rule', ...
                    'status_reason', 'mask', 'outputs', 'guard', 'wall_s', 'level_a_hash', ...
                    'recovered_from', 'recovery_decision_sha256'})) ...
                && strcmp(O.started_sha256, e.sS) && strcmp(O.post_sha256, e.sP) ...
                && outcome_consistent(method, e.P.guard_status, O.status) ...
                && any(strcmp(O.recovered_from, {'', 'POST'})) && isstruct(O.outputs), ...
                unit, sprintf('the OUTCOME of attempt %d is not bound to its STARTED and POST', j));
            e.fO = fO;  e.sO = baseline_sha256(fO);  e.O = O;
        end
        e.cls = evidence_class(method, e.P, e.O, incident_of(incs, j));
        ev(j) = e; %#ok<AGROW>
    end

    % ---- the rulings on this unit ---------------------------------------------------
    rents = entries(dec, ['ADJUDICATE_' unit '_a'], ['^ADJUDICATE_' unit '_a(\d+)\.mat$'], unit);
    rk = [rents.k];
    need(all(rk >= 1 & rk <= n), unit, 'a ruling exists for an attempt that never started');
    rfile = @(j) fullfile(dec, sprintf('ADJUDICATE_%s_a%d.mat', unit, j));

    % ---- superseded attempts ---------------------------------------------------------
    recf = mc_record_path(ctx.root, condition, trialId, method);
    hasRec = isfile(recf);
    last = n;
    for j = 1:n
        L.files(end+1, :) = {rel(ctx, ev(j).fS), ev(j).sS};
        if ~isempty(ev(j).fP), L.files(end+1, :) = {rel(ctx, ev(j).fP), ev(j).sP}; end
        if ~isempty(ev(j).fO), L.files(end+1, :) = {rel(ctx, ev(j).fO), ev(j).sO}; end
        if j < last
            f = rfile(j);
            need(isfile(f), unit, sprintf('attempt %d was superseded without a ruling', j));
            D = load_one(f, 'decision', unit);
            need(valid_ruling(D, ctx, condition, trialId, method, j) ...
                && strcmp(D.decision, 'AUTHORISE_NEW_ATTEMPT') ...
                && strcmp(D.evidence_class, 'INTERRUPTED_BEFORE_POST') ...
                && strcmp(ev(j).cls, 'INTERRUPTED_BEFORE_POST') ...
                && strcmp(D.started_sha256, ev(j).sS) && isempty(D.post_sha256) ...
                && isempty(D.outcome_sha256), unit, ...
                sprintf('the ruling that superseded attempt %d is not a valid, permitted ruling bound to it', j));
            L.files(end+1, :) = {rel(ctx, f), baseline_sha256(f)};
        end
    end

    % ---- the latest attempt ------------------------------------------------------------
    if hasRec
        rec = mc_record_read(recf, ctx.binding);
        L.status = 'TERMINAL';
        L.terminal = recf;
        L.record = rec;
        L.attempt = n;
        if strcmp(rec.status_level, 'A')
            need(n == 0 && isempty(rk) && rec.attempt == 0, unit, ...
                'a Level-A record carries attempt 0 and has no ledger file and no ruling');
            return
        end
        need(n >= 1 && rec.attempt == n && ~isempty(ev(n).sP) && ~isempty(ev(n).sO), unit, ...
            'the terminal record is not the latest attempt with STARTED, POST and OUTCOME');
        lg = rec.ledger;
        need(isstruct(lg) && all(isfield(lg, {'started_sha256', 'post_sha256', 'outcome_sha256', ...
            'recovered', 'recovery_decision_sha256'})) && strcmp(lg.started_sha256, ev(n).sS) ...
            && strcmp(lg.post_sha256, ev(n).sP) && strcmp(lg.outcome_sha256, ev(n).sO) ...
            && strcmp(rec.status, ev(n).O.status), unit, ...
            'the terminal record does not carry its attempt''s ledger hashes and status');
        f = rfile(n);
        if isequal(lg.recovered, true)
            need(isfile(f), unit, 'a recovered record has no RECOVER_RECORD ruling');
            D = load_one(f, 'decision', unit);
            ds = baseline_sha256(f);
            need(recover_link(D, ctx, condition, trialId, method, n, ev(n), ds) ...
                && strcmp(lg.recovery_decision_sha256, ds), unit, ...
                'the recovered record is not bound to a valid RECOVER_RECORD ruling');
            L.files(end+1, :) = {rel(ctx, f), ds};
        else
            need(~isfile(f), unit, 'a ruling exists for the terminal attempt of a record that was not recovered');
        end
        return
    end
    if n == 0
        need(isempty(rk), unit, 'a ruling exists for a unit that never started');
        L.status = 'FRESH';
        L.next_attempt = 1;
        return
    end
    e = ev(n);
    L.attempt = n;
    L.evidence = e.cls;
    L.permitted = permitted(e.cls);
    inc = incident_of(incs, n);
    if ~isempty(inc)
        L.incident_file = inc.file;
        L.incident_returned = logical(inc.returned);
        L.incident_guard_status = inc.guard_status;
    end
    L.started = e.sS;  L.post = e.sP;  L.outcome = e.sO;
    L.started_file = e.fS;  L.post_file = e.fP;  L.outcome_file = e.fO;
    f = rfile(n);
    if ~isfile(f)
        L.status = 'AMBIGUOUS';
        return
    end
    D = load_one(f, 'decision', unit);
    ds = baseline_sha256(f);
    L.decision_file = f;  L.decision_sha256 = ds;
    L.files(end+1, :) = {rel(ctx, f), ds};
    switch D.decision
        case 'AUTHORISE_NEW_ATTEMPT'
            need(valid_ruling(D, ctx, condition, trialId, method, n) ...
                && strcmp(e.cls, 'INTERRUPTED_BEFORE_POST') && strcmp(D.evidence_class, e.cls) ...
                && strcmp(D.started_sha256, e.sS) && isempty(D.post_sha256) && isempty(D.outcome_sha256), ...
                unit, 'the AUTHORISE_NEW_ATTEMPT ruling is not valid for the evidence of the latest attempt');
            L.status = 'AUTHORISED_NEW';
            L.next_attempt = n + 1;
        case 'RECOVER_RECORD'
            need(recover_link(D, ctx, condition, trialId, method, n, e, ds), unit, ...
                'the RECOVER_RECORD ruling is not valid for the evidence of the latest attempt');
            L.status = 'RECOVER_AUTHORISED';
        otherwise
            need(false, unit, sprintf('unknown ruling ''%s''', D.decision));
    end
end

% =====================================================================
function c = evidence_class(method, P, O, inc)
    if ~isempty(O)
        c = 'OUTCOME_DURABLE';
    elseif isempty(P)
        if isempty(inc)
            c = 'INTERRUPTED_BEFORE_POST';
        else
            % a HARNESS_ERROR of this very attempt is durable: the missing POST is
            % not evidence of an interruption (Sec. 10.4 / 10.5)
            c = 'INVOCATION_INCIDENT';
        end
    else
        switch P.guard_status
            case 'RETURNED'
                c = 'RETURNED_UNCLASSIFIED';
            case 'PROMOTED_ODE45_FAILURE'
                if strcmp(method, 'proposed')
                    c = 'PROMOTED_FAILURE_OBSERVED';
                else
                    c = 'HARNESS_OBSERVED';          % B1 for a baseline (Sec. 7.2)
                end
            otherwise
                c = 'HARNESS_OBSERVED';
        end
    end
end

% =====================================================================
function r = permitted(cls)
    switch cls
        case 'INTERRUPTED_BEFORE_POST'
            r = {'AUTHORISE_NEW_ATTEMPT'};
        case {'PROMOTED_FAILURE_OBSERVED', 'OUTCOME_DURABLE'}
            r = {'RECOVER_RECORD'};
        otherwise
            % RETURNED_UNCLASSIFIED, HARNESS_OBSERVED, INVOCATION_INCIDENT
            r = {};
    end
end

% =====================================================================
function I = unit_incidents(ctx, unit)
% The HARNESS_ERROR incidents that carry DURABLE evidence of an invocation of
% this unit (MC_RUN_CONDITION writes the block). Incidents without it - e.g. a
% Level-A or cross-condition failure - bind no attempt and are not read here;
% every incident still blocks the campaign through MC_INCIDENT_GATE.
    I = struct('attempt', {}, 'returned', {}, 'guard_status', {}, 'file', {});
    folder = fullfile(ctx.root, 'incidents');
    if ~isfolder(folder), return, end
    d = dir(fullfile(folder, '*.mat'));
    for i = 1:numel(d)
        if contains(d(i).name, '.tmp-'), continue, end
        S = load(fullfile(folder, d(i).name));
        if ~isfield(S, 'incident') || ~isstruct(S.incident) || ~isfield(S.incident, 'invocation')
            continue
        end
        iv = S.incident.invocation;
        if isstruct(iv) && isscalar(iv) && all(isfield(iv, {'unit', 'attempt', 'returned', 'guard_status'})) ...
                && strcmp(iv.unit, unit)
            I(end+1) = struct('attempt', iv.attempt, 'returned', iv.returned, ...
                'guard_status', iv.guard_status, 'file', d(i).name); %#ok<AGROW>
        end
    end
end

% =====================================================================
function inc = incident_of(I, j)
    inc = [];
    for i = 1:numel(I)
        if isequal(I(i).attempt, j)
            inc = I(i);
            return
        end
    end
end

% =====================================================================
function tf = outcome_consistent(method, guardStatus, status)
% The statuses a classification can assign after each guard status (Sec. 7.2).
    if strcmp(method, 'proposed')
        switch guardStatus
            case 'PROMOTED_ODE45_FAILURE'
                ok = {'INTEGRATOR_EXCEPTION'};
            case 'RETURNED'
                ok = {'IC_REFUSED', 'NUMERICAL_FAILURE', 'QP_INFEASIBLE_ABORT', ...
                      'GUARD_BREACH_ABORT', 'COMPLETE'};
            otherwise
                ok = {};
        end
    else
        if strcmp(guardStatus, 'RETURNED')
            ok = {'NUMERICAL_FAILURE', 'COMPLETE'};
        else
            ok = {};
        end
    end
    tf = ischar(status) && any(strcmp(status, ok));
end

% =====================================================================
function tf = recover_link(D, ctx, condition, trialId, method, n, e, ds)
% A RECOVER_RECORD ruling is valid for attempt n when it was permitted by the
% evidence it binds: OUTCOME_DURABLE (bound to that OUTCOME), or the proposed
% method's PROMOTED_FAILURE_OBSERVED (bound to STARTED and POST; the OUTCOME
% that the recovery then wrote names POST as its source and this ruling).
    tf = valid_ruling(D, ctx, condition, trialId, method, n) && strcmp(D.decision, 'RECOVER_RECORD') ...
        && strcmp(D.started_sha256, e.sS) && strcmp(D.post_sha256, e.sP) && ~isempty(e.sP);
    if ~tf, return, end
    switch D.evidence_class
        case 'OUTCOME_DURABLE'
            tf = ~isempty(e.sO) && strcmp(D.outcome_sha256, e.sO) && isempty(e.O.recovered_from);
        case 'PROMOTED_FAILURE_OBSERVED'
            tf = strcmp(method, 'proposed') && strcmp(e.P.guard_status, 'PROMOTED_ODE45_FAILURE') ...
                && isempty(D.outcome_sha256);
            if tf && ~isempty(e.sO)
                tf = strcmp(e.O.recovered_from, 'POST') && strcmp(e.O.recovery_decision_sha256, ds) ...
                    && strcmp(e.O.status, 'INTEGRATOR_EXCEPTION');
            end
        otherwise
            tf = false;
    end
end

% =====================================================================
function tf = valid_ruling(D, ctx, condition, trialId, method, j)
    fields = {'schema', 'decision', 'condition', 'trial_id', 'method', 'attempt', 'evidence_class', ...
              'started_sha256', 'post_sha256', 'outcome_sha256', 'binding', 'operator', 'reason', ...
              'utc', 'process'};
    tf = isstruct(D) && isscalar(D) && all(isfield(D, fields)) ...
        && strcmp(D.schema, 'task4_mc_adjudication_v2') && strcmp(D.condition, condition) ...
        && isequal(D.trial_id, trialId) && strcmp(D.method, method) && isequal(D.attempt, j) ...
        && isequal(D.binding, ctx.binding) && ischar(D.operator) && ~isempty(strtrim(D.operator)) ...
        && ischar(D.reason) && ~isempty(strtrim(D.reason)) && ischar(D.evidence_class);
end

% =====================================================================
function tf = same_unit(A, st, ctx, condition, trialId, method, j)
    tf = isstruct(A) && isscalar(A) ...
        && all(isfield(A, {'schema', 'state', 'binding', 'condition', 'trial_id', 'method', 'attempt'})) ...
        && strcmp(A.schema, 'task4_mc_attempt_v1') && strcmp(A.state, st) ...
        && isequal(A.binding, ctx.binding) && strcmp(A.condition, condition) ...
        && isequal(A.trial_id, trialId) && strcmp(A.method, method) && isequal(A.attempt, j);
end

% =====================================================================
function E = entries(folder, prefix, pattern, unit)
    E = struct('name', {}, 'k', {});
    if ~isfolder(folder), return, end
    d = dir(fullfile(folder, [prefix '*']));
    for i = 1:numel(d)
        if contains(d(i).name, '.tmp-') && ~d(i).isdir
            continue                   % an interrupted write's residue: no state
        end
        tok = regexp(d(i).name, pattern, 'tokens', 'once');
        need(~d(i).isdir && ~isempty(tok), unit, sprintf('unexpected ledger entry %s', d(i).name));
        E(end+1) = struct('name', d(i).name, 'k', str2double(tok{1})); %#ok<AGROW>
    end
end

% =====================================================================
function X = load_one(f, var, unit)
    S = load(f);
    fn = fieldnames(S);
    need(numel(fn) == 1 && strcmp(fn{1}, var) && isstruct(S.(var)) && isscalar(S.(var)), unit, ...
        sprintf('file %s does not hold exactly one ''%s'' struct', f, var));
    X = S.(var);
end

% =====================================================================
function r = rel(ctx, f)
    r = strrep(f(numel(ctx.root) + 2:end), filesep, '/');
end

% =====================================================================
function need(tf, unit, what)
    if ~tf
        error('mc:ledger:history', 'ABORT: the attempt history of %s is invalid: %s.', unit, what);
    end
end

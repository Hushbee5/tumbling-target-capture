function L = mc_run_condition(ctx, condition, shardId)
% MC_RUN_CONDITION  Execute one shard of one condition - the ONLY path to a method run.
%   L = mc_run_condition(ctx, condition, shardId)
%
%   Protocol Sec. 10.3 / 10.4 / 10.5 / R11:
%     - MC_CAMPAIGN_GUARD 'shard_start': live authority (full checkpoint scope),
%       every incident acknowledged, and for Condition M the COMPLETE
%       Condition-U checkpoint re-proven from scratch; its live lease is held
%       for the whole shard;
%     - a CLOSED condition is never executed again ('mc:campaign:condition_closed');
%     - the trial list is READ from the predeclared disjoint shard plan
%       (MC_SHARD_PLAN_READ); no caller chooses trials, so shards cannot overlap;
%     - the shard is OWNED by exactly one MATLAB process: a durable, exclusive
%       shard lock (MC_SHARD_LOCK) is taken before any pair work, and another
%       process's lock stops the shard ('mc:campaign:shard_owned_elsewhere').
%       With at most 3 shards, at most 3 processes ever execute;
%     - trials in increasing trial_id; within a trial the method order
%       proposed, nominal MPC, APF. The pair executor is a LOCAL function of
%       this file: no caller can execute a pair directly, out of order or
%       outside its shard, and the first pair that cannot complete stops the
%       shard, so a later trial never runs before an earlier pending one;
%     - the process pins maxNumCompThreads(1) and records it; the previous value
%       is restored when this function returns;
%     - the shard start is logged atomically before any run;
%     - a HARNESS_ERROR or an ambiguous attempt stops the shard (the error
%       propagates).
%
%   PER PAIR (a guarded boundary of its own)
%     1  MC_CAMPAIGN_GUARD 'pair': live checks again; incidents acknowledged;
%        for Condition M the complete Condition-U checkpoint re-proves
%     2  the plan assigns the trial to this shard and this process owns the
%        shard lock
%     3  no method of the pair may be AMBIGUOUS (MC_ATTEMPT_LEDGER 'state', the
%        strict history validator): it stops the campaign for an operator
%        ruling (MC_OPERATOR_ADJUDICATE_ATTEMPT) - never rerun automatically
%     4  an atomic reservation of the pair (MC_RESERVATION) before any table
%        build or controller call
%   PER METHOD, in the frozen order (guard 'method', live checks again):
%     FRESH / AUTHORISED_NEW  STARTED ledger -> the R18-guarded invocation ->
%        POST ledger (the durable knowledge that the controller ran) -> post-run
%        assertions, classification (Sec. 7.2), outputs (Sec. 6, 7) -> OUTCOME
%        ledger (status and outputs, durable) -> one immutable terminal record
%     RECOVER_AUTHORISED  the terminal record is rebuilt from the durable
%        evidence its ruling names - OUTCOME, or for the proposed method's
%        observed promoted ode45 failure, POST (INTEGRATOR_EXCEPTION) - and the
%        controller is NOT invoked
%     TERMINAL  skipped; a terminal record is never rerun or overwritten.
%   Level-A failures (TARGET_MODEL_INTEGRATION_FAILURE, M_CONSISTENCY_FAILURE)
%   produce three records with attempt 0 and no controller call. The rebuilt
%   Level A of a partially recorded pair must reproduce the stored Level A
%   bitwise; under Condition M the truth must hash identically to the trial's
%   Condition-U records.
%
%   HARNESS_ERROR - an unrelated exception, an integrity failure or an
%   unexpected output - is never a record: an incident file is written (a
%   failure to write it is reported, never swallowed) and the campaign STOPS
%   with 'mc:campaign:harness_error'.
%
%   L fields: condition, shard_id, trial_ids, pairs (trial_id, condition, state,
%   written, skipped, recovered), shard_log (path).

    c = mc_constants();
    gShard = mc_campaign_guard(ctx, 'shard_start', condition); %#ok<NASGU>   % live lease: the shard
    assert(~isfile(fullfile(ctx.root, sprintf('%s_CLOSED.mat', condition))), ...
        'mc:campaign:condition_closed', 'REFUSED: condition %s is closed; its checkpoint is final.', condition);
    plan = mc_shard_plan_read(ctx, condition);
    k = find(strcmp(plan.shard_ids, shardId), 1);
    assert(~isempty(k), 'mc:plan:unknown_shard', ...
        'REFUSED: shard %s is not in the %s plan (%s).', shardId, condition, strjoin(plan.shard_ids, ', '));
    trialIds = plan.shards{k};
    mc_shard_lock('acquire', ctx, condition, shardId);

    prevThreads = maxNumCompThreads(c.exec.max_num_comp_threads);
    restoreThreads = onCleanup(@() maxNumCompThreads(prevThreads));
    ctx.env.max_num_comp_threads = maxNumCompThreads;
    ctx.env.shard_id = shardId;
    ctx.env.process  = mc_process_identity();
    assert(ctx.env.max_num_comp_threads == c.exec.max_num_comp_threads, ...
        'mc:campaign:threads', 'maxNumCompThreads could not be pinned to 1 (R11).');

    folder = fullfile(ctx.root, 'shards');
    if ~isfolder(folder), mkdir(folder); end
    stamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmssSSS'));
    logf = fullfile(folder, sprintf('%s_%s_%s.mat', condition, shardId, stamp));
    shard = struct('condition', condition, 'shard_id', shardId, 'trial_ids', trialIds, ...
        'process', mc_process_identity(), 'max_num_comp_threads', ctx.env.max_num_comp_threads, ...
        'binding', ctx.binding, 'created_utc', mc_utc_now());
    opts = struct();
    if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
    mc_atomic_write(logf, struct('shard', shard), 'mat', opts);

    L = struct('condition', condition, 'shard_id', shardId, 'trial_ids', trialIds, ...
               'pairs', struct('trial_id', {}, 'condition', {}, 'state', {}, ...
                               'written', {}, 'skipped', {}, 'recovered', {}), 'shard_log', logf);
    for id = trialIds
        L.pairs(end+1) = run_pair(ctx, id, condition, shardId);
    end
    clear restoreThreads
end

% =====================================================================
function S = run_pair(ctx, trialId, condition, shardId)
% One (trial, condition): Level A, then the three methods. LOCAL - reachable only
% from the shard loop above, in the plan's order.
    c = mc_constants();
    methods = c.design.methods;
    S = struct('trial_id', trialId, 'condition', condition, 'state', '', ...
               'written', {{}}, 'skipped', {{}}, 'recovered', {{}});

    gPair = mc_campaign_guard(ctx, 'pair', condition, trialId); %#ok<NASGU>   % live lease: the pair
    [~, shardOf] = mc_shard_plan_read(ctx, condition);
    assert(strcmp(shardOf(trialId), shardId), 'mc:plan:foreign_trial', ...
        'REFUSED: trial %d belongs to shard %s, not to shard %s.', trialId, shardOf(trialId), shardId);
    mc_shard_lock('assert_owned', ctx, condition, shardId);

    scan = mc_record_scan(ctx.root, condition, ctx.binding, trialId);
    for mi = 1:numel(methods)
        st = mc_attempt_ledger('state', ctx, condition, trialId, methods{mi});
        stop_if_ambiguous(st);
    end
    if all(scan.present)
        S.state = 'ALREADY_COMPLETE';
        S.skipped = methods;
        return
    end
    mc_reservation('acquire', ctx, condition, trialId, shardId);
    row = mc_trial_row(ctx.trials, trialId);

    % ---- Level A ------------------------------------------------------------
    try
        A = mc_shared_tables(row, condition, ctx.pBL, ctx.Tsim);
    catch ME
        harness_stop(ctx, trialId, condition, 'LEVEL_A', mc_exception_summary(ME));
    end
    if strcmp(A.status, 'HARNESS_ERROR')
        harness_stop(ctx, trialId, condition, 'LEVEL_A', A.exception_info);
    end
    LA = struct('status', A.status, 'guard_status', A.guard_status, ...
                'exception', A.exception_info, 'v2c', A.v2c, 'diag', A.diag, ...
                'hash', A.hash, 'wall_s', A.wall_s, 'truthIC', A.truthIC, 'prevIC', A.prevIC);
    for mi = find(scan.present(1, :))
        prev = mc_record_read(scan.paths{1, mi}, ctx.binding);
        if ~(isequal(prev.level_a.status, LA.status) && isequal(prev.level_a.hash, LA.hash) ...
                && isequaln(prev.level_a.diag, LA.diag))
            harness_stop(ctx, trialId, condition, 'RESUME_MISMATCH', struct('identifier', ...
                'mc:campaign:resume_mismatch', 'message', ...
                'the rebuilt Level-A block differs from the stored one', 'stack', []));
        end
    end
    if strcmp(condition, 'M')
        cross_condition_truth(ctx, row, LA);
    end

    % ---- Level-A failure: three complete records, no controller call ---------
    if ~strcmp(A.status, 'TABLES_OK')
        for mi = 1:numel(methods)
            if scan.present(1, mi)
                S.skipped{end+1} = methods{mi};
                continue
            end
            R = mc_run_outputs(methods{mi}, condition, A.status, [], [], ctx.pBL);
            guard = struct('status', 'NOT_INVOKED', 'exception', mc_exception_summary([]), ...
                           'n_invocations', 0);
            info = struct('rule', level_a_rule(A.status), 'reason', 'Level-A status; not executed');
            rec = build_record(ctx, row, condition, methods{mi}, LA, A.status, 'A', info, ...
                               guard, R, [], NaN, 0, no_ledger());
            mc_record_write(ctx, rec);
            S.written{end+1} = methods{mi};
        end
        S.state = A.status;
        return
    end

    % ---- the three methods, in the frozen order --------------------------------
    for mi = 1:numel(methods)
        method = methods{mi};
        if scan.present(1, mi)
            S.skipped{end+1} = method;
            continue
        end
        gMethod = mc_campaign_guard(ctx, 'method', condition, trialId); %#ok<NASGU>   % live lease: the method
        st = mc_attempt_ledger('state', ctx, condition, trialId, method);
        if strcmp(st.status, 'RECOVER_AUTHORISED')
            try
                recover_record(ctx, row, condition, method, LA, st);
            catch ME
                if strcmp(ME.identifier, 'mc:campaign:harness_error')
                    rethrow(ME);
                end
                harness_stop(ctx, trialId, condition, [upper(method) '_RECOVER'], mc_exception_summary(ME));
            end
            S.written{end+1} = method;
            S.recovered{end+1} = method;
            continue
        end
        assert(any(strcmp(st.status, {'FRESH', 'AUTHORISED_NEW'})), 'mc:campaign:ambiguous_attempt', ...
            'STOP: %s is %s; it is never started automatically.', st.unit, st.status);
        k = st.next_attempt;

        mc_fault_hook('hit', ['before_started:' method]);
        Ls = mc_attempt_ledger('start', ctx, condition, trialId, method, k, shardId);
        mc_fault_hook('hit', ['after_started:' method]);
        try
            [obj, gInfo, wall] = invoke(ctx, method, row, A);
        catch ME
            harness_stop(ctx, trialId, condition, [upper(method) '_INVOKE'], mc_exception_summary(ME), ...
                struct(), invocation_evidence(condition, trialId, method, k, false, [], NaN));
        end
        mc_fault_hook('hit', ['after_invoke:' method]);
        iv = invocation_evidence(condition, trialId, method, k, true, gInfo, wall);
        try
            mc_fault_hook('hit', ['post_write:' method]);
            Lp = mc_attempt_ledger('post', ctx, condition, trialId, method, k, ...
                struct('guard_status', gInfo.status, 'exception', gInfo.exception_info, 'wall_s', wall));
        catch ME
            harness_stop(ctx, trialId, condition, [upper(method) '_POST_WRITE'], ...
                mc_exception_summary(ME), struct(), iv);
        end
        mc_fault_hook('hit', ['after_post:' method]);

        try
            if strcmp(gInfo.status, 'RETURNED')
                mc_postrun_check(method, obj, A, row);
            end
            if strcmp(method, 'proposed')
                [status, info] = mc_classify_proposed(gInfo.status, obj.out, ctx.K_expected);
                mask = info.mask;
            else
                [status, info] = mc_classify_baseline(gInfo.status, obj, method, ctx.K_expected);
                mask = [];
            end
            if strcmp(status, 'HARNESS_ERROR')
                harness_stop(ctx, trialId, condition, upper(method), gInfo.exception_info, info, iv);
            end
            mc_fault_hook('hit', ['record_build:' method]);
            R = mc_run_outputs(method, condition, status, obj, A.tabs, ctx.pBL);
            g = struct('status', gInfo.status, 'exception', gInfo.exception_info, ...
                       'n_invocations', gInfo.n_invocations);
            Lo = mc_attempt_ledger('outcome', ctx, condition, trialId, method, k, ...
                outcome_block(status, info, mask, R, g, wall, LA.hash, '', ''));
            mc_fault_hook('hit', ['after_outcome:' method]);
            ledger = struct('started_file', Ls.file, 'started_sha256', Ls.sha256, ...
                            'post_file', Lp.file, 'post_sha256', Lp.sha256, ...
                            'outcome_file', Lo.file, 'outcome_sha256', Lo.sha256, ...
                            'recovered', false, 'recovery_decision_sha256', '');
            rec = build_record(ctx, row, condition, method, LA, status, 'B', info, g, R, ...
                               mask, wall, k, ledger);
            mc_record_write(ctx, rec, ['record_atomic_before_rename:' method]);
        catch ME
            if strcmp(ME.identifier, 'mc:campaign:harness_error')
                rethrow(ME);
            end
            harness_stop(ctx, trialId, condition, upper(method), mc_exception_summary(ME), struct(), iv);
        end
        S.written{end+1} = method;
    end
    S.state = 'EXECUTED';
end

% =====================================================================
function recover_record(ctx, row, condition, method, LA, st)
% The terminal record of attempt st.attempt, rebuilt from DURABLE evidence under
% a RECOVER_RECORD ruling. The controller is not invoked.
    trialId = row.trial_id;
    if isempty(st.outcome)
        % PROMOTED_FAILURE_OBSERVED: B2 follows from POST alone (Sec. 7.2, 7.4)
        S = load(st.post_file, 'attempt');
        P = S.attempt;
        assert(strcmp(method, 'proposed') && strcmp(P.guard_status, 'PROMOTED_ODE45_FAILURE'), ...
            'mc:campaign:recover', 'Only the proposed method''s promoted failure is recovered from POST.');
        [status, info] = mc_classify_proposed(P.guard_status, [], ctx.K_expected);
        R = mc_run_outputs(method, condition, status, [], [], ctx.pBL);
        g = struct('status', P.guard_status, 'exception', P.exception, 'n_invocations', 1);
        oc = outcome_block(status, info, [], R, g, P.wall_s, LA.hash, 'POST', st.decision_sha256);
        Lo = mc_attempt_ledger('outcome', ctx, condition, trialId, method, st.attempt, oc);
    else
        S = load(st.outcome_file, 'attempt');
        O = S.attempt;
        assert(isequal(O.level_a_hash, LA.hash), 'mc:campaign:resume_mismatch', ...
            'The rebuilt Level A differs from the one the OUTCOME was computed with.');
        oc = struct('status', O.status, 'rule', O.status_rule, 'reason', O.status_reason, ...
                    'mask', O.mask, 'outputs', O.outputs, 'guard', O.guard, 'wall_s', O.wall_s);
        Lo = struct('file', st.outcome_file, 'sha256', st.outcome);
    end
    ledger = struct('started_file', st.started_file, 'started_sha256', st.started, ...
                    'post_file', st.post_file, 'post_sha256', st.post, ...
                    'outcome_file', Lo.file, 'outcome_sha256', Lo.sha256, ...
                    'recovered', true, 'recovery_decision_sha256', st.decision_sha256);
    info = struct('rule', oc.rule, 'reason', oc.reason);
    rec = build_record(ctx, row, condition, method, LA, oc.status, 'B', info, oc.guard, ...
                       oc.outputs, oc.mask, oc.wall_s, st.attempt, ledger);
    mc_record_write(ctx, rec, ['record_atomic_before_rename:' method]);
end

% =====================================================================
function iv = invocation_evidence(condition, trialId, method, k, returned, gInfo, wall)
% What is durably known about ONE invocation of ONE attempt, recorded in the
% incident so that a later restart cannot mistake it for an interruption.
    iv = struct('unit', sprintf('%s_t%03d_%s', condition, trialId, method), ...
                'condition', condition, 'trial_id', trialId, 'method', method, 'attempt', k, ...
                'returned', returned, 'guard_status', '', 'exception', mc_exception_summary([]), ...
                'wall_s', NaN);
    if returned
        iv.guard_status = gInfo.status;
        iv.exception = gInfo.exception_info;
        iv.wall_s = wall;
    end
end

% =====================================================================
function oc = outcome_block(status, info, mask, R, g, wall, laHash, from, decSha)
    oc = struct();
    oc.status = status;
    oc.rule = info.rule;
    oc.reason = info.reason;
    oc.mask = mask;
    oc.outputs = R;
    oc.guard = g;
    oc.wall_s = wall;
    oc.level_a_hash = laHash;
    oc.recovered_from = from;
    oc.recovery_decision_sha256 = decSha;
end

% =====================================================================
function lg = no_ledger()
    lg = struct('started_file', '', 'started_sha256', '', 'post_file', '', 'post_sha256', '', ...
                'outcome_file', '', 'outcome_sha256', '', 'recovered', false, ...
                'recovery_decision_sha256', '');
end

% =====================================================================
function stop_if_ambiguous(st)
    if strcmp(st.status, 'AMBIGUOUS')
        if isempty(st.permitted)
            what = 'no operator ruling is permitted: STOPPED for the reviewer';
        else
            what = ['permitted operator ruling: ' strjoin(st.permitted, ', ')];
        end
        error('mc:campaign:ambiguous_attempt', ...
            ['STOP: %s attempt %d has no terminal record (evidence %s). It is never rerun ' ...
             'automatically; %s (MC_OPERATOR_ADJUDICATE_ATTEMPT).'], st.unit, st.attempt, ...
            st.evidence, what);
    end
end

% =====================================================================
function [obj, gInfo, wall] = invoke(ctx, method, row, A)
% The R18-guarded invocation. A runner override exists only in verification
% contexts (the guard refuses one in any scientific context).
    if isfield(ctx.runner_override, method)
        X = ctx.runner_override.(method)(row, A, ctx.Tsim);
    elseif strcmp(method, 'proposed')
        X = mc_invoke_proposed(row, A, ctx.Tsim);
    else
        X = mc_invoke_baseline(method, row, A, ctx.Tsim, ctx.pBL, ctx.apf.theta);
    end
    gInfo = X.guard;
    wall  = X.wall_s;
    if strcmp(method, 'proposed')
        obj = struct('out', X.out, 'act_thresh', X.act_thresh);
    else
        obj = X.run;
    end
end

% =====================================================================
function rec = build_record(ctx, row, condition, method, LA, status, level, info, guard, R, ...
                            mask, wall, attempt, ledger)
    rec.schema        = 'task4_mc_run_record_v2';
    rec.kind          = ctx.record_kind;
    rec.binding       = ctx.binding;
    rec.condition     = condition;
    rec.trial_id      = row.trial_id;
    rec.method        = method;
    rec.trial         = struct('x0', row.x0, 'q0', row.q0, 'w0', row.w0, 'Idiag', row.Idiag, ...
                               'I_prev', LA.prevIC.I);
    rec.level_a       = LA;
    rec.status        = status;
    rec.status_level  = level;
    rec.status_rule   = info.rule;
    rec.status_reason = info.reason;
    rec.guard         = guard;
    rec.outputs       = R;
    if isempty(mask)
        rec.mask = struct('evaluated', false);
    else
        rec.mask = struct('evaluated', true, 'nonfinite', {mask.nonfinite}, ...
                          'structure', {mask.structure}, 'domain', mask.domain);
    end
    rec.attempt       = attempt;
    rec.ledger        = ledger;
    rec.process       = ctx.env.process;
    rec.shard_id      = ctx.env.shard_id;
    rec.timing        = struct('wall_s', wall, 'note', 'WALL-CLOCK; operational only');
    rec.environment   = rmfield(ctx.env, {'process', 'shard_id'});
    rec.horizon       = struct('Tsim', ctx.Tsim, 'K_expected', ctx.K_expected);
    rec.created_utc   = mc_utc_now();
end

% =====================================================================
function r = level_a_rule(status)
    switch status
        case 'TARGET_MODEL_INTEGRATION_FAILURE', r = 'A1';
        case 'M_CONSISTENCY_FAILURE',            r = 'A2';
        otherwise,                                r = 'A?';
    end
end

% =====================================================================
function cross_condition_truth(ctx, row, LA)
% Condition M of trial i must see the bitwise-identical physical truth that
% Condition U of trial i saw. The U checkpoint was re-proven by the guard.
    trialId = row.trial_id;
    scanU = mc_record_scan(ctx.root, 'U', ctx.binding, trialId);
    k = find(scanU.present(1, :), 1);
    if isempty(k)
        harness_stop(ctx, trialId, 'M', 'CROSS_CONDITION', struct('identifier', ...
            'mc:campaign:no_u_record', 'message', ...
            'Condition M ran before any Condition-U record of this trial existed', 'stack', []));
    end
    recU = mc_record_read(scanU.paths{1, k}, ctx.binding);
    if ~(isequal(recU.trial.x0, row.x0) && isequal(recU.level_a.truthIC, LA.truthIC))
        harness_stop(ctx, trialId, 'M', 'CROSS_CONDITION', struct('identifier', ...
            'mc:integrity:cross_condition_trial', 'message', ...
            'Condition U and Condition M describe different physical trials', 'stack', []));
    end
    hU = recU.level_a.hash;
    if isempty(hU) || isempty(LA.hash)
        return      % a TARGET_MODEL_INTEGRATION_FAILURE left no table to compare
    end
    f = {'qT', 'wT', 'p_cp_truth', 'v_cp_truth', 'n_cp_truth'};
    for i = 1:numel(f)
        if ~strcmp(hU.(f{i}), LA.hash.(f{i}))
            harness_stop(ctx, trialId, 'M', 'CROSS_CONDITION', struct('identifier', ...
                'mc:integrity:cross_condition_truth', 'message', ...
                sprintf('truth %s of Condition M differs from Condition U', f{i}), 'stack', []));
        end
    end
end

% =====================================================================
function harness_stop(ctx, trialId, condition, stage, exInfo, classInfo, invocation)
% Write an incident (never a checkpoint record) and STOP. A failure to write the
% incident is reported in the error itself, never swallowed; the attempt
% ledger blocks any automatic rerun either way.
%
%   invocation (optional) is the DURABLE EVIDENCE of the method invocation this
%   incident belongs to: unit, attempt and - when the invocation had already
%   RETURNED to the harness - its guard status, exception summary and wall time.
%   MC_ATTEMPT_LEDGER reads it: an attempt whose incident says the controller
%   returned is NOT an interrupted attempt, whatever the POST ledger is missing,
%   so the absence of POST alone can never be taken for an OS/process
%   interruption (protocol Sec. 10.4 / 10.5).
    if nargin < 6, classInfo = struct(); end
    if nargin < 7, invocation = []; end
    folder = fullfile(ctx.root, 'incidents');
    stamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmssSSS'));
    f = fullfile(folder, sprintf('HARNESS_ERROR_%s_t%03d_%s_%s.mat', condition, trialId, stage, stamp));
    incident = struct('kind', ctx.record_kind, 'binding', ctx.binding, 'condition', condition, ...
        'trial_id', trialId, 'stage', stage, 'exception', exInfo, 'classification', classInfo, ...
        'invocation', invocation, ...
        'process', mc_process_identity(), 'created_utc', mc_utc_now(), ...
        'note', 'HARNESS_ERROR: not a checkpoint record; the campaign stopped (Sec. 7.2, 10.4).');
    writeErr = '';
    try
        if ~isfolder(folder), mkdir(folder); end
        mc_fault_hook('hit', 'incident_write');
        opts = struct();
        if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
        mc_atomic_write(f, struct('incident', incident), 'mat', opts);
    catch WE
        writeErr = sprintf('%s: %s', WE.identifier, WE.message);
        fprintf(2, 'MC HARNESS_ERROR: INCIDENT NOT WRITTEN (%s)\n', writeErr);
    end
    msg = '';
    if isstruct(exInfo) && isfield(exInfo, 'message'), msg = exInfo.message; end
    if isempty(writeErr)
        error('mc:campaign:harness_error', ...
            'HARNESS_ERROR at %s trial %d stage %s: %s. The campaign STOPS. Incident: %s', ...
            condition, trialId, stage, msg, f);
    else
        error('mc:campaign:harness_error', ...
            ['HARNESS_ERROR at %s trial %d stage %s: %s. The campaign STOPS. INCIDENT NOT ' ...
             'WRITTEN (%s). The attempt ledger still blocks every automatic rerun.'], ...
            condition, trialId, stage, msg, writeErr);
    end
end

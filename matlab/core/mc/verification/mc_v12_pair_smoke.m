function R = mc_v12_pair_smoke(tmpRoot)
% MC_V12_PAIR_SMOKE  End-to-end orchestration on a FIXTURE trial, 3 s horizon. NON-SCIENTIFIC.
%   One fixture-seed trial row (seed 911, not the scientific seed) is run
%   through the real orchestration - predeclared shard plan, shard lock,
%   reservation, Level A, the three REAL methods in order, attempt ledger
%   (STARTED, POST, OUTCOME), classification, outputs, immutable records - in a
%   VERIFICATION context whose checkpoint lies outside the repository:
%     Condition U; rerun = no write and no change (immutability, no retry);
%     Condition M refused before the U closure; U closure; Condition M
%     (cross-condition truth identity enforced); a terminal record lost after
%     its controller ran (STARTED, POST and OUTCOME present, no record) is
%     AMBIGUOUS with evidence OUTCOME_DURABLE: the campaign STOPS without
%     re-invoking anything, a new attempt is REFUSED, and a RECOVER_RECORD
%     ruling rebuilds the identical record from the OUTCOME without any
%     controller call; a HARNESS_ERROR incident stops every shard and the
%     Condition-U verification until a person acknowledges it with a
%     content-bound acknowledgement; the aggregation barrier refuses an
%     incomplete set; aggregation runs on the complete fixture set; the M
%     closure re-proves the recovered history and the incident; a closed
%     condition is never executed again; there is no public pair executor;
%     maxNumCompThreads was pinned to 1 and restored; the wall time per method
%     is reported (operational).

    R.name = 'V12 end-to-end fixture pair (3 s)';
    ch = {};
    c = mc_constants();
    T = mc_fixture_trial_table(911, 2);
    ck = fullfile(tmpRoot, 'ckpt12');
    ctx = mc_context('verification', ck, 3, T, 1);
    mc_shard_plan(ctx, 'U', {1}, 'fixture-operator');
    mc_shard_plan(ctx, 'M', {1}, 'fixture-operator');
    thr0 = maxNumCompThreads;

    LU = mc_run_condition(ctx, 'U', 'S1');
    scanU = mc_record_scan(ck, 'U', ctx.binding, 1);
    ch{end+1} = mc_vt_check('Condition U: three records written in method order', ...
        all(scanU.present) && isequal(LU.pairs(1).written, c.design.methods), ...
        strjoin(scanU.status, ', '));
    recP = mc_record_read(scanU.paths{1, 1}, ctx.binding);
    ch{end+1} = mc_vt_check('records are VERIFICATION-bound and carry the fixture horizon', ...
        strcmp(recP.kind, 'VERIFICATION') && strcmp(recP.binding.mode, 'VERIFICATION_ONLY') ...
        && recP.horizon.Tsim == 3 && recP.horizon.K_expected == 30);
    me = mc_process_identity();
    ch{end+1} = mc_vt_check('records carry attempt 1, the STARTED/POST/OUTCOME hashes, the process and the shard', ...
        recP.attempt == 1 && ~isempty(recP.ledger.started_sha256) && ~isempty(recP.ledger.post_sha256) ...
        && ~isempty(recP.ledger.outcome_sha256) && isequal(recP.ledger.recovered, false) ...
        && strcmp(recP.shard_id, 'S1') && strcmp(recP.process.nonce, me.nonce));
    lk = mc_shard_lock('owner', ctx, 'U', 'S1');
    ch{end+1} = mc_vt_check('the shard is locked by this process', ...
        lk.exists && strcmp(lk.owner.process.nonce, me.nonce));
    ch{end+1} = mc_vt_check('maxNumCompThreads pinned to 1 during the run, restored after', ...
        recP.environment.max_num_comp_threads == 1 && maxNumCompThreads == thr0, ...
        sprintf('recorded %g, now %g', recP.environment.max_num_comp_threads, maxNumCompThreads));
    ch{end+1} = mc_vt_check('informational: fixture statuses', true, strjoin(scanU.status, ', '));

    h0 = cellfun(@baseline_sha256, scanU.paths, 'UniformOutput', false);
    LU2 = mc_run_condition(ctx, 'U', 'S1');
    h1 = cellfun(@baseline_sha256, scanU.paths, 'UniformOutput', false);
    ch{end+1} = mc_vt_check('rerun of a complete pair writes nothing and changes nothing', ...
        strcmp(LU2.pairs(1).state, 'ALREADY_COMPLETE') && isempty(LU2.pairs(1).written) ...
        && isequal(h0, h1));
    [ok, got] = mc_vt_throws(@() mc_run_pair(ctx, 1, 'U'), 'mc:campaign:no_direct_pair');
    ch{end+1} = mc_vt_check('there is no public pair executor (old entry point refuses)', ok, got);

    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'M', 'S1'), 'mc:closure:missing');
    ch{end+1} = mc_vt_check('Condition M is refused before the Condition-U checkpoint is closed', ok, got);
    CU = mc_close_condition(ctx, 'U', 'close');
    ch{end+1} = mc_vt_check('Condition-U closure lists every record and its history with SHA-256', ...
        CU.n_expected == 3 && numel(CU.manifest) == 3 && ~isempty(CU.history) ...
        && isfile(fullfile(ck, 'U_CLOSED.mat')), sprintf('%d history entries', numel(CU.history)));

    mc_run_condition(ctx, 'M', 'S1');
    scanM = mc_record_scan(ck, 'M', ctx.binding, 1);
    ch{end+1} = mc_vt_check('Condition M: three records (cross-condition truth identity enforced)', ...
        all(scanM.present), strjoin(scanM.status, ', '));
    recMp = mc_record_read(scanM.paths{1, 1}, ctx.binding);
    ch{end+1} = mc_vt_check('U and M of the trial share the truth hashes and the physical row', ...
        isequal(recMp.level_a.hash.qT, recP.level_a.hash.qT) ...
        && isequal(recMp.level_a.hash.p_cp_truth, recP.level_a.hash.p_cp_truth) ...
        && isequal(recMp.trial.x0, recP.trial.x0) && ~isequal(recMp.trial.I_prev, recP.trial.I_prev));

    % a terminal record lost AFTER its controller ran: STARTED, POST and OUTCOME exist
    old = mc_record_read(scanM.paths{1, 3}, ctx.binding);
    delete(scanM.paths{1, 3});
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'M', 'S1'), 'mc:campaign:ambiguous_attempt');
    st = mc_attempt_ledger('state', ctx, 'M', 1, 'apf');
    ch{end+1} = mc_vt_check('a lost record after execution is AMBIGUOUS (OUTCOME_DURABLE): STOP, nothing re-invoked', ...
        ok && ~isfile(scanM.paths{1, 3}) && strcmp(st.evidence, 'OUTCOME_DURABLE') ...
        && isequal(st.permitted, {'RECOVER_RECORD'}) ...
        && numel(dir(fullfile(ck, 'attempts', 'M_t001_apf_a*_STARTED.mat'))) == 1, got);
    [ok, got] = mc_vt_throws(@() mc_operator_adjudicate_attempt(ctx, 'M', 1, 'apf', 1, ...
        'AUTHORISE_NEW_ATTEMPT', 'fixture-operator', 'try a rerun'), 'mc:operator:not_permitted');
    ch{end+1} = mc_vt_check('a new attempt is refused when the outcome is durable', ok, got);
    mc_operator_adjudicate_attempt(ctx, 'M', 1, 'apf', 1, 'RECOVER_RECORD', ...
        'fixture-operator', 'fixture: the terminal record was removed by the fixture');
    L3 = mc_run_condition(ctx, 'M', 'S1');
    new = mc_record_read(scanM.paths{1, 3}, ctx.binding);
    ch{end+1} = mc_vt_check('RECOVER_RECORD rebuilds only that record, from the OUTCOME, with no controller call', ...
        isequal(L3.pairs(1).written, {'apf'}) && isequal(L3.pairs(1).recovered, {'apf'}) ...
        && isequal(L3.pairs(1).skipped, {'proposed', 'nominal_mpc'}) && new.attempt == 1 ...
        && isequal(new.ledger.recovered, true) ...
        && numel(dir(fullfile(ck, 'attempts', 'M_t001_apf_a*_STARTED.mat'))) == 1);
    ch{end+1} = mc_vt_check('the recovered record reproduces status, Level A (except wall time) and every output', ...
        strcmp(old.status, new.status) ...
        && isequaln(rmfield(old.level_a, 'wall_s'), rmfield(new.level_a, 'wall_s')) ...
        && isequaln(old.outputs, new.outputs));

    % a HARNESS_ERROR incident stops every shard and the U verification until a
    % person records a content-bound acknowledgement
    inc = fullfile(ck, 'incidents');
    if ~isfolder(inc), mkdir(inc); end
    incF = fullfile(inc, 'HARNESS_ERROR_M_t001_FIXTURE_20260911T000000000.mat');
    incident = struct('note', 'synthetic fixture incident'); %#ok<NASGU>
    save(incF, 'incident');
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'M', 'S1'), 'mc:campaign:unacknowledged_incident');
    ch{end+1} = mc_vt_check('an unacknowledged HARNESS_ERROR incident stops the campaign', ok, got);
    [ok, got] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'verify'), ...
        'mc:campaign:unacknowledged_incident');
    ch{end+1} = mc_vt_check('an unacknowledged incident also blocks closure verification', ok, got);
    mc_operator_acknowledge_incident(ctx, incF, 'reviewed: synthetic fixture incident', 'fixture-operator');
    L4 = mc_run_condition(ctx, 'M', 'S1');
    ch{end+1} = mc_vt_check('after a content-bound acknowledgement the campaign may continue', ...
        strcmp(L4.pairs(1).state, 'ALREADY_COMPLETE') && isempty(L4.pairs(1).written));

    recsU = load_all(scanU, ctx);
    recsM = load_all(mc_record_scan(ck, 'M', ctx.binding, 1), ctx);
    [ok, got] = mc_vt_throws(@() mc_aggregate('NON_SCIENTIFIC', 'condition', recsU(1:2), 1), ...
        'mc:aggregate:barrier');
    ch{end+1} = mc_vt_check('aggregation barrier refuses an incomplete record set', ok, got);
    [ok, got] = mc_vt_throws(@() mc_aggregate('NON_SCIENTIFIC', 'condition', [recsU, recsM], 1), ...
        'mc:aggregate:pooled');
    ch{end+1} = mc_vt_check('aggregation never pools U and M', ok, got);
    GU = mc_aggregate('NON_SCIENTIFIC', 'condition', recsU, 1);
    s = GU.outcome_flags.proposed.geometric_proximity_achieved;
    ch{end+1} = mc_vt_check('aggregation on real fixture records: breakdown sums to n', ...
        s.TRUE + s.FALSE + s.NOT_EXECUTED + s.UNKNOWN == 1 && GU.n == 1 ...
        && strcmp(GU.scope, 'NON_SCIENTIFIC'));
    CM = mc_close_condition(ctx, 'M', 'close');
    hm = {CM.history.file};
    ch{end+1} = mc_vt_check('Condition-M closure re-proves the recovered history, the ruling, the incident and its acknowledgement', ...
        numel(CM.manifest) == 3 && CM.manifest(3).attempt == 1 ...
        && any(strcmp(hm, 'decisions/ADJUDICATE_M_t001_apf_a1.mat')) ...
        && any(strcmp(hm, 'attempts/M_t001_apf_a1_OUTCOME.mat')) ...
        && any(strcmp(hm, ['incidents/' 'HARNESS_ERROR_M_t001_FIXTURE_20260911T000000000.mat'])) ...
        && any(startsWith(hm, 'acknowledgements/ACK_')));
    [ok, got] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'verify'), 'NO_ERROR');
    ch{end+1} = mc_vt_check('the Condition-U closure still verifies with the Condition-M artefacts present', ok, got);
    X = mc_aggregate('NON_SCIENTIFIC', 'cross', recsU, recsM, 1);
    ch{end+1} = mc_vt_check('cross-condition 2x2 per method is computed', ...
        isfield(X.proximity_2x2, 'proposed') && isfield(X.proximity_2x2, 'apf'));
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), 'mc:campaign:condition_closed');
    ch{end+1} = mc_vt_check('a closed condition is never executed again', ok, got);

    % operational timing of this 3 s fixture pair (wall clock, informational)
    tx = '';
    for i = 1:numel(recsU)
        tx = sprintf('%s%s %.1f s; ', tx, recsU{i}.method, recsU{i}.timing.wall_s);
    end
    ch{end+1} = mc_vt_check('informational: wall time per method (3 s horizon, Condition U)', true, ...
        sprintf('%stable build %.1f s', tx, recsU{1}.level_a.wall_s));
    R.checks = [ch{:}];
end

% =====================================================================
function recs = load_all(scan, ctx)
    recs = cell(1, numel(scan.paths));
    for i = 1:numel(scan.paths)
        recs{i} = mc_record_read(scan.paths{i}, ctx.binding);
    end
end

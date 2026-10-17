function info = mc_record_write(ctx, rec, hook)
% MC_RECORD_WRITE  Write one CHECKPOINT-COMPLETE record, atomically, exactly once.
%   info = mc_record_write(ctx, rec)
%   info = mc_record_write(ctx, rec, hook)     hook: fault point (fixtures only)
%
%   Protocol Sec. 10.4: a per-(trial, condition, method) record is
%   checkpoint-complete once written; every recorded status - refusals,
%   pre-run failures, aborts, numerical failures - is a complete record;
%   writes are atomic; a completed record is NEVER overwritten
%   (MC_ATOMIC_WRITE). HARNESS_ERROR is never a record.
%
%   AUTHORITY, checked before anything is written:
%     - the context is sealed and issued, and the write happens inside a live
%       boundary (MC_CAMPAIGN_GUARD 'write'); a scientific record is written
%       only inside that context's checkpoint;
%     - the record carries exactly the context's binding and record kind;
%     - THIS process holds the reservation of the (condition, trial) pair
%       (MC_RESERVATION 'assert_owned');
%     - a Level-B record names attempt k >= 1 whose STARTED, POST and OUTCOME
%       ledger files exist with the SHA-256 the record carries, and a
%       recovered record the SHA-256 of its RECOVER_RECORD ruling; a Level-A
%       record has attempt 0. (The complete history is re-proven at closure by
%       MC_ATTEMPT_LEDGER 'state'.)

    if nargin < 3, hook = ''; end
    mc_campaign_guard(ctx, 'write');
    mc_record_validate(rec);
    assert(~strcmp(rec.status, 'HARNESS_ERROR'), 'mc:record:harness', ...
        'HARNESS_ERROR is never a checkpoint record.');
    assert(isequal(rec.binding, ctx.binding) && strcmp(rec.kind, ctx.record_kind), ...
        'mc:record:binding', 'The record does not carry this campaign''s binding and kind.');
    mc_reservation('assert_owned', ctx, rec.condition, rec.trial_id);

    unit = sprintf('%s_t%03d_%s', rec.condition, rec.trial_id, rec.method);
    if strcmp(rec.status_level, 'B')
        att = fullfile(ctx.root, 'attempts');
        fS = fullfile(att, sprintf('%s_a%d_STARTED.mat', unit, rec.attempt));
        fP = fullfile(att, sprintf('%s_a%d_POST.mat', unit, rec.attempt));
        fO = fullfile(att, sprintf('%s_a%d_OUTCOME.mat', unit, rec.attempt));
        lg = rec.ledger;
        assert(rec.attempt >= 1 && isfile(fS) && isfile(fP) && isfile(fO) && isstruct(lg) ...
            && all(isfield(lg, {'started_sha256', 'post_sha256', 'outcome_sha256', 'recovered', ...
                                'recovery_decision_sha256'})) ...
            && strcmp(baseline_sha256(fS), lg.started_sha256) ...
            && strcmp(baseline_sha256(fP), lg.post_sha256) ...
            && strcmp(baseline_sha256(fO), lg.outcome_sha256), 'mc:record:ledger', ...
            'REFUSED: attempt %d of %s has no matching STARTED / POST / OUTCOME ledger.', rec.attempt, unit);
        if isequal(lg.recovered, true)
            fD = fullfile(ctx.root, 'decisions', sprintf('ADJUDICATE_%s_a%d.mat', unit, rec.attempt));
            assert(isfile(fD) && strcmp(baseline_sha256(fD), lg.recovery_decision_sha256), ...
                'mc:record:ledger', 'REFUSED: the recovered record of %s names no matching ruling.', unit);
        end
    else
        assert(rec.attempt == 0, 'mc:record:ledger', 'A Level-A record carries attempt 0.');
    end

    f = mc_record_path(ctx.root, rec.condition, rec.trial_id, rec.method);
    if ~isfolder(fileparts(f))
        mkdir(fileparts(f));
    end
    opts = struct('hook', hook);
    if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
    info = mc_atomic_write(f, struct('rec', rec), 'mat', opts);
end

% =====================================================================
function mc_record_validate(rec)
    need = {'schema', 'kind', 'binding', 'condition', 'trial_id', 'method', 'trial', ...
            'level_a', 'status', 'status_level', 'status_rule', 'status_reason', ...
            'guard', 'outputs', 'timing', 'environment', 'horizon', 'created_utc', ...
            'attempt', 'ledger', 'process', 'shard_id'};
    assert(isstruct(rec) && isscalar(rec) && all(isfield(rec, need)), 'mc:record:schema', ...
        'A record must carry every schema field.');
    assert(strcmp(rec.schema, 'task4_mc_run_record_v2'), 'mc:record:schema', ...
        'Unknown record schema ''%s''.', rec.schema);
    switch rec.kind
        case 'SCIENTIFIC',   ok = strcmp(rec.binding.mode, 'SCIENTIFIC');
        case 'VERIFICATION', ok = strcmp(rec.binding.mode, 'VERIFICATION_ONLY');
        otherwise,           ok = false;
    end
    assert(ok, 'mc:record:kind', 'Record kind and binding mode disagree.');
    assert(any(strcmp(rec.status_level, {'A', 'B'})) && isnumeric(rec.attempt) && isscalar(rec.attempt), ...
        'mc:record:schema', 'Bad status level or attempt.');
end

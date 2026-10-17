function dec = mc_operator_adjudicate_attempt(ctx, condition, trialId, method, attempt, decision, operator, reason)
% MC_OPERATOR_ADJUDICATE_ATTEMPT  A person's ruling on ONE ambiguous attempt, as its evidence permits.
%   dec = mc_operator_adjudicate_attempt(ctx, condition, trialId, method, attempt, ...
%                                        decision, operator, reason)
%   decision: 'AUTHORISE_NEW_ATTEMPT' | 'RECOVER_RECORD'
%
%   Allowed only when that attempt is the AMBIGUOUS latest attempt of the unit
%   (MC_ATTEMPT_LEDGER 'state', the strict history validator), and ONLY with a
%   ruling its DURABLE EVIDENCE permits - operator text never widens it
%   ('mc:operator:not_permitted'):
%
%     INTERRUPTED_BEFORE_POST    AUTHORISE_NEW_ATTEMPT: nothing durable shows that
%                                the controller ran to any outcome; the interrupted
%                                run, having no record, is rerun from scratch
%                                (protocol Sec. 10.4). Attempt k+1 may then start.
%     PROMOTED_FAILURE_OBSERVED  RECOVER_RECORD: the proposed method's promoted ode45
%                                failure is observed in POST; the INTEGRATOR_EXCEPTION
%                                record is written from that evidence and the
%                                controller is NEVER invoked again (Sec. 10.5: no
%                                retry of a failed run).
%     OUTCOME_DURABLE            RECOVER_RECORD: the status and outputs are durable in
%                                OUTCOME; the record is rebuilt from them, never
%                                re-executed.
%     RETURNED_UNCLASSIFIED      no ruling ('mc:operator:reviewer_required'): RETURNED
%                                is not proof of scientific success and the outcome
%                                was never made durable.
%     HARNESS_OBSERVED           no ruling ('mc:operator:reviewer_required'):
%                                HARNESS_ERROR stops the campaign; another run needs
%                                new protocol authority (Sec. 10.4).
%
%   The ruling binds the SHA-256 of the attempt's STARTED, POST and OUTCOME
%   ('' where absent), its evidence class and this campaign's binding, and is
%   written once as <root>/decisions/ADJUDICATE_<unit>_a<k>.mat. Refused for a
%   closed condition.

    gOp = mc_campaign_guard(ctx, 'operator'); %#ok<NASGU>   % live lease for the write below
    assert(any(strcmp(decision, {'AUTHORISE_NEW_ATTEMPT', 'RECOVER_RECORD'})), 'mc:operator:decision', ...
        'A ruling is AUTHORISE_NEW_ATTEMPT or RECOVER_RECORD.');
    assert(ischar(operator) && ~isempty(strtrim(operator)) && ischar(reason) ...
        && ~isempty(strtrim(reason)), 'mc:operator:decision', ...
        'A ruling needs the operator''s name and a reason.');
    assert(~isfile(fullfile(ctx.root, sprintf('%s_CLOSED.mat', condition))), ...
        'mc:operator:condition_closed', 'REFUSED: condition %s is closed; its checkpoint is final.', condition);
    st = mc_attempt_ledger('state', ctx, condition, trialId, method);
    assert(strcmp(st.status, 'AMBIGUOUS') && st.attempt == attempt, 'mc:operator:not_ambiguous', ...
        'Attempt %d of %s is not the ambiguous latest attempt (%s).', attempt, st.unit, st.status);
    if isempty(st.permitted)
        error('mc:operator:reviewer_required', ...
            ['REFUSED: attempt %d of %s has evidence %s. No operator ruling is permitted; ' ...
             'the unit stays STOPPED for the reviewer.'], attempt, st.unit, st.evidence);
    end
    assert(any(strcmp(decision, st.permitted)), 'mc:operator:not_permitted', ...
        'REFUSED: %s is not permitted for evidence %s of %s attempt %d (permitted: %s).', ...
        decision, st.evidence, st.unit, attempt, strjoin(st.permitted, ', '));
    dec = struct('schema', 'task4_mc_adjudication_v2', 'decision', decision, ...
        'condition', condition, 'trial_id', trialId, 'method', method, 'attempt', attempt, ...
        'evidence_class', st.evidence, 'started_sha256', st.started, 'post_sha256', st.post, ...
        'outcome_sha256', st.outcome, 'binding', ctx.binding, 'operator', operator, ...
        'reason', reason, 'utc', mc_utc_now(), 'process', mc_process_identity());
    out = fullfile(ctx.root, 'decisions');
    if ~isfolder(out), mkdir(out); end
    opts = struct();
    if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
    mc_atomic_write(fullfile(out, sprintf('ADJUDICATE_%s_a%d.mat', st.unit, attempt)), ...
        struct('decision', dec), 'mat', opts);
end

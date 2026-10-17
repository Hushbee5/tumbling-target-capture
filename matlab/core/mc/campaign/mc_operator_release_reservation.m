function dec = mc_operator_release_reservation(ctx, condition, trialId, operator, reason)
% MC_OPERATOR_RELEASE_RESERVATION  A person releases a stale pair reservation.
%   dec = mc_operator_release_reservation(ctx, condition, trialId, operator, reason)
%
%   Refused while ANY method of the pair has an AMBIGUOUS attempt
%   ('mc:operator:ambiguous_attempt'): an attempt that may have executed must be
%   adjudicated first, so a release can never enable a rerun of a method whose
%   completion state is unknown. Refused for a COMPLETE pair
%   ('mc:operator:pair_complete': its reservation is part of its closure proof)
%   and for a closed condition. Otherwise the decision - bound to the SHA-256
%   of the reservation's owner.mat (or recording that it was missing) and to
%   this campaign's binding - is written once to <root>/decisions, and the
%   reservation directory is moved, by one rename, to
%   <root>/reservations/released/. Nothing is deleted.

    gOp = mc_campaign_guard(ctx, 'operator'); %#ok<NASGU>   % live lease for the writes below
    c = mc_constants();
    assert(ischar(operator) && ~isempty(strtrim(operator)) && ischar(reason) ...
        && ~isempty(strtrim(reason)), 'mc:operator:decision', ...
        'A release needs the operator''s name and a reason.');
    assert(~isfile(fullfile(ctx.root, sprintf('%s_CLOSED.mat', condition))), ...
        'mc:operator:condition_closed', 'REFUSED: condition %s is closed; its checkpoint is final.', condition);
    r = mc_reservation('owner', ctx, condition, trialId);
    assert(r.exists, 'mc:operator:no_reservation', 'Pair %s t%03d is not reserved.', condition, trialId);
    nTerminal = 0;
    for mi = 1:numel(c.design.methods)
        st = mc_attempt_ledger('state', ctx, condition, trialId, c.design.methods{mi});
        assert(~strcmp(st.status, 'AMBIGUOUS'), 'mc:operator:ambiguous_attempt', ...
            'REFUSED: %s has an ambiguous attempt; adjudicate it before any release.', st.unit);
        nTerminal = nTerminal + strcmp(st.status, 'TERMINAL');
    end
    assert(nTerminal < numel(c.design.methods), 'mc:operator:pair_complete', ...
        'REFUSED: pair %s t%03d is complete; its reservation is final.', condition, trialId);
    ownerf = fullfile(r.dir, 'owner.mat');
    ownerSha = '';
    if isfile(ownerf), ownerSha = baseline_sha256(ownerf); end
    stamp = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyyMMdd''T''HHmmssSSS'));
    dec = struct('schema', 'task4_mc_reservation_release_v1', 'condition', condition, ...
        'trial_id', trialId, 'owner_sha256', ownerSha, 'owner', r.owner, 'binding', ctx.binding, ...
        'operator', operator, 'reason', reason, 'utc', mc_utc_now(), 'process', mc_process_identity());
    out = fullfile(ctx.root, 'decisions');
    if ~isfolder(out), mkdir(out); end
    opts = struct();
    if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
    mc_atomic_write(fullfile(out, sprintf('RELEASE_%s_t%03d_%s.mat', condition, trialId, stamp)), ...
        struct('decision', dec), 'mat', opts);
    rel = fullfile(ctx.root, 'reservations', 'released');
    if ~isfolder(rel), mkdir(rel); end
    target = fullfile(rel, sprintf('%s_t%03d__%s', condition, trialId, stamp));
    ok = java.io.File(r.dir).renameTo(java.io.File(target));
    assert(logical(ok) && ~isfolder(r.dir), 'mc:operator:release_rename', ...
        'The reservation directory could not be moved to %s.', target);
end

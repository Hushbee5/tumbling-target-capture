function dec = mc_operator_release_shard(ctx, condition, shardId, operator, reason)
% MC_OPERATOR_RELEASE_SHARD  A person releases the stale lock of a shard.
%   dec = mc_operator_release_shard(ctx, condition, shardId, operator, reason)
%
%   For a shard lock (MC_SHARD_LOCK) whose owner process is known to have ended,
%   e.g. after a crash. Refused for a closed condition. The decision - bound to
%   the SHA-256 of the lock's owner.mat (or recording that it was missing) and
%   to this campaign's binding - is written once as
%   <root>/decisions/RELEASE_SHARD_<cond>_<shard>_<stamp>.mat, and the lock
%   directory is moved, by one rename, to <root>/shard_locks/released/
%   <cond>_<shard>__<stamp>. Nothing is deleted. Releasing a lock authorises no
%   rerun: every pair keeps its own reservation, attempt ledger and records,
%   and the next owner resumes the shard in order from its first pending pair.

    gOp = mc_campaign_guard(ctx, 'operator'); %#ok<NASGU>   % live lease for the writes below
    assert(ischar(operator) && ~isempty(strtrim(operator)) && ischar(reason) ...
        && ~isempty(strtrim(reason)), 'mc:operator:decision', ...
        'A release needs the operator''s name and a reason.');
    assert(~isfile(fullfile(ctx.root, sprintf('%s_CLOSED.mat', condition))), ...
        'mc:operator:condition_closed', 'REFUSED: condition %s is closed; its checkpoint is final.', condition);
    r = mc_shard_lock('owner', ctx, condition, shardId);
    assert(r.exists, 'mc:operator:no_shard_lock', 'Shard %s of %s is not locked.', shardId, condition);
    ownerf = fullfile(r.dir, 'owner.mat');
    ownerSha = '';
    if isfile(ownerf), ownerSha = baseline_sha256(ownerf); end
    stamp = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyyMMdd''T''HHmmssSSS'));
    dec = struct('schema', 'task4_mc_shard_release_v1', 'condition', condition, ...
        'shard_id', shardId, 'owner_sha256', ownerSha, 'owner', r.owner, 'binding', ctx.binding, ...
        'operator', operator, 'reason', reason, 'utc', mc_utc_now(), 'process', mc_process_identity());
    out = fullfile(ctx.root, 'decisions');
    if ~isfolder(out), mkdir(out); end
    opts = struct();
    if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
    mc_atomic_write(fullfile(out, sprintf('RELEASE_SHARD_%s_%s_%s.mat', condition, shardId, stamp)), ...
        struct('decision', dec), 'mat', opts);
    rel = fullfile(ctx.root, 'shard_locks', 'released');
    if ~isfolder(rel), mkdir(rel); end
    target = fullfile(rel, sprintf('%s_%s__%s', condition, shardId, stamp));
    ok = java.io.File(r.dir).renameTo(java.io.File(target));
    assert(logical(ok) && ~isfolder(r.dir), 'mc:operator:release_rename', ...
        'The shard lock directory could not be moved to %s.', target);
end

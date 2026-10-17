function r = mc_shard_lock(action, ctx, condition, shardId)
% MC_SHARD_LOCK  Durable, exclusive ownership of one shard by ONE MATLAB process.
%   r = mc_shard_lock('acquire', ctx, condition, shardId)
%   r = mc_shard_lock('owner',   ctx, condition, shardId)
%   mc_shard_lock('assert_owned', ctx, condition, shardId)
%
%   Protocol Sec. 10.4: execution may use 1 to 3 DISJOINT MATLAB processes. The
%   plan (MC_SHARD_PLAN) makes the shards disjoint; this lock makes each shard
%   the work of exactly one process. THE LOCK IS THE DIRECTORY
%   <root>/shard_locks/<cond>_<shard>, created with java.io.File.mkdir, which
%   succeeds for exactly ONE caller - also across processes - and fails if the
%   directory exists; the creation IS the test. The winner then writes
%   owner.mat (binding, condition, shard, its trial ids from the plan, process
%   identity, UTC) atomically. Locks are durable: the campaign never deletes
%   one.
%
%   'acquire' (a write: MC_CAMPAIGN_GUARD 'write', inside a live boundary)
%   returns r.state = 'ACQUIRED' (created now) or 'OWNED' (this process created
%   it earlier). A lock of another process - or one whose owner.mat is missing
%   - is REFUSED ('mc:campaign:shard_owned_elsewhere'): the shard STOPS before
%   any pair work. Nothing is taken over automatically; a person may release
%   a stale lock of a process known to have ended (MC_OPERATOR_RELEASE_SHARD).
%   'assert_owned' refuses ('mc:campaign:shard_not_owned') unless this process
%   holds the lock; every pair and every pair reservation requires it.

    folder = fullfile(ctx.root, 'shard_locks');
    dirp   = fullfile(folder, sprintf('%s_%s', condition, shardId));
    ownerf = fullfile(dirp, 'owner.mat');
    me = mc_process_identity();
    switch action
        case 'acquire'
            mc_campaign_guard(ctx, 'write');
            plan = mc_shard_plan_read(ctx, condition);
            k = find(strcmp(plan.shard_ids, shardId), 1);
            assert(~isempty(k), 'mc:plan:unknown_shard', ...
                'REFUSED: shard %s is not in the %s plan.', shardId, condition);
            if ~isfolder(folder), mkdir(folder); end
            created = logical(java.io.File(dirp).mkdir());
            if created
                owner = struct('schema', 'task4_mc_shard_lock_v1', 'binding', ctx.binding, ...
                    'condition', condition, 'shard_id', shardId, 'trial_ids', plan.shards{k}, ...
                    'process', me, 'created_utc', mc_utc_now());
                mc_atomic_write(ownerf, struct('owner', owner), 'mat', struct('ctx', ctx));
                r = struct('state', 'ACQUIRED', 'owner', owner, 'dir', dirp);
                return
            end
            o = read_owner(ownerf);
            assert(mine(o, ctx, condition, shardId, me), 'mc:campaign:shard_owned_elsewhere', ...
                ['STOP: shard %s of %s is owned by another process or its owner is unknown ' ...
                 '(%s). Nothing is taken over automatically; an operator may release a stale ' ...
                 'lock (MC_OPERATOR_RELEASE_SHARD).'], shardId, condition, describe(o));
            r = struct('state', 'OWNED', 'owner', o, 'dir', dirp);
        case 'owner'
            r = struct('exists', isfolder(dirp), 'owner', read_owner(ownerf), 'dir', dirp);
        case 'assert_owned'
            o = read_owner(ownerf);
            assert(mine(o, ctx, condition, shardId, me), 'mc:campaign:shard_not_owned', ...
                'REFUSED: this process does not own shard %s of %s (%s).', shardId, condition, describe(o));
            r = struct('state', 'OWNED', 'owner', o, 'dir', dirp);
        otherwise
            error('mc:shard_lock:action', 'Unknown shard-lock action ''%s''.', action);
    end
end

% =====================================================================
function tf = mine(o, ctx, condition, shardId, me)
    tf = ~isempty(o) && isfield(o, 'binding') && isequal(o.binding, ctx.binding) ...
        && strcmp(o.condition, condition) && strcmp(o.shard_id, shardId) ...
        && strcmp(o.process.nonce, me.nonce);
end

% =====================================================================
function o = read_owner(f)
    o = [];
    if isfile(f)
        S = load(f, 'owner');
        if isfield(S, 'owner') && isstruct(S.owner) && isfield(S.owner, 'process')
            o = S.owner;
        end
    end
end

% =====================================================================
function s = describe(o)
    if isempty(o)
        s = 'owner.mat missing';
    else
        s = sprintf('owner process %s since %s', o.process.nonce, o.created_utc);
    end
end

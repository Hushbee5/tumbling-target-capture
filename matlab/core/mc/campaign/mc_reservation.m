function r = mc_reservation(action, ctx, condition, trialId, shardId)
% MC_RESERVATION  Atomic, durable reservation of one (condition, trial) pair.
%   r = mc_reservation('acquire', ctx, condition, trialId, shardId)
%   r = mc_reservation('owner',   ctx, condition, trialId)
%   mc_reservation('assert_owned', ctx, condition, trialId)
%
%   THE LOCK IS THE DIRECTORY <root>/reservations/<cond>_t<NNN>, created with
%   java.io.File.mkdir, which succeeds for exactly ONE caller - also across
%   processes - and fails if the directory already exists. There is no
%   check-then-write window: the creation IS the test. The winner then writes
%   owner.mat (binding, condition, trial, shard from the predeclared plan,
%   process identity, UTC) atomically. Reservations are durable: they are never
%   deleted by the campaign.
%
%   'acquire' returns r.state = 'ACQUIRED' (created now) or 'OWNED' (this
%   process created it earlier). A reservation of another process - or one
%   whose owner.mat is missing, e.g. after a crash between the two steps - is
%   REFUSED ('mc:campaign:reserved_elsewhere'): the pair STOPS for operator
%   adjudication (MC_OPERATOR_RELEASE_RESERVATION). Nothing is taken over
%   automatically, so a live owner can never be raced. 'acquire' is a write
%   (MC_CAMPAIGN_GUARD 'write': inside a live boundary) and requires that THIS
%   process owns the shard of the pair (MC_SHARD_LOCK 'assert_owned').

    folder = fullfile(ctx.root, 'reservations');
    dirp   = fullfile(folder, sprintf('%s_t%03d', condition, trialId));
    ownerf = fullfile(dirp, 'owner.mat');
    me = mc_process_identity();
    switch action
        case 'acquire'
            mc_campaign_guard(ctx, 'write');
            mc_shard_lock('assert_owned', ctx, condition, shardId);
            if ~isfolder(folder), mkdir(folder); end
            created = logical(java.io.File(dirp).mkdir());
            if created
                owner = struct('schema', 'task4_mc_reservation_v1', 'binding', ctx.binding, ...
                    'condition', condition, 'trial_id', trialId, 'shard_id', shardId, ...
                    'process', me, 'created_utc', mc_utc_now());
                mc_atomic_write(ownerf, struct('owner', owner), 'mat', struct('ctx', ctx));
                r = struct('state', 'ACQUIRED', 'owner', owner, 'dir', dirp);
                return
            end
            o = read_owner(ownerf);
            assert(~isempty(o) && isequal(o.binding, ctx.binding) ...
                && strcmp(o.process.nonce, me.nonce), 'mc:campaign:reserved_elsewhere', ...
                ['STOP: pair %s t%03d is reserved by another process or its owner is ' ...
                 'unknown (%s). Nothing is taken over automatically; an operator must ' ...
                 'adjudicate (MC_OPERATOR_RELEASE_RESERVATION).'], condition, trialId, describe(o));
            r = struct('state', 'OWNED', 'owner', o, 'dir', dirp);
        case 'owner'
            r = struct('exists', isfolder(dirp), 'owner', read_owner(ownerf), 'dir', dirp);
        case 'assert_owned'
            o = read_owner(ownerf);
            assert(~isempty(o) && strcmp(o.process.nonce, me.nonce) && isequal(o.binding, ctx.binding) ...
                && strcmp(o.condition, condition) && o.trial_id == trialId, ...
                'mc:campaign:not_reserved', ...
                'REFUSED: this process does not hold the reservation of %s t%03d.', condition, trialId);
            r = struct('state', 'OWNED', 'owner', o, 'dir', dirp);
        otherwise
            error('mc:reservation:action', 'Unknown reservation action ''%s''.', action);
    end
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
        s = sprintf('owner process %s, shard %s, since %s', o.process.nonce, o.shard_id, o.created_utc);
    end
end

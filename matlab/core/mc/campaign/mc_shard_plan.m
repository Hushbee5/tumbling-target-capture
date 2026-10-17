function plan = mc_shard_plan(ctx, condition, shards, operator)
% MC_SHARD_PLAN  Predeclare the DISJOINT shard plan of one condition, once.
%   plan = mc_shard_plan(ctx, condition, shards, operator)
%
%   shards: cell array of 1 to 3 trial-id vectors that PARTITION ctx.trial_ids
%   exactly (every intended trial in exactly one shard; protocol Sec. 10.4).
%   Shard ids are 'S1'..'Sn' in the order given. The plan is written ONCE,
%   atomically, as <root>/plan/<cond>_PLAN.mat and is never overwritten; every
%   shard and every pair reads it back through MC_SHARD_PLAN_READ, so no process
%   can choose its own trial list. This is an operator action and is recorded
%   with the operator's name.

    gOp = mc_campaign_guard(ctx, 'operator'); %#ok<NASGU>   % live lease for the write below
    c = mc_constants();
    assert(any(strcmp(condition, c.design.conditions)), 'mc:plan:condition', ...
        'Unknown condition ''%s''.', condition);
    assert(ischar(operator) && ~isempty(strtrim(operator)), 'mc:plan:operator', ...
        'The plan must name the operator who declares it.');
    assert(iscell(shards) && any(numel(shards) == 1:3), 'mc:plan:shards', ...
        'A plan has 1 to 3 shards (protocol Sec. 10.4).');
    shards = cellfun(@(s) double(s(:).'), shards, 'UniformOutput', false);
    plan = struct('schema', 'task4_mc_shard_plan_v1', 'condition', condition, ...
        'binding', ctx.binding, 'trial_ids', ctx.trial_ids, ...
        'shard_ids', {arrayfun(@(k) sprintf('S%d', k), 1:numel(shards), 'UniformOutput', false)}, ...
        'shards', {shards}, 'operator', operator, 'created_utc', mc_utc_now(), ...
        'process', mc_process_identity());
    mc_shard_plan_check(plan, ctx, condition);

    folder = fullfile(ctx.root, 'plan');
    if ~isfolder(folder), mkdir(folder); end
    mc_atomic_write(fullfile(folder, sprintf('%s_PLAN.mat', condition)), struct('plan', plan), ...
        'mat', struct('ctx', ctx));
end

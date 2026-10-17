function [plan, shardOf] = mc_shard_plan_read(ctx, condition)
% MC_SHARD_PLAN_READ  Read and re-verify the predeclared shard plan of a condition.
%   [plan, shardOf] = mc_shard_plan_read(ctx, condition) refuses
%   ('mc:plan:missing') if no plan was declared, and otherwise re-checks it
%   with MC_SHARD_PLAN_CHECK. shardOf(trialId) returns the id of the ONE shard
%   that owns that trial.

    f = fullfile(ctx.root, 'plan', sprintf('%s_PLAN.mat', condition));
    assert(isfile(f), 'mc:plan:missing', ...
        'REFUSED: no shard plan has been declared for condition %s.', condition);
    S = load(f, 'plan');
    assert(isfield(S, 'plan'), 'mc:plan:schema', 'File %s holds no plan.', f);
    plan = S.plan;
    mc_shard_plan_check(plan, ctx, condition);
    shardOf = @(tid) owner(plan, tid);
end

% =====================================================================
function id = owner(plan, tid)
    for k = 1:numel(plan.shards)
        if any(plan.shards{k} == tid)
            id = plan.shard_ids{k};
            return
        end
    end
    error('mc:plan:unassigned', 'Trial %d is assigned to no shard.', tid);
end

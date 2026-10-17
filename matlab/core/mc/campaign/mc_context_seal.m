function d = mc_context_seal(ctx)
% MC_CONTEXT_SEAL  Digest of every field of a campaign context that must not change.
%   d = mc_context_seal(ctx) is MC_VALUE_SHA256 of the SEALED fields:
%     kind, root, Tsim, K_expected, trial_ids, trials, binding, record_kind,
%     pBL, apf (theta and gains), runner_override, inputs
%   The runtime fields env (threads, process, shard) and seal itself are not
%   sealed; they describe the process, not the experiment.

    f = {'kind', 'root', 'Tsim', 'K_expected', 'trial_ids', 'trials', 'binding', ...
         'record_kind', 'pBL', 'apf', 'runner_override', 'inputs'};
    assert(isstruct(ctx) && isscalar(ctx) && all(isfield(ctx, f)), 'mc:campaign:ctx_shape', ...
        'Not a campaign context: a sealed field is missing.');
    s = struct();
    for k = 1:numel(f)
        s.(f{k}) = ctx.(f{k});
    end
    d = mc_value_sha256(s);
end

function f = mc_record_path(root, condition, trialId, method)
% MC_RECORD_PATH  The unique file of one (condition, trial, method) record.
%   f = mc_record_path(root, condition, trialId, method) returns
%       <root>/<condition>/<condition>_t<NNN>_<method>.mat
%   One record per (trial, condition, method); the name alone identifies it,
%   and MC_RECORD_READ checks that the content agrees with the name.

    c = mc_constants();
    assert(any(strcmp(condition, c.design.conditions)), 'mc:record:condition', ...
        'Unknown condition ''%s''.', condition);
    assert(any(strcmp(method, c.design.methods)), 'mc:record:method', ...
        'Unknown method ''%s''.', method);
    assert(isscalar(trialId) && trialId == round(trialId) && trialId >= 1 && trialId <= 999, ...
        'mc:record:trial', 'trial_id must be an integer in [1, 999].');
    f = fullfile(root, condition, sprintf('%s_t%03d_%s.mat', condition, trialId, method));
end

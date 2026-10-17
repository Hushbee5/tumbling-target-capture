function row = mc_trial_row(T, trialId)
% MC_TRIAL_ROW  The physical execution inputs of one trial, from a stored table.
%   row = mc_trial_row(T, trialId) returns the DERIVED fields of the stored
%   row (Sec. 10.1: execution loads the derived inputs; it never regenerates a
%   trial from RNG and never recomputes the mapping):
%       trial_id, x0 (6x1), q0 (4x1), w0 (3x1), Idiag (3x1), I_true (3x3)

    assert(isscalar(trialId) && trialId == round(trialId) && trialId >= 1 ...
        && trialId <= T.n && T.trial_id(trialId) == trialId, 'mc:trials:row', ...
        'trial_id %g is not a row of this table.', trialId);
    row.trial_id = trialId;
    row.x0     = [T.r0(:, trialId); T.v0(:, trialId)];
    row.q0     = T.q0(:, trialId);
    row.w0     = T.w0(:, trialId);
    row.Idiag  = T.Idiag(:, trialId);
    row.I_true = diag(row.Idiag);
end

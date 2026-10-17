function status = mc_condition_gate(condition, guardStatus, v2c)
% MC_CONDITION_GATE  The Level-A status of one (trial, condition) (Sec. 7.2).
%   status = mc_condition_gate(condition, guardStatus, v2c)
%
%   guardStatus is the R18-guard status of the shared table build:
%     'OTHER_EXCEPTION'         -> 'HARNESS_ERROR'                     (A0)
%     'PROMOTED_ODE45_FAILURE'  -> 'TARGET_MODEL_INTEGRATION_FAILURE'  (A1)
%     'RETURNED'                -> the V2c decision below
%   After a returned build (v2c = the unmodified frozen
%   baseline_preview_truth_audit(tabs, 1e-6, 1e-6)):
%     Condition M and ~v2c.pass -> 'M_CONSISTENCY_FAILURE'             (A2)
%     otherwise                 -> 'TABLES_OK'
%   Condition U NEVER gates on V2c: its preview inertia intentionally differs
%   from the truth, and its V2c values are descriptive only (Sec. 4.1, 6.2).

    assert(any(strcmp(condition, {'U', 'M'})), 'mc:gate:condition', ...
        'Unknown condition ''%s''.', condition);
    switch guardStatus
        case 'OTHER_EXCEPTION'
            status = 'HARNESS_ERROR';
            return
        case 'PROMOTED_ODE45_FAILURE'
            status = 'TARGET_MODEL_INTEGRATION_FAILURE';
            return
        case 'RETURNED'
        otherwise
            error('mc:gate:guard', 'Unknown guard status ''%s''.', guardStatus);
    end
    assert(isstruct(v2c) && isfield(v2c, 'pass') && islogical(v2c.pass) ...
        && isscalar(v2c.pass), 'mc:gate:v2c', 'v2c must be a frozen V2c result.');
    if strcmp(condition, 'M') && ~v2c.pass
        status = 'M_CONSISTENCY_FAILURE';
    else
        status = 'TABLES_OK';
    end
end

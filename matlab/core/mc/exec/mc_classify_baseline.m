function [status, info] = mc_classify_baseline(guardStatus, run, method, K_expected)
% MC_CLASSIFY_BASELINE  Level-B execution status of one baseline run (Sec. 7.2).
%   [status, info] = mc_classify_baseline(guardStatus, run, method, K_expected)
%
%     B1  HARNESS_ERROR      any thrown error escaping simulate_baseline
%                            (including, by construction, a promoted ode45
%                            exception, which the frozen internal guard would
%                            normally have caught)
%     B2  NUMERICAL_FAILURE  ~run.numerically_eligible; this INCLUDES an ode45
%                            failure, promoted or not, caught by the frozen
%                            internal guard (simulate_baseline.m:236-246)
%     B3  COMPLETE           run.completed && run.numerically_eligible
%         none of the above -> HARNESS_ERROR (unexpected state)

    info = struct('rule', '', 'reason', '');
    switch guardStatus
        case {'OTHER_EXCEPTION', 'PROMOTED_ODE45_FAILURE'}
            status = 'HARNESS_ERROR';  info.rule = 'B1';
            info.reason = sprintf('exception escaped simulate_baseline (%s)', guardStatus);
            return
        case 'RETURNED'
        otherwise
            error('mc:classify:guard', 'Unknown guard status ''%s''.', guardStatus);
    end
    if ~(isstruct(run) && isscalar(run) && all(isfield(run, ...
            {'numerically_eligible', 'completed', 'method', 'K_expected'})) ...
            && strcmp(run.method, method) && isequal(run.K_expected, K_expected))
        status = 'HARNESS_ERROR';  info.rule = 'UNEXPECTED';
        info.reason = 'the returned run does not describe the requested method or horizon';
        return
    end
    if ~run.numerically_eligible
        status = 'NUMERICAL_FAILURE';  info.rule = 'B2';
        info.reason = run.failure_reason;
        return
    end
    if run.completed && run.numerically_eligible
        status = 'COMPLETE';  info.rule = 'B3';
        info.reason = 'full horizon';
        return
    end
    status = 'HARNESS_ERROR';  info.rule = 'UNEXPECTED';
    info.reason = 'no rule holds';
end

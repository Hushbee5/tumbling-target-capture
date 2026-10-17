function [status, info] = mc_classify_proposed(guardStatus, out, K_expected)
% MC_CLASSIFY_PROPOSED  Level-B execution status of one proposed run (Sec. 7.2).
%   [status, info] = mc_classify_proposed(guardStatus, out, K_expected)
%
%   guardStatus is MC_R18_INVOKE's status; out is the returned output ([] if
%   none); K_expected is the full-horizon step count (8000 in the MC).
%   Rules are evaluated top to bottom; the first that holds assigns the
%   status (protocol Sec. 7.2, exactly):
%
%     B1  HARNESS_ERROR        any thrown error OTHER than the promoted ode45
%                              exception -> the campaign STOPS
%     B2  INTEGRATOR_EXCEPTION the promoted ode45 exception escaped
%                              simulate_task4; NO out was returned
%     B3  IC_REFUSED           strcmp(out.eligibility, 'INELIGIBLE_IC'),
%                              assigned IMMEDIATELY, before any finiteness
%                              classification
%     B4  NUMERICAL_FAILURE    ONLY for an ELIGIBLE returned out: a violation of
%                              the finite-required field / mask contract
%                              (MC_MASK_CONTRACT, MC_MASK_CHECK)
%     B5  QP_INFEASIBLE_ABORT  out.qp_failure.occurred
%     B6  GUARD_BREACH_ABORT   out.aborted && strcmp(out.event, 'GUARD_BREACH')
%     B7  COMPLETE             ~out.aborted && out.K_applied == K_expected
%         none of the above -> HARNESS_ERROR (unexpected state)
%
%   A contract STRUCTURE violation (missing / extra / mis-sized field) is an
%   unexpected state of the frozen output, not a numerical failure, and is
%   returned as HARNESS_ERROR with info.reason = 'CONTRACT_STRUCTURE'.
%
%   info fields: rule (B1..B7 or 'UNEXPECTED'), reason, mask (MC_MASK_CHECK
%   result, when evaluated).

    info = struct('rule', '', 'reason', '', 'mask', []);

    switch guardStatus
        case 'OTHER_EXCEPTION'
            status = 'HARNESS_ERROR';  info.rule = 'B1';
            info.reason = 'an exception other than the promoted ode45 exception';
            return
        case 'PROMOTED_ODE45_FAILURE'
            status = 'INTEGRATOR_EXCEPTION';  info.rule = 'B2';
            info.reason = 'the promoted ode45 exception escaped simulate_task4; no out';
            return
        case 'RETURNED'
            % continue below
        otherwise
            error('mc:classify:guard', 'Unknown guard status ''%s''.', guardStatus);
    end

    if ~(isstruct(out) && isscalar(out) && isfield(out, 'eligibility') && ischar(out.eligibility))
        status = 'HARNESS_ERROR';  info.rule = 'UNEXPECTED';
        info.reason = 'the returned output carries no eligibility field';
        return
    end

    if strcmp(out.eligibility, 'INELIGIBLE_IC')                        % B3
        status = 'IC_REFUSED';  info.rule = 'B3';
        info.reason = 'refused at the frozen initial-admissibility gate';
        return
    end
    if ~strcmp(out.eligibility, 'ELIGIBLE')
        status = 'HARNESS_ERROR';  info.rule = 'UNEXPECTED';
        info.reason = sprintf('unknown eligibility ''%s''', out.eligibility);
        return
    end

    mask = mc_mask_check(out);                                         % B4
    info.mask = mask;
    if ~isempty(mask.structure)
        status = 'HARNESS_ERROR';  info.rule = 'UNEXPECTED';
        info.reason = ['CONTRACT_STRUCTURE: ' strjoin(mask.structure, '; ')];
        return
    end
    if ~isempty(mask.nonfinite)
        status = 'NUMERICAL_FAILURE';  info.rule = 'B4';
        info.reason = strjoin(mask.nonfinite, '; ');
        return
    end

    if out.qp_failure.occurred                                         % B5
        status = 'QP_INFEASIBLE_ABORT';  info.rule = 'B5';
        info.reason = 'two-row HOCBF-QP infeasible';
        return
    end
    if out.aborted && strcmp(out.event, 'GUARD_BREACH')                % B6
        status = 'GUARD_BREACH_ABORT';  info.rule = 'B6';
        info.reason = 'in-loop D9 GUARD_BREACH';
        return
    end
    if ~out.aborted && out.K_applied == K_expected                     % B7
        status = 'COMPLETE';  info.rule = 'B7';
        info.reason = 'full horizon';
        return
    end

    status = 'HARNESS_ERROR';  info.rule = 'UNEXPECTED';
    info.reason = sprintf('no rule holds (aborted = %d, K_applied = %g, K_expected = %g)', ...
        out.aborted, out.K_applied, K_expected);
end

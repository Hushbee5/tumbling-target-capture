function r = mc_r18_invoke(op)
% MC_R18_INVOKE  The additive MC execution guard (protocol Sec. 10.5, R18).
%   r = mc_r18_invoke(op) invokes the zero-argument function handle op EXACTLY
%   ONCE under the frozen guard
%
%       old_state = warning;                                   % complete state
%       restore   = onCleanup(@() warning(old_state));         % UNCONDITIONAL
%       warning('error', 'MATLAB:ode45:IntegrationTolNotMet');  % ONLY this id
%       result    = <exactly one frozen invocation>;
%
%   Rules implemented literally:
%     - ONLY MATLAB:ode45:IntegrationTolNotMet is promoted; every other warning
%       keeps its prior state and is neither promoted nor suppressed;
%     - the complete prior warning state is restored on EVERY exit, normal or
%       exceptional (onCleanup);
%     - no retry, no tolerance change, no continuation: op is called once and
%       whatever it does is reported.
%
%   r.status
%     'RETURNED'                op returned; r.value holds its output
%     'PROMOTED_ODE45_FAILURE'  the promoted identifier escaped op
%     'OTHER_EXCEPTION'         any other exception escaped op; the callers map
%                               it to HARNESS_ERROR, which stops the campaign
%   r.exception       the MException, or [] (kept in memory only)
%   r.exception_info  MC_EXCEPTION_SUMMARY of it (safe to save)
%   r.n_invocations   always 1

    assert(isa(op, 'function_handle') && nargin(op) == 0, 'mc:r18:op', ...
        'op must be a zero-argument function handle.');

    r = struct('status', '', 'value', [], 'exception', [], ...
               'exception_info', mc_exception_summary([]), 'n_invocations', 0);

    old_state = warning;
    restore   = onCleanup(@() warning(old_state));
    warning('error', 'MATLAB:ode45:IntegrationTolNotMet');

    r.n_invocations = 1;
    try
        r.value  = op();
        r.status = 'RETURNED';
    catch ME
        r.exception      = ME;
        r.exception_info = mc_exception_summary(ME);
        if strcmp(ME.identifier, 'MATLAB:ode45:IntegrationTolNotMet')
            r.status = 'PROMOTED_ODE45_FAILURE';
        else
            r.status = 'OTHER_EXCEPTION';
        end
    end
    clear restore                  % restore now, before returning
end

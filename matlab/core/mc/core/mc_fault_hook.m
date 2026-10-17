function out = mc_fault_hook(action, point)
% MC_FAULT_HOOK  Fault-injection points for the NON-SCIENTIFIC verification suite.
%   mc_fault_hook('arm', point)   arm a named point; ONLY inside a session in
%                                 which the verification suite has started
%                                 (MC_RNG_SENTINEL 'in_verification')
%   mc_fault_hook('hit', point)   no-op unless that point is armed; then the
%                                 point is disarmed and 'mc:fault:injected' thrown
%   tf = mc_fault_hook('armed')   true while any point is armed
%   mc_fault_hook('disarm')       disarm every point
%
%   The scientific campaign guard refuses to run while any point is armed, and
%   no point can be armed outside the verification suite, so these calls are
%   inert in every scientific process.

    persistent armed
    mlock;
    if isempty(armed), armed = {}; end
    out = false;
    switch action
        case 'arm'
            assert(mc_rng_sentinel('in_verification'), 'mc:fault:not_verification', ...
                'Fault injection is available only inside the verification suite.');
            armed{end+1} = point;
        case 'hit'
            k = find(strcmp(armed, point), 1);
            if ~isempty(k)
                armed(k) = [];
                error('mc:fault:injected', 'Injected verification fault at ''%s''.', point);
            end
        case 'armed'
            out = ~isempty(armed);
        case 'disarm'
            armed = {};
        otherwise
            error('mc:fault:action', 'Unknown fault-hook action ''%s''.', action);
    end
end

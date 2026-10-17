function state = mc_rng_sentinel(action)
% MC_RNG_SENTINEL  Session-lifetime firewall around the SCIENTIFIC random stream.
%   mc_rng_sentinel('mark')                  called by MC_SCIENTIFIC_TRIAL_TABLE on
%                                            the line immediately BEFORE it constructs
%                                            RandStream('mt19937ar','Seed',116075)
%   reached = mc_rng_sentinel('query')       true iff that line was ever reached in
%                                            this MATLAB session
%   mc_rng_sentinel('enter_verification')    called by MC_VERIFY before any fixture
%   inVer = mc_rng_sentinel('in_verification')  true iff the verification suite has
%                                            run (or is running) in this session
%
%   A session in which the verification suite has run can NEVER generate the
%   scientific trial table or start a scientific campaign: MC_SCIENTIFIC_TRIAL_TABLE
%   and MC_CONTEXT('scientific') refuse first thing when 'in_verification' is
%   true, whatever the repository state. There is deliberately NO reset action,
%   and the function locks itself in memory (MLOCK) so that CLEAR cannot erase
%   either record; only a new MATLAB process starts clean.

    persistent reached inVer
    mlock;
    if isempty(reached), reached = false; end
    if isempty(inVer),   inVer   = false; end
    switch action
        case 'mark'
            reached = true;
            state = reached;
        case 'query'
            state = reached;
        case 'enter_verification'
            inVer = true;
            state = inVer;
        case 'in_verification'
            state = inVer;
        otherwise
            error('mc:rng:sentinel_action', 'Unknown action ''%s''.', action);
    end
end

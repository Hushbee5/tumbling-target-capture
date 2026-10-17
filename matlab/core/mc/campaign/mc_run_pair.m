function mc_run_pair(varargin) %#ok<INUSD>
% MC_RUN_PAIR  REMOVED as a public entry point. A pair is never executed directly.
%   Every call is refused ('mc:campaign:no_direct_pair'). The pair executor is
%   a LOCAL function of MC_RUN_CONDITION, reachable only from its shard loop:
%   after the shard lock is held by this process, in the plan's increasing
%   trial order, stopping at the first pair that cannot complete. This file
%   only keeps the old public name answering with a refusal.

    error('mc:campaign:no_direct_pair', ...
        ['REFUSED: pairs are executed only through MC_RUN_CONDITION (shard ownership, ' ...
         'plan order).']);
end

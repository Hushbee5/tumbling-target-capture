function mc_context_registry(varargin) %#ok<INUSD>
% MC_CONTEXT_REGISTRY  REMOVED. There is no public context registry.
%   Every call is refused ('mc:registry:removed'). The seal digests of issued
%   contexts are held by a registry LOCAL to MC_CONTEXT, which only a
%   successful issuance can extend; MC_CAMPAIGN_GUARD queries it through
%   MC_CONTEXT('is_issued', digest). This file only keeps the old public name
%   answering with a refusal instead of silently accepting a registration.

    error('mc:registry:removed', ...
        ['REFUSED: the public context registry was removed. Contexts are issued ' ...
         'and registered only by MC_CONTEXT.']);
end

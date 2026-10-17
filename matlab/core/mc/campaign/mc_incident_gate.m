function mc_incident_gate(ctx)
% MC_INCIDENT_GATE  A HARNESS_ERROR stops the campaign until a person decides.
%   mc_incident_gate(ctx) refuses ('mc:campaign:unacknowledged_incident') while
%   ANY file in <root>/incidents lacks a valid acknowledgement. An
%   acknowledgement is the immutable file
%       <root>/acknowledgements/ACK_<SHA-256 of the incident's raw bytes>.mat
%   written by MC_OPERATOR_ACKNOWLEDGE_INCIDENT, whose content repeats that
%   SHA-256, carries this campaign's binding and names an operator and a
%   decision. It is bound to the incident's CONTENT: it cannot cover another
%   incident, whatever its file name, and it stops covering an incident whose
%   bytes change. The context carries no acknowledgement. Every file in the
%   incidents folder counts, including a partially written one.

    folder = fullfile(ctx.root, 'incidents');
    if ~isfolder(folder)
        return
    end
    d = dir(folder);
    d = d(~[d.isdir]);
    open = {};
    for i = 1:numel(d)
        f = fullfile(folder, d(i).name);
        sha = baseline_sha256(f);
        ackf = fullfile(ctx.root, 'acknowledgements', sprintf('ACK_%s.mat', sha));
        ok = false;
        if isfile(ackf)
            S = load(ackf, 'ack');
            ok = isfield(S, 'ack') && isfield(S.ack, 'incident_sha256') ...
                && strcmp(S.ack.incident_sha256, sha) && isequal(S.ack.binding, ctx.binding) ...
                && ischar(S.ack.decision) && ~isempty(strtrim(S.ack.decision)) ...
                && ischar(S.ack.operator) && ~isempty(strtrim(S.ack.operator));
        end
        if ~ok
            open{end+1} = d(i).name; %#ok<AGROW>
        end
    end
    assert(isempty(open), 'mc:campaign:unacknowledged_incident', ...
        ['The campaign is STOPPED: %d HARNESS_ERROR incident(s) in %s lack a ' ...
         'content-bound acknowledgement (%s). Review them and record a decision with ' ...
         'MC_OPERATOR_ACKNOWLEDGE_INCIDENT.'], numel(open), folder, strjoin(open, ', '));
end

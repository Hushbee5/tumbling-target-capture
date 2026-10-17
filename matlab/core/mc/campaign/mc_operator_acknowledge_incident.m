function ack = mc_operator_acknowledge_incident(ctx, incidentFile, decision, operator)
% MC_OPERATOR_ACKNOWLEDGE_INCIDENT  Record a person's decision on ONE incident.
%   ack = mc_operator_acknowledge_incident(ctx, incidentFile, decision, operator)
%
%   Binds the decision to the incident's RAW-BYTE SHA-256, this campaign's
%   binding, the operator's name, the UTC time and this process. Written once,
%   atomically, as <root>/acknowledgements/ACK_<sha256>.mat; it never covers
%   any other incident (MC_INCIDENT_GATE). Acknowledging an incident does not
%   authorise any rerun: an ambiguous attempt still needs its own adjudication
%   (MC_OPERATOR_ADJUDICATE_ATTEMPT).

    gOp = mc_campaign_guard(ctx, 'operator'); %#ok<NASGU>   % live lease for the write below
    assert(ischar(decision) && ~isempty(strtrim(decision)) && ischar(operator) ...
        && ~isempty(strtrim(operator)), 'mc:operator:decision', ...
        'An acknowledgement needs a decision text and the operator''s name.');
    folder = mc_abs_path(fullfile(ctx.root, 'incidents'));
    f = mc_abs_path(incidentFile);
    assert(isfile(f) && strcmpi(fileparts(f), folder), 'mc:operator:incident', ...
        'The incident must be a file in %s.', folder);
    sha = baseline_sha256(f);
    [~, nm, ext] = fileparts(f);
    ack = struct('schema', 'task4_mc_incident_ack_v1', 'incident_file', [nm ext], ...
        'incident_sha256', sha, 'binding', ctx.binding, 'decision', decision, ...
        'operator', operator, 'utc', mc_utc_now(), 'process', mc_process_identity());
    out = fullfile(ctx.root, 'acknowledgements');
    if ~isfolder(out), mkdir(out); end
    opts = struct();
    if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
    mc_atomic_write(fullfile(out, sprintf('ACK_%s.mat', sha)), struct('ack', ack), 'mat', opts);
end

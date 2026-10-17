function P = mc_condition_reproof(ctx, condition)
% MC_CONDITION_REPROOF  Re-prove one condition's checkpoint FROM SCRATCH.
%   P = mc_condition_reproof(ctx, condition) rescans the live checkpoint and
%   refuses unless ALL of the following hold:
%
%   RECORDS   <root>/<cond> holds EXACTLY the N x 3 files <cond>_t<NNN>_<method>.mat
%             for the intended trials - no missing unit, no extra, no directory
%             ('mc:closure:incomplete' / 'mc:closure:unexpected_file'); only the
%             '.tmp-' residue of an interrupted write of one of those files is
%             tolerated, never read, and bound in the history below. Each record
%             reads back under this campaign's binding with content matching its
%             name, condition and record kind. A Level-A status
%             (TARGET_MODEL_INTEGRATION_FAILURE, M_CONSISTENCY_FAILURE) is itself
%             one terminal record per method, so the denominator never shrinks.
%   HISTORY   every unit's COMPLETE attempt history passes the one strict history
%             validator (MC_ATTEMPT_LEDGER 'state', 'mc:ledger:history'): exact
%             names, contiguous attempts, every file's content and binding, every
%             superseded attempt's ruling bound to its own evidence and permitted
%             by it, the terminal record linked to the latest attempt.
%   RESERVE   every intended pair holds a reservation bound to this campaign,
%             condition, trial and the planned shard of the trial.
%   INVENTORY every other file in EVERY checkpoint location is accounted for
%             (MC_CHECKPOINT_INVENTORY): this condition's artefacts are validated
%             and bound; the other condition's well-named artefacts (concurrent,
%             disjoint work) are tolerated; anything else is refused.
%   INCIDENTS every incident is acknowledged (MC_INCIDENT_GATE).
%
%   P fields: condition, n, manifest (struct array file, sha256, status,
%   attempt, in trial-then-method order), manifest_sha256, history (struct
%   array file, sha256: EVERY other artefact of this condition - ledger files,
%   rulings, reservations, releases, shard locks, shard logs, the plan, its
%   incidents and their acknowledgements, residue - sorted by path),
%   history_sha256.

    c = mc_constants();
    methods = c.design.methods;
    ids = ctx.trial_ids;
    folder = fullfile(ctx.root, condition);
    assert(isfolder(folder), 'mc:closure:incomplete', 'Condition %s has no records.', condition);

    expected = cell(numel(ids) * numel(methods), 1);
    k = 0;
    for i = 1:numel(ids)
        for mi = 1:numel(methods)
            k = k + 1;
            expected{k} = sprintf('%s_t%03d_%s.mat', condition, ids(i), methods{mi});
        end
    end
    d = dir(folder);
    d = d(~ismember({d.name}, {'.', '..'}));
    assert(~any([d.isdir]), 'mc:closure:unexpected_file', ...
        'A directory exists inside the %s record folder.', condition);
    names = {d.name};
    stems = regexprep(expected, '\.mat$', '');
    isRes = false(size(names));
    for i = 1:numel(names)
        tok = regexp(names{i}, '^(.+)\.tmp-\d+-\d+\.mat$', 'tokens', 'once');
        isRes(i) = ~isempty(tok) && any(strcmp(tok{1}, stems));
    end
    extra = setdiff(names(~isRes), expected);
    missing = setdiff(expected, names);
    assert(isempty(extra), 'mc:closure:unexpected_file', ...
        'Unexpected file(s) in the %s checkpoint: %s', condition, strjoin(extra, ', '));
    if ~isempty(missing)
        error('mc:closure:incomplete', 'Condition %s lacks %d of %d terminal records (first: %s).', ...
            condition, numel(missing), numel(expected), missing{1});
    end

    [~, shardOf] = mc_shard_plan_read(ctx, condition);
    manifest = struct('file', {}, 'sha256', {}, 'status', {}, 'attempt', {});
    ledgerFiles = cell(0, 2);
    for k = 1:numel(expected)
        f = fullfile(folder, expected{k});
        tok = regexp(expected{k}, '_t(\d{3})_(proposed|nominal_mpc|apf)\.mat$', 'tokens', 'once');
        H = mc_attempt_ledger('state', ctx, condition, str2double(tok{1}), tok{2});
        assert(strcmp(H.status, 'TERMINAL'), 'mc:closure:ledger', ...
            'Unit %s is not terminal (%s).', H.unit, H.status);
        rec = H.record;
        assert(strcmp(rec.condition, condition) && strcmp(rec.kind, ctx.record_kind), ...
            'mc:closure:record', 'Record %s has the wrong condition or kind.', expected{k});
        ledgerFiles = [ledgerFiles; H.files]; %#ok<AGROW>
        manifest(end+1) = struct('file', [condition '/' expected{k}], 'sha256', baseline_sha256(f), ...
                                 'status', rec.status, 'attempt', rec.attempt); %#ok<AGROW>
    end
    for i = 1:numel(ids)
        r = mc_reservation('owner', ctx, condition, ids(i));
        o = r.owner;
        assert(r.exists && ~isempty(o) && isequal(o.binding, ctx.binding) ...
            && strcmp(o.condition, condition) && isequal(o.trial_id, ids(i)) ...
            && strcmp(o.shard_id, shardOf(ids(i))), 'mc:closure:reservation', ...
            'Pair %s t%03d holds no valid reservation of its planned shard.', condition, ids(i));
    end

    extraHistory = mc_checkpoint_inventory(ctx, condition, ledgerFiles);
    all_ = [ledgerFiles; extraHistory];
    [~, ord] = sort(all_(:, 1));
    all_ = all_(ord, :);
    assert(numel(unique(all_(:, 1))) == size(all_, 1), 'mc:closure:unexpected_file', ...
        'An artefact of condition %s is listed twice.', condition);
    history = struct('file', all_(:, 1).', 'sha256', all_(:, 2).');
    if isempty(all_)
        history = struct('file', {}, 'sha256', {});
    end
    mc_incident_gate(ctx);

    P = struct('condition', condition, 'n', numel(manifest), 'manifest', manifest, ...
               'manifest_sha256', mc_value_sha256(manifest), 'history', history, ...
               'history_sha256', mc_value_sha256(history));
end

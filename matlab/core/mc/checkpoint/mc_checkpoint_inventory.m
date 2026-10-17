function H = mc_checkpoint_inventory(ctx, condition, ledgerFiles)
% MC_CHECKPOINT_INVENTORY  Account for EVERY entry of the checkpoint tree; bind one condition's artefacts.
%   H = mc_checkpoint_inventory(ctx, condition, ledgerFiles)
%
%   Called by MC_CONDITION_REPROOF after the records and every unit's attempt
%   history have been re-proven; ledgerFiles (n x 2 cell, root-relative path and
%   SHA-256) are the ledger and ruling files those histories consist of. Every
%   entry of every location is classified; anything not listed below is
%   refused ('mc:closure:unexpected_file'), and an artefact of THIS condition
%   whose content does not validate is refused ('mc:closure:artefact').
%
%   THIS CONDITION (validated, and bound: returned in H with its SHA-256)
%     root            <C>_CLOSED residue of an interrupted closure write
%     <C>/            residue of an interrupted record write (the records
%                     themselves are bound by the caller's manifest)
%     attempts/       ledger files - ONLY those of a validated history
%                     (ledgerFiles); residue
%     decisions/      ADJUDICATE_* - ONLY those of a validated history;
%                     RELEASE_<C>_t<NNN>_<stamp> and RELEASE_SHARD_<C>_<S>_<stamp>,
%                     each valid and linked one-to-one with its released
%                     directory, whose owner.mat it binds by SHA-256; residue
%     reservations/   <C>_t<NNN>/ holding owner.mat only (validated by the
%                     caller); released/<C>_t<NNN>__<stamp>/ (linked)
%     shard_locks/    <C>_<S>/ holding owner.mat only - bound to this campaign,
%                     condition, a planned shard and its trial ids;
%                     released/<C>_<S>__<stamp>/ (linked)
%     plan/           <C>_PLAN.mat (validated by MC_SHARD_PLAN_READ)
%     shards/         <C>_<S>_<stamp>.mat shard-start logs - bound to this
%                     campaign, condition, a planned shard and its trial ids
%     incidents/      HARNESS_ERROR_<C>_t<NNN>_*.mat
%     acknowledgements/ ACK_<sha>.mat of an incident of this condition
%   THE OTHER CONDITION: its well-named artefacts in the same locations are
%   TOLERATED, including residue - concurrent, disjoint work (Condition-M
%   shards run while each of their pairs re-proves Condition U) must never make
%   this condition's proof fail. They are proven by that condition's own
%   closure.
%   EVERY acknowledgement is validated (schema, the incident SHA-256 it is named
%   after, this campaign's binding, decision, operator) and must match an
%   incident that is present with exactly those bytes; an orphan
%   acknowledgement means an acknowledged incident vanished or changed and is
%   refused. Residue ('<stem>.tmp-<pid>-<stamp>.mat', MC_ATOMIC_WRITE) is never
%   read.
%
%   H: n x 2 cell {root-relative path, SHA-256}, this condition's artefacts other
%   than its records and ledgerFiles.

    c = mc_constants();
    C = condition;
    conds = c.design.conditions;
    ids = ctx.trial_ids;
    root = ctx.root;
    [plan, ~] = mc_shard_plan_read(ctx, C);
    X = '(U|M)';
    T = 't(\d{3})';
    MTH = ['(' strjoin(c.design.methods, '|') ')'];
    RES = '(\.tmp-\d+-\d+)?';
    ST = '(\d{8}T\d{9})';
    ledgerSet = ledgerFiles(:, 1);
    H = cell(0, 2);

    % ---- root ---------------------------------------------------------------------
    dirsOK = [conds, {'attempts', 'decisions', 'acknowledgements', 'incidents', 'reservations', ...
                      'plan', 'shards', 'shard_locks'}];
    for e = entries(root)
        if e.isdir
            chk(any(strcmp(e.name, dirsOK)), root, e.name);
        else
            tok = regexp(e.name, ['^' X '_CLOSED' RES '\.mat$'], 'tokens', 'once');
            chk(~isempty(tok), root, e.name);
            if strcmp(tok{1}, C) && ~isempty(tok{2})
                H = add(H, ctx, fullfile(root, e.name));
            end
        end
    end

    % ---- record folders ---------------------------------------------------------------
    for ci = 1:numel(conds)
        folder = fullfile(root, conds{ci});
        for e = entries(folder)
            tok = regexp(e.name, ['^' conds{ci} '_' T '_' MTH RES '\.mat$'], 'tokens', 'once');
            chk(~e.isdir && ~isempty(tok) && in_ids(tok{1}, ids), folder, e.name);
            if strcmp(conds{ci}, C) && ~isempty(tok{3})
                H = add(H, ctx, fullfile(folder, e.name));
            end
        end
    end

    % ---- attempts -------------------------------------------------------------------------
    folder = fullfile(root, 'attempts');
    for e = entries(folder)
        tok = regexp(e.name, ['^' X '_' T '_' MTH '_a(\d+)_(STARTED|POST|OUTCOME)' RES '\.mat$'], ...
                     'tokens', 'once');
        chk(~e.isdir && ~isempty(tok) && in_ids(tok{2}, ids), folder, e.name);
        if strcmp(tok{1}, C)
            if isempty(tok{6})
                chk(any(strcmp(['attempts/' e.name], ledgerSet)), folder, e.name, ...
                    'is not part of any validated attempt history');
            else
                H = add(H, ctx, fullfile(folder, e.name));
            end
        end
    end

    % ---- decisions -------------------------------------------------------------------------
    folder = fullfile(root, 'decisions');
    linkedRes = {};  linkedShard = {};
    for e = entries(folder)
        f = fullfile(folder, e.name);
        t1 = regexp(e.name, ['^ADJUDICATE_' X '_' T '_' MTH '_a(\d+)' RES '\.mat$'], 'tokens', 'once');
        t2 = regexp(e.name, ['^RELEASE_SHARD_' X '_(S\d+)_' ST RES '\.mat$'], 'tokens', 'once');
        t3 = regexp(e.name, ['^RELEASE_' X '_' T '_' ST RES '\.mat$'], 'tokens', 'once');
        chk(~e.isdir && (~isempty(t1) || ~isempty(t2) || ~isempty(t3)), folder, e.name);
        if ~isempty(t1)
            chk(in_ids(t1{2}, ids), folder, e.name);
            if strcmp(t1{1}, C)
                if isempty(t1{5})
                    chk(any(strcmp(['decisions/' e.name], ledgerSet)), folder, e.name, ...
                        'is not part of any validated attempt history');
                else
                    H = add(H, ctx, f);
                end
            end
        elseif ~isempty(t2)
            if strcmp(t2{1}, C)
                if isempty(t2{4})
                    D = load_one(f, 'decision');
                    dname = sprintf('%s_%s__%s', C, t2{2}, t2{3});
                    rdir = fullfile(root, 'shard_locks', 'released', dname);
                    art(isstruct(D) && all(isfield(D, {'schema', 'condition', 'shard_id', ...
                        'owner_sha256', 'binding', 'operator', 'reason'})) ...
                        && strcmp(D.schema, 'task4_mc_shard_release_v1') && strcmp(D.condition, C) ...
                        && strcmp(D.shard_id, t2{2}) && any(strcmp(D.shard_id, plan.shard_ids)) ...
                        && isequal(D.binding, ctx.binding) && nonempty(D.operator) ...
                        && nonempty(D.reason) && isfolder(rdir) ...
                        && strcmp(D.owner_sha256, owner_sha(rdir)), f, ...
                        'is not a valid shard-lock release linked to its released lock');
                    linkedShard{end+1} = dname; %#ok<AGROW>
                end
                H = add(H, ctx, f);
            end
        else
            chk(in_ids(t3{2}, ids), folder, e.name);
            if strcmp(t3{1}, C)
                if isempty(t3{4})
                    D = load_one(f, 'decision');
                    dname = sprintf('%s_t%s__%s', C, t3{2}, t3{3});
                    rdir = fullfile(root, 'reservations', 'released', dname);
                    art(isstruct(D) && all(isfield(D, {'schema', 'condition', 'trial_id', ...
                        'owner_sha256', 'binding', 'operator', 'reason'})) ...
                        && strcmp(D.schema, 'task4_mc_reservation_release_v1') ...
                        && strcmp(D.condition, C) && isequal(D.trial_id, str2double(t3{2})) ...
                        && isequal(D.binding, ctx.binding) && nonempty(D.operator) ...
                        && nonempty(D.reason) && isfolder(rdir) ...
                        && strcmp(D.owner_sha256, owner_sha(rdir)), f, ...
                        'is not a valid reservation release linked to its released reservation');
                    linkedRes{end+1} = dname; %#ok<AGROW>
                end
                H = add(H, ctx, f);
            end
        end
    end

    % ---- incidents (every file needs a content-bound acknowledgement: MC_INCIDENT_GATE) ----
    folder = fullfile(root, 'incidents');
    incSha = {};  incCond = {};
    for e = entries(folder)
        tok = regexp(e.name, ['^HARNESS_ERROR_' X '_' T '_.+\.mat$'], 'tokens', 'once');
        chk(~e.isdir && ~isempty(tok) && in_ids(tok{2}, ids), folder, e.name);
        f = fullfile(folder, e.name);
        incSha{end+1} = baseline_sha256(f); %#ok<AGROW>
        incCond{end+1} = tok{1}; %#ok<AGROW>
        if strcmp(tok{1}, C)
            H(end+1, :) = {rel(ctx, f), incSha{end}}; %#ok<AGROW>
        end
    end

    % ---- acknowledgements --------------------------------------------------------------------
    folder = fullfile(root, 'acknowledgements');
    for e = entries(folder)
        tok = regexp(e.name, ['^ACK_([0-9a-f]{64})' RES '\.mat$'], 'tokens', 'once');
        chk(~e.isdir && ~isempty(tok), folder, e.name);
        k = find(strcmp(incSha, tok{1}), 1);
        chk(~isempty(k), folder, e.name, ...
            'acknowledges no incident present with those bytes (orphan acknowledgement)');
        f = fullfile(folder, e.name);
        if isempty(tok{2})
            A = load_one(f, 'ack');
            art(isstruct(A) && all(isfield(A, {'schema', 'incident_sha256', 'binding', 'decision', ...
                'operator'})) && strcmp(A.schema, 'task4_mc_incident_ack_v1') ...
                && strcmp(A.incident_sha256, tok{1}) && isequal(A.binding, ctx.binding) ...
                && nonempty(A.decision) && nonempty(A.operator), f, 'is not a valid acknowledgement');
        end
        if strcmp(incCond{k}, C)
            H = add(H, ctx, f);
        end
    end

    % ---- reservations --------------------------------------------------------------------------
    folder = fullfile(root, 'reservations');
    for e = entries(folder)
        if e.isdir && strcmp(e.name, 'released')
            continue
        end
        tok = regexp(e.name, ['^' X '_' T '$'], 'tokens', 'once');
        chk(e.isdir && ~isempty(tok) && in_ids(tok{2}, ids), folder, e.name);
        H = owner_dir(H, ctx, fullfile(folder, e.name), strcmp(tok{1}, C), RES);
    end
    folder = fullfile(root, 'reservations', 'released');
    for e = entries(folder)
        tok = regexp(e.name, ['^' X '_' T '__' ST '$'], 'tokens', 'once');
        chk(e.isdir && ~isempty(tok) && in_ids(tok{2}, ids), folder, e.name);
        if strcmp(tok{1}, C)
            chk(any(strcmp(e.name, linkedRes)), folder, e.name, 'has no release decision');
        end
        H = owner_dir(H, ctx, fullfile(folder, e.name), strcmp(tok{1}, C), RES);
    end

    % ---- shard locks -------------------------------------------------------------------------------
    folder = fullfile(root, 'shard_locks');
    for e = entries(folder)
        if e.isdir && strcmp(e.name, 'released')
            continue
        end
        tok = regexp(e.name, ['^' X '_(S\d+)$'], 'tokens', 'once');
        chk(e.isdir && ~isempty(tok), folder, e.name);
        mine = strcmp(tok{1}, C);
        if mine
            k = find(strcmp(plan.shard_ids, tok{2}), 1);
            chk(~isempty(k), folder, e.name, 'is not a planned shard');
            of = fullfile(folder, e.name, 'owner.mat');
            if isfile(of)
                O = load_one(of, 'owner');
                art(isstruct(O) && all(isfield(O, {'schema', 'binding', 'condition', 'shard_id', ...
                    'trial_ids', 'process'})) && strcmp(O.schema, 'task4_mc_shard_lock_v1') ...
                    && isequal(O.binding, ctx.binding) && strcmp(O.condition, C) ...
                    && strcmp(O.shard_id, tok{2}) && isequal(O.trial_ids, plan.shards{k}), of, ...
                    'is not this campaign''s lock of that planned shard');
            end
        end
        H = owner_dir(H, ctx, fullfile(folder, e.name), mine, RES);
    end
    folder = fullfile(root, 'shard_locks', 'released');
    for e = entries(folder)
        tok = regexp(e.name, ['^' X '_(S\d+)__' ST '$'], 'tokens', 'once');
        chk(e.isdir && ~isempty(tok), folder, e.name);
        if strcmp(tok{1}, C)
            chk(any(strcmp(e.name, linkedShard)), folder, e.name, 'has no release decision');
        end
        H = owner_dir(H, ctx, fullfile(folder, e.name), strcmp(tok{1}, C), RES);
    end

    % ---- plan ------------------------------------------------------------------------------------------
    folder = fullfile(root, 'plan');
    for e = entries(folder)
        tok = regexp(e.name, ['^' X '_PLAN' RES '\.mat$'], 'tokens', 'once');
        chk(~e.isdir && ~isempty(tok), folder, e.name);
        if strcmp(tok{1}, C)
            H = add(H, ctx, fullfile(folder, e.name));
        end
    end

    % ---- shard-start logs ---------------------------------------------------------------------------------
    folder = fullfile(root, 'shards');
    for e = entries(folder)
        tok = regexp(e.name, ['^' X '_(S\d+)_' ST RES '\.mat$'], 'tokens', 'once');
        chk(~e.isdir && ~isempty(tok), folder, e.name);
        if strcmp(tok{1}, C)
            f = fullfile(folder, e.name);
            if isempty(tok{4})
                k = find(strcmp(plan.shard_ids, tok{2}), 1);
                chk(~isempty(k), folder, e.name, 'is not a planned shard');
                Sh = load_one(f, 'shard');
                art(isstruct(Sh) && all(isfield(Sh, {'condition', 'shard_id', 'trial_ids', 'binding'})) ...
                    && strcmp(Sh.condition, C) && strcmp(Sh.shard_id, tok{2}) ...
                    && isequal(Sh.trial_ids, plan.shards{k}) && isequal(Sh.binding, ctx.binding), f, ...
                    'is not this campaign''s start log of that planned shard');
            end
            H = add(H, ctx, f);
        end
    end
end

% =====================================================================
function H = owner_dir(H, ctx, d, mine, RES)
% A reservation or shard-lock directory holds owner.mat and, at most, the
% residue of its interrupted write - nothing else.
    for e = entries(d)
        ok = ~e.isdir && (strcmp(e.name, 'owner.mat') || ~isempty(regexp(e.name, ['^owner' RES '\.mat$'], 'once')));
        chk(ok, d, e.name);
        if mine
            H = add(H, ctx, fullfile(d, e.name));
        end
    end
end

% =====================================================================
function s = owner_sha(d)
    f = fullfile(d, 'owner.mat');
    s = '';
    if isfile(f), s = baseline_sha256(f); end
end

% =====================================================================
function E = entries(folder)
    E = struct('name', {}, 'isdir', {});
    if ~isfolder(folder), return, end
    d = dir(folder);
    d = d(~ismember({d.name}, {'.', '..'}));
    E = struct('name', {d.name}, 'isdir', {d.isdir});
    E = E(:).';
end

% =====================================================================
function tf = in_ids(s, ids)
    tf = any(ids == str2double(s));
end

% =====================================================================
function tf = nonempty(s)
    tf = ischar(s) && ~isempty(strtrim(s));
end

% =====================================================================
function X = load_one(f, var)
    S = load(f);
    fn = fieldnames(S);
    art(numel(fn) == 1 && strcmp(fn{1}, var) && isstruct(S.(var)) && isscalar(S.(var)), f, ...
        sprintf('does not hold exactly one ''%s'' struct', var));
    X = S.(var);
end

% =====================================================================
function H = add(H, ctx, f)
    H(end+1, :) = {rel(ctx, f), baseline_sha256(f)};
end

% =====================================================================
function r = rel(ctx, f)
    r = strrep(f(numel(ctx.root) + 2:end), filesep, '/');
end

% =====================================================================
function chk(tf, folder, name, why)
    if nargin < 4, why = 'is not an accounted-for checkpoint artefact'; end
    if ~tf
        error('mc:closure:unexpected_file', 'Unexpected checkpoint entry %s in %s: %s.', name, folder, why);
    end
end

% =====================================================================
function art(tf, f, why)
    if ~tf
        error('mc:closure:artefact', 'Checkpoint artefact %s %s.', f, why);
    end
end

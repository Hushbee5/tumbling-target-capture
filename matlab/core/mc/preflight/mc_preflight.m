function pre = mc_preflight(mode, inputs, opts)
% MC_PREFLIGHT  The additive MC preflight of protocol Sec. 11.
%   (opts.checkpoint_scope, execution mode only: 'full' (default) scans the
%   whole checkpoint in check 9; struct('condition', c, 'trial_id', i) scans
%   that pair's records only - used by MC_CAMPAIGN_GUARD before each pair and
%   method, while every shard start and closure uses the full scope.)
%   pre = mc_preflight('verification')
%       NON-SCIENTIFIC source-test mode. Runs every check that is meaningful
%       before the MC source is frozen and reports each one. It NEVER
%       authorises anything: pre.authorised is always false.
%
%   pre = mc_preflight('generation', inputs)
%       Gate of MC_SCIENTIFIC_TRIAL_TABLE (Sec. 10 step 6). inputs:
%         protocol_sha256, mc_source_aggregate, mc_impl_commit
%
%   pre = mc_preflight('execution', inputs)
%       Gate of the scientific campaign (Sec. 10 step 11). inputs: the four
%       frozen identities of the authorising invocation
%         protocol_sha256, mc_source_aggregate, mc_impl_commit,
%         freeze_record_sha256
%       The canonical CSV SHA-256 is NOT an input: it is READ from the
%       committed freeze record (Sec. 11 check 6).
%
%   In 'generation' and 'execution' the FIRST failing check aborts with its
%   own 'mc:preflight:*' identifier; pre.authorised = true only when every
%   check passed. No placeholder can pass: every identity is verified against
%   committed Git history and live file bytes.
%
%   CHECKS (Sec. 11 numbering)
%   1 ANCESTRY    anchor f9791f0 and the protocol commit are ancestors of HEAD;
%                 scientific modes: the MC implementation commit as well
%   2 ADDITIVE    git diff --quiet f9791f0 HEAD -- src ':(exclude)src/mc';
%                 scientific modes: git diff --quiet <impl> HEAD -- src/mc
%   3 CLEAN       git diff --quiet -- src ; git diff --cached --quiet HEAD -- src ;
%                 untracked files under src: only src/mc/** in verification mode,
%                 none in scientific modes
%   4 AGGREGATES  17-file production, 60-file R7, the two sweep harnesses; the
%                 src/mc aggregate (every file a .m) - equal to the supplied
%                 value in scientific modes, reported in verification mode
%   5 PROTOCOL    MC_GIT_FILE_STATE: tracked, one stage-0 entry, WORKTREE ==
%                 INDEX and INDEX == HEAD proven SEPARATELY, and the worktree,
%                 index and HEAD bytes all hash to the frozen protocol SHA-256;
%                 committed blob id as frozen
%   6 TRIAL TABLE execution only: freeze record and CSV each clean in the same
%                 per-file sense; the freeze record hashes to the supplied
%                 SHA-256 and declares protocol / aggregate / commit / seed 116075
%                 / N_PHYSICAL 100 / ZERO runs and the MAPPING IMPLEMENTATION
%                 (src/mc/trials/mc_trial_mapping.m and its SHA-256, which must
%                 equal both the working-tree file and its blob at the
%                 implementation commit); the CSV hashes to the SHA-256 DECLARED
%                 IN THE COMMITTED FREEZE RECORD; Git history proves the CSV and
%                 the record were added together in ONE commit whose parent held
%                 neither, after the implementation commit, and never touched
%                 again (MC_TRIAL_FREEZE_HISTORY)
%   7 RECORDS     Object A, Object B v2, the deterministic, transition and
%                 post-commit records - each a TRACKED authority record, proven
%                 in the per-file Git sense (MC_GIT_FILE_STATE: tracked, one
%                 stage-0 entry, WORKTREE == INDEX and INDEX == HEAD separately,
%                 and the worktree, index and HEAD bytes all hashing to its
%                 frozen SHA-256), so a staged change with a restored worktree is
%                 seen - and .gitattributes (its reviewed identity, containing
%                 the CSV rule; scientific modes: clean in the per-file sense)
%   8 RESULTS     the frozen deterministic artifacts and the tuning record
%   9 DESTINATIONS verification: results/task4/mc absent; generation: CSV and
%                 freeze record absent; execution: an absent checkpoint (fresh)
%                 or one whose every record reads back under this binding and
%                 whose every artefact is younger than the trial-freeze commit

    if nargin < 2, inputs = struct(); end
    if nargin < 3 || isempty(opts), opts = struct(); end
    if ~isfield(opts, 'checkpoint_scope'), opts.checkpoint_scope = 'full'; end
    c = mc_constants();
    root = mc_repo_root();
    sci = ~strcmp(mode, 'verification');
    assert(any(strcmp(mode, {'verification', 'generation', 'execution'})), ...
        'mc:preflight:mode', 'Unknown preflight mode ''%s''.', mode);

    pre = struct('mode', mode, 'authorised', false, 'inputs', inputs, ...
                 'verified', struct(), 'repo', root, 'utc', mc_utc_now(), ...
                 'checks', struct('id', {}, 'name', {}, 'pass', {}, 'detail', {}));

    % ---- inputs ---------------------------------------------------------------
    if sci
        need = {'protocol_sha256', 'mc_source_aggregate', 'mc_impl_commit'};
        if strcmp(mode, 'execution'), need{end+1} = 'freeze_record_sha256'; end
        assert(isstruct(inputs) && all(isfield(inputs, need)), 'mc:preflight:inputs', ...
            'The %s preflight needs the inputs: %s.', mode, strjoin(need, ', '));
        assert(is_hex(inputs.protocol_sha256, 64) && strcmp(inputs.protocol_sha256, c.protocol.sha256), ...
            'mc:preflight:protocol_input', 'The supplied protocol SHA-256 is not the frozen one.');
        assert(is_hex(inputs.mc_source_aggregate, 64), 'mc:preflight:aggregate_input', ...
            'The supplied MC-source aggregate is not a 64-hex SHA-256.');
        assert(is_hex(inputs.mc_impl_commit, 40), 'mc:preflight:commit_input', ...
            'The supplied MC implementation commit is not a 40-hex commit id.');
        if strcmp(mode, 'execution')
            assert(is_hex(inputs.freeze_record_sha256, 64), 'mc:preflight:freeze_input', ...
                'The supplied freeze-record SHA-256 is not a 64-hex SHA-256.');
        end
    end

    % ---- 1 ANCESTRY -----------------------------------------------------------
    pre = chk(pre, sci, '1a', 'anchor commit is an ancestor of HEAD', ...
        is_ancestor(root, c.anchor.commit), c.anchor.commit);
    pre = chk(pre, sci, '1b', 'protocol commit is an ancestor of HEAD', ...
        is_ancestor(root, c.protocol.commit), c.protocol.commit);
    if sci
        [t, ~] = mc_git(root, sprintf('cat-file -t %s', inputs.mc_impl_commit), true);
        pre = chk(pre, sci, '1c', 'MC implementation commit exists and is an ancestor of HEAD', ...
            strcmp(t, 'commit') && is_ancestor(root, inputs.mc_impl_commit), inputs.mc_impl_commit);
    end

    % ---- 2 ADDITIVE ONLY --------------------------------------------------------
    [~, e] = mc_git(root, sprintf('diff --quiet %s HEAD -- src ":(exclude)src/mc"', c.anchor.commit), true);
    pre = chk(pre, sci, '2a', 'src outside src/mc is byte-identical to the anchor', e == 0, ...
        sprintf('exit %d', e));
    if sci
        [~, e] = mc_git(root, sprintf('diff --quiet %s HEAD -- src/mc', inputs.mc_impl_commit), true);
        pre = chk(pre, sci, '2b', 'src/mc unchanged since the MC implementation commit', e == 0, ...
            sprintf('exit %d', e));
        [lst, ~] = mc_git(root, sprintf('ls-tree -r --name-only %s -- src/mc', inputs.mc_impl_commit), true);
        pre = chk(pre, sci, '2c', 'the MC implementation commit contains src/mc', ~isempty(lst), '');
    end

    % ---- 3 CLEAN SOURCE / INDEX / WORKTREE --------------------------------------
    [~, e1] = mc_git(root, 'diff --quiet -- src', true);
    [~, e2] = mc_git(root, 'diff --cached --quiet HEAD -- src', true);
    pre = chk(pre, sci, '3a', 'tracked src clean in the worktree', e1 == 0, sprintf('exit %d', e1));
    pre = chk(pre, sci, '3b', 'tracked src clean in the index', e2 == 0, sprintf('exit %d', e2));
    untracked = split_lines(mc_git(root, 'ls-files --others --exclude-standard -- src', true));
    if sci
        pre = chk(pre, sci, '3c', 'no untracked file under src', isempty(untracked), ...
            strjoin(untracked, ', '));
    else
        outside = untracked(~startsWith(untracked, [c.mc.src_dir '/']));
        pre = chk(pre, sci, '3c', 'untracked files under src exist only in src/mc', ...
            isempty(outside), sprintf('%d untracked src/mc file(s)', numel(untracked)));
    end

    % ---- 4 BYTE AGGREGATES --------------------------------------------------------
    assert(isequal(sort(c.production17.files), c.production17.files), 'mc:preflight:manifest', ...
        'The 17-file manifest is not in LC_ALL=C order.');
    a17 = mc_file_aggregate(root, c.production17.files);
    pre = chk(pre, sci, '4a', '17-file production aggregate', ...
        strcmp(a17, c.production17.aggregate), a17);
    r7files = mc_list_files(root, c.r7.dir);
    a7 = mc_file_aggregate(root, r7files);
    pre = chk(pre, sci, '4b', '60-file R7 baseline aggregate', ...
        numel(r7files) == c.r7.n_files && strcmp(a7, c.r7.aggregate), ...
        sprintf('%s (%d files)', a7, numel(r7files)));
    for key = {'harness_sweep', 'harness_final'}
        k = find(strcmp(c.files(:, 1), key{1}), 1);
        h = baseline_sha256(fullfile(root, strrep(c.files{k, 2}, '/', filesep)));
        pre = chk(pre, sci, '4c', ['sweep harness ' c.files{k, 2}], strcmp(h, c.files{k, 3}), h);
    end
    mcFiles = mc_list_files(root, c.mc.src_dir);
    allM = ~isempty(mcFiles) && all(endsWith(mcFiles, '.m'));
    pre = chk(pre, sci, '4d', 'every src/mc file is a .m file (LF-protected by *.m text eol=lf)', ...
        allM, sprintf('%d file(s)', numel(mcFiles)));
    aMC = '';
    if ~isempty(mcFiles)
        aMC = mc_file_aggregate(root, mcFiles);
    end
    pre.verified.mc_source_aggregate_worktree = aMC;
    pre.verified.mc_source_files = mcFiles;
    if sci
        pre = chk(pre, sci, '4e', 'src/mc aggregate equals the supplied frozen value', ...
            strcmp(aMC, inputs.mc_source_aggregate), aMC);
        pre.verified.mc_source_aggregate = aMC;
        pre.verified.mc_impl_commit = inputs.mc_impl_commit;
    end

    % ---- 5 COMMITTED PROTOCOL ----------------------------------------------------
    pre = committed_file(pre, sci, '5', root, c.protocol.path, c.protocol.sha256);
    blob = mc_git(root, sprintf('rev-parse HEAD:%s', c.protocol.path), true);
    pre = chk(pre, sci, '5d', 'committed protocol blob id as frozen', ...
        strcmp(blob, c.protocol.blob), blob);

    % ---- 6 COMMITTED TRIAL-TABLE PROVENANCE (execution) ---------------------------
    if strcmp(mode, 'execution')
        pre = committed_file(pre, sci, '6a', root, c.freeze_record.path, inputs.freeze_record_sha256);
        txt = fileread(fullfile(root, strrep(c.freeze_record.path, '/', filesep)));
        F = mc_freeze_record_parse(txt);
        pre = chk(pre, sci, '6b', 'freeze record declares the canonical CSV path', ...
            strcmp(F.csv_path, c.csv.path), F.csv_path);
        pre = chk(pre, sci, '6c', 'freeze record declares the frozen protocol SHA-256', ...
            strcmp(F.protocol_sha256, c.protocol.sha256), F.protocol_sha256);
        pre = chk(pre, sci, '6d', 'freeze record declares the supplied MC-source aggregate', ...
            strcmp(F.mc_source_aggregate, inputs.mc_source_aggregate), F.mc_source_aggregate);
        pre = chk(pre, sci, '6e', 'freeze record declares the supplied implementation commit', ...
            strcmp(F.mc_impl_commit, inputs.mc_impl_commit), F.mc_impl_commit);
        pre = chk(pre, sci, '6f', 'freeze record declares seed 116075 and N_PHYSICAL 100', ...
            F.seed == c.rng.seed && F.N_PHYSICAL == c.design.N_PHYSICAL, ...
            sprintf('seed %g, N %g', F.seed, F.N_PHYSICAL));
        pre = chk(pre, sci, '6g', 'freeze record declares ZERO scientific runs at freeze', ...
            strcmp(F.runs_at_freeze, 'ZERO'), F.runs_at_freeze);
        mapRel = 'src/mc/trials/mc_trial_mapping.m';
        mapW = baseline_sha256(fullfile(root, strrep(mapRel, '/', filesep)));
        mapI = blob_sha256(root, sprintf('%s:%s', inputs.mc_impl_commit, mapRel));
        pre = chk(pre, sci, '6i', 'freeze record binds the mapping implementation file and SHA-256', ...
            strcmp(F.mapping_file, mapRel) && strcmp(F.mapping_sha256, mapW) ...
            && strcmp(F.mapping_sha256, mapI), sprintf('%s %s', F.mapping_file, F.mapping_sha256));
        pre = committed_file(pre, sci, '6h', root, c.csv.path, F.csv_sha256);
        H = mc_trial_freeze_history(root, c.csv.path, c.freeze_record.path, inputs.mc_impl_commit);
        pre = chk(pre, sci, '6j', ['CSV and freeze record committed together once, after the ' ...
            'implementation commit, never touched again'], H.pass, strjoin(H.reasons, '; '));
        pre = chk(pre, sci, '6k', 'the freeze commit''s CSV blob hashes to the declared SHA-256', ...
            strcmp(blob_sha256(root, sprintf('%s:%s', H.trial_commit, c.csv.path)), F.csv_sha256), ...
            H.trial_commit);
        pre = chk(pre, sci, '6l', 'the freeze commit''s record blob hashes to the supplied SHA-256', ...
            strcmp(blob_sha256(root, sprintf('%s:%s', H.trial_commit, c.freeze_record.path)), ...
                   inputs.freeze_record_sha256), H.trial_commit);
        pre.verified.trial_csv_sha256     = F.csv_sha256;
        pre.verified.freeze_record_sha256 = inputs.freeze_record_sha256;
        pre.verified.trial_commit         = H.trial_commit;
        pre.verified.trial_commit_time    = H.trial_commit_time;
    end

    % ---- 7 OTHER RECORDS / 8 RESULTS -------------------------------------------
    for k = 1:size(c.files, 1)
        if startsWith(c.files{k, 1}, 'harness_')
            continue
        end
        rel = c.files{k, 2};
        if startsWith(rel, 'notes/')
            % a TRACKED authority record: never the worktree bytes alone
            s = mc_git_file_state(root, rel, c.files{k, 3});
            pre = chk(pre, sci, '7', [rel ' tracked; worktree == index == HEAD == frozen SHA-256'], ...
                s.matches, sprintf('%s | %s', s.worktree_sha256, state_text(s)));
            continue
        end
        f = fullfile(root, strrep(rel, '/', filesep));
        h = '';
        if isfile(f), h = baseline_sha256(f); end
        id = '7';
        if startsWith(rel, 'results/'), id = '8'; end          % untracked results: bytes only
        pre = chk(pre, sci, id, rel, strcmp(h, c.files{k, 3}), h);
    end
    ga = fileread(fullfile(root, '.gitattributes'));
    pre = chk(pre, sci, '7g', '.gitattributes carries the reviewed CSV rule', ...
        any(strcmp(regexp(ga, '\n', 'split'), c.gitattributes.csv_rule)), c.gitattributes.csv_rule);
    if sci
        k = find(strcmp(c.files(:, 1), 'gitattributes'), 1);
        gs = mc_git_file_state(root, '.gitattributes');
        pre = chk(pre, sci, '7h', ['.gitattributes clean (worktree == index == HEAD) at its ' ...
            'reviewed identity'], gs.clean && strcmp(gs.head_sha256, c.files{k, 3}), state_text(gs));
    end

    % ---- 9 DESTINATIONS -----------------------------------------------------------
    dest = fullfile(root, strrep(c.mc.dest_dir, '/', filesep));
    csvF = fullfile(root, strrep(c.csv.path, '/', filesep));
    frF  = fullfile(root, strrep(c.freeze_record.path, '/', filesep));
    switch mode
        case 'verification'
            pre = chk(pre, sci, '9', 'no MC destination exists (results/task4/mc absent)', ...
                ~isfolder(dest) && ~isfile(csvF) && ~isfile(frF), c.mc.dest_dir);
        case 'generation'
            pre = chk(pre, sci, '9', 'canonical CSV and freeze record absent before generation', ...
                ~isfile(csvF) && ~isfile(frF) && ~isfolder(fullfile(dest, 'checkpoint')), c.csv.path);
        case 'execution'
            ck = fullfile(dest, 'checkpoint');
            ok = true;  det = 'fresh (no checkpoint)';
            if isfolder(ck)
                b = mc_binding('SCIENTIFIC', struct('mode', 'execution', 'authorised', true, ...
                                                    'verified', pre.verified));
                if isstruct(opts.checkpoint_scope)
                    conds = {opts.checkpoint_scope.condition};
                    ids = opts.checkpoint_scope.trial_id;
                else
                    conds = c.design.conditions;
                    ids = 1:c.design.N_PHYSICAL;
                end
                t0 = pre.verified.trial_commit_time;
                young = true;  oldest = '';
                for cond = conds
                    S = mc_record_scan(ck, cond{1}, b, ids);          % aborts on a binding mismatch
                    for i = 1:numel(S.paths)
                        if ~isempty(S.paths{i})
                            r = mc_record_read(S.paths{i}, b);
                            if utc_seconds(r.created_utc) < t0
                                young = false;  oldest = S.paths{i};
                            end
                        end
                    end
                end
                if ~isstruct(opts.checkpoint_scope)
                    [young2, oldest2] = ledger_young(ck, t0);
                    young = young && young2;
                    if ~young2, oldest = oldest2; end
                end
                ok = young;
                det = 'resume: every record reads back under this binding and postdates the freeze';
                if ~young
                    det = sprintf('an artefact predates the trial-freeze commit: %s', oldest);
                end
            end
            pre = chk(pre, sci, '9', 'checkpoint destination fresh or binding-consistent', ok, det);
    end

    pre.authorised = sci && all([pre.checks.pass]);
end

% =====================================================================
function pre = chk(pre, enforce, id, name, pass, detail)
    pre.checks(end+1) = struct('id', id, 'name', name, 'pass', logical(pass), 'detail', detail);
    if enforce
        assert(logical(pass), ['mc:preflight:check_' strrep(id, '.', '_')], ...
            'PREFLIGHT ABORT at check %s (%s): %s', id, name, detail);
    end
end

% =====================================================================
function ok = is_ancestor(root, commit)
    [~, e] = mc_git(root, sprintf('merge-base --is-ancestor %s HEAD', commit), true);
    ok = (e == 0);
end

% =====================================================================
function ok = is_hex(s, n)
    ok = ischar(s) && numel(s) == n && all(ismember(s, '0123456789abcdef'));
end

% =====================================================================
function L = split_lines(s)
    if isempty(s)
        L = cell(0, 1);
        return
    end
    L = strtrim(regexp(s, '\r?\n', 'split'));
    L = L(~cellfun(@isempty, L));
    L = L(:);
end

% =====================================================================
function pre = committed_file(pre, sci, id, root, rel, wantSha)
% Per-file Git proof (MC_GIT_FILE_STATE): tracked, one stage-0 entry,
% WORKTREE == INDEX and INDEX == HEAD established SEPARATELY, and the working-
% tree, index and HEAD bytes all hash to wantSha. A single 'git diff HEAD' is
% blind to a staged change whose worktree copy was restored; this is not.
    s = mc_git_file_state(root, rel);
    pre = chk(pre, sci, [id 'a'], [rel ' tracked; worktree == index == HEAD'], s.clean, state_text(s));
    pre = chk(pre, sci, [id 'b'], [rel ' working-tree SHA-256'], strcmp(s.worktree_sha256, wantSha), ...
        s.worktree_sha256);
    pre = chk(pre, sci, [id 'c'], [rel ' committed-blob SHA-256'], ...
        strcmp(s.head_sha256, wantSha) && strcmp(s.index_sha256, wantSha), s.head_sha256);
end

% =====================================================================
function t = state_text(s)
    t = sprintf('tracked %d, stage0 %d, worktree==index %d, index==HEAD %d, blobs equal %d', ...
        s.tracked, s.stage0, s.wt_eq_index, s.index_eq_head, strcmp(s.index_blob, s.head_blob));
end

% =====================================================================
function h = blob_sha256(root, spec)
% SHA-256 of the raw bytes of a committed blob, written by git to a temporary
% file outside the repository.
    h = '';
    tmp = fullfile(tempdir, sprintf('mc_blob_%d_%s.bin', feature('getpid'), ...
                   char(datetime('now', 'Format', 'yyyyMMddHHmmssSSSSSS'))));
    cl = onCleanup(@() delete_if_exists(tmp));
    [st, ~] = system(sprintf('git -C "%s" cat-file blob "%s" > "%s"', root, spec, tmp));
    if st == 0 && isfile(tmp)
        h = baseline_sha256(tmp);
    end
    clear cl
end

% =====================================================================
function s = utc_seconds(str)
    s = posixtime(datetime(str, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', 'TimeZone', 'UTC'));
end

% =====================================================================
function [young, oldest] = ledger_young(ck, t0)
% Every plan, reservation and shard-lock owner (current and released), attempt,
% shard log, incident, decision and acknowledgement file must postdate the
% trial-freeze commit (Sec. 10 step 10).
    young = true;  oldest = '';
    spec = {'plan', 'plan', 'created_utc'; 'attempts', 'attempt', 'utc'; ...
            'shards', 'shard', 'created_utc'; 'incidents', 'incident', 'created_utc'; ...
            'decisions', 'decision', 'utc'; 'acknowledgements', 'ack', 'utc'};
    for k = 1:size(spec, 1)
        folder = fullfile(ck, spec{k, 1});
        if ~isfolder(folder), continue, end
        d = dir(fullfile(folder, '*.mat'));
        for i = 1:numel(d)
            if contains(d(i).name, '.tmp-'), continue, end
            S = load(fullfile(folder, d(i).name));
            if isfield(S, spec{k, 2}) && isfield(S.(spec{k, 2}), spec{k, 3})
                if utc_seconds(S.(spec{k, 2}).(spec{k, 3})) < t0
                    young = false;  oldest = fullfile(folder, d(i).name);
                end
            end
        end
    end
    for rs = {fullfile(ck, 'reservations'), fullfile(ck, 'reservations', 'released'), ...
              fullfile(ck, 'shard_locks'), fullfile(ck, 'shard_locks', 'released')}
        if ~isfolder(rs{1}), continue, end
        d = dir(rs{1});
        for i = 1:numel(d)
            f = fullfile(rs{1}, d(i).name, 'owner.mat');
            if d(i).isdir && ~any(strcmp(d(i).name, {'.', '..'})) && isfile(f)
                S = load(f, 'owner');
                if utc_seconds(S.owner.created_utc) < t0
                    young = false;  oldest = f;
                end
            end
        end
    end
end

% =====================================================================
function delete_if_exists(f)
    if isfile(f)
        delete(f);
    end
end

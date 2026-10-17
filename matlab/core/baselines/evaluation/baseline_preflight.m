function pre = baseline_preflight(p, opt)
% BASELINE_PREFLIGHT  The Sec. 11 provenance gate for the baseline evaluation.
%   pre = baseline_preflight(p, opt) verifies every frozen identity of protocol
%   Sec. 2 and refuses the run if any of them moved, or if any destination
%   already exists. It ABORTS by raising; it never repairs, normalises or
%   continues past a mismatch.
%
%   EVERY FROZEN IDENTITY OF PROTOCOL SEC. 2 IS COVERED, in this order:
%     1. the protocol record itself           07acf575...
%     2. the baseline-support aggregate       the SUPPLIED frozen value, matched
%                                             against both computed forms
%     3. the 17-file production aggregate     bd3ea140...
%     3b. the tracked production WORKTREE     git diff --quiet HEAD -- src
%         (catches an uncommitted edit to a TRACKED production source, which
%          leaves the HEAD:src tree object below completely unchanged;
%          untracked src/baselines/** is correctly ignored)
%     4. the tracked src tree                 HEAD:src == d641966...
%     5. the four frozen final800 artifacts   by SHA-256
%     6. the frozen 800 s protocol            036670b0...
%        the frozen 800 s harness             0b8afa51...
%        the frozen 800 s results record      9bf4207b...
%     7. the protected 400 s reference        b6d1efd8... and 4 462 193 bytes
%     8. every baseline destination is ABSENT (relaxable for the post-run recheck)
%
%   THE POST-RUN INTEGRITY RECHECK CALLS THIS SAME FUNCTION, so it covers every
%   identity above rather than a subset. Only the destination-absence clause is
%   relaxed after the run, because the destinations then exist by design.
%
%   THE 17-FILE MANIFEST IS READ, NOT RE-DERIVED. Its per-file table lives in
%   notes/task4_alpha_sweep_protocol.md Sec. 2.2 and is parsed from there, so
%   this file holds no second copy of the manifest that could silently drift
%   from the frozen one. The two harnesses task4_alpha_sweep.m and
%   task4_final_800s.m are deliberately NOT in that set - they are hashed
%   separately - and the parse asserts the table still has exactly 17 rows.
%
%   SEPARATOR AMBIGUITY IS RESOLVED BY ACCEPTING EITHER FORM, NOT BY GUESSING.
%   The aggregate procedure is "for x in $MANIFEST; do sha256sum \"$x\"; done |
%   sha256sum", and GNU coreutils writes "<hex>  <path>" in text mode and
%   "<hex> *<path>" in binary mode depending on the build. Both listings are
%   hashed and a match with either is accepted; the report records which one
%   matched, so the freeze record can state it as a fact.
%
%   WHY HASHES AND NOT GIT for the Task 4 sources: all 17 files are UNTRACKED,
%   so git diff says nothing whatsoever about them. The byte hashes are their
%   only provenance. Repository HEAD is recorded as context, never as integrity
%   evidence for them.
%
%   opt fields:
%       repo_root                default: resolved from this file
%       destinations             cellstr; default the three Sec. 11 artifacts
%       expected_aggregate       REQUIRED. The ONE frozen baseline-support
%                                aggregate SHA-256 from Source-Freeze Record B.
%                                It is matched against BOTH independently
%                                computed listing forms and a mismatch ABORTS.
%                                This function never picks a "canonical" form
%                                of its own.
%       require_destinations_absent   default true

    assert(nargin >= 2 && isstruct(opt) && isfield(opt, 'expected_aggregate') ...
           && ~isempty(opt.expected_aggregate), 'baseline_preflight:expected_aggregate', ...
        ['opt.expected_aggregate is REQUIRED. The frozen baseline-support ' ...
         'aggregate is an EXTERNAL identity from Source-Freeze Record B; the ' ...
         'preflight verifies it, it does not choose it.']);
    thisDir = fileparts(mfilename('fullpath'));            % src/baselines/evaluation
    if ~isfield(opt, 'repo_root') || isempty(opt.repo_root)
        opt.repo_root = fileparts(fileparts(fileparts(thisDir)));
        w = what(opt.repo_root);  if ~isempty(w), opt.repo_root = w(1).path; end
    end
    if ~isfield(opt, 'require_destinations_absent')
        opt.require_destinations_absent = true;
    end
    root = opt.repo_root;

    if ~isfield(opt, 'destinations') || isempty(opt.destinations)
        bdir = fullfile(root, 'results', 'task4', 'baselines');
        opt.destinations = { ...
            fullfile(bdir, 'baseline_nominal_mpc_800s.mat'), ...
            fullfile(bdir, 'baseline_apf_800s.mat'), ...
            fullfile(bdir, 'baseline_800s_summary.mat')};
    end

    % ---- 1. the protocol record --------------------------------------------
    protoFile = fullfile(root, p.bl.protocol_file);
    pre.protocol = hash_gate(protoFile, p.bl.protocol_sha256, 'protocol record');

    % ---- 2. the baseline-support aggregate ---------------------------------
    man = baseline_manifest();
    pre.baseline = struct('count', man.count, ...
        'aggregate_sha256',        man.aggregate_sha256, ...
        'aggregate_sha256_binary', man.aggregate_sha256_binary, ...
        'collisions',              {man.collisions});
    assert(isempty(man.collisions), 'baseline_preflight:collision', ...
        ['A baseline source basename collides with an existing project ' ...
         'function and would shadow it through addpath(genpath(src)): %s'], ...
        strjoin(man.collisions, ', '));
    expAgg = lower(char(opt.expected_aggregate));
    if strcmpi(expAgg, man.aggregate_sha256)
        aggForm = 'text (two-space separator)';
    elseif strcmpi(expAgg, man.aggregate_sha256_binary)
        aggForm = 'binary (space-asterisk separator)';
    else
        error('baseline_preflight:baseline_aggregate', ...
            ['ABORT: the baseline-support source hashes to %s (text form) / %s ' ...
             '(binary form), NEITHER of which is the frozen %s from ' ...
             'Source-Freeze Record B.'], man.aggregate_sha256, ...
            man.aggregate_sha256_binary, expAgg);
    end
    pre.baseline.expected_aggregate = expAgg;      % the SUPPLIED frozen value
    pre.baseline.matched_listing_form = aggForm;
    pre.baseline.checked_against_freeze_record = true;

    % ---- 3. the 17-file production aggregate -------------------------------
    pre.production = production_gate(root);

    % ---- 3b. the tracked production WORKTREE -------------------------------
    % The tree-object identity below proves nothing under src/ was COMMITTED.
    % It cannot see an uncommitted edit to a tracked production source, which
    % would change the executing code while leaving HEAD:src identical. This
    % gate closes that gap; both are required and neither replaces the other.
    pre.tracked_src = baseline_tracked_src_gate(root);

    % ---- 4. the tracked src tree -------------------------------------------
    pre.src_tree = src_tree_gate(root);

    % ---- 5. the four frozen final800 artifacts -----------------------------
    f8 = fullfile(root, 'results', 'task4', 'final800');
    final800 = { ...
        'task4_final_800s_alpha1em3.mat', '7a5af1c307a08c42ad0a14778261333121fed0d707eb475ba75d2e36754f32f0', 'HEADLINE REFERENCE'
        'task4_final_800s_alpha1em2.mat', 'a737033e577b361a8dde37a0f96beeb0e64b8c948a130cc2bd706df3dfd55d0b', 'SENSITIVITY ONLY'
        'task4_final_800s_alpha1em4.mat', '567b7a4395a2c142d74fd2663b4a308f9d29677c8b60bdb690c137cab92ecc58', 'SENSITIVITY ONLY'
        'task4_final_800s_summary.mat',   '748409566f549d50d14a43bcec8ca29804ee8430b3db7ebc0282cb31b1809b1f', 'SWEEP SUMMARY'};
    for i = 1:size(final800, 1)
        pre.final800(i) = hash_gate(fullfile(f8, final800{i, 1}), final800{i, 2}, ...
            sprintf('final800 %s [%s]', final800{i, 1}, final800{i, 3}));
    end
    pre.headline_reference = fullfile(f8, final800{1, 1});
    pre.headline_note = ['The proposed method is NOT rerun. Its immutable ' ...
        'pre-result nominal alpha = 1e-3 final-800 artifact is the headline ' ...
        'cross-method reference and is compared against BY HASH. The 1e-2 and ' ...
        '1e-4 artifacts remain SENSITIVITY results and may not be substituted ' ...
        'after baseline results are known.'];

    % ---- 6. the remaining frozen Section-2 identities -----------------------
    % The 800 s protocol, the 800 s harness and the 800 s results record are
    % named in Sec. 2 alongside the artifacts they govern. Verifying the
    % artifacts while leaving the contract and the harness that produced them
    % unchecked would leave the provenance chain open at exactly the point a
    % silent edit would matter most.
    sec2 = { ...
        fullfile(root, 'notes', 'task4_final_800s_protocol.md'), ...
            '036670b0d7a4a0aee7248c41e5feaf86d4a6a44486c87c4abe2620633d651b0a', ...
            'frozen 800 s protocol'
        fullfile(root, 'src', 'sim', 'task4_final_800s.m'), ...
            '0b8afa512f3a372c8a5982c550b8c2441cecf467ede45e01230c2fea6c64f70c', ...
            'frozen 800 s harness'
        fullfile(root, 'notes', 'task4_final_800s_results_record.md'), ...
            '9bf4207bd8dac51f00d41b2015c17701f415878c45d5a8be6aad70386a171592', ...
            'frozen 800 s results record'};
    for i = 1:size(sec2, 1)
        pre.section2(i) = hash_gate(sec2{i, 1}, sec2{i, 2}, sec2{i, 3});
    end

    % ---- 7. the protected 400 s reference ----------------------------------
    ref400 = fullfile(root, 'results', 'task4', 'task4_first_diagnostic_400s_alpha1e3.mat');
    pre.ref400 = hash_gate(ref400, ...
        'b6d1efd802833582053dc8f0f7ba7b41358b0229326d5e2b96cd7e8ab9f66289', ...
        'protected 400 s reference');
    d = dir(ref400);
    assert(~isempty(d) && d(1).bytes == 4462193, 'baseline_preflight:ref400_size', ...
        'ABORT: the protected 400 s reference is %d bytes, not the frozen 4462193.', ...
        tern_num(isempty(d), -1, d(1).bytes));
    pre.ref400.bytes = d(1).bytes;

    % ---- 8. destinations must be ABSENT ------------------------------------
    pre.destinations = opt.destinations;
    if opt.require_destinations_absent
        for i = 1:numel(opt.destinations)
            assert(exist(opt.destinations{i}, 'file') ~= 2, ...
                'baseline_preflight:destination_exists', ...
                ['ABORT: destination already exists:\n    %s\nThe evaluation ' ...
                 'never overwrites, never appends to a foreign file and never ' ...
                 'retries.'], opt.destinations{i});
        end
    end

    pre.repo_root = root;
    pre.git_head  = git_head_now(root);
    pre.head_caveat = ['Repository HEAD does not establish the integrity of ' ...
        'the Task 4 or baseline sources: both sets are UNTRACKED. Byte hashes ' ...
        'are the only provenance that covers them.'];
    pre.stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');       %#ok<TNOW1,DATST>
    pre.pass  = true;
end

% =====================================================================
function g = hash_gate(file, expected, label)
    assert(exist(file, 'file') == 2, 'baseline_preflight:missing', ...
        'ABORT: %s is missing:\n    %s', label, file);
    actual = baseline_sha256(file);
    assert(strcmpi(actual, expected), 'baseline_preflight:hash', ...
        ['ABORT: %s hashes to\n    %s\nbut the frozen identity is\n    %s\n' ...
         'file: %s\nThis is a provenance failure. Do not repair, normalise or ' ...
         'continue.'], label, actual, expected, file);
    g = struct('label', label, 'file', file, 'sha256', actual, 'pass', true);
end

% =====================================================================
function pr = production_gate(root)
% Parse the 17-file manifest out of notes/task4_alpha_sweep_protocol.md Sec. 2.2
% and check both the per-file hashes and the aggregate.
    src = fullfile(root, 'notes', 'task4_alpha_sweep_protocol.md');
    assert(exist(src, 'file') == 2, 'baseline_preflight:manifest_missing', ...
        'ABORT: the 17-file production manifest source is missing:\n    %s', src);

    txt  = fileread(src);
    rows = regexp(txt, '\|\s*`(src/[^`]+\.m)`\s*\|[^|]*\|\s*`([0-9a-fA-F]{64})`\s*\|', ...
                  'tokens');
    assert(numel(rows) == 17, 'baseline_preflight:manifest_rows', ...
        ['ABORT: the production manifest table in %s parsed to %d rows, not ' ...
         'the frozen 17.'], src, numel(rows));

    rel = cell(17, 1);  expSha = cell(17, 1);
    for i = 1:17
        rel{i}    = rows{i}{1};
        expSha{i} = lower(rows{i}{2});
    end
    [rel, ord] = sort_bytewise(rel);
    expSha = expSha(ord);

    actSha = cell(17, 1);
    partsT = cell(17, 1);
    partsB = cell(17, 1);
    for i = 1:17
        f = fullfile(root, strrep(rel{i}, '/', filesep));
        assert(exist(f, 'file') == 2, 'baseline_preflight:production_missing', ...
            'ABORT: frozen production source is missing:\n    %s', f);
        actSha{i} = baseline_sha256(f);
        assert(strcmpi(actSha{i}, expSha{i}), 'baseline_preflight:production_file', ...
            'ABORT: %s hashes to\n    %s\nbut the frozen manifest records\n    %s', ...
            rel{i}, actSha{i}, expSha{i});
        partsT{i} = sprintf('%s  %s\n', actSha{i}, rel{i});
        partsB{i} = sprintf('%s *%s\n', actSha{i}, rel{i});
    end

    aggT = baseline_sha256(uint8([partsT{:}]), false);
    aggB = baseline_sha256(uint8([partsB{:}]), false);
    frozen = 'bd3ea14043ef7f0d14e6fed375e5e5ae7624dd88f21ba5753c8d05c36906a241';
    if strcmpi(aggT, frozen)
        form = 'text (two-space separator)';
    elseif strcmpi(aggB, frozen)
        form = 'binary (space-asterisk separator)';
    else
        error('baseline_preflight:production_aggregate', ...
            ['ABORT: the 17-file production aggregate is\n    %s  (text form)\n' ...
             '    %s  (binary form)\nneither of which is the frozen\n    %s'], ...
            aggT, aggB, frozen);
    end

    pr = struct('count', 17, 'rel', {rel}, 'sha256', {actSha}, ...
        'aggregate_sha256', frozen, 'listing_form', form, 'source', src, ...
        'pass', true, ...
        'note', ['All 17 files are UNTRACKED, so git says nothing about them; ' ...
                 'these byte hashes are their only provenance. The two sweep ' ...
                 'harnesses are excluded from this set by the frozen ' ...
                 'definition and are hashed separately.']);
end

% =====================================================================
function g = src_tree_gate(root)
% The frozen preflight identity of protocol Sec. 15.3:
%     git rev-parse HEAD:src == fb4ff84:src == d641966176b36cf909b77120a78f460a8c0e5557
% Committing anything under src/ changes this tree object and destroys the
% identity the entire Task 4 provenance chain is checked against - which is
% exactly why the baseline sources must stay UNTRACKED.
    expected = 'd641966176b36cf909b77120a78f460a8c0e5557';
    [st, out] = system(sprintf('git -C "%s" rev-parse HEAD:src', root));
    assert(st == 0, 'baseline_preflight:git', ...
        'ABORT: could not read the tracked src tree object (git exit %d).', st);
    actual = strtrim(out);
    assert(strcmpi(actual, expected), 'baseline_preflight:src_tree', ...
        ['ABORT: HEAD:src is\n    %s\nbut the frozen tree object is\n    %s\n' ...
         'Something under src/ has been COMMITTED. The baseline sources must ' ...
         'remain untracked until after the evaluation is frozen.'], actual, expected);
    g = struct('expected', expected, 'actual', actual, 'pass', true);
end

% =====================================================================
function [s, ord] = sort_bytewise(c)
% LC_ALL=C ordering of relative paths, matching BASELINE_MANIFEST.
    n = numel(c);
    L = zeros(n, 1);  B = cell(n, 1);
    for i = 1:n
        B{i} = uint8(unicode2native(c{i}, 'UTF-8'));
        L(i) = numel(B{i});
    end
    M = zeros(n, max(L));
    for i = 1:n, M(i, 1:L(i)) = double(B{i}); end
    [~, ord] = sortrows(M);
    s = c(ord);
end

% =====================================================================
function h = git_head_now(root)
    h = 'UNAVAILABLE';
    try
        [st, o] = system(sprintf('git -C "%s" rev-parse HEAD', root));
        if st == 0
            o = strtrim(o);
            if ~isempty(regexp(o, '^[0-9a-f]{40}$', 'once')), h = o; end
        end
    catch
        % A missing git is a provenance gap to record, not a reason to stop.
    end
end

% =====================================================================
function v = tern_num(c, a, b)
    if c, v = a; else, v = b; end
end

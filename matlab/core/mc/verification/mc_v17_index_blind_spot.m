function R = mc_v17_index_blind_spot(tmpRoot)
% MC_V17_INDEX_BLIND_SPOT  Per-file Git proof is not blind to the index (F7, R-E). NON-SCIENTIFIC.
%   In a TEMPORARY repository under tempdir (the project index is never touched):
%   a committed file is clean; then modified content is STAGED and the working
%   tree is restored to the committed bytes. A single 'git diff --quiet HEAD'
%   now reports clean - the blind spot - while MC_GIT_FILE_STATE (used by every
%   protected-file check of MC_PREFLIGHT) reports INDEX ~= HEAD and not clean.
%   Also: an unstaged modification (worktree ~= index) is detected.
%   R-E: the same staged-modification case is demonstrated for a NOTES AUTHORITY
%   RECORD at its own repository path, through the SAME predicate MC_PREFLIGHT
%   check 7 now applies to those records - s.matches, which requires the
%   worktree, the index AND the committed blob to hash to the frozen SHA-256.
%   The frozen-bytes-only test that check 7 used before would have passed.

    R.name = 'V17 preflight index blind spot (isolated repository)';
    ch = {};
    repo = fullfile(tmpRoot, 'v17_repo');
    mkdir(repo);
    mc_vt_git(repo, 'init -q');
    rel = 'notes/protected.md';
    A = sprintf('frozen content\n');
    mc_vt_write_text(repo, rel, A);
    mc_vt_git(repo, ['add -- ' rel]);
    [~, e] = mc_vt_git(repo, 'commit -q -m fixture');
    ch{end+1} = mc_vt_check('fixture repository committed', e == 0);
    s0 = mc_git_file_state(repo, rel);
    ch{end+1} = mc_vt_check('a committed, untouched file is clean', s0.clean, sprintf('%d', s0.clean));

    mc_vt_write_text(repo, rel, sprintf('MODIFIED content\n'));
    mc_vt_git(repo, ['add -- ' rel]);                    % stage the modification
    mc_vt_write_text(repo, rel, A);                      % restore the worktree to HEAD bytes
    [~, eOld] = mc_vt_git(repo, ['diff --quiet HEAD -- ' rel]);
    ch{end+1} = mc_vt_check('the blind spot exists: git diff --quiet HEAD reports clean', eOld == 0, ...
        sprintf('exit %d', eOld));
    s1 = mc_git_file_state(repo, rel);
    ch{end+1} = mc_vt_check('MC_GIT_FILE_STATE: INDEX ~= HEAD detected, file NOT clean', ...
        ~s1.index_eq_head && ~s1.clean && ~strcmp(s1.index_blob, s1.head_blob) ...
        && strcmp(s1.worktree_sha256, s1.head_sha256), ...
        sprintf('index==HEAD %d, clean %d', s1.index_eq_head, s1.clean));

    mc_vt_git(repo, ['reset -q -- ' rel]);              % index back to HEAD (fixture repo only)
    mc_vt_write_text(repo, rel, sprintf('unstaged edit\n'));
    s2 = mc_git_file_state(repo, rel);
    ch{end+1} = mc_vt_check('an unstaged modification: WORKTREE ~= INDEX detected, NOT clean', ...
        ~s2.wt_eq_index && s2.index_eq_head && ~s2.clean);

    % ---- R-E: a NOTES AUTHORITY RECORD, through the predicate check 7 now uses --------
    nrel = 'notes/task4_git_checkpoint_postcommit_record.md';
    B = sprintf('# fixture authority record\nfrozen bytes\n');
    mc_vt_write_text(repo, nrel, B);
    mc_vt_git(repo, ['add -- ' nrel]);
    mc_vt_git(repo, 'commit -q -m record');
    want = baseline_sha256(fullfile(repo, strrep(nrel, '/', filesep)));
    n0 = mc_git_file_state(repo, nrel, want);
    ch{end+1} = mc_vt_check('an authority record at its frozen identity: matches (worktree == index == HEAD)', ...
        n0.matches && n0.clean, want);
    mc_vt_write_text(repo, nrel, sprintf('# fixture authority record\nSTAGED CHANGE\n'));
    mc_vt_git(repo, ['add -- ' nrel]);
    mc_vt_write_text(repo, nrel, B);                     % worktree restored to the frozen bytes
    n1 = mc_git_file_state(repo, nrel, want);
    ch{end+1} = mc_vt_check(['R-E a staged change with a restored worktree: the frozen-bytes-only test ' ...
        'passes, the per-file predicate does NOT'], ...
        strcmp(n1.worktree_sha256, want) && ~n1.index_eq_head && ~n1.matches, ...
        sprintf('worktree==frozen %d, index==HEAD %d, matches %d', ...
        strcmp(n1.worktree_sha256, want), n1.index_eq_head, n1.matches));
    R.checks = [ch{:}];
end

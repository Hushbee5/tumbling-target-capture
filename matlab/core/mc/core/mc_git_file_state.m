function s = mc_git_file_state(root, rel, wantSha)
% MC_GIT_FILE_STATE  Complete Git cleanliness proof for ONE tracked file.
%   s = mc_git_file_state(root, rel)
%   s = mc_git_file_state(root, rel, wantSha)   also s.matches: clean AND the
%                  worktree, index and HEAD bytes all hash to wantSha - the
%                  per-file identity check MC_PREFLIGHT applies to every tracked
%                  authority record (checks 5, 6, 7)
%   establishes SEPARATELY (protocol Sec. 11 check 3, "tracked and clean
%   against HEAD"):
%
%     tracked        the path is in the index (ls-files)
%     stage0         exactly one index entry, at stage 0 (no conflict)
%     wt_eq_index    WORKTREE == INDEX    git diff --quiet -- <rel>
%     index_eq_head  INDEX == HEAD        git diff --cached --quiet HEAD -- <rel>
%     head_blob, index_blob   the two blob ids, required equal
%     worktree_sha256, index_sha256, head_sha256   SHA-256 of the raw bytes of
%                    the working-tree file, the index blob and the HEAD blob
%     clean          all of the above hold and the three byte hashes agree
%
%   A single 'git diff --quiet HEAD -- <rel>' compares the working tree with
%   HEAD only; it is BLIND to a staged change whose working-tree copy was
%   restored to HEAD. That is why both comparisons are made here.
%   root may be any repository (the verification suite uses temporary ones).

    if nargin < 3, wantSha = ''; end
    s = struct('path', rel, 'tracked', false, 'stage0', false, 'wt_eq_index', false, ...
               'index_eq_head', false, 'head_blob', '', 'index_blob', '', ...
               'worktree_sha256', '', 'index_sha256', '', 'head_sha256', '', 'clean', false, ...
               'matches', false);

    [ls, e] = mc_git(root, sprintf('ls-files -s -- "%s"', rel), true);
    L = regexp(strtrim(ls), '\r?\n', 'split');
    L = L(~cellfun(@isempty, L));
    s.tracked = (e == 0) && ~isempty(L);
    if s.tracked && numel(L) == 1
        tok = regexp(L{1}, '^(\d+) ([0-9a-f]{40}) (\d)\t(.+)$', 'tokens', 'once');
        if ~isempty(tok)
            s.stage0 = strcmp(tok{3}, '0') && strcmp(tok{4}, rel);
            s.index_blob = tok{2};
        end
    end
    [~, e1] = mc_git(root, sprintf('diff --quiet -- "%s"', rel), true);
    [~, e2] = mc_git(root, sprintf('diff --cached --quiet HEAD -- "%s"', rel), true);
    s.wt_eq_index   = (e1 == 0);
    s.index_eq_head = (e2 == 0);
    [hb, e3] = mc_git(root, sprintf('rev-parse "HEAD:%s"', rel), true);
    if e3 == 0 && numel(hb) == 40 && all(ismember(hb, '0123456789abcdef'))
        s.head_blob = hb;
    end

    f = fullfile(root, strrep(rel, '/', filesep));
    if isfile(f)
        s.worktree_sha256 = baseline_sha256(f);
    end
    if s.tracked
        s.index_sha256 = blob_sha256(root, [':' rel]);
    end
    if ~isempty(s.head_blob)
        s.head_sha256 = blob_sha256(root, ['HEAD:' rel]);
    end
    s.clean = s.tracked && s.stage0 && s.wt_eq_index && s.index_eq_head ...
        && ~isempty(s.head_blob) && strcmp(s.index_blob, s.head_blob) ...
        && ~isempty(s.head_sha256) && strcmp(s.worktree_sha256, s.head_sha256) ...
        && strcmp(s.index_sha256, s.head_sha256);
    s.matches = s.clean && ~isempty(wantSha) && strcmp(s.worktree_sha256, wantSha) ...
        && strcmp(s.index_sha256, wantSha) && strcmp(s.head_sha256, wantSha);
end

% =====================================================================
function h = blob_sha256(root, spec)
% SHA-256 of the raw bytes of a blob, written by git itself to a temporary
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
function delete_if_exists(f)
    if isfile(f)
        delete(f);
    end
end

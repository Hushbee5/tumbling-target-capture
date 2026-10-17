function g = baseline_tracked_src_gate(repoRoot)
% BASELINE_TRACKED_SRC_GATE  Tracked production worktree must match frozen HEAD.
%   g = baseline_tracked_src_gate(repoRoot) verifies that no TRACKED file under
%   src/ differs from HEAD, in the working tree OR in the index. It ABORTS on
%   any difference and on any failure of the check itself.
%
%   WHY THIS EXISTS, BESIDE THE HEAD:src TREE GATE.
%   BASELINE_PREFLIGHT already asserts
%       git rev-parse HEAD:src == d641966176b36cf909b77120a78f460a8c0e5557
%   but that identifies the COMMITTED tree object only. An uncommitted edit to a
%   tracked production source - say src/dynamics/rel_translational_dynamics.m -
%   leaves HEAD:src completely unchanged while changing the code that actually
%   executes. The two checks are complementary and BOTH are required: the tree
%   object proves nothing was committed, this proves nothing was edited.
%
%   TWO INDEPENDENT LAYER TESTS, NOT ONE NET-DIFFERENCE TEST.
%       unstaged   git -C <repo> diff --quiet -- src              (worktree vs index)
%       staged     git -C <repo> diff --cached --quiet HEAD -- src (index vs HEAD)
%   PASS requires BOTH to exit exactly 0.
%
%   A SINGLE `git diff --quiet HEAD -- src` IS NOT SUFFICIENT, and this is not a
%   theoretical objection. That command reports the NET difference between the
%   working tree and HEAD, so a staged change whose working-tree content has been
%   restored to the HEAD content is invisible to it:
%       HEAD content = A ; stage content B ; restore the working tree to A
%       git status --short          ->  MM src/a.txt
%       git diff --quiet HEAD -- src ->  exit 0        (WRONG: index differs)
%   The index still differs from HEAD, so the repository state is NOT clean, yet
%   the net test passes. Splitting the question into the two layers removes that
%   blind spot: the worktree-vs-index test catches the restore, and the
%   index-vs-HEAD test catches the staged content, and either one alone is
%   enough to fail the gate.
%
%   UNTRACKED FILES ARE CORRECTLY IGNORED. Both commands report only TRACKED
%   paths, so the deliberately UNTRACKED src/baselines/** files - and the 17
%   untracked Task-4 production files - do not trip the gate. git status is
%   deliberately NOT used as the scientific gate: it reports untracked paths, and
%   untracked baseline source is the required state throughout protocol
%   Sec. 15.3.
%
%   EXIT-CODE CONTRACT, applied to EACH command (git diff --quiet):
%       0   that layer is clean
%       1   tracked src differs                    -> ABORT
%      >1   the check itself failed (no git, not a -> ABORT
%           repository, bad object, ...)              a silent pass is never
%                                                     allowed to stand in for a
%                                                     check that did not run
%
%   Invoked before every scientific stage: by BASELINE_VERIFY ahead of V1-V11, by
%   BASELINE_TUNING ahead of the development search, and by BASELINE_PREFLIGHT
%   ahead of the deterministic evaluation. Each records the returned struct, so
%   the provenance chain states that tracked production source matched frozen
%   HEAD at that stage.
%
%   g fields: pass, unstaged, staged (each with command/exit_code/pass),
%   changed_files, repo_root, stamp, note

    assert(nargin >= 1 && ~isempty(repoRoot), 'baseline_tracked_src_gate:repo', ...
        'A repository root is required.');

    cmdUnstaged = sprintf('git -C "%s" diff --quiet -- src', repoRoot);
    cmdStaged   = sprintf('git -C "%s" diff --cached --quiet HEAD -- src', repoRoot);

    [codeU, outU] = system(cmdUnstaged);
    [codeS, outS] = system(cmdStaged);
    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');          %#ok<TNOW1,DATST>

    g = struct( ...
        'pass',          false, ...
        'unstaged',      struct('command', cmdUnstaged, 'exit_code', codeU, ...
                                'pass', codeU == 0, ...
                                'compares', 'working tree vs index'), ...
        'staged',        struct('command', cmdStaged, 'exit_code', codeS, ...
                                'pass', codeS == 0, ...
                                'compares', 'index vs HEAD'), ...
        'changed_files', {{}}, ...
        'repo_root',     repoRoot, ...
        'stamp',         stamp, ...
        'note', ['Tracked production worktree gate. Complements, and does not ' ...
                 'replace, the frozen HEAD:src tree-object identity: that one ' ...
                 'proves nothing under src/ was COMMITTED, this one proves ' ...
                 'nothing tracked under src/ was EDITED. The two layers are ' ...
                 'tested INDEPENDENTLY, because a single net "git diff HEAD" ' ...
                 'misses a staged change whose working-tree content was ' ...
                 'restored to the HEAD content. Untracked files, including all ' ...
                 'of src/baselines/**, are correctly ignored by both commands.']);

    % ---- a check that could not run establishes nothing ---------------------
    if codeU > 1 || codeS > 1
        error('baseline_tracked_src_gate:failed', ...
            ['ABORT: the tracked-src integrity check itself failed and ' ...
             'therefore established nothing.\n' ...
             '  unstaged: exit %d  |  %s\n    %s\n' ...
             '  staged  : exit %d  |  %s\n    %s\n' ...
             'A check that did not run must never be recorded as a pass.'], ...
            codeU, cmdUnstaged, strtrim(outU), codeS, cmdStaged, strtrim(outS));
    end

    if codeU == 0 && codeS == 0
        g.pass = true;
        return
    end

    % ---- dirty: report the UNION of both layers' tracked paths -------------
    lst = [name_only(repoRoot, 'diff --name-only -- src'), ...
           name_only(repoRoot, 'diff --cached --name-only HEAD -- src')];
    lst = unique(lst);
    if isempty(lst)
        lst = {'(could not list the differing paths)'};
    end
    % lst is NOT stored back into g: this path always raises, so g is never
    % returned here and the assignment would be dead. changed_files stays empty
    % on the PASS path, where there is by definition nothing to list.

    error('baseline_tracked_src_gate:dirty', ...
        ['ABORT: the TRACKED production worktree under src/ differs from ' ...
         'frozen HEAD.\n' ...
         '  unstaged (working tree vs index): exit %d\n' ...
         '  staged   (index vs HEAD)        : exit %d\n' ...
         'Differing tracked path(s), union of both layers:\n    %s\n' ...
         'A scientific stage may not run against edited production source. The ' ...
         'HEAD:src tree object alone would NOT have caught this, because an ' ...
         'uncommitted edit leaves it unchanged. Restore the tracked files, or ' ...
         'establish a new frozen identity deliberately.'], ...
        codeU, codeS, strjoin(lst, sprintf('\n    ')));
end

% =====================================================================
function lst = name_only(repoRoot, args)
% One --name-only listing, as a cellstr. A failure here only costs detail in the
% abort message, never the abort itself, so it is reported as empty rather than
% raised over the top of the real finding.
    lst = {};
    [code, out] = system(sprintf('git -C "%s" %s', repoRoot, args));
    if code ~= 0
        return
    end
    out = strtrim(out);
    if isempty(out)
        return
    end
    lst = strtrim(regexp(out, '\r?\n', 'split'));
    lst = lst(~cellfun(@isempty, lst));
end

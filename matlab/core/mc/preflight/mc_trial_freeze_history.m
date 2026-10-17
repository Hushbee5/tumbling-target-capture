function h = mc_trial_freeze_history(root, csvRel, frRel, implCommit)
% MC_TRIAL_FREEZE_HISTORY  Git-history proof of the trial-table freeze (Sec. 10 steps 5-10).
%   h = mc_trial_freeze_history(root, csvRel, frRel, implCommit) proves from
%   committed history, never from a statement:
%
%     1  the canonical CSV and the freeze record were each touched by EXACTLY
%        ONE commit T (added once, never modified, deleted or re-added), the
%        SAME commit for both - they were committed together (step 9);
%     2  T adds both paths and has exactly one parent P, which contains neither;
%     3  the MC implementation commit is an ancestor of P, i.e. it strictly
%        precedes the trial-table freeze commit (step 5 before step 6);
%     4  T is an ancestor of HEAD.
%
%   The freeze record never names T (it cannot contain its own commit); T is
%   identified here, afterwards. h.trial_commit_time (Unix seconds, committer
%   date of T) lets the execution preflight prove that no scientific
%   checkpoint artefact predates the freeze (step 10). root may be any
%   repository (the verification suite uses temporary ones).
%
%   h fields: pass, reasons (cellstr), trial_commit, parent, trial_commit_time.

    h = struct('pass', false, 'reasons', {{}}, 'trial_commit', '', 'parent', '', ...
               'trial_commit_time', NaN);
    csvC = lines_of(mc_git(root, sprintf('log --format=%%H --full-history -- "%s"', csvRel), true));
    frC  = lines_of(mc_git(root, sprintf('log --format=%%H --full-history -- "%s"', frRel), true));
    if numel(csvC) ~= 1
        h.reasons{end+1} = sprintf('the CSV was touched by %d commits, not exactly one', numel(csvC));
    end
    if numel(frC) ~= 1
        h.reasons{end+1} = sprintf('the freeze record was touched by %d commits, not exactly one', numel(frC));
    end
    if ~(numel(csvC) == 1 && numel(frC) == 1)
        return
    end
    if ~strcmp(csvC{1}, frC{1})
        h.reasons{end+1} = 'the CSV and the freeze record were not committed together';
        return
    end
    T = csvC{1};
    h.trial_commit = T;

    st = lines_of(mc_git(root, sprintf('diff-tree --no-commit-id --root -r --name-status %s', T), true));
    if ~(any(strcmp(st, sprintf('A\t%s', csvRel))) && any(strcmp(st, sprintf('A\t%s', frRel))))
        h.reasons{end+1} = 'the freeze commit does not ADD both the CSV and the freeze record';
    end
    par = strsplit(strtrim(mc_git(root, sprintf('rev-list --parents -n 1 %s', T), true)));
    if numel(par) ~= 2
        h.reasons{end+1} = sprintf('the freeze commit has %d parent(s), not exactly one', numel(par) - 1);
        return
    end
    P = par{2};
    h.parent = P;
    [~, e1] = mc_git(root, sprintf('cat-file -e "%s:%s"', P, csvRel), true);
    [~, e2] = mc_git(root, sprintf('cat-file -e "%s:%s"', P, frRel), true);
    if e1 == 0 || e2 == 0
        h.reasons{end+1} = 'the parent of the freeze commit already contains the CSV or the freeze record';
    end
    [~, e3] = mc_git(root, sprintf('merge-base --is-ancestor %s %s', implCommit, P), true);
    if e3 ~= 0
        h.reasons{end+1} = 'the MC implementation commit does not strictly precede the freeze commit';
    end
    [~, e4] = mc_git(root, sprintf('merge-base --is-ancestor %s HEAD', T), true);
    if e4 ~= 0
        h.reasons{end+1} = 'the freeze commit is not an ancestor of HEAD';
    end
    h.trial_commit_time = str2double(mc_git(root, sprintf('show -s --format=%%ct %s', T), true));
    h.pass = isempty(h.reasons);
end

% =====================================================================
function L = lines_of(s)
    L = regexp(strtrim(s), '\r?\n', 'split');
    L = L(~cellfun(@isempty, L));
end

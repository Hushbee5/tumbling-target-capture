function [out, code] = mc_git(root, args, allowFail)
% MC_GIT  Run one git command against the repository; return trimmed output.
%   out         = mc_git(root, args)          errors on a non-zero exit code
%   [out, code] = mc_git(root, args, true)    returns the exit code instead
%
%   Same invocation form as the frozen baseline gates
%   (baseline_tracked_src_gate.m:134): git -C "<root>" <args>. The command is
%   read-only in every use inside src/mc; nothing here stages, commits or
%   rewrites anything.

    if nargin < 3, allowFail = false; end
    [code, out] = system(sprintf('git -C "%s" %s', root, args));
    out = strtrim(out);
    if ~allowFail
        assert(code == 0, 'mc:git', 'git %s failed (exit %d): %s', args, code, out);
    end
end

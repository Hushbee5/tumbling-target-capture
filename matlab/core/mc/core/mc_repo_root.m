function root = mc_repo_root()
% MC_REPO_ROOT  Repository root, derived from this file's own location.
%   root = mc_repo_root() returns the canonical absolute path of the repository
%   that contains src/mc. Nothing is read from the environment or the current
%   folder, so a harness started from another directory still binds to the
%   repository whose MC source it is executing.

    here = fileparts(mfilename('fullpath'));            % <root>/src/mc/core
    root = fileparts(fileparts(fileparts(here)));
    root = mc_abs_path(root);
    assert(exist(fullfile(root, 'src', 'mc', 'core', 'mc_repo_root.m'), 'file') == 2, ...
        'mc:root', 'Could not resolve the repository root from %s.', here);
end

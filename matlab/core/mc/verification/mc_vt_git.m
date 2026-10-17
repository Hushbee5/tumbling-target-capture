function [out, code] = mc_vt_git(root, args)
% MC_VT_GIT  git in a TEMPORARY fixture repository, with a fixed fixture identity.
%   [out, code] = mc_vt_git(root, args) runs
%     git -C "<root>" -c user.name=mc-fixture -c user.email=mc-fixture@example.invalid
%         -c core.autocrlf=false -c commit.gpgsign=false <args>
%   It never touches the project repository: the verification suite only calls
%   it on folders created under tempdir, and it refuses a root inside the project.

    proj = mc_repo_root();
    r = mc_abs_path(root);
    assert(~strncmpi(r, [proj filesep], numel(proj) + 1) && ~strcmpi(r, proj), 'mc:vt:git_root', ...
        'Fixture git commands never run inside the project repository.');
    [out, code] = mc_git(r, ['-c user.name=mc-fixture -c user.email=mc-fixture@example.invalid ' ...
                             '-c core.autocrlf=false -c commit.gpgsign=false ' args], true);
end

function fx = baseline_shadow_fixture(names)
% BASELINE_SHADOW_FIXTURE  Install the V9b/V10b path-shadowing stubs.
%   fx = baseline_shadow_fixture(names) materialises one stub per name from the
%   stored +shadow_stubs package into a FRESH TEMPORARY PLAIN DIRECTORY, puts
%   that directory at the FRONT of the MATLAB path, and asserts through which()
%   that every forbidden name now resolves to it.
%
%   THE RETURNED OBJECT OWNS THE CLEANUP. fx.cleanup is an onCleanup that
%   restores the original MATLAB path UNCONDITIONALLY and deletes the temporary
%   directory. Keep fx alive for exactly as long as the shadowed run, and clear
%   it (or let it go out of scope) immediately afterwards. The stubs are
%   installed ONLY for V9b/V10b and NEVER for any scientific run.
%
%   PRECEDENCE ASSERTION BEFORE THE TEST RUN. If any forbidden function does not
%   resolve to the intended stub path, this function ERRORS. The runtime
%   exclusion proof then FAILS WITHOUT EXECUTING THE TEST RUN, which is exactly
%   what the protocol requires: a run that completes while the stubs were not
%   actually in front would prove nothing at all.
%
%   WHY A PLAIN TEMPORARY DIRECTORY AND NOT THE STORED FOLDER.
%   The stubs are stored in a '+' package folder because genpath refuses to
%   descend into one. That matters: every validator and Task 4 harness here
%   calls addpath(genpath(<src>)), which would otherwise put a plain stub
%   directory ahead of src/control and the toolboxes during ordinary project
%   work and shadow quadprog, mpc_step, mpc_condensed and
%   capture_reference_preview globally. A '+' folder is invisible to genpath but
%   its contents are ALSO not ordinary functions, so they cannot shadow anything
%   from where they are stored. Copying them into a plain temporary directory
%   gives the protocol exactly what it asks for - "a verification-only PLAIN
%   directory (NOT a +package, so it genuinely shadows)" - while leaving the
%   repository safe between tests.
%
%   THE COPIES ARE VERIFIED BYTE-IDENTICAL to the stored originals by SHA-256,
%   so the file that actually shadows is provably the file the manifest covers.
%
%   fx fields: dir, names, sources, sha256, resolved, cleanup, note

    assert(iscellstr(names) && ~isempty(names), 'baseline_shadow_fixture:names', ...
        'names must be a non-empty cell array of function names.'); %#ok<ISCLSTR>

    thisDir = fileparts(mfilename('fullpath'));
    stubDir = fullfile(thisDir, '+shadow_stubs');
    assert(exist(stubDir, 'dir') == 7, 'baseline_shadow_fixture:stubdir', ...
        'The stored stub package is missing: %s', stubDir);

    tmpDir = [tempname '_shadow'];
    mkOk = mkdir(tmpDir);
    assert(mkOk, 'baseline_shadow_fixture:tmpdir', ...
        'Could not create the temporary shadow directory %s', tmpDir);

    % Path restoration is armed BEFORE anything is added to the path, so an
    % error anywhere below still restores and still deletes the directory.
    savedPath = path();
    fx.cleanup = onCleanup(@() restore_env(savedPath, tmpDir));

    sources = cell(1, numel(names));
    shas    = cell(1, numel(names));
    for i = 1:numel(names)
        src = fullfile(stubDir, [names{i} '.m']);
        assert(exist(src, 'file') == 2, 'baseline_shadow_fixture:missing_stub', ...
            ['No stored stub for the forbidden function ''%s''. Every name in ' ...
             'the exclusion list must have one, or the proof has a hole.'], names{i});
        dst = fullfile(tmpDir, [names{i} '.m']);
        [ok, msg] = copyfile(src, dst);
        assert(ok, 'baseline_shadow_fixture:copy', ...
            'Could not materialise the stub for %s: %s', names{i}, msg);

        a = baseline_sha256(src);
        b = baseline_sha256(dst);
        assert(strcmpi(a, b), 'baseline_shadow_fixture:copy_integrity', ...
            ['The materialised stub for %s is not byte-identical to the stored ' ...
             'original (%s vs %s).'], names{i}, a, b);
        sources{i} = src;
        shas{i}    = a;
    end

    addpath(tmpDir, '-begin');
    rehash path

    % ---- PRECEDENCE ASSERTION ----------------------------------------------
    resolved = cell(1, numel(names));
    for i = 1:numel(names)
        expected = fullfile(tmpDir, [names{i} '.m']);
        actual   = which(names{i});
        resolved{i} = actual;
        assert(samefile(actual, expected), 'baseline_shadow_fixture:precedence', ...
            ['PRECEDENCE ASSERTION FAILED for ''%s'': which() resolves to\n' ...
             '    %s\nbut the verification stub is\n    %s\n' ...
             'The runtime exclusion proof FAILS WITHOUT EXECUTING THE TEST RUN.'], ...
            names{i}, actual, expected);
    end

    fx.dir      = tmpDir;
    fx.names    = names;
    fx.sources  = sources;
    fx.sha256   = shas;
    fx.resolved = resolved;
    fx.note = ['Stubs installed for a V9b/V10b runtime exclusion proof only. ' ...
        'The MATLAB path is restored unconditionally and this directory is ' ...
        'deleted when the returned object is cleared.'];
end

% =====================================================================
function restore_env(savedPath, tmpDir)
    try
        path(savedPath);
        rehash path
    catch
        % Restoring the path must never be skipped, but a failure here must also
        % never mask the original error; it is reported and execution continues.
        warning('baseline_shadow_fixture:restore', ...
            'Could not restore the saved MATLAB path.');
    end
    if exist(tmpDir, 'dir') == 7
        try
            rmdir(tmpDir, 's');
        catch
            warning('baseline_shadow_fixture:cleanup', ...
                'Could not delete the temporary shadow directory %s', tmpDir);
        end
    end
end

% =====================================================================
function tf = samefile(a, b)
% Path comparison that tolerates separator and case differences on Windows but
% nothing else. An empty which() result is never a match.
    if isempty(a) || isempty(b)
        tf = false;
        return
    end
    na = strrep(strrep(a, '\', '/'), '//', '/');
    nb = strrep(strrep(b, '\', '/'), '//', '/');
    tf = strcmpi(na, nb);
end

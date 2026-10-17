function man = baseline_manifest(rootDir)
% BASELINE_MANIFEST  Recursive provenance manifest of the baseline-support source.
%   man = baseline_manifest()        resolves src/baselines from this file
%   man = baseline_manifest(rootDir) uses an explicit root
%
%   Implements the PROCEDURE frozen in protocol Sec. 15.1 - and only the
%   procedure. This function contains NO expected manifest, NO expected file
%   count and NO expected aggregate: those belong to the separate source-freeze
%   record (protocol Sec. 15.2 object B), never to the code and never to the
%   protocol record itself.
%
%       MANIFEST   deterministic, recursive, LC_ALL=C-sorted RELATIVE paths of
%                  EVERY .m file under src/baselines/**, including verification
%                  fixtures and the +shadow_stubs package
%       AGGREGATE  for x in $MANIFEST; do sha256sum "$x"; done | sha256sum
%
%   LC_ALL=C SORTING IS IMPLEMENTED AS BYTE ORDER, NOT AS MATLAB sort().
%   The cellstr sort is not documented as byte-wise, so the paths are converted
%   to UTF-8 bytes, zero-padded to equal length and ordered with SORTROWS. That
%   is exactly what LC_ALL=C gives, and it depends on no locale, release or
%   platform.
%
%   PATH SPELLING. Relative paths are emitted with FORWARD slashes and are
%   rooted at the repository, e.g. 'src/baselines/apf/controller_apf.m', so the
%   MATLAB-side aggregate reproduces what the shell command above produces on
%   the same tree. Windows backslashes never enter the hashed byte stream.
%
%   SEPARATOR AMBIGUITY, RECORDED RATHER THAN GUESSED. GNU coreutils sha256sum
%   writes "<hex>  <path>" in text mode and "<hex> *<path>" in binary mode, and
%   the default differs between builds. Both byte streams are therefore hashed
%   and both aggregates are returned:
%       aggregate_sha256          two-space separator (POSIX text-mode form)
%       aggregate_sha256_binary   " *" separator (binary-mode form)
%   The source-freeze record states which one the reference shell produced.
%   Nothing is silently assumed.
%
%   NAME-COLLISION SELF-TEST. Every existing project harness calls
%   addpath(genpath(src)), and genpath descends alphabetically, so src/baselines
%   lands on the MATLAB path AHEAD of src/control, src/dynamics and the
%   toolboxes. A baseline file sharing a basename with a project function would
%   silently shadow it. This function therefore reports every basename under
%   src/baselines/** that collides with another .m file under src/, and lists
%   the +shadow_stubs package separately: those files are deliberately
%   collision-named, which is exactly why they live in a '+' directory that
%   genpath refuses to descend into.
%
%   Returned fields:
%       root, repo_root, files, count, rel, sha, bytes
%       listing_text, listing_text_binary
%       aggregate_sha256, aggregate_sha256_binary
%       collisions, stub_package_files, stub_package_is_genpath_excluded
%       hash_backend, stamp

    if nargin < 1 || isempty(rootDir)
        thisDir = fileparts(mfilename('fullpath'));            % src/baselines/common
        rootDir = fileparts(thisDir);                          % src/baselines
    end
    w = what(rootDir);
    if ~isempty(w), rootDir = w(1).path; end
    assert(exist(rootDir, 'dir') == 7, 'baseline_manifest:root', ...
        'Baseline root does not exist: %s', rootDir);

    repoRoot = fileparts(fileparts(rootDir));                  % <repo>/src/baselines -> <repo>
    wr = what(repoRoot);
    if ~isempty(wr), repoRoot = wr(1).path; end

    % ---- collect every .m file, recursively --------------------------------
    found = collect_m_files(rootDir);
    assert(~isempty(found), 'baseline_manifest:empty', ...
        'No .m file found under %s. A manifest of nothing is not a manifest.', rootDir);

    rel = cell(numel(found), 1);
    for i = 1:numel(found)
        rel{i} = to_repo_relative(found{i}, repoRoot);
    end

    % ---- LC_ALL=C (byte) ordering ------------------------------------------
    ord = byte_sort_order(rel);
    rel = rel(ord);
    absPaths = found(ord);
    absPaths = absPaths(:);

    % ---- per-file hashes ----------------------------------------------------
    n   = numel(rel);
    sha = cell(n, 1);
    nby = zeros(n, 1);
    backend = '';
    for i = 1:n
        [sha{i}, backend] = baseline_sha256(absPaths{i});
        d = dir(absPaths{i});
        nby(i) = d(1).bytes;
    end

    % ---- the two coreutils listing forms and their aggregates ---------------
    partsT = cell(n, 1);
    partsB = cell(n, 1);
    for i = 1:n
        partsT{i} = sprintf('%s  %s\n', sha{i}, rel{i});
        partsB{i} = sprintf('%s *%s\n', sha{i}, rel{i});
    end
    txtT = [partsT{:}];
    txtB = [partsB{:}];
    aggT = baseline_sha256(uint8(txtT), false);
    aggB = baseline_sha256(uint8(txtB), false);

    % ---- name-collision self-test ------------------------------------------
    [coll, stubFiles] = name_collisions(absPaths, rel, repoRoot);

    man = struct( ...
        'root',                    rootDir, ...
        'repo_root',               repoRoot, ...
        'files',                   {absPaths}, ...
        'count',                   n, ...
        'rel',                     {rel}, ...
        'sha',                     {sha}, ...
        'bytes',                   nby, ...
        'listing_text',            txtT, ...
        'listing_text_binary',     txtB, ...
        'aggregate_sha256',        aggT, ...
        'aggregate_sha256_binary', aggB, ...
        'collisions',              {coll}, ...
        'stub_package_files',      {stubFiles}, ...
        'stub_package_is_genpath_excluded', true, ...
        'hash_backend',            backend, ...
        'stamp',                   datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
end

% =====================================================================
function out = collect_m_files(d)
% Recursive .m collection. Every subdirectory is descended into, INCLUDING the
% +shadow_stubs package: protocol Sec. 15.1 requires the stubs inside the
% manifest, so a flat glob or a genpath-style filter would be wrong here.
    out = {};
    entries = dir(d);
    for i = 1:numel(entries)
        nm = entries(i).name;
        if strcmp(nm, '.') || strcmp(nm, '..')
            continue
        end
        full = fullfile(d, nm);
        if entries(i).isdir
            out = [out, collect_m_files(full)];    %#ok<AGROW>
        elseif numel(nm) > 2 && strcmpi(nm(end-1:end), '.m')
            out{end+1} = full;                     %#ok<AGROW>
        end
    end
end

% =====================================================================
function r = to_repo_relative(full, repoRoot)
% Repository-relative path with FORWARD slashes, so the hashed byte stream is
% platform independent and matches the shell command of protocol Sec. 15.1.
    fwd  = strrep(full, filesep, '/');
    fwd  = strrep(fwd, '\', '/');
    root = strrep(repoRoot, filesep, '/');
    root = strrep(root, '\', '/');
    if ~isempty(root) && root(end) ~= '/'
        root = [root '/'];
    end
    if strncmpi(fwd, root, numel(root))
        r = fwd(numel(root)+1:end);
    else
        r = fwd;                                   % defensive: never silently blank
    end
end

% =====================================================================
function ord = byte_sort_order(strs)
% LC_ALL=C ordering: compare the UTF-8 byte sequences, zero-padded on the right.
% Byte 0 sorts below every printable byte, so a prefix sorts before its
% extensions, exactly as LC_ALL=C sort does.
    n = numel(strs);
    B = cell(n, 1);
    L = zeros(n, 1);
    for i = 1:n
        B{i} = uint8(unicode2native(strs{i}, 'UTF-8'));
        L(i) = numel(B{i});
    end
    M = zeros(n, max(L));
    for i = 1:n
        M(i, 1:L(i)) = double(B{i});
    end
    [~, ord] = sortrows(M);
end

% =====================================================================
function [coll, stubFiles] = name_collisions(absPaths, rel, repoRoot)
% Report baseline basenames that also exist elsewhere under src/. Files inside
% the +shadow_stubs package are SUPPOSED to collide - that is what makes them
% shadow - so they are listed separately rather than flagged as a defect.
    srcDir = fullfile(repoRoot, 'src');
    others = collect_m_files(srcDir);
    blRoot = strrep(fullfile(srcDir, 'baselines'), '\', '/');
    blRoot = strrep(blRoot, filesep, '/');
    keep = true(numel(others), 1);
    for i = 1:numel(others)
        o = strrep(strrep(others{i}, filesep, '/'), '\', '/');
        keep(i) = ~strncmpi(o, blRoot, numel(blRoot));
    end
    others = others(keep);

    otherNames = cell(numel(others), 1);
    for i = 1:numel(others)
        [~, otherNames{i}] = fileparts(others{i});
    end

    coll = {};
    stubFiles = {};
    for i = 1:numel(absPaths)
        [~, nm] = fileparts(absPaths{i});
        p = strrep(strrep(absPaths{i}, filesep, '/'), '\', '/');
        if ~isempty(strfind(p, '/+shadow_stubs/')) %#ok<STREMP>
            stubFiles{end+1} = rel{i};             %#ok<AGROW>
            continue
        end
        if any(strcmp(nm, otherNames))
            coll{end+1} = rel{i};                  %#ok<AGROW>
        end
    end
end

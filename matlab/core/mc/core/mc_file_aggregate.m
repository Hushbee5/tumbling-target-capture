function [agg, listing, hexes, paths] = mc_file_aggregate(root, relPaths)
% MC_FILE_AGGREGATE  Canonical byte aggregate over a set of repository files.
%   [agg, listing, hexes, paths] = mc_file_aggregate(root, relPaths)
%
%   The aggregate is the SHA-256 of the listing whose lines are, byte for byte,
%
%       '<64 lowercase hex> *<repository-relative forward-slash path>\n'
%
%   in LC_ALL=C (code-point) order of the paths. This is the convention of the
%   frozen 17-file production aggregate, the R7 baseline aggregate and Object
%   B v2 (task4_baseline_source_freeze_record_v2.md Sec. F.2). Shell
%   equivalent, from the repository root:
%
%       for f in $(printf '%s\n' <paths> | LC_ALL=C sort); do
%           sha256sum -b "$f"; done | sha256sum
%
%   File bytes are hashed RAW by the frozen BASELINE_SHA256; no line-ending
%   or encoding normalisation happens anywhere.

    paths = cellstr(relPaths(:));
    assert(~isempty(paths), 'mc:aggregate:empty', 'No files were supplied.');
    paths = sort(paths);
    assert(numel(unique(paths)) == numel(paths), 'mc:aggregate:duplicate', ...
        'The file list contains a duplicate path.');

    n = numel(paths);
    hexes = cell(n, 1);
    lines = cell(n, 1);
    for i = 1:n
        assert(~contains(paths{i}, '\') && ~startsWith(paths{i}, '/'), ...
            'mc:aggregate:path', 'Path %s is not repository-relative forward-slash.', ...
            paths{i});
        f = fullfile(root, strrep(paths{i}, '/', filesep));
        hexes{i} = baseline_sha256(f);
        lines{i} = sprintf('%s *%s\n', hexes{i}, paths{i});
    end
    listing = [lines{:}];
    agg = baseline_sha256(unicode2native(listing, 'UTF-8'), false);
end

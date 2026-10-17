function rel = mc_list_files(root, relDir)
% MC_LIST_FILES  Every file below a repository folder, as sorted relative paths.
%   rel = mc_list_files(root, relDir) returns a column cellstr of
%   repository-relative, forward-slash paths of ALL regular files below relDir
%   (recursively), in code-point (LC_ALL=C) order. Paths are built by
%   concatenating directory entry names, never by stripping a prefix from an
%   absolute path, so the result cannot depend on how the root was spelled.
%   A missing folder yields an empty list.

    rel = cell(0, 1);
    base = fullfile(root, strrep(relDir, '/', filesep));
    if ~isfolder(base)
        return
    end
    rel = walk(base, relDir);
    rel = sort(rel);
end

% =====================================================================
function rel = walk(absDir, relDir)
    rel = cell(0, 1);
    d = dir(absDir);
    for i = 1:numel(d)
        name = d(i).name;
        if strcmp(name, '.') || strcmp(name, '..')
            continue
        end
        if d(i).isdir
            rel = [rel; walk(fullfile(absDir, name), [relDir '/' name])]; %#ok<AGROW>
        else
            rel{end+1, 1} = [relDir '/' name];                               %#ok<AGROW>
        end
    end
end

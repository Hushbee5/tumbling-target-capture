function p = mc_abs_path(p)
% MC_ABS_PATH  Canonical absolute form of a file or folder path.
%   p = mc_abs_path(p) resolves '.', '..', relative components and, on
%   Windows, the stored letter case and 8.3 short names, through
%   java.io.File.getCanonicalPath. The path does not need to exist. Used
%   wherever a destination must be compared against a protected location, so
%   that two spellings of one folder can never be mistaken for two folders.

    assert(ischar(p) || (isstring(p) && isscalar(p)), 'mc:path:type', ...
        'A path must be a character vector or a string scalar.');
    p = char(java.io.File(char(p)).getCanonicalPath());
end

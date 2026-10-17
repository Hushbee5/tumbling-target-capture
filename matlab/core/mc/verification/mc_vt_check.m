function c = mc_vt_check(name, pass, detail)
% MC_VT_CHECK  One verification assertion result: struct(name, pass, detail).
    if nargin < 3, detail = ''; end
    if ~ischar(detail), detail = char(string(detail)); end
    c = struct('name', name, 'pass', logical(pass), 'detail', detail);
end

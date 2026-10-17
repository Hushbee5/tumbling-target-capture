function s = mc_vt_set_path(s, path, value)
% MC_VT_SET_PATH  Return a copy of struct s with the dotted field path set to value.
    parts = strsplit(path, '.');
    if numel(parts) == 1
        s.(parts{1}) = value;
    else
        s.(parts{1}) = mc_vt_set_path(s.(parts{1}), strjoin(parts(2:end), '.'), value);
    end
end

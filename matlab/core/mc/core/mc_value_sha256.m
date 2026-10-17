function hex = mc_value_sha256(x)
% MC_VALUE_SHA256  Canonical SHA-256 of a MATLAB value (Merkle over its structure).
%   hex = mc_value_sha256(x) hashes class, size and raw bytes of every array
%   leaf (MC_ARRAY_SHA256), struct field names in sorted order, cell and struct
%   array layout, and function handles by their text. Equal hashes mean
%   bitwise-equal values. Used to seal campaign contexts and to bind manifests;
%   it relies only on documented MATLAB behaviour.

    hex = baseline_sha256(unicode2native(node(x), 'UTF-8'), false);
end

% =====================================================================
function s = node(x)
    if isstruct(x)
        f = sort(fieldnames(x));
        parts = cell(1, numel(x) * numel(f));
        n = 0;
        for i = 1:numel(x)
            for k = 1:numel(f)
                n = n + 1;
                parts{n} = [f{k} '=' mc_value_sha256(x(i).(f{k}))];
            end
        end
        s = sprintf('S|%s|%s|%s', mat2str(size(x)), strjoin(f(:).', ','), strjoin(parts, ';'));
    elseif iscell(x)
        parts = cell(1, numel(x));
        for i = 1:numel(x)
            parts{i} = mc_value_sha256(x{i});
        end
        s = sprintf('C|%s|%s', mat2str(size(x)), strjoin(parts, ';'));
    elseif isa(x, 'function_handle')
        s = ['F|' func2str(x)];
    elseif isstring(x)
        s = ['T|' mat2str(size(x)) '|' mc_value_sha256(cellstr(x))];
    elseif isnumeric(x) || islogical(x) || ischar(x)
        s = ['A|' mc_array_sha256(x)];
    else
        error('mc:hash:value', 'A value of class %s cannot be hashed canonically.', class(x));
    end
end

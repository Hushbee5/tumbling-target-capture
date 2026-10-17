function [eq, where] = mc_vt_bitwise_equal(a, b, path)
% MC_VT_BITWISE_EQUAL  Recursive BITWISE equality of two MATLAB values.
%   [eq, where] = mc_vt_bitwise_equal(a, b) compares class, size and raw
%   bytes of numeric arrays (so -0 ~= +0 and NaN payloads are compared
%   exactly), values of logical and char arrays, and recurses through
%   structs (same field SET) and cells. where names the first difference.
    if nargin < 3, path = 'value'; end
    eq = false;  where = path;
    if ~strcmp(class(a), class(b)) || ~isequal(size(a), size(b))
        where = sprintf('%s: class/size %s%s vs %s%s', path, class(a), mat2str(size(a)), ...
                        class(b), mat2str(size(b)));
        return
    end
    if isnumeric(a)
        if isempty(a)
            eq = true;
        elseif isreal(a) && isreal(b)
            eq = isequal(typecast(a(:), 'uint8'), typecast(b(:), 'uint8'));
        else
            eq = isequal(typecast(real(a(:)), 'uint8'), typecast(real(b(:)), 'uint8')) ...
                 && isequal(typecast(imag(a(:)), 'uint8'), typecast(imag(b(:)), 'uint8'));
        end
    elseif islogical(a) || ischar(a)
        eq = isequal(a, b);
    elseif isstruct(a)
        fa = sort(fieldnames(a));  fb = sort(fieldnames(b));
        if ~isequal(fa, fb)
            where = sprintf('%s: field sets differ', path);
            return
        end
        for i = 1:numel(a)
            for k = 1:numel(fa)
                [e, w] = mc_vt_bitwise_equal(a(i).(fa{k}), b(i).(fa{k}), ...
                                             sprintf('%s(%d).%s', path, i, fa{k}));
                if ~e, where = w; return, end
            end
        end
        eq = true;
    elseif iscell(a)
        for i = 1:numel(a)
            [e, w] = mc_vt_bitwise_equal(a{i}, b{i}, sprintf('%s{%d}', path, i));
            if ~e, where = w; return, end
        end
        eq = true;
    elseif isa(a, 'function_handle')
        eq = strcmp(func2str(a), func2str(b));
    else
        eq = isequal(a, b);
    end
    if eq, where = ''; end
end

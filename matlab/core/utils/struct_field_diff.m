function d = struct_field_diff(a, b)
% STRUCT_FIELD_DIFF  Recursive comparison of two plain structs.
%   d = struct_field_diff(a, b) returns a cellstr naming every field that
%   differs, using dotted paths for nested structs. An empty result means the
%   two structs are identical under ISEQUALN.
%
%   Used by the Task 4 replay-identity checks: TASK4_CLASSIFY compares run
%   configurations across the alpha sweep, and F5_HCAP_SCAN verifies that the
%   parameter set it was handed matches the one that produced the run. Both need
%   the same comparison, so it lives here rather than being duplicated.
%
%   Intended for pure numeric/char/logical structs. Non-struct leaves are
%   compared with ISEQUALN, so NaN equals NaN.

    d = {};
    if ~isstruct(a) || ~isstruct(b)
        if ~isequaln(a, b), d = {'<value>'}; end
        return
    end
    fa = fieldnames(a);  fb = fieldnames(b);
    if ~isequal(sort(fa), sort(fb))
        d = {'<field set>'};
        return
    end
    for i = 1:numel(fa)
        va = a.(fa{i});  vb = b.(fa{i});
        if isstruct(va) && isstruct(vb)
            sub = struct_field_diff(va, vb);
            for j = 1:numel(sub)
                d{end+1} = [fa{i} '.' sub{j}]; %#ok<AGROW>
            end
        elseif ~isequaln(va, vb)
            d{end+1} = fa{i}; %#ok<AGROW>
        end
    end
end

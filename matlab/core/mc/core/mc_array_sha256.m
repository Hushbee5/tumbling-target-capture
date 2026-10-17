function hex = mc_array_sha256(A)
% MC_ARRAY_SHA256  SHA-256 of an array's class, size and raw bytes.
%   hex = mc_array_sha256(A) hashes the header '<class>|<size>|' followed by
%   the IEEE-754 (or integer / logical / char) bytes of A in column-major
%   order. Equal hashes therefore mean BITWISE-equal arrays of the same class
%   and size; this is stricter than ISEQUAL, which treats -0 and +0 as equal.
%   Used to bind shared tables and truth histories across records without
%   storing them.

    assert(isnumeric(A) || islogical(A) || ischar(A), 'mc:hash:class', ...
        'Only numeric, logical or char arrays can be hashed; got %s.', class(A));
    assert(isreal(A), 'mc:hash:complex', 'Complex arrays are not hashed here.');
    hdr = unicode2native(sprintf('%s|%s|', class(A), mat2str(size(A))), 'UTF-8');
    if islogical(A)
        b = uint8(A(:));
    elseif ischar(A)
        b = unicode2native(A(:).', 'UTF-8');
    elseif isempty(A)
        b = zeros(0, 1, 'uint8');
    else
        b = typecast(A(:), 'uint8');
    end
    hex = baseline_sha256([hdr(:); b(:)], false);
end

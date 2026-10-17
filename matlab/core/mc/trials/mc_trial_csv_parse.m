function T = mc_trial_csv_parse(bytes, nExpected)
% MC_TRIAL_CSV_PARSE  Strict parser of canonical trial-CSV BYTES (protocol Sec. 10.1).
%   T = mc_trial_csv_parse(bytes, nExpected) enforces every byte-contract
%   clause, each with its own identifier: no BOM, ASCII only, no CR, final LF,
%   exact header, exactly nExpected rows, trial_id = 1..n, 32 fields per row, no
%   trailing comma, finite values, and CANONICAL NUMBER TEXT: every value field
%   must equal sprintf('%.17g', v) of the double v it parses to. The last clause
%   makes the bytes identical to MC_TRIAL_CSV_BYTES of the parsed values and
%   guarantees an exact double round trip.
%
%   The DERIVED fields are returned as execution inputs; the raw draws are
%   returned for audit only (Sec. 3.4). T.kind is 'PARSED' - a provenance label
%   that authorises nothing.

    c = mc_constants();
    assert(isa(bytes, 'uint8'), 'mc:csv:bytes', 'bytes must be uint8.');
    bytes = bytes(:).';
    assert(numel(bytes) >= 1, 'mc:csv:empty', 'The trial CSV is empty.');
    assert(~(numel(bytes) >= 3 && isequal(bytes(1:3), uint8([239 187 191]))), ...
        'mc:csv:bom', 'The trial CSV starts with a UTF-8 BOM.');
    assert(all(bytes < 128), 'mc:csv:ascii', 'The trial CSV contains a non-ASCII byte.');
    assert(~any(bytes == 13), 'mc:csv:cr', 'The trial CSV contains a carriage return.');
    assert(bytes(end) == 10, 'mc:csv:final_newline', 'The trial CSV lacks a final newline.');

    txt   = char(bytes(1:end-1));
    lines = regexp(txt, '\n', 'split');
    assert(numel(lines) == nExpected + 1, 'mc:csv:rows', ...
        'Expected a header and %d rows; found %d lines.', nExpected, numel(lines));
    assert(strcmp(lines{1}, c.csv.header), 'mc:csv:header', 'The CSV header is not canonical.');

    M = zeros(c.csv.n_columns - 1, nExpected);
    for i = 1:nExpected
        L = lines{i + 1};
        assert(~isempty(L) && L(end) ~= ',', 'mc:csv:trailing_comma', ...
            'Row %d is empty or ends with a comma.', i);
        f = regexp(L, ',', 'split');
        assert(numel(f) == c.csv.n_columns, 'mc:csv:columns', ...
            'Row %d has %d fields, not %d.', i, numel(f), c.csv.n_columns);
        assert(strcmp(f{1}, sprintf('%d', i)), 'mc:csv:trial_id', ...
            'Row %d carries trial_id ''%s''.', i, f{1});
        for j = 2:c.csv.n_columns
            v = str2double(f{j});
            assert(isfinite(v) && isreal(v), 'mc:csv:value', ...
                'Row %d field %d (''%s'') is not a finite number.', i, j, f{j});
            assert(strcmp(sprintf('%.17g', v), f{j}), 'mc:csv:noncanonical', ...
                'Row %d field %d (''%s'') is not the canonical %%.17g text of its value.', ...
                i, j, f{j});
            M(j - 1, i) = v;
        end
    end

    T.kind     = 'PARSED';
    T.n        = nExpected;
    T.trial_id = 1:nExpected;
    T.U        = M(1:15, :);
    T.r0       = M(16:18, :);
    T.v0       = M(19:21, :);
    T.q0       = M(22:25, :);
    T.w0       = M(26:28, :);
    T.Idiag    = M(29:31, :);
end

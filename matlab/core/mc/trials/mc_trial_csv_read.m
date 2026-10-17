function T = mc_trial_csv_read(path, nExpected, expectedSha256)
% MC_TRIAL_CSV_READ  Read and strictly parse a canonical trial CSV (protocol Sec. 10.1).
%   T = mc_trial_csv_read(path, nExpected)
%   T = mc_trial_csv_read(path, nExpected, expectedSha256)
%
%   When expectedSha256 is supplied the raw bytes are hashed FIRST and must
%   match; scientific execution always supplies the SHA-256 read from the
%   committed freeze record (Sec. 10.1, 11 check 6). Parsing is
%   MC_TRIAL_CSV_PARSE on the exact bytes read. T.source records path, SHA-256
%   and byte count.

    assert(isfile(path), 'mc:csv:missing', 'Trial CSV not found: %s', path);
    fid = fopen(path, 'rb');
    assert(fid > 0, 'mc:csv:open', 'Could not open %s.', path);
    closer = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8').';
    clear closer
    got = baseline_sha256(bytes, false);
    if nargin >= 3 && ~isempty(expectedSha256)
        assert(strcmpi(got, expectedSha256), 'mc:csv:sha', ...
            'The trial CSV hashes to %s, not the frozen %s.', got, lower(expectedSha256));
    end
    T = mc_trial_csv_parse(bytes, nExpected);
    T.source = struct('path', path, 'sha256', got, 'bytes', numel(bytes));
end

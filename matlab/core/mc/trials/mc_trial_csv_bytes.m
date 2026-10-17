function bytes = mc_trial_csv_bytes(T)
% MC_TRIAL_CSV_BYTES  The canonical CSV byte string of a trial table (Sec. 10.1).
%   bytes = mc_trial_csv_bytes(T) builds, and only builds, the bytes:
%
%     header  exactly one line, 32 columns, no spaces (MC_CONSTANTS csv.header)
%     rows    T.n rows, trial_id = 1..n in increasing order
%     formats trial_id %d ; every other field %.17g ; finite real values only
%     bytes   ASCII, no BOM, comma separator, '.' decimal point,
%             LF only, final newline present, no trailing comma
%
%   Column order: trial_id, u01..u15, r0_x..z, v0_x..z, q0_s,x,y,z, w0_x..z,
%   I_11, I_22, I_33. Producing bytes authorises nothing: no writer in src/mc
%   will place them at a protected destination (MC_PROTECTED_PATH).

    c = mc_constants();
    n = T.n;
    M = [T.U; T.r0; T.v0; T.q0; T.w0; T.Idiag];
    assert(isequal(size(M), [c.csv.n_columns - 1, n]), 'mc:csv:shape', ...
        'The trial table does not have 31 value rows.');
    assert(all(isfinite(M(:))) && isreal(M), 'mc:csv:nonfinite', ...
        'The canonical CSV admits finite real values only.');
    assert(isequal(T.trial_id, 1:n), 'mc:csv:trial_id', 'trial_id must be 1..n in increasing order.');

    lines = cell(n + 1, 1);
    lines{1} = [c.csv.header, char(10)];
    for i = 1:n
        lines{i + 1} = [sprintf('%d', T.trial_id(i)), sprintf(',%.17g', M(:, i)), char(10)];
    end
    txt = [lines{:}];
    assert(all(double(txt) < 128), 'mc:csv:ascii', 'The CSV text is not pure ASCII.');
    assert(~any(txt == char(13)), 'mc:csv:cr', 'The CSV text contains a carriage return.');
    bytes = uint8(txt);
end

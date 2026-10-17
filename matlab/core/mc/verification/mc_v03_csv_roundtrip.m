function R = mc_v03_csv_roundtrip(tmpRoot)
% MC_V03_CSV_ROUNDTRIP  Canonical CSV write-then-parse on FIXTURE data (Sec. 10.1, 10.2).
%   Writes the fixture-seed table to a temporary file OUTSIDE the repository,
%   verifies every byte-contract clause on the raw bytes, parses it back with
%   the strict parser and requires every double to round-trip BITWISE. Then:
%   overwrite refusal, refusal to write any table - whatever its label -
%   anywhere under results/task4/mc (nothing is created there), and one
%   negative control per parser clause. A SYNTHETIC table of edge values (exact
%   binary fractions, the extreme rand outputs 2^-53 and 1 - 2^-53) must
%   round-trip too.

    R.name = 'V03 canonical CSV round trip (fixture data)';
    ch = {};
    c = mc_constants();
    root = mc_repo_root();
    T = mc_fixture_trial_table(20260911, c.design.N_PHYSICAL);
    f = fullfile(tmpRoot, 'fixture_trials.csv');

    info = mc_trial_csv_write(T, f);
    fid = fopen(f, 'rb');  b = fread(fid, Inf, '*uint8').';  fclose(fid);
    txt = char(b);
    lines = regexp(txt(1:end-1), '\n', 'split');
    ch{end+1} = mc_vt_check('written bytes hash to the reported SHA-256', ...
        strcmp(baseline_sha256(f), info.sha256) && info.bytes == numel(b), info.sha256);
    ch{end+1} = mc_vt_check('ASCII, no BOM, no CR, final LF, 101 lines', ...
        all(b < 128) && ~isequal(b(1:3), uint8([239 187 191])) && ~any(b == 13) ...
        && b(end) == 10 && sum(b == 10) == 101);
    ch{end+1} = mc_vt_check('exact 32-column header, no spaces', strcmp(lines{1}, c.csv.header) ...
        && numel(strsplit(lines{1}, ',')) == 32 && ~contains(lines{1}, ' '));
    ch{end+1} = mc_vt_check('no trailing comma, trial_id 1..100', ...
        ~any(endsWith(lines, ',')) && isequal(cellfun(@(L) str2double(strtok(L, ',')), lines(2:end)), 1:100));

    T2 = mc_trial_csv_read(f, c.design.N_PHYSICAL, info.sha256);
    fields = {'U', 'r0', 'v0', 'q0', 'w0', 'Idiag'};
    rt = true;
    for k = 1:numel(fields)
        rt = rt && isequal(typecast(T.(fields{k})(:), 'uint64'), typecast(T2.(fields{k})(:), 'uint64'));
    end
    ch{end+1} = mc_vt_check('every one of the 3100 doubles round-trips BITWISE', rt);

    before = baseline_sha256(f);
    [ok, got] = mc_vt_throws(@() mc_trial_csv_write(T, f), 'mc:io:exists');
    ch{end+1} = mc_vt_check('overwrite refused and the file is unchanged', ...
        ok && strcmp(baseline_sha256(f), before), got);

    sciDir = fullfile(root, strrep(c.mc.dest_dir, '/', filesep));
    [ok, got] = mc_vt_throws(@() mc_trial_csv_write(T, fullfile(sciDir, 'x.csv')), ...
        'mc:csv:protected_path');
    ch{end+1} = mc_vt_check('a fixture table is refused under results/task4/mc; nothing created', ...
        ok && ~isfolder(sciDir), got);
    [ok, got] = mc_vt_throws(@() mc_trial_csv_write(T, fullfile(root, strrep(c.csv.path, '/', filesep))), ...
        'mc:csv:protected_path');
    ch{end+1} = mc_vt_check('a fixture table is refused at the canonical scientific path', ok && ~isfolder(sciDir), got);
    Ts = T;  Ts.kind = 'SCIENTIFIC';
    [ok, got] = mc_vt_throws(@() mc_trial_csv_write(Ts, fullfile(root, strrep(c.csv.path, '/', filesep))), ...
        'mc:csv:protected_path');
    ch{end+1} = mc_vt_check('a SCIENTIFIC label authorises nothing: canonical path still refused', ...
        ok && ~isfolder(sciDir), got);

    % ---- negative controls, one per parser clause ------------------------------
    good = txt;
    neg = {
        'CRLF line ends',        strrep(good, char(10), [char(13) char(10)]),            'mc:csv:cr'
        'UTF-8 BOM',             [char([239 187 191]) good],                              'mc:csv:bom'
        'no final newline',      good(1:end-1),                                           'mc:csv:final_newline'
        'wrong header',          strrep(good, 'trial_id,u01', 'trial,u01'),              'mc:csv:header'
        'trailing comma',        regexprep(good, '\n1,([^\n]*)\n', '\n1,$1,\n', 'once'),  'mc:csv:trailing_comma'
        'non-canonical number',  noncanonical(good),                                      'mc:csv:noncanonical'
        'missing row',           drop_last_row(good),                                     'mc:csv:rows'
        };
    for k = 1:size(neg, 1)
        g = fullfile(tmpRoot, sprintf('neg_%d.csv', k));
        fid = fopen(g, 'wb');  fwrite(fid, uint8(neg{k, 2}), 'uint8');  fclose(fid);
        [ok, got] = mc_vt_throws(@() mc_trial_csv_read(g, c.design.N_PHYSICAL), neg{k, 3});
        ch{end+1} = mc_vt_check(['parser refuses: ' neg{k, 1}], ok, got); %#ok<AGROW>
    end
    [ok, got] = mc_vt_throws(@() mc_trial_csv_read(f, c.design.N_PHYSICAL, repmat('0', 1, 64)), 'mc:csv:sha');
    ch{end+1} = mc_vt_check('parser refuses a SHA-256 mismatch before parsing', ok, got);

    % ---- edge values ---------------------------------------------------------------
    Ue = repmat([0.5; 0.25; 0.75; 2^-53; 1 - 2^-53; 0.1; 1/3; 0.9; 0.3; 0.6; 0.2; 0.4; 0.7; 0.05; 0.95], 1, 3);
    Ue(:, 2) = flipud(Ue(:, 2));
    Ue(1:6, 3) = [0.125; 0.375; 0.625; 0.875; 2^-40; 1 - 2^-40];
    Te = mc_trial_table_from_U(Ue, 'SYNTHETIC');
    fe = fullfile(tmpRoot, 'edge_trials.csv');
    ie = mc_trial_csv_write(Te, fe);
    Te2 = mc_trial_csv_read(fe, 3, ie.sha256);
    rt = true;
    for k = 1:numel(fields)
        rt = rt && isequal(typecast(Te.(fields{k})(:), 'uint64'), typecast(Te2.(fields{k})(:), 'uint64'));
    end
    ch{end+1} = mc_vt_check('edge values (2^-53, 1-2^-53, binary fractions) round-trip bitwise', rt);

    R.checks = [ch{:}];
end

% =====================================================================
function t = noncanonical(t)
% Rewrite the first u01 value of row 1 with one extra trailing zero digit:
% the same double, but not its canonical %.17g text.
    L = regexp(t, '\n', 'split');
    f = strsplit(L{2}, ',');
    if contains(f{2}, 'e')
        f{2} = strrep(f{2}, 'e', '0e');
    else
        f{2} = [f{2} '0'];
    end
    L{2} = strjoin(f, ',');
    t = strjoin(L, char(10));
end

% =====================================================================
function t = drop_last_row(t)
    L = regexp(t(1:end-1), '\n', 'split');
    t = [strjoin(L(1:end-1), char(10)) char(10)];
end

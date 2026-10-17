function [T, csv] = mc_scientific_trial_table(inputs)
% MC_SCIENTIFIC_TRIAL_TABLE  THE authoritative trial-table generation transaction.
%   [T, csv] = mc_scientific_trial_table(inputs) implements protocol Sec. 3.3,
%   3.4 and Sec. 10 steps 6-7 as ONE high-level operation. It is the only code
%   in src/mc that constructs the scientific stream
%
%       stream = RandStream('mt19937ar', 'Seed', 116075);
%       U      = rand(stream, 15, 100);
%
%   and the only code that can publish results/task4/mc/task4_mc_trials.csv:
%   the publication step is a LOCAL function of this file, unreachable from
%   any other caller, and every lower-level writer refuses that path.
%
%   inputs: protocol_sha256, mc_source_aggregate, mc_impl_commit (the
%   identities of the authorising invocation, Sec. 11).
%
%   THE TRANSACTION, IN ORDER; any failure stops it before publication:
%     1  session firewall: never in a session that has run the verification
%        suite (MC_RNG_SENTINEL); no fault-injection point armed
%     2  live generation preflight from the supplied inputs (MC_PREFLIGHT):
%        frozen protocol committed, MC source committed and clean with the
%        supplied aggregate and implementation commit, reviewed .gitattributes,
%        canonical CSV and freeze record ABSENT
%     3  the scientific draw: exactly N_PHYSICAL = 100 trials, 15 draws each,
%        from the dedicated stream; the caller supplies no draw and no table
%     4  the frozen mapping and collision rule; every hard validation check
%     5  the canonical bytes, strictly re-parsed IN MEMORY: exact header and
%        32-column contract, trial_id 1:100, every double reproduced bitwise
%     6  the live generation preflight AGAIN, then the canonical target
%        re-checked absent
%     7  local atomic publication (temporary file, no-replace rename)
%     8  strict read-back from disk against the published SHA-256, bitwise
%   A table generated here is never regenerated: publication refuses an
%   existing file, and nothing is resampled (collision rule, Sec. 3.4).

    c = mc_constants();
    root = mc_repo_root();

    % ---- 1 session firewall --------------------------------------------------
    assert(~mc_rng_sentinel('in_verification'), 'mc:rng:verification_session', ...
        ['REFUSED: the verification suite has run in this MATLAB session; the ' ...
         'scientific trial table may only be generated from a fresh process.']);
    assert(~mc_fault_hook('armed'), 'mc:rng:fault_hook_armed', ...
        'REFUSED: a verification fault-injection point is armed in this session.');
    assert(isstruct(inputs) && isscalar(inputs) ...
        && all(isfield(inputs, {'protocol_sha256', 'mc_source_aggregate', 'mc_impl_commit'})), ...
        'mc:rng:not_authorised', ...
        'REFUSED: the generation transaction needs the three authorising identities.');

    % ---- 2 live generation preflight -------------------------------------------
    pre = mc_preflight('generation', inputs);
    assert(isequal(pre.authorised, true), 'mc:rng:not_authorised', ...
        'REFUSED: the generation preflight did not pass.');
    dest = mc_abs_path(fullfile(root, strrep(c.csv.path, '/', filesep)));
    assert(~isfile(dest), 'mc:csv:exists', ...
        'REFUSED: %s already exists; the canonical table is generated once.', c.csv.path);

    % ---- 3 the scientific draw ---------------------------------------------------
    mc_rng_sentinel('mark');
    stream = RandStream(c.rng.generator, 'Seed', c.rng.seed);
    U = rand(stream, c.design.n_draws, c.design.N_PHYSICAL);
    assert(isequal(size(U), [c.design.n_draws, c.design.N_PHYSICAL]), 'mc:trials:shape', ...
        'STOP: the scientific draw is not 15 x 100.');

    % ---- 4 mapping, collision rule, validation ---------------------------------
    T = mc_trial_table_from_U(U, 'DERIVED');
    T.kind      = 'SCIENTIFIC';
    T.seed      = c.rng.seed;
    T.generator = c.rng.generator;
    rep = mc_trial_validate(T);
    assert(rep.ok_hard && T.n == c.design.N_PHYSICAL && isequal(T.trial_id, 1:c.design.N_PHYSICAL), ...
        'mc:trials:invalid', 'STOP: the generated table fails a hard check: %s', ...
        strjoin(rep.issues, '; '));
    T.validation = rep;

    % ---- 5 canonical bytes, strictly re-parsed in memory -------------------------
    bytes = mc_trial_csv_bytes(T);
    Tm = mc_trial_csv_parse(bytes, c.design.N_PHYSICAL);
    same_bits(T, Tm, 'in-memory parse');

    % ---- 6 re-verify live state, then publish once --------------------------------
    pre2 = mc_preflight('generation', inputs);
    assert(isequal(pre2.authorised, true) && ~isfile(dest), 'mc:rng:not_authorised', ...
        'REFUSED: the generation preflight no longer passes, or the target appeared.');
    csv = publish(dest, bytes);

    % ---- 8 strict read-back from disk -------------------------------------------------
    T2 = mc_trial_csv_read(dest, c.design.N_PHYSICAL, csv.sha256);
    same_bits(T, T2, 'read-back');
    csv.readback = 'strict parse OK; every stored double reproduced bitwise';
end

% =====================================================================
function csv = publish(dest, bytes)
% LOCAL publication of the canonical CSV: the only writer of that path.
    folder = fileparts(dest);
    if ~isfolder(folder)
        mkdir(folder);
    end
    assert(~isfile(dest), 'mc:csv:exists', 'REFUSED: the canonical CSV exists.');
    tmp = sprintf('%s.tmp-%d-%s', dest, feature('getpid'), ...
                  char(datetime('now', 'Format', 'yyyyMMddHHmmssSSSSSS')));
    cl = onCleanup(@() delete_if_exists(tmp));
    fid = fopen(tmp, 'wb');
    assert(fid > 0, 'mc:csv:open', 'Could not open %s.', tmp);
    n = fwrite(fid, bytes(:), 'uint8');
    st = fclose(fid);
    assert(n == numel(bytes) && st == 0, 'mc:csv:write', 'Short or failed write.');
    want = baseline_sha256(tmp);
    assert(~isfile(dest), 'mc:csv:exists', 'REFUSED: the canonical CSV appeared during the write.');
    ok = java.io.File(tmp).renameTo(java.io.File(dest));
    assert(logical(ok) && isfile(dest), 'mc:csv:rename', 'Atomic publication failed.');
    got = baseline_sha256(dest);
    assert(strcmp(got, want), 'mc:csv:verify', 'The published bytes do not verify.');
    clear cl
    csv = struct('path', dest, 'sha256', got, 'bytes', numel(bytes));
end

% =====================================================================
function same_bits(A, B, label)
    f = {'U', 'r0', 'v0', 'q0', 'w0', 'Idiag'};
    for k = 1:numel(f)
        assert(isequal(typecast(A.(f{k})(:), 'uint64'), typecast(B.(f{k})(:), 'uint64')), ...
            'mc:csv:readback', 'STOP: the %s does not reproduce %s bitwise.', label, f{k});
    end
end

% =====================================================================
function delete_if_exists(f)
    if isfile(f)
        delete(f);
    end
end

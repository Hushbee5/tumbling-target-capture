function V = mc_verify(opts)
% MC_VERIFY  The NON-SCIENTIFIC Monte Carlo verification suite (protocol Sec. 10.2).
%   V = mc_verify()             run every fixture
%   V = mc_verify(opts)         opts.fixtures: subset of fixture names;
%                               opts.keep_tmp: keep the temporary folder
%
%   Consumes NO scientific RNG, NO physical MC trial and NEVER the evaluation
%   initial condition. Everything it writes goes to a temporary folder OUTSIDE
%   the repository, removed at the end unless opts.keep_tmp.
%
%   SESSION GUARDS, asserted before and after EVERY fixture:
%     - the scientific-stream sentinel (MC_RNG_SENTINEL) is unset;
%     - the global random stream is the same object in the same state
%       (no global RNG use anywhere in the MC path or in the frozen code it
%       calls);
%     - the complete warning state is unchanged;
%     - results/task4/mc does not exist;
%     - no fault-injection point is left armed (MC_FAULT_HOOK; every point is
%       disarmed after each fixture, and a fixture that left one armed is
%       reported).
%   A fixture that throws is a FAILED fixture; the suite continues and reports
%   every result.

    if nargin < 1, opts = struct(); end
    c = mc_constants();
    root = mc_repo_root();
    allFixtures = {'mc_v01_r18_guard', 'mc_v02_generator_audit', 'mc_v03_csv_roundtrip', ...
           'mc_v04_adapter_frozen', 'mc_v05_truth_identity', 'mc_v06_shared_table_path', ...
           'mc_v07_v2c_reuse', 'mc_v08_ic_refusal_mask', 'mc_v09_apf_winner', ...
           'mc_v10_checkpoint', 'mc_v11_preflight', 'mc_v12_pair_smoke', ...
           'mc_v13_aggregation_units', 'mc_v14_prefix_shapes', 'mc_v15_authorisation_bypass', ...
           'mc_v16_closure_corruption', 'mc_v17_index_blind_spot', 'mc_v18_freeze_history', ...
           'mc_v19_failure_injection', 'mc_v20_shard_reservation', ...
           'mc_v21_shard_ownership'};
    if isfield(opts, 'fixtures') && ~isempty(opts.fixtures)
        list = opts.fixtures;
    else
        list = allFixtures;
    end

    V = struct('started_utc', mc_utc_now(), 'matlab', version, 'computer', computer, ...
               'repo', root, 'protocol_sha256', c.protocol.sha256, 'fixtures', [], ...
               'guards', [], 'pass', false, 'finished_utc', '');

    sciDir = fullfile(root, strrep(c.mc.dest_dir, '/', filesep));
    gs = RandStream.getGlobalStream;
    g0 = struct('type', gs.Type, 'seed', gs.Seed, 'state', gs.State);
    w0 = warning;
    assert(~mc_rng_sentinel('query'), 'mc:verify:sentinel', ...
        'The scientific-stream sentinel is already set in this MATLAB session.');
    assert(~isfolder(sciDir), 'mc:verify:destination', ...
        'results/task4/mc exists; the verification suite refuses to run.');
    % From here on, this MATLAB session can never generate the scientific table
    % or start a scientific campaign (session firewall, MC_RNG_SENTINEL).
    mc_rng_sentinel('enter_verification');

    stamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss'));
    tmpRoot = fullfile(tempdir, sprintf('mc_verify_%d_%s', feature('getpid'), stamp));
    mkdir(tmpRoot);
    assert(~strncmpi(mc_abs_path(tmpRoot), [root filesep], numel(root) + 1), 'mc:verify:tmp', ...
        'The temporary folder must lie outside the repository.');

    res = struct('name', {}, 'fixture', {}, 'pass', {}, 'n_checks', {}, 'n_failed', {}, ...
                 'checks', {}, 'error', {}, 'seconds', {});
    guards = struct('fixture', {}, 'sentinel_unset', {}, 'global_rng_unchanged', {}, ...
                    'warning_state_unchanged', {}, 'no_mc_destination', {}, 'no_fault_armed', {});
    mc_fault_hook('disarm');
    for i = 1:numel(list)
        fn = str2func(list{i});
        t0 = tic;
        r = struct('name', list{i}, 'fixture', list{i}, 'pass', false, 'n_checks', 0, ...
                   'n_failed', 0, 'checks', [], 'error', '', 'seconds', NaN);
        try
            out = fn(tmpRoot);
            r.name = out.name;
            r.checks = out.checks;
            r.n_checks = numel(out.checks);
            r.n_failed = sum(~[out.checks.pass]);
            r.pass = r.n_checks > 0 && r.n_failed == 0;
        catch ME
            r.error = sprintf('%s: %s', ME.identifier, ME.message);
            if ~isempty(ME.stack)
                r.error = sprintf('%s [%s:%d]', r.error, ME.stack(1).name, ME.stack(1).line);
            end
        end
        r.seconds = toc(t0);
        res(end+1) = r; %#ok<AGROW>

        gsNow = RandStream.getGlobalStream;
        gd = struct('fixture', list{i}, ...
            'sentinel_unset', ~mc_rng_sentinel('query'), ...
            'global_rng_unchanged', gsNow == gs && strcmp(gsNow.Type, g0.type) ...
                                    && gsNow.Seed == g0.seed && isequal(gsNow.State, g0.state), ...
            'warning_state_unchanged', isequal(warning, w0), ...
            'no_mc_destination', ~isfolder(sciDir), ...
            'no_fault_armed', ~mc_fault_hook('armed'));
        guards(end+1) = gd; %#ok<AGROW>
        mc_fault_hook('disarm');         % a fixture that failed mid-injection leaves nothing armed
        if ~gd.warning_state_unchanged
            warning(w0);                 % report, then restore so later fixtures are clean
        end
        print_fixture(r, gd);
    end

    V.fixtures = res;
    V.guards   = guards;
    V.tmp_root = tmpRoot;
    gOk = all_true(guards);
    V.pass = all([res.pass]) && gOk;
    V.finished_utc = mc_utc_now();
    fprintf('\n==== MC VERIFICATION: %d fixture(s), %d check(s), %d failed check(s), %d fixture error(s); guards %s ====\n', ...
        numel(res), sum([res.n_checks]), sum([res.n_failed]), sum(~cellfun(@isempty, {res.error})), ...
        tern(gOk, 'OK', 'VIOLATED'));
    fprintf('==== OVERALL: %s ====\n', tern(V.pass, 'PASS', 'FAIL'));

    if ~(isfield(opts, 'keep_tmp') && opts.keep_tmp)
        rmdir(tmpRoot, 's');
        V.tmp_removed = true;
    else
        V.tmp_removed = false;
    end
end

% =====================================================================
function ok = all_true(g)
    ok = true;
    for i = 1:numel(g)
        ok = ok && g(i).sentinel_unset && g(i).global_rng_unchanged ...
             && g(i).warning_state_unchanged && g(i).no_mc_destination && g(i).no_fault_armed;
    end
end

% =====================================================================
function print_fixture(r, gd)
    fprintf('\n---- %s  [%s]  %.1f s\n', r.name, tern(r.pass, 'PASS', 'FAIL'), r.seconds);
    if ~isempty(r.error)
        fprintf('     FIXTURE ERROR: %s\n', r.error);
    end
    for k = 1:numel(r.checks)
        x = r.checks(k);
        d = x.detail;
        if numel(d) > 160, d = [d(1:157) '...']; end
        fprintf('     %s  %s', tern(x.pass, 'ok  ', 'FAIL'), x.name);
        if ~isempty(d), fprintf('  | %s', d); end
        fprintf('\n');
    end
    fprintf(['     guards: sentinel_unset=%d global_rng_unchanged=%d warning_state_unchanged=%d ' ...
             'no_mc_destination=%d no_fault_armed=%d\n'], gd.sentinel_unset, gd.global_rng_unchanged, ...
        gd.warning_state_unchanged, gd.no_mc_destination, gd.no_fault_armed);
end

% =====================================================================
function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

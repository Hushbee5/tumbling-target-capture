function R = mc_v21_shard_ownership(tmpRoot)
% MC_V21_SHARD_OWNERSHIP  One process per shard, in plan order, no direct pairs (R-C). NON-SCIENTIFIC.
%   THREE REAL MATLAB PROCESSES are started CONCURRENTLY on the same fixture
%   checkpoint, each asking for the SAME shard (which holds BOTH fixture
%   trials) with counted, replayed runner overrides - no controller runs, no
%   scientific seed, no scientific trial row, everything outside the repository.
%   Exactly one process may own the shard:
%     - exactly one reports EXECUTED for both pairs, and ONLY that process
%       invoked any method (each process counts its invocations into its own
%       file);
%     - every other process stops with 'mc:campaign:shard_owned_elsewhere'
%       BEFORE any pair work - so two processes can never take different pairs
%       of one shard, and the 1-3 planned shards bound the number of executing
%       processes;
%     - the shard lock and every pair reservation name the winner's process.
%   Then, in this process: the shard is refused (another process owns it), an
%   operator release moves the lock, and the shard then resumes as
%   ALREADY_COMPLETE without invoking anything. Finally: there is no public
%   pair executor, and a pending pair stops the shard, so a later trial never
%   runs before an earlier one.

    R.name = 'V21 shard ownership: concurrent processes, plan order, no direct pair execution';
    ch = {};
    cap = mc_vt_capture();
    % a SYNTHETIC two-row table whose rows are the SAME physical trial, so the
    % replayed capture is valid for both pairs of the shard
    T = mc_trial_table_from_U([cap.T.U(:, 1), cap.T.U(:, 1)], 'SYNTHETIC');
    ck = fullfile(tmpRoot, 'v21');
    fixF = fullfile(tmpRoot, 'v21_fixture.mat');
    P = cap.P;  Bm = cap.Bm;  Ba = cap.Ba;  Tsim = cap.Tsim; %#ok<NASGU>
    save(fixF, 'T', 'P', 'Bm', 'Ba', 'Tsim', '-v7.3');

    cntP = containers.Map('KeyType', 'char', 'ValueType', 'double');
    ov = struct('proposed', @(r, a, t) mc_vt_counted(cntP, 'proposed', cap.P), ...
                'nominal_mpc', @(r, a, t) mc_vt_counted(cntP, 'nominal_mpc', cap.Bm), ...
                'apf', @(r, a, t) mc_vt_counted(cntP, 'apf', cap.Ba));
    ctx = mc_context('verification', ck, cap.Tsim, T, [1 2], struct('runner_override', ov));
    mc_shard_plan(ctx, 'U', {[1 2]}, 'fixture-operator');

    % ---- three concurrent processes ask for the same shard --------------------------
    n = 3;
    exe = fullfile(matlabroot, 'bin', 'matlab');
    if ispc, exe = [exe '.exe']; end
    procs = cell(1, n);  resF = cell(1, n);  cntF = cell(1, n);
    for i = 1:n
        resF{i} = fullfile(tmpRoot, sprintf('v21_result_%d.mat', i));
        cntF{i} = fullfile(tmpRoot, sprintf('v21_calls_%d.txt', i));
        scr = write_child(tmpRoot, i, mc_repo_root(), fixF, ck, resF{i}, cntF{i});
        pb = java.lang.ProcessBuilder({exe, '-batch', sprintf('run(''%s'')', fwd(scr))});
        pb.redirectErrorStream(true);
        pb.redirectOutput(java.io.File(fullfile(tmpRoot, sprintf('v21_child_%d.log', i))));
        procs{i} = pb.start();
    end
    started = numel(procs);
    for i = 1:n
        procs{i}.waitFor(900, java.util.concurrent.TimeUnit.SECONDS);
        if procs{i}.isAlive(), procs{i}.destroyForcibly(); end
    end
    res = cell(1, n);  ok = true;
    for i = 1:n
        if isfile(resF{i})
            S = load(resF{i}, 'res');
            res{i} = S.res;
        else
            ok = false;
            res{i} = struct('nonce', '', 'ok', false, 'id', 'NO_RESULT_FILE', 'states', {{}});
        end
    end
    ch{end+1} = mc_vt_check('three concurrent MATLAB processes ran and reported', ...
        started == n && ok, strjoin(cellfun(@(r) sprintf('%d/%s', r.ok, r.id), res, ...
        'UniformOutput', false), ', '));

    won = find(cellfun(@(r) r.ok, res));
    lost = find(~cellfun(@(r) r.ok, res));
    ch{end+1} = mc_vt_check('exactly one process owned the shard and executed both pairs', ...
        numel(won) == 1 && isequal(res{won}.states, {'EXECUTED', 'EXECUTED'}), ...
        sprintf('%d winner(s)', numel(won)));
    ids = cellfun(@(r) r.id, res(lost), 'UniformOutput', false);
    ch{end+1} = mc_vt_check('every other process stopped with shard_owned_elsewhere', ...
        ~isempty(lost) && all(strcmp(ids, 'mc:campaign:shard_owned_elsewhere')), strjoin(ids, ', '));
    nCalls = cellfun(@(f) count_lines(f), cntF);
    ch{end+1} = mc_vt_check('ONLY the winning process invoked any method (6 = 2 pairs x 3 methods)', ...
        nCalls(won) == 6 && all(nCalls(lost) == 0), mat2str(nCalls));

    scan = mc_record_scan(ck, 'U', ctx.binding, [1 2]);
    lock = mc_shard_lock('owner', ctx, 'U', 'S1');
    r1 = mc_reservation('owner', ctx, 'U', 1);
    r2 = mc_reservation('owner', ctx, 'U', 2);
    ch{end+1} = mc_vt_check('both pairs are complete, and the lock and both reservations name the winner', ...
        all(scan.present(:)) && strcmp(lock.owner.process.nonce, res{won}.nonce) ...
        && strcmp(r1.owner.process.nonce, res{won}.nonce) ...
        && strcmp(r2.owner.process.nonce, res{won}.nonce));

    % ---- this process: refused, then released, then a no-op resume ---------------------
    [okR, got] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), 'mc:campaign:shard_owned_elsewhere');
    ch{end+1} = mc_vt_check('this process is refused the shard another process owns', okR, got);
    mc_operator_release_shard(ctx, 'U', 'S1', 'fixture-operator', 'fixture: the child process ended');
    L = mc_run_condition(ctx, 'U', 'S1');
    ch{end+1} = mc_vt_check('after the operator release this process resumes the shard: nothing to do', ...
        isequal({L.pairs.state}, {'ALREADY_COMPLETE', 'ALREADY_COMPLETE'}) && isempty(keys(cntP)));
    [okC, gotC] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'close'), 'NO_ERROR');
    ch{end+1} = mc_vt_check('the checkpoint the other process wrote closes here (one campaign, two owners)', ...
        okC, gotC);

    % ---- no direct pair execution; a pending pair stops the shard ------------------------
    [ok1, g1] = mc_vt_throws(@() mc_run_pair(ctx, 2, 'U'), 'mc:campaign:no_direct_pair');
    ch{end+1} = mc_vt_check('R-C there is no public pair executor: no out-of-order direct call exists', ok1, g1);
    ck2 = fullfile(tmpRoot, 'v21b');
    cnt2 = containers.Map('KeyType', 'char', 'ValueType', 'double');
    ov2 = struct('proposed', @(r, a, t) mc_vt_counted(cnt2, 'proposed', cap.P), ...
                 'nominal_mpc', @(r, a, t) mc_vt_counted(cnt2, 'nominal_mpc', cap.Bm), ...
                 'apf', @(r, a, t) mc_vt_counted(cnt2, 'apf', cap.Ba));
    ctx2 = mc_context('verification', ck2, cap.Tsim, T, [1 2], struct('runner_override', ov2));
    mc_shard_plan(ctx2, 'U', {[1 2]}, 'fixture-operator');
    mc_fault_hook('arm', 'after_started:proposed');
    [okF, ~] = mc_vt_throws(@() mc_run_condition(ctx2, 'U', 'S1'), 'mc:fault:injected');
    mc_fault_hook('disarm');
    [okA, gotA] = mc_vt_throws(@() mc_run_condition(ctx2, 'U', 'S1'), 'mc:campaign:ambiguous_attempt');
    ch{end+1} = mc_vt_check(['R-C a pending first trial stops the shard: the second trial is never ' ...
        'started, reserved or recorded'], ...
        okF && okA && ~isfolder(fullfile(ck2, 'reservations', 'U_t002')) ...
        && isempty(dir(fullfile(ck2, 'attempts', 'U_t002_*.mat'))) ...
        && isempty(dir(fullfile(ck2, 'U', 'U_t002_*.mat'))), gotA);
    R.checks = [ch{:}];
end

% =====================================================================
function scr = write_child(tmpRoot, i, repo, fixF, ck, resF, cntF)
% One child: enter the verification session, build its own verification context
% on the shared fixture checkpoint and ask for shard S1.
    scr = fullfile(tmpRoot, sprintf('v21_child_%d.m', i));
    L = {
    'res = struct(''nonce'', '''', ''ok'', false, ''id'', ''STARTUP'', ''states'', {{}});'
    'try'
    sprintf('    addpath(genpath(''%s''));', fwd(fullfile(repo, 'src')))
    '    mc_rng_sentinel(''enter_verification'');'
    sprintf('    F = load(''%s'');', fwd(fixF))
    sprintf('    cf = ''%s'';', fwd(cntF))
    '    ov = struct(''proposed'', @(r, a, t) mc_vt_counted_file(cf, ''proposed'', F.P), ...'
    '                ''nominal_mpc'', @(r, a, t) mc_vt_counted_file(cf, ''nominal_mpc'', F.Bm), ...'
    '                ''apf'', @(r, a, t) mc_vt_counted_file(cf, ''apf'', F.Ba));'
    sprintf('    ctx = mc_context(''verification'', ''%s'', F.Tsim, F.T, [1 2], struct(''runner_override'', ov));', fwd(ck))
    '    me = mc_process_identity();'
    '    res.nonce = me.nonce;'
    '    res.id = '''';'
    '    try'
    '        L = mc_run_condition(ctx, ''U'', ''S1'');'
    '        res.ok = true;'
    '        res.states = {L.pairs.state};'
    '    catch ME'
    '        res.id = ME.identifier;'
    '    end'
    'catch ME2'
    '    res.id = [''STARTUP:'' ME2.identifier];'
    'end'
    sprintf('save(''%s'', ''res'');', fwd(resF))
    };
    fid = fopen(scr, 'w');
    assert(fid > 0, 'mc:vt:child', 'Cannot write %s.', scr);
    fprintf(fid, '%s\n', L{:});
    fclose(fid);
end

% =====================================================================
function s = fwd(p)
    s = strrep(p, '\', '/');
end

% =====================================================================
function n = count_lines(f)
    n = 0;
    if ~isfile(f), return, end
    t = fileread(f);
    n = numel(regexp(t, '\n', 'match'));
end

function R = mc_v20_shard_reservation(tmpRoot)
% MC_V20_SHARD_RESERVATION  Disjoint shard plans, shard locks and atomic reservations (F3, R-C). NON-SCIENTIFIC.
%   Plan: overlapping, incomplete and four-shard plans are refused; a valid
%   partition is written once and cannot be replaced; an unknown shard id is
%   refused. Reservation: the lock primitive (java mkdir) succeeds for exactly
%   one creator; a reservation directory created by ANOTHER OS PROCESS (cmd.exe)
%   before the pair starts - the collision window - makes the pair stop BEFORE
%   any table build or method call; a reservation owned by another process
%   nonce likewise; an operator release is refused while an attempt is
%   ambiguous and for a COMPLETE pair, and otherwise moves the reservation to
%   'released' after which the pair runs exactly once. Shard lock: a lock owned
%   by another process stops the shard before any pair, and only an operator
%   release (which moves it, never deletes it) lets this process take it.
%   No controller runs (MC_VT_CAPTURE replay).

    R.name = 'V20 shard plans and atomic reservations';
    ch = {};
    cap = mc_vt_capture();
    cnt = containers.Map('KeyType', 'char', 'ValueType', 'double');
    ov = struct('proposed', @(r, a, t) mc_vt_counted(cnt, 'proposed', cap.P), ...
                'nominal_mpc', @(r, a, t) mc_vt_counted(cnt, 'nominal_mpc', cap.Bm), ...
                'apf', @(r, a, t) mc_vt_counted(cnt, 'apf', cap.Ba));

    % ---- plans -----------------------------------------------------------------
    ck = fullfile(tmpRoot, 'v20');
    ctx2 = mc_context('verification', ck, cap.Tsim, cap.T, [1 2], struct('runner_override', ov));
    [ok, got] = mc_vt_throws(@() mc_shard_plan(ctx2, 'U', {[1 2], 2}, 'op'), 'mc:plan:overlap');
    ch{end+1} = mc_vt_check('an overlapping plan is refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_shard_plan(ctx2, 'U', {1}, 'op'), 'mc:plan:incomplete');
    ch{end+1} = mc_vt_check('an incomplete plan is refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_shard_plan(ctx2, 'U', {1, 2, 1, 2}, 'op'), 'mc:plan:shards');
    ch{end+1} = mc_vt_check('more than three shards are refused', ok, got);
    mc_shard_plan(ctx2, 'U', {1, 2}, 'fixture-operator');
    [ok, got] = mc_vt_throws(@() mc_shard_plan(ctx2, 'U', {[1 2]}, 'op'), 'mc:io:exists');
    ch{end+1} = mc_vt_check('a declared plan is immutable', ok, got);
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx2, 'U', 'S3'), 'mc:plan:unknown_shard');
    ch{end+1} = mc_vt_check('an unknown shard id is refused', ok, got);

    % ---- the lock primitive ------------------------------------------------------
    lk = fullfile(tmpRoot, 'v20_lock');
    first  = logical(java.io.File(lk).mkdir());
    second = logical(java.io.File(lk).mkdir());
    ch{end+1} = mc_vt_check('exclusive create: the first mkdir wins, the second fails', first && ~second);

    % ---- a reservation created by ANOTHER PROCESS in the collision window ----------
    resDir = fullfile(ck, 'reservations', 'U_t001');
    [st, ~] = system(sprintf('cmd /c mkdir "%s"', resDir));
    ch{end+1} = mc_vt_check('fixture: another OS process created the reservation directory', ...
        st == 0 && isfolder(resDir));
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx2, 'U', 'S1'), 'mc:campaign:reserved_elsewhere');
    ch{end+1} = mc_vt_check('the pair stops: reserved elsewhere', ok, got);
    ch{end+1} = mc_vt_check('no table build and no method call happened (no ledger, no record)', ...
        calls(cnt) == 0 && ~isfolder(fullfile(ck, 'attempts')) && ~isfolder(fullfile(ck, 'U')));

    % a foreign owner.mat (another process nonce) is refused as well
    owner = struct('schema', 'task4_mc_reservation_v1', 'binding', ctx2.binding, 'condition', 'U', ...
        'trial_id', 1, 'shard_id', 'S1', 'process', struct('pid', 1, 'start_utc', 'x', ...
        'nonce', '1_someone_else'), 'created_utc', mc_utc_now()); %#ok<NASGU>
    save(fullfile(resDir, 'owner.mat'), 'owner');
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx2, 'U', 'S1'), 'mc:campaign:reserved_elsewhere');
    ch{end+1} = mc_vt_check('a reservation owned by another process nonce is refused', ok, got);

    % an operator release, then exactly one execution
    mc_operator_release_reservation(ctx2, 'U', 1, 'fixture-operator', 'fixture: stale reservation');
    rel = dir(fullfile(ck, 'reservations', 'released'));
    ch{end+1} = mc_vt_check('the release is recorded and the reservation moved, not deleted', ...
        ~isfolder(resDir) && any(startsWith({rel.name}, 'U_t001__')) ...
        && ~isempty(dir(fullfile(ck, 'decisions', 'RELEASE_U_t001_*.mat'))));
    L = mc_run_condition(ctx2, 'U', 'S1');
    ch{end+1} = mc_vt_check('after the release the pair runs, each method exactly once', ...
        strcmp(L.pairs(1).state, 'EXECUTED') && calls(cnt) == 3, ...
        sprintf('%s, calls %d', L.pairs(1).state, calls(cnt)));
    L = mc_run_condition(ctx2, 'U', 'S1');
    ch{end+1} = mc_vt_check('a completed pair is never executed again', ...
        strcmp(L.pairs(1).state, 'ALREADY_COMPLETE') && calls(cnt) == 3);
    [ok, got] = mc_vt_throws(@() mc_operator_release_reservation(ctx2, 'U', 1, 'op', 'try'), ...
        'mc:operator:pair_complete');
    ch{end+1} = mc_vt_check('the reservation of a COMPLETE pair is never released', ok, got);

    % ---- shard ownership (R-C) -------------------------------------------------------
    lockDir = fullfile(ck, 'shard_locks', 'U_S2');
    mkdir(lockDir);
    owner = struct('schema', 'task4_mc_shard_lock_v1', 'binding', ctx2.binding, 'condition', 'U', ...
        'shard_id', 'S2', 'trial_ids', 2, 'process', struct('pid', 2, 'start_utc', 'y', ...
        'nonce', '2_another_process'), 'created_utc', mc_utc_now()); %#ok<NASGU>
    save(fullfile(lockDir, 'owner.mat'), 'owner');
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx2, 'U', 'S2'), 'mc:campaign:shard_owned_elsewhere');
    ch{end+1} = mc_vt_check('a shard owned by another process stops before any pair', ...
        ok && calls(cnt) == 3 && ~isfolder(fullfile(ck, 'reservations', 'U_t002')), got);
    mc_operator_release_shard(ctx2, 'U', 'S2', 'fixture-operator', 'fixture: the owner process ended');
    relS = dir(fullfile(ck, 'shard_locks', 'released'));
    ch{end+1} = mc_vt_check('the shard lock is moved to released, with its decision, never deleted', ...
        ~isfolder(lockDir) && any(startsWith({relS.name}, 'U_S2__')) ...
        && ~isempty(dir(fullfile(ck, 'decisions', 'RELEASE_SHARD_U_S2_*.mat'))));

    % a release is refused while an attempt is ambiguous
    mc_fault_hook('arm', 'after_started:proposed');
    [ok1, ~] = mc_vt_throws(@() mc_run_condition(ctx2, 'U', 'S2'), 'mc:fault:injected');
    mc_fault_hook('disarm');
    [ok, got] = mc_vt_throws(@() mc_operator_release_reservation(ctx2, 'U', 2, 'op', 'try'), ...
        'mc:operator:ambiguous_attempt');
    ch{end+1} = mc_vt_check('a release is refused while an attempt of the pair is ambiguous', ok1 && ok, got);
    R.checks = [ch{:}];
end

% =====================================================================
function n = calls(cnt)
    n = 0;
    k = keys(cnt);
    for i = 1:numel(k)
        n = n + cnt(k{i});
    end
end

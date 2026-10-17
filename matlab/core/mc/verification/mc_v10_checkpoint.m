function R = mc_v10_checkpoint(tmpRoot)
% MC_V10_CHECKPOINT  Atomic, never-overwritten records and resume inventory (Sec. 10.4).
%   NON-SCIENTIFIC; everything is written under a temporary folder OUTSIDE the
%   repository. Covers: atomic byte and MAT writes with no temporary leftover;
%   refusal to overwrite (content unchanged); a complete record round trip; a
%   scientific-failure status (M_CONSISTENCY_FAILURE) is itself a complete,
%   immutable record; binding and identity mismatches abort on read; a stale
%   temporary file from an interrupted write is not a record, and its run is
%   pending; an unexpected file aborts the scan; a verification context can
%   never be rooted inside the repository; HARNESS_ERROR is never a record;
%   kind and binding must agree; a record is refused without the pair's
%   reservation; a writer called outside every guarded boundary is refused
%   (no live lease), so the direct writer calls of this fixture hold one.

    R.name = 'V10 checkpoint immutability and resume inventory';
    ch = {};
    c = mc_constants();
    root = mc_repo_root();
    pBL = baseline_config();

    d = fullfile(tmpRoot, 'atomic');
    mkdir(d);
    f = fullfile(d, 'a.bin');
    info = mc_atomic_write(f, uint8('first'), 'bytes');
    ch{end+1} = mc_vt_check('atomic byte write: file present, hash verified', ...
        isfile(f) && strcmp(info.sha256, baseline_sha256(f)), info.sha256);
    [ok, got] = mc_vt_throws(@() mc_atomic_write(f, uint8('second'), 'bytes'), 'mc:io:exists');
    ch{end+1} = mc_vt_check('overwrite refused; content unchanged', ...
        ok && strcmp(baseline_sha256(f), info.sha256), got);
    g = fullfile(d, 'b.mat');
    mc_atomic_write(g, struct('x', magic(4), 's', 'text'), 'mat');
    S = load(g);
    ch{end+1} = mc_vt_check('atomic MAT write round-trips its variables', ...
        isequal(S.x, magic(4)) && strcmp(S.s, 'text'));
    dd = dir(d);
    ch{end+1} = mc_vt_check('no temporary file is left behind', ...
        ~any(contains({dd.name}, '.tmp-')), strjoin({dd(~[dd.isdir]).name}, ', '));

    T = mc_fixture_trial_table(911, 2);
    ck = fullfile(tmpRoot, 'ckpt10');
    ctx = mc_context('verification', ck, 1, T, [1 2]);
    mc_shard_plan(ctx, 'M', {[1 2]}, 'fixture-operator');
    rec0 = synthetic_record(ctx, 'M', 1, 'apf', pBL);
    [ok, got] = mc_vt_throws(@() mc_record_write(ctx, rec0), 'mc:campaign:no_live_authority');
    ch{end+1} = mc_vt_check('a writer called outside any guarded boundary is refused (no live lease)', ok, got);
    op = mc_campaign_guard(ctx, 'operator'); %#ok<NASGU>   % a live boundary for the direct writer calls below
    mc_shard_lock('acquire', ctx, 'M', 'S1');
    mc_reservation('acquire', ctx, 'M', 1, 'S1');
    rec = synthetic_record(ctx, 'M', 1, 'apf', pBL);
    wi = mc_record_write(ctx, rec);
    back = mc_record_read(wi.path, ctx.binding);
    ch{end+1} = mc_vt_check('an M_CONSISTENCY_FAILURE record is written and reads back unchanged', ...
        isequaln(back, rec));
    [ok, got] = mc_vt_throws(@() mc_record_write(ctx, rec), 'mc:io:exists');
    ch{end+1} = mc_vt_check('a completed record is never overwritten', ...
        ok && strcmp(baseline_sha256(wi.path), wi.sha256), got);
    b2 = ctx.binding;  b2.mc_impl_commit = 'SOMETHING_ELSE';
    [ok, got] = mc_vt_throws(@() mc_record_read(wi.path, b2), 'mc:record:binding');
    ch{end+1} = mc_vt_check('a binding mismatch aborts on read', ok, got);
    wrong = fullfile(tmpRoot, 'M_t002_apf.mat');
    copyfile(wi.path, wrong);
    [ok, got] = mc_vt_throws(@() mc_record_read(wrong, ctx.binding), 'mc:record:identity');
    ch{end+1} = mc_vt_check('a record whose content disagrees with its name aborts', ok, got);

    stale = fullfile(ck, 'M', 'M_t002_apf.tmp-1-20260911000000000000.mat');
    fid = fopen(stale, 'wb');  fwrite(fid, uint8('partial'));  fclose(fid);
    scan = mc_record_scan(ck, 'M', ctx.binding, [1 2]);
    ch{end+1} = mc_vt_check('stale temporary file: reported, not a record; its run is pending', ...
        numel(scan.stale_tmp) == 1 && scan.present(1, 3) && ~scan.present(2, 3), ...
        sprintf('present %s', mat2str(scan.present)));
    [ok, got] = mc_vt_throws(@() mc_record_write(ctx, synthetic_record(ctx, 'M', 2, 'apf', pBL)), ...
        'mc:campaign:not_reserved');
    ch{end+1} = mc_vt_check('a record is refused while its pair is not reserved by this process', ok, got);
    mc_reservation('acquire', ctx, 'M', 2, 'S1');
    mc_record_write(ctx, synthetic_record(ctx, 'M', 2, 'apf', pBL));
    scan = mc_record_scan(ck, 'M', ctx.binding, [1 2]);
    ch{end+1} = mc_vt_check('the pending run can then be recorded', scan.present(2, 3), mat2str(scan.present));

    ck2 = fullfile(tmpRoot, 'ckpt10b');
    mkdir(fullfile(ck2, 'U'));
    fid = fopen(fullfile(ck2, 'U', 'notes.txt'), 'wb');  fwrite(fid, uint8('x'));  fclose(fid);
    [ok, got] = mc_vt_throws(@() mc_record_scan(ck2, 'U', ctx.binding, 1), 'mc:record:unknown_file');
    ch{end+1} = mc_vt_check('an unexpected file in a checkpoint folder aborts the scan', ok, got);

    sciDir = fullfile(root, strrep(c.mc.dest_dir, '/', filesep));
    [ok, got] = mc_vt_throws(@() mc_context('verification', fullfile(sciDir, 'checkpoint'), 1, T, 1), ...
        'mc:context:verification_root');
    ch{end+1} = mc_vt_check('a verification context can never be rooted inside the repository', ...
        ok && ~isfolder(sciDir), got);
    rh = rec;  rh.status = 'HARNESS_ERROR';
    [ok, got] = mc_vt_throws(@() mc_record_write(ctx, rh), 'mc:record:harness');
    ch{end+1} = mc_vt_check('HARNESS_ERROR is never written as a record', ok, got);
    rk = rec;  rk.kind = 'SCIENTIFIC';
    [ok, got] = mc_vt_throws(@() mc_record_write(ctx, rk), 'mc:record:kind');
    ch{end+1} = mc_vt_check('record kind and binding mode must agree', ok, got);
    R.checks = [ch{:}];
end

% =====================================================================
function rec = synthetic_record(ctx, condition, trialId, method, pBL)
% A complete Level-A record, as MC_RUN_PAIR writes for M_CONSISTENCY_FAILURE.
    rec.schema        = 'task4_mc_run_record_v2';
    rec.kind          = ctx.record_kind;
    rec.binding       = ctx.binding;
    rec.condition     = condition;
    rec.trial_id      = trialId;
    rec.method        = method;
    rec.trial         = struct('x0', zeros(6, 1), 'q0', [1; 0; 0; 0], 'w0', zeros(3, 1), ...
                               'Idiag', [20; 25; 30], 'I_prev', diag([20 25 30]));
    rec.level_a       = struct('status', 'M_CONSISTENCY_FAILURE', 'hash', [], 'diag', []);
    rec.status        = 'M_CONSISTENCY_FAILURE';
    rec.status_level  = 'A';
    rec.status_rule   = 'A2';
    rec.status_reason = 'synthetic fixture record';
    rec.guard         = struct('status', 'NOT_INVOKED', 'exception', mc_exception_summary([]), ...
                               'n_invocations', 0);
    rec.outputs       = mc_run_outputs(method, condition, 'M_CONSISTENCY_FAILURE', [], [], pBL);
    rec.mask          = struct('evaluated', false);
    rec.attempt       = 0;
    rec.ledger        = struct('started_file', '', 'started_sha256', '', 'post_file', '', ...
                               'post_sha256', '', 'outcome_file', '', 'outcome_sha256', '', ...
                               'recovered', false, 'recovery_decision_sha256', '');
    rec.process       = mc_process_identity();
    rec.shard_id      = 'S1';
    rec.timing        = struct('wall_s', NaN, 'note', 'fixture');
    rec.environment   = struct('matlab_version', version);
    rec.horizon       = struct('Tsim', 1, 'K_expected', 10);
    rec.created_utc   = mc_utc_now();
end

function R = mc_v15_authorisation_bypass(tmpRoot)
% MC_V15_AUTHORISATION_BYPASS  Every exposed lower-level path is refused. NON-SCIENTIFIC.
%   F1  canonical scientific CSV: a SCIENTIFIC-labelled 100-row table through
%       the fixture writer, raw canonical bytes through the atomic writer, the
%       freeze-record path, a scientific-tree file without a scientific
%       context, a SCIENTIFIC table label, the generation transaction in this
%       session - all refused, and results/task4/mc is never created.
%   R-A the issuance registry is not public: the removed public registry
%       refuses, MC_CONTEXT registers only what it issues, and a context that
%       is MUTATED, RE-SEALED and then offered for registration is refused as
%       UNREGISTERED - for that reason, not because this is a verification
%       session (the seal checks precede the session firewall). Every
%       checkpoint writer called outside a guarded boundary is refused for want
%       of a LIVE LEASE, so no write can substitute a seal for live authority.
%   F2  a Condition-M shard before the Condition-U closure, even with every
%       Condition-U record present; a mutated context (horizon, trial row,
%       kind); a re-sealed but unregistered context; no public pair executor.
%   F5  a scientific aggregate from a verification context; scientific records
%       through the non-scientific aggregation primitive.
%   F2/F9  a forged scientific record through the record writer.
%   No controller runs: the one fixture pair replays MC_VT_CAPTURE results.

    R.name = 'V15 authorisation bypass attempts (all refused)';
    ch = {};
    c = mc_constants();
    root = mc_repo_root();
    sciDir = fullfile(root, strrep(c.mc.dest_dir, '/', filesep));
    csvF = fullfile(root, strrep(c.csv.path, '/', filesep));
    frF  = fullfile(root, strrep(c.freeze_record.path, '/', filesep));

    % ---- F1: canonical publication bypasses ----------------------------------------
    T = mc_fixture_trial_table(20260911, c.design.N_PHYSICAL);
    Tf = T;  Tf.kind = 'SCIENTIFIC';                        % a forged label, n = 100, ids 1:100
    [ok, got] = mc_vt_throws(@() mc_trial_csv_write(Tf, csvF), 'mc:csv:protected_path');
    ch{end+1} = mc_vt_check('F1 fixture writer + forged SCIENTIFIC 100-row table -> canonical path refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_trial_csv_write(T, fullfile(sciDir, 'other.csv')), 'mc:csv:protected_path');
    ch{end+1} = mc_vt_check('F1 fixture writer -> anywhere under results/task4/mc refused', ok, got);
    bytes = mc_trial_csv_bytes(Tf);
    [ok, got] = mc_vt_throws(@() mc_atomic_write(csvF, bytes, 'bytes'), 'mc:io:protected_path');
    ch{end+1} = mc_vt_check('F1 atomic writer + canonical bytes -> canonical path refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_atomic_write(frF, uint8('x'), 'bytes'), 'mc:io:protected_path');
    ch{end+1} = mc_vt_check('F1 atomic writer -> freeze-record path refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_atomic_write(fullfile(sciDir, 'checkpoint', 'x.mat'), ...
        struct('x', 1), 'mat'), 'mc:io:protected_path');
    ch{end+1} = mc_vt_check('F1 atomic writer -> scientific tree without a scientific context refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_trial_table_from_U(T.U, 'SCIENTIFIC'), 'mc:trials:kind');
    ch{end+1} = mc_vt_check('F1 a SCIENTIFIC table label cannot be created', ok, got);
    inputs = struct('protocol_sha256', c.protocol.sha256, 'mc_source_aggregate', repmat('0', 1, 64), ...
                    'mc_impl_commit', c.anchor.commit);
    [ok, got] = mc_vt_throws(@() mc_scientific_trial_table(inputs), 'mc:rng:verification_session');
    ch{end+1} = mc_vt_check('F1 the generation transaction itself is refused in this session', ok, got);
    ch{end+1} = mc_vt_check('F1 results/task4/mc, the CSV and the freeze record do not exist', ...
        ~isfolder(sciDir) && ~isfile(csvF) && ~isfile(frF) && ~mc_rng_sentinel('query'));

    % ---- R-A: issuance authority is not public --------------------------------------------
    cap = mc_vt_capture();
    ck = fullfile(tmpRoot, 'v15');
    cnt = containers.Map('KeyType', 'char', 'ValueType', 'double');
    ov = struct('proposed', @(r, a, t) mc_vt_counted(cnt, 'proposed', cap.P), ...
                'nominal_mpc', @(r, a, t) mc_vt_counted(cnt, 'nominal_mpc', cap.Bm), ...
                'apf', @(r, a, t) mc_vt_counted(cnt, 'apf', cap.Ba));
    ctx = mc_context('verification', ck, cap.Tsim, cap.T, 1, struct('runner_override', ov));
    cF = ctx;  cF.kind = 'scientific';  cF.record_kind = 'SCIENTIFIC';
    cF.root = fullfile(sciDir, 'checkpoint');               % a path string only; nothing is created
    cF.seal.digest = mc_context_seal(cF);                   % mutated, then RE-SEALED
    [ok1, g1] = mc_vt_throws(@() mc_context_registry('register', cF.seal.digest), 'mc:registry:removed');
    [ok2, g2] = mc_vt_throws(@() mc_context('register', cF.seal.digest), 'mc:context:kind');
    ch{end+1} = mc_vt_check('R-A no public registration path exists (removed registry, no MC_CONTEXT action)', ...
        ok1 && ok2, sprintf('%s / %s', g1, g2));
    ch{end+1} = mc_vt_check('R-A MC_CONTEXT registers only what it issued', ...
        mc_context('is_issued', ctx.seal.digest) && ~mc_context('is_issued', cF.seal.digest));
    [ok, got] = mc_vt_throws(@() mc_atomic_write(fullfile(cF.root, 'forged.mat'), struct('x', 1), ...
        'mat', struct('ctx', cF)), 'mc:campaign:ctx_unregistered');
    ch{end+1} = mc_vt_check(['R-A a mutated, re-sealed SCIENTIFIC context is refused as UNREGISTERED ' ...
        '(not by the session firewall) and nothing is created'], ok && ~isfolder(sciDir), got);
    [ok, got] = mc_vt_throws(@() mc_record_write(cF, struct()), 'mc:campaign:ctx_unregistered');
    ch{end+1} = mc_vt_check('R-A the record writer refuses it for the same reason', ok, got);

    % ---- R-A: no write outside a guarded boundary (the live lease) --------------------------
    mc_shard_plan(ctx, 'U', {1}, 'fixture-operator');
    mc_shard_plan(ctx, 'M', {1}, 'fixture-operator');
    [ok, got] = mc_vt_throws(@() mc_shard_lock('acquire', ctx, 'U', 'S1'), 'mc:campaign:no_live_authority');
    ch{end+1} = mc_vt_check('R-A the shard lock cannot be taken outside a guarded boundary', ok, got);
    [ok, got] = mc_vt_throws(@() mc_reservation('acquire', ctx, 'U', 1, 'S1'), 'mc:campaign:no_live_authority');
    ch{end+1} = mc_vt_check('R-A a pair reservation cannot be taken outside a guarded boundary', ok, got);
    [ok, got] = mc_vt_throws(@() mc_attempt_ledger('start', ctx, 'U', 1, 'proposed', 1, 'S1'), ...
        'mc:campaign:no_live_authority');
    ch{end+1} = mc_vt_check('R-A the attempt ledger cannot be written outside a guarded boundary', ok, got);
    ch{end+1} = mc_vt_check('R-A no checkpoint artefact was created by those attempts', ...
        ~isfolder(fullfile(ck, 'shard_locks')) && ~isfolder(fullfile(ck, 'reservations')) ...
        && ~isfolder(fullfile(ck, 'attempts')));

    % ---- F2: direct Condition-M before the U closure; mutated contexts ----------------
    mc_run_condition(ctx, 'U', 'S1');
    ch{end+1} = mc_vt_check('fixture: the Condition-U pair recorded all three methods (replayed)', ...
        all(mc_record_scan(ck, 'U', ctx.binding, 1).present));
    n0 = sum(cell2mat(values(cnt)));
    [ok, got] = mc_vt_throws(@() mc_run_pair(ctx, 1, 'M'), 'mc:campaign:no_direct_pair');
    ch{end+1} = mc_vt_check('F2 there is no public pair executor to call directly', ok, got);
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'M', 'S1'), 'mc:closure:missing');
    ch{end+1} = mc_vt_check('F2 Condition-M shard before the U closure refused', ok, got);
    ch{end+1} = mc_vt_check('F2 no method was invoked by the refused M attempts', ...
        sum(cell2mat(values(cnt))) == n0 && ~isfolder(fullfile(ck, 'M')));

    c1 = ctx;  c1.Tsim = 2.9;
    [ok, got] = mc_vt_throws(@() mc_run_condition(c1, 'U', 'S1'), 'mc:campaign:ctx_mutated');
    ch{end+1} = mc_vt_check('F2 mutated horizon refused', ok, got);
    c2 = ctx;  c2.trials.r0(1, 1) = c2.trials.r0(1, 1) + 1e-9;
    [ok, got] = mc_vt_throws(@() mc_run_condition(c2, 'U', 'S1'), 'mc:campaign:ctx_mutated');
    ch{end+1} = mc_vt_check('F2 mutated trial row refused', ok, got);
    c3 = ctx;  c3.kind = 'scientific';
    [ok, got] = mc_vt_throws(@() mc_run_condition(c3, 'U', 'S1'), 'mc:campaign:ctx_mutated');
    ch{end+1} = mc_vt_check('F2 a context relabelled scientific refused', ok, got);
    c4 = c1;  c4.seal.digest = mc_context_seal(c4);
    [ok, got] = mc_vt_throws(@() mc_run_condition(c4, 'U', 'S1'), 'mc:campaign:ctx_unregistered');
    ch{end+1} = mc_vt_check('F2 a re-sealed but unregistered context refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_record_write(c1, struct()), 'mc:campaign:ctx_mutated');
    ch{end+1} = mc_vt_check('F2 the record writer refuses a mutated context', ok, got);

    % ---- F2/F9: forged scientific record ---------------------------------------------------
    recs = load_recs(ck, ctx);
    rf = recs{1};  rf.kind = 'SCIENTIFIC';  rf.binding.mode = 'SCIENTIFIC';
    [ok, got] = mc_vt_throws(@() mc_record_write(ctx, rf), 'mc:campaign:no_live_authority');
    ch{end+1} = mc_vt_check('F2 a forged SCIENTIFIC record outside a boundary is refused for want of a lease', ok, got);
    op = mc_campaign_guard(ctx, 'operator'); %#ok<NASGU>     % a live boundary, to reach the record checks
    [ok, got] = mc_vt_throws(@() mc_record_write(ctx, rf), 'mc:record:binding');
    ch{end+1} = mc_vt_check('F2 a forged SCIENTIFIC record is refused by the record writer', ok, got);
    clear op

    % ---- F5: scientific aggregation bypasses ------------------------------------------------
    [ok, got] = mc_vt_throws(@() mc_aggregate('SCIENTIFIC', ctx, 'U'), 'mc:aggregate:not_scientific');
    ch{end+1} = mc_vt_check('F5 scientific aggregation from a verification context refused', ok, got);
    rs = recs;
    for i = 1:numel(rs), rs{i}.binding.mode = 'SCIENTIFIC'; end
    [ok, got] = mc_vt_throws(@() mc_aggregate('NON_SCIENTIFIC', 'condition', rs, 1), ...
        'mc:aggregate:scientific_records');
    ch{end+1} = mc_vt_check('F5 scientific records through the non-scientific primitive refused', ok, got);
    G = mc_aggregate('NON_SCIENTIFIC', 'condition', recs, 1);
    ch{end+1} = mc_vt_check('F5 a small-n fixture aggregate is stamped NON_SCIENTIFIC', ...
        strcmp(G.scope, 'NON_SCIENTIFIC'));
    R.checks = [ch{:}];
end

% =====================================================================
function recs = load_recs(ck, ctx)
    S = mc_record_scan(ck, 'U', ctx.binding, 1);
    recs = cellfun(@(p) mc_record_read(p, ctx.binding), S.paths, 'UniformOutput', false);
end

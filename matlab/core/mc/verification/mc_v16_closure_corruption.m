function R = mc_v16_closure_corruption(tmpRoot)
% MC_V16_CLOSURE_CORRUPTION  Closure verification is a FULL re-proof (F4, R-B). NON-SCIENTIFIC.
%   A one-trial fixture condition WITH HISTORY - attempt 1 of the proposed
%   method interrupted before POST, an operator ruling, attempt 2 complete
%   (replayed MC_VT_CAPTURE results; no controller runs) - is closed, and the
%   closure verifies. Then each corruption is applied in turn and must make
%   'verify' refuse, and the untouched checkpoint must verify again after each
%   restoration:
%     TERMINAL RECORDS  missing, extra out-of-set, duplicate under another name,
%       wrong binding, content changed after closure, interrupted-write residue
%       appearing after the closure, empty-manifest closure, closure bound
%       elsewhere, unacknowledged incident;
%     HISTORICAL CHAIN (R-B)  the SUPERSEDED attempt's STARTED bytes altered,
%       its ruling's binding altered, its ruling's bound hash altered, its
%       STARTED deleted with the ruling kept, an extra ledger entry beyond the
%       recorded attempt - each refused by the one strict history validator -
%       and a CONSISTENTLY forged chain (STARTED and ruling altered together),
%       which the closure's history binding still detects;
%     WEAKLY SCANNED LOCATIONS (R-B)  a stray file in the checkpoint root, in
%       decisions/ and in shards/, an extra file inside a reservation
%       directory, a released reservation with no release decision, and an
%       orphan acknowledgement.
%   Finally: well-named artefacts of the OTHER condition - concurrent, disjoint
%   work - do NOT make this condition's proof fail.

    R.name = 'V16 closure corruption (full re-proof)';
    ch = {};
    cap = mc_vt_capture();
    ov = struct('proposed', @(r, a, t) cap.P, 'nominal_mpc', @(r, a, t) cap.Bm, ...
                'apf', @(r, a, t) cap.Ba);
    ck = fullfile(tmpRoot, 'v16');
    ctx = mc_context('verification', ck, cap.Tsim, cap.T, 1, struct('runner_override', ov));
    mc_shard_plan(ctx, 'U', {1}, 'fixture-operator');
    mc_fault_hook('arm', 'after_started:proposed');
    [okI, gotI] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), 'mc:fault:injected');
    mc_fault_hook('disarm');
    mc_operator_adjudicate_attempt(ctx, 'U', 1, 'proposed', 1, 'AUTHORISE_NEW_ATTEMPT', ...
        'fixture-operator', 'fixture: interrupted before the controller call');
    mc_run_condition(ctx, 'U', 'S1');
    C = mc_close_condition(ctx, 'U', 'close');
    ch{end+1} = mc_vt_check('a condition with a superseded attempt closes with 3 manifest entries and its history', ...
        okI && C.n_expected == 3 && numel(C.manifest) == 3 && numel(C.history) >= 8, ...
        sprintf('%s; %d history entries', gotI, numel(C.history)));
    ch{end+1} = mc_vt_check('the untouched checkpoint verifies', verifies(ctx));

    U = fullfile(ck, 'U');
    att = fullfile(ck, 'attempts');
    dec = fullfile(ck, 'decisions');
    recA = fullfile(U, 'U_t001_apf.mat');
    bak  = fullfile(tmpRoot, 'v16_apf_backup.mat');
    copyfile(recA, bak);
    closf = fullfile(ck, 'U_CLOSED.mat');
    closBak = fullfile(tmpRoot, 'v16_closure_backup.mat');
    copyfile(closf, closBak);
    fS1 = fullfile(att, 'U_t001_proposed_a1_STARTED.mat');
    fS1Bak = fullfile(tmpRoot, 'v16_started1_backup.mat');
    copyfile(fS1, fS1Bak);
    dR1 = fullfile(dec, 'ADJUDICATE_U_t001_proposed_a1.mat');
    dR1Bak = fullfile(tmpRoot, 'v16_ruling1_backup.mat');
    copyfile(dR1, dR1Bak);

    % ---- terminal records ---------------------------------------------------------
    movefile(recA, fullfile(tmpRoot, 'v16_moved.mat'));
    ch{end+1} = expect_refusal(ctx, 'missing record', 'mc:closure:incomplete');
    movefile(fullfile(tmpRoot, 'v16_moved.mat'), recA);
    copyfile(recA, fullfile(U, 'U_t002_apf.mat'));
    ch{end+1} = expect_refusal(ctx, 'extra out-of-set record', 'mc:closure:unexpected_file');
    delete(fullfile(U, 'U_t002_apf.mat'));
    copyfile(recA, fullfile(U, 'U_t001_apf_copy.mat'));
    ch{end+1} = expect_refusal(ctx, 'duplicate of a logical unit', 'mc:closure:unexpected_file');
    delete(fullfile(U, 'U_t001_apf_copy.mat'));
    copyfile(recA, fullfile(U, 'U_t001_apf.tmp-1-20260911000000000000.mat'));
    ch{end+1} = expect_refusal(ctx, 'interrupted-write residue that appeared after the closure', ...
        'mc:closure:changed');
    delete(fullfile(U, 'U_t001_apf.tmp-1-20260911000000000000.mat'));
    S = load(recA, 'rec');  rec = S.rec;  rec.binding.mc_impl_commit = 'TAMPERED'; %#ok<NASGU>
    delete(recA);  save(recA, 'rec', '-v7');
    ch{end+1} = expect_refusal(ctx, 'wrong-binding record', 'mc:record:binding');
    delete(recA);  copyfile(bak, recA);
    S = load(recA, 'rec');  rec = S.rec;  rec.status_reason = 'edited after closure'; %#ok<NASGU>
    delete(recA);  save(recA, 'rec', '-v7');
    ch{end+1} = expect_refusal(ctx, 'record content changed after closure', 'mc:closure:changed');
    delete(recA);  copyfile(bak, recA);

    % ---- the historical chain (R-B) --------------------------------------------------
    S = load(fS1);  S.attempt.process.nonce = 'ALTERED';
    delete(fS1);  save(fS1, '-struct', 'S', '-v7');
    ch{end+1} = expect_refusal(ctx, 'superseded attempt: STARTED bytes altered', 'mc:ledger:history');
    delete(fS1);  copyfile(fS1Bak, fS1);
    S = load(dR1);  S.decision.binding.mc_impl_commit = 'ALTERED';
    delete(dR1);  save(dR1, '-struct', 'S', '-v7');
    ch{end+1} = expect_refusal(ctx, 'superseded attempt: ruling bound to another campaign', 'mc:ledger:history');
    delete(dR1);  copyfile(dR1Bak, dR1);
    S = load(dR1);  S.decision.started_sha256 = repmat('0', 1, 64);
    delete(dR1);  save(dR1, '-struct', 'S', '-v7');
    ch{end+1} = expect_refusal(ctx, 'superseded attempt: ruling hash no longer its STARTED', 'mc:ledger:history');
    delete(dR1);  copyfile(dR1Bak, dR1);
    movefile(fS1, fullfile(tmpRoot, 'v16_s1.mat'));
    ch{end+1} = expect_refusal(ctx, 'superseded attempt: STARTED removed, ruling kept', 'mc:ledger:history');
    movefile(fullfile(tmpRoot, 'v16_s1.mat'), fS1);
    copyfile(fS1, fullfile(att, 'U_t001_proposed_a3_STARTED.mat'));
    ch{end+1} = expect_refusal(ctx, 'a ledger entry beyond the recorded attempt', 'mc:ledger:history');
    delete(fullfile(att, 'U_t001_proposed_a3_STARTED.mat'));
    S = load(fS1);  S.attempt.process.nonce = 'ALTERED_CONSISTENTLY';
    delete(fS1);  save(fS1, '-struct', 'S', '-v7');
    S = load(dR1);  S.decision.started_sha256 = baseline_sha256(fS1);
    delete(dR1);  save(dR1, '-struct', 'S', '-v7');
    ch{end+1} = expect_refusal(ctx, 'a CONSISTENTLY forged chain (both files altered together)', ...
        'mc:closure:changed');
    delete(fS1);  copyfile(fS1Bak, fS1);
    delete(dR1);  copyfile(dR1Bak, dR1);

    % ---- weakly scanned locations (R-B) ------------------------------------------------
    stray = fullfile(ck, 'stray_root_file.bin');
    write_bytes(stray);
    ch{end+1} = expect_refusal(ctx, 'a stray file in the checkpoint root', 'mc:closure:unexpected_file');
    delete(stray);
    stray = fullfile(dec, 'NOTES.txt');
    write_bytes(stray);
    ch{end+1} = expect_refusal(ctx, 'a stray file in decisions/', 'mc:closure:unexpected_file');
    delete(stray);
    stray = fullfile(ck, 'shards', 'NOTES.txt');
    write_bytes(stray);
    ch{end+1} = expect_refusal(ctx, 'a stray file in shards/', 'mc:closure:unexpected_file');
    delete(stray);
    stray = fullfile(ck, 'reservations', 'U_t001', 'extra.txt');
    write_bytes(stray);
    ch{end+1} = expect_refusal(ctx, 'an extra file inside a reservation directory', 'mc:closure:unexpected_file');
    delete(stray);
    orphanDir = fullfile(ck, 'reservations', 'released', 'U_t001__20260911T000000000');
    mkdir(orphanDir);
    ch{end+1} = expect_refusal(ctx, 'a released reservation with no release decision', ...
        'mc:closure:unexpected_file');
    rmdir(orphanDir);
    ackDir = fullfile(ck, 'acknowledgements');
    if ~isfolder(ackDir), mkdir(ackDir); end
    ackF = fullfile(ackDir, ['ACK_' repmat('a', 1, 64) '.mat']);
    ack = struct('schema', 'task4_mc_incident_ack_v1', 'incident_sha256', repmat('a', 1, 64), ...
        'binding', ctx.binding, 'decision', 'x', 'operator', 'x'); %#ok<NASGU>
    save(ackF, 'ack', '-v7');
    ch{end+1} = expect_refusal(ctx, 'an orphan acknowledgement (its incident is gone)', ...
        'mc:closure:unexpected_file');
    delete(ackF);

    % ---- closure file itself ------------------------------------------------------------
    S = load(closf, 'closure');  closure = S.closure;
    closure.manifest = closure.manifest([]);  closure.manifest_sha256 = mc_value_sha256(closure.manifest); %#ok<STRNU>
    delete(closf);  save(closf, 'closure', '-v7');
    ch{end+1} = expect_refusal(ctx, 'empty-manifest closure', 'mc:closure:malformed');
    delete(closf);  copyfile(closBak, closf);
    S = load(closf, 'closure');  closure = S.closure;  closure.binding.mc_impl_commit = 'ELSEWHERE'; %#ok<STRNU>
    delete(closf);  save(closf, 'closure', '-v7');
    ch{end+1} = expect_refusal(ctx, 'closure bound elsewhere', 'mc:closure:malformed');
    delete(closf);  copyfile(closBak, closf);
    S = load(closf, 'closure');  closure = S.closure;
    closure.history = closure.history(1);  closure.history_sha256 = mc_value_sha256(closure.history); %#ok<STRNU>
    delete(closf);  save(closf, 'closure', '-v7');
    ch{end+1} = expect_refusal(ctx, 'a closure whose history was trimmed', 'mc:closure:changed');
    delete(closf);  copyfile(closBak, closf);

    % ---- unacknowledged incident ----------------------------------------------------------
    incF = fullfile(ck, 'incidents');
    if ~isfolder(incF), mkdir(incF); end
    incident = struct('note', 'fixture incident'); %#ok<NASGU>
    incName = fullfile(incF, 'HARNESS_ERROR_U_t001_FIXTURE_20260911T000000000.mat');
    save(incName, 'incident', '-v7');
    ch{end+1} = expect_refusal(ctx, 'unacknowledged incident', 'mc:campaign:unacknowledged_incident');
    delete(incName);

    ch{end+1} = mc_vt_check('after every restoration the checkpoint verifies again', verifies(ctx));

    % ---- concurrent, disjoint work of the OTHER condition is tolerated ---------------------
    mfile = fullfile(att, 'M_t001_proposed_a1_STARTED.mat');
    copyfile(fS1, mfile);
    copyfile(fS1, fullfile(att, 'M_t001_proposed_a1_STARTED.tmp-7-20260911000000000000.mat'));
    mkdir(fullfile(ck, 'reservations', 'M_t001'));
    copyfile(fullfile(ck, 'reservations', 'U_t001', 'owner.mat'), ...
             fullfile(ck, 'reservations', 'M_t001', 'owner.mat'));
    mkdir(fullfile(ck, 'M'));
    copyfile(recA, fullfile(ck, 'M', 'M_t001_apf.mat'));
    ch{end+1} = mc_vt_check(['well-named Condition-M artefacts (a concurrent, disjoint shard) do not ' ...
        'break the Condition-U proof'], verifies(ctx));
    delete(mfile);
    delete(fullfile(att, 'M_t001_proposed_a1_STARTED.tmp-7-20260911000000000000.mat'));
    delete(fullfile(ck, 'reservations', 'M_t001', 'owner.mat'));
    rmdir(fullfile(ck, 'reservations', 'M_t001'));
    delete(fullfile(ck, 'M', 'M_t001_apf.mat'));
    rmdir(fullfile(ck, 'M'));
    R.checks = [ch{:}];
end

% =====================================================================
function ok = verifies(ctx)
    [ok, ~] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'verify'), 'NO_ERROR');
end

% =====================================================================
function c = expect_refusal(ctx, label, id)
    [ok, got] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'verify'), id);
    c = mc_vt_check(['closure verify refuses: ' label], ok, got);
end

% =====================================================================
function write_bytes(f)
    fid = fopen(f, 'wb');
    fwrite(fid, uint8('x'));
    fclose(fid);
end

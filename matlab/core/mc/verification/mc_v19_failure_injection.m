function R = mc_v19_failure_injection(tmpRoot)
% MC_V19_FAILURE_INJECTION  Crash / failure points around a method attempt (F9, R-D). NON-SCIENTIFIC.
%   No controller runs: the methods are replayed from MC_VT_CAPTURE through
%   verification-only runner overrides that count their calls. For each
%   injection point a fresh checkpoint is used and the shard is re-run
%   afterwards. The rule is the DURABLE EVIDENCE of the attempt, not the
%   operator's wish (MC_ATTEMPT_LEDGER, MC_OPERATOR_ADJUDICATE_ATTEMPT):
%     no attempt marker             the work may start (and does)
%     STARTED, no POST, no incident INTERRUPTED_BEFORE_POST: AMBIGUOUS, the
%                                   controller is NOT invoked again; only
%                                   AUTHORISE_NEW_ATTEMPT is permitted, and that
%                                   no-record resume really works (Sec. 10.4)
%     STARTED, no POST, but an incident OF THAT ATTEMPT (the POST write failed
%                                   after the invocation returned)
%                                   INVOCATION_INCIDENT: acknowledging the incident
%                                   authorises nothing; no ruling is permitted, so a
%                                   known-or-unknown outcome is never re-run
%     POST RETURNED, no OUTCOME     RETURNED_UNCLASSIFIED: no ruling is permitted -
%                                   RETURNED is not proof of scientific success
%     POST of the proposed method's promoted ode45 failure
%                                   PROMOTED_FAILURE_OBSERVED: only RECOVER_RECORD;
%                                   the INTEGRATOR_EXCEPTION record is written from
%                                   POST and the controller is never invoked again
%     POST with any other exception HARNESS_OBSERVED: no ruling is permitted
%     OUTCOME present               OUTCOME_DURABLE: only RECOVER_RECORD; the record
%                                   is rebuilt from the durable outputs, identical
%                                   to the one the uninterrupted run writes
%   Injection points: before STARTED, after STARTED, the controller throwing,
%   after the invocation returns, after POST, during record construction, after
%   OUTCOME, during the record's atomic write, and a failed incident write
%   (reported, never swallowed). A returned baseline NUMERICAL_FAILURE is
%   covered in both windows. Incident acknowledgements are content-bound.

    R.name = 'V19 failure injection around the attempt ledger';
    ch = {};
    cap = mc_vt_capture();
    Pthrow = cap.P;
    Pthrow.guard = rmfield(mc_r18_invoke(@() other_exception()), 'value');
    Pthrow.out = [];
    Ppromoted = cap.P;
    Ppromoted.guard = rmfield(mc_r18_invoke(@() promoted_fail()), 'value');
    Ppromoted.out = [];
    BmFail = cap.Bm;
    BmFail.run.numerically_eligible = false;
    BmFail.run.completed = false;
    BmFail.run.failure_reason = 'fixture: a returned baseline numerical failure';
    BmFail.run.failure_k = 1;
    BmFail.run.nonfinite_fields = {'fixture'};
    ch{end+1} = mc_vt_check('fixture guard statuses: OTHER_EXCEPTION and PROMOTED_ODE45_FAILURE', ...
        strcmp(Pthrow.guard.status, 'OTHER_EXCEPTION') ...
        && strcmp(Ppromoted.guard.status, 'PROMOTED_ODE45_FAILURE'));

    % 1 before STARTED: nothing recorded, the rerun executes
    [ctx, cnt] = new_ctx(tmpRoot, 'before_started', cap, cap.P);
    arm_and_run(ctx, 'before_started:proposed');
    st = mc_attempt_ledger('state', ctx, 'U', 1, 'proposed');
    ch{end+1} = mc_vt_check('before STARTED: no attempt marker, controller not invoked', ...
        strcmp(st.status, 'FRESH') && calls(cnt) == 0, st.status);
    L = mc_run_condition(ctx, 'U', 'S1');
    ch{end+1} = mc_vt_check('before STARTED: the rerun executes all three methods', ...
        strcmp(L.pairs(1).state, 'EXECUTED') && calls(cnt) == 1 && numel(L.pairs(1).written) == 3, ...
        L.pairs(1).state);
    refRec = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'proposed'), ctx.binding);

    % 2 after STARTED (crash before / during invocation): only a new attempt is permitted
    [ctx, cnt] = new_ctx(tmpRoot, 'after_started', cap, cap.P);
    arm_and_run(ctx, 'after_started:proposed');
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 0, 'after STARTED', 'INTERRUPTED_BEFORE_POST');
    [ok, got] = mc_vt_throws(@() rule(ctx, 'RECOVER_RECORD'), 'mc:operator:not_permitted');
    ch{end+1} = mc_vt_check('after STARTED: recovering a record is refused (nothing durable to recover)', ok, got);
    rule(ctx, 'AUTHORISE_NEW_ATTEMPT');
    L = mc_run_condition(ctx, 'U', 'S1');
    recP = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'proposed'), ctx.binding);
    ch{end+1} = mc_vt_check('after an adjudication: attempt 2 runs once and is recorded as attempt 2', ...
        strcmp(L.pairs(1).state, 'EXECUTED') && calls(cnt) == 1 && recP.attempt == 2, ...
        sprintf('attempt %d', recP.attempt));
    [ok, got] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'close'), 'NO_ERROR');
    ch{end+1} = mc_vt_check('the adjudicated history (attempt 1 superseded) re-proves in the closure', ok, got);

    % 3 the controller throws: HARNESS_ERROR, incident, POST written, no ruling permitted
    [ctx, cnt] = new_ctx(tmpRoot, 'throws', cap, Pthrow);
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), 'mc:campaign:harness_error');
    ch{end+1} = mc_vt_check('controller exception -> HARNESS_ERROR with an incident', ...
        ok && numel(dir(fullfile(ctx.root, 'incidents', '*.mat'))) == 1, got);
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), 'mc:campaign:unacknowledged_incident');
    ch{end+1} = mc_vt_check('restart: the unacknowledged incident stops the shard', ok, got);
    ack_all(ctx);
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'controller exception (acknowledged)', 'HARNESS_OBSERVED');
    [ok1, g1] = mc_vt_throws(@() rule(ctx, 'AUTHORISE_NEW_ATTEMPT'), 'mc:operator:reviewer_required');
    [ok2, g2] = mc_vt_throws(@() rule(ctx, 'RECOVER_RECORD'), 'mc:operator:reviewer_required');
    ch{end+1} = mc_vt_check('an observed HARNESS_ERROR permits NO ruling: stopped for the reviewer', ...
        ok1 && ok2, sprintf('%s / %s', g1, g2));

    % 4 after the invocation returns, before POST - a true interruption, no incident:
    %   the Sec. 10.4 no-record resume must still work
    [ctx, cnt] = new_ctx(tmpRoot, 'after_invoke', cap, cap.P);
    arm_and_run(ctx, 'after_invoke:proposed');
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'after invocation, before POST', 'INTERRUPTED_BEFORE_POST');
    ch{end+1} = mc_vt_check('a true interruption leaves no incident of that attempt', ...
        isempty(dir(fullfile(ctx.root, 'incidents', '*.mat'))));
    rule(ctx, 'AUTHORISE_NEW_ATTEMPT');
    L = mc_run_condition(ctx, 'U', 'S1');
    recI = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'proposed'), ctx.binding);
    ch{end+1} = mc_vt_check(['Sec. 10.4 preserved: the interrupted run with no record is rerun from ' ...
        'scratch as attempt 2'], ...
        strcmp(L.pairs(1).state, 'EXECUTED') && calls(cnt) == 2 && recI.attempt == 2, ...
        sprintf('calls %d, attempt %d', calls(cnt), recI.attempt));

    % 4b THE POST LEDGER WRITE FAILS after the invocation returned: the incident of
    %    that attempt is durable, so the missing POST is not an interruption
    [ctx, cnt] = new_ctx(tmpRoot, 'post_write', cap, cap.P);
    arm_and_run(ctx, 'post_write:proposed', 'mc:campaign:harness_error');
    inc = dir(fullfile(ctx.root, 'incidents', '*.mat'));
    Sinc = load(fullfile(inc(1).folder, inc(1).name), 'incident');
    iv = Sinc.incident.invocation;
    ch{end+1} = mc_vt_check(['a failed POST write leaves a HARNESS_ERROR incident that records the ' ...
        'invocation: unit, attempt and guard status'], ...
        numel(inc) == 1 && strcmp(Sinc.incident.stage, 'PROPOSED_POST_WRITE') ...
        && strcmp(iv.unit, 'U_t001_proposed') && iv.attempt == 1 && isequal(iv.returned, true) ...
        && strcmp(iv.guard_status, 'RETURNED') ...
        && ~isfile(fullfile(ctx.root, 'attempts', 'U_t001_proposed_a1_POST.mat')), ...
        sprintf('%s / %s', Sinc.incident.stage, iv.guard_status));
    ack_all(ctx);                                   % a content-bound acknowledgement authorises nothing
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'a failed POST write (acknowledged)', 'INVOCATION_INCIDENT');
    [ok1, g1] = mc_vt_throws(@() rule(ctx, 'AUTHORISE_NEW_ATTEMPT'), 'mc:operator:reviewer_required');
    [ok2, g2] = mc_vt_throws(@() rule(ctx, 'RECOVER_RECORD'), 'mc:operator:reviewer_required');
    ch{end+1} = mc_vt_check(['R-D/F9 acknowledging that incident authorises NO ruling: the returned-but-' ...
        'unrecorded invocation is never re-run'], ...
        ok1 && ok2 && calls(cnt) == 1 && ~isfile(mc_record_path(ctx.root, 'U', 1, 'proposed')) ...
        && numel(dir(fullfile(ctx.root, 'attempts', 'U_t001_proposed_a*_STARTED.mat'))) == 1, ...
        sprintf('%s / %s; calls %d', g1, g2, calls(cnt)));

    % 4c the same window with an OBSERVED promoted ode45 failure
    [ctx, cnt] = new_ctx(tmpRoot, 'post_write_promoted', cap, Ppromoted);
    arm_and_run(ctx, 'post_write:proposed', 'mc:campaign:harness_error');
    inc = dir(fullfile(ctx.root, 'incidents', '*.mat'));
    Sinc = load(fullfile(inc(1).folder, inc(1).name), 'incident');
    ack_all(ctx);
    st = mc_attempt_ledger('state', ctx, 'U', 1, 'proposed');
    [ok1, g1] = mc_vt_throws(@() rule(ctx, 'AUTHORISE_NEW_ATTEMPT'), 'mc:operator:reviewer_required');
    [ok2, ~] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), 'mc:campaign:ambiguous_attempt');
    ch{end+1} = mc_vt_check(['R-D/F9 a promoted ode45 failure whose POST write failed: the incident ' ...
        'records the failure, no ruling is permitted and the controller is never invoked again'], ...
        strcmp(Sinc.incident.invocation.guard_status, 'PROMOTED_ODE45_FAILURE') ...
        && strcmp(st.evidence, 'INVOCATION_INCIDENT') && isempty(st.permitted) && ok1 && ok2 ...
        && calls(cnt) == 1, sprintf('%s; %s; calls %d', st.evidence, g1, calls(cnt)));

    % 5 after POST: the outcome was never made durable
    [ctx, cnt] = new_ctx(tmpRoot, 'after_post', cap, cap.P);
    arm_and_run(ctx, 'after_post:proposed');
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'after POST', 'RETURNED_UNCLASSIFIED');
    [ok1, g1] = mc_vt_throws(@() rule(ctx, 'AUTHORISE_NEW_ATTEMPT'), 'mc:operator:reviewer_required');
    [ok2, g2] = mc_vt_throws(@() rule(ctx, 'RECOVER_RECORD'), 'mc:operator:reviewer_required');
    ch{end+1} = mc_vt_check('RETURNED alone permits NO ruling: neither a rerun nor a recovery', ...
        ok1 && ok2, sprintf('%s / %s', g1, g2));

    % 6 during record construction (before the outputs are durable)
    [ctx, cnt] = new_ctx(tmpRoot, 'record_build', cap, cap.P);
    arm_and_run(ctx, 'record_build:proposed', 'mc:campaign:harness_error');
    ack_all(ctx);
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'during record construction', 'RETURNED_UNCLASSIFIED');

    % 7 after OUTCOME: the record is recovered, identical, with no controller call
    [ctx, cnt] = new_ctx(tmpRoot, 'after_outcome', cap, cap.P);
    arm_and_run(ctx, 'after_outcome:proposed', 'mc:campaign:harness_error');
    ack_all(ctx);
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'after OUTCOME', 'OUTCOME_DURABLE');
    [ok, got] = mc_vt_throws(@() rule(ctx, 'AUTHORISE_NEW_ATTEMPT'), 'mc:operator:not_permitted');
    ch{end+1} = mc_vt_check('a new attempt is refused once the outcome is durable', ok, got);
    rule(ctx, 'RECOVER_RECORD');
    L = mc_run_condition(ctx, 'U', 'S1');
    rec = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'proposed'), ctx.binding);
    ch{end+1} = mc_vt_check(['RECOVER_RECORD rebuilds the record from the durable outputs: attempt 1, ' ...
        'recovered, no controller call, identical outputs and status'], ...
        calls(cnt) == 1 && rec.attempt == 1 && isequal(rec.ledger.recovered, true) ...
        && strcmp(rec.status, refRec.status) && isequaln(rec.outputs, refRec.outputs) ...
        && isequal(L.pairs(1).recovered, {'proposed'}), sprintf('calls %d, attempt %d', calls(cnt), rec.attempt));
    [ok, got] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'close'), 'NO_ERROR');
    ch{end+1} = mc_vt_check('the recovered history re-proves in the closure', ok, got);

    % 8 during the record's atomic write
    [ctx, cnt] = new_ctx(tmpRoot, 'record_write', cap, cap.P);
    arm_and_run(ctx, 'record_atomic_before_rename:proposed', 'mc:campaign:harness_error');
    d = dir(fullfile(ctx.root, 'U'));
    ch{end+1} = mc_vt_check('during the atomic record write: no record and no temporary file remain', ...
        ~any(contains({d.name}, 'U_t001_proposed')));
    ack_all(ctx);
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'during the record atomic write', 'OUTCOME_DURABLE');
    rule(ctx, 'RECOVER_RECORD');
    mc_run_condition(ctx, 'U', 'S1');
    rec = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'proposed'), ctx.binding);
    ch{end+1} = mc_vt_check('a failed record write is recovered from the durable outputs, not re-executed', ...
        calls(cnt) == 1 && isequaln(rec.outputs, refRec.outputs));

    % 9 the incident write itself fails: reported, never swallowed
    [ctx, cnt] = new_ctx(tmpRoot, 'incident_write', cap, cap.P);
    mc_fault_hook('arm', 'record_build:proposed');
    mc_fault_hook('arm', 'incident_write');
    msg = '';
    try
        mc_run_condition(ctx, 'U', 'S1');
    catch ME
        msg = ME.message;
    end
    mc_fault_hook('disarm');
    ch{end+1} = mc_vt_check('a failed incident write is reported in the error', ...
        contains(msg, 'INCIDENT NOT WRITTEN') && isempty(dir(fullfile(ctx.root, 'incidents', '*.mat'))), msg);
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'incident write failed', 'RETURNED_UNCLASSIFIED');

    % 10 an OBSERVED promoted ode45 failure of the proposed method
    [ctx, cnt] = new_ctx(tmpRoot, 'promoted', cap, Ppromoted);
    arm_and_run(ctx, 'after_post:proposed');
    ch{end+1} = restart_is_ambiguous(ctx, cnt, 1, 'observed promoted ode45 failure', 'PROMOTED_FAILURE_OBSERVED');
    [ok, got] = mc_vt_throws(@() rule(ctx, 'AUTHORISE_NEW_ATTEMPT'), 'mc:operator:not_permitted');
    ch{end+1} = mc_vt_check('R-D a new attempt after an OBSERVED failure is refused (no retry of a failed run)', ...
        ok, got);
    rule(ctx, 'RECOVER_RECORD');
    mc_run_condition(ctx, 'U', 'S1');
    rec = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'proposed'), ctx.binding);
    O = load(fullfile(ctx.root, 'attempts', 'U_t001_proposed_a1_OUTCOME.mat'), 'attempt');
    ch{end+1} = mc_vt_check(['R-D the INTEGRATOR_EXCEPTION record is written from POST: attempt 1, ' ...
        'recovered from POST, controller not invoked again, every metric UNKNOWN'], ...
        calls(cnt) == 1 && rec.attempt == 1 && strcmp(rec.status, 'INTEGRATOR_EXCEPTION') ...
        && strcmp(rec.status_rule, 'B2') && strcmp(O.attempt.recovered_from, 'POST') ...
        && strcmp(rec.outputs.metrics.min_h_body.marker, 'UNKNOWN'), ...
        sprintf('calls %d, status %s', calls(cnt), rec.status));
    [ok, got] = mc_vt_throws(@() mc_close_condition(ctx, 'U', 'close'), 'NO_ERROR');
    ch{end+1} = mc_vt_check('the POST-recovered history re-proves in the closure', ok, got);

    % 11 a RETURNED baseline numerical failure, in both windows
    [ctx, cnt] = new_ctx(tmpRoot, 'numfail_ref', cap, cap.P, BmFail);
    mc_run_condition(ctx, 'U', 'S1');
    refNum = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'nominal_mpc'), ctx.binding);
    ch{end+1} = mc_vt_check('a returned baseline numerical failure is a complete record (B2)', ...
        strcmp(refNum.status, 'NUMERICAL_FAILURE') && strcmp(refNum.outputs.base_marker, 'UNKNOWN'));
    [ctx, cnt] = new_ctx(tmpRoot, 'numfail_post', cap, cap.P, BmFail);
    arm_and_run(ctx, 'after_post:nominal_mpc');
    st = mc_attempt_ledger('state', ctx, 'U', 1, 'nominal_mpc');
    [ok1, g1] = mc_vt_throws(@() mc_operator_adjudicate_attempt(ctx, 'U', 1, 'nominal_mpc', 1, ...
        'AUTHORISE_NEW_ATTEMPT', 'fixture-operator', 'try'), 'mc:operator:reviewer_required');
    [ok2, g2] = mc_vt_throws(@() mc_operator_adjudicate_attempt(ctx, 'U', 1, 'nominal_mpc', 1, ...
        'RECOVER_RECORD', 'fixture-operator', 'try'), 'mc:operator:reviewer_required');
    ch{end+1} = mc_vt_check(['R-D a returned baseline numerical failure interrupted BEFORE its outcome ' ...
        'was durable permits no ruling'], ...
        strcmp(st.evidence, 'RETURNED_UNCLASSIFIED') && ok1 && ok2, sprintf('%s; %s / %s', st.evidence, g1, g2));
    [ctx, cnt] = new_ctx(tmpRoot, 'numfail_outcome', cap, cap.P, BmFail);
    arm_and_run(ctx, 'after_outcome:nominal_mpc', 'mc:campaign:harness_error');
    ack_all(ctx);
    mc_operator_adjudicate_attempt(ctx, 'U', 1, 'nominal_mpc', 1, 'RECOVER_RECORD', ...
        'fixture-operator', 'fixture: the outcome is durable');
    mc_run_condition(ctx, 'U', 'S1');
    recN = mc_record_read(mc_record_path(ctx.root, 'U', 1, 'nominal_mpc'), ctx.binding);
    ch{end+1} = mc_vt_check(['R-D with the outcome durable, the NUMERICAL_FAILURE record is recovered ' ...
        'unchanged, never re-executed'], ...
        strcmp(recN.status, 'NUMERICAL_FAILURE') && isequal(recN.ledger.recovered, true) ...
        && isequaln(recN.outputs, refNum.outputs) && recN.attempt == 1);

    % 12 acknowledgements are content-bound
    [ctx, ~] = new_ctx(tmpRoot, 'ack_binding', cap, Pthrow);
    try, mc_run_condition(ctx, 'U', 'S1'); catch, end
    inc = dir(fullfile(ctx.root, 'incidents', '*.mat'));
    f1 = fullfile(inc(1).folder, inc(1).name);
    mc_operator_acknowledge_incident(ctx, f1, 'reviewed', 'fixture-operator');
    incident = struct('note', 'a second incident with the same name pattern'); %#ok<NASGU>
    save(fullfile(inc(1).folder, 'HARNESS_ERROR_U_t001_OTHER_x.mat'), 'incident');
    [ok, got] = mc_vt_throws(@() mc_incident_gate(ctx), 'mc:campaign:unacknowledged_incident');
    ch{end+1} = mc_vt_check('one acknowledgement never covers another incident', ok, got);
    delete(fullfile(inc(1).folder, 'HARNESS_ERROR_U_t001_OTHER_x.mat'));
    [ok, ~] = mc_vt_throws(@() mc_incident_gate(ctx), 'NO_ERROR');
    ch{end+1} = mc_vt_check('the acknowledged incident alone passes the gate', ok);
    fid = fopen(f1, 'ab');  fwrite(fid, uint8(0));  fclose(fid);     % change its bytes
    [ok, got] = mc_vt_throws(@() mc_incident_gate(ctx), 'mc:campaign:unacknowledged_incident');
    ch{end+1} = mc_vt_check('an acknowledgement stops covering an incident whose bytes change', ok, got);
    R.checks = [ch{:}];
end

% =====================================================================
function [ctx, cnt] = new_ctx(tmpRoot, tag, cap, Pprop, Bm)
    if nargin < 5, Bm = cap.Bm; end
    cnt = containers.Map('KeyType', 'char', 'ValueType', 'double');
    ov = struct('proposed', @(r, a, t) mc_vt_counted(cnt, 'proposed', Pprop), ...
                'nominal_mpc', @(r, a, t) mc_vt_counted(cnt, 'nominal_mpc', Bm), ...
                'apf', @(r, a, t) cap.Ba);
    ctx = mc_context('verification', fullfile(tmpRoot, ['v19_' tag]), cap.Tsim, cap.T, 1, ...
                     struct('runner_override', ov));
    mc_shard_plan(ctx, 'U', {1}, 'fixture-operator');
end

function arm_and_run(ctx, point, id)
    if nargin < 3, id = 'mc:fault:injected'; end
    mc_fault_hook('arm', point);
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), id);
    mc_fault_hook('disarm');
    assert(ok, 'mc:vt:injection', 'Injection at %s produced %s, not %s.', point, got, id);
end

function dec = rule(ctx, decision)
    dec = mc_operator_adjudicate_attempt(ctx, 'U', 1, 'proposed', 1, decision, ...
        'fixture-operator', 'fixture: injected interruption');
end

function n = calls(cnt)
    n = 0;
    if isKey(cnt, 'proposed'), n = cnt('proposed'); end
end

function c = restart_is_ambiguous(ctx, cnt, nBefore, label, evidence)
    [ok, got] = mc_vt_throws(@() mc_run_condition(ctx, 'U', 'S1'), 'mc:campaign:ambiguous_attempt');
    st = mc_attempt_ledger('state', ctx, 'U', 1, 'proposed');
    c = mc_vt_check(['restart after "' label '": AMBIGUOUS (' evidence '), controller not re-invoked'], ...
        ok && calls(cnt) == nBefore && strcmp(st.evidence, evidence) ...
        && ~isfile(mc_record_path(ctx.root, 'U', 1, 'proposed')), ...
        sprintf('%s; evidence %s; calls %d (expected %d)', got, st.evidence, calls(cnt), nBefore));
end

function ack_all(ctx)
    inc = dir(fullfile(ctx.root, 'incidents', '*.mat'));
    for i = 1:numel(inc)
        mc_operator_acknowledge_incident(ctx, fullfile(inc(i).folder, inc(i).name), ...
            'reviewed: fixture injection', 'fixture-operator');
    end
end

function y = promoted_fail()
% a stand-in invocation that raises the ONE promoted identifier (Sec. 10.5)
    y = [];
    error('MATLAB:ode45:IntegrationTolNotMet', 'fixture: promoted ode45 failure');
end

function y = other_exception()
    y = [];
    error('mc:fixture:controller_crash', 'fixture: the controller throws');
end

function R = mc_v01_r18_guard(~)
% MC_V01_R18_GUARD  R18 guard fixture (protocol Sec. 10.2, 10.5). NON-SCIENTIFIC.
%   Confirms: the complete warning state is restored after normal return AND
%   after a thrown error; exactly MATLAB:ode45:IntegrationTolNotMet is promoted
%   and caught (synthetic AND a genuine ode45 tolerance failure); unrelated
%   warnings are neither promoted nor suppressed; an unrelated exception maps
%   to HARNESS_ERROR; the operation is invoked exactly once (no retry); a
%   caller's prior state of the promoted identifier is restored exactly; the
%   Level-A guard mapping.

    R.name = 'V01 R18 guard';
    ch = {};
    id = 'MATLAB:ode45:IntegrationTolNotMet';
    cnt = containers.Map('KeyType', 'char', 'ValueType', 'double');

    % (a) normal return
    cnt('n') = 0;  s0 = warning;
    r = mc_r18_invoke(@() op_value(cnt, 42));
    ch{end+1} = mc_vt_check('normal return: RETURNED with the operation value', ...
        strcmp(r.status, 'RETURNED') && isequal(r.value, 42), r.status);
    ch{end+1} = mc_vt_check('normal return: exactly one invocation', ...
        cnt('n') == 1 && r.n_invocations == 1, sprintf('%d', cnt('n')));
    ch{end+1} = mc_vt_check('normal return: complete warning state restored', isequal(warning, s0));

    % (b) synthetic promoted warning
    cnt('n') = 0;  s0 = warning;
    r = mc_r18_invoke(@() op_warn(cnt, id));
    ch{end+1} = mc_vt_check('synthetic IntegrationTolNotMet is promoted and caught', ...
        strcmp(r.status, 'PROMOTED_ODE45_FAILURE') && strcmp(r.exception_info.identifier, id), r.status);
    ch{end+1} = mc_vt_check('promoted failure: exactly one invocation (no retry)', cnt('n') == 1, ...
        sprintf('%d', cnt('n')));
    ch{end+1} = mc_vt_check('thrown error: complete warning state restored', isequal(warning, s0));

    % (c) a GENUINE ode45 tolerance failure: y' = y^2, y(0) = 1 blows up at t = 1
    s0 = warning;  lastwarn('');
    [tt, ~] = ode45(@(t, y) y.^2, [0 2], 1);
    [~, lid] = lastwarn;
    ch{end+1} = mc_vt_check('outside the guard, ode45 only WARNS and returns shortened output', ...
        strcmp(lid, id) && tt(end) < 2, sprintf('lastwarn %s, t_end %.6g', lid, tt(end)));
    ch{end+1} = mc_vt_check('outside the guard, warning state untouched', isequal(warning, s0));
    cnt('n') = 0;  s0 = warning;
    r = mc_r18_invoke(@() op_ode(cnt));
    ch{end+1} = mc_vt_check('genuine ode45 failure inside the guard is promoted and caught', ...
        strcmp(r.status, 'PROMOTED_ODE45_FAILURE') && strcmp(r.exception_info.identifier, id), r.status);
    ch{end+1} = mc_vt_check('genuine failure: one invocation, state restored', ...
        cnt('n') == 1 && isequal(warning, s0));

    % (d) an unrelated warning is neither promoted nor suppressed
    cnt('n') = 0;  s0 = warning;  lastwarn('');
    r = mc_r18_invoke(@() op_unrelated_warn(cnt));
    [~, lid] = lastwarn;
    ch{end+1} = mc_vt_check('unrelated warning: returned normally, warning was issued', ...
        strcmp(r.status, 'RETURNED') && isequal(r.value, 7) && strcmp(lid, 'mc:fixture:unrelated'), lid);
    ch{end+1} = mc_vt_check('unrelated warning: state restored', isequal(warning, s0));

    % (e) an unrelated exception is HARNESS_ERROR for every consumer, no retry
    cnt('n') = 0;  s0 = warning;
    r = mc_r18_invoke(@() op_error(cnt));
    sp = mc_classify_proposed(r.status, [], 8000);
    sb = mc_classify_baseline(r.status, [], 'apf', 8000);
    sa = mc_condition_gate('U', r.status, []);
    ch{end+1} = mc_vt_check('unrelated exception -> OTHER_EXCEPTION -> HARNESS_ERROR (B1 / A0)', ...
        strcmp(r.status, 'OTHER_EXCEPTION') && strcmp(sp, 'HARNESS_ERROR') ...
        && strcmp(sb, 'HARNESS_ERROR') && strcmp(sa, 'HARNESS_ERROR'), [sp '/' sb '/' sa]);
    ch{end+1} = mc_vt_check('unrelated exception: one invocation, state restored', ...
        cnt('n') == 1 && isequal(warning, s0));

    % (f) an operation that rewrites warning states cannot leak them
    s0 = warning;
    mc_r18_invoke(@() op_change_state());
    ch{end+1} = mc_vt_check('states changed inside the operation are fully restored', isequal(warning, s0));

    % (g) a caller's prior 'off' state of the promoted identifier is restored exactly
    sFull = warning;
    warning('off', id);
    s1 = warning;
    cnt('n') = 0;
    r = mc_r18_invoke(@() op_warn(cnt, id));
    q1 = warning('query', id);
    ok = strcmp(r.status, 'PROMOTED_ODE45_FAILURE') && isequal(warning, s1) && strcmp(q1.state, 'off');
    warning(sFull);
    ch{end+1} = mc_vt_check('prior off-state: promoted inside, restored to off after', ok);
    ch{end+1} = mc_vt_check('caller state reinstated after the fixture', isequal(warning, sFull));

    % (h) a promoted failure caught INSIDE the operation (the frozen baseline path) returns
    r = mc_r18_invoke(@() op_internal_catch());
    ch{end+1} = mc_vt_check('an internal try/catch sees the promoted error; the guard sees RETURNED', ...
        strcmp(r.status, 'RETURNED') && strcmp(r.value, id), char(string(r.value)));
    sb = mc_classify_baseline('PROMOTED_ODE45_FAILURE', [], 'apf', 8000);
    ch{end+1} = mc_vt_check('a promoted exception ESCAPING simulate_baseline is HARNESS_ERROR (B1)', ...
        strcmp(sb, 'HARNESS_ERROR'), sb);

    % (i) Level-A guard mapping
    ch{end+1} = mc_vt_check('Level A: promoted failure in the table build -> TARGET_MODEL_INTEGRATION_FAILURE', ...
        strcmp(mc_condition_gate('U', 'PROMOTED_ODE45_FAILURE', []), 'TARGET_MODEL_INTEGRATION_FAILURE') ...
        && strcmp(mc_condition_gate('M', 'PROMOTED_ODE45_FAILURE', []), 'TARGET_MODEL_INTEGRATION_FAILURE'));
    sp = mc_classify_proposed('PROMOTED_ODE45_FAILURE', [], 8000);
    ch{end+1} = mc_vt_check('proposed: promoted exception with no out -> INTEGRATOR_EXCEPTION (B2)', ...
        strcmp(sp, 'INTEGRATOR_EXCEPTION'), sp);

    R.checks = [ch{:}];
end

% =====================================================================
function v = op_value(cnt, v)
    cnt('n') = cnt('n') + 1;
end

function v = op_warn(cnt, id)
    cnt('n') = cnt('n') + 1;
    warning(id, 'fixture: synthetic integration tolerance failure');
    v = 1;
end

function v = op_ode(cnt)
    cnt('n') = cnt('n') + 1;
    [t, ~] = ode45(@(t, y) y.^2, [0 2], 1);
    v = t(end);
end

function v = op_unrelated_warn(cnt)
    cnt('n') = cnt('n') + 1;
    warning('mc:fixture:unrelated', 'fixture: an unrelated warning');
    v = 7;
end

function v = op_error(cnt)
    cnt('n') = cnt('n') + 1;
    error('mc:fixture:boom', 'fixture: an unrelated exception');
    v = 0; %#ok<UNRCH>
end

function v = op_change_state()
    warning('off', 'mc:fixture:changed');
    warning('error', 'mc:fixture:changed_too');
    warning('off', 'MATLAB:singularMatrix');
    v = 1;
end

function v = op_internal_catch()
    try
        [~, ~] = ode45(@(t, y) y.^2, [0 2], 1);
        v = 'NOT_THROWN';
    catch ME
        v = ME.identifier;
    end
end

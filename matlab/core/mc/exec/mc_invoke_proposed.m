function P = mc_invoke_proposed(row, A, Tsim)
% MC_INVOKE_PROPOSED  One guarded invocation of the frozen proposed method.
%   P = mc_invoke_proposed(row, A, Tsim) implements the PROPOSED block of
%   protocol Sec. 5 for the (trial, condition) whose shared Level-A result is A
%   (A.status must be 'TABLES_OK'):
%
%     p_trial = params();  p_trial.target.q0 = q0_i;  p_trial.target.w0 = w0_i;
%     p_trial.target.I = I_true_i;  pT4 = params_task4(p_trial);
%     [the frozen parameter-drift gate of task4_final_800s.m:255-262, re-applied]
%     PRE-RUN   the table supplied IS tabs_ic.tbl_preview, and
%               tabs_ic.identity.preview equals prevIC_ic (q, w and I)
%     out = simulate_task4(pT4, struct('Tsim', Tsim, 'alpha', 1e-3, 'x0', x0_i, ...
%                                      'targetEst', prevIC_ic, 'tbl', tabs_ic.tbl_preview))
%     POST-RUN  when an out is returned: out.config.custom_tbl == true and
%               isequal(out.config.opt.tbl, tabs_ic.tbl_preview) - applied by
%               MC_POSTRUN_CHECK after the POST_EXECUTION ledger entry is written
%
%   The call runs inside MC_R18_INVOKE. A PRE-RUN assertion failure is an
%   integrity failure: it throws an 'mc:integrity:*' error, which the
%   orchestrator records as HARNESS_ERROR and which stops the campaign.
%   allow_eval_x0 and allow_inadmissible_ic are never set.
%
%   P fields: guard (MC_R18_INVOKE result without .value), out (or []),
%   wall_s, act_thresh (the frozen p.cbf.act_thresh used for out.active).

    c = mc_constants();
    assert(strcmp(A.status, 'TABLES_OK'), 'mc:proposed:level_a', ...
        'The proposed method may run only after a TABLES_OK Level-A result.');

    p_trial = params();
    p_trial.target.q0 = row.q0;
    p_trial.target.w0 = row.w0;
    p_trial.target.I  = row.I_true;
    pT4 = params_task4(p_trial);
    drift_gate(pT4);

    tabs   = A.tabs;
    prevIC = A.prevIC;

    % ---- PRE-RUN --------------------------------------------------------
    assert(isequal(tabs.identity.preview.q(:), prevIC.q(:)) ...
        && isequal(tabs.identity.preview.w(:), prevIC.w(:)) ...
        && isequal(tabs.identity.preview.I, prevIC.I), ...
        'mc:integrity:prerun_preview_identity', ...
        'PRE-RUN: tabs_ic.identity.preview does not equal prevIC_ic.');
    opt = struct( ...
          'Tsim',      Tsim, ...
          'alpha',     c.design.alpha, ...
          'x0',        row.x0, ...
          'targetEst', prevIC, ...
          'tbl',       tabs.tbl_preview);
    assert(isequal(opt.tbl, tabs.tbl_preview) && isequal(opt.targetEst, prevIC), ...
        'mc:integrity:prerun_table', 'PRE-RUN: the supplied table is not tabs_ic.tbl_preview.');

    t0 = tic;
    r = mc_r18_invoke(@() simulate_task4(pT4, opt));
    P.wall_s = toc(t0);

    P.out   = [];
    P.guard = rmfield(r, 'value');
    P.act_thresh = pT4.cbf.act_thresh;
    if strcmp(r.status, 'RETURNED')
        % The POST-RUN assertion (MC_POSTRUN_CHECK) is applied by MC_RUN_PAIR
        % only after the POST_EXECUTION ledger entry is durable.
        P.out = r.value;
    end
end

% =====================================================================
function drift_gate(p_base)
% The frozen parameter-drift gate of task4_final_800s.m:255-262, reproduced
% UNCHANGED: identical fields, identical values.
    drift_ok = p_base.t4.s_cap == 0.106226 && p_base.t4.kappa1 == 0.20 && p_base.t4.kappa2 == 0.20 ...
        && p_base.t4.Tw == 1.0 && p_base.t4.M == 50 && p_base.t4.gamma == 100 ...
        && abs(p_base.t4.nu0 - sqrt(3)) < 1e-15 && all(p_base.t4.theta_hat0 == 0) ...
        && p_base.t4.dwell_samples == 0 ...
        && p_base.cbf.k1 == 0.04 && p_base.cbf.k2 == 0.04 && p_base.cbf.delta == 0 ...
        && p_base.chaser.u_max == 0.01 && p_base.ctrl.Ts == 0.1 && p_base.mpc.N == 100 ...
        && abs(p_base.geom.r_safe - 0.70) < 1e-15;
    assert(drift_ok, 'mc:proposed:drift', ...
        'A frozen parameter differs from the freeze record. Refusing to run.');
end

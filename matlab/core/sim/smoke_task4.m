function smoke_task4()
% SMOKE_TASK4  Implementation-level checks for the production Task 4 code.
%
%   THESE ARE IMPLEMENTATION CHECKS ONLY. They establish that the new code
%   executes, that the two-row QP is wired correctly, that the D9 event paths
%   behave as frozen, and that the required diagnostics are logged. They are NOT
%   scientific validation, NOT evidence of closed-loop performance, and NOT a
%   capture-success or handoff-success result. No sweep is run, no alpha is
%   frozen, and no demonstration horizon is selected.
%
%   25 checks: S1, S1b, S2, S3, S4, S7, S11, S12, S13, S14, S5, S8, S6, S9, S15,
%   S10, S16, S17, S18, S19, S20, S21, S22, S23, S24. S1b is a SEPARATE check,
%   not a subcheck of S1.
%
%   D9's outcome taxonomy is NOT extended anywhere in this file. It remains
%   exactly NORMAL, GUARD_BREACH, NO_EVENT. A run refused by the pre-run
%   initial-admissibility gate carries eligibility = 'INELIGIBLE_IC',
%   d9_evaluated = false and the marker event = 'NOT_EVALUATED', which records
%   the ABSENCE of a D9 outcome rather than adding one.
%
%   Checks S5 and S6 use deliberately ARTIFICIAL initial conditions placed in or
%   below the commitment band. They are unit-test fixtures whose only purpose is
%   to execute the NORMAL and GUARD_BREACH code paths. They are not scenarios,
%   and no frozen parameter is altered to produce them.

    thisDir = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(thisDir, '..')));

    p = params_task4();
    fprintf('=============================================================\n');
    fprintf(' TASK 4 PRODUCTION SMOKE CHECKS (implementation only)\n');
    fprintf('=============================================================\n');
    nfail = 0;

    %% S1 - frozen parameters load and match the freeze record
    ok =  abs(p.t4.s_cap  - 0.106226) < 1e-15 ...
       && p.t4.kappa1 == 0.20 && p.t4.kappa2 == 0.20 ...
       && p.t4.Tw == 1.0 && p.t4.M == 50 && p.t4.gamma == 100 ...
       && abs(p.t4.nu0 - sqrt(3)) < 1e-15 ...
       && all(p.t4.theta_hat0 == 0) && p.t4.dwell_samples == 0 ...
       && abs(p.t4.eps_rho - p.t4.alpha*p.t4.s_cap) < 1e-18;
    nfail = report('S1  frozen params load and match the freeze record', ok, nfail);
    fprintf('      s_cap %.6f | kappa %.2f/%.2f | Tw %.1f M %d gamma %d | nu0 %.6f\n', ...
        p.t4.s_cap, p.t4.kappa1, p.t4.kappa2, p.t4.Tw, p.t4.M, p.t4.gamma, p.t4.nu0);
    fprintf('      alpha %.0e (%s) -> eps_rho %.6e m, eps_h %.6e m^2\n', ...
        p.t4.alpha, p.t4.alpha_status, p.t4.eps_rho, p.t4.eps_h);
    ok = ~isfield(p.t4,'s_cap_exact') && ischar(p.t4.s_cap_provenance);
    nfail = report('S1b s_cap has no alternative operative value (provenance is text only)', ok, nfail);
    fprintf('      provenance: %s\n', p.t4.s_cap_provenance);

    %% S2 - single-row two-row solver reproduces the frozen Task 3 filter
    rng_states = [ 0 -10 0  0 0 0; 0.4 -1.2 0.3  0.01 -0.02 0.005;
                   1.0 -0.5 0.2 -0.03 0.01 0.02; -0.6 0.5 0.4 0.02 0.02 -0.01 ].';
    dmax = 0;
    for i = 1:size(rng_states,2)
        xk = rng_states(:,i);
        un = [0.004; -0.009; 0.006];
        [uA, ~] = cbf_qp_filter(xk, un, p);
        [~,~,hd,Lf2,Lg] = safety_function(xk, p, 'cw');
        h = safety_function(xk, p, 'cw');
        row = struct('A', -Lg, 'b', Lf2 + (p.cbf.k1+p.cbf.k2)*hd + p.cbf.k1*p.cbf.k2*h - p.cbf.delta, ...
                     'name', 'body');
        uB = cbf_qp_two_row(row, un, p);
        dmax = max(dmax, norm(uA - uB, inf));
    end
    ok = dmax < 1e-9;
    nfail = report('S2  single-row solver agrees with frozen cbf_qp_filter', ok, nfail);
    fprintf('      max ||u_quadprog - u_bisection||_inf over 4 states = %.3e\n', dmax);

    %% S3 - estimator reproduces the canonical causal headline at t = 200 s
    pt = p;  pt.sim.dt = p.ctrl.Ts;  pt.sim.T_final = 200;
    [tT, ~, wT] = target_tumbling_model(pt);
    rec = cl_records(tT, wT, p);
    est = cl_estimator_init(p);
    for k = 1:numel(tT)
        [est, v] = cl_estimator_step(est, tT(k), rec, p);
    end
    errT = norm(v.theta_hat - p.t4.theta_true);
    ok = rec.n == 200 && abs(v.nu - 0.369600) < 5e-7 && abs(errT - 0.085518) < 5e-7 ...
         && rec.resid < 1e-11;
    nfail = report('S3  estimator matches the canonical causal headline at t=200 s', ok, nfail);
    fprintf('      records %d (expect 200) | regression residual %.3e\n', rec.n, rec.resid);
    fprintf('      nu_sp(200) %.6f (expect 0.369600) | ||theta_tilde(200)|| %.6f (expect 0.085518)\n', ...
        v.nu, errT);

    %% S4 - nominal short run: two rows wired, both enforced, NO_EVENT representable
    o = simulate_task4(p, struct('Tsim', 20));
    bothRows = all(o.cap_enforced) && all(~isnan(o.feas_body)) && all(~isnan(o.feas_cap));
    rowsSat  = all(o.psi2_body >= -1e-9) && all(o.psi2_cap >= -1e-9);
    ok = ~o.aborted && bothRows && rowsSat && ~any(o.qp_infeasible);
    nfail = report('S4  two-row QP wired; both rows enforced and satisfied pre-handoff', ok, nfail);
    fprintf('      steps %d | cap row enforced on %d/%d | min psi2_body %+.3e | min psi2_cap %+.3e\n', ...
        o.K, sum(o.cap_enforced), o.K, min(o.psi2_body), min(o.psi2_cap));
    fprintf('      min individual feas: body %+.3e  cap %+.3e | min joint %+.3e\n', ...
        min(o.feas_body), min(o.feas_cap), min(o.feas_joint));
    fprintf('      capture row active on %d steps, body row active on %d steps\n', ...
        sum(o.row_active_cap), sum(o.row_active_body));

    ok = strcmp(o.event,'NO_EVENT') && isempty(o.handoff) && ~o.handoff_done ...
         && strcmp(o.guard_validation,'PASS');
    nfail = report('S7  NO_EVENT is representable and correctly reported', ok, nfail);
    fprintf('      event %s | guard_validation %s | rho %.4f -> %.4f m (s_cap %.6f)\n', ...
        o.event, o.guard_validation, o.rho(1), o.rho(end), o.s_cap);

    %% S11 - admissible production IC is accepted and its four quantities recorded
    ok = o.ic.admissible && isempty(o.ic.reasons) && o.ic.cap_active_initially ...
         && o.ic.h_body > 0 && o.ic.psi1_body > 0 && o.ic.h_cap > 0 && o.ic.psi1_cap > 0 ...
         && ~o.synthetic && strcmp(o.eligibility,'ELIGIBLE') && o.d9_evaluated;
    nfail = report('S11 (a) admissible production IC accepted, all four recorded', ok, nfail);
    fprintf('      eligibility %s | d9_evaluated %d | D9 outcome %s\n', ...
        o.eligibility, o.d9_evaluated, o.event);
    fprintf('      h_body(0) %+.6e  psi1_body(0) %+.6e\n', o.ic.h_body, o.ic.psi1_body);
    fprintf('      h_cap(0)  %+.6e  psi1_cap(0)  %+.6e  (capture row active initially: %d)\n', ...
        o.ic.h_cap, o.ic.psi1_cap, o.ic.cap_active_initially);

    %% S12 - h_body(0) < 0 must be refused and classified, never counted
    o12 = simulate_task4(p, struct('Tsim', 1, 'x0', [0.30; 0; 0; 0; 0; 0]));
    ok = strcmp(o12.eligibility,'INELIGIBLE_IC') && ~o12.d9_evaluated ...
         && strcmp(o12.event,'NOT_EVALUATED') && ~o12.ic.admissible && o12.aborted ...
         && strcmp(o12.guard_validation,'N/A') && o12.K == 0 ...
         && any(contains(o12.ic.reasons, 'h_body(0)'));
    nfail = report('S12 (b) h_body(0) < 0 refused: INELIGIBLE_IC, D9 NOT_EVALUATED', ok, nfail);
    fprintf('      h_body(0) %+.6e | eligibility %s | D9 %s | guard_validation %s | steps %d\n', ...
        o12.ic.h_body, o12.eligibility, o12.event, o12.guard_validation, o12.K);
    fprintf('      reason: %s\n', strjoin(o12.ic.reasons, ' | '));

    %% S13 - h_body(0) >= 0 but psi1_body(0) < 0 must be refused
    o13 = simulate_task4(p, struct('Tsim', 1, 'x0', [0.72; 0; 0; -0.002; 0; 0]));
    ok = strcmp(o13.eligibility,'INELIGIBLE_IC') && ~o13.d9_evaluated ...
         && strcmp(o13.event,'NOT_EVALUATED') ...
         && o13.ic.h_body >= 0 && o13.ic.psi1_body < 0 ...
         && o13.aborted && strcmp(o13.guard_validation,'N/A') ...
         && any(contains(o13.ic.reasons, 'psi1_body(0)'));
    nfail = report('S13 (c) h_body(0) >= 0 but psi1_body(0) < 0 refused', ok, nfail);
    fprintf('      h_body(0) %+.6e >= 0 | psi1_body(0) %+.6e < 0 | eligibility %s | D9 %s\n', ...
        o13.ic.h_body, o13.ic.psi1_body, o13.eligibility, o13.event);
    fprintf('      reason: %s\n', strjoin(o13.ic.reasons, ' | '));

    %% S14 - capture-row admissibility is checked and recorded when active
    fx14 = band_fixture(p, 0.5*p.t4.eps_rho, -2e-4);   % closes 19x faster than the
    o14  = simulate_task4(p, struct('Tsim', 1, 'x0', fx14));  % envelope permits
    ok = strcmp(o14.eligibility,'INELIGIBLE_IC') && ~o14.d9_evaluated ...
         && strcmp(o14.event,'NOT_EVALUATED') && o14.ic.cap_active_initially ...
         && o14.ic.h_cap >= 0 && o14.ic.psi1_cap < 0 ...
         && any(contains(o14.ic.reasons, 'psi1_cap(0)')) ...
         && strcmp(o14.guard_validation,'N/A');
    nfail = report('S14 (d) capture-row h_cap(0)/psi1_cap(0) checked and recorded', ok, nfail);
    fprintf('      h_cap(0) %+.6e >= 0 | psi1_cap(0) %+.6e < 0 | eligibility %s | D9 %s\n', ...
        o14.ic.h_cap, o14.ic.psi1_cap, o14.eligibility, o14.event);
    fprintf('      reason: %s\n', strjoin(o14.ic.reasons, ' | '));
    fprintf('      NOTE: this fixture is refused by the production rule; it is NOT validation.\n');

    %% S5 - NORMAL path, ADMISSIBLE production fixture (no override used)
    % Closing rate 1e-5 m/s is inside the envelope kappa1*delta at this gap, so
    % psi1_cap(0) >= 0 and the fixture passes the production admissibility gate.
    fx = band_fixture(p, 0.5*p.t4.eps_rho, -1e-5);
    oN = simulate_task4(p, struct('Tsim', 2, 'x0', fx));
    kstar = NaN;
    if ~isempty(oN.handoff), kstar = oN.handoff.k; end
    capOff = ~isnan(kstar) && ~any(oN.cap_enforced(kstar:end));
    capOnBefore = isnan(kstar) || kstar == 1 || all(oN.cap_enforced(1:kstar-1));
    bodyOn = all(~isnan(oN.feas_body)) && all(oN.psi2_body >= -1e-9);
    ok = strcmp(oN.event,'NORMAL') && oN.handoff_done && ~oN.aborted ...
         && capOff && capOnBefore && bodyOn && strcmp(oN.guard_validation,'PASS') ...
         && oN.ic.admissible && ~oN.synthetic;
    nfail = report('S5  NORMAL disables ONLY h_cap; h_body stays enforced; run continues', ok, nfail);
    fprintf('      IC admissible %d (production path, no override) | psi1_cap(0) %+.6e\n', ...
        oN.ic.admissible, oN.ic.psi1_cap);
    fprintf('      fired at k=%d t=%.2f s | rho %.9f in [%.9f, %.9f] | rho_dot %+.3e\n', ...
        kstar, oN.handoff.t, oN.handoff.rho, p.t4.s_cap, p.t4.s_cap+p.t4.eps_rho, oN.handoff.rho_dot);
    fprintf('      cap enforced after handoff: %d steps (expect 0) | steps after handoff: %d\n', ...
        sum(oN.cap_enforced(kstar:end)), oN.K - kstar + 1);
    fprintf('      min psi2_body over the whole run %+.3e (body row still enforced)\n', min(oN.psi2_body));

    %% S8 - required D9 diagnostics are all logged at the firing sample
    need = {'t','k','event','rho','rho_dot','v_rel_cp','nu','h_body','psi1_body', ...
            'h_cap','psi1_cap','alpha','eps_rho'};
    have = isfield(oN.handoff, need);
    ok = all(have) && all(structfun(@(z) ~isempty(z), rmfield(oN.handoff,'event')));
    nfail = report('S8  all frozen D9 firing-sample diagnostics are logged', ok, nfail);
    fprintf('      missing: %s\n', strjoin(need(~have), ', '));
    fprintf('      t=%.3f k=%d %s rho=%.9f rho_dot=%+.3e |v-v_cp|=%.6e nu=%.6f\n', ...
        oN.handoff.t, oN.handoff.k, oN.handoff.event, oN.handoff.rho, ...
        oN.handoff.rho_dot, oN.handoff.v_rel_cp, oN.handoff.nu);
    fprintf('      h_body=%.6e psi1_body=%.6e h_cap=%.6e psi1_cap=%.6e alpha=%.0e eps_rho=%.6e\n', ...
        oN.handoff.h_body, oN.handoff.psi1_body, oN.handoff.h_cap, ...
        oN.handoff.psi1_cap, oN.handoff.alpha, oN.handoff.eps_rho);

    %% S6 - GUARD_BREACH path
    % First the detector predicate itself, as a pure unit test:
    evb = handoff_detector(0.5*p.t4.s_cap, -1e-4, false, p);
    evn = handoff_detector(0.5*p.t4.s_cap, -1e-4, true,  p);   % already handed off
    %
    % Then the run-level machinery. NOTE: a GUARD_BREACH is NOT RULED OUT from an
    % initially admissible condition. Because no sampled-data or intersample
    % invariance theorem is established for this design, an initially admissible
    % sampled trajectory may still later produce a sampled GUARD_BREACH - through
    % an intersample excursion, sampled implementation effects, truth/model
    % mismatch, QP or input-feasibility issues, or numerical effects. No such
    % trajectory has been exhibited, so its existence is not asserted; equally,
    % nothing here claims that sampled enforcement precludes a breach. The
    % synthetic override below is used only because it exercises the termination
    % path deterministically in a unit test; it is a CODE-PATH test and implies
    % nothing about how likely or unlikely a real breach is. Such a run is
    % stamped synthetic and can never yield a verdict.
    fxb = band_fixture(p, -0.5*p.t4.s_cap, -2e-4);
    oB  = simulate_task4(p, struct('Tsim', 2, 'x0', fxb, 'allow_inadmissible_ic', true));
    ok = strcmp(evb,'GUARD_BREACH') && strcmp(evn,'NONE') ...
         && strcmp(oB.event,'GUARD_BREACH') && oB.aborted && ~oB.handoff_done ...
         && isempty(oB.handoff) && ~isempty(oB.event_log) ...
         && strcmp(oB.event_log.event,'GUARD_BREACH') ...
         && oB.synthetic && startsWith(oB.guard_validation,'N/A');
    nfail = report('S6  GUARD_BREACH: predicate + termination path (synthetic, no verdict)', ok, nfail);
    fprintf('      detector predicate: rho<s_cap -> %s ; after handoff -> %s\n', evb, evn);
    fprintf('      synthetic %d | guard_validation forced to: %s\n', oB.synthetic, oB.guard_validation);
    fprintf(['      event %s | guard_validation %s | aborted %d | handoff_done %d ' ...
             '| out.handoff empty %d\n'], ...
        oB.event, oB.guard_validation, oB.aborted, oB.handoff_done, isempty(oB.handoff));
    fprintf('      rho at breach %.9f < s_cap %.9f | control steps retained %d\n', ...
        oB.event_log.rho, p.t4.s_cap, oB.K);
    fprintf('      reason: %s\n', oB.abort_reason);

    %% S9 - INDEPENDENT F5 REPLAY: both frozen branches, cases A-E
    % The scan replays the frozen D9 predicates over independently rebuilt
    % geometry. It must catch a classification disagreement, not only a sampled
    % h_cap violation - an erroneous NORMAL produces no negative h_cap at all.
    sN = f5_hcap_scan(oN, p);  sB = f5_hcap_scan(oB, p);  sO = f5_hcap_scan(o, p);

    % (A) detector reports a FALSE NORMAL that the independent replay does not see
    oFalseN = o;  oFalseN.event = 'NORMAL';
    sA = f5_hcap_scan(oFalseN, p);
    okA = strcmp(sA.independent_event,'NO_EVENT') && ~sA.classification_agree ...
          && sA.F5 && strcmp(sA.F5_branch,'classification-disagreement') ...
          && ~sA.breach_found;

    % (B) detector MISSES a NORMAL that the independent replay does see
    oMissN = oN;  oMissN.event = 'NO_EVENT';  oMissN.handoff = [];
    sBm = f5_hcap_scan(oMissN, p);
    okB = strcmp(sBm.independent_event,'NORMAL') && ~sBm.classification_agree ...
          && sBm.F5 && strcmp(sBm.F5_branch,'classification-disagreement');

    % (C) correct NORMAL -> no disagreement branch
    okC = strcmp(sN.independent_event,'NORMAL') && sN.classification_agree ...
          && ~sN.breach_found && ~sN.F5 && strcmp(sN.F5_branch,'none');

    % (D) correct NO_EVENT -> no disagreement branch
    okD = strcmp(sO.independent_event,'NO_EVENT') && sO.classification_agree ...
          && ~sO.F5 && strcmp(sO.F5_branch,'none');

    % (E) correct GUARD_BREACH -> sampled-violation branch still fires
    okE = strcmp(sB.independent_event,'GUARD_BREACH') && sB.classification_agree ...
          && sB.breach_found && sB.F5 && strcmp(sB.F5_branch,'sampled-violation');

    okM = max([sO.max_rho_mismatch, sN.max_rho_mismatch, sB.max_rho_mismatch]) < 1e-12;
    ok = okA && okB && okC && okD && okE && okM;
    nfail = report('S9  independent F5 replay: h_cap branch AND classification branch', ok, nfail);
    fprintf('      (A) false NORMAL   : independent %-12s detector %-12s F5=%d %s\n', ...
        sA.independent_event, sA.detector_event, sA.F5, sA.F5_branch);
    fprintf('      (B) missed NORMAL  : independent %-12s detector %-12s F5=%d %s\n', ...
        sBm.independent_event, sBm.detector_event, sBm.F5, sBm.F5_branch);
    fprintf('      (C) correct NORMAL : independent %-12s at k=%d rho %.9f rho_dot %+.3e F5=%d %s\n', ...
        sN.independent_event, sN.independent_event_k, sN.event_rho, sN.event_rho_dot, sN.F5, sN.F5_branch);
    fprintf('      (D) correct none   : independent %-12s detector %-12s F5=%d %s\n', ...
        sO.independent_event, sO.detector_event, sO.F5, sO.F5_branch);
    fprintf('      (E) correct BREACH : independent %-12s at k=%d h_cap %+.6e F5=%d %s\n', ...
        sB.independent_event, sB.independent_event_k, sB.event_h_cap, sB.F5, sB.F5_branch);
    fprintf('      rho cross-check (independent vs production path): max %.2e\n', ...
        max([sO.max_rho_mismatch, sN.max_rho_mismatch, sB.max_rho_mismatch]));

    %% S15 - QP-FAILURE BOOKKEEPING (regression for the output-slicing defect)
    % Under the previous code the failing step was cut away by idx = 1:kEnd, so
    % out.qp_infeasible could never contain a true and F3 could never fire. This
    % check FAILS on that code and PASSES on the corrected bookkeeping.
    %
    % The fixture rides the capture envelope (psi1_cap = 0) at rho = 2 m, where
    % the capture row is individually infeasible.
    %
    % EMPIRICAL OBSERVATION FROM THE FIXTURE SEARCH, not a result: all eight
    % probed immediately QP-infeasible states (rho in {1.5, 2.0, 2.5, 3.0} m,
    % two offset directions each) were body-INADMISSIBLE, with psi1_body from
    % -3.35e-01 to -1.73e+00. This is a statement about eight probed states. It
    % is NOT a set-based feasibility result and NOT a proof that admissible
    % states cannot produce QP infeasibility. O2 remains empirically supported on
    % screened trajectories and NOT formally closed.
    %
    % Consequently the synthetic override is needed to reach the QP here, and
    % this check is a BOOKKEEPING test.
    fx15 = envelope_fixture(p, 2.0, [1;0;0]);
    o15  = simulate_task4(p, struct('Tsim', 1, 'x0', fx15, ...
                                    'allow_inadmissible_ic', true));
    qf = o15.qp_failure;
    ok = qf.occurred && qf.k == 1 && qf.cap_active && ~qf.feasible ...
         && ~isempty(qf.feas_margin) && numel(qf.feas_margin) == 2 ...
         && qf.feas_margin(2) < 0 && ~isempty(qf.joint_margin) ...
         && o15.K_applied == 0 && o15.K_evaluated == 1 && o15.aborted;
    nfail = report('S15 QP-failure record survives output slicing (F3 regression)', ok, nfail);
    fprintf('      occurred %d | k %d | t %.3f | cap_active %d | exitflag %d\n', ...
        qf.occurred, qf.k, qf.t, qf.cap_active, qf.exitflag);
    fprintf('      individual margins: %s %+.4e | %s %+.4e | joint %+.4e\n', ...
        qf.row_names{1}, qf.feas_margin(1), qf.row_names{2}, qf.feas_margin(2), qf.joint_margin);
    fprintf('      K_applied %d (no command applied at the failing step), K_evaluated %d\n', ...
        o15.K_applied, o15.K_evaluated);
    fprintf('      per-step array length %d -> the failing step is NOT in it, by design\n', ...
        numel(o15.qp_infeasible));

    %% S10 - classifier on a WELL-FORMED three-alpha fixture, plus negatives
    % Three 20 s runs carrying exactly the predeclared alpha set. This is a
    % CLASSIFIER WIRING fixture, not the alpha sweep: 20 s is not a diagnostic
    % horizon and the outcome below is not reported as sweep evidence.
    rr = [];  ss = [];
    for a = p.t4.alpha_set
        ra = simulate_task4(p, struct('Tsim', 20, 'alpha', a));
        rr = [rr ra];  ss = [ss f5_hcap_scan(ra, p)];  %#ok<AGROW>
    end
    cA = task4_classify(rr, ss, p);

    % negatives - each must be refused, never classified
    neg = struct('name', {}, 'id', {}, 'got', {});
    neg(end+1) = try_classify('only two alphas',   rr(1:2), ss(1:2), p);
    rdup = rr; rdup(3) = rr(1);  sdup = ss; sdup(3) = ss(1);
    neg(end+1) = try_classify('duplicate alpha',   rdup, sdup, p);
    rfor = rr; rfor(2).alpha = 5e-3;
    neg(end+1) = try_classify('foreign alpha',     rfor, ss, p);
    rcfg = rr; rcfg(2).config.opt.Tsim = 40;
    neg(end+1) = try_classify('mismatched Tsim',   rcfg, ss, p);
    rcfg2 = rr; rcfg2(3).config.opt.x0 = rr(3).config.opt.x0 + [0;0;0;0;0;1e-6];
    neg(end+1) = try_classify('mismatched x0',     rcfg2, ss, p);
    rsyn = rr; rsyn(3) = oB;  ssyn = ss; ssyn(3) = sB;
    neg(end+1) = try_classify('synthetic run',     rsyn, ssyn, p);

    % A well-formed sweep whose shared initial condition is inadmissible: all
    % three alphas replay the SAME run, so all three are refused at the gate and
    % their configurations match. This is the realistic INELIGIBLE case, and it
    % must be reported as an outcome, not raised as an error.
    ri = [];  si = [];
    for a = p.t4.alpha_set
        rq = simulate_task4(p, struct('Tsim', 1, 'alpha', a, ...
                                      'x0', [0.30; 0; 0; 0; 0; 0]));
        ri = [ri rq];  si = [si f5_hcap_scan(rq, p)];  %#ok<AGROW>
    end
    cI = task4_classify(ri, si, p);                 % INELIGIBLE, not an error

    ok = strcmp(cA.outcome,'INCONCLUSIVE') && ~cA.F1 && ~cA.F2 && ~cA.F3 && ~cA.F5 ...
         && strcmp(cI.outcome,'INELIGIBLE') && all(~cellfun(@isempty, {neg.id}));
    nfail = report('S10 classifier: well-formed 3-alpha fixture + 6 negative checks', ok, nfail);
    fprintf('      alphas [%s] -> %-12s F1=%d F2=%d F3=%d F4=%d F5=%d\n', ...
        num2str([rr.alpha], '%g '), cA.outcome, cA.F1, cA.F2, cA.F3, cA.F4, cA.F5);
    fprintf('      one INELIGIBLE_IC   -> %-12s (outside the D9 taxonomy; no F-trigger)\n', cI.outcome);
    for i = 1:numel(neg)
        fprintf('      refused: %-18s -> %s\n', neg(i).name, neg(i).id);
    end

    %% S16 - F3 fires from the run-level QP-failure record (classifier unit test)
    % Struct-level fixture: no admissible-IC trajectory that is QP-infeasible
    % exists (see S15), so the classifier's F3 branch is exercised by injecting
    % the record into an otherwise valid run.
    rF = rr;
    rF(2).qp_failure.occurred   = true;
    rF(2).qp_failure.cap_active = true;
    cF = task4_classify(rF, ss, p);
    % and the same record with the capture row already handed off must NOT fire
    rG = rr;
    rG(2).qp_failure.occurred   = true;
    rG(2).qp_failure.cap_active = false;
    cG = task4_classify(rG, ss, p);
    ok = cF.F3 && strcmp(cF.outcome,'FAIL') && ~cG.F3 && ~strcmp(cG.outcome,'FAIL');
    nfail = report('S16 F3 fires from qp_failure when cap active, not when inactive', ok, nfail);
    fprintf('      cap_active=true  -> F3=%d outcome %s\n', cF.F3, cF.outcome);
    fprintf('      cap_active=false -> F3=%d outcome %s (frozen F3 is cap-active only)\n', ...
        cG.F3, cG.outcome);

    %% S17 - intersample h_cap uses the MOVING capture point
    % Independently reconstructs the capture-point trajectory on its own fine
    % grid and compares against the stored diagnostic. The second figure is the
    % discriminating one: it is what the stored values WOULD have been under the
    % previous code, which held p_cp(t_k) fixed across the control interval.
    r17 = intersample_residual(o, p, 20);
    ok = r17.max_err < 1e-12 && r17.max_stale_gap > 1e-6;
    nfail = report('S17 intersample h_cap uses p_cp(t_sub), not the stale p_cp(t_k)', ok, nfail);
    fprintf('      samples %d over t = %.2f .. %.2f s\n', r17.n, r17.t1, r17.t2);
    fprintf('      stored vs independent reconstruction (moving p_cp): max err %.3e\n', r17.max_err);
    fprintf('      stored vs the STALE p_cp(t_k) variant             : max gap %.3e\n', r17.max_stale_gap);
    fprintf('      capture point moves up to %.3e m within one control interval\n', r17.max_pcp_move);

    %% S18 - horizon default removed; alpha locked to the predeclared set
    e1 = try_err(@() simulate_task4(p, struct('x0', [0;-10;0;0;0;0])));
    e2 = try_err(@() simulate_task4(p, struct('Tsim', 5, 'alpha', 5e-3)));
    e3 = try_err(@() simulate_task4(p, struct('Tsim', 5, 'alpha', 1e-3)));  % allowed
    ok = strcmp(e1,'simulate_task4:Tsim') && strcmp(e2,'simulate_task4:alpha') && isempty(e3);
    nfail = report('S18 Tsim is required; alpha restricted to the predeclared set', ok, nfail);
    fprintf('      omitted Tsim      -> %s\n', e1);
    fprintf('      alpha = 5e-3      -> %s\n', e2);
    fprintf('      alpha = 1e-3      -> accepted (development default, NOT final-frozen)\n');

    %% S19 - D9 IS EVALUATED AT THE TERMINAL SAMPLE (regression)
    % The detector used to run only inside k = 1..K, so a run whose FINAL sample
    % satisfied the NORMAL trigger was misreported as NO_EVENT. These fixtures
    % are SYNTHETIC: their closing rates violate the capture envelope, so they
    % need the override. They are code-path tests, not scenarios.
    oTN = simulate_task4(p, struct('Tsim', 0.1, 'alpha', 1e-2, ...
            'x0', terminal_fixture(p, 2.0e-3, 1.2e-2), 'allow_inadmissible_ic', true));
    oTB = simulate_task4(p, struct('Tsim', 0.1, 'alpha', 1e-2, ...
            'x0', terminal_fixture(p, 1.2e-3, 2.0e-2), 'allow_inadmissible_ic', true));
    okN = strcmp(oTN.event,'NORMAL') && oTN.handoff_done && ~isempty(oTN.handoff) ...
          && oTN.handoff.k == oTN.K_applied + 1 && strcmp(oTN.events{1},'NONE');
    okB = strcmp(oTB.event,'GUARD_BREACH') && ~oTB.handoff_done && isempty(oTB.handoff) ...
          && ~isempty(oTB.event_log) && strcmp(oTB.events{1},'NONE');
    okX = strcmp(o.event,'NO_EVENT') && o.K_detector == o.K_applied + 1;
    ok = okN && okB && okX;
    nfail = report('S19 D9 evaluated at the terminal sample (NORMAL / BREACH / none)', ok, nfail);
    fprintf('      (a) terminal NORMAL : in-loop sample %s -> terminal %s at k=%d, rho %.9f\n', ...
        oTN.events{1}, oTN.event, oTN.handoff.k, oTN.handoff.rho);
    fprintf('          band [%.9f, %.9f] | rho_dot %+.3e | nu %.6f\n', ...
        oTN.s_cap, oTN.s_cap + oTN.eps_rho, oTN.handoff.rho_dot, oTN.handoff.nu);
    fprintf('      (b) terminal BREACH : in-loop sample %s -> terminal %s, rho %.9f < s_cap %.9f\n', ...
        oTB.events{1}, oTB.event, oTB.event_log.rho, oTB.s_cap);
    fprintf('      (c) terminal none   : %s, detector samples %d = K_applied %d + 1\n', ...
        o.event, o.K_detector, o.K_applied);

    %% S20 - COUNTER SEMANTICS ARE DISTINCT AND CORRECT
    okQ = o15.K_applied == 0 && o15.K_evaluated == 1 && o15.K_detector == 1;
    okG = oB.K_applied  == 0 && oB.K_evaluated  == 0 && oB.K_detector  == 1;
    okC = o.K_applied == o.K && o.K_evaluated == o.K && o.K_detector == o.K + 1;
    ok = okQ && okG && okC;
    nfail = report('S20 K_applied / K_evaluated / K_detector have distinct semantics', ok, nfail);
    fprintf('      QP failure at k=1   : applied %d, QPs evaluated %d, detector %d\n', ...
        o15.K_applied, o15.K_evaluated, o15.K_detector);
    fprintf('      pre-QP breach at k=1: applied %d, QPs evaluated %d (QP never ran), detector %d\n', ...
        oB.K_applied, oB.K_evaluated, oB.K_detector);
    fprintf('      completed run       : applied %d, QPs evaluated %d, detector %d (incl. terminal)\n', ...
        o.K_applied, o.K_evaluated, o.K_detector);

    %% S21 - ESTIMATOR END-STATE MATCHES THE ACTUAL TRAJECTORY END TIME
    okQ = o15.estimator.t_end == 0 && o15.estimator.E_end == 0 ...
          && all(o15.estimator.theta_hat_end == 0) ...
          && abs(o15.estimator.nu_end - p.t4.nu0) < 1e-15;
    okG = oB.estimator.t_end == 0 && oB.estimator.E_end == 0 ...
          && abs(oB.estimator.nu_end - p.t4.nu0) < 1e-15;
    okC = abs(o.estimator.t_end - o.t(end)) < 1e-12 && o.estimator.E_end >= 0;
    ok = okQ && okG && okC;
    nfail = report('S21 estimator end-state corresponds to the real trajectory end', ok, nfail);
    fprintf('      QP failure at k=1   : t_end %.3f s, E_end %.6e, nu_end %.6f (no interval executed)\n', ...
        o15.estimator.t_end, o15.estimator.E_end, o15.estimator.nu_end);
    fprintf('      pre-QP breach at k=1: t_end %.3f s, E_end %.6e, nu_end %.6f\n', ...
        oB.estimator.t_end, oB.estimator.E_end, oB.estimator.nu_end);
    fprintf('      completed 20 s run  : t_end %.3f s (traj end %.3f), E_end %.6e, nu_end %.6f\n', ...
        o.estimator.t_end, o.t(end), o.estimator.E_end, o.estimator.nu_end);

    %% S22 - Tsim GRID CONSISTENCY AND INPUT-INTEGRITY GUARDS
    g = {};
    g{end+1} = {'Tsim off-grid 0.15 s', try_err(@() simulate_task4(p, struct('Tsim', 0.15)))};
    g{end+1} = {'N not an integer',     try_err(@() simulate_task4(p, struct('Tsim', 1, 'N', 10.5)))};
    g{end+1} = {'n_sub = 0',            try_err(@() simulate_task4(p, struct('Tsim', 1, 'n_sub', 0)))};
    g{end+1} = {'x0 has 5 elements',    try_err(@() simulate_task4(p, struct('Tsim', 1, 'x0', zeros(5,1))))};
    g{end+1} = {'x0 contains NaN',      try_err(@() simulate_task4(p, struct('Tsim', 1, 'x0', [NaN;0;0;0;0;0])))};
    g{end+1} = {'alpha = Inf',          try_err(@() simulate_task4(p, struct('Tsim', 1, 'alpha', Inf)))};
    ok = all(cellfun(@(z) ~isempty(z{2}), g));
    nfail = report('S22 Tsim must be grid-consistent; input-integrity guards fire', ok, nfail);
    for i = 1:numel(g)
        fprintf('      %-22s -> %s\n', g{i}{1}, g{i}{2});
    end

    %% S23 - CONFIG COMPLETENESS: trajectory-generating inputs are all compared
    % Each differs from the sweep only in something the previous curated config
    % did NOT record, so each would previously have been accepted.
    neg2 = struct('name', {}, 'id', {}, 'got', {});
    rT = rr;  rT(2).config.p.target.w0 = rr(2).config.p.target.w0 * 1.001;
    neg2(end+1) = try_classify('truth target w0',  rT, ss, p);
    rJ = rr;  rJ(2).config.p.target.I(1,1) = rr(2).config.p.target.I(1,1) + 1e-9;
    neg2(end+1) = try_classify('truth inertia',    rJ, ss, p);
    rO = rr;  rO(3).config.p.orbit.alt = rr(3).config.p.orbit.alt + 1;
    neg2(end+1) = try_classify('orbit altitude',   rO, ss, p);
    rC = rr;  rC(2).config.custom_tbl = true;
    rC(2).config.opt.tbl = struct('t', 0, 'pL', [0;0;0], 'vL', [0;0;0], 'nL', [1;0;0], 'Ts', 0.1);
    neg2(end+1) = try_classify('custom preview tbl', rC, ss, p);
    ok = all(~cellfun(@isempty, {neg2.id}));
    nfail = report('S23 config covers truth target, orbit and preview-table identity', ok, nfail);
    for i = 1:numel(neg2)
        fprintf('      refused: %-20s -> %s\n', neg2(i).name, neg2(i).id);
    end

    %% S24 - SCAN/RUN BINDING: permuted, cross-alpha and SAME-ALPHA stale scans
    % source_alpha alone cannot separate two runs that share an alpha but differ
    % in configuration, so the scan carries the full source configuration.
    sPerm = ss([2 1 3]);
    nA = try_classify('permuted scans',      rr, sPerm, p);
    sX  = ss;  sX(2) = ss(3);
    nB = try_classify('cross-alpha stale',   rr, sX, p);

    % SAME-ALPHA stale scan: a second run with the SAME alpha but a different
    % trajectory-generating configuration. Its scan carries source_alpha = 1e-3
    % exactly like the real one, so only the source_config binding can catch it.
    rStale = simulate_task4(p, struct('Tsim', 10, 'alpha', 1e-3));
    sStale = f5_hcap_scan(rStale, p);
    sSame  = ss;  sSame(2) = sStale;
    nC = try_classify('SAME-alpha stale',    rr, sSame, p);

    % and a p that does not belong to the run must be refused by the scan itself
    pAlien = p;  pAlien.orbit.alt = p.orbit.alt + 1;
    idP = try_err(@() f5_hcap_scan(rr(2), pAlien));

    ok = strcmp(nA.id,'task4_classify:scan_align') ...
         && strcmp(nB.id,'task4_classify:scan_align') ...
         && strcmp(nC.id,'task4_classify:scan_source') ...
         && strcmp(idP,'f5_hcap_scan:p_mismatch') ...
         && sStale.source_alpha == rr(2).alpha;
    nfail = report('S24 scans bound to the EXACT source run (alpha + configuration)', ok, nfail);
    fprintf('      scan source_alpha values: [%s] vs run alphas [%s]\n', ...
        num2str([ss.source_alpha], '%g '), num2str([rr.alpha], '%g '));
    fprintf('      permuted scans     -> %s\n', nA.id);
    fprintf('      cross-alpha stale  -> %s\n', nB.id);
    fprintf('      SAME-alpha stale   -> %s  (source_alpha %g == run alpha %g, config differs)\n', ...
        nC.id, sStale.source_alpha, rr(2).alpha);
    fprintf('      alien p to scan    -> %s\n', idP);

    fprintf('-------------------------------------------------------------\n');
    if nfail == 0
        fprintf(' ALL IMPLEMENTATION CHECKS PASSED (implementation only, not validation)\n');
    else
        fprintf(' %d CHECK(S) FAILED\n', nfail);
    end
    fprintf('=============================================================\n');
end

% ===== local functions =====================================================
function x0 = band_fixture(p, gap, closing)
% Artificial initial state at range (s_cap + gap) from the t=0 capture point,
% with a small inward relative velocity. Unit-test fixture only: it exercises a
% code path and is not a scenario. No frozen parameter is modified.
    [~, R_LI, ~] = lvlh_frame(0, p);
    R    = R_LI * quat_to_rotm(p.target.q0);
    pb   = p.target.p_cp_body(:);
    p_cp = R * pb;
    wBL  = p.target.w0(:) - R.'*[0;0;p.orbit.n];
    v_cp = R * cross(wBL, pb);
    e    = p_cp / norm(p_cp);              % radially outward through the capture
                                           % point, so the fixture stays clear of
                                           % the body keep-out sphere
    r0   = p_cp + (p.t4.s_cap + gap) * e;
    v0   = v_cp + closing * e;             % closing < 0 gives rho_dot < 0
    x0   = [r0; v0];
end

function x0 = envelope_fixture(p, rho, e)
% State at range rho from the t=0 capture point, closing exactly at the capture
% envelope rate so psi1_cap = 0. At rho of a couple of metres the capture row is
% individually infeasible there. Unit-test fixture only.
    e = e(:)/norm(e);
    [~, R_LI, ~] = lvlh_frame(0, p);
    R    = R_LI * quat_to_rotm(p.target.q0);
    pbv  = p.target.p_cp_body(:);
    p_cp = R * pbv;
    wBL  = p.target.w0(:) - R.'*[0;0;p.orbit.n];
    v_cp = R * cross(wBL, pbv);
    vcl  = p.t4.kappa1 * (rho^2 - p.t4.s_cap^2) / (2*rho);   % gives psi1_cap = 0
    x0   = [p_cp + rho*e; v_cp - vcl*e];
end

function x0 = terminal_fixture(p, gap, closing)
% State at range (s_cap + gap) from the t=0 capture point with relative closing
% speed `closing`. Used to place the FIRST sample outside the detection band and
% the TERMINAL sample inside it (or below s_cap). SYNTHETIC: the closing rate
% violates the capture envelope, so the override is required.
    [~, R_LI, ~] = lvlh_frame(0, p);
    R    = R_LI * quat_to_rotm(p.target.q0);
    pbv  = p.target.p_cp_body(:);
    p_cp = R * pbv;
    wBL  = p.target.w0(:) - R.'*[0;0;p.orbit.n];
    v_cp = R * cross(wBL, pbv);
    e    = p_cp / norm(p_cp);
    x0   = [p_cp + (p.t4.s_cap + gap)*e; v_cp - closing*e];
end

function s = try_classify(name, runs, scans, p)
% Submit a deliberately malformed sweep and record the refusal identifier.
    s.name = name;  s.id = '';  s.got = '';
    try
        c = task4_classify(runs, scans, p);
        s.got = c.outcome;                 % must not happen
    catch ME
        s.id = ME.identifier;
    end
end

function id = try_err(fn)
% Run a thunk and return the error identifier, or '' if it succeeded.
    id = '';
    try
        fn();
    catch ME
        id = ME.identifier;
    end
end

function r = intersample_residual(o, p, Tsim)
% Rebuild the capture-point trajectory independently on its own fine grid and
% compare the stored intersample h_cap against it, and against the stale
% p_cp(t_k) variant the previous code produced.
    pbv = p.target.p_cp_body(:);
    dtF = p.ctrl.Ts / 10;
    ptf = p;  ptf.sim.dt = dtF;  ptf.sim.T_final = Tsim;
    [~, qF, ~] = target_tumbling_model(ptf);
    n = numel(o.inter.t);
    eMove = zeros(1,n);  eStale = zeros(1,n);  move = zeros(1,n);
    for i = 1:n
        ti = o.inter.t(i);
        ri = o.inter.r(:,i);
        [~, RLi, ~] = lvlh_frame(ti, p);
        pcp_i = RLi * quat_to_rotm(qF(:, round(ti/dtF)+1)) * pbv;      % moving
        kc = floor((ti - 1e-9)/p.ctrl.Ts) + 1;                          % its control step
        [~, RLc, ~] = lvlh_frame(o.t(kc), p);
        pcp_c = RLc * quat_to_rotm(o.qT(:,kc)) * pbv;                   % stale
        hMove  = norm(ri - pcp_i)^2 - p.t4.s_cap^2;
        hStale = norm(ri - pcp_c)^2 - p.t4.s_cap^2;
        eMove(i)  = abs(o.inter.h_cap_diag(i) - hMove);
        eStale(i) = abs(o.inter.h_cap_diag(i) - hStale);
        move(i)   = norm(pcp_i - pcp_c);
    end
    r.n = n;  r.t1 = o.inter.t(1);  r.t2 = o.inter.t(end);
    r.max_err        = max(eMove);
    r.max_stale_gap  = max(eStale);
    r.max_pcp_move   = max(move);
end

function n = report(name, ok, n)
    if ok
        fprintf(' [PASS] %s\n', name);
    else
        fprintf(' [FAIL] %s\n', name);
        n = n + 1;
    end
end

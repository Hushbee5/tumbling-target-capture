function task4_first_diagnostic_report()
% TASK4_FIRST_DIAGNOSTIC_REPORT  Read-only analysis of the saved H-1 first run.
%
%   Reads results/task4/task4_first_diagnostic_400s_alpha1e3.mat and reports the
%   quantitative diagnostics required by the H-1 run brief. It does NOT rerun the
%   Task 4 controller and does NOT modify anything.
%
%   The frozen Task 3 400 s supplemental diagnostic IS reproduced here, purely as
%   the comparison baseline for the deviation metrics. That is a frozen Task 3
%   artifact, not a Task 4 run.

    thisDir = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(thisDir, '..')));
    S = load(fullfile(thisDir, '..', '..', 'results', 'task4', ...
                      'task4_first_diagnostic_400s_alpha1e3.mat'));
    out = S.out;  p = S.p;  meta = S.meta;
    th  = p.t4.theta_true;

    L = @(varargin) fprintf(varargin{:});
    L('=============================================================\n');
    L(' TASK 4 FIRST DIAGNOSTIC RUN - QUANTITATIVE REPORT\n');
    L(' Tsim %g s | alpha %.0e | eps_rho %.9e m | runtime %.1f s\n', ...
        meta.Tsim, meta.alpha, meta.eps_rho, meta.runtime_s);
    L('=============================================================\n');

    %% 3. PRIMARY OUTCOME
    L('\n3. PRIMARY OUTCOME\n');
    if out.qp_failure.occurred, prim = 'QP_FAILURE'; else, prim = out.event; end
    if strcmp(out.eligibility,'INELIGIBLE_IC'), prim = 'INELIGIBLE_IC'; end
    L('   %s\n', prim);
    L('   D9 event field      : %s\n', out.event);
    L('   eligibility         : %s   d9_evaluated %d\n', out.eligibility, out.d9_evaluated);
    L('   guard_validation    : %s\n', out.guard_validation);
    L('   aborted             : %d   %s\n', out.aborted, out.abort_reason);
    L('   synthetic           : %d\n', out.synthetic);

    %% 4A. TRAJECTORY / GEOMETRY
    nS = numel(out.t);
    [minrho, irho] = min(out.rho);
    [minhb, ihb]   = min(out.h_body);
    hcw = out.h_cap(1:min(hcap_window(out), nS));
    [minhc, ihc]   = min(hcw);
    [mind, idsf]   = min(out.d_safe);
    [minhi, ihi]   = min(out.inter.h_cap_diag);
    [minhbi, ihbi] = min(out.inter.h_body);
    L('\n4A. TRAJECTORY / GEOMETRY\n');
    L('   ||d||  initial %.9f m   terminal %.9f m\n', out.rho(1), out.rho(end));
    L('   ||d||  minimum %.9f m at t = %.1f s (k = %d)\n', minrho, out.t(irho), irho);
    L('   zeta   initial %.4f      terminal %.4f      minimum %.4f\n', ...
        out.rho(1)/out.s_cap, out.rho(end)/out.s_cap, minrho/out.s_cap);
    L('   body clearance d_safe minimum %.9f m at t = %.1f s (k = %d)\n', mind, out.t(idsf), idsf);
    L('   h_body minimum %+.9e at t = %.1f s (k = %d)\n', minhb, out.t(ihb), ihb);
    L('   h_cap  minimum while enforced %+.9e at t = %.1f s (k = %d)  [window 1..%d]\n', ...
        minhc, out.t(ihc), ihc, numel(hcw));
    L('   intersample h_cap  minimum %+.9e at t = %.3f s\n', minhi, out.inter.t(ihi));
    L('   intersample h_body minimum %+.9e at t = %.3f s\n', minhbi, out.inter.t(ihbi));

    %% 4B. HOCBF / QP
    capIdx = find(out.cap_enforced);
    L('\n4B. HOCBF / QP\n');
    L('   psi1_body minimum %+.9e | psi2_body minimum %+.9e\n', ...
        min(out.psi1_body), min(out.psi2_body));
    if isempty(capIdx)
        L('   capture row was never enforced\n');
    else
        L('   psi1_cap  minimum while active %+.9e (at t = %.1f s)\n', ...
            min(out.psi1_cap(capIdx)), out.t(capIdx(argmin(out.psi1_cap(capIdx)))));
        L('   psi2_cap  minimum while active %+.9e (at t = %.1f s)\n', ...
            min(out.psi2_cap(capIdx)), out.t(capIdx(argmin(out.psi2_cap(capIdx)))));
        L('   psi1_cap negative on %d of %d enforced steps\n', ...
            sum(out.psi1_cap(capIdx) < 0), numel(capIdx));
    end
    K = out.K_applied;
    L('   body row active   %6.2f %% of %d applied steps\n', 100*mean(out.row_active_body), K);
    L('   capture row active %5.2f %% of %d applied steps\n', 100*mean(out.row_active_cap), K);
    L('   capture row ENFORCED on %d of %d steps (%.2f %%)\n', ...
        sum(out.cap_enforced), K, 100*mean(out.cap_enforced));
    L('   filter intervention (dev_inf > act_thresh) on %.2f %% of steps\n', 100*mean(out.active));
    L('   dev_inf > 0.25*u_max on %.2f %% of steps\n', 100*mean(out.dev_inf > 0.25*p.chaser.u_max));
    L('   max ||u_safe - u_mpc||_inf %.9e m/s^2\n', max(out.dev_inf));
    L('   max ||u_safe - u_mpc||_2   %.9e m/s^2\n', max(vecnorm(out.Usafe - out.Umpc)));
    L('   QP infeasible steps in the per-step array : %d\n', sum(out.qp_infeasible));
    L('   qp_failure.occurred %d', out.qp_failure.occurred);
    if out.qp_failure.occurred
        L(' at k = %d (t = %.4f s), cap_active %d, exitflag %d\n', ...
            out.qp_failure.k, out.qp_failure.t, out.qp_failure.cap_active, out.qp_failure.exitflag);
        L('     individual margins %s | joint %+.6e\n', ...
            mat2str(out.qp_failure.feas_margin, 6), out.qp_failure.joint_margin);
    else
        L('\n');
    end
    L('   min individual feasibility  body %+.9e', min(out.feas_body));
    if any(~isnan(out.feas_cap)), L('   cap %+.9e\n', min(out.feas_cap)); else, L('   cap n/a\n'); end
    L('   min two-row joint feasibility margin %+.9e\n', min(out.feas_joint));

    %% 4C. CONTROL / PERFORMANCE
    Ts = p.ctrl.Ts;
    dv = sum(vecnorm(out.Usafe)) * Ts;
    L('\n4C. CONTROL / PERFORMANCE\n');
    L('   Delta-v (project convention, sum||u_safe||*Ts) %.9f m/s\n', dv);
    L('   effort_quadratic sum(||u||^2)*Ts               %.9e\n', sum(sum(out.Usafe.^2))*Ts);
    L('   max ||u_mpc||_2  %.9e | max ||u_safe||_2  %.9e m/s^2\n', ...
        max(vecnorm(out.Umpc)), max(vecnorm(out.Usafe)));
    sat = max(abs(out.Usafe), [], 1) >= p.chaser.u_max*(1-1e-9);
    L('   actuator saturation (any axis at u_max) on %.2f %% of steps\n', 100*mean(sat));
    L('   per-axis saturation  x %.2f %%  y %.2f %%  z %.2f %%\n', ...
        100*mean(abs(out.Usafe(1,:))>=p.chaser.u_max*(1-1e-9)), ...
        100*mean(abs(out.Usafe(2,:))>=p.chaser.u_max*(1-1e-9)), ...
        100*mean(abs(out.Usafe(3,:))>=p.chaser.u_max*(1-1e-9)));

    % deviation from the frozen Task 3 400 s replay (frozen artifact, not Task 4)
    o3 = simulate_mpc(p, struct('use_filter', true, 'Tsim', 400));
    n  = min(size(out.X,2), size(o3.X,2));
    dPos = vecnorm(out.X(1:3,1:n) - o3.X(1:3,1:n));
    dVel = vecnorm(out.X(4:6,1:n) - o3.X(4:6,1:n));
    L('   DEVIATION FROM THE FROZEN TASK 3 400 s REPLAY (%d common samples)\n', n);
    L('     position: max %.9f m at t = %.1f s | RMS %.9f m | terminal %.9f m\n', ...
        max(dPos), out.t(argmax(dPos)), rms_(dPos), dPos(end));
    L('     velocity: max %.9e m/s | RMS %.9e m/s | terminal %.9e m/s\n', ...
        max(dVel), rms_(dVel), dVel(end));
    L('     terminal s_cp   Task 4 %.6f m vs Task 3 replay %.6f m\n', out.rho(end), o3.s_cp(end));
    L('     min d_safe      Task 4 %.6f m vs Task 3 replay %.6f m\n', mind, min(o3.d_safe));
    L('     Delta-v         Task 4 %.6f vs Task 3 replay %.6f (%+.2f %%)\n', ...
        dv, o3.delta_v, 100*(dv/o3.delta_v - 1));
    L('     filter activity Task 4 %.1f %% vs Task 3 replay %.1f %%\n', ...
        100*mean(out.active), 100*mean(o3.active));

    %% 4D. ESTIMATOR
    L('\n4D. ESTIMATOR (predeclared regression check)\n');
    k200 = round(200/Ts) + 1;
    nu200 = out.nu(k200);  e200 = norm(out.theta_hat(:,k200) - th);
    nu400 = out.estimator.nu_end;  e400 = norm(out.estimator.theta_hat_end - th);
    ref = [0.369600182, 0.085518204, 0.055287858, 0.012665107];
    got = [nu200, e200, nu400, e400];
    nm  = {'nu_sp(200)','||theta_tilde(200)||','nu_sp(400)','||theta_tilde(400)||'};
    L('   records built over the run : %d   (stack depth cap M = %d)\n', out.estimator.records, p.t4.M);
    L('   records available at 200 s : %d      at 400 s : %d\n', floor(200/p.t4.Tw), floor(400/p.t4.Tw));
    L('   E(200) %.12e   E(400) %.12e\n', -log(nu200/p.t4.nu0)/p.t4.gamma, out.estimator.E_end);
    L('   estimator t_end %.4f s (trajectory end %.4f s)\n', out.estimator.t_end, out.t(end));
    L('   regression residual over records %.3e\n', out.estimator.resid);
    L('   quantity                 observed          predeclared        |diff|      verdict\n');
    allok = true;
    for i = 1:4
        d = abs(got(i) - ref(i));  okk = d <= 1e-12;  allok = allok && okk;
        L('   %-22s %.12f   %.12f   %.2e   %s\n', nm{i}, got(i), ref(i), d, tern(okk,'MATCH','MISMATCH'));
    end
    L('   predeclared tolerance 1e-12 : %s\n', tern(allok, 'ALL MATCH', 'MISMATCH - see the H-1 note'));

    %% 4E. D9
    L('\n4E. D9\n');
    L('   d9_evaluated %d | K_detector %d | K_applied %d | K_evaluated %d\n', ...
        out.d9_evaluated, out.K_detector, out.K_applied, out.K_evaluated);
    L('   event %s | alpha %.0e | epsilon_rho %.9e m\n', out.event, out.alpha, out.eps_rho);
    if isempty(out.event_log)
        L('   no D9 event fired at any sampled state\n');
        L('   closest approach to the band: min rho %.9f m, band top %.9f m, gap %.9e m\n', ...
            minrho, out.s_cap + out.eps_rho, minrho - (out.s_cap + out.eps_rho));
    else
        e = out.event_log;
        L('   FIRED  t = %.4f s   sample k = %d   exit %s\n', e.t, e.k, e.event);
        L('     rho          %.9f m\n', e.rho);
        L('     rho_dot      %+.9e m/s\n', e.rho_dot);
        L('     ||v - v_cp|| %.9e m/s\n', e.v_rel_cp);
        L('     nu           %.9f\n', e.nu);
        L('     h_body       %+.9e   psi1_body %+.9e\n', e.h_body, e.psi1_body);
        L('     h_cap        %+.9e   psi1_cap  %+.9e\n', e.h_cap, e.psi1_cap);
        L('     alpha %.0e   epsilon_rho %.9e m   s_cap %.9f m\n', e.alpha, e.eps_rho, e.s_cap);
    end

    %% 5. INDEPENDENT F5 SCAN
    sc = f5_hcap_scan(out, p);
    L('\n5. INDEPENDENT POST-RUN F5 SCAN (software-consistency diagnostic)\n');
    L('   independent_event    %s', sc.independent_event);
    if ~isempty(sc.independent_event_k)
        L('  at k = %d (t = %.4f s), rho %.9f, rho_dot %+.3e\n', ...
            sc.independent_event_k, out.t(sc.independent_event_k), sc.event_rho, sc.event_rho_dot);
    else
        L('\n');
    end
    L('   detector_event       %s\n', sc.detector_event);
    L('   classification_agree %d   comparable %d\n', sc.classification_agree, sc.comparable);
    L('   breach_found         %d   min_h_cap %+.9e\n', sc.breach_found, sc.min_h_cap);
    L('   F5                   %d   branch %s\n', sc.F5, sc.F5_branch);
    L('   rho cross-check vs the production path: max %.3e\n', sc.max_rho_mismatch);
    L('   NOTE: the three-alpha classifier is NOT run here; one alpha is not a sweep.\n');

    %% 6. INTERSAMPLE
    L('\n6. INTERSAMPLE DIAGNOSTIC (moving capture point)\n');
    L('   samples %d over t = %.3f .. %.3f s\n', numel(out.inter.t), out.inter.t(1), out.inter.t(end));
    L('   intersample h_cap  min %+.9e  (negative at %d of %d points)\n', ...
        minhi, sum(out.inter.h_cap_diag < 0), numel(out.inter.h_cap_diag));
    L('   intersample h_body min %+.9e  (negative at %d of %d points)\n', ...
        minhbi, sum(out.inter.h_body < 0), numel(out.inter.h_body));
    L('   NO sampled-data or intersample forward-invariance theorem is claimed.\n');
    L('=============================================================\n');
end

% ----- helpers -----
function k = hcap_window(out)
    if strcmp(out.event,'NORMAL') && ~isempty(out.handoff), k = out.handoff.k;
    else, k = numel(out.t); end
end
function i = argmin(x), [~,i] = min(x); end
function i = argmax(x), [~,i] = max(x); end
function r = rms_(x), r = sqrt(mean(x.^2)); end
function s = tern(c,a,b), if c, s=a; else, s=b; end, end

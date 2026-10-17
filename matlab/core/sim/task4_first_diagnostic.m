function task4_first_diagnostic()
% TASK4_FIRST_DIAGNOSTIC  The single H-1 first development/diagnostic run.
%
%   Executes EXACTLY ONE production Task 4 closed-loop trajectory at the
%   H-1-frozen configuration (notes/task4_freeze_record.md Section 9):
%
%       Tsim  = 400 s
%       alpha = 1e-3
%       x0    = frozen scenario initial condition
%       everything else at its frozen value
%
%   Prints the pre-run provenance block, runs once, and saves the complete raw
%   output so the trajectory can be re-analysed and visualised later WITHOUT
%   rerunning the controller.
%
%   This script does not tune, sweep, retry or select anything. The horizon and
%   alpha are read from the H-1 freeze and asserted against the frozen parameter
%   set before the run starts.

    thisDir = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(thisDir, '..')));

    % ---- H-1 frozen run specification --------------------------------------
    TSIM  = 400;
    ALPHA = 1e-3;
    outFile = fullfile(thisDir, '..', '..', 'results', 'task4', ...
                       'task4_first_diagnostic_400s_alpha1e3.mat');

    p  = params_task4();
    x0 = [p.scenario.r0; p.scenario.v0];

    fprintf('=============================================================\n');
    fprintf(' TASK 4 FIRST DEVELOPMENT/DIAGNOSTIC RUN - PRE-RUN RECORD\n');
    fprintf(' H-1 frozen 2026-08-24, before any Task 4 closed-loop outcome\n');
    fprintf('=============================================================\n');

    eps_rho = ALPHA * p.t4.s_cap;
    eps_h   = (p.t4.s_cap + eps_rho)^2 - p.t4.s_cap^2;

    fprintf(' RUN SPECIFICATION (H-1)\n');
    fprintf('   Tsim                    %g s\n', TSIM);
    fprintf('   alpha                   %.0e   (%s)\n', ALPHA, p.t4.alpha_status);
    fprintf('   epsilon_rho             %.9e m\n', eps_rho);
    fprintf('   epsilon_h               %.9e m^2\n', eps_h);
    fprintf(' FROZEN GEOMETRY AND GAINS\n');
    fprintf('   s_cap                   %.6f m\n', p.t4.s_cap);
    fprintf('   r_safe                  %.6f m\n', p.geom.r_safe);
    fprintf('   kappa_1, kappa_2        %.2f, %.2f 1/s\n', p.t4.kappa1, p.t4.kappa2);
    fprintf('   body k1, k2             %.2f, %.2f 1/s\n', p.cbf.k1, p.cbf.k2);
    fprintf('   Ts                      %.2f s\n', p.ctrl.Ts);
    fprintf('   MPC horizon N           %d steps (%.1f s)\n', p.mpc.N, p.mpc.N*p.ctrl.Ts);
    fprintf('   u_max                   %.4f m/s^2 (per axis)\n', p.chaser.u_max);
    fprintf(' FROZEN ESTIMATOR\n');
    fprintf('   Tw %.1f s | Ts %.2f s | M %d | gamma %d | nu_0 %.9f\n', ...
        p.t4.Tw, p.ctrl.Ts, p.t4.M, p.t4.gamma, p.t4.nu0);
    fprintf('   theta_hat(0)            [%g %g %g]\n', p.t4.theta_hat0);
    fprintf('   theta_true              [%+.9f %+.9f %+.9f]\n', p.t4.theta_true);
    fprintf(' INITIAL STATE\n');
    fprintf('   x0  r = [%g %g %g] m,  v = [%g %g %g] m/s\n', x0(1:3), x0(4:6));

    ic = task4_ic_admissibility(x0, p.target.q0, p.target.w0, p.t4.theta_hat0, 0, p);
    fprintf(' INITIAL ADMISSIBILITY (pre-run gate)\n');
    fprintf('   h_body(0)               %+.9e\n', ic.h_body);
    fprintf('   psi1_body(0)            %+.9e\n', ic.psi1_body);
    fprintf('   h_cap(0)                %+.9e\n', ic.h_cap);
    fprintf('   psi1_cap(0)             %+.9e\n', ic.psi1_cap);
    fprintf('   capture row active initially : %d\n', ic.cap_active_initially);
    fprintf('   eligibility             %s\n', ternchar(ic.admissible, 'ELIGIBLE', 'INELIGIBLE_IC'));
    if ~ic.admissible
        fprintf('   reasons: %s\n', strjoin(ic.reasons, ' | '));
    end

    % ---- assert nothing result-dependent drifted since H-1 -----------------
    ok =  p.t4.s_cap == 0.106226 && p.t4.kappa1 == 0.20 && p.t4.kappa2 == 0.20 ...
       && p.t4.Tw == 1.0 && p.t4.M == 50 && p.t4.gamma == 100 ...
       && abs(p.t4.nu0 - sqrt(3)) < 1e-15 && all(p.t4.theta_hat0 == 0) ...
       && p.t4.dwell_samples == 0 && isequal(p.t4.alpha_set, [1e-2 1e-3 1e-4]) ...
       && p.cbf.k1 == 0.04 && p.cbf.k2 == 0.04 && p.cbf.delta == 0 ...
       && p.chaser.u_max == 0.01 && p.ctrl.Ts == 0.1 && p.mpc.N == 100 ...
       && abs(p.geom.r_safe - 0.70) < 1e-15;
    fprintf(' PARAMETER-DRIFT CHECK vs the H-1 record : %s\n', ternchar(ok, 'PASS', 'FAIL'));
    assert(ok, 'task4_first_diagnostic:drift', ...
        'A frozen parameter differs from the H-1 record. Refusing to run.');

    fprintf('=============================================================\n');
    fprintf(' EXECUTING ONE RUN. No retry, no alternative horizon, no sweep.\n');
    fprintf('=============================================================\n');

    t0 = tic;
    out = simulate_task4(p, struct('Tsim', TSIM, 'alpha', ALPHA, 'x0', x0));
    runtime = toc(t0);

    fprintf(' run complete in %.1f s (%.2f min)\n', runtime, runtime/60);
    fprintf(' PRIMARY OUTCOME : %s\n', out.event);

    meta = struct('Tsim', TSIM, 'alpha', ALPHA, 'eps_rho', eps_rho, 'eps_h', eps_h, ...
                  'x0', x0, 'ic', ic, 'runtime_s', runtime, ...
                  'git_head', 'e0835e0f3f957d0d8fadfb0acb57cbc3b6da32e1', ...
                  'frozen_by', 'H-1, notes/task4_freeze_record.md Section 9', ...
                  'stamp', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>

    d = fileparts(outFile);
    if ~exist(d, 'dir'), mkdir(d); end
    save(outFile, 'out', 'p', 'meta', '-v7.3');
    fprintf(' raw result saved to %s\n', outFile);
    fprintf('=============================================================\n');
end

function s = ternchar(c, a, b)
    if c, s = a; else, s = b; end
end

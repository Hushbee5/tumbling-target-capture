% VALIDATE_TASK2  Validation of the HOCBF-QP safety filter (checks V1-V19).
%   Implements the validation plan of notes/task2_spec_hocbf_qp.md Sec. 8.
%   Prints a PASS/FAIL table plus the physical diagnostics requested for the
%   review, and raises an error if any check fails, so
%       matlab -batch "validate_task2"
%   works as a regression test.
%
%   Locked configuration under test: k1 = k2 = 0.04 1/s, delta = 0, W = I,
%   u_max = 0.01 m/s^2 per axis, activation threshold 1e-6 m/s^2.

clear; clc; close all;

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..')));
dataDir = fullfile(thisDir, '..', '..', 'data');

p    = params();
umax = p.chaser.u_max;
k1   = p.cbf.k1;
k2   = p.cbf.k2;
T_N2 = 200;                         % see run_filter_demo for why 200 s

chk = struct('name', {}, 'value', {}, 'tol', {}, 'cmp', {});

%% ---- runs used by several checks ----
oN1  = simulate_filtered(p, struct('ref_mode','point','r_ref',[0;-3;0],'use_filter',true));
oN2f = simulate_filtered(p, struct('ref_mode','origin','use_filter',true, 'Tsim',T_N2));
oN2n = simulate_filtered(p, struct('ref_mode','origin','use_filter',false,'Tsim',T_N2));
oN2f_300 = simulate_filtered(p, struct('ref_mode','origin','use_filter',true,'Tsim',300));

%% V1 -- filter inactive when safe
chk(end+1) = struct('name','V1  benign nominal: peak deviation      ', ...
    'value', max(oN1.dev_inf), 'tol', p.cbf.act_thresh, 'cmp','le');

%% V2 -- filter active when needed
chk(end+1) = struct('name','V2  unsafe nominal: peak deviation      ', ...
    'value', max(oN2f.dev_inf), 'tol', p.cbf.act_thresh, 'cmp','ge');

%% V3 / V3b -- safety maintained, and the contrast is real
chk(end+1) = struct('name','V3  filtered: min h                     ', ...
    'value', min(oN2f.h), 'tol', -1e-9, 'cmp','ge');
chk(end+1) = struct('name','V3a filtered: min clearance d [m]       ', ...
    'value', min(oN2f.d_safe), 'tol', -1e-9, 'cmp','ge');
chk(end+1) = struct('name','V3b unfiltered: min d < 0 (violates)    ', ...
    'value', -min(oN2n.d_safe), 'tol', 1e-6, 'cmp','ge');

%% V4 -- HOCBF residual at the sampling instants
chk(end+1) = struct('name','V4  filtered: min psi2 at samples       ', ...
    'value', min(oN2f.psi2), 'tol', -1e-9, 'cmp','ge');

%% V5 -- actuator bounds
chk(end+1) = struct('name','V5  actuator bound slack [m/s^2]        ', ...
    'value', umax - max(abs(oN2f.Usafe(:))), 'tol', -1e-12, 'cmp','ge');

%% V6 -- boundary behaviour at h = 0
eR = [1;0;0];
x6a = [p.geom.r_safe*eR;  0.01*eR];              % outward radial velocity
x6b = [p.geom.r_safe*eR; [0;0.01;0]];            % tangential velocity
o6a = simulate_filtered(p, struct('ref_mode','origin','use_filter',true, ...
                                  'x0',x6a,'Tsim',60));
o6b = simulate_filtered(p, struct('ref_mode','origin','use_filter',true, ...
                                  'x0',x6b,'Tsim',60));
chk(end+1) = struct('name','V6a boundary start, outward: min h      ', ...
    'value', min(o6a.h), 'tol', -1e-9, 'cmp','ge');

% V6b is the worst admissible initial condition: exactly on the boundary of BOTH
% C0 and C1 (h = 0 AND psi1 = 0), with the nominal command pulling inward. Here
% the sampled-and-hold implementation does NOT maintain h >= 0 - which is the
% limitation stated in spec Sec. 5, not an implementation error. The check
% therefore asserts that the excursion is bounded and behaves like a
% discretization artifact, rather than asserting a guarantee we have not proved.
exc6b = -min(o6b.d_safe);                              % excursion depth in clearance [m]
chk(end+1) = struct('name','V6b boundary start: excursion depth [m] ', ...
    'value', exc6b, 'tol', 1e-3, 'cmp','le');

% V6c: the excursion must scale like O(Ts) - halving the control step halves it.
p6h = p;  p6h.ctrl.Ts = p.ctrl.Ts/2;
o6h = simulate_filtered(p6h, struct('ref_mode','origin','use_filter',true, ...
                                    'x0',x6b,'Tsim',60));
ratio6c = exc6b / max(-min(o6h.d_safe), eps);
chk(end+1) = struct('name','V6c excursion halves with Ts (ratio)    ', ...
    'value', abs(ratio6c - 2), 'tol', 0.2, 'cmp','le');

% V6d: separate tightening experiment authorised by R2 - a small delta > 0
% removes the excursion entirely. Baseline stays at delta = 0.
p6d = p;  p6d.cbf.delta = 1e-5;
o6d = simulate_filtered(p6d, struct('ref_mode','origin','use_filter',true, ...
                                    'x0',x6b,'Tsim',60));
chk(end+1) = struct('name','V6d tightening delta=1e-5: min h        ', ...
    'value', min(o6d.h), 'tol', -1e-12, 'cmp','ge');

%% V7 -- constructed infeasibility, analytic criterion vs solver
x7 = [0.75; 0; 0; -0.03; 0; 0];
p7 = p;  p7.chaser.u_max = 5e-4;                 % shrink authority deliberately
[~, i7]  = cbf_qp_filter(x7, [0;0;0], p7);
analytic7 = (i7.b_cbf < -p7.chaser.u_max*norm(i7.A_cbf, 1));   % Sec. 4.1
chk(end+1) = struct('name','V7  infeasible case: solver agrees      ', ...
    'value', double(analytic7 && ~i7.feasible && i7.status == -1), 'tol', 1, 'cmp','ge');
% and the same state must be feasible at the real u_max
[~, i7b] = cbf_qp_filter(x7, [0;0;0], p);
chk(end+1) = struct('name','V7b same state feasible at real u_max   ', ...
    'value', double(i7b.feasible), 'tol', 1, 'cmp','ge');

%% V8 -- benign zero command preserved exactly
x8 = [0; -8; 0; 0; 0; 0];
[u8, ~] = cbf_qp_filter(x8, [0;0;0], p);
chk(end+1) = struct('name','V8  zero nominal preserved: ||u_safe||  ', ...
    'value', norm(u8), 'tol', 0, 'cmp','le');

%% V9 -- constraint coefficients verified against finite differences
x9 = [2.0; -1.5; 0.4; -0.02; 0.01; -0.005];
u9 = [0.002; -0.001; 0.0015];
[u9s, i9] = cbf_qp_filter(x9, u9, p);             % psi2 in info refers to u9s
dtF = 1e-3;
[~, ~, hd0] = safety_function(x9, p, 'cw');
[~, ~, hdM] = safety_function(rk4_step(x9, u9s, p, -dtF), p, 'cw');
[~, ~, hdP] = safety_function(rk4_step(x9, u9s, p, +dtF), p, 'cw');
hddot_fd  = (hdP - hdM) / (2*dtF);
psi2_fd   = hddot_fd + (k1 + k2)*hd0 + k1*k2*i9.h;
psi2_ana  = i9.psi2;
chk(end+1) = struct('name','V9  psi2 analytic vs finite diff (rel)  ', ...
    'value', abs(psi2_ana - psi2_fd)/max(abs(psi2_ana), eps), 'tol', 1e-6, 'cmp','le');

%% V10 -- solver status
badStatus = sum(oN2f.status < 0) + sum(oN1.status < 0);
chk(end+1) = struct('name','V10 negative solver statuses (count)    ', ...
    'value', badStatus, 'tol', 0, 'cmp','le');

%% V11 -- determinism
oDet1 = simulate_filtered(p, struct('ref_mode','origin','use_filter',true,'Tsim',30));
oDet2 = simulate_filtered(p, struct('ref_mode','origin','use_filter',true,'Tsim',30));
identical = isequal(oDet1.X, oDet2.X) && isequal(oDet1.Usafe, oDet2.Usafe);
chk(end+1) = struct('name','V11 deterministic rerun (bitwise)       ', ...
    'value', double(identical), 'tol', 1, 'cmp','ge');

%% V12 -- admissible initial condition
x0 = [p.scenario.r0; p.scenario.v0];
[h0, ~, hdot0] = safety_function(x0, p, 'cw');
psi1_0 = hdot0 + k1*h0;
chk(end+1) = struct('name','V12 initial h(x0)                       ', ...
    'value', h0,     'tol', 0, 'cmp','ge');
chk(end+1) = struct('name','V12a initial psi1(x0)                   ', ...
    'value', psi1_0, 'tol', 0, 'cmp','ge');

%% V12b -- inadmissible initial condition is classified, not mislabelled
x12 = [0.8; 0; 0; -1; 0; 0];
[h12, ~, hd12] = safety_function(x12, p, 'cw');
psi1_12 = hd12 + k1*h12;
[~, i12] = cbf_qp_filter(x12, [0;0;0], p);
label12 = classify_initial(h12, psi1_12);
correct12 = strcmp(label12, 'outside HOCBF admissible set') && (h12 >= 0) ...
            && (psi1_12 < 0) && i12.feasible;   % feasible => not an infeasibility event
chk(end+1) = struct('name','V12b h>=0 but psi1<0 classified correctly', ...
    'value', double(correct12), 'tol', 1, 'cmp','ge');

%% V13 -- psi1 monitored throughout
chk(end+1) = struct('name','V13 filtered: min psi1 over run         ', ...
    'value', min(oN2f.psi1), 'tol', -1e-9, 'cmp','ge');

%% V14 -- intersample excursion
chk(end+1) = struct('name','V14 intersample min h                   ', ...
    'value', oN2f.inter.h_min, 'tol', -1e-9, 'cmp','ge');

%% V15 -- minimal intervention equals the analytic halfspace projection
x15 = oN2f.X(:, 40);
u15 = nominal_pd(x15, [0;0;0], [0;0;0], p);
[u15s, i15] = cbf_qp_filter(x15, u15, p);
a15 = i15.A_cbf(:);
viol15 = i15.A_cbf*u15 - i15.b_cbf;
u15_proj = u15 - a15 * (viol15 / (a15.'*a15));   % projection onto the halfspace
boxOk = all(abs(u15_proj) <= umax + 1e-15);      % valid only if the box is inactive
chk(end+1) = struct('name','V15 minimal intervention vs projection  ', ...
    'value', ternary_num(boxOk, norm(u15s - u15_proj), 0), 'tol', 1e-9, 'cmp','le');

%% V16 -- feasibility margin
chk(end+1) = struct('name','V16 min feasibility margin              ', ...
    'value', min(oN2f.feas_margin), 'tol', 0, 'cmp','ge');

%% V17 -- locked gain against the sizing heuristic (baseline only)
gd = cbf_gain_design(p, [], false);
chk(end+1) = struct('name','V17 k_used / k_heuristic (baseline)     ', ...
    'value', gd.ratio, 'tol', 1, 'cmp','le');

%% V18 -- realised authority usage
peakUse = max(abs(oN2f.Usafe(:))) / umax;
chk(end+1) = struct('name','V18 peak |u_safe|_inf / u_max           ', ...
    'value', peakUse, 'tol', 1 + 1e-12, 'cmp','le');

%% V19 -- three-way cross-check of the QP solution
% The custom exact projection solver remains the production path; quadprog and
% mpcActiveSetSolver are independent references only.
d_ab = 0; d_ac = 0; d_bc = 0;                      % pairwise control discrepancies
j_ab = 0; j_ac = 0;                                % objective-value discrepancies
res_a = -inf; res_b = -inf; res_c = -inf;          % CBF row residuals (want <= 0)
box_a = -inf; box_b = -inf; box_c = -inf;          % box residuals   (want <= 0)
flagsQ = []; statusM = []; nCases = 0;
qpOpt = optimoptions('quadprog', 'Display','none', ...
    'OptimalityTolerance',1e-14, 'ConstraintTolerance',1e-14, 'StepTolerance',1e-16);
rng(0);
for trial = 1:60
    dirv = randn(3,1);  dirv = dirv / norm(dirv);
    rad  = p.geom.r_safe + 6*rand;                % anywhere outside the sphere
    xt   = [rad*dirv; 0.15*randn(3,1)];
    ut   = 1.5*umax*(2*rand(3,1) - 1);            % sometimes outside the box too

    [ua, ia] = cbf_qp_filter(xt, ut, p);
    if ~ia.feasible, continue; end

    [ub, stM] = solve_with_mpc_solver(ia.A_cbf, ia.b_cbf, ut, umax);
    [uc, ~, fgQ] = quadprog(eye(3), -ut, ia.A_cbf, ia.b_cbf, [], [], ...
                            -umax*ones(3,1), umax*ones(3,1), [], qpOpt);
    if isempty(ub) || isempty(uc), continue; end
    nCases = nCases + 1;

    d_ab = max(d_ab, norm(ua-ub, inf));
    d_ac = max(d_ac, norm(ua-uc, inf));
    d_bc = max(d_bc, norm(ub-uc, inf));

    Jof  = @(u) 0.5*norm(u - ut)^2;
    j_ab = max(j_ab, abs(Jof(ua) - Jof(ub)));
    j_ac = max(j_ac, abs(Jof(ua) - Jof(uc)));

    res_a = max(res_a, ia.A_cbf*ua - ia.b_cbf);
    res_b = max(res_b, ia.A_cbf*ub - ia.b_cbf);
    res_c = max(res_c, ia.A_cbf*uc - ia.b_cbf);
    box_a = max(box_a, max(abs(ua)) - umax);
    box_b = max(box_b, max(abs(ub)) - umax);
    box_c = max(box_c, max(abs(uc)) - umax);

    flagsQ(end+1)  = fgQ;   %#ok<AGROW>
    statusM(end+1) = stM;   %#ok<AGROW>
end
maxDiff19 = max([d_ab, d_ac, d_bc]);
chk(end+1) = struct('name','V19a custom vs mpcActiveSetSolver       ', ...
    'value', d_ab, 'tol', 1e-10, 'cmp','le');
chk(end+1) = struct('name','V19b custom vs quadprog                 ', ...
    'value', d_ac, 'tol', 1e-8,  'cmp','le');
chk(end+1) = struct('name','V19c objective gap, custom vs quadprog  ', ...
    'value', j_ac, 'tol', 1e-12, 'cmp','le');
chk(end+1) = struct('name','V19d all three feasible (max CBF resid) ', ...
    'value', max([res_a, res_b, res_c]), 'tol', 1e-10, 'cmp','le');
chk(end+1) = struct('name','V19e all three respect the box          ', ...
    'value', max([box_a, box_b, box_c]), 'tol', 1e-12, 'cmp','le');
chk(end+1) = struct('name','V19f quadprog exit flags all positive   ', ...
    'value', double(all(flagsQ > 0)), 'tol', 1, 'cmp','ge');

%% ---- report ----
fprintf('=============================================================\n');
fprintf(' TASK 2 VALIDATION - HOCBF-QP safety filter\n');
fprintf(' %s | k1 = k2 = %.3g 1/s | delta = %g | u_max = %g m/s^2 | Ts = %g s\n', ...
    string(datetime('now','Format','yyyy-MM-dd HH:mm')), k1, p.cbf.delta, umax, p.ctrl.Ts);
fprintf('=============================================================\n');
nFail = 0;
for k = 1:numel(chk)
    switch chk(k).cmp
        case 'le', ok = chk(k).value <= chk(k).tol;  sym = '<=';
        case 'ge', ok = chk(k).value >= chk(k).tol;  sym = '>=';
    end
    if ~ok, nFail = nFail + 1; end
    fprintf('  %s : %11.3e   (%s %8.1e)  %s\n', ...
        chk(k).name, chk(k).value, sym, chk(k).tol, upper_pf(ok));
end

fprintf('-------------------------------------------------------------\n');
fprintf(' PHYSICAL DIAGNOSTICS (scenario N2, r_ref = 0, T = %g s)\n', T_N2);
fprintf('   min h            = %+.6e            min d = %+.6f m\n', min(oN2f.h), min(oN2f.d_safe));
fprintf('   min psi1         = %+.6e            min psi2 = %+.3e\n', min(oN2f.psi1), min(oN2f.psi2));
fprintf('   intersample      : min h = %+.6e , min psi2 = %+.3e\n', ...
    oN2f.inter.h_min, oN2f.inter.psi2_min);
fprintf('   peak ||u_nom||_inf  = %.6f m/s^2   (%.1f %% of u_max)\n', ...
    max(abs(oN2f.Unom(:))),  100*max(abs(oN2f.Unom(:)))/umax);
fprintf('   peak ||u_safe||_inf = %.6f m/s^2   (%.1f %% of u_max)\n', ...
    max(abs(oN2f.Usafe(:))), 100*peakUse);
fprintf('   filter active    : %.1f %% of steps (%d of %d), peak deviation %.3e m/s^2\n', ...
    100*mean(oN2f.active), sum(oN2f.active), numel(oN2f.active), max(oN2f.dev_inf));
fprintf('   min feasibility margin = %.6e\n', min(oN2f.feas_margin));
fprintf('   solver status distribution: ');
us = unique(oN2f.status);
for s = us(:).'
    fprintf('[%d]x%d ', s, sum(oN2f.status == s));
end
fprintf('\n');
fprintf('   unfiltered contrast: min d = %+.4f m (violation depth %.4f m)\n', ...
    min(oN2n.d_safe), max(0, -min(oN2n.d_safe)));
fprintf('   supplementary T = 300 s: min d = %+.6f m, min psi1 = %+.3e, intersample min h = %+.3e\n', ...
    min(oN2f_300.d_safe), min(oN2f_300.psi1), oN2f_300.inter.h_min);
fprintf('   far-field acceleration cap at rest (rho = 10 m) = %.5f m/s^2 vs u_max %.5f\n', ...
    k1*k2*(100 - p.geom.r_safe^2)/20, umax);
fprintf('   benign N1: peak deviation %.3e m/s^2, active %.1f %%\n', ...
    max(oN1.dev_inf), 100*mean(oN1.active));
fprintf(' SOLVER CROSS-VALIDATION (%d feasible random states, three solvers)\n', nCases);
fprintf('   control discrepancy  : custom-vs-mpcAS %.3e , custom-vs-quadprog %.3e , mpcAS-vs-quadprog %.3e\n', ...
    d_ab, d_ac, d_bc);
fprintf('   objective discrepancy: custom-vs-mpcAS %.3e , custom-vs-quadprog %.3e\n', j_ab, j_ac);
fprintf('   max CBF row residual : custom %+.3e , mpcAS %+.3e , quadprog %+.3e   (want <= 0)\n', ...
    res_a, res_b, res_c);
fprintf('   max box residual     : custom %+.3e , mpcAS %+.3e , quadprog %+.3e   (want <= 0)\n', ...
    box_a, box_b, box_c);
fprintf('   quadprog exit flags  : %s | mpcActiveSetSolver status range [%d, %d]\n', ...
    mat2str(unique(flagsQ)), min(statusM), max(statusM));
fprintf(' SAMPLED-DATA LIMITATION (worst admissible start: h0 = psi1_0 = 0)\n');
fprintf('   delta = 0    : excursion %.3e m of clearance at Ts = %.3g s\n', exc6b, p.ctrl.Ts);
fprintf('                  %.3e m at Ts/2  -> ratio %.2f (O(Ts) expected 2.00)\n', ...
    -min(o6h.d_safe), ratio6c);
fprintf('   delta = 1e-5 : excursion %.3e m (removed), N2 min d shifts %+.4f m\n', ...
    max(0, -min(o6d.d_safe)), min(simulate_filtered(p6d, struct('ref_mode','origin', ...
        'use_filter',true,'Tsim',T_N2)).d_safe) - min(oN2f.d_safe));
fprintf('=============================================================\n');

%% ---- verdict ----
if nFail > 0
    error('validate_task2:failed', 'TASK 2 VALIDATION FAILED (%d of %d checks).', ...
        nFail, numel(chk));
end
fprintf('  TASK 2 VALIDATION PASSED (%d/%d checks).\n', numel(chk), numel(chk));

%% ---- local functions ----
function s = upper_pf(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function v = ternary_num(cond, a, b)
    if cond, v = a; else, v = b; end
end

function label = classify_initial(h0, psi1_0)
% Classification agreed in spec Sec. 1.4: an initial state with h >= 0 but
% psi1 < 0 is outside the HOCBF admissible set. It is NOT a safety violation
% and NOT an infeasibility event.
    if h0 < 0
        label = 'inside keep-out set';
    elseif psi1_0 < 0
        label = 'outside HOCBF admissible set';
    else
        label = 'admissible';
    end
end

function xn = rk4_step(x, u, p, dt)
    f  = @(xx) rel_translational_dynamics(xx, u, p, 'cw');
    k1_ = f(x);
    k2_ = f(x + 0.5*dt*k1_);
    k3_ = f(x + 0.5*dt*k2_);
    k4_ = f(x + dt*k3_);
    xn = x + (dt/6)*(k1_ + 2*k2_ + 2*k3_ + k4_);
end

function [u, status] = solve_with_mpc_solver(A_cbf, b_cbf, u_nom, umax)
% Independent solution of the same QP with the MPC Toolbox active-set solver.
%   min 0.5||u - u_nom||^2  s.t.  A_cbf u <= b_cbf,  -umax <= u <= umax
    H  = eye(3);
    f  = -u_nom;
    Ai = [A_cbf; eye(3); -eye(3)];
    bi = [b_cbf; umax*ones(3,1); umax*ones(3,1)];
    Linv = inv(chol(H, 'lower'));
    opt  = mpcActiveSetOptions;
    iA0  = false(size(bi));
    [u, status] = mpcActiveSetSolver(Linv, f, Ai, bi, zeros(0,3), zeros(0,1), iA0, opt);
    if status <= 0
        u = [];
    end
end

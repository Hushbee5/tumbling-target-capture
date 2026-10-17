% VALIDATE_TASK1  Validation of the LVLH frame, relative plant and safety function.
%   Implements checks T1-T10 of notes/task1_spec_lvlh_cw.md. Prints a PASS/FAIL
%   table, writes a figure to data/, and raises an error if any check fails, so
%       matlab -batch "validate_task1"
%   works as a regression test (non-zero exit status on failure).
%
%   T1  frame round trip R_LI*R_IL = I, det(R_IL) = +1
%   T2  a point fixed in inertial rotates at exactly n when seen in LVLH
%   T3  capture-point radius invariant under the inertial->LVLH mapping
%   T4  transport term: finite difference of p_cp_L vs analytic v_cp_L
%   T5  CW propagation matches the closed-form solution; bounded orbit closes
%   T6  secular along-track drift rate equals -3*(2*n*rx0 + vy0)
%   T7  nonlinear two-body relative dynamics agrees with CW at metre scale
%   T8  h_ddot formula (Lf2h + Lgh*u) matches finite differences of h
%   T9  sign convention: h >= 0 <=> d >= 0 <=> outside the keep-out sphere
%   T10 unit guard: no kilometre-valued quantity reaches the dynamics layer
%
%   Scope: Task 1 only. No controller, no CBF condition, no QP, no manipulator.

clear; clc; close all;

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..')));
dataDir = fullfile(thisDir, '..', '..', 'data');

p    = params();
n    = p.orbit.n;
Torb = p.orbit.T;
odeOpt = odeset('RelTol', 1e-12, 'AbsTol', 1e-12);

chk = struct('name', {}, 'value', {}, 'tol', {}, 'cmp', {});

%% T1 -- frame round trip
ts   = linspace(0, Torb, 200);
e1   = 0; e2 = 0;
for tk = ts
    [R_IL, R_LI] = lvlh_frame(tk, p);
    e1 = max(e1, norm(R_LI*R_IL - eye(3), 'fro'));
    e2 = max(e2, abs(det(R_IL) - 1));
end
chk(end+1) = struct('name', 'T1  frame round trip ||R_LI R_IL - I||', ...
                    'value', e1, 'tol', 1e-12, 'cmp', 'le');
chk(end+1) = struct('name', 'T1b frame det(R_IL) - 1               ', ...
                    'value', e2, 'tol', 1e-12, 'cmp', 'le');

%% T2 -- a point fixed in inertial rotates at n when seen in LVLH
pI    = [1; 2; 3];
% Resolution is chosen so that the central-difference truncation error of the
% rate check below (order dt^2) sits well under its tolerance; the limit here is
% the test's own discretization, not the frame code.
tt    = linspace(0, Torb, 20001);
pL    = zeros(3, numel(tt));
for k = 1:numel(tt)
    [~, R_LI] = lvlh_frame(tt(k), p);
    pL(:, k) = R_LI * pI;
end
closureErr = norm(pL(:, end) - pL(:, 1)) / norm(pI);        % returns after one orbit
normErr    = max(abs(vecnorm(pL) - norm(pI))) / norm(pI);   % rotation preserves norm
% rate check: d/dt p_L must equal -omega_L x p_L
dtL   = tt(2) - tt(1);
pLdot = (pL(:, 3:end) - pL(:, 1:end-2)) / (2*dtL);
omega_L = [0; 0; n];
rateErr = 0;
for k = 2:numel(tt)-1
    rateErr = max(rateErr, norm(pLdot(:, k-1) + cross(omega_L, pL(:, k))));
end
rateErr = rateErr / (n * norm(pI));
chk(end+1) = struct('name', 'T2  inertial point closure over 1 orbit', ...
                    'value', closureErr, 'tol', 1e-9,  'cmp', 'le');
chk(end+1) = struct('name', 'T2b LVLH mapping preserves norm       ', ...
                    'value', normErr,    'tol', 1e-12, 'cmp', 'le');
chk(end+1) = struct('name', 'T2c rate: dp_L/dt = -omega_L x p_L    ', ...
                    'value', rateErr,    'tol', 1e-6,  'cmp', 'le');

%% T3/T4 -- capture point mapped into LVLH, and the transport term
[t, qHist, wHist]      = target_tumbling_model(p);
[pcpI, vcpI, ncpI]     = capture_point_trajectory(qHist, wHist, p);
[pcpL, vcpL, ~]        = capture_point_lvlh(t, pcpI, vcpI, ncpI, p);

radiusDevL = max(abs(vecnorm(pcpL) - p.geom.r_grapple)) / p.geom.r_grapple;
chk(end+1) = struct('name', 'T3  capture radius in LVLH (rel dev)  ', ...
                    'value', radiusDevL, 'tol', 1e-12, 'cmp', 'le');

dt    = mean(diff(t));
vFd   = (pcpL(:, 3:end) - pcpL(:, 1:end-2)) / (2*dt);
vRef  = max(vecnorm(vcpL));
errWith = max(vecnorm(vFd - vcpL(:, 2:end-1))) / vRef;
% same comparison with the transport term deliberately omitted, to show the
% test actually discriminates (this is the quasi-inertial error of D4)
vcpNaive = zeros(size(vcpL));
for k = 1:numel(t)
    [~, R_LI] = lvlh_frame(t(k), p);
    vcpNaive(:, k) = R_LI * vcpI(:, k);
end
errWithout = max(vecnorm(vFd - vcpNaive(:, 2:end-1))) / vRef;
chk(end+1) = struct('name', 'T4  transport term: FD vs analytic    ', ...
                    'value', errWith, 'tol', 1e-4, 'cmp', 'le');

%% T5 -- CW numerical propagation vs closed form, and bounded-orbit closure
x0gen = [5; -3; 2; 0.002; -0.004; 0.001];          % generic initial condition
[~, Xg] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'cw'), ...
                [0 Torb], x0gen, odeOpt);
xNum   = Xg(end, :).';
xAna   = cw_analytic(x0gen, Torb, n);
genErr = norm(xNum - xAna) / norm(x0gen);

rx0    = 5;
x0bnd  = [rx0; 0; 0; 0; -2*n*rx0; 0];              % bounded relative orbit
[~, Xb] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'cw'), ...
                [0 Torb], x0bnd, odeOpt);
bndErr = norm(Xb(end, :).' - x0bnd) / norm(x0bnd);
chk(end+1) = struct('name', 'T5  CW numerical vs closed form (rel) ', ...
                    'value', genErr, 'tol', 1e-6, 'cmp', 'le');
chk(end+1) = struct('name', 'T5b bounded orbit closes after 1 orbit', ...
                    'value', bndErr, 'tol', 1e-6, 'cmp', 'le');

%% T6 -- secular along-track drift rate
rx0d = 5;  vy0d = 0;
x0d  = [rx0d; 0; 0; 0; vy0d; 0];
[~, Xd] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'cw'), ...
                [0 Torb 2*Torb], x0d, odeOpt);
driftMeas = Xd(3, 2) - Xd(2, 2);                   % ry(2T) - ry(T)
driftPred = -3 * (2*n*rx0d + vy0d) * Torb;         % closed-form secular term
driftErr  = abs(driftMeas - driftPred) / abs(driftPred);
chk(end+1) = struct('name', 'T6  secular drift rate vs closed form ', ...
                    'value', driftErr, 'tol', 1e-6, 'cmp', 'le');

%% T7 -- nonlinear two-body vs CW at the scenario scale
x0s = [p.scenario.r0; p.scenario.v0];
[~, Xcw] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'cw'), ...
                 [0 p.scenario.Tsim], x0s, odeOpt);
[~, Xnl] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'nonlinear'), ...
                 [0 p.scenario.Tsim], x0s, odeOpt);
modelDiff = norm(Xnl(end, 1:3) - Xcw(end, 1:3));   % absolute position gap [m]
chk(end+1) = struct('name', 'T7  nonlinear vs CW position gap [m]  ', ...
                    'value', modelDiff, 'tol', 1e-5, 'cmp', 'le');

%% T8 -- h_dot and h_ddot formulas vs finite differences along the trajectory
% Two chained FIRST-derivative differences are used rather than one second
% difference: the latter is limited by roundoff of order eps*|h|/dt^2 and would
% make the test's own error, not the formula's, the quantity being measured.
xT8 = [3; -4; 1; 0.01; 0.02; -0.005];
uT8 = [0.003; -0.002; 0.001];
dtF = 1e-3;
xm  = rk4_step(xT8, uT8, p, -dtF);
xp  = rk4_step(xT8, uT8, p, +dtF);

% h_dot: analytic vs central difference of h
[~, ~, hdotAna]              = safety_function(xT8, p, 'cw');
[hm, ~, hdotM]               = safety_function(xm,  p, 'cw');
[hp, ~, hdotP]               = safety_function(xp,  p, 'cw');
hdotFd  = (hp - hm) / (2*dtF);
hdotErr = abs(hdotAna - hdotFd) / max(abs(hdotAna), eps);

% h_ddot: analytic (Lf2h + Lgh*u) vs central difference of the analytic h_dot
[~, ~, ~, Lf2h, Lgh] = safety_function(xT8, p, 'cw');
hddotAna = Lf2h + Lgh * uT8;
hddotFd  = (hdotP - hdotM) / (2*dtF);
hddotErr = abs(hddotAna - hddotFd) / max(abs(hddotAna), eps);

lghErr = norm(Lgh - 2*xT8(1:3).');
chk(end+1) = struct('name', 'T8  h_dot analytic vs finite diff     ', ...
                    'value', hdotErr,  'tol', 1e-9,  'cmp', 'le');
chk(end+1) = struct('name', 'T8b h_ddot analytic vs finite diff    ', ...
                    'value', hddotErr, 'tol', 1e-9,  'cmp', 'le');
chk(end+1) = struct('name', 'T8c Lgh = 2 r'' (relative degree 2)    ', ...
                    'value', lghErr,   'tol', 1e-12, 'cmp', 'le');
chk(end+1) = struct('name', 'T8d ||Lgh|| > 0 (input reaches h_ddot)', ...
                    'value', norm(Lgh), 'tol', 1e-6, 'cmp', 'ge');

%% T9 -- sign convention of h and d
rSweep   = linspace(0.5*p.geom.r_safe, 2*p.geom.r_safe, 501);
signMism = 0;
for rr = rSweep
    [hh, dd] = safety_function([rr; 0; 0; 0; 0; 0], p);
    if sign(hh) ~= sign(dd), signMism = signMism + 1; end
end
[hAt, dAt] = safety_function([p.geom.r_safe; 0; 0; 0; 0; 0], p);
zeroErr = max(abs(hAt), abs(dAt));
chk(end+1) = struct('name', 'T9  sign(h) == sign(d) over sweep     ', ...
                    'value', signMism, 'tol', 0,     'cmp', 'le');
chk(end+1) = struct('name', 'T9b h and d vanish exactly at r_safe  ', ...
                    'value', zeroErr,  'tol', 1e-12, 'cmp', 'le');

%% T10 -- unit guard
unitOk = (n > 1e-4 && n < 1e-2) ...                       % rad/s
      && (p.orbit.a_m  > 6.0e6 && p.orbit.a_m  < 8.0e6) ...% m
      && (p.orbit.mu_m > 3.0e14 && p.orbit.mu_m < 5.0e14)... % m^3/s^2
      && (p.geom.r_safe < 100) && (p.geom.r_grapple < 100);  % m, not km
chk(end+1) = struct('name', 'T10 unit guard (SI at dynamics layer) ', ...
                    'value', double(unitOk), 'tol', 1, 'cmp', 'ge');

%% ---- report ----
fprintf('=============================================================\n');
fprintf(' TASK 1 VALIDATION - LVLH frame, relative plant, safety function\n');
fprintf(' %s | n = %.4e rad/s | T_orbit = %.1f s\n', ...
    string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), n, Torb);
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
fprintf('  keep-out: r_safe = r_target %.2f + r_chaser %.2f + margin %.2f = %.3f m\n', ...
    p.geom.r_target, p.geom.r_chaser, p.geom.margin, p.geom.r_safe);
fprintf('  capture point at %.3f m -> clearance to keep-out = %.3f m\n', ...
    p.geom.r_grapple, p.geom.r_grapple - p.geom.r_safe);
fprintf('  scenario: r0 = [%g %g %g] m, v0 = 0, Tsim = %g s, u_max = %g m/s^2\n', ...
    p.scenario.r0, p.scenario.Tsim, p.chaser.u_max);
fprintf('  D4 correction size: transport term omitted -> FD error %.2f%% vs %.4f%% with it\n', ...
    100*errWithout, 100*errWith);
fprintf('=============================================================\n');

%% ---- figure ----
fig = figure('Name', 'Task 1 validation', 'Color', 'w', 'Position', [80 80 1100 780]);

subplot(2,2,1);
plot3(pcpI(1,:), pcpI(2,:), pcpI(3,:), '-', 'LineWidth', 1.2); hold on;
plot3(pcpL(1,:), pcpL(2,:), pcpL(3,:), '-', 'LineWidth', 1.2);
grid on; axis equal; view(135, 25);
xlabel('x [m]'); ylabel('y [m]'); zlabel('z [m]');
title('Capture point: inertial vs LVLH');
legend({'inertial', 'LVLH'}, 'Location', 'best');

subplot(2,2,2);
plot(t, vecnorm(pcpL - pcpI), 'LineWidth', 1.4); grid on;
xlabel('t [s]'); ylabel('|| p_{cp}^{L} - p_{cp}^{I} || [m]');
title('D4: error of the quasi-inertial shortcut');

subplot(2,2,3);
% Dense re-propagation of both T5b/T6 cases for a readable trace; the drifting
% case leaves the axes on purpose - that is the point of the comparison.
tOrb = linspace(0, Torb, 600);
[~, XbP] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'cw'), ...
                 tOrb, x0bnd, odeOpt);
[~, XdP] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'cw'), ...
                 tOrb, x0d, odeOpt);
plot(XbP(:,1), XbP(:,2), 'LineWidth', 1.6); hold on;
plot(XdP(:,1), XdP(:,2), '--', 'LineWidth', 1.2);
plot(0, 0, 'k+', 'MarkerSize', 10); grid on; axis equal;
xlim([-16 16]); ylim([-28 16]);
xlabel('x radial [m]'); ylabel('y along-track [m]');
title('CW free drift over one orbit');
legend({'v_{y0} = -2 n x_0  (closes, T5b)', 'v_{y0} = 0  (drifts, T6)'}, ...
    'Location', 'southwest');

subplot(2,2,4);
tS = linspace(0, p.scenario.Tsim, 300);
[~, Xs] = ode45(@(tt_, x) rel_translational_dynamics(x, zeros(3,1), p, 'nonlinear'), ...
                tS, x0s, odeOpt);
dS = zeros(1, numel(tS));
for k = 1:numel(tS)
    [~, dS(k)] = safety_function(Xs(k, :).', p);
end
plot(tS, dS, 'LineWidth', 1.6); grid on; hold on;
yline(0, 'r--', 'keep-out boundary');
ylim([-0.5, 1.15*max(dS)]);
xlabel('t [s]'); ylabel('clearance d = ||r|| - r_{safe} [m]');
title({'Clearance, uncontrolled from the baseline scenario', ...
       'a pure V-bar offset is a CW equilibrium: no natural approach'});

if ~exist(dataDir, 'dir'), mkdir(dataDir); end
force_light_figure(fig);
exportgraphics(fig, fullfile(dataDir, 'task1_validation.png'), 'Resolution', 150);
fprintf('  figure written to data/task1_validation.png\n');

%% ---- verdict ----
if nFail > 0
    error('validate_task1:failed', 'TASK 1 VALIDATION FAILED (%d of %d checks).', ...
        nFail, numel(chk));
end
fprintf('  TASK 1 VALIDATION PASSED (%d/%d checks).\n', numel(chk), numel(chk));

%% ---- local functions ----
function s = upper_pf(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function x = cw_analytic(x0, t, n)
% Closed-form Clohessy-Wiltshire solution with u = 0 (radial-outward x).
    rx0 = x0(1); ry0 = x0(2); rz0 = x0(3);
    vx0 = x0(4); vy0 = x0(5); vz0 = x0(6);
    c = cos(n*t); s = sin(n*t);
    rx = (4 - 3*c)*rx0 + (s/n)*vx0 + (2/n)*(1 - c)*vy0;
    ry = 6*(s - n*t)*rx0 + ry0 - (2/n)*(1 - c)*vx0 + (1/n)*(4*s - 3*n*t)*vy0;
    rz = rz0*c + (vz0/n)*s;
    vx = 3*n*s*rx0 + c*vx0 + 2*s*vy0;
    vy = 6*n*(c - 1)*rx0 - 2*s*vx0 + (4*c - 3)*vy0;
    vz = -n*rz0*s + vz0*c;
    x  = [rx; ry; rz; vx; vy; vz];
end

function xn = rk4_step(x, u, p, dt)
% One classical RK4 step of the CW dynamics, used by the T8 finite differences.
    f  = @(xx) rel_translational_dynamics(xx, u, p, 'cw');
    k1 = f(x);
    k2 = f(x + 0.5*dt*k1);
    k3 = f(x + 0.5*dt*k2);
    k4 = f(x + dt*k3);
    xn = x + (dt/6)*(k1 + 2*k2 + 2*k3 + k4);
end

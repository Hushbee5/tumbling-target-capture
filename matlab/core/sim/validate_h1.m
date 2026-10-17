% VALIDATE_H1  Re-runnable validation of the H1 target-dynamics model.
%   Checks the conservation laws and geometric invariants that the torque-free
%   tumbling model and the body-fixed capture point must satisfy, prints a
%   PASS/FAIL table, and writes two figures to data/.
%
%   Usage:
%       validate_h1                                  % from the MATLAB editor
%       matlab -batch "validate_h1"                  % as a regression test
%   The script raises an error if any check fails, so a non-zero exit status
%   means the H1 model has regressed.
%
%   Checks:
%     V1  quaternion unit norm preserved
%     V2  DCM orthogonality  ||R'R - I||  over the whole history
%     V3  DCM proper rotation  det(R) - 1  over the whole history
%     V4  angular momentum conserved in the inertial frame (torque-free)
%     V5  rotational kinetic energy conserved (torque-free)
%     V6  capture-point radius invariant (rigid body)
%     V7  capture-point velocity consistent with the trajectory it produces
%     V8  capture-point velocity perpendicular to its radius (pure rotation)
%     V9  capture-point clearance outside the forbidden sphere (must be > 0)
%
%   V1-V8 are error-like (PASS when below tolerance); V9 is margin-like (PASS
%   when at or above tolerance). The printed comparison symbol states which.
%
%   Scope note: H1 only. The relative translational plant, the safety function
%   h(x) and the approach-corridor test are deliberately NOT covered here -
%   they are not implemented yet (see notes/project_handoff_status.md).

clear; clc; close all;

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..')));
dataDir = fullfile(thisDir, '..', '..', 'data');

p = params();

%% ---- run the model under test ----
[t, qHist, wHist] = target_tumbling_model(p);
[pcpHist, vcpHist, ncpHist] = capture_point_trajectory(qHist, wHist, p);

N  = numel(t);
I  = p.target.I;
dt = mean(diff(t));

%% ---- derived quantities ----
qNormErr = abs(sqrt(sum(qHist.^2, 1)) - 1);         % 1xN
orthErr  = zeros(1, N);                             % ||R'R - I||_F
detErr   = zeros(1, N);                             % |det(R) - 1|
Hin      = zeros(3, N);                             % angular momentum, inertial
Trot     = zeros(1, N);                             % rotational kinetic energy

for k = 1:N
    R           = quat_to_rotm(qHist(:, k));
    orthErr(k)  = norm(R.'*R - eye(3), 'fro');
    detErr(k)   = abs(det(R) - 1);
    Hin(:, k)   = R * (I * wHist(:, k));
    Trot(k)     = 0.5 * wHist(:, k).' * I * wHist(:, k);
end

H0        = Hin(:, 1);
Hdrift    = vecnorm(Hin - H0) / norm(H0);           % relative, 1xN
Tdrift    = abs(Trot - Trot(1)) / Trot(1);          % relative, 1xN
radii     = vecnorm(pcpHist);                       % 1xN
radiusDev = abs(radii - p.geom.r_grapple) / p.geom.r_grapple;

% V7: compare the analytic velocity with a central difference of the position
vFd     = (pcpHist(:, 3:end) - pcpHist(:, 1:end-2)) / (2*dt);
vErrRel = vecnorm(vFd - vcpHist(:, 2:end-1)) / max(vecnorm(vcpHist));

% V8: for a body-fixed point the velocity must be perpendicular to the radius
perpErr = abs(sum(pcpHist .* vcpHist, 1)) ./ max(radii .* vecnorm(vcpHist), eps);

%% ---- assemble the checks ----
% Each check carries an explicit comparison direction so that no quantity has
% an ambiguous sign:
%   'le' : error-like quantity, PASS when value <= tol
%   'ge' : margin-like quantity, PASS when value >= tol
chk = struct('name', {}, 'value', {}, 'tol', {}, 'cmp', {});
chk(end+1) = struct('name', 'V1 quaternion norm error           ', ...
                    'value', max(qNormErr),  'tol', 1e-12, 'cmp', 'le');
chk(end+1) = struct('name', 'V2 DCM orthogonality ||R''R - I||   ', ...
                    'value', max(orthErr),   'tol', 1e-12, 'cmp', 'le');
chk(end+1) = struct('name', 'V3 DCM determinant |det(R) - 1|    ', ...
                    'value', max(detErr),    'tol', 1e-12, 'cmp', 'le');
chk(end+1) = struct('name', 'V4 angular momentum drift (rel)    ', ...
                    'value', max(Hdrift),    'tol', 1e-8,  'cmp', 'le');
chk(end+1) = struct('name', 'V5 kinetic energy drift (rel)      ', ...
                    'value', max(Tdrift),    'tol', 1e-9,  'cmp', 'le');
chk(end+1) = struct('name', 'V6 capture radius deviation (rel)  ', ...
                    'value', max(radiusDev), 'tol', 1e-12, 'cmp', 'le');
chk(end+1) = struct('name', 'V7 velocity vs finite diff (rel)   ', ...
                    'value', max(vErrRel),   'tol', 1e-4,  'cmp', 'le');
chk(end+1) = struct('name', 'V8 velocity-radius perpendicularity', ...
                    'value', max(perpErr),   'tol', 1e-12, 'cmp', 'le');
% V9 sign convention: clearance = (how far the capture point sits OUTSIDE the
% forbidden sphere). Positive = outside = mission feasible; zero or negative
% would mean the capture point is on or inside the forbidden region.
chk(end+1) = struct('name', 'V9 capture-point clearance [m]     ', ...
                    'value', min(radii) - p.geom.r_target, 'tol', 0, 'cmp', 'ge');

%% ---- report ----
fprintf('=============================================================\n');
fprintf(' H1 VALIDATION - torque-free tumbling target + capture point\n');
fprintf(' %s | T = %g s | dt = %g s | N = %d samples\n', ...
    string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), p.sim.T_final, p.sim.dt, N);
fprintf('=============================================================\n');

nFail = 0;
for k = 1:numel(chk)
    switch chk(k).cmp
        case 'le', ok = chk(k).value <= chk(k).tol;  sym = '<=';
        case 'ge', ok = chk(k).value >= chk(k).tol;  sym = '>=';
        otherwise, error('validate_h1:cmp', 'unknown comparison "%s"', chk(k).cmp);
    end
    if ~ok, nFail = nFail + 1; end
    fprintf('  %s : %11.3e   (%s %8.1e)  %s\n', ...
        chk(k).name, chk(k).value, sym, chk(k).tol, upper_pf(ok));
end

fprintf('-------------------------------------------------------------\n');
fprintf('  scenario: |w0| = %.4f rad/s (%.2f deg/s), I = diag(%g %g %g)\n', ...
    norm(p.target.w0), rad2deg(norm(p.target.w0)), I(1,1), I(2,2), I(3,3));
fprintf('  geometry: r_target = %.3f m, r_grapple = %.3f m, clearance = %.3f m\n', ...
    p.geom.r_target, p.geom.r_grapple, p.geom.r_grapple - p.geom.r_target);
fprintf('  capture-point speed: %.4f .. %.4f m/s\n', ...
    min(vecnorm(vcpHist)), max(vecnorm(vcpHist)));
fprintf('=============================================================\n');

%% ---- figures ----
plot_scenario_3d(t, qHist, pcpHist, ncpHist, p);
f1 = gcf;

f2 = figure('Name', 'H1 validation diagnostics', 'Color', 'w');
subplot(2,2,1);
semilogy(t, max(qNormErr, eps), 'LineWidth', 1.1); grid on;
xlabel('t [s]'); ylabel('| ||q|| - 1 |'); title('V1  quaternion norm');
subplot(2,2,2);
semilogy(t, max(Hdrift, eps), 'LineWidth', 1.1); grid on;
xlabel('t [s]'); ylabel('relative drift'); title('V4  angular momentum (inertial)');
subplot(2,2,3);
semilogy(t, max(Tdrift, eps), 'LineWidth', 1.1); grid on;
xlabel('t [s]'); ylabel('relative drift'); title('V5  rotational kinetic energy');
subplot(2,2,4);
plot(t, radii, 'LineWidth', 1.4); grid on; hold on;
yline(p.geom.r_target, 'r--', 'r_{target}');
ylim([0, 1.15*p.geom.r_grapple]);
xlabel('t [s]'); ylabel('||p_{cp}|| [m]'); title('V6/V9  capture radius vs forbidden sphere');

if ~exist(dataDir, 'dir'), mkdir(dataDir); end
force_light_figure(f1);   % export on white regardless of the desktop theme
force_light_figure(f2);
exportgraphics(f1, fullfile(dataDir, 'h1_scenario.png'),   'Resolution', 150);
exportgraphics(f2, fullfile(dataDir, 'h1_validation.png'), 'Resolution', 150);
fprintf('  figures written to data/h1_scenario.png, data/h1_validation.png\n');

%% ---- verdict ----
if nFail > 0
    error('validate_h1:failed', 'H1 VALIDATION FAILED (%d of %d checks).', ...
        nFail, numel(chk));
end
fprintf('  H1 VALIDATION PASSED (%d/%d checks).\n', numel(chk), numel(chk));

%% ---- local functions ----
function s = upper_pf(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end


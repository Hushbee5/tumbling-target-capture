% RUN_H1_DEMO  Week-1 milestone driver.
%   Propagates the tumbling target, computes the body-fixed capture point
%   trajectory in LVLH, and renders the 3D scenario. Run this file directly.
%
%   Milestone check (H1): open-loop sim runs, target tumbles, the capture
%   point traces a path on a sphere of radius r_grapple around the body.

clear; clc; close all;

% Add the whole src/ tree to the path (this file lives in src/sim/).
thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..')));

% --- configuration ---
p = params();

% --- propagate target tumbling ---
[t, qHist, wHist] = target_tumbling_model(p);

% --- capture point trajectory in LVLH ---
[pcpHist, vcpHist, ncpHist] = capture_point_trajectory(qHist, wHist, p);

% --- sanity prints ---
fprintf('--- H1 demo ---\n');
fprintf('mean motion n     = %.4e rad/s  (orbit period %.1f min)\n', ...
    p.orbit.n, 2*pi/p.orbit.n/60);
fprintf('body radius       = %.3f m\n', p.geom.r_body);
fprintf('capture radius    = %.3f m  (must be > body radius)\n', p.geom.r_grapple);
fprintf('capture-pt speed  = %.4f .. %.4f m/s\n', ...
    min(vecnorm_local(vcpHist)), max(vecnorm_local(vcpHist)));
fprintf('quaternion norm err (max) = %.2e\n', ...
    max(abs(sqrt(sum(qHist.^2,1)) - 1)));

% --- visualize ---
plot_scenario_3d(t, qHist, pcpHist, ncpHist, p);

% --- local helper ---
function nv = vecnorm_local(V)
    nv = sqrt(sum(V.^2, 1));
end

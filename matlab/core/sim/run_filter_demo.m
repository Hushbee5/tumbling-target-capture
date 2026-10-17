% RUN_FILTER_DEMO  Task 2 demonstration: HOCBF-QP safety filter in isolation.
%   Runs the two scenarios of notes/task2_spec_hocbf_qp.md Sec. 7 and produces
%   figure F4:
%     N1  benign standoff reference     -> the filter must not interfere
%     N1b tumbling capture-point track  -> reported diagnostic (tight geometry)
%     N2  reference at the target COM   -> structurally unsafe naive guidance
%
%   For N2 both a filtered and an unfiltered run are made, so the figure shows
%   the same nominal command with and without the filter. No MPC, no
%   uncertainty, no tuned parameters.

clear; clc; close all;

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..')));
dataDir = fullfile(thisDir, '..', '..', 'data');

p = params();

% N2 needs a horizon long enough for the naive guidance to actually reach the
% keep-out sphere: the PD has a ~32 s time constant, so from 10 m it needs about
% 140 s just to touch it. The baseline 120 s scenario is too short to expose the
% structural unsafety. Nothing else is changed.
T_N2 = 200;

fprintf('=============================================================\n');
fprintf(' TASK 2 DEMO - HOCBF-QP safety filter (no MPC)\n');
fprintf(' %s\n', string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')));
fprintf('=============================================================\n');
cbf_gain_design(p);

%% N1 -- benign standoff: the filter should stay out of the way
oN1 = simulate_filtered(p, struct('ref_mode','point', 'r_ref',[0;-3;0], ...
                                  'use_filter',true));
fprintf('\n N1 benign standoff (r_ref = [0 -3 0] m):\n');
fprintf('   peak ||u_safe - u_nom||_inf = %.3e m/s^2   (threshold %.0e)\n', ...
    max(oN1.dev_inf), p.cbf.act_thresh);
fprintf('   active steps = %.1f %%,  min clearance = %.3f m\n', ...
    100*mean(oN1.active), min(oN1.d_safe));

%% N1b -- tracking the tumbling capture point (diagnostic for the tight geometry)
oN1b = simulate_filtered(p, struct('ref_mode','capture', 'use_filter',true));
fprintf('\n N1b capture-point tracking (diagnostic, not a pass/fail case):\n');
fprintf('   min clearance = %.4f m  (capture point sits %.3f m outside r_safe)\n', ...
    min(oN1b.d_safe), p.geom.r_grapple - p.geom.r_safe);
fprintf('   active steps = %.1f %%,  peak deviation = %.3e m/s^2\n', ...
    100*mean(oN1b.active), max(oN1b.dev_inf));

%% N2 -- structurally unsafe nominal, with and without the filter
oN2n = simulate_filtered(p, struct('ref_mode','origin','use_filter',false,'Tsim',T_N2));
oN2f = simulate_filtered(p, struct('ref_mode','origin','use_filter',true, 'Tsim',T_N2));

fprintf('\n N2 naive guidance aimed at the target COM (T = %g s):\n', T_N2);
fprintf('   unfiltered: min d = %+.4f m  -> %s\n', min(oN2n.d_safe), ...
    ternary(min(oN2n.d_safe) < 0, 'KEEP-OUT VIOLATED', 'no violation'));
fprintf('   filtered  : min d = %+.4f m  -> %s\n', min(oN2f.d_safe), ...
    ternary(min(oN2f.d_safe) < 0, 'KEEP-OUT VIOLATED', 'safe'));
fprintf('   filtered  : min h = %+.4e, min psi1 = %+.4e, min psi2 = %+.3e\n', ...
    min(oN2f.h), min(oN2f.psi1), min(oN2f.psi2));
fprintf('   filtered  : intersample min h = %+.4e, min psi2 = %+.3e\n', ...
    oN2f.inter.h_min, oN2f.inter.psi2_min);
fprintf('   filtered  : active %.1f %% of steps, peak deviation %.3e m/s^2\n', ...
    100*mean(oN2f.active), max(oN2f.dev_inf));
fprintf('   peak ||u_nom||_inf = %.4f, peak ||u_safe||_inf = %.4f  (u_max = %.4f)\n', ...
    max(abs(oN2f.Unom(:))), max(abs(oN2f.Usafe(:))), p.chaser.u_max);
fprintf('   min feasibility margin = %.4e\n', min(oN2f.feas_margin));

%% figure F4
pt = p;  pt.sim.dt = p.ctrl.Ts;  pt.sim.T_final = T_N2;
[tt, qH, wH] = target_tumbling_model(pt);
[pI, vI, nI] = capture_point_trajectory(qH, wH, pt);
pcpL         = capture_point_lvlh(tt, pI, vI, nI, pt);

fig = plot_f4_safety(oN2f, oN2n, p, pcpL);
if ~exist(dataDir, 'dir'), mkdir(dataDir); end
force_light_figure(fig);
exportgraphics(fig, fullfile(dataDir, 'f4_safety_filter.png'), 'Resolution', 150);
fprintf('\n figure written to data/f4_safety_filter.png\n');
fprintf('=============================================================\n');

%% ----- local functions -----
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end

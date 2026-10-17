function fig = plot_f4_safety(oF, oN, p, pcpL)
% PLOT_F4_SAFETY  Figure F4: the safety-filter result (spec Sec. 9).
%   fig = plot_f4_safety(oF, oN, p, pcpL) draws the four panels agreed for the
%   manuscript figure, from two runs of simulate_filtered:
%     oF  filtered run
%     oN  unfiltered run of the same nominal command
%     p   parameters
%     pcpL (optional) 3xN capture-point path in LVLH, for context
%
%   (a) trajectory and geometry      (b) clearance d(t) with the zero boundary
%   (c) u_nom versus u_safe          (d) HOCBF residual and filter activity

    fig = figure('Name', 'F4 safety filter', 'Color', 'w', ...
                 'Position', [60 60 1180 820]);

    % ---- (a) trajectory and geometry -----------------------------------
    subplot(2,2,1); hold on; grid on; axis equal;
    [xs, ys, zs] = sphere(28);
    surf(p.geom.r_safe*xs, p.geom.r_safe*ys, p.geom.r_safe*zs, ...
        'FaceColor', [0.85 0.25 0.25], 'FaceAlpha', 0.16, 'EdgeColor', 'none');
    surf(p.geom.r_target*xs, p.geom.r_target*ys, p.geom.r_target*zs, ...
        'FaceColor', [0.35 0.35 0.35], 'FaceAlpha', 0.30, 'EdgeColor', 'none');
    if nargin > 3 && ~isempty(pcpL)
        plot3(pcpL(1,:), pcpL(2,:), pcpL(3,:), '-', 'Color', [0 0.6 0.2], ...
              'LineWidth', 1.0);
    end
    plot3(oN.X(1,:), oN.X(2,:), oN.X(3,:), '--', 'Color', [0.85 0.33 0.10], ...
          'LineWidth', 1.6);
    plot3(oF.X(1,:), oF.X(2,:), oF.X(3,:), '-',  'Color', [0 0.45 0.74], ...
          'LineWidth', 1.8);
    % Zoom on the terminal region: at full scale the 0.7 m sphere is invisible
    % against a 10 m approach. The start (10 m on the -V-bar) is off-frame.
    L = 1.4;
    xlim([-L L]); ylim([-L L]); zlim([-L L]);
    view(28, 18);
    xlabel('x radial [m]'); ylabel('y along-track [m]'); zlabel('z [m]');
    title(sprintf('(a) Terminal geometry (start at %.0f m, off-frame)', ...
        norm(oF.X(1:3,1))));
    legend({'keep-out r_{safe}', 'target body', 'capture point', ...
            'nominal only', 'filtered'}, 'Location', 'southoutside', ...
            'NumColumns', 2);

    % ---- (b) clearance --------------------------------------------------
    subplot(2,2,2); hold on; grid on;
    plot(oN.t, oN.d_safe, '--', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.6);
    plot(oF.t, oF.d_safe, '-',  'Color', [0 0.45 0.74], 'LineWidth', 1.8);
    yline(0, 'r-', 'keep-out boundary', 'LineWidth', 1.2);
    xlabel('t [s]'); ylabel('d = ||r|| - r_{safe} [m]');
    title(sprintf('(b) Clearance   (min: nominal %.3f m, filtered %.3f m)', ...
        min(oN.d_safe), min(oF.d_safe)));
    legend({'nominal only', 'filtered'}, 'Location', 'best');

    % ---- (c) commands ---------------------------------------------------
    subplot(2,2,3); hold on; grid on;
    tc = oF.t(1:size(oF.Unom,2));
    % Per-axis bound compared against the INF-norm (a 2-norm would be
    % incompatible: with a box, ||u||_2 may reach sqrt(3)*u_max).
    plot(tc, max(abs(oF.Unom),[],1),  '--', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.4);
    plot(tc, max(abs(oF.Usafe),[],1), '-',  'Color', [0 0.45 0.74], 'LineWidth', 1.6);
    yline(p.chaser.u_max, 'k:', 'u_{max} (per axis)', 'LineWidth', 1.0);
    xlabel('t [s]'); ylabel('||u||_\infty [m/s^2]');
    title('(c) Nominal versus filtered command');
    legend({'||u_{nom}||_\infty', '||u_{safe}||_\infty'}, 'Location', 'best');

    % ---- (d) intervention and the sampled-data residual ------------------
    % At the sampling instants psi2 is exactly 0 whenever the row is active, so
    % plotting it there shows only machine noise. The informative quantity is
    % the residual BETWEEN samples, which is where the zero-order hold costs
    % something (spec Sec. 5).
    subplot(2,2,4);
    yyaxis left
    plot(tc, oF.dev_inf, '-', 'LineWidth', 1.5); hold on;
    yline(p.cbf.act_thresh, ':', 'activation threshold');
    ylabel('||u_{safe} - u_{nom}||_\infty [m/s^2]');
    yyaxis right
    if ~isempty(oF.inter.t)
        plot(oF.inter.t, oF.inter.psi2, '-', 'LineWidth', 1.0);
    end
    yline(0, 'k:');
    ylabel('\psi_2 between samples [m^2/s^2]');
    grid on; xlabel('t [s]');
    title(sprintf('(d) Intervention, active %.0f%% (\\psi_2 = 0 at samples)', ...
        100*mean(oF.active)));
end

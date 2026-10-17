function fig = plot_f3_tracking(oF, oN, p)
% PLOT_F3_TRACKING  Task 3 figure: preview MPC approach with the HOCBF filter.
%   fig = plot_f3_tracking(oF, oN, p) draws four panels from a filtered run oF
%   and the corresponding unfiltered MPC run oN.
%
%   (a) approach geometry with the tumbling capture-point path
%   (b) distance to the moving capture point and clearance to the keep-out sphere
%   (c) commands: MPC versus filtered, with the actuator limit
%   (d) HOCBF intervention magnitude and closing speed against the heuristic

    fig = figure('Name','F3 preview MPC + HOCBF', 'Color','w', ...
                 'Position',[60 60 1180 820]);

    % ---- (a) geometry -----------------------------------------------------
    subplot(2,2,1); hold on; grid on; axis equal;
    [xs, ys, zs] = sphere(28);
    surf(p.geom.r_safe*xs, p.geom.r_safe*ys, p.geom.r_safe*zs, ...
        'FaceColor',[0.85 0.25 0.25], 'FaceAlpha',0.15, 'EdgeColor','none');
    surf(p.geom.r_target*xs, p.geom.r_target*ys, p.geom.r_target*zs, ...
        'FaceColor',[0.35 0.35 0.35], 'FaceAlpha',0.30, 'EdgeColor','none');
    plot3(oF.Pcp(1,:), oF.Pcp(2,:), oF.Pcp(3,:), '-', 'Color',[0 0.6 0.2], 'LineWidth',1.1);
    plot3(oF.X(1,:), oF.X(2,:), oF.X(3,:), '-', 'Color',[0 0.45 0.74], 'LineWidth',1.8);
    plot3(oF.X(1,1), oF.X(2,1), oF.X(3,1), 'ko','MarkerFaceColor','k','MarkerSize',6);
    plot3(oF.X(1,end), oF.X(2,end), oF.X(3,end), 'bs','MarkerFaceColor','b','MarkerSize',7);
    L = 2.2; xlim([-L L]); ylim([-L L]); zlim([-L L]); view(28,18);
    xlabel('x radial [m]'); ylabel('y along-track [m]'); zlabel('z [m]');
    title(sprintf('(a) Terminal geometry (start %.0f m, off-frame)', norm(oF.X(1:3,1))));
    legend({'keep-out r_{safe}','target body','capture-point path','chaser', ...
            'start','end'}, 'Location','southoutside','NumColumns',3);

    % ---- (b) distances ----------------------------------------------------
    subplot(2,2,2); hold on; grid on;
    plot(oF.t, oF.s_cp, '-',  'Color',[0 0.45 0.74], 'LineWidth',1.8);
    plot(oF.t, oF.d_safe, '-',  'Color',[0.47 0.67 0.19], 'LineWidth',1.5);
    yline(0, 'r-', 'keep-out boundary', 'LineWidth',1.2);
    % At exact capture geometry s_cp = 0 while d_safe = r_grapple - r_safe.
    % The line marks the CLEARANCE at that configuration, not where s_cp lands.
    yline(p.geom.r_grapple - p.geom.r_safe, 'k:', 'd_{safe} at exact capture geometry');
    set(gca,'YScale','log'); ylim([1e-2 20]);
    xlabel('t [s]'); ylabel('[m]');
    title(sprintf('(b) Approach: final ||r-p_{cp}|| = %.3f m, min d = %.3f m', ...
        oF.s_cp(end), min(oF.d_safe)));
    legend({'distance to capture point','clearance to keep-out'}, 'Location','best');

    % ---- (c) commands -----------------------------------------------------
    subplot(2,2,3); hold on; grid on;
    tc = oF.t(1:size(oF.Umpc,2));
    % Per-axis actuator bound must be compared against the INF-norm, not the
    % 2-norm: with a box constraint ||u||_2 may legitimately reach sqrt(3)*u_max.
    plot(tc, max(abs(oF.Umpc),[],1),  '--','Color',[0.85 0.33 0.10],'LineWidth',1.3);
    plot(tc, max(abs(oF.Usafe),[],1), '-', 'Color',[0 0.45 0.74],'LineWidth',1.6);
    yline(p.chaser.u_max, 'k:', 'u_{max} (per axis)');
    xlabel('t [s]'); ylabel('||u||_\infty [m/s^2]');
    % No efficiency claim in the figure: the filtered and unfiltered runs do not
    % have matched terminal states at the final time, so their Delta-v totals are
    % not comparable. The matched-distance comparison lives in the validation log.
    title('(c) Commanded versus filtered acceleration');
    legend({'||u_{MPC}||_\infty','||u_{safe}||_\infty'}, 'Location','best');

    % ---- (d) intervention and closing speed --------------------------------
    subplot(2,2,4);
    yyaxis left
    plot(tc, oF.dev_inf, '-', 'LineWidth',1.5); hold on;
    yline(0.25*p.chaser.u_max, ':', 'E2 threshold 0.25 u_{max}');
    ylabel('||u_{safe} - u_{MPC}||_\infty [m/s^2]');
    yyaxis right
    plot(oF.t, oF.v_close, '-', 'LineWidth',1.3);
    yline(0, 'k:');
    ylabel('closing speed to capture point [m/s]');
    grid on; xlabel('t [s]');
    title(sprintf('(d) HOCBF intervention (active %.0f%% of steps)', ...
        100*mean(oF.active)));
end

function plot_scenario_3d(t, qHist, pcpHist, ncpHist, p)
% PLOT_SCENARIO_3D  Visualize the H1 scenario in 3D (LVLH frame).
%   plot_scenario_3d(t, qHist, pcpHist, ncpHist, p) draws:
%     - the target body sphere (radius r_target)
%     - the capture-point trajectory as the target tumbles
%     - target body axes at a few instants
%     - the approach-corridor cone at the final instant
%
%   Inputs come from target_tumbling_model + capture_point_trajectory.

    figure('Name', 'H1 scenario', 'Color', 'w');
    hold on; grid on; axis equal;

    % --- target body sphere ---
    [xs, ys, zs] = sphere(30);
    surf(p.geom.r_target*xs, p.geom.r_target*ys, p.geom.r_target*zs, ...
        'FaceColor', [0.85 0.25 0.25], 'FaceAlpha', 0.18, 'EdgeColor', 'none');

    % --- capture-point trajectory ---
    plot3(pcpHist(1,:), pcpHist(2,:), pcpHist(3,:), '-', ...
        'Color', [0.1 0.3 0.8], 'LineWidth', 1.4);
    plot3(pcpHist(1,1), pcpHist(2,1), pcpHist(3,1), 'go', ...
        'MarkerFaceColor', 'g', 'MarkerSize', 8);          % start
    plot3(pcpHist(1,end), pcpHist(2,end), pcpHist(3,end), 'ks', ...
        'MarkerFaceColor', 'k', 'MarkerSize', 8);          % end

    % --- target body axes at sampled instants ---
    nFrames = 6;
    idx = round(linspace(1, size(qHist,2), nFrames));
    L = 0.35;
    axCols = {'r','g','b'};
    for k = idx
        R = quat_to_rotm(qHist(:,k));
        for ax = 1:3
            quiver3(0,0,0, R(1,ax)*L, R(2,ax)*L, R(3,ax)*L, 0, ...
                'Color', axCols{ax}, 'LineWidth', 1.0, 'MaxHeadSize', 0.5);
        end
    end

    % --- approach corridor cone at final instant ---
    draw_corridor(pcpHist(:,end), ncpHist(:,end), p);

    xlabel('x_{LVLH} [m]'); ylabel('y_{LVLH} [m]'); zlabel('z_{LVLH} [m]');
    title(sprintf('H1: tumbling target + capture point (T = %.0f s)', t(end)));
    legend({'target body','capture-point path','start','end'}, ...
        'Location', 'bestoutside');
    view(135, 25);
    hold off;
end

% ----- local functions -----
function draw_corridor(apex, axisDir, p)
% Translucent cone: apex at capture point, opening along outward axis.
    axisDir = axisDir / norm(axisDir);
    Lc = p.geom.L_corridor;
    rEnd = Lc * tan(p.geom.theta_c);
    % build a circle at the cone base, perpendicular to axisDir
    tmp = [1;0;0]; if abs(dot(tmp, axisDir)) > 0.9, tmp = [0;1;0]; end
    u = cross(axisDir, tmp); u = u/norm(u);
    v = cross(axisDir, u);
    th = linspace(0, 2*pi, 24);
    baseC = apex + axisDir*Lc;
    ring = baseC + rEnd*(u*cos(th) + v*sin(th));
    for i = 1:numel(th)
        plot3([apex(1) ring(1,i)], [apex(2) ring(2,i)], [apex(3) ring(3,i)], ...
            '-', 'Color', [0.2 0.6 0.2 0.25]);
    end
    plot3(ring(1,:), ring(2,:), ring(3,:), '-', 'Color', [0.2 0.6 0.2 0.4]);
end

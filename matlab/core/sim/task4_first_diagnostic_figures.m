function task4_first_diagnostic_figures()
% TASK4_FIRST_DIAGNOSTIC_FIGURES  Read-only diagnostic figures for the H-1 run.
%
%   Reads results/task4/task4_first_diagnostic_400s_alpha1e3.mat and writes seven
%   diagnostic PNGs to results/task4/. It reruns nothing and modifies nothing.
%
%   THESE ARE DIAGNOSTIC FIGURES, NOT MANUSCRIPT FIGURES. The simulation is not
%   changed because of how any of them looks.
%
%   GEOMETRY IS ONLY WHAT THE MODEL CONTAINS: the chaser is a point mass, the
%   target is a keep-out sphere of radius r_safe with a body-fixed capture point
%   at p_cp_body, and the commitment sphere has radius s_cap about that capture
%   point. No manipulator, gripper or structure is drawn, because none exists in
%   the model.
%
%   ANIMATION DATA. Everything a later read-only 3D animation needs is already in
%   the saved file: out.t, out.X (chaser state), out.qT (target attitude) and
%   out.wT. The capture point is reconstructed exactly as below, so no extra
%   logging is required and no source change is needed.

    thisDir = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(thisDir, '..')));
    outDir = fullfile(thisDir, '..', '..', 'results', 'task4');
    S = load(fullfile(outDir, 'task4_first_diagnostic_400s_alpha1e3.mat'));
    out = S.out;  p = S.p;
    pb = p.target.p_cp_body(:);  nS = numel(out.t);

    % exact capture-point reconstruction from the logged attitude
    Pcp = zeros(3, nS);
    for k = 1:nS
        [~, R_LI, ~] = lvlh_frame(out.t(k), p);
        Pcp(:,k) = R_LI * quat_to_rotm(out.qT(:,k)) * pb;
    end
    t = out.t;  X = out.X;  K = out.K_applied;  tc = t(1:K);
    ev = out.event_log;

    %% F1 - 3D trajectory, capture-point path, keep-out sphere
    f = figure('Position',[100 100 900 700],'Color','w');
    [sx,sy,sz] = sphere(40);
    surf(p.geom.r_safe*sx, p.geom.r_safe*sy, p.geom.r_safe*sz, ...
        'FaceColor',[0.85 0.35 0.35],'FaceAlpha',0.20,'EdgeColor','none'); hold on
    plot3(X(1,:),X(2,:),X(3,:),'b-','LineWidth',1.4);
    plot3(Pcp(1,:),Pcp(2,:),Pcp(3,:),'-','Color',[0.2 0.6 0.2],'LineWidth',1.0);
    plot3(X(1,1),X(2,1),X(3,1),'bo','MarkerFaceColor','b','MarkerSize',7);
    plot3(X(1,end),X(2,end),X(3,end),'bs','MarkerFaceColor','b','MarkerSize',7);
    plot3(0,0,0,'k+','MarkerSize',10,'LineWidth',1.5);
    if ~isempty(ev)
        plot3(X(1,ev.k),X(2,ev.k),X(3,ev.k),'rp','MarkerFaceColor','r','MarkerSize',16);
    end
    axis equal; grid on; box on; view(35,22);
    xlabel('x_{LVLH} [m] (radial)'); ylabel('y_{LVLH} [m] (along-track)'); zlabel('z_{LVLH} [m]');
    title(sprintf('F1  Task 4 first diagnostic, %g s, alpha = %.0e', out.Tsim, out.alpha));
    legend({'keep-out sphere r_{safe}','chaser','capture point','start','end','target COM'}, ...
        'Location','best'); hold off
    save_fig(f, outDir, 'f_t4d_01_trajectory3d.png');

    %% F2 - range and the commitment boundaries
    f = figure('Position',[100 100 950 520],'Color','w');
    semilogy(t, out.rho, 'b-','LineWidth',1.3); hold on
    yline(out.s_cap,'r-','LineWidth',1.4);
    yline(out.s_cap+out.eps_rho,'m--','LineWidth',1.1);
    yline(p.geom.r_safe,'k:','LineWidth',1.1);
    if ~isempty(ev), xline(ev.t,'g-','LineWidth',1.2); end
    grid on; xlabel('t [s]'); ylabel('||d|| [m]  (log scale)');
    title('F2  range to the capture point vs the frozen boundaries');
    legend({'||d||','s_{cap}','s_{cap}+\epsilon_\rho','r_{safe} (scale ref)'},'Location','best');
    hold off; save_fig(f, outDir, 'f_t4d_02_range.png');

    %% F3 - barrier functions and the HOCBF chain
    f = figure('Position',[100 100 950 760],'Color','w');
    subplot(3,1,1)
      semilogy(t, max(out.h_body,eps),'k-','LineWidth',1.2); hold on
      semilogy(t, max(out.h_cap ,eps),'b-','LineWidth',1.2);
      grid on; ylabel('h  [m^2]'); legend({'h_{body}','h_{cap}'},'Location','best');
      title('F3  barrier functions and the HOCBF chain (sampled)'); hold off
    subplot(3,1,2)
      plot(t, out.psi1_body,'k-','LineWidth',1.1); hold on
      plot(t, out.psi1_cap ,'b-','LineWidth',1.1); yline(0,'r--');
      grid on; ylabel('\psi_1'); legend({'\psi_1 body','\psi_1 cap'},'Location','best'); hold off
    subplot(3,1,3)
      plot(tc, out.psi2_body,'k-','LineWidth',1.0); hold on
      plot(tc, out.psi2_cap ,'b-','LineWidth',1.0); yline(0,'r--');
      grid on; xlabel('t [s]'); ylabel('\psi_2 at the applied command');
      legend({'\psi_2 body','\psi_2 cap'},'Location','best'); hold off
    save_fig(f, outDir, 'f_t4d_03_barriers.png');

    %% F4 - commanded vs filtered control
    f = figure('Position',[100 100 950 700],'Color','w');
    lbl = {'u_x','u_y','u_z'};
    for i = 1:3
        subplot(3,1,i)
        plot(tc, out.Umpc(i,:),'-','Color',[0.6 0.6 0.6],'LineWidth',1.0); hold on
        plot(tc, out.Usafe(i,:),'b-','LineWidth',1.0);
        yline( p.chaser.u_max,'r:'); yline(-p.chaser.u_max,'r:');
        grid on; ylabel([lbl{i} ' [m/s^2]']);
        if i==1, title('F4  MPC command vs filtered command (box \pm u_{max})');
                 legend({'u_{MPC}','u_{safe}'},'Location','best'); end
        if i==3, xlabel('t [s]'); end
        hold off
    end
    save_fig(f, outDir, 'f_t4d_04_control.png');

    %% F5 - intervention magnitude and active rows
    f = figure('Position',[100 100 950 620],'Color','w');
    subplot(2,1,1)
      plot(tc, out.dev_inf,'b-','LineWidth',1.0); hold on
      yline(0.25*p.chaser.u_max,'r--'); grid on
      ylabel('||u_{safe}-u_{MPC}||_\infty'); title('F5  safety-filter intervention and active rows');
      legend({'deviation','0.25 u_{max}'},'Location','best'); hold off
    subplot(2,1,2)
      stairs(tc, double(out.row_active_body),'k-','LineWidth',1.0); hold on
      stairs(tc, double(out.row_active_cap)+1.5,'b-','LineWidth',1.0);
      stairs(tc, double(out.cap_enforced)+3.0,'-','Color',[0.5 0.5 0.5],'LineWidth',1.0);
      grid on; ylim([-0.3 4.3]); yticks([0 1 1.5 2.5 3 4]);
      yticklabels({'body 0','body 1','cap 0','cap 1','enf 0','enf 1'});
      xlabel('t [s]'); legend({'body row active','capture row active','capture row enforced'}, ...
        'Location','best'); hold off
    save_fig(f, outDir, 'f_t4d_05_intervention.png');

    %% F6 - estimator
    f = figure('Position',[100 100 950 620],'Color','w');
    subplot(2,1,1)
      plot(tc, out.theta_hat(1,:),'r-','LineWidth',1.1); hold on
      plot(tc, out.theta_hat(2,:),'g-','LineWidth',1.1);
      plot(tc, out.theta_hat(3,:),'b-','LineWidth',1.1);
      yline(out.theta_true(1),'r:'); yline(out.theta_true(2),'g:'); yline(out.theta_true(3),'b:');
      grid on; ylabel('\theta_{hat}'); title('F6  concurrent-learning estimator (causal)');
      legend({'\theta_1','\theta_2','\theta_3'},'Location','best'); hold off
    subplot(2,1,2)
      err = vecnorm(out.theta_hat - out.theta_true);
      semilogy(tc, max(out.nu,eps),'k-','LineWidth',1.3); hold on
      semilogy(tc, max(err,eps),'b-','LineWidth',1.1);
      grid on; xlabel('t [s]'); ylabel('bound / error');
      legend({'\nu_{sp}(t)','||\theta - \theta_{hat}||'},'Location','best'); hold off
    save_fig(f, outDir, 'f_t4d_06_estimator.png');

    %% F7 - D9 event neighbourhood, or the closest approach if no event
    f = figure('Position',[100 100 950 620],'Color','w');
    if ~isempty(ev), tc0 = ev.t; ttl = sprintf('F7  D9 %s at t = %.2f s', ev.event, ev.t);
    else, [~,ic] = min(out.rho); tc0 = t(ic); ttl = 'F7  closest approach (no D9 event fired)'; end
    w = t >= tc0-40 & t <= tc0+40;
    subplot(2,1,1)
      plot(t(w), out.rho(w),'b-','LineWidth',1.4); hold on
      yline(out.s_cap,'r-','LineWidth',1.4); yline(out.s_cap+out.eps_rho,'m--','LineWidth',1.1);
      if ~isempty(ev), xline(ev.t,'g-','LineWidth',1.2); end
      grid on; ylabel('||d|| [m]'); title(ttl);
      legend({'||d||','s_{cap}','s_{cap}+\epsilon_\rho'},'Location','best'); hold off
    subplot(2,1,2)
      plot(t(w), out.rho_dot(w),'b-','LineWidth',1.2); hold on; yline(0,'r--');
      if ~isempty(ev), xline(ev.t,'g-','LineWidth',1.2); end
      grid on; xlabel('t [s]'); ylabel('d(||d||)/dt [m/s]'); hold off
    save_fig(f, outDir, 'f_t4d_07_d9_event.png');

    fprintf('7 diagnostic figures written to %s\n', outDir);
end

function save_fig(f, d, name)
    if exist('force_light_figure','file'), force_light_figure(f); end
    exportgraphics(f, fullfile(d, name), 'Resolution', 150);
    close(f);
    fprintf('  wrote %s\n', name);
end

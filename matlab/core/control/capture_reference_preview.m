function [Pref, Vref, info] = capture_reference_preview(tk, x, N, p, tbl)
% CAPTURE_REFERENCE_PREVIEW  Horizon reference for the preview-based MPC.
%   [Pref, Vref, info] = capture_reference_preview(tk, x, N, p, tbl) returns the
%   position and velocity reference over the prediction horizon, built from the
%   predicted capture-point trajectory in tbl.
%
%   TWO DISTINCT DISTANCES - never share a symbol between them:
%     s_cp   = ||r - p_cp||     distance to the MOVING capture point (arrival)
%     d_safe = ||r|| - r_safe   clearance from the target-centred keep-out sphere
%                               (collision)
%
%   KINEMATICALLY CONSISTENT CONSTRUCTION (corrected 2026-08-09 after review).
%   The virtual reference stays on the direct chaser-to-capture-point line and
%   only a SCALAR closing speed is shaped:
%
%       Pref_j = Pcp_j + s_j * e_hat
%       Vref_j = Vcp_j - c_j * e_hat
%       s_{j+1} = max(0, s_j - c_j*Ts)
%
%   so the relative offset D_j = Pref_j - Pcp_j = s_j*e_hat satisfies
%   (D_{j+1} - D_j)/Ts = -c_j*e_hat = Vref_j - Vcp_j exactly.
%
%   The previous implementation shaped the velocity as a VECTOR along u_r while
%   advancing the scalar schedule with only its e_hat projection. Whenever u_r
%   was not parallel to e_hat that made Vref ~= d(Pref)/dt, which is a genuine
%   defect because the MPC penalises position and velocity tracking together.
%
%   RADIAL-ENVELOPE COMPATIBILITY (reference shaping, NOT a safety theorem).
%   The psi1 envelope bounds the INWARD RADIAL rate about the target COM and
%   says nothing about tangential motion, so only the scalar c is constrained:
%
%       -u_r' * Vref <= v_rad_env,    u_r = Pref/||Pref||
%       v_rad_env = gamma_env * k1 * d_safe * phi(rho),  phi = (rho+r_safe)/(2 rho)
%
%   With Vref = Vcp - c*e_hat this is linear in c:
%
%       c * A <= RHS,   A = u_r'*e_hat,   RHS = v_rad_env + u_r'*Vcp
%
%   and the admissible c is derived per geometric case (A > 0, A = 0, A < 0)
%   rather than by dividing blindly. The largest admissible c in [0, c_raw] is
%   taken, c_raw being the terminal braking heuristic. If NO nonnegative c can
%   satisfy the envelope - which happens when the capture point's own motion
%   already violates it at the virtual-reference position - the condition is
%   reported through info.env_infeasible and a best-effort c is used. The
%   approach DIRECTION is never altered to hide it, and no corridor logic is
%   introduced.
%
%   Outputs: Pref, Vref are 3x(N+1) for j = 0..N.

    Ts = p.ctrl.Ts;
    r  = x(1:3);
    v  = x(4:6);

    % --- capture-point trajectory over [tk, tk + N*Ts] ---
    idx0 = round(tk / tbl.Ts) + 1;
    idx  = idx0 + (0:N);
    if idx(end) > numel(tbl.t)
        error('capture_reference_preview:horizon', ...
            'capture table too short: need t = %.2f s, have %.2f s.', ...
            tk + N*Ts, tbl.t(end));
    end
    Pcp = tbl.pL(:, idx);
    Vcp = tbl.vL(:, idx);

    % --- current geometry ---
    dvec = r - Pcp(:,1);
    s_cp = norm(dvec);
    if s_cp > eps, e_hat = dvec / s_cp; else, e_hat = [0;0;0]; end
    v_close = -( dvec.' * (v - Vcp(:,1)) ) / max(s_cp, eps);

    % --- schedule ---
    Pref = zeros(3, N+1);
    Vref = zeros(3, N+1);
    s    = s_cp;
    c_raw0 = 0;  c_shaped0 = 0;  v_rad_env0 = 0;
    limited0 = false;  envInfeas0 = false;

    for j = 1:N+1
        Pref(:,j) = Pcp(:,j) + s*e_hat;

        % geometry of the virtual reference point
        rho_j = norm(Pref(:,j));
        if rho_j > eps, u_r = Pref(:,j)/rho_j; else, u_r = [0;0;0]; end
        d_safe_j  = rho_j - p.geom.r_safe;
        phi_j     = (rho_j + p.geom.r_safe) / (2*max(rho_j, eps));
        v_rad_env = p.capture.gamma_env * p.cbf.k1 * max(d_safe_j, 0) * phi_j;

        % terminal braking heuristic gives the unshaped closing speed
        c_raw = approach_speed_profile(s, p);

        % admissible scalar closing speed:  c*A <= RHS,  c in [0, c_raw]
        A   = u_r.' * e_hat;
        RHS = v_rad_env + u_r.' * Vcp(:,j);
        [c, wasLimited, envInfeas] = admissible_closing_speed(c_raw, A, RHS);

        % advance the schedule first, then derive the velocity from the ACTUAL
        % scheduled displacement, so that Vref = d(Pref)/dt holds exactly even
        % on the step where s reaches the floor at zero
        s_next = max(0, s - c*Ts);
        c_eff  = (s - s_next) / Ts;
        Vref(:,j) = Vcp(:,j) - c_eff*e_hat;

        if j == 1
            c_raw0     = c_raw;
            c_shaped0  = c_eff;
            v_rad_env0 = v_rad_env;
            % rad_limited means the ENVELOPE reduced the closing speed. It must
            % not be set by the terminal schedule clamp at s -> 0, nor by the
            % ~1e-15 round-off that (s - s_next)/Ts reintroduces into c_eff.
            limited0   = wasLimited;
            envInfeas0 = envInfeas;
            % inward radial rates implied by the raw and the shaped reference
            v_rad_raw0    = -( u_r.' * (Vcp(:,j) - c_raw*e_hat) );
            v_rad_shaped0 = -( u_r.' * Vref(:,j) );
        end

        s = s_next;
    end

    info.s_cp          = s_cp;
    info.v_close       = v_close;
    info.p_cp          = Pcp(:,1);
    info.v_cp          = Vcp(:,1);
    info.n_cp          = tbl.nL(:, idx0);
    info.e_hat         = e_hat;
    info.c_raw         = c_raw0;         % scalar closing speed before shaping [m/s]
    info.c_shaped      = c_shaped0;      % scalar closing speed actually scheduled [m/s]
    info.v_rad_raw     = v_rad_raw0;     % inward radial rate the raw reference implies
    info.v_rad_shaped  = v_rad_shaped0;  % inward radial rate the shaped reference implies
    info.v_rad_env     = v_rad_env0;     % gamma_env-scaled psi1 envelope [m/s]
    info.rad_limited   = limited0;
    info.env_infeasible = envInfeas0;    % no c >= 0 could satisfy the envelope
end

% ===== local functions =====================================================
function [c, wasLimited, envInfeas] = admissible_closing_speed(c_raw, A, RHS)
% Largest c in [0, c_raw] satisfying c*A <= RHS, handling every geometric case
% explicitly instead of dividing by A.
%
%   A   = u_r'*e_hat  is the radial projection of the closing direction.
%         A > 0 : closing moves the reference INWARD  (the usual case)
%         A = 0 : closing is purely tangential; c cannot affect the radial rate
%         A < 0 : closing moves the reference OUTWARD
%   RHS = v_rad_env + u_r'*Vcp
%
% When the feasible set is empty the condition is REPORTED and a best-effort c
% that minimises the violation is returned - the direction is never changed.

    tolA = 1e-12;
    envInfeas = false;

    if A > tolA
        cmax = RHS / A;                       % upper bound on c
        if cmax < 0
            % even c = 0 violates: the capture point's own radial motion
            % exceeds the envelope at this virtual-reference position
            envInfeas = true;
            c = 0;                            % minimises the violation
        else
            c = min(c_raw, cmax);
        end
    elseif A < -tolA
        cmin = RHS / A;                       % dividing by a negative flips it
        if cmin > c_raw
            envInfeas = true;
            c = c_raw;                        % minimises the violation (A < 0)
        else
            c = c_raw;                        % any c >= max(0, cmin) works
        end
    else
        % A ~ 0: c has no influence on the radial rate at all
        if RHS < 0
            envInfeas = true;
        end
        c = c_raw;
    end

    c = max(0, c);
    wasLimited = (c < c_raw - 1e-15);
end

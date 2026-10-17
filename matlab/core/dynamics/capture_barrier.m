function cb = capture_barrier(x, q, w, theta_hat, t, p)
% CAPTURE_BARRIER  Adaptive terminal commitment barrier h_cap and its HOCBF chain.
%   cb = capture_barrier(x, q, w, theta_hat, t, p) evaluates, at the measured
%   chaser state x = [r; v] (LVLH) and the measured target attitude/rate (q, w),
%
%       d      = r - p_cp_L(t)
%       h_cap  = ||d||^2 - s_cap^2          safe set  h_cap >= 0  <=>  ||d|| >= s_cap
%       hdot   = 2 d' (v - v_cp_L)
%       Lf2h   = 2 ||v - v_cp||^2 + 2 d' (a_drift - a_cp_L)
%       Lgh    = 2 d'
%       psi1   = hdot + kappa1 * h
%       psi2   = (Lf2h + Lgh u) + (kappa1+kappa2) hdot + kappa1 kappa2 h
%
%   as specified in notes/task4_freeze_record.md Sec. 2 and Sec. 3.
%
%   WHERE THE UNCERTAINTY ENTERS. p_cp and v_cp depend only on (q, w), which are
%   available by assumption A2, so they are exact. The capture-point ACCELERATION
%   needs omega_dot = Y_omega(w) * theta, so it is evaluated with the ESTIMATE
%   theta_hat and is the only uncertain term in the chain. The mismatch is
%   bounded by eta * nu and is what the row tightening covers:
%
%       eta = || L_Y L_f h_cap || = || 2 d' R_L [p_b]x diag(Y_omega(w)) ||
%
%   with Y_omega(w) = diag(w2 w3, w3 w1, w1 w2) exactly (freeze record Sec. 1).
%
%   Returned fields:
%     h, hdot, Lf2h, Lgh, psi1        barrier chain (psi2 needs a command)
%     eta                             tightening prefactor, >= 0
%     rho, rho_dot                    range and range rate to the capture point
%     d, p_cp, v_cp, a_cp_hat         geometry (a_cp_hat uses theta_hat)
%     v_rel_cp                        ||v - v_cp||, logged by the D9 detector
%
%   psi2 for a given command u is obtained as
%       psi2 = (cb.Lf2h + cb.Lgh*u) + (k1+k2)*cb.hdot + k1*k2*cb.h
%   or via CAPTURE_BARRIER_ROW, which builds the tightened QP row directly.

    r = x(1:3);  v = x(4:6);
    pb = p.target.p_cp_body(:);

    % --- target attitude in LVLH -------------------------------------------
    [~, R_LI, ~] = lvlh_frame(t, p);
    R  = R_LI * quat_to_rotm(q);                 % body -> LVLH
    wL = [0; 0; p.orbit.n];                      % LVLH frame rate, inertial-referenced
    wLb = R.' * wL;                              % same, expressed in the body frame
    wBL = w(:) - wLb;                            % body rate relative to LVLH

    % --- capture point: position and velocity are exact ---------------------
    p_cp = R * pb;
    v_cp = R * cross(wBL, pb);

    % --- capture-point acceleration: the only theta-dependent term ----------
    % d/dt (R' wL) = -wBL x (R' wL), so
    %   wBL_dot = w_dot - d/dt(R' wL) = Y_omega(w) theta + wBL x (R' wL)
    Yw   = [ w(2)*w(3); w(3)*w(1); w(1)*w(2) ];
    wdot = Yw .* theta_hat(:) + cross(wBL, wLb);
    a_cp = R * ( cross(wBL, cross(wBL, pb)) + cross(wdot, pb) );

    % --- barrier chain ------------------------------------------------------
    d  = r - p_cp;
    dd = v - v_cp;
    [~, aDrift] = rel_translational_dynamics(x, zeros(3,1), p, 'cw');

    rho = norm(d);
    cb.h    = d.'*d - p.t4.s_cap^2;
    cb.hdot = 2 * (d.'*dd);
    cb.Lf2h = 2*(dd.'*dd) + 2*(d.'*(aDrift - a_cp));
    cb.Lgh  = 2 * d.';
    cb.psi1 = cb.hdot + p.t4.kappa1 * cb.h;

    % --- tightening prefactor eta = ||L_Y L_f h_cap|| -----------------------
    Sb  = [   0   -pb(3)  pb(2);
            pb(3)    0   -pb(1);
           -pb(2)  pb(1)    0  ];               % [p_b]x
    cb.eta = norm( 2 * (d.') * R * Sb * diag(Yw) );

    % --- geometry and detector inputs ---------------------------------------
    cb.rho = rho;
    if rho < eps
        cb.rho_dot = 0;                          % direction undefined at contact
    else
        cb.rho_dot = (d.'*dd) / rho;
    end
    cb.d        = d;
    cb.p_cp     = p_cp;
    cb.v_cp     = v_cp;
    cb.a_cp_hat = a_cp;
    cb.v_rel_cp = norm(dd);
    cb.R_BL     = R;
    cb.Y_omega  = Yw;
end

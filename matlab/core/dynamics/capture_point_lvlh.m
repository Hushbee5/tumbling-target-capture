function [pcpL, vcpL, ncpL] = capture_point_lvlh(t, pcpI, vcpI, ncpI, p)
% CAPTURE_POINT_LVLH  Express the capture-point history in the LVLH frame.
%   [pcpL, vcpL, ncpL] = capture_point_lvlh(t, pcpI, vcpI, ncpI, p) maps the
%   inertial-frame capture-point history produced by capture_point_trajectory
%   into the rotating LVLH frame in which the relative translational dynamics
%   are written.
%
%   Position is a plain rotation, but the velocity seen in the rotating frame
%   also picks up the transport term:
%       p_L = R_LI * p_I
%       v_L = R_LI * v_I - cross(omega_L, p_L)
%       n_L = R_LI * n_I
%
%   Dropping the transport term is exactly the quasi-inertial approximation
%   rejected by decision D4; at r_grapple = 0.8 m it is worth n*r = 9.1e-4 m/s
%   (about 1.8% of the tumbling-induced speed) and accumulates into ~0.11 m of
%   position error over 120 s.
%
%   Inputs  (3xN, inertial frame)  : pcpI [m], vcpI [m/s], ncpI [-]
%   Outputs (3xN, LVLH frame)      : pcpL [m], vcpL [m/s], ncpL [-]
%   t is 1xN [s].

    N    = numel(t);
    pcpL = zeros(3, N);
    vcpL = zeros(3, N);
    ncpL = zeros(3, N);

    for k = 1:N
        [~, R_LI, omega_L] = lvlh_frame(t(k), p);
        pcpL(:, k) = R_LI * pcpI(:, k);
        vcpL(:, k) = R_LI * vcpI(:, k) - cross(omega_L, pcpL(:, k));
        ncpL(:, k) = R_LI * ncpI(:, k);
    end
end

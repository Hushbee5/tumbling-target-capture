function [pcpHist, vcpHist, ncpHist] = capture_point_trajectory(qHist, wHist, p)
% CAPTURE_POINT_TRAJECTORY  Position/velocity of the body-fixed capture point.
%   [pcpHist, vcpHist, ncpHist] = capture_point_trajectory(qHist, wHist, p)
%   maps the body-fixed capture point through the tumbling attitude history
%   into the INERTIAL frame (the target centre of mass is the origin).
%
%   FRAME NOTE: these outputs are inertial-frame quantities, because q(t) is
%   propagated inertially by target_tumbling_model. To obtain the LVLH-frame
%   history used by the relative translational dynamics, pass them through
%   capture_point_lvlh, which applies R_LI(t) and the transport term. Treating
%   the outputs below directly as LVLH is the quasi-inertial approximation
%   rejected by decision D4.
%
%   For a point fixed in the body at p_cp_body:
%       p_cp(t) = R(q(t)) * p_cp_body
%       v_cp(t) = R(q(t)) * ( w(t) x p_cp_body )   (rotation-induced velocity)
%       n_cp(t) = R(q(t)) * n_cp_body                    (capture axis)
%   with n_cp_body a MODELLING ASSUMPTION (baseline: radially outward).
%
%   Outputs (all 3xN, INERTIAL frame - see the FRAME NOTE above). The LVLH
%   versions are produced by capture_point_lvlh, which applies R_LI(t) and the
%   transport term; nothing here is expressed in LVLH.
%       pcpHist : capture point position, INERTIAL [m]
%       vcpHist : capture point velocity, INERTIAL [m/s]
%       ncpHist : capture-axis unit vector, INERTIAL

    N    = size(qHist, 2);
    pcb  = p.target.p_cp_body(:);
    % Capture AXIS comes from its own field (a modelling assumption, see
    % params.m); numerically identical to the normalised position in the
    % baseline, but no longer silently equated with it.
    nb   = p.target.n_cp_body(:);
    nb   = nb / norm(nb);

    pcpHist = zeros(3, N);
    vcpHist = zeros(3, N);
    ncpHist = zeros(3, N);

    for k = 1:N
        R = quat_to_rotm(qHist(:, k));
        pcpHist(:, k) = R * pcb;
        vcpHist(:, k) = R * cross(wHist(:, k), pcb);
        ncpHist(:, k) = R * nb;
    end
end

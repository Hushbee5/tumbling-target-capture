function [R_IL, R_LI, omega_L] = lvlh_frame(t, p)
% LVLH_FRAME  Rotation between the inertial frame and the target LVLH frame.
%   [R_IL, R_LI, omega_L] = lvlh_frame(t, p) returns, for a circular target
%   orbit of mean motion p.orbit.n:
%       R_IL     LVLH -> inertial rotation matrix (its columns are the LVLH
%                axes expressed in inertial coordinates)
%       R_LI     inertial -> LVLH rotation matrix, R_LI = R_IL'
%       omega_L  angular velocity of LVLH w.r.t. inertial, in LVLH coordinates
%
%   Frame definition (notes/conventions.md): LVLH has +x radial outward,
%   +y along-track, +z = x cross y (the orbit normal). Inertial axes are chosen
%   without loss of generality so that the two frames coincide at t = 0 and the
%   orbit normal lies along their common z. LVLH then rotates about +z at the
%   constant rate n, so
%       R_IL(t) = Rz(n t),   omega_L = [0; 0; n].
%   The first column of R_IL is [cos(n t); sin(n t); 0], i.e. the radial-outward
%   direction of a target that has travelled n*t along its orbit.
%
%   Usage:  v_L = R_LI * v_I    and    v_I = R_IL * v_L.
%   For a position expressed in LVLH the velocity seen in LVLH follows the
%   transport theorem:  v_L = R_LI*v_I - cross(omega_L, p_L).

    th = p.orbit.n * t;
    c  = cos(th);
    s  = sin(th);

    R_IL = [ c, -s, 0;
             s,  c, 0;
             0,  0, 1 ];
    R_LI = R_IL.';

    omega_L = [0; 0; p.orbit.n];
end

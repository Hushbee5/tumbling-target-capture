function R = quat_to_rotm(q)
% QUAT_TO_ROTM  Rotation matrix from a scalar-first unit quaternion.
%   R = quat_to_rotm(q) returns the BODY-to-WORLD rotation matrix, so that
%       v_world = R   * v_body
%       v_body  = R.' * v_world
%   q = [q0; q1; q2; q3] is Hamilton, scalar-first (see notes/conventions.md).
%   The input is normalized defensively; R is orthogonal with det(R) = +1.

    q  = q(:) / norm(q);
    q0 = q(1); q1 = q(2); q2 = q(3); q3 = q(4);
    R = [ 1-2*(q2^2+q3^2),   2*(q1*q2-q0*q3),   2*(q1*q3+q0*q2);
          2*(q1*q2+q0*q3),   1-2*(q1^2+q3^2),   2*(q2*q3-q0*q1);
          2*(q1*q3-q0*q2),   2*(q2*q3+q0*q1),   1-2*(q1^2+q2^2) ];
end

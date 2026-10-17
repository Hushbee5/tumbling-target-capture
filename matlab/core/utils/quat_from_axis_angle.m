function q = quat_from_axis_angle(axis, theta)
% QUAT_FROM_AXIS_ANGLE  Scalar-first unit quaternion from an axis and angle.
%   q = quat_from_axis_angle(axis, theta) with theta in radians returns
%       q0 = cos(theta/2),   [q1;q2;q3] = sin(theta/2) * axis/||axis||
%   Hamilton, scalar-first convention (see notes/conventions.md).

    e = axis(:) / norm(axis);
    q = [cos(theta/2); sin(theta/2) * e];
end

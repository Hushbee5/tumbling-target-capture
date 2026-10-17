function v_allow = approach_speed_profile(s, p)
% APPROACH_SPEED_PROFILE  Terminal-approach speed heuristic (spec Sec. 6).
%   v_allow = approach_speed_profile(s, p) returns the closing speed permitted at
%   a remaining distance s to the MOVING capture point:
%
%       v_allow(s) = min( v_cruise, sqrt( 2 * beta * u_max * s ) )
%
%   where s = ||r - p_cp|| is the distance to the capture point - NOT the keep-out
%   clearance d = ||r|| - r_safe used by the HOCBF layer. The two govern different
%   things: this heuristic governs arrival, the barrier governs collision.
%
%   THIS IS A HEURISTIC, NOT A GUARANTEE. Three reasons, all documented in the
%   specification rather than hidden:
%     1. u_max is a per-axis box, so the acceleration available along a direction
%        e is u_max*||e||_1, between u_max and sqrt(3)*u_max. Using u_max is
%        conservative but direction dependent.
%     2. The capture point is accelerating (centripetal ~0.0031-0.0037 m/s^2,
%        i.e. 31-37% of u_max), and braking and tracking draw on the same budget -
%        which is why beta = 0.3 rather than 1.
%     3. It is a one-dimensional energy argument applied to a coupled 3-D problem.

    s = max(s, 0);
    v_allow = min( p.capture.v_cruise, sqrt(2 * p.capture.beta * p.chaser.u_max * s) );
end

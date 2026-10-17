function [h, d_safe, hdot, Lf2h, Lgh] = safety_function(x, p, mode)
% SAFETY_FUNCTION  Keep-out barrier function for the target body.
%   [h, d, hdot, Lf2h, Lgh] = safety_function(x, p, mode) evaluates the safety
%   function of the controlled chaser point at state x = [r; v] (LVLH, metres).
%
%   Forbidden region: sphere of radius r_safe about the target centre of mass,
%   where r_safe = r_target + r_chaser + margin is the Minkowski inflation of
%   the target body by the chaser extent plus a margin (decision S3).
%
%   Outputs
%     h      = ||r||^2 - r_safe^2     [m^2]  barrier function used by the QP
%     d_safe = ||r||   - r_safe       [m]    SAFETY CLEARANCE from the
%              target-centred keep-out sphere, reported and plotted.
%
%   NAMING RULE: d_safe is NOT the distance to the capture point. The capture
%   problem uses s_cp = ||r - p_cp||, which is a different quantity governing
%   arrival rather than collision. The two must never share a symbol.
%     hdot  = 2 r' v                  [m^2/s]
%     Lf2h  = 2 v'v + 2 r' aDrift     [m^2/s^2]  drift part of h_ddot
%     Lgh   = 2 r'                    (1x3)      input part of h_ddot
%
%   with   h_ddot = Lf2h + Lgh * u.
%
%   Sign convention: h >= 0  <=>  d >= 0  <=>  the point is OUTSIDE the
%   forbidden sphere, i.e. safe. This matches the clearance convention of
%   check V9 in validate_h1.m (positive = safe).
%
%   Relative degree: u does not appear in h or hdot but enters h_ddot through
%   Lgh = 2 r' (nonzero whenever r != 0), so the relative degree with respect
%   to u is exactly 2. That is what makes the high-order (HOCBF) construction
%   of dev_plan.md Sec. 3.7 the correct one; the CBF condition and the QP
%   itself belong to Task 2 and are deliberately NOT implemented here.
%
%   mode is passed through to rel_translational_dynamics ('cw' by default).

    if nargin < 3 || isempty(mode)
        mode = 'cw';
    end

    r = x(1:3);
    v = x(4:6);

    rn = norm(r);
    h  = rn^2 - p.geom.r_safe^2;
    d_safe = rn - p.geom.r_safe;

    if nargout > 2
        hdot = 2 * (r.' * v);
    end

    if nargout > 3
        [~, aDrift] = rel_translational_dynamics(x, zeros(3,1), p, mode);
        Lf2h = 2 * (v.' * v) + 2 * (r.' * aDrift);
        Lgh  = 2 * r.';
    end
end

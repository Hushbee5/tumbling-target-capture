function tbl = capture_table_build(p, targetEst, Tspan)
% CAPTURE_TABLE_BUILD  Precompute the capture-point trajectory in LVLH.
%   tbl = capture_table_build(p, targetEst, Tspan) propagates the target attitude
%   from the ESTIMATED state targetEst and maps the body-fixed capture point into
%   the LVLH frame on a uniform grid of step p.ctrl.Ts covering [0, Tspan].
%
%   targetEst fields (all required):
%       q   4x1 scalar-first quaternion estimate at t = 0
%       w   3x1 body angular-velocity estimate at t = 0 [rad/s]
%       I   3x3 inertia estimate [kg m^2]
%   In Task 3 (A-core) the estimate is exact, so this reproduces the truth. The
%   interface takes an ESTIMATE because decision D3 routes target-inertia
%   uncertainty through exactly this path in Task 6 (inertia -> tumbling
%   prediction -> capture-point prediction -> safety margin), so the MPC layer
%   will not need reworking then.
%
%   Returned fields (all on the same grid):
%       t    1xM time [s]
%       pL   3xM capture-point position in LVLH [m]
%       vL   3xM capture-point velocity in LVLH [m/s] (includes transport term)
%       nL   3xM outward capture-axis unit vector in LVLH
%
%   The target tumbles autonomously - its motion does not depend on the chaser's
%   control - so this trajectory is an exogenous signal that may be precomputed.

    pt = p;
    pt.target.q0 = targetEst.q(:);
    pt.target.w0 = targetEst.w(:);
    pt.target.I  = targetEst.I;
    pt.sim.dt      = p.ctrl.Ts;
    pt.sim.T_final = Tspan;

    [t, qH, wH]    = target_tumbling_model(pt);
    [pI, vI, nI]   = capture_point_trajectory(qH, wH, pt);
    [pL, vL, nL]   = capture_point_lvlh(t, pI, vI, nI, pt);

    tbl.t  = t;
    tbl.pL = pL;
    tbl.vL = vL;
    tbl.nL = nL;
    tbl.Ts = p.ctrl.Ts;
end

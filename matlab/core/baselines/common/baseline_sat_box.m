function [u, clipped, per_axis] = baseline_sat_box(u_cmd, u_max)
% BASELINE_SAT_BOX  Per-axis actuator box enforcement for the APF baseline.
%   [u, clipped, per_axis] = baseline_sat_box(u_cmd, u_max) applies the frozen
%   componentwise limit |u_i| <= u_max (protocol Sec. 3.3 and 8).
%
%   u        3x1 applied command
%   clipped  scalar logical, the CLIPPING FLAG of Sec. 10.4:
%                clipped = ( ||u_cmd||_inf > u_max )      STRICT inequality
%            A command sitting exactly ON the bound is NOT clipping. That is the
%            frozen definition, and V4e tests it explicitly.
%   per_axis 3x1 logical, |u_cmd_i| > u_max per axis (STRICT, same rule)
%
%   BITWISE PASS-THROUGH INSIDE THE BOX. When no component exceeds the bound the
%   input is returned by assignment, so isequal(u, u_cmd) holds bitwise (V4a).
%   Only the components that actually exceed the bound are replaced, and they
%   are replaced by the exact signed bound; every other component keeps its
%   input bits unchanged (V4b-V4d).
%
%   FAIRNESS NOTE. The nominal-MPC baseline does NOT pass through this function:
%   its identical box is enforced inside the optimiser by M.lb / M.ub, with no
%   post-command clip (protocol Sec. 8, V10c/V10d). The fairness requirement is
%   the identical actuator CONSTRAINT, not a literally shared clipping operator.

    assert(isnumeric(u_cmd) && numel(u_cmd) == 3, 'baseline_sat_box:u_cmd', ...
        'u_cmd must be a 3-vector; got %d element(s).', numel(u_cmd));
    assert(isscalar(u_max) && isfinite(u_max) && isreal(u_max) && u_max > 0, ...
        'baseline_sat_box:u_max', 'u_max must be a positive finite scalar.');

    u_cmd = u_cmd(:);
    u     = u_cmd;

    per_axis = abs(u_cmd) > u_max;          % STRICT, per Sec. 10.4
    clipped  = any(per_axis);               % == ( ||u_cmd||_inf > u_max )

    if clipped
        idx    = per_axis;
        u(idx) = sign(u_cmd(idx)) * u_max;  % exact signed bound
    end
end

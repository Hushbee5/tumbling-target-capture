function u_nom = nominal_pd(x, r_ref, v_ref, p)
% NOMINAL_PD  Deliberately simple nominal guidance used to isolate the filter.
%   u_nom = nominal_pd(x, r_ref, v_ref, p) returns the saturated PD command
%       u = sat( -Kp*(r - r_ref) - Kd*(v - v_ref), u_max )
%   with the gains of notes/task2_spec_hocbf_qp.md Sec. 6: Kp is sized so that
%   the initial 10 m error does not by itself saturate the actuator, and Kd is
%   the critically damped companion.
%
%   This law exists so that any difference in the results is attributable to the
%   safety filter rather than to an optimizer. Per decision S6 neither these
%   gains nor u_max are ever adjusted to make the nominal controller look worse.
%
%   Saturation is component-wise, matching the actuator box used by the filter.

    r = x(1:3);
    v = x(4:6);

    u = -p.nominal.Kp * (r - r_ref) - p.nominal.Kd * (v - v_ref);

    umax  = p.chaser.u_max;
    u_nom = min(max(u, -umax), umax);
end

function [xdot, aDrift] = rel_translational_dynamics(x, u, p, mode)
% REL_TRANSLATIONAL_DYNAMICS  Relative translational motion in the LVLH frame.
%   [xdot, aDrift] = rel_translational_dynamics(x, u, p, mode) evaluates
%       xdot = [ v ; aDrift(r,v) + u ]
%   for the state x = [r; v] (6x1) of the controlled chaser point relative to
%   the target centre of mass, expressed in LVLH, and the commanded
%   acceleration u (3x1) [m/s^2].
%
%   mode (optional, default 'cw'):
%     'cw'         linearized Clohessy-Wiltshire drift - the controller
%                  prediction model (decision S1):
%                       ax = 3 n^2 rx + 2 n vy
%                       ay =           -2 n vx
%                       az = -n^2 rz
%     'nonlinear'  exact two-body differential gravity in the rotating frame -
%                  the truth model used for validation:
%                       a = -mu (Rt+r)/||Rt+r||^3 + mu Rt/||Rt||^3
%                           - 2 omega x v - omega x (omega x r)
%                  with Rt = [a_m; 0; 0] the target position in LVLH.
%
%   Linearizing 'nonlinear' about r = 0 reproduces 'cw' exactly; at the
%   separations of interest (metres against a 6778 km orbit radius) the two
%   agree to ~1e-7 m over 120 s, which validate_task1.m checks as T7.
%
%   Units: r [m], v [m/s], u [m/s^2], n [rad/s]. No kilometres enter here.

    if nargin < 4 || isempty(mode)
        mode = 'cw';
    end

    r = x(1:3);
    v = x(4:6);
    n = p.orbit.n;

    switch lower(mode)
        case 'cw'
            aDrift = [ 3*n^2*r(1) + 2*n*v(2);
                                   -2*n*v(1);
                       -n^2*r(3)             ];

        case 'nonlinear'
            omega = [0; 0; n];
            Rt    = [p.orbit.a_m; 0; 0];       % target position in LVLH [m]
            rc    = Rt + r;                    % chaser point from Earth centre
            aGrav = -p.orbit.mu_m * rc / norm(rc)^3 ...
                    + p.orbit.mu_m * Rt / norm(Rt)^3;
            aDrift = aGrav - 2*cross(omega, v) - cross(omega, cross(omega, r));

        otherwise
            error('rel_translational_dynamics:mode', ...
                  'unknown mode "%s" (use ''cw'' or ''nonlinear'')', mode);
    end

    xdot = [v; aDrift + u];
end

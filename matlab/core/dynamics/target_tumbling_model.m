function [t, qHist, wHist] = target_tumbling_model(p)
% TARGET_TUMBLING_MODEL  Propagate free tumbling of the non-cooperative target.
%   [t, qHist, wHist] = target_tumbling_model(p) integrates the torque-free
%   rigid-body attitude dynamics of the target from the initial state in p.
%
%   Dynamics (free tumbling, no external torque):
%       I * w_dot = -( w x (I*w) )            (Euler's equation)
%       q_dot     = 0.5 * Omega(w) * q        (quaternion kinematics)
%   with q scalar-first and w in the body frame.
%
%   Outputs:
%       t      : 1xN time vector [s]
%       qHist  : 4xN unit quaternion history (scalar-first)
%       wHist  : 3xN body angular velocity history [rad/s]

    y0    = [p.target.q0(:); p.target.w0(:)];          % 7x1 state [q; w]
    tspan = (0:p.sim.dt:p.sim.T_final)';
    opts  = odeset('RelTol', 1e-9, 'AbsTol', 1e-10);

    [tcol, Y] = ode45(@(tt, y) state_dot(y, p.target.I), tspan, y0, opts);

    qHist = Y(:, 1:4)';                                % 4xN
    wHist = Y(:, 5:7)';                                % 3xN
    qHist = qHist ./ sqrt(sum(qHist.^2, 1));           % renormalize quaternions
    t     = tcol';                                     % 1xN
end

% ----- local functions -----
function dy = state_dot(y, I)
    q = y(1:4);
    w = y(5:7);
    qdot = 0.5 * Omega(w) * q;
    wdot = I \ ( -cross(w, I*w) );
    dy   = [qdot; wdot];
end

function M = Omega(w)
% 4x4 quaternion-rate matrix for scalar-first q with body-frame w.
    wx = w(1); wy = w(2); wz = w(3);
    M = [ 0,  -wx, -wy, -wz;
          wx,  0,   wz, -wy;
          wy, -wz,  0,   wx;
          wz,  wy, -wx,  0 ];
end

function [A, B, Ad, Bd] = cw_matrices(p, dt)
% CW_MATRICES  Continuous and discrete Clohessy-Wiltshire state-space model.
%   [A, B] = cw_matrices(p) returns the continuous-time matrices of
%       xdot = A x + B u,   x = [r; v] (6x1),  u (3x1) [m/s^2]
%   in the LVLH frame with +x radial outward (notes/conventions.md Sec. 4).
%
%   [A, B, Ad, Bd] = cw_matrices(p, dt) additionally returns the exact
%   zero-order-hold discretization over the step dt:
%       x[k+1] = Ad x[k] + Bd u[k]
%   computed from the matrix exponential of the augmented system, so no
%   Control System Toolbox dependency is introduced:
%       expm([A B; 0 0] dt) = [Ad Bd; 0 I]
%
%   The pair (A,B) is the linearization of the 'nonlinear' mode of
%   rel_translational_dynamics about r = 0.

    n = p.orbit.n;

    A = [ 0        0     0      1      0    0;
          0        0     0      0      1    0;
          0        0     0      0      0    1;
          3*n^2    0     0      0    2*n    0;
          0        0     0   -2*n      0    0;
          0        0  -n^2      0      0    0 ];

    B = [zeros(3, 3); eye(3)];

    if nargout > 2
        if nargin < 2 || isempty(dt)
            error('cw_matrices:dt', 'dt is required for the discrete model.');
        end
        nx = size(A, 1);
        nu = size(B, 2);
        M  = expm([A, B; zeros(nu, nx + nu)] * dt);
        Ad = M(1:nx, 1:nx);
        Bd = M(1:nx, nx+1:nx+nu);
    end
end

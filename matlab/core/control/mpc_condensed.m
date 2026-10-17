function M = mpc_condensed(p, N)
% MPC_CONDENSED  Build the constant matrices of the condensed MPC quadratic program.
%   M = mpc_condensed(p, N) assembles everything that does not depend on the
%   current state or reference, so it is computed once per configuration.
%
%   Prediction (exact ZOH of the CW model, decision S1):
%       x[j+1] = Ad x[j] + Bd u[j]
%   Stacking the predicted states X = [x_1; ...; x_N] and inputs
%   U = [u_0; ...; u_{N-1}]:
%       X = Sx * x0 + Su * U
%
%   Cost:
%       J = sum_{j=1}^{N-1} (x_j - xr_j)' Q (x_j - xr_j)
%           + (x_N - xr_N)' P (x_N - xr_N)
%           + sum_{j=0}^{N-1} u_j' R u_j
%     = U' (Su'*Qbar*Su + Rbar) U + 2 (Sx*x0 - Xr)' Qbar Su U + const
%   so in quadprog form (min 0.5 U'H U + f'U):
%       H = 2*(Su'*Qbar*Su + Rbar),   f = 2*Su'*Qbar*(Sx*x0 - Xr)
%
%   Weights are normalised by physical scales (spec Sec. 4), leaving rho as the
%   only free knob:
%       Q = diag([1/sigma_p^2 * ones(1,3), 1/sigma_v^2 * ones(1,3)])
%       R = rho / u_max^2 * I_3
%   The terminal weight P is the discrete LQR cost matrix, which makes the
%   UNCONSTRAINED finite-horizon solution coincide with the infinite-horizon LQR.
%   That is a nominal-stability argument for the unconstrained case only; it is
%   not a constrained-MPC stability proof and must not be presented as one.
%
%   NOTE the cost term u'Ru is CONTROL EFFORT, not fuel (spec Sec. 4.1).

    if nargin < 2 || isempty(N), N = p.mpc.N; end

    [~, ~, Ad, Bd] = cw_matrices(p, p.ctrl.Ts);
    nx = size(Ad, 1);
    nu = size(Bd, 2);

    Q = diag([ (1/p.mpc.sigma_p^2) * ones(1,3), (1/p.mpc.sigma_v^2) * ones(1,3) ]);
    R = (p.mpc.rho / p.chaser.u_max^2) * eye(nu);

    if p.mpc.use_dlqr_terminal
        [K, P] = dlqr(Ad, Bd, Q, R);
    else
        P = Q;  K = [];
    end

    % --- prediction matrices ---
    Sx = zeros(nx*N, nx);
    Su = zeros(nx*N, nu*N);
    Apow = eye(nx);
    for i = 1:N
        Apow = Apow * Ad;                       % Ad^i
        Sx((i-1)*nx+(1:nx), :) = Apow;
        for j = 1:i
            Su((i-1)*nx+(1:nx), (j-1)*nu+(1:nu)) = Ad^(i-j) * Bd;
        end
    end

    Qcell = repmat({Q}, 1, N);
    Qcell{end} = P;
    Qbar = blkdiag(Qcell{:});
    Rbar = kron(eye(N), R);

    H = 2 * (Su.' * Qbar * Su + Rbar);
    H = (H + H.') / 2;                          % symmetrize against round-off

    M.Ad = Ad;  M.Bd = Bd;  M.Q = Q;  M.R = R;  M.P = P;  M.K = K;
    M.Sx = Sx;  M.Su = Su;  M.Qbar = Qbar;  M.Rbar = Rbar;
    M.H  = H;   M.N = N;   M.nx = nx;  M.nu = nu;
    M.lb = -p.chaser.u_max * ones(nu*N, 1);
    M.ub =  p.chaser.u_max * ones(nu*N, 1);
end

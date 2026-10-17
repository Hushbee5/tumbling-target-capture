function [u_mpc, info] = mpc_step(x, Pref, Vref, M, p, U_warm)
% MPC_STEP  Solve one instance of the condensed MPC quadratic program.
%   [u_mpc, info] = mpc_step(x, Pref, Vref, M, p, U_warm) returns the first
%   element of the optimal input sequence, given the current state x and the
%   position/velocity reference over the horizon (3x(N+1), index 1 = now).
%
%   Only the states j = 1..N are penalised, so references at index 2..N+1 are
%   used. The actuator box is the same u_max the HOCBF-QP uses (decision S6): if
%   the two layers disagreed on it, the filter would clip commands the MPC
%   believed feasible.
%
%   info: exitflag, solve time, predicted cost, the full sequence U, and the
%   first-move value before any safety filtering.

    N  = M.N;
    nu = M.nu;

    Xr = reshape([Pref(:, 2:N+1); Vref(:, 2:N+1)], [], 1);   % 6N x 1
    f  = 2 * (M.Su.' * (M.Qbar * (M.Sx * x - Xr)));

    if nargin < 6 || isempty(U_warm)
        U_warm = zeros(nu*N, 1);
    end

    opts = optimoptions('quadprog', 'Display', 'none', ...
        'OptimalityTolerance', 1e-12, 'ConstraintTolerance', 1e-12, ...
        'StepTolerance', 1e-14);

    tS = tic;
    [U, fval, exitflag] = quadprog(M.H, f, [], [], [], [], M.lb, M.ub, U_warm, opts);
    tElapsed = toc(tS);

    if isempty(U) || exitflag <= 0
        u_mpc = zeros(nu, 1);
        info.exitflag = exitflag;
        info.solve_time = tElapsed;
        info.cost = NaN;
        info.U = [];
        return
    end

    u_mpc = U(1:nu);
    info.exitflag   = exitflag;
    info.solve_time = tElapsed;
    info.cost       = fval;
    info.U          = U;
end

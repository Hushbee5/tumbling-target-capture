function Xd = nmpc_f_nl(X, U, NM)
% NMPC_F_NL  V3n: nonlinear relative dynamics (r3 eq. 2), batched over columns; same algebra as
%   REL_TRANSLATIONAL_DYNAMICS 'nonlinear' (test N2).
% nonlinear relative dynamics, batched over columns (identical algebra to REL_TRANSLATIONAL_DYNAMICS 'nonlinear')
    r = X(1:3, :);  v = X(4:6, :);  n = NM.n;
    rc = r;  rc(1, :) = rc(1, :) + NM.a_m;
    nr3 = sum(rc.^2, 1).^1.5;
    aG = -NM.mu_m * rc ./ nr3;  aG(1, :) = aG(1, :) + NM.mu_m / NM.a_m^2;
    cor = [-2*(-n*v(2, :)); -2*(n*v(1, :)); zeros(1, size(v, 2))];      % -2 w x v, w = [0;0;n]
    cen = [n^2 * r(1, :); n^2 * r(2, :); zeros(1, size(r, 2))];           % -w x (w x r)
    Xd = [v; aG + cor + cen + U];
end

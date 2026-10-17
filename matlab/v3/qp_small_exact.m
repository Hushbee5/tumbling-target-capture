function [z, info] = qp_small_exact(H, f, G, h)
% QP_SMALL_EXACT  V3: exact solution of a small strictly convex QP by active-set enumeration.
%   [z, info] = qp_small_exact(H, f, G, h) solves
%
%       min  0.5*z'*H*z + f'*z     s.t.   G*z <= h
%
%   with H symmetric positive definite and n = numel(f) small (here n <= 4, m = size(G,1) <= 9).
%
%   METHOD. The optimum of a strictly convex QP is unique and satisfies the KKT conditions with
%   some set S of active constraints whose normals are linearly independent (|S| <= n). Every
%   such S is enumerated: the equality-constrained problem on S is solved in closed form,
%       [H  G_S'; G_S  0] [z; lam_S] = [-f; h_S],
%   and the candidate is accepted iff it is primal feasible (G z <= h + tol_p) and dual feasible
%   (lam_S >= -tol_d). Among accepted candidates the one with the lowest objective is returned.
%   If no candidate is accepted the problem is declared infeasible (status -1); this verdict is
%   only as reliable as the tolerances and is cross-checked by the caller with an LP margin.
%
%   CERTIFICATE (info.kkt): primal violation max(G z - h, 0), most negative multiplier,
%   stationarity residual ||H z + f + G' lam||_inf and complementarity max |lam_i (G_i z - h_i)|,
%   all recomputed from the returned z and lam, independently of how z was found.
%
%   Rows of G are normalised to unit 2-norm internally (h scaled alike), so the tolerances are in
%   the units of z. No iteration limit exists: the number of candidates is sum_{k<=n} C(m, k).

    n = numel(f);  m = size(G, 1);
    f = f(:);  h = h(:);
    sc = sqrt(sum(G.^2, 2));
    assert(all(sc > 0), 'qp_small_exact:zero_row', 'G has an all-zero row.');
    Gn = G ./ sc;  hn = h ./ sc;
    tol_p = 1e-12 * max(1, max(abs(hn)));
    tol_d = 1e-12;
    best = struct('obj', inf, 'z', [], 'S', [], 'lam', []);
    nCand = 0;  nAcc = 0;
    for k = 0:min(n, m)
        if k == 0
            sets = zeros(1, 0);
        else
            sets = nchoosek(1:m, k);
        end
        for r = 1:size(sets, 1)
            S = sets(r, :);
            GS = Gn(S, :);
            if k > 0 && rank(GS, 1e-10) < k
                continue
            end
            nCand = nCand + 1;
            KKT = [H, GS.'; GS, zeros(k)];
            sol = KKT \ [-f; hn(S)];
            z = sol(1:n);  lamS = sol(n+1:end);
            if any(lamS < -tol_d)
                continue
            end
            if any(Gn*z - hn > tol_p)
                continue
            end
            nAcc = nAcc + 1;
            obj = 0.5*(z.'*H*z) + f.'*z;
            if obj < best.obj - 1e-15*max(1, abs(obj))
                best = struct('obj', obj, 'z', z, 'S', S, 'lam', lamS);
            end
        end
    end
    info.n_candidates = nCand;
    info.n_accepted = nAcc;
    if isempty(best.z)
        z = [];
        info.status = -1;
        info.active = [];
        info.lam = nan(m, 1);
        info.kkt = struct('primal_viol', NaN, 'min_lam', NaN, 'stationarity', NaN, ...
                          'complementarity', NaN);
        return
    end
    z = best.z;
    lam = zeros(m, 1);
    lam(best.S) = best.lam ./ sc(best.S);        % multipliers of the ORIGINAL rows
    info.status = 1;
    info.active = best.S;
    info.lam = lam;
    info.kkt = struct( ...
        'primal_viol',     max([0; G*z - h]), ...
        'min_lam',         min([0; lam]), ...
        'stationarity',    norm(H*z + f + G.'*lam, inf), ...
        'complementarity', max(abs(lam .* (G*z - h))));
end

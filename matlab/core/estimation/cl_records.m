function rec = cl_records(tGrid, wHist, p)
% CL_RECORDS  Build the concurrent-learning regression records for T4-D4.
%   rec = cl_records(tGrid, wHist, p) integrates the exactly theta-affine
%   angular-rate identity over non-overlapping windows of length p.t4.Tw:
%
%       omega_dot = Y_omega(omega) * theta ,   Y_omega = diag(w2 w3, w3 w1, w1 w2)
%
%   so integrating over the window [(j-1) Tw, j Tw] gives the linear regression
%
%       Delta_omega_j = Ybar_j .* theta ,      Ybar_j = integral of Y_omega dt
%
%   with NO approximation beyond the quadrature. The frozen quadrature is
%   SIMPSON on the 0.1 s control grid (freeze record Sec. 1.2).
%
%   CANONICAL CAUSAL TILING (freeze record Sec. 1.1). Record j spans
%   [(j-1) Tw, j Tw] and becomes available only at t = j Tw. The loop bound on
%   the state-sample grid is therefore
%
%       a = 1 : nw : (Nsamp - nw),      nw = Tw / Ts
%
%   where Nsamp = K+1 is the number of STATE samples on [0, T]. Using the number
%   of CONTROL steps K instead drops the final window; that off-by-one is the
%   documented cause of the superseded non-causal headline values, and it is the
%   reason this bound is written out explicitly here.
%
%   Fields:
%     Y   3xJ  Ybar_j, the integrated regressor (diagonal, stored as a column)
%     D   3xJ  Delta_omega_j = omega(j Tw) - omega((j-1) Tw)
%     Te  1xJ  availability time of each record, exactly j * Tw
%     resid    max_j || D_j - Y_j .* theta_true ||, a numerical self-check
%
%   wHist must be the MEASURED target angular-rate history on the control grid
%   (available by assumption A2), sampled at p.ctrl.Ts.

    Ts = p.ctrl.Ts;
    nw = round(p.t4.Tw / Ts);
    assert(mod(nw,2) == 0 && nw >= 2, 'cl_records:simpson', ...
        ['Simpson quadrature needs an even, positive number of subintervals; ' ...
         'Tw/Ts = %g gives nw = %d.'], p.t4.Tw/Ts, nw);
    assert(abs(nw*Ts - p.t4.Tw) < 1e-12, 'cl_records:grid', ...
        'Tw = %g s is not an integer multiple of Ts = %g s.', p.t4.Tw, Ts);

    Nsamp = numel(tGrid);
    assert(size(wHist,2) == Nsamp, 'cl_records:size', ...
        'wHist has %d columns but tGrid has %d samples.', size(wHist,2), Nsamp);

    % composite Simpson weights over one window
    c = ones(1, nw+1);  c(2:2:end) = 4;  c(3:2:end-1) = 2;

    starts = 1 : nw : (Nsamp - nw);          % CANONICAL bound, see header
    J = numel(starts);
    Y  = zeros(3, J);
    D  = zeros(3, J);
    Te = zeros(1, J);

    for j = 1:J
        a   = starts(j);
        idx = a : a+nw;
        wk  = wHist(:, idx);
        Yk  = [ wk(2,:).*wk(3,:);
                wk(3,:).*wk(1,:);
                wk(1,:).*wk(2,:) ];
        Y(:,j)  = (Ts/3) * (Yk * c.');
        D(:,j)  = wHist(:, a+nw) - wHist(:, a);
        Te(j)   = tGrid(a+nw);
    end

    rec.Y  = Y;
    rec.D  = D;
    rec.Te = Te;
    rec.n  = J;
    if isfield(p, 't4') && isfield(p.t4, 'theta_true')
        rec.resid = max(vecnorm(D - Y .* p.t4.theta_true(:)));
    else
        rec.resid = NaN;
    end
end

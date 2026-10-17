function tblL = capture_preview_online_v3(tk, q_k, w_k, theta_hat, p, N, nsub)
% CAPTURE_PREVIEW_ONLINE_V3  V3: CAPTURE_PREVIEW_ONLINE (V2) with the RK4 substep count as an
%   argument (default 10 = V2, bit-identical). V3 uses nsub = 2 (dt = 0.05 s) for speed; the
%   accuracy difference is measured by V3 test T6. Everything else is the V2 text.
%
% CAPTURE_PREVIEW_ONLINE  V2 (EXPLORATORY): receding-horizon capture-point preview.
%   tblL = capture_preview_online(tk, q_k, w_k, theta_hat, p, N) re-anchors the MPC
%   capture-point preview at every control instant on the MEASURED target attitude q_k
%   and body rate w_k (assumption A2, already used by the frozen safety layer) and
%   propagates them over the MPC window [tk, tk + (N+1)*Ts] with the scale-free
%   torque-free model  w_dot = Y_omega(w) .* theta_hat,  Y_omega = [w2 w3; w3 w1; w1 w2],
%   using the ONLINE estimate theta_hat of the concurrent-learning estimator.
%
%   INFORMATION USED: q_k, w_k (measured, A2), theta_hat (online estimate), the known
%   body-fixed capture point p.target.p_cp_body / n_cp_body and the known reference orbit
%   (LVLH frame). NOT USED: p.target.I, p.t4.theta_true, any future truth sample. The
%   V2 test T3 checks that the output is invariant to p.target.I.
%
%   The returned table has the field layout of CAPTURE_TABLE_BUILD on a RELATIVE time
%   grid tblL.t = (0:N+1)*Ts, so the frozen CAPTURE_REFERENCE_PREVIEW can consume it
%   unchanged with tk = 0. Absolute times tk + tblL.t are used for the LVLH mapping.
%
%   Integration: classical RK4 with 10 substeps per Ts (dt = 0.01 s), quaternion
%   renormalised at every control-grid node.

    Ts   = p.ctrl.Ts;
    if nargin < 7 || isempty(nsub), nsub = 10; end
    dt   = Ts / nsub;
    M    = N + 1;
    th   = theta_hat(:);

    Q = zeros(4, M + 1);   W = zeros(3, M + 1);
    q = q_k(:);  w = w_k(:);
    Q(:, 1) = q;  W(:, 1) = w;
    for j = 1:M
        for s = 1:nsub
            [k1q, k1w] = f(q, w, th);
            [k2q, k2w] = f(q + 0.5*dt*k1q, w + 0.5*dt*k1w, th);
            [k3q, k3w] = f(q + 0.5*dt*k2q, w + 0.5*dt*k2w, th);
            [k4q, k4w] = f(q + dt*k3q, w + dt*k3w, th);
            q = q + dt/6 * (k1q + 2*k2q + 2*k3q + k4q);
            w = w + dt/6 * (k1w + 2*k2w + 2*k3w + k4w);
        end
        q = q / norm(q);
        Q(:, j + 1) = q;  W(:, j + 1) = w;
    end

    tRel = (0:M) * Ts;
    tAbs = tk + tRel;
    [pI, vI, nI] = capture_point_trajectory(Q, W, p);
    [pL, vL, nL] = capture_point_lvlh(tAbs, pI, vI, nI, p);
    tblL = struct('t', tRel, 'pL', pL, 'vL', vL, 'nL', nL, 'Ts', Ts, ...
                  't_anchor', tk, 'source', 'V2 online re-anchored preview (measured q,w; theta_hat)');
end

function [qd, wd] = f(q, w, th)
    wx = w(1); wy = w(2); wz = w(3);
    Om = [ 0,  -wx, -wy, -wz;
           wx,  0,   wz, -wy;
           wy, -wz,  0,   wx;
           wz,  wy, -wx,  0 ];
    qd = 0.5 * Om * q;
    wd = [wy*wz; wz*wx; wx*wy] .* th;
end

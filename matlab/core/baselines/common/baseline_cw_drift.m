function a_cw = baseline_cw_drift(x, p)
% BASELINE_CW_DRIFT  The uncontrolled CW translational acceleration a_CW(x).
%   a_cw = baseline_cw_drift(x, p) returns the 3-vector defined by protocol
%   Sec. 3.3 as "the acceleration-drift output of
%   rel_translational_dynamics(x, 0, p, 'cw')", i.e. the SECOND output of the
%   frozen production dynamics with a zero command:
%
%       a_CW = [ 3 n^2 rx + 2 n vy ;  -2 n vx ;  -n^2 rz ]
%
%   It is the term the APF control law cancels:
%       u_cmd = -a_CW(x) + a_cp_ff(t) - grad U(r,t) - k_d*( v - v_cp_preview(t) )
%
%   NOTHING IS RE-DERIVED HERE. The expression above is documentation; the value
%   comes from the frozen production function, so the baseline can never drift
%   away from the model the proposed method used. V3d checks that frozen output
%   against an INDEPENDENT transcription of src/dynamics/cw_matrices.m, which is
%   the only sign test in the verification set - V3c's linearity check is
%   sign-blind by construction.
%
%   a_CW is LINEAR in x, so a_CW(0) is exactly the zero vector (V3b).

    assert(isnumeric(x) && numel(x) == 6, 'baseline_cw_drift:x', ...
        'x must be a 6-vector [r; v]; got %d element(s).', numel(x));

    [~, a_cw] = rel_translational_dynamics(x(:), zeros(3, 1), p, 'cw');
    a_cw = a_cw(:);
end

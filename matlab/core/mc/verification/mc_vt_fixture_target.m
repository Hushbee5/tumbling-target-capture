function fx = mc_vt_fixture_target()
% MC_VT_FIXTURE_TARGET  The ONE non-scientific target / chaser fixture.
%   fx = mc_vt_fixture_target() returns a hand-written, NON-SCIENTIFIC trial
%   row for the short-horizon fixtures of protocol Sec. 10.2. It comes from no
%   random stream, it is not a row of any trial table, and neither x0 nor
%   x0_bad is the evaluation initial condition [0;-10;0;0;0;0].
%
%   fx.row      admissible fixture: trial_id 1, x0, q0, w0, Idiag, I_true
%   fx.row_bad  the same target with a synthetic INADMISSIBLE x0: the chaser
%               starts inside the keep-out sphere (|r| = 0.5 m < r_safe = 0.7 m),
%               so the frozen entry gate refuses the run before any plant step

    c = mc_constants();
    q = [0.9; 0.1; -0.3; 0.2];
    q = q / norm(q);
    w = deg2rad([1.5; -2.5; 3.0]);
    Idiag = [21; 24.5; 31];
    x0 = [0.6; -9.3; 0.4; 0.002; -0.001; 0.0015];
    x0_bad = [0; -0.5; 0; 0; 0; 0];
    assert(~isequal(x0, c.design.eval_x0) && ~isequal(x0_bad, c.design.eval_x0), ...
        'mc:fixture:eval_ic', 'A fixture may never be the evaluation initial condition.');
    fx.row     = struct('trial_id', 1, 'x0', x0, 'q0', q, 'w0', w, 'Idiag', Idiag, ...
                        'I_true', diag(Idiag));
    fx.row_bad = fx.row;
    fx.row_bad.x0 = x0_bad;
end

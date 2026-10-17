function res = v08_ucmd_reconstruction(p, V, run) %#ok<INUSL>
% V08_UCMD_RECONSTRUCTION  V8: the four APF command components sum to u_cmd.
%
%   components  c1 = -a_CW , c2 = +a_cp_ff , c3 = -gradU , c4 = -k_d*edot_ctrl
%   PASS  || (c1+c2+c3+c4) - u_cmd ||_inf <= 1e-14 * max(1, ||u_cmd||_inf)
%         at EVERY control step of the Tsim_V run
%   PASS  all four components are 3xK and finite
%
%   THE TOLERANCE ALLOWS SUMMATION ORDER ONLY. The controller forms u_cmd as
%   c1 + c2 + c3 + c4; this test re-adds the same four stored vectors, so any
%   difference beyond floating-point associativity means a term was dropped,
%   double-counted or built from something other than what was logged.
%
%   c2 IS THE PREVIEW-DERIVED FEEDFORWARD. c4 uses edot_ctrl = v - v_cp_preview,
%   the CONTROL error rate, not the truth error rate. Both are checked here only
%   for consistency with what the controller recorded; the preview/truth
%   separation itself is V2c's subject.

    K      = run.K;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    assert(isfield(run, 'apf'), 'v08:method', ...
        'V8 requires an APF run: the four-component decomposition exists only there.');
    a = run.apf;

    % ---- shapes and finiteness ---------------------------------------------
    comp  = {a.c1, a.c2, a.c3, a.c4};
    names = {'c1 = -a_CW', 'c2 = +a_cp_ff', 'c3 = -gradU', 'c4 = -k_d*edot_ctrl'};
    okShape = true;
    for i = 1:4
        okShape = okShape && isequal(size(comp{i}), [3 K]) && all(isfinite(comp{i}(:)));
    end
    checks(end+1) = baseline_check('V8 all four components are 3xK and finite', ...
        okShape, 'K = %d; sizes %s / %s / %s / %s', K, ...
        mat2str(size(comp{1})), mat2str(size(comp{2})), ...
        mat2str(size(comp{3})), mat2str(size(comp{4})));

    % ---- the reconstruction, at every step ---------------------------------
    S = comp{1} + comp{2} + comp{3} + comp{4};
    D = abs(S - run.u_cmd);
    errPerStep = max(D, [], 1);
    tolPerStep = 1e-14 * max(1, max(abs(run.u_cmd), [], 1));
    okSum = all(errPerStep <= tolPerStep);
    [worst, kw] = max(errPerStep - tolPerStep);
    checks(end+1) = baseline_check('V8 c1+c2+c3+c4 reconstructs u_cmd at every step', ...
        okSum, ['%d control steps; worst (err - tol) = %.3e at k = %d ' ...
        '(err = %.6e, tol = %.6e)'], K, worst, kw-1, ...
        errPerStep(kw), tolPerStep(kw));

    % ---- a per-component sanity read, reported not gated -------------------
    mag = zeros(1, 4);
    for i = 1:4
        mag(i) = max(max(abs(comp{i})));
    end
    checks(end+1) = baseline_check('V8 component magnitudes recorded', true, ...
        'max |.|_inf: %s = %.4e, %s = %.4e, %s = %.4e, %s = %.4e', ...
        names{1}, mag(1), names{2}, mag(2), names{3}, mag(3), names{4}, mag(4));

    res.name   = 'V8 - u_cmd reconstruction from its four components';
    res.checks = checks;
    res.pass   = all([checks.pass]);
    res.component_max = mag;
end

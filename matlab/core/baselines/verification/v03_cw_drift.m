function res = v03_cw_drift(p, V)
% V03_CW_DRIFT  V3: a_CW sign, dimension and linearity.
%
%   V3a  PASS  a_CW(x) is 3x1 double and finite at VP1..VP4
%   V3b  PASS  a_CW(0) == [0;0;0] exactly
%   V3c  LINEARITY (NOT a sign test)
%        PASS  || a_CW(s*x) - s*a_CW(x) ||_inf <= 1e-12*max(1,||a_CW(x)||_inf)
%              for s in {-2, 0.5, 3} at VP1
%        DETECTS      non-linear or state-mixing error, wrong output slot,
%                     unintended input contribution
%        DOES NOT DETECT  a GLOBAL SIGN FLIP: -a_CW(s*x) = s*(-a_CW(x)) also
%                     holds. LINEARITY IS SIGN-BLIND, and saying so is the point
%                     of separating V3c from V3d.
%   V3d  SIGN / CONVENTION - THE ONLY SIGN TEST
%        PASS  compared against the CW expression TRANSCRIBED from
%              src/dynamics/cw_matrices.m at verification-writing time (never
%              from recollection), using the authoritative p.orbit.n:
%              || a_CW(x) - a_CW_transcribed(x) ||_inf <= 1e-12*max(1,||.||_inf)
%
%   THE TRANSCRIPTION, read from src/dynamics/cw_matrices.m rows 4-6 of A while
%   writing this file:
%       A(4,:) = [ 3n^2   0     0     0    2n   0 ]
%       A(5,:) = [ 0      0     0   -2n     0   0 ]
%       A(6,:) = [ 0      0  -n^2     0     0   0 ]
%   so, with x = [r; v],
%       a_CW = [ 3n^2*rx + 2n*vy ;  -2n*vx ;  -n^2*rz ]
%   It is rebuilt below as an explicit 3x6 matrix rather than as three scalar
%   expressions, so a transposition or a misplaced row would show up as a
%   numerical disagreement instead of hiding inside matching prose.
%
%   The protocol writes the V3c scalings as "alpha". They are named `scal` here
%   and stored as v3_scalings, so that no field anywhere in the baseline
%   namespace carries the name or an alias of 'alpha' (Sec. 9, V11e).

    n      = p.orbit.n;
    tol    = V.fd.v3_tol;
    scals  = V.fd.v3_scalings;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    % ---- V3a ----------------------------------------------------------------
    okA = true;
    for i = 1:size(V.VP, 2)
        a = baseline_cw_drift(V.VP(:, i), p);
        okA = okA && isa(a, 'double') && isequal(size(a), [3 1]) && all(isfinite(a));
    end
    checks(end+1) = baseline_check('V3a a_CW is 3x1 double and finite at VP1..VP4', ...
        okA, 'checked at %d verification points', size(V.VP, 2));

    % ---- V3b ----------------------------------------------------------------
    a0 = baseline_cw_drift(zeros(6, 1), p);
    checks(end+1) = baseline_check('V3b a_CW(0) == [0;0;0] exactly', ...
        isequal(a0, [0; 0; 0]), 'a_CW(0) = %s', mat2str(a0.', 17));

    % ---- V3c ----------------------------------------------------------------
    x1  = V.VP(:, 1);
    aX  = baseline_cw_drift(x1, p);
    okC = true;  worstC = 0;
    for i = 1:numel(scals)
        s = scals(i);
        e = norm(baseline_cw_drift(s*x1, p) - s*aX, Inf);
        worstC = max(worstC, e);
        okC = okC && (e <= tol * max(1, norm(aX, Inf)));
    end
    checks(end+1) = baseline_check('V3c a_CW is linear (SIGN-BLIND by construction)', ...
        okC, ['scalings [%s] at VP1; worst |err|_inf = %.6e against tol = %.6e. ' ...
        'This test cannot detect a global sign flip.'], ...
        num2str(scals, '%g '), worstC, tol * max(1, norm(aX, Inf)));

    % ---- V3d : the only sign test ------------------------------------------
    Acw = [ 3*n^2,  0,      0,     0,    2*n,  0 ;
            0,      0,      0,  -2*n,      0,  0 ;
            0,      0,   -n^2,     0,      0,  0 ];
    okD = true;  worstD = 0;  worstTolD = 0;
    for i = 1:size(V.VP, 2)
        x    = V.VP(:, i);
        aImp = baseline_cw_drift(x, p);
        aRef = Acw * x;
        e    = norm(aImp - aRef, Inf);
        tD   = tol * max(1, norm(aRef, Inf));
        worstD = max(worstD, e);  worstTolD = max(worstTolD, tD);
        okD = okD && (e <= tD);
    end
    checks(end+1) = baseline_check('V3d a_CW sign/convention vs transcribed cw_matrices', ...
        okD, ['n = %.15e rad/s; worst |err|_inf = %.6e against tol = %.6e over ' ...
        '%d verification points'], n, worstD, worstTolD, size(V.VP, 2));

    res.name   = 'V3 - a_CW sign, dimension and linearity';
    res.checks = checks;
    res.pass   = all([checks.pass]);
    res.transcription_source = 'src/dynamics/cw_matrices.m rows 4-6 of A';
end

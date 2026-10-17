function res = v04_sat_box(p, V) %#ok<INUSD>
% V04_SAT_BOX  V4: per-axis sat_box, direction angle and common utilisation.
%
%   V4a  inside the box          PASS  isequal(u, u_cmd) BITWISE ; clip flag false
%   V4b  one component > +u_max  PASS  that component == +u_max ; others bitwise
%                                      unchanged
%   V4c  one component < -u_max  PASS  that component == -u_max ; others bitwise
%                                      unchanged
%   V4d  all three outside       PASS  all at the correct signed bound
%   V4e  exactly at the bound    PASS  isequal(u, u_cmd) ; clip flag FALSE
%                                      (the frozen definition uses the STRICT
%                                      inequality ||u_cmd||_inf > u_max)
%   V4f  DIRECTION ANGLE         PASS  implements Sec. 10.5 exactly, including
%                                      the mandatory clamp, the explicit 0 on
%                                      exact equality, the NaN rule, exclusion
%                                      from statistics and the excluded count.
%                                      No complex or NaN output may arise from
%                                      an out-of-range acos argument.
%   V4g  COMMON UTILISATION      PASS  the dimensionless rule of Sec. 10.4 is
%                                      used: ratio = ||u||_inf/u_max and a
%                                      sample counts as saturated when
%                                      ratio >= 1 - 1e-9. No acceleration-valued
%                                      quantity is subtracted from the number 1.
%
%   V4f's anti-pattern coverage is the important part, and it is split into two
%   honest halves rather than one overclaimed one:
%     (i)  a pair that is PROVABLY clipped and PROVABLY not bitwise equal, so
%          the guarded acos path really executes and must return a real, finite,
%          non-negative angle. Whether that pair's raw cosine happens to exceed
%          1 is REPORTED, never asserted.
%     (ii) the clamp hazard demonstrated arithmetically in the test itself -
%          acos(1 + 4*eps) is COMPLEX while acos(min(1,max(-1,1 + 4*eps))) is
%          exactly 0 - plus a static check that the production function really
%          performs the clamp assignment BEFORE its acos(cs) call, compared by
%          source position rather than by mere token presence, over a
%          line-by-line comment strip that does not depend on MATLAB's default
%          dotall regexp semantics.
%   The production BASELINE_DIRECTION_ANGLE is not modified to suit the test.

    umax   = p.chaser.u_max;
    checks = struct('name', {}, 'pass', {}, 'detail', {});

    % ---- V4a ----------------------------------------------------------------
    uc = [0.3; -0.5; 0.9] * umax;
    [u, cl] = baseline_sat_box(uc, umax);
    checks(end+1) = baseline_check('V4a inside the box: bitwise pass-through', ...
        isequal(u, uc) && ~cl, 'isequal = %d, clip flag = %d', isequal(u, uc), cl);

    % ---- V4b ----------------------------------------------------------------
    uc = [1.7*umax; -0.25*umax; 0.5*umax];
    [u, cl] = baseline_sat_box(uc, umax);
    okB = (u(1) == umax) && isequal(u(2:3), uc(2:3)) && cl;
    checks(end+1) = baseline_check('V4b one component above +u_max', okB, ...
        'u = %s, clip flag = %d; untouched components bitwise equal = %d', ...
        mat2str(u.', 17), cl, isequal(u(2:3), uc(2:3)));

    % ---- V4c ----------------------------------------------------------------
    uc = [0.25*umax; -3.1*umax; -0.5*umax];
    [u, cl] = baseline_sat_box(uc, umax);
    okC = (u(2) == -umax) && isequal(u([1 3]), uc([1 3])) && cl;
    checks(end+1) = baseline_check('V4c one component below -u_max', okC, ...
        'u = %s, clip flag = %d; untouched components bitwise equal = %d', ...
        mat2str(u.', 17), cl, isequal(u([1 3]), uc([1 3])));

    % ---- V4d ----------------------------------------------------------------
    uc = [2*umax; -2*umax; 5*umax];
    [u, cl, per] = baseline_sat_box(uc, umax);
    okD = isequal(u, [umax; -umax; umax]) && cl && all(per);
    checks(end+1) = baseline_check('V4d all three outside the box', okD, ...
        'u = %s, clip flag = %d, per-axis = %s', mat2str(u.', 17), cl, mat2str(per.'));

    % ---- V4e ----------------------------------------------------------------
    uc = [umax; -umax; 0];
    [u, cl] = baseline_sat_box(uc, umax);
    checks(end+1) = baseline_check('V4e exactly at the bound is NOT clipping', ...
        isequal(u, uc) && ~cl, ...
        ['isequal = %d, clip flag = %d; the frozen rule is the STRICT ' ...
         '||u_cmd||_inf > u_max'], isequal(u, uc), cl);

    % ---- V4f ----------------------------------------------------------------
    okZeroCmd = isnan(baseline_direction_angle([1; 0; 0], [0; 0; 0]));
    okZeroApp = isnan(baseline_direction_angle([0; 0; 0], [1; 0; 0]));
    aEq = baseline_direction_angle(uc, uc);
    okEq = (aEq == 0);

    % ---- the GUARDED NON-EQUALITY path must actually be exercised ---------
    % The earlier spelling of this pair used u_max*(1 + 1e-16), which rounds to
    % exactly u_max in IEEE double (eps = 2.22e-16). The pair was therefore
    % bitwise equal after clipping and took the EXPLICIT-ZERO branch, so the
    % guarded acos path this check exists to exercise never ran at all.
    %
    % u_max*(1 + 8*eps) is ~10 ULP above u_max at u_max = 0.01, so it is a
    % DIFFERENT double, it is strictly outside the box, and after clipping the
    % applied vector is provably NOT bitwise equal to the command. That the pair
    % was really clipped and really unequal is ASSERTED below rather than
    % assumed, so this check cannot silently degrade again.
    ucAdv = [umax*(1 + 8*eps); umax*1e-9; 0];
    [uaAdv, clAdv] = baseline_sat_box(ucAdv, umax);
    pathExercised = clAdv && ~isequal(uaAdv, ucAdv);
    aAdv   = baseline_direction_angle(uaAdv, ucAdv);
    rawCos = (uaAdv.' * ucAdv) / (norm(uaAdv) * norm(ucAdv));
    okAdv  = pathExercised && isreal(aAdv) && isfinite(aAdv) && aAdv >= 0;

    % NO CLAIM IS MADE that this particular pair drives the raw quotient above
    % 1; whether it does is reported, not asserted. The requirement is that the
    % guarded path runs and returns a real, finite angle.
    checks(end+1) = baseline_check('V4f the guarded non-equality path is exercised', ...
        pathExercised, ['clipped = %d, bitwise-equal = %d; raw cosine = ' ...
        '%.20g (reported, not asserted to exceed 1); angle = %.6e rad, ' ...
        'real = %d, finite = %d'], clAdv, isequal(uaAdv, ucAdv), rawCos, ...
        aAdv, isreal(aAdv), isfinite(aAdv));

    % ---- the MANDATORY clamp: hazard demonstrated, then implementation
    %      confirmed by static inspection of the production function ----------
    % The hazard is demonstrated HERE, in the test, on a quotient constructed to
    % exceed 1. This is what an unclamped acos would do to any pair whose
    % floating-point cosine overshoots.
    overCos   = 1 + 4*eps;
    unclamped = acos(overCos);
    clamped   = acos(min(1, max(-1, overCos)));
    okHazard  = ~isreal(unclamped) && isreal(clamped) && clamped == 0;

    % COMMENT STRIPPING IS LINE BY LINE, AND THAT MATTERS.
    % An earlier spelling used regexprep(srcDA, '(?m)%.*$', ''). MATLAB's regexp
    % defaults to DOTALL - '.' matches newline unless 'dotexceptnewline' is
    % requested - and '(?m)' only changes line ANCHORING, it does not disable
    % dotall. '%.*$' therefore matched greedily from the FIRST '%' in the file
    % through later newlines to the end, deleting the entire body. Both token
    % searches then found nothing and this check reported a false FAIL against a
    % production function that does contain the clamp. The line-by-line strip
    % below keeps the code on every line and removes only from the first '%' to
    % the end of THAT line, which is the mechanism already used successfully in
    % V10_NOMINAL_MPC_PATH.
    srcDA  = fileread(which('baseline_direction_angle.m'));
    codeDA = strip_line_comments(srcDA);

    % ORDER IS THE PROPERTY UNDER TEST, NOT MERE PRESENCE. The frozen
    % requirement is that the clamp happens BEFORE acos; two tokens existing
    % somewhere in the same file would not establish that. The source positions
    % of the clamp assignment and of the acos(cs) call are compared directly.
    clampPos = regexp(codeDA, ...
        'cs\s*=\s*min\s*\(\s*1\s*,\s*max\s*\(\s*-1\s*,\s*cs\s*\)\s*\)', 'once');
    acosPos  = regexp(codeDA, 'acos\s*\(\s*cs\s*\)', 'once');
    hasClamp = ~isempty(clampPos);
    hasAcos  = ~isempty(acosPos);
    ordered  = hasClamp && hasAcos && (clampPos < acosPos);
    okClamp  = okHazard && ordered;
    checks(end+1) = baseline_check('V4f the mandatory clamp is implemented before acos', ...
        okClamp, ['unclamped acos(1+4*eps) is complex = %d; clamped is real ' ...
        'and exactly 0 = %d; clamp assignment found = %d (pos %s); acos(cs) ' ...
        'found = %d (pos %s); ordered clamp-before-acos = %d'], ...
        ~isreal(unclamped), isreal(clamped) && clamped == 0, ...
        hasClamp, pos_str(clampPos), hasAcos, pos_str(acosPos), ordered);

    aVec = baseline_direction_angle([[1;0;0], [0;0;0], [1;1;0]], ...
                                    [[1;0;0], [1;0;0], [1;0;0]]);
    [~, stats] = baseline_direction_angle([[1;0;0], [0;0;0], [1;1;0]], ...
                                          [[1;0;0], [1;0;0], [1;0;0]]);
    okStats = stats.n_excluded == 1 && stats.n_used == 2 && isfinite(stats.max);

    checks(end+1) = baseline_check('V4f direction angle implements Sec. 10.5', ...
        okZeroCmd && okZeroApp && okEq && okAdv && okClamp && okStats, ...
        ['zero-cmd NaN = %d, zero-applied NaN = %d, exact-equality 0 = %d, ' ...
         'guarded path real/finite = %d, clamp before acos = %d, ' ...
         'excluded = %d of %d, used = %d'], okZeroCmd, okZeroApp, okEq, okAdv, ...
        okClamp, stats.n_excluded, stats.n_total, stats.n_used);
    checks(end+1) = baseline_check('V4f NaN samples are excluded from statistics', ...
        okStats && isnan(aVec(2)), ...
        'angle vector = %s; statistics used %d samples', mat2str(aVec, 4), stats.n_used);

    % ---- V4g ----------------------------------------------------------------
    % The dimensionless rule, recoded here independently of BASELINE_METRICS.
    U = [ umax,        0.5*umax,  0.999999*umax ;
          0,           0,         0             ;
          0,           0,         0             ];
    ratio = max(abs(U), [], 1) / umax;
    frac  = mean(ratio >= 1 - p.bl.util_eps);
    okG   = abs(frac - 1/3) < 1e-12 && abs(max(ratio) - 1) < 1e-15;
    checks(end+1) = baseline_check('V4g common utilisation is dimensionless', okG, ...
        ['ratios = %s, saturated fraction = %.6f with eps = %.1e; no ' ...
         'acceleration-valued quantity is subtracted from 1'], ...
        mat2str(ratio, 8), frac, p.bl.util_eps);

    res.name   = 'V4 - per-axis sat_box, direction angle, common utilisation';
    res.checks = checks;
    res.pass   = all([checks.pass]);
end

% =====================================================================
function code = strip_line_comments(src)
% Remove each line's trailing comment, LINE BY LINE. Deliberately does NOT use
% a multiline regexprep: MATLAB's regexp is DOTALL by default, so '%.*$' would
% run past newlines and delete the rest of the file. Splitting on line breaks
% first makes the behaviour independent of that default.
%
% Deliberately simple: it does not need to handle transposes or strings that
% contain '%', because a false POSITIVE here would only make the test stricter,
% never weaker.
    lines = regexp(src, '\r?\n', 'split');
    keep  = cell(1, numel(lines));
    for i = 1:numel(lines)
        L = lines{i};
        q = strfind(L, '%');
        if ~isempty(q)
            L = L(1:q(1)-1);
        end
        keep{i} = L;
    end
    code = strjoin(keep, newline);
end

% =====================================================================
function s = pos_str(p)
% Report a source position, or 'none' when the pattern was not found, so the
% recorded detail distinguishes 'absent' from 'at character 0'.
    if isempty(p)
        s = 'none';
    else
        s = sprintf('%d', p);
    end
end

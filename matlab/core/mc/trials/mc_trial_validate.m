function rep = mc_trial_validate(T)
% MC_TRIAL_VALIDATE  Audit every stored trial row against protocol Sec. 3.4.
%   rep = mc_trial_validate(T) never modifies T. It reports two kinds of check:
%
%   HARD (rep.ok_hard) - must hold for any usable table:
%     every value finite; |norm(q0) - 1| <= 1e-12 (the tolerance
%     baseline_capture_tables.m:138 enforces); canonical sign (q0(1) > 0, or
%     q0(1) == 0 with the first non-zero component positive); positive
%     principal moments with all three strict triangle inequalities; no x0
%     equal to the evaluation initial condition.
%
%   DECLARED OPEN RANGES (rep.ok_open) - the images of the open draw interval:
%     u in (0,1); r0 - [0;-10;0] in (-1,1)^3; v0 in (-0.01,0.01)^3;
%     |w0| in (1,5) deg/s; inertia scale factors in (0.85,1.15)^3.
%   A boundary value can only arise from floating-point rounding of a draw
%   within about 1e-15 of 0 or 1; it is reported, never silently accepted.
%
%   rep.issues lists every failed check with its trial index.

    c = mc_constants();
    n = T.n;
    issues = {};
    okHard = true;
    okOpen = true;

    for i = 1:n
        u  = T.U(:, i);
        r0 = T.r0(:, i);  v0 = T.v0(:, i);  q = T.q0(:, i);
        w  = T.w0(:, i);  Id = T.Idiag(:, i);
        vals = [u; r0; v0; q; w; Id];

        if ~all(isfinite(vals))
            okHard = false;  issues{end+1} = sprintf('trial %d: non-finite value', i); %#ok<AGROW>
            continue
        end
        if abs(norm(q) - 1) > 1e-12
            okHard = false;
            issues{end+1} = sprintf('trial %d: |norm(q0)-1| = %.3g > 1e-12', i, abs(norm(q)-1)); %#ok<AGROW>
        end
        if ~canonical_sign(q)
            okHard = false;  issues{end+1} = sprintf('trial %d: q0 not in canonical sign', i); %#ok<AGROW>
        end
        if ~(all(Id > 0) && Id(1)+Id(2) > Id(3) && Id(2)+Id(3) > Id(1) && Id(1)+Id(3) > Id(2))
            okHard = false;  issues{end+1} = sprintf('trial %d: inertia not physical', i); %#ok<AGROW>
        end
        if isequal([r0; v0], c.design.eval_x0)
            okHard = false;  issues{end+1} = sprintf('trial %d: x0 equals the evaluation IC', i); %#ok<AGROW>
        end

        dr   = r0 - [0; -10; 0];
        wdeg = norm(w) * 180 / pi;
        s    = Id ./ [20; 25; 30];
        open = all(u > 0 & u < 1) && all(abs(dr) < 1) && all(abs(v0) < 0.01) ...
               && wdeg > 1 && wdeg < 5 && all(s > 0.85 & s < 1.15);
        if ~open
            okOpen = false;  issues{end+1} = sprintf('trial %d: a declared open range is not strict', i); %#ok<AGROW>
        end
    end

    rep = struct('ok_hard', okHard, 'ok_open', okOpen, 'n', n, 'issues', {issues});
end

% =====================================================================
function ok = canonical_sign(q)
    if q(1) > 0
        ok = true;
    elseif q(1) == 0
        k = find(q(2:4) ~= 0, 1);
        ok = ~isempty(k) && q(1 + k) > 0;
    else
        ok = false;
    end
end

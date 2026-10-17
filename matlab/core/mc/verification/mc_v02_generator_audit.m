function R = mc_v02_generator_audit(~)
% MC_V02_GENERATOR_AUDIT  Generator audit with a FIXTURE seed (Sec. 10.2). NON-SCIENTIFIC.
%   On the generating platform and MATLAB version, with fixture seed 20260911
%   (NOT the scientific seed): the scientific seed is refused before any
%   stream exists; a per-trial loop reproduces the one-call draw matrix
%   bitwise; the table stores exactly those draws; recomputing the frozen
%   mapping reproduces every derived field bitwise; every derived field lies in
%   its declared open range; |norm(q0) - 1| <= 1e-12; canonical sign; the sign
%   canonicalisation leaves the rotation matrix bitwise unchanged; the
%   collision rule stops generation on a synthetic evaluation-IC column.

    R.name = 'V02 generator audit (fixture seed)';
    ch = {};
    c = mc_constants();
    fs = 20260911;
    n  = c.design.N_PHYSICAL;
    assert(fs ~= c.rng.seed, 'mc:verify:seed', 'The fixture seed must differ from the scientific seed.');

    [ok, got] = mc_vt_throws(@() mc_fixture_trial_table(c.rng.seed, 1), 'mc:rng:scientific_seed_forbidden');
    ch{end+1} = mc_vt_check('the scientific seed is refused by the fixture generator', ok, got);
    ch{end+1} = mc_vt_check('the refusal happened before any scientific stream (sentinel unset)', ...
        ~mc_rng_sentinel('query'));

    s1 = RandStream(c.rng.generator, 'Seed', fs);
    U1 = rand(s1, c.design.n_draws, n);
    s2 = RandStream(c.rng.generator, 'Seed', fs);
    U2 = zeros(c.design.n_draws, n);
    for i = 1:n
        U2(:, i) = rand(s2, c.design.n_draws, 1);
    end
    ch{end+1} = mc_vt_check('per-trial loop reproduces the one-call draw matrix bitwise', ...
        isequal(typecast(U1(:), 'uint64'), typecast(U2(:), 'uint64')));

    T = mc_fixture_trial_table(fs, n);
    ch{end+1} = mc_vt_check('the fixture table stores exactly the one-call draws (15 x 100)', ...
        isequal(size(T.U), [15 n]) && isequal(typecast(T.U(:), 'uint64'), typecast(U1(:), 'uint64')) ...
        && strcmp(T.kind, 'FIXTURE') && T.seed == fs);

    same = true;
    for i = 1:n
        row = mc_trial_mapping(T.U(:, i));
        same = same && isequal(typecast(row.r0, 'uint64'), typecast(T.r0(:, i), 'uint64')) ...
            && isequal(typecast(row.v0, 'uint64'), typecast(T.v0(:, i), 'uint64')) ...
            && isequal(typecast(row.q0, 'uint64'), typecast(T.q0(:, i), 'uint64')) ...
            && isequal(typecast(row.w0, 'uint64'), typecast(T.w0(:, i), 'uint64')) ...
            && isequal(typecast(row.Idiag, 'uint64'), typecast(T.Idiag(:, i), 'uint64'));
    end
    ch{end+1} = mc_vt_check('recomputing the frozen mapping reproduces every derived field bitwise', same);

    % ---- INDEPENDENT oracle (F12-A): a different implementation, a few ulp ----
    worst = 0;
    for i = 1:n
        o = mc_vt_mapping_oracle(T.U(:, i));
        f = {'r0', 'v0', 'q0', 'w0', 'Idiag'};
        for k = 1:numel(f)
            a = T.(f{k})(:, i);  b = o.(f{k});
            worst = max(worst, max(abs(a - b) ./ max(1, abs(b))));
        end
    end
    ch{end+1} = mc_vt_check('an INDEPENDENT implementation of Sec. 3.4 agrees on all 100 rows (<= 1e-14 rel.)', ...
        worst <= 1e-14, sprintf('worst relative difference %.3g', worst));

    % ---- hand-derived rows, exact analytic expectations (F12-A) ---------------
    uh = [0.25; 0.5; 0.75; 0.5; 0.75; 0.25; 0.5; 0.125; 0.125; 0.5; 0.25; 0.5; 0.5; 0.5; 0.5];
    h = mc_trial_mapping(uh);
    % r0 = [0;-10;0] + (2u-1) = [-0.5; -10; 0.5]   v0 = 0.01(2u-1) = [0; 0.005; -0.005]
    % a = b = sqrt(1/2); 2 pi u8 = 2 pi u9 = pi/4 -> q = [1/2; 1/2; 1/2; 1/2]
    % z = 0, phi = pi/2 -> d = [cos(pi/2); 1; 0];  |w| = 3 deg/s;  I = [20; 25; 30]
    okH = isequal(h.r0, [-0.5; -10; 0.5]) && isequal(h.v0, [0; 0.005; -0.005]) ...
        && max(abs(h.q0 - [0.5; 0.5; 0.5; 0.5])) <= 4*eps ...
        && max(abs(h.w0 - (3*pi/180) * [0; 1; 0])) <= 4*eps ...
        && isequal(h.Idiag, [20; 25; 30]);
    ch{end+1} = mc_vt_check('a hand-derived row matches its analytic expectation', okH, ...
        sprintf('q0 %s, w0 %s', mat2str(h.q0', 17), mat2str(h.w0', 17)));
    uh2 = uh;  uh2(7) = 0.75;  uh2(9) = 0.625;          % b cos(2 pi u9) < 0 -> sign flip
    h2 = mc_trial_mapping(uh2);
    raw = [sqrt(0.75)*cos(2*pi*0.625); sqrt(0.25)*sin(2*pi*0.125); sqrt(0.25)*cos(2*pi*0.125); ...
           sqrt(0.75)*sin(2*pi*0.625)];
    ch{end+1} = mc_vt_check('a hand-derived row with a negative scalar part is sign-canonicalised', ...
        raw(1) < 0 && h2.q0(1) > 0 && max(abs(h2.q0 + raw / norm(raw))) <= 4*eps);

    rep = mc_trial_validate(T);
    ch{end+1} = mc_vt_check('hard checks: finite, unit norm (<= 1e-12), canonical sign, physical inertia, no eval IC', ...
        rep.ok_hard, strjoin(rep.issues, '; '));
    ch{end+1} = mc_vt_check('every derived field lies in its declared OPEN range', rep.ok_open, ...
        strjoin(rep.issues, '; '));
    qn = max(abs(sqrt(sum(T.q0.^2, 1)) - 1));
    ch{end+1} = mc_vt_check('max |norm(q0) - 1| over the table', qn <= 1e-12, sprintf('%.3g', qn));

    rotOk = true;
    for i = 1:n
        rotOk = rotOk && isequal(quat_to_rotm(T.q0(:, i)), quat_to_rotm(-T.q0(:, i)));
    end
    ch{end+1} = mc_vt_check('sign canonicalisation does not alter the rotation: R(q) == R(-q) bitwise', rotOk);

    Uc = 0.5 * ones(c.design.n_draws, 1);        % r0 = [0;-10;0], v0 = 0 exactly
    [ok, got] = mc_vt_throws(@() mc_trial_table_from_U(Uc, 'SYNTHETIC'), 'mc:trials:eval_ic_collision');
    ch{end+1} = mc_vt_check('collision rule: an x0 equal to the evaluation IC STOPS generation', ok, got);

    s = T.Idiag ./ [20; 25; 30];
    nOrd = sum(~(T.Idiag(1, :) < T.Idiag(2, :) & T.Idiag(2, :) < T.Idiag(3, :)));
    ch{end+1} = mc_vt_check('descriptive: fixture envelope summary (informational)', true, ...
        sprintf('|w0| in [%.4f, %.4f] deg/s; scales in [%.4f, %.4f]; changed ordering %d/%d', ...
        min(sqrt(sum(T.w0.^2, 1))) * 180/pi, max(sqrt(sum(T.w0.^2, 1))) * 180/pi, ...
        min(s(:)), max(s(:)), nOrd, n));

    R.checks = [ch{:}];
end

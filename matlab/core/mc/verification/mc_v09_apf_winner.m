function R = mc_v09_apf_winner(tmpRoot)
% MC_V09_APF_WINNER  The frozen APF winner loader (R10). NON-SCIENTIFIC.
%   The winner is READ from the hash-frozen tuning record and equals the
%   approved candidate-95 values exactly; a file with any other bytes is a
%   hard stop at the hash gate; the exact-value gate independently hard-stops
%   on a one-ulp perturbation of any theta or derived gain, a wrong id or
%   wrong levels; and the gains the APF invocation builds are those values.

    R.name = 'V09 APF winner loader';
    ch = {};
    c = mc_constants();
    pBL = baseline_config();

    W = mc_load_apf_winner(pBL);
    ch{end+1} = mc_vt_check('winner read from the frozen record: id 95, levels [24 8 8 8]', ...
        W.provenance.winner_id == 95 && isequal(W.provenance.winner_levels(:).', [24 8 8 8]) ...
        && strcmp(W.provenance.record_sha256, c.files{strcmp(c.files(:, 1), 'tuning_record'), 3}));
    tf = fieldnames(c.apf.theta);
    okT = true;
    for k = 1:numel(tf)
        okT = okT && isequal(W.theta.(tf{k}), c.apf.theta.(tf{k}));
    end
    gf = fieldnames(c.apf.derived);
    okG = true;
    for k = 1:numel(gf)
        okG = okG && isequal(W.gains.(gf{k}), c.apf.derived.(gf{k}));
    end
    ch{end+1} = mc_vt_check('theta equals the approved values exactly', okT, ...
        sprintf('omega_n %.17g', W.theta.omega_n));
    ch{end+1} = mc_vt_check('derived k_a, k_d, k_r equal the approved values exactly', okG, ...
        sprintf('k_a %.17g, k_d %.17g, k_r %.17g', W.gains.k_a, W.gains.k_d, W.gains.k_r));
    ch{end+1} = mc_vt_check('the APF invocation gains apf_gains(theta_95, pBL) equal the loaded gains', ...
        isequal(apf_gains(W.theta, pBL), W.gains));

    fake = fullfile(tmpRoot, 'not_the_tuning_record.mat');
    res = struct('outcome', 'SEARCH_COMPLETE'); %#ok<NASGU>
    save(fake, 'res');
    [ok, got] = mc_vt_throws(@() mc_load_apf_winner(pBL, fake), 'mc:apf:record_sha');
    ch{end+1} = mc_vt_check('a record with other bytes is a hard stop at the hash gate', ok, got);

    th = W.theta;  th.omega_n = th.omega_n + eps(th.omega_n);
    [ok, got] = mc_vt_throws(@() mc_apf_winner_check(95, [24 8 8 8], th, W.gains), 'mc:apf:theta');
    ch{end+1} = mc_vt_check('one-ulp omega_n perturbation: hard stop', ok, got);
    g = W.gains;  g.k_r = g.k_r + eps(g.k_r);
    [ok, got] = mc_vt_throws(@() mc_apf_winner_check(95, [24 8 8 8], W.theta, g), 'mc:apf:derived');
    ch{end+1} = mc_vt_check('one-ulp k_r perturbation: hard stop', ok, got);
    [ok, got] = mc_vt_throws(@() mc_apf_winner_check(94, [24 8 8 8], W.theta, W.gains), 'mc:apf:winner_id');
    ch{end+1} = mc_vt_check('wrong winner id: hard stop', ok, got);
    [ok, got] = mc_vt_throws(@() mc_apf_winner_check(95, [24 8 8 7], W.theta, W.gains), 'mc:apf:levels');
    ch{end+1} = mc_vt_check('wrong levels: hard stop', ok, got);
    R.checks = [ch{:}];
end

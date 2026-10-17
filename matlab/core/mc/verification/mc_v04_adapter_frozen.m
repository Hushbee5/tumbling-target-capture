function R = mc_v04_adapter_frozen(~)
% MC_V04_ADAPTER_FROZEN  The Sec. 6.1 adapter on the FROZEN proposed artifact, READ-ONLY.
%   Loads results/task4/final800/task4_final_800s_alpha1em3.mat (hash-checked
%   before and after), builds the deterministic target's truth tables with the
%   frozen baseline_capture_tables (a TARGET-ONLY propagation - no chaser
%   state, no evaluation IC, no method run), applies MC_PROPOSED_ADAPTER and
%   requires the independently audited values of protocol Sec. 10.2:
%       proximity time 626.3 s, DeltaV-to-proximity 1.723583838685 m/s,
%       DeltaV-full 2.347033143010 m/s, terminal rho 0.0193085971351 m,
%       min h_body 0.0926471152914 m^2
%   each to half a unit in its last printed digit. The proposed method is NOT
%   rerun. The same artifact also exercises the B4 contract and the
%   classifier on real frozen output.

    R.name = 'V04 adapter on the frozen alpha=1e-3 artifact (read-only)';
    ch = {};
    c = mc_constants();
    root = mc_repo_root();
    k = find(strcmp(c.files(:, 1), 'proposed_ref'), 1);
    f = fullfile(root, strrep(c.files{k, 2}, '/', filesep));
    sha0 = baseline_sha256(f);
    ch{end+1} = mc_vt_check('artifact hashes to its frozen SHA-256 (before)', strcmp(sha0, c.files{k, 3}), sha0);

    S = load(f, 'out');
    out = S.out;
    pBL = baseline_config();
    tg = out.config.p.target;
    p0 = params();
    truthIC = struct('q', tg.q0, 'w', tg.w0, 'I', tg.I);
    ch{end+1} = mc_vt_check('artifact target is the deterministic params() target', ...
        isequal(tg.q0, p0.target.q0) && isequal(tg.w0, p0.target.w0) && isequal(tg.I, p0.target.I));
    ch{end+1} = mc_vt_check('artifact built its own preview from the truth (no supplied table)', ...
        isequal(out.config.custom_tbl, false) && isequal(out.config.opt.targetEst, truthIC));

    tabs = baseline_capture_tables(pBL, truthIC, truthIC, c.design.Tsim);
    [m, ~] = mc_proposed_adapter(out, tabs, pBL);

    want = {
        'proximity time [s]',           m.t_kstar,             626.3,           1e-9
        'DeltaV to proximity [m/s]',    m.DeltaV_to_proximity, 1.723583838685,  5e-13
        'DeltaV full [m/s]',            m.DeltaV_full,         2.347033143010,  5e-13
        'terminal rho [m]',             m.rho_truth_final,     0.0193085971351, 5e-14
        'min h_body [m^2]',             m.min_h_body,          0.0926471152914, 5e-14
        };
    for i = 1:size(want, 1)
        d = abs(want{i, 2} - want{i, 3});
        ch{end+1} = mc_vt_check(['adapter reproduces ' want{i, 1}], d <= want{i, 4}, ...
            sprintf('%.15g (audited %.15g, |d| = %.3g)', want{i, 2}, want{i, 3}, d)); %#ok<AGROW>
    end
    ch{end+1} = mc_vt_check('proximity achieved, no observed body violation over the union', ...
        m.proximity_achieved && m.no_observed_body_violation && m.n_inspected == 80001, ...
        sprintf('n_inspected %d', m.n_inspected));
    rs = pBL.geom.r_safe;
    mcl = sqrt(m.min_h_body + rs^2) - rs;
    ch{end+1} = mc_vt_check('union-consistent min clearance (R13) ~ 0.06331325 m', ...
        abs(mcl - 0.06331325) <= 5e-9, sprintf('%.12g', mcl));

    mask = mc_mask_check(out);
    ch{end+1} = mc_vt_check('B4 contract: the frozen COMPLETE output has no violation', ...
        isempty(mask.nonfinite) && isempty(mask.structure), ...
        strjoin([mask.nonfinite, mask.structure], '; '));
    st = mc_classify_proposed('RETURNED', out, c.design.K);
    ch{end+1} = mc_vt_check('classifier: frozen 800 s output is COMPLETE (B7)', strcmp(st, 'COMPLETE'), st);

    bitQ = isequal(out.qT, tabs.qT) && isequal(out.wT, tabs.wT);
    ch{end+1} = mc_vt_check('informational: truth qT/wT of the artifact equal a fresh table build', ...
        true, sprintf('bitwise equal = %d (not required: the artifact ran under default threading, R11)', bitQ));

    sha1 = baseline_sha256(f);
    ch{end+1} = mc_vt_check('artifact unchanged (after)', strcmp(sha1, sha0), sha1);
    R.checks = [ch{:}];
end

function [m, run_pm] = mc_proposed_adapter(out, tabs, pBL)
% MC_PROPOSED_ADAPTER  Method-neutral metrics for the proposed method (Sec. 6.1).
%   [m, run_pm] = mc_proposed_adapter(out, tabs, pBL) builds exactly
%
%       run_pm.t            = out.t
%       run_pm.X            = out.X
%       run_pm.u_applied    = out.Usafe
%       run_pm.u_cmd        = out.Usafe        (no post-command clip)
%       run_pm.clip_flags   = []
%       run_pm.p_cp_truth   = tabs.p_cp_truth(:, 1:numel(out.t))
%       run_pm.v_cp_truth   = tabs.v_cp_truth(:, 1:numel(out.t))
%       run_pm.inter_t      = out.inter.t
%       run_pm.inter_r      = out.inter.r
%       run_pm.inter_h_body = h_body recomputed from out.inter.r with pBL's
%                             safety_function
%       m = baseline_metrics(run_pm, pBL)
%
%   and calls the FROZEN baseline_metrics UNMODIFIED; no metric is
%   reimplemented. Adapter-intrinsic integrity assertions (Sec. 6.1), each an
%   'mc:integrity:*' error:
%       numel(out.inter.t) == (n_sub - 1) * (numel(out.t) - 1)
%       the recomputed intersample h_body equals out.inter.h_body exactly
%   The MC-specific per-run assertions (shared-table consumption and truth
%   identity) are MC_PROPOSED_INTEGRITY; they are not applicable to the
%   frozen deterministic artifact, which built its own preview.
%
%   For an aborted run numel(out.t) = K_applied + 1 and size(out.Usafe, 2) =
%   K_applied, so baseline_metrics evaluates the executed PREFIX (Sec. 7.5).

    ns = numel(out.t);
    nInt = out.config.opt.n_sub - 1;
    assert(numel(out.inter.t) == nInt * (ns - 1) && size(out.inter.r, 2) == numel(out.inter.t), ...
        'mc:integrity:inter_count', ...
        'numel(out.inter.t) = %d, expected %d x (numel(out.t) - 1) = %d.', ...
        numel(out.inter.t), nInt, nInt * (ns - 1));
    assert(size(tabs.p_cp_truth, 2) >= ns && size(tabs.v_cp_truth, 2) >= ns, ...
        'mc:integrity:truth_span', 'The truth tables are shorter than the trajectory.');

    nI = numel(out.inter.t);
    h  = zeros(1, nI);
    for j = 1:nI
        h(j) = safety_function([out.inter.r(:, j); 0; 0; 0], pBL, pBL.bl.drift_mode);
    end
    assert(numel(out.inter.h_body) == nI && isequal(h(:), out.inter.h_body(:)), ...
        'mc:integrity:inter_h_body', ...
        'The recomputed intersample h_body does not equal out.inter.h_body.');

    run_pm.t            = out.t;
    run_pm.X            = out.X;
    run_pm.u_applied    = out.Usafe;
    run_pm.u_cmd        = out.Usafe;
    run_pm.clip_flags   = [];
    run_pm.p_cp_truth   = tabs.p_cp_truth(:, 1:ns);
    run_pm.v_cp_truth   = tabs.v_cp_truth(:, 1:ns);
    run_pm.inter_t      = out.inter.t;
    run_pm.inter_r      = out.inter.r;
    run_pm.inter_h_body = h;

    m = baseline_metrics(run_pm, pBL);
end

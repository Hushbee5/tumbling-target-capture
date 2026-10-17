function v2c = baseline_preview_truth_audit(tabs, tol_p, tol_v)
% BASELINE_PREVIEW_TRUTH_AUDIT  The V2c preview/truth consistency audit.
%   v2c = baseline_preview_truth_audit(tabs, tol_p, tol_v) measures, over the
%   FULL DETERMINISTIC TARGET HORIZON on the grid t = 0 : Ts : 800 s,
%
%       Ep = max || p_cp_preview - p_cp_truth ||_inf   [m]
%       Ev = max || v_cp_preview - v_cp_truth ||_inf   [m/s]
%
%   PASS   Ep <= tol_p AND Ev <= tol_v      (frozen at 1e-6 m and 1e-6 m/s)
%   REPORT Ep, Ev and their argmax indices AND times, ALWAYS, regardless of
%          PASS/FAIL.
%
%   SCOPE IS TARGET-ONLY. tabs comes from BASELINE_CAPTURE_TABLES, which
%   propagates the target alone: no chaser state, no evaluation IC and no
%   scientific baseline run is involved in producing these numbers.
%
%   ONE IMPLEMENTATION, TWO CONSUMERS. V02_ACP_FF_AND_PREVIEW_TRUTH calls this
%   for the V1-V11 gate, and BASELINE_EVALUATE calls it so that every saved
%   deterministic artifact carries the same audit under meta.v2c (V11b). A
%   second copy could report a different number for the same tables.
%
%   TOLERANCE STATUS, stated rather than implied. 1e-6 is an A-PRIORI
%   ENGINEERING numerical-consistency tolerance. ODE RelTol/AbsTol are LOCAL
%   error controls and do NOT mathematically guarantee any global error bound;
%   no such guarantee is asserted. The value is an engineering judgement: five
%   decades below s_cap, hence far too tight to mask any physically meaningful
%   discrepancy, while loose enough to tolerate output-grid and step-partition
%   effects of the kind already measured in the frozen Channel-A/Channel-B audits.
%
%   v2c fields (all required by BASELINE_SCHEMA's V11b check):
%       Ep, Ev, argmax_index_p, argmax_t_p, argmax_index_v, argmax_t_v,
%       n_samples, tol_p, tol_v, pass_p, pass_v, pass,
%       tolerance_status, scope

    if nargin < 2 || isempty(tol_p), tol_p = 1e-6; end
    if nargin < 3 || isempty(tol_v), tol_v = 1e-6; end

    assert(isstruct(tabs) && all(isfield(tabs, ...
        {'t', 'p_cp_preview', 'v_cp_preview', 'p_cp_truth', 'v_cp_truth'})), ...
        'baseline_preview_truth_audit:tabs', ...
        'tabs must be a BASELINE_CAPTURE_TABLES result.');

    dP = abs(tabs.p_cp_preview - tabs.p_cp_truth);
    dV = abs(tabs.v_cp_preview - tabs.v_cp_truth);
    [Ep, ip] = max(max(dP, [], 1));
    [Ev, iv] = max(max(dV, [], 1));

    v2c.Ep             = Ep;
    v2c.Ev             = Ev;
    v2c.argmax_index_p = ip - 1;              % zero-based physical sample index
    v2c.argmax_t_p     = tabs.t(ip);
    v2c.argmax_index_v = iv - 1;
    v2c.argmax_t_v     = tabs.t(iv);
    v2c.n_samples      = numel(tabs.t);
    v2c.tol_p          = tol_p;
    v2c.tol_v          = tol_v;
    v2c.pass_p         = Ep <= tol_p;
    v2c.pass_v         = Ev <= tol_v;
    v2c.pass           = v2c.pass_p && v2c.pass_v;
    v2c.tolerance_status = ['A-PRIORI ENGINEERING numerical-consistency ' ...
        'tolerance. ODE RelTol/AbsTol are LOCAL error controls and do not ' ...
        'mathematically guarantee any global error bound; no such guarantee ' ...
        'is asserted.'];
    v2c.scope = 'TARGET-ONLY propagation; no chaser state and no evaluation IC';
end

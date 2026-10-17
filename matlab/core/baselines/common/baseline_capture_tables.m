function tabs = baseline_capture_tables(p, truthIC, previewIC, Tsim)
% BASELINE_CAPTURE_TABLES  Independent PREVIEW and TRUTH capture-point histories.
%   tabs = baseline_capture_tables(p, truthIC)                     Tsim = p.bl.T_eval
%   tabs = baseline_capture_tables(p, truthIC, previewIC, Tsim)
%
%   Implements the preview/truth separation frozen in protocol Sec. 7:
%
%       p_cp_preview , v_cp_preview     CONTROLLER / reference information
%       p_cp_truth   , v_cp_truth       METHOD-NEUTRAL evaluation geometry
%
%   The APF control error and a_cp_ff use PREVIEW only; every shared proximity
%   metric uses TRUTH only. Both identities are stored in every artifact and are
%   audited by V2c.
%
%   truthIC / previewIC fields: q (4x1 scalar-first), w (3x1 body rad/s),
%   I (3x3 kg m^2). previewIC defaults to truthIC, which is the DETERMINISTIC
%   case: same target initial conditions, same intended target model. The two
%   are kept as SEPARATE arguments because the later Monte Carlo protocol must
%   be able to set I_truth ~= I_preview_nom without changing any metric
%   semantics, and a random truth inertia must never be silently handed to the
%   preview model.
%
%   THE TWO TABLES ARE GENERATED INDEPENDENTLY, ON PURPOSE.
%     preview  capture_table_build(p, previewIC, Tsim + (N+2)*Ts) - the same
%              construction and the same span the frozen MPC path uses, so the
%              fairness contract "identical capture_table_build span" holds for
%              both compared methods. It integrates the attitude on the CONTROL
%              grid over the extended span.
%     truth    the target is propagated on the FINE grid dt = Ts/n_sub over
%              [0, Tsim] - the same fine propagation SIMULATE_TASK4 uses - and
%              then subsampled to the control grid before the body-fixed capture
%              point is mapped through capture_point_trajectory and
%              capture_point_lvlh.
%   Because the two integrations use different tspans and different step
%   partitions, they are NOT bitwise identical, and protocol Sec. 7 does not
%   require them to be. What is required is the same deterministic target
%   initial conditions and the same intended target model. V2c measures the
%   residual difference and gates it at 1e-6 m / 1e-6 m/s.
%
%   V2c PRECONDITION, CONFIRMED BY SOURCE INSPECTION BEFORE ANY EXECUTION.
%   Both p_cp_preview and p_cp_truth are LVLH-frame capture-point quantities in
%   metres and metres per second, produced through the SAME capture_point_lvlh
%   transport formula, sampled on the SAME grid t = 0 : Ts : Tsim (the preview
%   table is simply longer and is truncated to that grid here). They are
%   therefore dimensionally and semantically comparable.
%
%   Returned fields:
%       t                  1x(K+1) control-grid time [s]
%       p_cp_preview       3x(K+1) [m]     v_cp_preview 3x(K+1) [m/s]
%       p_cp_truth         3x(K+1) [m]     v_cp_truth   3x(K+1) [m/s]
%       n_cp_preview / n_cp_truth  3x(K+1) capture-axis unit vectors
%       qT 4x(K+1), wT 3x(K+1)     TRUTH target attitude / body rate
%       tbl_preview        the full-span table object the MPC path consumes
%       identity           preview and truth target identities, both stored

    if nargin < 3 || isempty(previewIC), previewIC = truthIC; end
    if nargin < 4 || isempty(Tsim),      Tsim      = p.bl.T_eval; end

    Ts    = p.ctrl.Ts;
    n_sub = p.bl.n_sub;
    N     = p.bl.N;

    check_target_ic(truthIC,   'truthIC');
    check_target_ic(previewIC, 'previewIC');

    nStepsExact = Tsim / Ts;
    assert(abs(nStepsExact - round(nStepsExact)) <= 1e-9 * max(1, abs(nStepsExact)), ...
        'baseline_capture_tables:grid', ...
        'Tsim = %.12g s is not an integer multiple of Ts = %g s.', Tsim, Ts);
    K = round(nStepsExact);

    % ---- PREVIEW: the frozen Task 3 construction, extended span -------------
    tbl = capture_table_build(p, previewIC, Tsim + (N+2)*Ts);
    assert(numel(tbl.t) >= K+1, 'baseline_capture_tables:preview_short', ...
        'Preview table has %d samples, fewer than the K+1 = %d required.', ...
        numel(tbl.t), K+1);
    idx = 1:(K+1);
    assert(abs(tbl.t(K+1) - Tsim) <= 1e-9, 'baseline_capture_tables:preview_align', ...
        ['Preview sample %d sits at t = %.12g s, not at Tsim = %.12g s; the ' ...
         'preview and truth grids are not aligned.'], K+1, tbl.t(K+1), Tsim);

    % ---- TRUTH: fine-grid propagation, then subsample to the control grid ---
    pt = p;
    pt.target.q0   = truthIC.q(:);
    pt.target.w0   = truthIC.w(:);
    pt.target.I    = truthIC.I;
    pt.sim.dt      = Ts / n_sub;
    pt.sim.T_final = Tsim;
    [tF, qF, wF] = target_tumbling_model(pt);
    assert(numel(tF) == K*n_sub + 1, 'baseline_capture_tables:finegrid', ...
        'Fine target history has %d samples, expected K*n_sub+1 = %d.', ...
        numel(tF), K*n_sub + 1);

    ctrlIdx = 1 : n_sub : numel(tF);
    tT = tF(ctrlIdx);  qT = qF(:, ctrlIdx);  wT = wF(:, ctrlIdx);
    assert(numel(tT) == K+1, 'baseline_capture_tables:ctrlgrid', ...
        'Truth control-grid history has %d samples, expected K+1 = %d.', ...
        numel(tT), K+1);

    [pI, vI, nI] = capture_point_trajectory(qT, wT, pt);
    [pLt, vLt, nLt] = capture_point_lvlh(tT, pI, vI, nI, pt);

    % ---- pack ---------------------------------------------------------------
    tabs.t            = tT;
    tabs.p_cp_preview = tbl.pL(:, idx);
    tabs.v_cp_preview = tbl.vL(:, idx);
    tabs.n_cp_preview = tbl.nL(:, idx);
    tabs.p_cp_truth   = pLt;
    tabs.v_cp_truth   = vLt;
    tabs.n_cp_truth   = nLt;
    tabs.qT           = qT;
    tabs.wT           = wT;
    tabs.K            = K;
    tabs.Ts           = Ts;
    tabs.Tsim         = Tsim;
    tabs.tbl_preview  = tbl;      % full extended span, consumed by the MPC path

    % BOTH identities are stored, always. V11b requires it and V2c audits it.
    tabs.identity = struct( ...
        'truth',   struct('q', truthIC.q(:),   'w', truthIC.w(:),   'I', truthIC.I), ...
        'preview', struct('q', previewIC.q(:), 'w', previewIC.w(:), 'I', previewIC.I), ...
        'preview_equals_truth', isequal(truthIC.q(:), previewIC.q(:)) ...
                              && isequal(truthIC.w(:), previewIC.w(:)) ...
                              && isequal(truthIC.I, previewIC.I), ...
        'preview_span_s', Tsim + (N+2)*Ts, ...
        'note', ['Preview and truth are generated independently (different ' ...
                 'integration grids), so bitwise equality is not expected and ' ...
                 'is not required. V2c measures the residual difference.']);
end

% =====================================================================
function check_target_ic(ic, name)
    assert(isstruct(ic) && all(isfield(ic, {'q', 'w', 'I'})), ...
        'baseline_capture_tables:ic', ...
        '%s must be a struct with fields q, w and I.', name);
    assert(numel(ic.q) == 4 && all(isfinite(ic.q(:))), ...
        'baseline_capture_tables:ic_q', '%s.q must be a finite 4-vector.', name);
    assert(abs(norm(ic.q(:)) - 1) <= 1e-12, 'baseline_capture_tables:ic_qnorm', ...
        '%s.q has norm %.17g; a unit quaternion is required.', name, norm(ic.q(:)));
    assert(numel(ic.w) == 3 && all(isfinite(ic.w(:))), ...
        'baseline_capture_tables:ic_w', '%s.w must be a finite 3-vector.', name);
    assert(isequal(size(ic.I), [3 3]) && all(isfinite(ic.I(:))), ...
        'baseline_capture_tables:ic_I', '%s.I must be a finite 3x3 matrix.', name);
end

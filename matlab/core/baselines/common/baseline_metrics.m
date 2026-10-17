function m = baseline_metrics(run, p)
% BASELINE_METRICS  Method-neutral metrics, milestone semantics and T-inputs.
%   m = baseline_metrics(run, p) computes every quantity protocol Sec. 6, 7.1,
%   10.1 and 10.4 define for one completed baseline run. It decides nothing:
%   the total order lives in BASELINE_SELECTION and the R1 diagnostic lives in
%   APF_R1_MARGIN, neither of which this function calls.
%
%   run fields (all required unless noted):
%       t             1x(K+1) control-grid time [s]
%       X             6x(K+1) state history [r; v] in LVLH
%       u_applied     3xK     applied commands
%       u_cmd         3xK     unsaturated commands (APF); == u_applied for the
%                             nominal MPC, which has no post-command clip
%       clip_flags    1xK logical, APF only; [] for the nominal MPC
%       p_cp_truth    3x(K+1) [m]      v_cp_truth 3x(K+1) [m/s]
%       inter_t       1x9K interior times [s]
%       inter_h_body  1x9K interior h_body values [m^2]
%       inter_r       3x9K interior positions [m]   (carried, not used here)
%
%   THE INSPECTED UNION, used identically for NO_OBSERVED_BODY_VIOLATION, T1, T2
%   and t_viol (Sec. 6.2):
%       the K+1 control-state samples + the 9 strict-interior diagnostic points
%       per control interval, total (K+1) + 9*K elements.
%   THIS IS A GRID RESULT, NOT CONTINUOUS-TIME SAFETY, and must never be
%   conflated with the proposed method's continuous-time HOCBF claim.
%
%   rho_truth IS EVALUATED ON THE CONTROL GRID ONLY. No fine-grid event detector
%   is introduced anywhere, at any point (Sec. 6.3 and 10.1).
%
%   TRUTH GEOMETRY FOR EVERY SHARED METRIC (Sec. 7). rho_truth, kstar, the
%   residual shortfall and the approach speed all use p_cp_truth / v_cp_truth.
%   Preview information never enters a reported metric.
%
%   Returned fields include, beside the histories:
%       no_observed_body_violation, min_h_body, t_viol
%       K_safe_count, p_safe, kstar, t_kstar, proximity_achieved
%       rho_dot_truth_kstar (SIGNED), rho_dot_truth_kstar_note
%       I_sel (zero-based interval indices), I_sel_count, empty_selection
%       DeltaV_cumulative, DeltaV_to_proximity, DeltaV_full, DeltaV_Isel
%       clip_fraction_Isel, control_effort, utilisation
%       T1_no_violation, T2_deficit, T3_proximity, T4_shortfall,
%       T5_dv_Isel, T6_clip_Isel        (per-scenario T inputs, Sec. 6.4)

    s_cap  = p.bl.s_cap;
    Ts     = p.ctrl.Ts;
    u_max  = p.chaser.u_max;

    t  = run.t(:).';
    X  = run.X;
    U  = run.u_applied;
    K  = size(U, 2);

    assert(numel(t) == K+1 && size(X, 2) == K+1, 'baseline_metrics:grid', ...
        ['State/time bookkeeping is inconsistent: numel(t) = %d, ' ...
         'size(X,2) = %d, size(u_applied,2) = %d.'], numel(t), size(X, 2), K);

    R = X(1:3, :);
    V = X(4:6, :);

    % ---- control-grid signals ----------------------------------------------
    h_body    = nan(1, K+1);
    clearance = nan(1, K+1);
    for k = 1:K+1
        [h_body(k), clearance(k)] = safety_function(X(:, k), p, p.bl.drift_mode);
    end
    D         = R - run.p_cp_truth;
    rho_truth = sqrt(sum(D.^2, 1));

    % ---- the inspected union, time ordered ---------------------------------
    tAll = [t, run.inter_t(:).'];
    hAll = [h_body, run.inter_h_body(:).'];
    assert(numel(tAll) == (K+1) + numel(run.inter_t), 'baseline_metrics:union', ...
        'Inspected union assembly lost or duplicated a sample.');
    [tAll, ord] = sort(tAll);
    hAll = hAll(ord);

    m.n_inspected = numel(tAll);
    m.min_h_body  = min(hAll);
    m.no_observed_body_violation = ~any(hAll < 0);

    iv = find(hAll < 0, 1, 'first');
    if isempty(iv)
        m.t_viol = Inf;
    else
        m.t_viol = tAll(iv);
    end

    % Well-posedness (Sec. 6.3): every frozen development scenario starts far
    % outside the keep-out sphere, so h_body(t_0) > 0 and t_viol > 0. K_safe can
    % then never be empty. This is asserted, not assumed.
    assert(m.t_viol > t(1), 'baseline_metrics:t_viol_at_start', ...
        ['An observed body violation at or before t_0 makes the safe ' ...
         'control-grid prefix empty; the frozen scenarios cannot produce this.']);

    % ---- safe control-grid prefix (Sec. 6.3) -------------------------------
    isSafeState  = t < m.t_viol;                 % control-grid indices only
    m.K_safe_count = sum(isSafeState);
    m.p_safe       = min(rho_truth(isSafeState));

    % ---- proximity milestone (Sec. 10.1), control grid only ----------------
    ik = find(rho_truth <= s_cap, 1, 'first');   % MATLAB index
    if isempty(ik)
        m.kstar   = [];
        m.t_kstar = NaN;
        m.proximity_achieved = false;
    else
        m.kstar   = ik - 1;                      % zero-based physical index
        m.t_kstar = t(ik);
        % PROXIMITY_ACHIEVED requires no observed body violation UP TO kstar.
        % Expressed through t_viol so the test is exact on the same union:
        % a violation exactly AT t_kstar disqualifies.
        m.proximity_achieved = m.t_viol > m.t_kstar;
    end

    % ---- signed truth range rate at kstar (Sec. 7.1, C4) -------------------
    m.rho_dot_truth_kstar = NaN;
    m.rho_dot_truth_kstar_note = 'no proximity milestone reached';
    if ~isempty(ik)
        d  = D(:, ik);
        nd = norm(d);
        if nd > 0
            m.rho_dot_truth_kstar = ( d.' * (V(:, ik) - run.v_cp_truth(:, ik)) ) / nd;
            m.rho_dot_truth_kstar_note = ['signed truth range rate; negative ' ...
                'means closing. Never replaced by its magnitude.'];
        else
            m.rho_dot_truth_kstar = NaN;
            m.rho_dot_truth_kstar_note = 'undefined at zero separation';
        end
    end

    % ---- selection horizon I_sel (Sec. 6.3) --------------------------------
    % Zero-based APPLIED CONTROL INTERVAL indices. Interval i occupies
    % [t_i, t_{i+1}) and is MATLAB column i+1 of u_applied.
    if m.proximity_achieved
        sel = 0 : (m.kstar - 1);                 % case A; empty when kstar == 0
        m.I_sel_case = 'A_proximity';
    elseif isfinite(m.t_viol)
        % case B: STRICT. Only intervals COMPLETED STRICTLY BEFORE the observed
        % violation qualify. The interval that produced, or contains, the
        % violating state is EXCLUDED and must never improve tuning selection.
        iAll = 0 : (K-1);
        sel  = iAll( t(iAll + 2) < m.t_viol );
        m.I_sel_case = 'B_violation';
    else
        sel = 0 : (K-1);                         % case C: full horizon
        m.I_sel_case = 'C_full';
    end
    m.I_sel          = sel;
    m.I_sel_count    = numel(sel);
    m.empty_selection = isempty(sel);

    % ---- Delta-v and effort (Sec. 10.1, 10.4) ------------------------------
    un = sqrt(sum(U.^2, 1));                     % ||u_i||_2 per applied interval
    m.DeltaV_cumulative  = Ts * cumsum(un);
    m.DeltaV_full        = Ts * sum(un);
    m.control_effort     = Ts * sum(un.^2);

    if isempty(ik)
        m.DeltaV_to_proximity = NaN;
    else
        % Only intervals COMPLETED BEFORE state sample kstar contributed to it.
        m.DeltaV_to_proximity = Ts * sum(un(1:m.kstar));
    end

    if m.empty_selection
        m.DeltaV_Isel = 0;                       % frozen empty-set convention
    else
        m.DeltaV_Isel = Ts * sum(un(sel + 1));
    end

    % ---- APF clipping fraction over I_sel ----------------------------------
    if isfield(run, 'clip_flags') && ~isempty(run.clip_flags)
        cf = logical(run.clip_flags(:).');
        assert(numel(cf) == K, 'baseline_metrics:clip_len', ...
            'clip_flags has %d entries, expected K = %d.', numel(cf), K);
        m.clip_fraction_full = mean(cf);
        if m.empty_selection
            m.clip_fraction_Isel = 0;            % frozen empty-set convention
        else
            m.clip_fraction_Isel = mean(cf(sel + 1));
        end
    else
        % Nominal MPC: the identical box is enforced inside the optimiser, so no
        % post-command clipping exists to measure. NaN records that absence; it
        % is never reported as "zero clipping" (Sec. 10.4).
        m.clip_fraction_full = NaN;
        m.clip_fraction_Isel = NaN;
    end

    % ---- COMMON actuator metrics (Sec. 10.4), dimensionless ----------------
    uinf  = max(abs(U), [], 1);
    ratio = uinf / u_max;
    m.utilisation = struct( ...
        'max_ratio',  max(ratio), ...
        'mean_ratio', mean(ratio), ...
        'fraction',   mean(ratio >= 1 - p.bl.util_eps), ...
        'eps',        p.bl.util_eps, ...
        'ratio_history', ratio, ...
        'note', ['Dimensionless comparison. No acceleration-valued quantity is ' ...
                 'subtracted from the number 1; the 1e-9 constant is NUMERICAL, ' ...
                 'not scientific.']);

    % ---- histories kept for the artifact -----------------------------------
    m.h_body     = h_body;
    m.clearance  = clearance;
    m.rho_truth  = rho_truth;
    m.min_clearance = min(clearance);
    if isempty(ik)
        m.min_clearance_to_kstar = NaN;
    else
        m.min_clearance_to_kstar = min(clearance(1:ik));
    end
    m.rho_truth_final = rho_truth(end);

    % ---- per-scenario inputs to the frozen total order (Sec. 6.4) ----------
    % These are RANKING quantities, not pass conditions. BASELINE_SELECTION
    % aggregates them across the five development scenarios.
    m.T1_no_violation = m.no_observed_body_violation;          % counted, MAX
    m.T2_deficit      = max(0, -m.min_h_body);                 % summed, MIN
    m.T3_proximity    = m.proximity_achieved;                  % counted, MAX
    m.T4_shortfall    = max(m.p_safe - s_cap, 0);              % averaged, MIN
    m.T5_dv_Isel      = m.DeltaV_Isel;                         % averaged, MIN
    m.T6_clip_Isel    = m.clip_fraction_Isel;                  % averaged, MIN

    m.s_cap = s_cap;
    m.s_cap_wording = p.bl.s_cap_wording;
    m.note = ['Body safety here is a GRID result over the inspected union, not ' ...
        'a continuous-time guarantee. Proximity is a method-neutral milestone ' ...
        'and is NEVER described as capture or grasp.'];
end

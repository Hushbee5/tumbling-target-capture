function art = baseline_artifact(run, m, prov)
% BASELINE_ARTIFACT  Assemble the common baseline artifact of protocol V11a.
%   art = baseline_artifact(run, m, prov) merges one SIMULATE_BASELINE output,
%   its BASELINE_METRICS result and the harness-level provenance into the single
%   struct that is saved to disk and validated by BASELINE_SCHEMA.
%
%   prov fields (all required):
%       run_identity, meta, git_head, stamp,
%       protocol_sha, baseline_aggregate_sha, artifact_status, note
%
%   FIELDS DELIBERATELY ABSENT (V11c, protocol Sec. 10.6). psi1_body, psi2_body
%   and d_safe do NOT appear here and do not appear in the metric struct.
%   h_body and the physical clearance are the sufficient common body-safety
%   signals. They may be added later ONLY if a pre-evaluation figure requirement
%   justifies it, and only before the evaluation run.
%
%   ALSO ABSENT, AND FOR THE SAME REASON: every method-specific quantity of
%   Sec. 10.6 - feasibility margins, qp_infeasible, qp_failure, CBF intervention
%   fraction, dev_inf, eta, nu, lambda_min, h_cap, psi1_cap, psi2_cap, the D9
%   event and F1-F5. Those belong to the proposed method's immutable artifacts.
%
%   NO FIELD IS NAMED OR ALIASED 'alpha' (V11e). D9 and alpha are excluded from
%   every baseline controller, harness and classification by Sec. 9, and the
%   configuration this artifact carries was built by BASELINE_CONFIG, which
%   never propagates p.t4.
%
%   DIAGNOSTIC_ONLY IS USED FOR EXACTLY ONE THING (V11d): the terminal a_cp_ff
%   column, stored as a_cp_ff_terminal and tagged a_cp_ff_terminal_tag. It is
%   NOT an element of a_cp_ff_ctrl, which has exactly K columns.

    reqProv = {'run_identity', 'meta', 'git_head', 'stamp', ...
               'protocol_sha', 'baseline_aggregate_sha', 'artifact_status', 'note'};
    assert(isstruct(prov) && all(isfield(prov, reqProv)), 'baseline_artifact:prov', ...
        'prov must carry: %s', strjoin(reqProv, ', '));

    % ---- trajectory and command history ------------------------------------
    art.t         = run.t;
    art.x0        = run.x0;
    art.X         = run.X;
    art.v         = run.v;
    art.u_cmd     = run.u_cmd;
    art.u_applied = run.u_applied;

    % ---- target truth attitude / rate --------------------------------------
    art.qT = run.qT;
    art.wT = run.wT;

    % ---- preview information (controller side) -----------------------------
    art.p_cp_preview = run.p_cp_preview;
    art.v_cp_preview = run.v_cp_preview;
    art.a_cp_ff_ctrl = run.a_cp_ff_ctrl;
    art.a_cp_ff_terminal     = run.a_cp_ff_terminal;
    art.a_cp_ff_terminal_tag = run.a_cp_ff_terminal_tag;   % 'DIAGNOSTIC_ONLY'

    % ---- truth geometry (evaluation side) ----------------------------------
    art.p_cp_truth = run.p_cp_truth;
    art.v_cp_truth = run.v_cp_truth;

    % ---- method-neutral metric histories -----------------------------------
    art.rho_truth = m.rho_truth;
    art.clearance = m.clearance;
    art.h_body    = m.h_body;

    % ---- inspected-union interior diagnostics ------------------------------
    art.inter_t      = run.inter_t;
    art.inter_h_body = run.inter_h_body;
    art.inter_r      = run.inter_r;

    % ---- Delta-v and effort -------------------------------------------------
    art.DeltaV_cumulative   = m.DeltaV_cumulative;
    art.DeltaV_to_proximity = m.DeltaV_to_proximity;
    art.DeltaV_full         = m.DeltaV_full;
    art.control_effort      = m.control_effort;

    % ---- proximity milestone ------------------------------------------------
    art.kstar               = m.kstar;
    art.t_kstar             = m.t_kstar;
    art.rho_dot_truth_kstar = m.rho_dot_truth_kstar;        % SIGNED, never |.|
    art.rho_dot_truth_kstar_note = m.rho_dot_truth_kstar_note;
    art.proximity_achieved  = m.proximity_achieved;
    art.min_clearance_to_kstar = m.min_clearance_to_kstar;

    % ---- T4/T5/T6 inputs and the safe prefix / selection horizon -----------
    art.t_viol          = m.t_viol;
    art.K_safe_count    = m.K_safe_count;
    art.p_safe          = m.p_safe;
    art.I_sel_count     = m.I_sel_count;
    art.empty_selection = m.empty_selection;
    art.I_sel_case      = m.I_sel_case;
    art.DeltaV_Isel     = m.DeltaV_Isel;
    art.clip_fraction_Isel = m.clip_fraction_Isel;

    % ---- body safety (grid result, never a continuous-time claim) ----------
    art.no_observed_body_violation = m.no_observed_body_violation;
    art.min_h_body    = m.min_h_body;
    art.min_clearance = m.min_clearance;
    art.n_inspected   = m.n_inspected;

    % ---- COMMON utilisation histories --------------------------------------
    art.utilisation = m.utilisation;

    % ---- execution integrity ------------------------------------------------
    art.method               = run.method;
    art.K                    = run.K;
    art.K_expected           = run.K_expected;
    art.Tsim                 = run.Tsim;
    art.completed            = run.completed;
    art.numerical_failure    = run.numerical_failure;
    art.failure_reason       = run.failure_reason;
    art.numerically_eligible = run.numerically_eligible;

    % ---- method-specific blocks --------------------------------------------
    if isfield(run, 'apf')
        art.apf = run.apf;
    end
    if isfield(run, 'mpc_solver_status')
        art.mpc_solver_status = run.mpc_solver_status;
    end

    % ---- configuration and provenance --------------------------------------
    art.config       = run.config;
    art.run_identity = prov.run_identity;
    art.meta         = prov.meta;
    art.git_head     = prov.git_head;
    art.stamp        = prov.stamp;
    art.protocol_sha = prov.protocol_sha;
    art.baseline_aggregate_sha = prov.baseline_aggregate_sha;
    art.artifact_status        = prov.artifact_status;
    art.note                   = prov.note;
    art.s_cap_wording          = m.s_cap_wording;
end

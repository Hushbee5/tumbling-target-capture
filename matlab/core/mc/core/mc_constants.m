function c = mc_constants()
% MC_CONSTANTS  Frozen identities and fixed design values of the Task-4 Monte Carlo.
%   c = mc_constants() returns every constant the additive MC source binds to.
%   Each value is copied from the COMMITTED, hash-frozen MC protocol
%
%       notes/task4_mc_protocol_record.md
%       SHA-256 0a859cd775f149a02410d0b8ee1794d62fe5bc25ecec861af7320528628cf69a
%
%   and the protocol section it comes from is cited beside it. Nothing here is
%   tuned, derived from a run, or chosen after any Monte Carlo data exist.
%
%   DELIBERATELY ABSENT - NO PLACEHOLDERS. The identities that authorise
%   scientific trial generation and scientific execution do not exist yet:
%
%       the frozen src/mc aggregate, the MC implementation commit,
%       the trial-table freeze-record SHA-256, the canonical CSV SHA-256.
%
%   They are INPUTS of the authorising invocation (protocol Sec. 11) and are
%   verified there against committed repository state by MC_PREFLIGHT. None of
%   them is represented here by a dummy value that could satisfy a check.

    % ---- the frozen MC protocol (external freeze, commit 8cc6f55) -----------
    c.protocol.path   = 'notes/task4_mc_protocol_record.md';
    c.protocol.sha256 = '0a859cd775f149a02410d0b8ee1794d62fe5bc25ecec861af7320528628cf69a';
    c.protocol.bytes  = 83330;
    c.protocol.commit = '8cc6f55aa571d7cf5962a2038faf4a90812eca13';
    c.protocol.blob   = 'd48015fd9f531e68b3c82a7e5c50c88139fe8a94';

    % ---- the closed deterministic epoch (Sec. 1, Sec. 11 checks 1-2) -------
    c.anchor.commit   = 'f9791f0098cca1ed9ade9c7432176bd94989987b';
    c.anchor.src_tree = 'f165fcb3768d14ca510e0003a23e78db5a9dffd2';

    % ---- frozen file identities: {key, repo-relative path, SHA-256} --------
    % Sec. 1 identity set; Sec. 11 checks 7 (records) and 8 (results).
    c.files = { ...
        'object_a',        'notes/task4_baseline_protocol_record.md', ...
                           '07acf575652d7c182b0696689c19a5f0ef30dbd314c7c1f3fbbbd07cdd8be6e2';
        'object_b_v2',     'notes/task4_baseline_source_freeze_record_v2.md', ...
                           '4f10ac93af92e8f1156779c112be6ff7a5edfc41a97807324498290b3cc12df7';
        'det_record',      'notes/task4_baseline_deterministic_results_record.md', ...
                           'a7b4a43f4d8518082e005080aae0aaf7cbd3bb27faafb27ba9abc83f44ef95bb';
        'transition',      'notes/task4_git_checkpoint_transition_record.md', ...
                           'bf92a7362b9a9ef4cda80d02c08210a8abf3af7c9b7df888f879f44e5ead3de7';
        'postcommit',      'notes/task4_git_checkpoint_postcommit_record.md', ...
                           '9d85421d24fb885d307de46202328ac20ae3422115c5265ee548ab0bde002ef7';
        'gitattributes',   '.gitattributes', ...
                           '82b5a20c7cb5ebca7a35259d8f7ee324a0d73cbebf37ddf1633c1ef1fbbd6340';
        'tuning_record',   'results/task4/baselines_tuning/baseline_tuning_record.mat', ...
                           'a04e3e21b3f545f5ef381e7e3e7de330ddd1298304fbeacf0eac32ae601f29de';
        'gate2',           'results/task4/baselines_verification_r7/baseline_verification_gate.mat', ...
                           'f656ee7fa934fe8b686144b75696ea8eb0fe0a020816727a98298e651aa734e6';
        'bl_nominal_mpc',  'results/task4/baselines/baseline_nominal_mpc_800s.mat', ...
                           'b75fe37c6d123c01365e4995b056a11695f7686a8b607b9aa5093397c76d0edf';
        'bl_apf',          'results/task4/baselines/baseline_apf_800s.mat', ...
                           'ca1653c9d0e645e931170e86d601079238e558e01c070041005ee9d211074195';
        'bl_summary',      'results/task4/baselines/baseline_800s_summary.mat', ...
                           'f68d209c1bb88b46593793c8c54305da7dbcd5aadd195d725f45d5471f9b49bf';
        'proposed_ref',    'results/task4/final800/task4_final_800s_alpha1em3.mat', ...
                           '7a5af1c307a08c42ad0a14778261333121fed0d707eb475ba75d2e36754f32f0';
        'harness_sweep',   'src/sim/task4_alpha_sweep.m', ...
                           '436ed78c3cfff9d5e5a398319469293e014686ac9f68458e45e069977bf1a392';
        'harness_final',   'src/sim/task4_final_800s.m', ...
                           '0b8afa512f3a372c8a5982c550b8c2441cecf467ede45e01230c2fea6c64f70c'};
    % .gitattributes: the value above is the identity AFTER the one reviewed MC
    % rule below was appended (Sec. 10 step 5, R9). Its pre-MC identity was
    % bacf8b4afd5faf034d845dd153035e98fde8e9f6ace90e0a6e475eb247bf2c54.
    c.gitattributes.csv_rule = 'results/task4/mc/*.csv text eol=lf';
    c.gitattributes.pre_mc_sha256 = ...
        'bacf8b4afd5faf034d845dd153035e98fde8e9f6ace90e0a6e475eb247bf2c54';

    % ---- byte aggregates (Sec. 11 check 4) ---------------------------------
    % 17-file production manifest, notes/task4_alpha_sweep_protocol.md Sec. 2.2,
    % in its LC_ALL=C order.
    c.production17.files = { ...
        'src/config/params_task4.m'
        'src/control/cbf_qp_two_row.m'
        'src/control/handoff_detector.m'
        'src/dynamics/capture_barrier.m'
        'src/estimation/cl_estimator_init.m'
        'src/estimation/cl_estimator_step.m'
        'src/estimation/cl_records.m'
        'src/sim/f5_hcap_scan.m'
        'src/sim/simulate_task4.m'
        'src/sim/smoke_task4.m'
        'src/sim/task4_classify.m'
        'src/sim/task4_first_diagnostic.m'
        'src/sim/task4_first_diagnostic_figures.m'
        'src/sim/task4_first_diagnostic_report.m'
        'src/sim/task4_ic_admissibility.m'
        'src/sim/verify_capture_barrier.m'
        'src/utils/struct_field_diff.m'};
    c.production17.aggregate = ...
        'bd3ea14043ef7f0d14e6fed375e5e5ae7624dd88f21ba5753c8d05c36906a241';
    c.r7.dir       = 'src/baselines';
    c.r7.n_files   = 60;
    c.r7.aggregate = 'd372ab19160b5b33c0906c9c61389e7da8e197881a7dad62e8179bf48925bc3f';

    % ---- experimental design (Sec. 3.2, 3.3, 5) ----------------------------
    c.design.N_PHYSICAL = 100;
    c.design.n_draws    = 15;
    c.design.conditions = {'U', 'M'};                       % executed in this order
    c.design.methods    = {'proposed', 'nominal_mpc', 'apf'};  % Sec. 10.3 order
    c.design.Tsim       = 800;
    c.design.Ts         = 0.1;
    c.design.K          = 8000;
    c.design.n_sub      = 10;
    c.design.N_MPC      = 100;
    c.design.alpha      = 1e-3;
    c.design.I_nom      = diag([20, 25, 30]);              % Sec. 3.4, = params().target.I
    c.design.eval_x0    = [0; -10; 0; 0; 0; 0];            % Sec. 3.4 collision rule

    % ---- the ONE scientific random stream (Sec. 3.3) -----------------------
    % Consumed ONLY by MC_SCIENTIFIC_TRIAL_TABLE, and only after the generation
    % preflight has passed. Every other stream in src/mc is a fixture stream.
    c.rng.generator = 'mt19937ar';
    c.rng.seed      = 116075;

    % ---- gates and statistics (Sec. 4.2, 8.2) ------------------------------
    c.v2c.tol_p      = 1e-6;
    c.v2c.tol_v      = 1e-6;
    c.stats.wilson_z = 1.959963984540054;

    % ---- canonical trial table (Sec. 10.1, 10.1.1) -------------------------
    c.csv.path   = 'results/task4/mc/task4_mc_trials.csv';
    c.csv.header = ['trial_id,u01,u02,u03,u04,u05,u06,u07,u08,u09,u10,u11,u12,' ...
                    'u13,u14,u15,r0_x,r0_y,r0_z,v0_x,v0_y,v0_z,q0_s,q0_x,q0_y,' ...
                    'q0_z,w0_x,w0_y,w0_z,I_11,I_22,I_33'];
    c.csv.n_columns = 32;
    c.freeze_record.path = 'notes/task4_mc_trial_table_freeze_record.md';
    c.mc.src_dir  = 'src/mc';
    c.mc.dest_dir = 'results/task4/mc';

    % ---- frozen primary APF winner (Sec. 1, R10) ---------------------------
    c.apf.winner_id = 95;
    c.apf.levels    = [24 8 8 8];
    c.apf.theta     = struct('omega_n', 0.030420264193385706, 'zeta', 1, ...
                             'beta', 6.25, 'kappa', 1);
    c.apf.derived   = struct('k_a', 0.0009253924735953845, ...
                             'k_d', 0.06084052838677141, ...
                             'k_r', 0.0025154775451671006);

    % ---- operational (R11) -------------------------------------------------
    c.exec.max_num_comp_threads = 1;
end

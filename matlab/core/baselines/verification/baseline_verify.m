function gate = baseline_verify(opt)
% BASELINE_VERIFY  The V1-V11 verification gate (protocol Sec. 14).
%   gate = baseline_verify()      runs the whole gate and writes the evidence
%   gate = baseline_verify(opt)   with options (see below)
%
%   Executed and passed BEFORE any scientific development run. Its outputs are
%   IMPLEMENTATION EVIDENCE ONLY, NEVER SCIENTIFIC RESULTS, and are written to a
%   separate namespace: results/task4/baselines_verification/. Nothing this
%   function produces may be reported as a scientific outcome, and nothing here
%   is a baseline result.
%
%   GATE SEMANTICS (Sec. 14.1)
%       ANY V-test FAIL
%          -> NO scientific development run
%          -> patch ONLY additive baseline-support code
%          -> independent review
%          -> recompute the baseline-support aggregate SHA-256
%          -> rerun the ENTIRE gate from V1
%       Scientific tuning starts only after ONE COMPLETE PASS of V1..V11.
%       No production Task 4 source is changed at any point.
%
%   [0; -10; 0; 0; 0; 0] IS FORBIDDEN THROUGHOUT V1-V11. The verification runs
%   start from VP1, and SIMULATE_BASELINE refuses the evaluation IC on every
%   path that does not explicitly set allow_eval_x0, which nothing here does.
%
%   WHAT IS EXECUTED. Two Tsim_V = 5 s runs (one APF, one nominal MPC) plus the
%   TARGET-ONLY 800 s capture-point tables that V2c audits. No 800 s closed-loop
%   run happens: the 800 s bookkeeping statements of V6 and V7 are asserted
%   SYMBOLICALLY from the formulas.
%
%   REQUIRED OPTION - no default, on purpose:
%       expected_aggregate  the ONE frozen baseline-support aggregate SHA-256
%                           from Source-Freeze Record B.
%
%   WHY IT IS SUPPLIED AND NOT CHOSEN HERE. The listing form coreutils
%   sha256sum emits differs between builds (two-space text form versus " *"
%   binary form), so BASELINE_MANIFEST computes BOTH and this gate refuses to
%   promote either to "canonical". The supplied frozen value is asserted against
%   the two computed forms BEFORE any V-test runs, the matched form is reported,
%   and gate.baseline_aggregate_sha carries the SUPPLIED value verbatim - which
%   is what BASELINE_TUNING and BASELINE_EVALUATE later require to match.
%
%   opt fields:
%       out_dir   default <repo>/results/task4/baselines_verification
%       save      default true
%       verbose   default true

    assert(nargin >= 1 && isstruct(opt) && isfield(opt, 'expected_aggregate') ...
           && ~isempty(opt.expected_aggregate), 'baseline_verify:expected_aggregate', ...
        ['opt.expected_aggregate is REQUIRED and has no default. The frozen ' ...
         'baseline-support aggregate is an EXTERNAL identity from Source-Freeze ' ...
         'Record B; this gate refuses to invent or to choose one.']);
    if ~isfield(opt, 'save'),    opt.save    = true; end
    if ~isfield(opt, 'verbose'), opt.verbose = true; end

    thisDir  = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(fileparts(fileparts(thisDir)));
    w = what(repoRoot);  if ~isempty(w), repoRoot = w(1).path; end
    if ~isfield(opt, 'out_dir') || isempty(opt.out_dir)
        opt.out_dir = fullfile(repoRoot, 'results', 'task4', 'baselines_verification');
    end

    p   = baseline_config();
    V   = baseline_verify_inputs(p);
    man = baseline_manifest();

    % The protocol record must still be the one this code was written against.
    protoSha = baseline_sha256(fullfile(repoRoot, p.bl.protocol_file));
    assert(strcmpi(protoSha, p.bl.protocol_sha256), 'baseline_verify:protocol_sha', ...
        'The protocol record hashes to %s, not the frozen %s.', ...
        protoSha, p.bl.protocol_sha256);

    % ---- the SUPPLIED frozen aggregate, asserted BEFORE any V-test ---------
    expAgg = lower(char(opt.expected_aggregate));
    if strcmpi(expAgg, man.aggregate_sha256)
        aggForm = 'text (two-space separator)';
    elseif strcmpi(expAgg, man.aggregate_sha256_binary)
        aggForm = 'binary (space-asterisk separator)';
    else
        error('baseline_verify:aggregate', ...
            ['ABORT: the frozen baseline-support aggregate\n    %s\nmatches ' ...
             'NEITHER independently computed listing form:\n    %s  (text)\n' ...
             '    %s  (binary)\nThe source under src/baselines/** is not the ' ...
             'source Record B froze, so no V-test is run.'], expAgg, ...
            man.aggregate_sha256, man.aggregate_sha256_binary);
    end

    if opt.verbose
        fprintf('=============================================================\n');
        fprintf(' V1-V11 VERIFICATION GATE  (implementation evidence only)\n');
        fprintf('   protocol            %s\n', protoSha);
        fprintf('   frozen aggregate    %s  [%s], %d files\n', ...
            expAgg, aggForm, man.count);
        fprintf('   tracked src worktree matches frozen HEAD (git diff --quiet HEAD -- src)\n');
        fprintf('   theta_V             omega_n %g, zeta %g, beta %g, kappa %g  (OFF-lattice)\n', ...
            V.theta.omega_n, V.theta.zeta, V.theta.beta, V.theta.kappa);
        fprintf('   Tsim_V              %g s -> K_V %d, states %d, interior %d\n', ...
            V.Tsim_V, V.K_V, V.n_states_V, V.n_interior_V);
        fprintf('=============================================================\n');
    end

    % ---- the evidence destination must not already exist -------------------
    % Checked BEFORE any V-test runs, so an existing gate file costs a second
    % rather than a full verification pass, and so a previous PASS can never be
    % silently overwritten by a later run of unknown provenance.
    gateFile = fullfile(opt.out_dir, 'baseline_verification_gate.mat');
    if opt.save
        assert(exist(gateFile, 'file') ~= 2, 'baseline_verify:evidence_exists', ...
            ['ABORT: verification evidence already exists:\n    %s\n' ...
             'It is NOT overwritten. Preserve or archive the existing evidence, ' ...
             'or point opt.out_dir at a fresh verification namespace, and then ' ...
             'invoke the gate again deliberately.'], gateFile);
    end

    % ---- tracked production worktree must match frozen HEAD ----------------
    % Complements the HEAD:src tree-object identity the preflight checks: that
    % one proves nothing under src/ was COMMITTED, this one proves nothing
    % tracked under src/ was EDITED. Untracked src/baselines/** is ignored.
    trackedSrc = baseline_tracked_src_gate(repoRoot);

    % ---- shared inputs ------------------------------------------------------
    targetIC = struct('q', p.target.q0, 'w', p.target.w0, 'I', p.target.I);
    % TARGET-ONLY 800 s tables. No chaser state, no evaluation IC, no scientific
    % baseline run: this is the object V2c audits and the source of p_cp(t) at
    % the frozen test times t_V.
    tabs800 = baseline_capture_tables(p, targetIC, targetIC, p.bl.T_eval);

    % Two short verification runs from VP1. The evaluation IC is never used.
    r1V   = apf_r1_margin(V.gains, p);
    runApf = simulate_baseline(p, struct('method', 'apf', 'x0', V.VP(:, 1), ...
        'Tsim', V.Tsim_V, 'gains', V.gains, 'r1', r1V));
    runMpc = simulate_baseline(p, struct('method', 'nominal_mpc', ...
        'x0', V.VP(:, 1), 'Tsim', V.Tsim_V));

    % ---- V1 .. V10 ----------------------------------------------------------
    R = struct();
    R.V1  = v01_apf_gradient_hessian(p, V, tabs800);
    R.V2  = v02_acp_ff_and_preview_truth(p, V, tabs800);
    R.V3  = v03_cw_drift(p, V);
    R.V4  = v04_sat_box(p, V);
    R.V5  = v05_r1_diagnostic(p, V);
    R.V6  = v06_bookkeeping_indexing(p, V, runApf);
    R.V7  = v07_intersample_points(p, V, runApf);
    R.V8  = v08_ucmd_reconstruction(p, V, runApf);
    R.V9  = v09_apf_exclusion(p, V);
    R.V10 = v10_nominal_mpc_path(p, V, runMpc);

    % ---- V11 : assemble artifacts the way the evaluation harness does -------
    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');            %#ok<TNOW1,DATST>
    head  = git_head_now(repoRoot);
    arts  = struct();
    reps  = struct();
    mets  = struct();
    pairs = {'apf', runApf; 'nominal_mpc', runMpc};
    for i = 1:size(pairs, 1)
        mth = pairs{i, 1};
        run = pairs{i, 2};
        m   = baseline_metrics(run, p);
        mets.(mth) = m;
        prov = struct( ...
            'run_identity', struct('method', mth, 'config', run.config, ...
                'theta_V', V.theta, 'source', 'V1-V11 verification gate'), ...
            'meta', struct('harness', 'baseline_verify', 'Tsim_V', V.Tsim_V, ...
                'v2c', R.V2.v2c, 'is_verification_evidence', true), ...
            'git_head', head, 'stamp', stamp, ...
            'protocol_sha',           protoSha, ...
            'baseline_aggregate_sha', expAgg, ...
            'artifact_status',        'VERIFICATION_EVIDENCE_ONLY', ...
            'note', ['V1-V11 implementation evidence. NOT a scientific result, ' ...
                     'NOT a baseline run, and never to be reported as either.']);
        arts.(mth) = baseline_artifact(run, m, prov);
        % The ACTUAL metric struct is handed to the checker: V11c is a claim
        % about the artifact AND the saved metric struct, and a checker that
        % never saw the latter could only test half of it.
        reps.(mth) = baseline_schema(arts.(mth), mth, m);
    end
    R.V11 = v11_logging_schema(arts, reps);

    % ---- verdict ------------------------------------------------------------
    vn   = fieldnames(R);
    pass = true;
    for i = 1:numel(vn)
        pass = pass && R.(vn{i}).pass;
    end

    if opt.verbose
        fprintf('\n');
        for i = 1:numel(vn)
            r = R.(vn{i});
            fprintf(' %-4s %-58s %s\n', vn{i}, r.name, tern(r.pass, 'PASS', 'FAIL'));
            for q = 1:numel(r.checks)
                c = r.checks(q);
                fprintf('        [%s] %s\n', tern(c.pass, 'ok', 'XX'), c.name);
                fprintf('             %s\n', c.detail);
            end
        end
        fprintf('\n GATE: %s\n', tern(pass, 'PASS (V1..V11 complete)', 'FAIL'));
        if ~pass
            fprintf(2, [' Scientific tuning does NOT start. Patch ONLY additive\n' ...
                        ' baseline-support code, obtain an independent review,\n' ...
                        ' recompute the baseline-support aggregate SHA-256, and\n' ...
                        ' rerun the ENTIRE gate from V1.\n']);
        end
        fprintf('=============================================================\n');
    end

    gate = struct( ...
        'pass',        pass, ...
        'results',     R, ...
        'inputs',      V, ...
        'artifacts',   arts, ...
        'schema',      reps, ...
        'protocol_sha',           protoSha, ...
        'tracked_src_gate',       trackedSrc, ...
        'baseline_aggregate_sha', expAgg, ...
        'baseline_aggregate_form', aggForm, ...
        'baseline_aggregate_text_form',   man.aggregate_sha256, ...
        'baseline_aggregate_binary_form', man.aggregate_sha256_binary, ...
        'baseline_file_count',    man.count, ...
        'metrics',                mets, ...
        'manifest',    rmfield(man, {'listing_text', 'listing_text_binary'}), ...
        'git_head',    head, ...
        'stamp',       stamp, ...
        'namespace',   opt.out_dir, ...
        'status',      'IMPLEMENTATION_EVIDENCE_ONLY', ...
        'note', ['V1-V11 outputs are implementation evidence only, never ' ...
                 'scientific results. Scientific tuning starts only after ONE ' ...
                 'COMPLETE PASS of V1..V11.']);

    if opt.save
        if ~exist(opt.out_dir, 'dir'), mkdir(opt.out_dir); end
        f = gateFile;      % resolved and guarded before any V-test ran
        assert(exist(f, 'file') ~= 2, 'baseline_verify:evidence_exists_late', ...
            'ABORT: verification evidence appeared during the gate: %s', f);
        save(f, 'gate', '-v7.3');
        if opt.verbose, fprintf(' evidence saved to %s\n', f); end
    end
end

% =====================================================================
function h = git_head_now(root)
    h = 'UNAVAILABLE';
    try
        [st, o] = system(sprintf('git -C "%s" rev-parse HEAD', root));
        if st == 0
            o = strtrim(o);
            if ~isempty(regexp(o, '^[0-9a-f]{40}$', 'once')), h = o; end
        end
    catch
        % A missing git is a provenance gap to record, not a reason to stop.
    end
end

% =====================================================================
function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

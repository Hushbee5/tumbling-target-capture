function summary = task4_final_800s()
% TASK4_FINAL_800S  The predeclared three-alpha T4-D9 sweep at the FINAL horizon.
%
%   This harness is the FINAL-HORIZON (Tsim = 800 s) counterpart of the frozen
%   400 s development sweep TASK4_ALPHA_SWEEP. It exists for exactly the same
%   reason: to remove MANUAL EXECUTION AMBIGUITY from a manuscript-grade sweep.
%   It chooses nothing. Every number it uses is either read from the frozen
%   production configuration or asserted against it, and every scientific
%   decision is delegated to the existing production functions:
%
%       task4_ic_admissibility   initial HOCBF admissibility gate
%       simulate_task4           closed loop (MPC + two-row HOCBF-QP + D9)
%       f5_hcap_scan             independent post-hoc D9 replay (F5 branch 2)
%       task4_classify           ordered F1-F5 classifier and sweep verdict
%
%   NOTHING IS REIMPLEMENTED HERE. There is no second copy of the controller,
%   the estimator, the barrier algebra, the D9 predicates, the F5 scan or the
%   F1-F5 rules anywhere in this file. A duplicated rule is a rule that can
%   silently diverge from the frozen one, so the only defensible harness is one
%   that calls the frozen path and reports what it returns.
%
%   WHY A SECOND HARNESS EXISTS AT ALL. TASK4_ALPHA_SWEEP is hash-frozen at
%   436ed78c3cfff9d5e5a398319469293e014686ac9f68458e45e069977bf1a392 and takes
%   no arguments: its horizon, filename tags, output directory and filename
%   prefixes are internal constants, so no external caller can redirect it to
%   800 s. Parameterising it would require editing a frozen artifact. This file
%   is therefore ADDITIVE: the 400 s harness, its artifacts and its records stay
%   immutable, and the cost - two orchestration files that must stay
%   behaviourally consistent - is accepted deliberately and is the reason this
%   file must be reviewed for structural equivalence rather than assumed
%   equivalent to the one it was derived from.
%
%   FROZEN SWEEP CONTRACT (predeclared in notes/task4_final_800s_protocol.md,
%   not decided here)
%       Tsim        800 s                  = 8000 control steps at Ts = 0.1 s
%       alpha_set   [1e-2, 1e-3, 1e-4]     asserted against p.t4.alpha_set
%       x0          [0; -10; 0; 0; 0; 0]   asserted against p.scenario
%       everything else                    from the frozen production config
%
%   alpha is the ONLY quantity that differs between the three runs. This is not
%   merely intended, it is enforced twice: SIMULATE_TASK4 records a sanitized
%   run configuration with the alpha-derived fields removed, and TASK4_CLASSIFY
%   refuses the sweep if any two of those configurations differ.
%
%   EXECUTION ORDER is predeclared and preserved:
%       1. alpha = 1e-2
%       2. alpha = 1e-3
%       3. alpha = 1e-4
%   Runs are never reordered on the basis of intermediate results. There is no
%   tuning, no horizon extension, no retry to obtain a preferred D9 outcome and
%   no parameter change between runs. A genuine execution or infrastructure
%   failure aborts loudly; it is never silently rerun as though nothing happened.
%
%   NOMINAL DETERMINISTIC REPORTING CASE. alpha = 1e-3 was designated as the
%   primary deterministic trajectory BEFORE any 800 s result existed. That
%   designation is recorded as metadata and has NO effect on execution: it does
%   not suppress the other two runs, it does not mark 1e-3 as a validated
%   detector alpha, and it has no power to hide an F1 disagreement.
%
%   D9 TAXONOMY IS UNCHANGED: NORMAL | GUARD_BREACH | NO_EVENT. INELIGIBLE_IC is
%   NOT a fourth D9 outcome; it is a pre-run validation-eligibility status that
%   comes with d9_evaluated = false and the marker event = 'NOT_EVALUATED'.
%
%   SWEEP VERDICT IS UNCHANGED and is produced by TASK4_CLASSIFY, not here:
%       PASS          all three alpha are NORMAL   and no F1-F5
%       INCONCLUSIVE  all three alpha are NO_EVENT and no F1-F5
%       FAIL          any of F1-F5 (F1 includes classification disagreement
%                     across alpha)
%   This harness invents no intermediate success category and never suppresses
%   an F-trigger. PASS, INCONCLUSIVE and FAIL are all acceptable outcomes.
%
%   OUTPUT PROTECTION. Destinations are predeclared, unique to the final-horizon
%   sweep, and disjoint from the 400 s namespace in BOTH directory and filename
%   prefix. The immutable first diagnostic result and all four 400 s sweep
%   artifacts are asserted not to be destinations, rather than assumed not to be.
%   If any destination already exists the harness ABORTS before running anything:
%   it does not overwrite, it does not append to a foreign file, and it does not
%   retry.
%
%   CROSS-RUN INTEGRITY DIAGNOSTIC. alpha moves the D9 detector band; it does not
%   enter the continuous controller until a D9 branch changes the active row set.
%   Before the earliest D9 event among the compared runs the trajectories must
%   therefore agree to numerical precision. All three runs here use the SAME
%   Tsim, hence the same preview construction, so this remains the STRICT check
%   it is at 400 s and is not weakened by anything in the separate 400-vs-800
%   shared-prefix audit. It is an IMPLEMENTATION INTEGRITY diagnostic only. It is
%   NOT part of F1-F5, it does not enter the verdict, and it does not redefine
%   the frozen scientific classifier. If it fails, the harness STOPS after
%   preserving all evidence so the discrepancy can be investigated; it is never
%   tuned around.
%
%   Whether a comparison is meaningful at all is decided from the PRODUCTION
%   OUTPUTS - eligibility, d9_evaluated, event, aborted, qp_failure.occurred,
%   K_applied and t_end - and never from an empty event_log, because an
%   INELIGIBLE_IC refusal and an early abort both log no event while producing no
%   comparable trajectory. The diagnostic reports one of
%       COMPARED_FULL_HORIZON | COMPARED_PRE_EVENT
%       NOT_APPLICABLE_INELIGIBLE | NOT_APPLICABLE_TRUNCATED
%   with an explicit reason. A NOT_APPLICABLE result is not a failure: the check
%   could not run, so it does not raise and it is not an F-trigger. When it is
%   not applicable no measurement exists, so max_dX, max_dU and within_tol are
%   NaN rather than zero/true - a diagnostic that could not run must never read
%   as "measured, and perfectly consistent". The required comparison window is
%   also never shortened to fit a truncated run: if any run stored less than the
%   full required prefix the result is NOT_APPLICABLE_TRUNCATED, not a quieter
%   comparison reported under the same name.
%
%   THE 400-vs-800 SHARED-PREFIX AUDIT IS NOT PERFORMED HERE. It is a SEPARATE
%   read-only review step. This harness only records an unambiguous pointer to
%   the primary frozen 400 s reference and the exact shared window, and saves the
%   full production `out` struct from which that audit can be performed later. It
%   is deliberately NOT folded into the 800-vs-800 cross-alpha check, it is NOT
%   part of F1-F5, and NO closed-loop tolerance for it is encoded anywhere in
%   this file: the separately measured coarse-preview and fine-target exogenous
%   baselines in the frozen protocol authorize no closed-loop tolerance. No time
%   localization of the exogenous difference is encoded here as an execution rule
%   either - the protocol records that localization as a post-hoc descriptive
%   diagnostic, never as an acceptance boundary.
%
%   RUN IDENTITY. Each saved run carries `run_identity`, assembled only from
%   fields the production run returned (config, alpha, eps_rho, eps_h, s_cap).
%   The caller's parameter set is saved separately as `p_base` and is NOT the run
%   identity: SIMULATE_TASK4 applies opt.alpha to its own local copy, so
%   p_base.t4.alpha stays at the development default in every file of the sweep.
%
%   ARTIFACT STATE. Each per-run file is written immediately after its run and is
%   marked RAW_RUN_ONLY_UNCLASSIFIED. Once all three runs, the frozen classifier
%   and the cross-run diagnostic exist, a finalization record replaces that marker
%   with one of, in this fixed priority order,
%       INTEGRITY_FAILURE              xrun applicable and outside tolerance
%       INTEGRITY_FAILURE              any intersample bookkeeping mismatch
%       FINALIZED_XRUN_NOT_APPLICABLE  xrun could not be applied
%       COMPLETE                       otherwise
%   This is execution-status metadata only. None of them is a scientific outcome,
%   none of them is FAIL, and they sit beside the classifier outcome and never
%   inside it. The three per-run artifacts are finalized FIRST and the summary is
%   written LAST, so a summary claiming finalization cannot coexist with a run
%   file still marked RAW_RUN_ONLY_UNCLASSIFIED. Only after ALL evidence is on
%   disk does the harness stop on an integrity failure, so a discrepancy can be
%   investigated rather than re-run.
%
%   THIS FILE CARRIES NO HASH OF ITSELF. A self-referential hash is impossible;
%   the frozen SHA-256 of this harness is maintained EXTERNALLY and is verified
%   at the pre-execution provenance gate of the protocol, together with the
%   17-file production aggregate, the tracked src tree against fb4ff84, the
%   protocol and horizon-record hashes, the protected 400 s diagnostic and the
%   absence of every destination.
%
%   Returns the summary struct that is also saved to disk.

    thisDir  = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(thisDir, '..')));

    % Resolve the repository root ONCE, with '..' segments removed, so that every
    % destination below is absolute and canonical by construction. Two spellings
    % of the same file then cannot compare as different paths.
    repoRoot = fullfile(thisDir, '..', '..');
    wRoot = what(repoRoot);
    if ~isempty(wRoot), repoRoot = wRoot(1).path; end

    %% ---- FROZEN SWEEP CONTRACT -----------------------------------------
    TSIM        = 800;                         % FINAL horizon, frozen by the
                                               % result-independent selection rule
    ALPHA_ORDER = [1e-2, 1e-3, 1e-4];          % predeclared EXECUTION order
    ALPHA_NOMINAL = 1e-3;                      % nominal deterministic reporting
                                               % case, designated pre-execution
    X0_EXPECTED = [0; -10; 0; 0; 0; 0];
    % Predeclared filename tags. 'm' spells the MINUS sign explicitly, because a
    % bare "1e2" reads as a positive exponent. The authoritative numerical alpha
    % is out.alpha / run_identity.alpha, never the filename.
    RUN_TAGS    = {'alpha1em2', 'alpha1em3', 'alpha1em4'};

    % Predeclared step count for the final horizon: 800 / 0.1 = 8000 control
    % steps, hence 8001 stored states and 8000 stored controls. This is a CHECK
    % against the configuration, never the source of truth - the authoritative
    % count is round(TSIM / p_base.ctrl.Ts), asserted against this literal below.
    EXPECTED_STEPS = 8000;

    % Implementation-integrity tolerance for the cross-run diagnostic. This is a
    % SOFTWARE tolerance on quantities that should be bit-identical, not a design
    % margin, not a safety margin and not a scientific threshold. No verdict,
    % classification or reported physical result depends on it.
    XRUN_TOL = 1e-12;

    % Bookkeeping expectation only: at 400 s the intersample diagnostic arrays
    % held 36000 entries for 4000 control steps, i.e. 9 per applied step at the
    % production default n_sub = 10 (applied in SIMULATE_TASK4, not here). This
    % is a sanity check on array bookkeeping, NOT a scientific prediction and NOT
    % an abort condition: a mismatch is reported loudly and recorded, and never
    % silently discards a completed scientific run.
    INTER_PER_STEP = 9;

    %% ---- STABLE EXTERNAL IDENTITIES (recorded, never self-referential) --
    % Frozen elsewhere and reproduced here so every artifact this harness writes
    % names the contract it was executed under. The harness's OWN hash is
    % deliberately absent: it cannot contain a hash of itself.
    IDENT = struct( ...
        'protocol_file',   'notes/task4_final_800s_protocol.md', ...
        'protocol_sha256', '036670b0d7a4a0aee7248c41e5feaf86d4a6a44486c87c4abe2620633d651b0a', ...
        'horizon_file',    'notes/task4_final_horizon_selection.md', ...
        'horizon_sha256',  'f20351ac20ad8ee39c0417244e003948641c40e7b4ca5e68131a37907346e8b0', ...
        'sweep400_harness_file',   'src/sim/task4_alpha_sweep.m', ...
        'sweep400_harness_sha256', '436ed78c3cfff9d5e5a398319469293e014686ac9f68458e45e069977bf1a392', ...
        'harness_sha256',  'MAINTAINED_EXTERNALLY_NOT_SELF_REFERENTIAL');

    p_base = params_task4();

    %% ---- CONTRACT ASSERTIONS -------------------------------------------
    % The frozen configuration already stores the predeclared alpha set. Assert
    % it matches; never silently replace it with a locally written literal.
    assert(isfield(p_base.t4, 'alpha_set'), 'task4_final_800s:no_alpha_set', ...
        'The frozen configuration carries no p_base.t4.alpha_set to check against.');
    assert(isequal(sort(p_base.t4.alpha_set(:).'), sort(ALPHA_ORDER)), ...
        'task4_final_800s:alpha_set', ...
        ['The frozen p_base.t4.alpha_set = [%s] is not the predeclared sweep set ' ...
         '[%s]. The harness refuses to run against a changed set; it does not ' ...
         'overwrite it.'], num2str(p_base.t4.alpha_set, '%g '), num2str(ALPHA_ORDER, '%g '));
    assert(numel(unique(ALPHA_ORDER)) == numel(ALPHA_ORDER), ...
        'task4_final_800s:order', 'The predeclared execution order repeats an alpha.');
    assert(numel(RUN_TAGS) == numel(ALPHA_ORDER), 'task4_final_800s:tags', ...
        'Filename tags and the alpha order are not the same length.');
    % A repeated tag would make two runs share one destination. That is caught
    % later by the late-existence guard, but only after a wasted run, so it is
    % refused up front like every other destination problem.
    assert(numel(unique(RUN_TAGS)) == numel(RUN_TAGS), 'task4_final_800s:tags_unique', ...
        'The predeclared filename tags repeat, so two runs would share a destination.');
    % The nominal reporting case must be one of the runs actually executed.
    assert(any(ALPHA_NOMINAL == ALPHA_ORDER), 'task4_final_800s:alpha_nominal', ...
        'The designated nominal alpha %g is not in the executed order [%s].', ...
        ALPHA_NOMINAL, num2str(ALPHA_ORDER, '%g '));

    % FINAL-HORIZON assertion. SIMULATE_TASK4 refuses a Tsim that is not an
    % integer multiple of Ts, but checking here costs a second instead of a run,
    % and it also binds the horizon to the predeclared step count so a changed Ts
    % cannot silently redefine what "800 s" means in the saved artifacts.
    nStepsExact = TSIM / p_base.ctrl.Ts;
    assert(abs(nStepsExact - round(nStepsExact)) <= 1e-9 * max(1, abs(nStepsExact)), ...
        'task4_final_800s:grid', ...
        'Tsim = %.12g s is not an integer multiple of Ts = %g s.', TSIM, p_base.ctrl.Ts);
    assert(round(nStepsExact) == EXPECTED_STEPS, 'task4_final_800s:steps', ...
        ['Tsim = %g s at Ts = %g s gives %d control steps, not the predeclared ' ...
         '%d. The harness refuses to run a horizon that is not the frozen one.'], ...
        TSIM, p_base.ctrl.Ts, round(nStepsExact), EXPECTED_STEPS);

    % The frozen scenario supplies x0. Assert it is the predeclared state rather
    % than hard-coding a literal that could drift away from the configuration.
    x0 = [p_base.scenario.r0; p_base.scenario.v0];
    assert(isequal(x0, X0_EXPECTED), 'task4_final_800s:x0', ...
        ['The frozen scenario initial state is [%s], not the predeclared sweep ' ...
         'state [%s].'], num2str(x0(:).', '%g '), num2str(X0_EXPECTED(:).', '%g '));

    % Same parameter-drift gate the H-1 diagnostic and the 400 s sweep used. Its
    % purpose is to refuse to run if anything result-relevant moved since the
    % freeze. It is reproduced UNCHANGED: identical fields, identical values.
    drift_ok = p_base.t4.s_cap == 0.106226 && p_base.t4.kappa1 == 0.20 && p_base.t4.kappa2 == 0.20 ...
        && p_base.t4.Tw == 1.0 && p_base.t4.M == 50 && p_base.t4.gamma == 100 ...
        && abs(p_base.t4.nu0 - sqrt(3)) < 1e-15 && all(p_base.t4.theta_hat0 == 0) ...
        && p_base.t4.dwell_samples == 0 ...
        && p_base.cbf.k1 == 0.04 && p_base.cbf.k2 == 0.04 && p_base.cbf.delta == 0 ...
        && p_base.chaser.u_max == 0.01 && p_base.ctrl.Ts == 0.1 && p_base.mpc.N == 100 ...
        && abs(p_base.geom.r_safe - 0.70) < 1e-15;
    assert(drift_ok, 'task4_final_800s:drift', ...
        'A frozen parameter differs from the freeze record. Refusing to run.');

    %% ---- OUTPUT PROTECTION: resolve and guard destinations UP FRONT -----
    % Resolved and checked BEFORE any simulation, so a pre-existing destination
    % costs a second rather than three runs. The final-horizon namespace is
    % disjoint from the 400 s one in BOTH the directory and the filename prefix,
    % and that disjointness is asserted rather than assumed.
    outDir      = fullfile(repoRoot, 'results', 'task4', 'final800');
    runFiles    = cell(1, numel(ALPHA_ORDER));
    for i = 1:numel(ALPHA_ORDER)
        runFiles{i} = fullfile(outDir, sprintf('task4_final_800s_%s.mat', RUN_TAGS{i}));
    end
    summaryFile = fullfile(outDir, 'task4_final_800s_summary.mat');

    % EVERY immutable prior artifact, not just the first diagnostic: the four
    % 400 s sweep files are frozen evidence too and must never be a destination.
    sweepDir = fullfile(repoRoot, 'results', 'task4', 'sweep');
    protectedFiles = { ...
        fullfile(repoRoot, 'results', 'task4', 'task4_first_diagnostic_400s_alpha1e3.mat'), ...
        fullfile(sweepDir, 'task4_sweep_400s_alpha1em2.mat'), ...
        fullfile(sweepDir, 'task4_sweep_400s_alpha1em3.mat'), ...
        fullfile(sweepDir, 'task4_sweep_400s_alpha1em4.mat'), ...
        fullfile(sweepDir, 'task4_sweep_400s_summary.mat')};

    dests = [runFiles, {summaryFile}];
    for i = 1:numel(dests)
        % No destination may resolve to an immutable prior artifact. Both sides
        % were built from the canonical repoRoot resolved above, so a '..'
        % segment cannot disguise one as the other.
        for j = 1:numel(protectedFiles)
            assert(~strcmpi(dests{i}, protectedFiles{j}), ...
                'task4_final_800s:protected', ...
                ['Destination %d resolves to an immutable protected artifact:\n' ...
                 '    %s\nRefusing.'], i, protectedFiles{j});
        end
        if exist(dests{i}, 'file')
            error('task4_final_800s:exists', ...
                ['ABORT: destination already exists:\n    %s\n' ...
                 'The harness never overwrites, never appends to a foreign file ' ...
                 'and never retries. Move or archive the existing result and ' ...
                 'invoke the final-horizon sweep again deliberately.'], dests{i});
        end
    end
    %% ---- REQUIRED 400 s REFERENCE: BLOCKING GATE, BEFORE ANYTHING EXISTS -
    % The protocol preflight REQUIRES the protected first diagnostic, and the
    % 400-vs-800 shared-prefix audit is part of the accepted reporting contract.
    % Producing 800 s artifacts that can never be audited against that reference
    % is therefore not a lesser outcome to be reported afterwards: its absence or
    % corruption ABORTS. This runs BEFORE mkdir and BEFORE any simulation, so a
    % failure here creates nothing at all.
    %
    % The authoritative identity remains the EXTERNAL SHA-256 preflight check
    %     b6d1efd802833582053dc8f0f7ba7b41358b0229326d5e2b96cd7e8ab9f66289
    % The byte-size check below is an additional cheap in-process guard. It is
    % deliberately NOT a substitute for that hash and must never be described as
    % one: equal size does not establish equal content.
    ref400      = protectedFiles{1};
    REF400_SIZE = 4462193;                    % bytes, frozen artifact
    if exist(ref400, 'file') ~= 2
        error('task4_final_800s:reference_missing', ...
            ['ABORT: the required protected 400 s reference is absent:\n    %s\n' ...
             'It is required by the protocol pre-execution provenance gate and ' ...
             'by the 400-vs-800 shared-prefix audit. Restore it and invoke the ' ...
             'final-horizon sweep again deliberately. Nothing has been created.'], ...
            ref400);
    end
    ref400_info = dir(ref400);
    if ref400_info.bytes ~= REF400_SIZE
        error('task4_final_800s:reference_size', ...
            ['ABORT: the protected 400 s reference is %d bytes, not the frozen ' ...
             '%d:\n    %s\nThis is a provenance failure, not a formality. Do not ' ...
             'repair, normalise or continue. Nothing has been created.'], ...
            ref400_info.bytes, REF400_SIZE, ref400);
    end

    if ~exist(outDir, 'dir'), mkdir(outDir); end

    %% ---- 400-vs-800 SHARED-PREFIX AUDIT: POINTER ONLY, NOT PERFORMED ----
    % Recorded so the SEPARATE read-only review step is unambiguous about which
    % file it compares against and over which window. Nothing here compares
    % anything, nothing here is F1-F5, and no closed-loop tolerance is declared:
    % the separately measured coarse-preview and fine-target exogenous baselines
    % in the frozen protocol authorize none.
    prefix_audit = struct( ...
        'performed_here',        false, ...
        'applies_to_alpha',      ALPHA_NOMINAL, ...
        'reference_file',        ref400, ...
        'reference_sha256',      'b6d1efd802833582053dc8f0f7ba7b41358b0229326d5e2b96cd7e8ab9f66289', ...
        'reference_sha_checked_here', false, ...
        'reference_bytes_expected',  REF400_SIZE, ...
        'reference_bytes_on_disk',   ref400_info.bytes, ...
        'reference_gate',        'PASSED_BEFORE_ANY_OUTPUT_EXISTED', ...
        'shared_prefix_states',  round(400 / p_base.ctrl.Ts) + 1, ...
        'shared_prefix_controls', round(400 / p_base.ctrl.Ts), ...
        'is_diagnostic_only',    true, ...
        'note', ['The 400-vs-800 shared-prefix comparison is a SEPARATE ' ...
            'read-only review step. It is NOT part of F1-F5, NOT part of the ' ...
            'sweep verdict, and must never be merged with the 800-vs-800 ' ...
            'cross-alpha integrity check or used to relax it. The full ' ...
            'production out struct saved beside this pointer is the data the ' ...
            'audit needs. No closed-loop tolerance is declared here: the ' ...
            'separately measured coarse-preview and fine-target exogenous ' ...
            'baselines in the frozen protocol are statements about the target ' ...
            'alone and license no closed-loop tolerance. The reference SHA-256 ' ...
            'above is verified by the EXTERNAL preflight; only presence and ' ...
            'byte size were checked in process.']);

    %% ---- PROVENANCE, QUERIED AT EXECUTION TIME --------------------------
    head  = git_head_now(repoRoot);        % never hard-coded
    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
    head_caveat = ['Repository HEAD does not establish the integrity of the ' ...
                   'Task 4 sources: they are untracked. Byte hashes are checked ' ...
                   'externally before and after this execution.'];

    fprintf('=============================================================\n');
    fprintf(' TASK 4 FINAL-HORIZON THREE-ALPHA D9 SWEEP - PREDECLARED, ONCE\n');
    fprintf('=============================================================\n');
    fprintf('   Tsim                    %g s   (%d control steps, %d states)\n', ...
        TSIM, EXPECTED_STEPS, EXPECTED_STEPS + 1);
    fprintf('   alpha execution order   [%s]  (%s)\n', ...
        num2str(ALPHA_ORDER, '%g '), p_base.t4.alpha_status);
    fprintf('   nominal reporting case  alpha = %.0e   (designated pre-execution)\n', ALPHA_NOMINAL);
    fprintf('   x0                      r = [%g %g %g] m, v = [%g %g %g] m/s\n', x0(1:3), x0(4:6));
    fprintf('   s_cap %.6f m | r_safe %.6f m | kappa [%.2f %.2f] | Ts %.2f s | N %d\n', ...
        p_base.t4.s_cap, p_base.geom.r_safe, p_base.t4.kappa1, p_base.t4.kappa2, p_base.ctrl.Ts, p_base.mpc.N);
    fprintf('   protocol                %s\n', IDENT.protocol_file);
    fprintf('                           %s\n', IDENT.protocol_sha256);
    fprintf('   horizon record          %s\n', IDENT.horizon_file);
    fprintf('                           %s\n', IDENT.horizon_sha256);
    fprintf('   HEAD at execution time  %s\n', head);
    fprintf('   NOTE  %s\n', head_caveat);
    fprintf('   destinations            %s\n', outDir);
    fprintf('   400-vs-800 prefix audit NOT performed here (separate read-only step)\n');
    fprintf('   required 400 s reference  PRESENT, %d bytes (gate passed)\n', ref400_info.bytes);
    fprintf('                             %s\n', ref400);
    fprintf('                             SHA-256 verified by the EXTERNAL preflight, not here\n');
    fprintf('=============================================================\n');

    %% ---- RUN LOOP: fixed order, no retry, no tuning ---------------------
    runs   = [];
    scans  = [];
    ics    = [];
    idents = [];
    for i = 1:numel(ALPHA_ORDER)
        a = ALPHA_ORDER(i);
        fprintf('\n RUN %d/%d   alpha = %.0e   Tsim = %g s\n', i, numel(ALPHA_ORDER), a, TSIM);

        % (3) existing IC admissibility gate, recorded per run. alpha does not
        % enter h_cap or psi1_cap, so this is expected to be identical across the
        % three runs; it is evaluated per run anyway so the record is complete.
        ic = task4_ic_admissibility(x0, p_base.target.q0, p_base.target.w0, p_base.t4.theta_hat0, 0, p_base);
        fprintf('   IC gate : h_body %+.6e  psi1_body %+.6e  h_cap %+.6e  psi1_cap %+.6e  -> %s\n', ...
            ic.h_body, ic.psi1_body, ic.h_cap, ic.psi1_cap, ...
            tern(ic.admissible, 'ELIGIBLE', 'INELIGIBLE_IC'));

        % (4) existing production closed loop. Only alpha changes between runs.
        t0  = tic;
        out = simulate_task4(p_base, struct('Tsim', TSIM, 'alpha', a, 'x0', x0));
        rt  = toc(t0);

        % (7) D9 taxonomy is frozen. Assert it, so a foreign string can never be
        % carried forward into a verdict.
        assert(any(strcmp(out.event, {'NORMAL', 'GUARD_BREACH', 'NO_EVENT', 'NOT_EVALUATED'})), ...
            'task4_final_800s:taxonomy', ...
            ['Run %d returned event = ''%s'', which is outside the frozen D9 ' ...
             'taxonomy (NORMAL | GUARD_BREACH | NO_EVENT) and its ' ...
             'NOT_EVALUATED marker.'], i, out.event);
        assert(out.alpha == a, 'task4_final_800s:alpha_echo', ...
            'Run %d was asked for alpha = %g but reports alpha = %g.', i, a, out.alpha);
        % The horizon the simulator actually used must be the one predeclared
        % here; a silently different Tsim would mislabel every saved artifact.
        assert(out.Tsim == TSIM, 'task4_final_800s:tsim_echo', ...
            'Run %d was asked for Tsim = %g s but reports Tsim = %g s.', i, TSIM, out.Tsim);

        fprintf('   run complete in %.1f s   D9 event : %s   eligibility : %s\n', ...
            rt, out.event, out.eligibility);
        fprintf('   K_applied %d / %d expected   states stored %d   controls stored %d\n', ...
            out.K_applied, EXPECTED_STEPS, size(out.X, 2), size(out.Usafe, 2));

        % (5) existing independent F5 replay. (6) its source binding to this exact
        % run is established inside F5_HCAP_SCAN and re-checked by TASK4_CLASSIFY.
        scan = f5_hcap_scan(out, p_base);
        fprintf('   independent scan : %s   agree %d   F5 branch %s\n', ...
            scan.independent_event, scan.classification_agree, scan.F5_branch);

        % Per-run evidence is written immediately, so an interruption later in the
        % sweep cannot destroy a completed run. The destination was guarded above
        % and is re-checked here against anything that appeared in the meantime.
        if exist(runFiles{i}, 'file')
            error('task4_final_800s:exists_late', ...
                'ABORT: destination appeared during the sweep: %s', runFiles{i});
        end
        % AUTHORITATIVE RUN IDENTITY. It is assembled ONLY from fields the
        % production run itself returned; nothing alpha-derived is recomputed
        % here. p_base is the CALLER's parameter set and is deliberately NOT the
        % identity of the run: SIMULATE_TASK4 applies opt.alpha to its own local
        % copy, so p_base.t4.alpha stays at the development default for every run
        % in the sweep. Saving it under a name that cannot be mistaken for the
        % run configuration is the point.
        run_identity = struct('config',  out.config, ...
                              'alpha',   out.alpha, ...
                              'eps_rho', out.eps_rho, ...
                              'eps_h',   out.eps_h, ...
                              's_cap',   out.s_cap);

        % ARTIFACT STATE. At this moment the file holds ONE raw run and no
        % cross-run classification, because classification is a cross-run result
        % that cannot exist yet. Marking it makes it impossible to mistake a
        % crash-interrupted raw run for a fully classified sweep result.
        artifact_status = 'RAW_RUN_ONLY_UNCLASSIFIED';
        artifact_status_note = ['Raw run only. The frozen classifier and the ' ...
            'cross-run diagnostic are cross-run results and do not exist yet. ' ...
            'This is execution-status metadata, never a scientific outcome.'];

        meta = struct('alpha', a, 'Tsim', TSIM, 'x0', x0, 'run_index', i, ...
                      'run_order', ALPHA_ORDER, 'runtime_s', rt, ...
                      'expected_steps', EXPECTED_STEPS, ...
                      'alpha_nominal', ALPHA_NOMINAL, ...
                      'is_nominal_case', a == ALPHA_NOMINAL, ...
                      'ic', ic, 'git_head_at_execution', head, ...
                      'head_caveat', head_caveat, 'stamp', stamp, ...
                      'identities', IDENT, 'prefix_audit', prefix_audit, ...
                      'harness', 'task4_final_800s');
        save(runFiles{i}, 'out', 'scan', 'run_identity', 'p_base', 'meta', ...
                          'artifact_status', 'artifact_status_note', '-v7.3');
        fprintf('   raw run saved to %s   [%s]\n', runFiles{i}, artifact_status);

        runs  = [runs,  out];           %#ok<AGROW>
        scans = [scans, scan];          %#ok<AGROW>
        ics   = [ics,   ic];            %#ok<AGROW>
        idents = [idents, run_identity]; %#ok<AGROW>
    end

    %% ---- CLASSIFIER: existing, frozen, not reimplemented ----------------
    cls = task4_classify(runs, scans, p_base);

    fprintf('\n=============================================================\n');
    fprintf(' SWEEP CLASSIFICATION (produced by TASK4_CLASSIFY, frozen rule)\n');
    fprintf('   per-alpha D9 events : ');
    for i = 1:numel(runs), fprintf('%.0e -> %s   ', runs(i).alpha, runs(i).event); end
    fprintf('\n   F1 %d  F2 %d  F3 %d  F4 %d  F5 %d\n', ...
        cls.F1, cls.F2, cls.F3, cls.F4, cls.F5);
    fprintf('   OUTCOME : %s\n', cls.outcome);
    if isfield(cls, 'note') && ~isempty(cls.note), fprintf('   note    : %s\n', cls.note); end
    fprintf('=============================================================\n');

    %% ---- CROSS-RUN INTEGRITY DIAGNOSTIC (read-only, NOT F1-F5) ----------
    xrun = cross_run_check(runs, ALPHA_ORDER, XRUN_TOL, round(TSIM / p_base.ctrl.Ts));
    fprintf('\n CROSS-RUN IMPLEMENTATION-INTEGRITY DIAGNOSTIC (not F1-F5)\n');
    fprintf('   status           : %s\n', xrun.status);
    fprintf('   reason           : %s\n', xrun.reason);
    fprintf('   samples compared : %d of %d\n', xrun.k_compared, xrun.k_available);
    fprintf('   max |dX|         : %.6e   (state)\n', xrun.max_dX);
    fprintf('   max |dU_safe|    : %.6e   (applied control)\n', xrun.max_dU);
    fprintf('   tolerance        : %.0e   (software integrity only)\n', XRUN_TOL);
    fprintf('   VERDICT          : %s\n', xrun.verdict);

    %% ---- INTERSAMPLE ARRAY BOOKKEEPING (integrity check, not F1-F5) -----
    % The protocol declares the 9-per-applied-step convention an abort/sanity
    % INTEGRITY check, so a mismatch is an IMPLEMENTATION / ARTIFACT INTEGRITY
    % FAILURE here - not a warning, and not a scientific outcome. It is NOT
    % F1-F5, it is NOT a scientific FAIL, and it does not touch the classifier.
    % All evidence is still finalized and the summary is still written; only
    % after that does the harness stop.
    inter_n        = arrayfun(@(r) numel(r.inter.h_body), runs);
    inter_expected = [runs.K_applied] * INTER_PER_STEP;
    inter_match    = inter_n == inter_expected;
    inter_ok       = all(inter_match);
    intersample_bookkeeping = struct( ...
        'per_step',      INTER_PER_STEP, ...
        'observed',      inter_n, ...
        'expected',      inter_expected, ...
        'match',         inter_match, ...
        'all_match',     inter_ok, ...
        'is_diagnostic_only', true, ...
        'note', ['Array-length integrity check. A mismatch is an ' ...
                 'IMPLEMENTATION / ARTIFACT INTEGRITY FAILURE recorded in ' ...
                 'artifact_status; it is NOT F1-F5 and NOT a scientific FAIL. ' ...
                 'The classifier outcome is in the classifier variable and is ' ...
                 'unaffected.']);
    fprintf('\n INTERSAMPLE ARRAY BOOKKEEPING (integrity check, not F1-F5)\n');
    fprintf('   observed : %s\n', mat2str(inter_n));
    fprintf('   expected : %s   (%d per applied step)\n', mat2str(inter_expected), INTER_PER_STEP);
    if inter_ok
        fprintf('   MATCH\n');
    else
        fprintf(2, ['   MISMATCH: %s\n' ...
                    '   IMPLEMENTATION / ARTIFACT INTEGRITY FAILURE. Not F1-F5, not a\n' ...
                    '   scientific FAIL. All evidence is finalized first, then the\n' ...
                    '   harness stops. Investigate; do not rerun and do not tune.\n'], ...
                    mat2str(inter_match));
    end

    % ---- EXECUTION-STATUS metadata, kept strictly beside the science --------
    % This describes the state of the ARTIFACT, never the scientific outcome.
    % PASS / INCONCLUSIVE / FAIL and F1-F5 live in `classifier` and are untouched.
    % A NOT_APPLICABLE cross-run diagnostic is not an integrity FAILURE: the check
    % could not run, it did not fail, so the reason is recorded in
    % cross_run.status instead. An out-of-tolerance cross-run comparison and an
    % intersample bookkeeping mismatch ARE integrity failures, and both outrank
    % NOT_APPLICABLE in the fixed priority order below.
    stop_xrun  = xrun.applicable && ~xrun.within_tol;
    stop_inter = ~inter_ok;
    if stop_xrun
        artifact_status = 'INTEGRITY_FAILURE';
    elseif stop_inter
        artifact_status = 'INTEGRITY_FAILURE';
    elseif ~xrun.applicable
        artifact_status = 'FINALIZED_XRUN_NOT_APPLICABLE';
    else
        artifact_status = 'COMPLETE';
    end
    artifact_status_note = ['Execution-status metadata for this artifact. It is ' ...
        'independent of the scientific classifier outcome, which is in the ' ...
        '`classifier` variable. INTEGRITY_FAILURE covers an out-of-tolerance ' ...
        'cross-run comparison and an intersample bookkeeping mismatch; neither ' ...
        'is F1-F5 and neither is a scientific FAIL.'];

    %% ---- FINALIZE THE THREE PER-RUN ARTIFACTS, BEFORE ANY SUMMARY -------
    % ORDERING MATTERS. The summary is the artifact that claims the sweep was
    % finalized, so it must not exist until every per-run artifact has actually
    % been finalized. Writing it first would allow a summary marked COMPLETE to
    % coexist with a run file still marked RAW_RUN_ONLY_UNCLASSIFIED if an append
    % failed. If any append below raises, no summary is written at all.
    %
    % The classification is a CROSS-RUN result and cannot exist when a single run
    % is written, so it is appended here: an append of our own just-written
    % variables, never an append to a pre-existing foreign file. `artifact_status`
    % is written again under the same name, which REPLACES the
    % RAW_RUN_ONLY_UNCLASSIFIED marker set during the run loop; that replacement
    % is the whole point of the finalization record. There is no retry.
    for i = 1:numel(runFiles)
        classifier = cls;
        cross_run  = xrun;
        save(runFiles{i}, 'classifier', 'cross_run', 'intersample_bookkeeping', ...
                          'artifact_status', 'artifact_status_note', '-append');
    end
    fprintf('\n finalized all %d run files: classifier + cross-run diagnostic, status %s\n', ...
        numel(runFiles), artifact_status);

    %% ---- SUMMARY OUTPUT, WRITTEN LAST -----------------------------------
    summary = struct( ...
        'Tsim',                 TSIM, ...
        'expected_steps',       EXPECTED_STEPS, ...
        'alpha_order',          ALPHA_ORDER, ...
        'alpha_nominal',        ALPHA_NOMINAL, ...
        'x0',                   x0, ...
        'events',               {{runs.event}}, ...
        'eligibility',          {{runs.eligibility}}, ...
        'd9_evaluated',         [runs.d9_evaluated], ...
        'independent_events',   {{scans.independent_event}}, ...
        'F5_branches',          {{scans.F5_branch}}, ...
        'classifier',           cls, ...
        'run_identity',         idents, ...
        'ic',                   ics, ...
        'cross_run',            xrun, ...
        'intersample_bookkeeping', intersample_bookkeeping, ...
        'prefix_audit',         prefix_audit, ...
        'artifact_status',      artifact_status, ...
        'xrun_tol',             XRUN_TOL, ...
        'run_files',            {runFiles}, ...
        'identities',           IDENT, ...
        'git_head_at_execution', head, ...
        'head_caveat',          head_caveat, ...
        'stamp',                stamp, ...
        'harness',              'task4_final_800s');

    if exist(summaryFile, 'file')
        error('task4_final_800s:exists_late', ...
            'ABORT: summary destination appeared during the sweep: %s', summaryFile);
    end
    save(summaryFile, 'summary', 'p_base', 'artifact_status', ...
                      'artifact_status_note', '-v7.3');
    fprintf(' sweep summary saved to %s   [%s]\n', summaryFile, artifact_status);

    % The integrity diagnostics are reported and ALL evidence is on disk - the
    % three finalized per-run artifacts and the summary - BEFORE the harness stops
    % on them, so an unexpected difference can be investigated rather than re-run.
    % Neither condition is a scientific outcome and neither ever becomes one.
    if stop_xrun || stop_inter
        detail = '';
        if stop_xrun
            detail = sprintf(['Pre-event cross-run differences exceed the ' ...
                'declared software integrity tolerance (max |dX| = %.6e, ' ...
                'max |dU| = %.6e, tol = %.0e). '], xrun.max_dX, xrun.max_dU, XRUN_TOL);
        end
        if stop_inter
            detail = [detail sprintf(['Intersample array bookkeeping ' ...
                'mismatched (observed %s, expected %s at %d per applied step). '], ...
                mat2str(inter_n), mat2str(inter_expected), INTER_PER_STEP)];
        end
        error('task4_final_800s:integrity', ...
            ['STOP: implementation / artifact integrity failure. %s' ...
             'All evidence has been saved: the three per-run artifacts are ' ...
             'finalized and the summary is written, both marked %s. This is NOT ' ...
             'F1-F5 and NOT a scientific FAIL - the classifier outcome is in the ' ...
             '`classifier` variable and is unaffected. Investigate the ' ...
             'implementation; do not tune around this and do not rerun as though ' ...
             'nothing happened.'], detail, artifact_status);
    end
    fprintf('=============================================================\n');
end

% =====================================================================
function xr = cross_run_check(runs, alphaOrder, tol, expectedSteps)
% READ-ONLY cross-run consistency. alpha moves the detector band only; until a
% D9 branch changes the active row set the closed loops are the same trajectory.
% This compares them and reports the largest deviation. It is a SOFTWARE
% integrity diagnostic: it is not F1-F5, it does not enter the sweep verdict and
% it establishes no physical or theoretical property.
%
% COMPLETION IS ESTABLISHED FROM THE PRODUCTION OUTPUTS, NEVER INFERRED FROM AN
% EMPTY event_log. An INELIGIBLE_IC refusal and an early abort each produce an
% empty event log while producing no comparable trajectory at all, so reading
% "nothing was logged" as "completed NO_EVENT run" would describe a refused or
% truncated run as a full-horizon comparison. The completion state is therefore
% read from eligibility, d9_evaluated, event, aborted, qp_failure.occurred,
% K_applied and t_end, all of which the production run already returns.
    A = numel(runs);
    xr.alpha_order    = alphaOrder;
    xr.expected_steps = expectedSteps;

    % ---- per-run completion state, from the production outputs -------------
    eligible  = false(1, A);
    completed = false(1, A);
    noEvent   = false(1, A);
    for i = 1:A
        r = runs(i);
        eligible(i)  = strcmp(r.eligibility, 'ELIGIBLE') && r.d9_evaluated;
        completed(i) = eligible(i) && ~r.aborted && ~r.qp_failure.occurred ...
                       && r.K_applied == expectedSteps && r.t_end == r.Tsim;
        noEvent(i)   = strcmp(r.event, 'NO_EVENT');
    end
    xr.eligible  = eligible;
    xr.completed = completed;
    xr.events    = {runs.event};

    % Earliest D9 firing sample among the runs, or Inf where nothing fired.
    kEvent = inf(1, A);
    for i = 1:A
        if ~isempty(runs(i).event_log) && isfield(runs(i).event_log, 'k')
            kEvent(i) = runs(i).event_log(1).k;
        end
    end
    xr.k_event = kEvent;

    % Stored lengths per run. The integrity claim is that the runs agree over the
    % FULL required prefix, so the window is NEVER silently shortened to whatever
    % a truncated run happened to store: insufficient data makes the diagnostic
    % NOT_APPLICABLE rather than a shorter comparison under the same name.
    nX = arrayfun(@(r) size(r.X, 2), runs);
    nU = arrayfun(@(r) size(r.Usafe, 2), runs);
    kApp = [runs.K_applied];
    xr.n_state_stored   = nX;
    xr.n_control_stored = nU;
    xr.k_applied        = kApp;
    xr.k_available      = min(nX);

    % ---- window selection --------------------------------------------------
    kState = 0;  kCtrl = 0;
    xr.k_pre_required = [];
    if ~all(eligible)
        xr.status     = 'NOT_APPLICABLE_INELIGIBLE';
        xr.reason     = sprintf(['At least one run is not an eligible, ' ...
            'detector-evaluated run (eligibility: %s). No cross-run trajectory ' ...
            'comparison is meaningful.'], strjoin({runs.eligibility}, '/'));
        xr.applicable = false;
    elseif any(isfinite(kEvent))
        % A genuine D9 event fired. The required window is strictly BEFORE the
        % earliest one: the firing sample is where the branch is taken, so it is
        % excluded from the "should be identical" prefix.
        kPre = min(kEvent) - 1;
        xr.k_pre_required = kPre;
        if kPre < 1
            xr.status     = 'NOT_APPLICABLE_TRUNCATED';
            xr.reason     = sprintf(['The earliest D9 event is at k = %d, so no ' ...
                'common pre-event window exists.'], min(kEvent));
            xr.applicable = false;
        elseif any(nX < kPre) || any(nU < kPre) || any(kApp < kPre)
            % A run stored less than the required prefix. Comparing only the part
            % that survives would test a weaker claim while still calling the
            % result COMPARED_PRE_EVENT, so it is refused instead.
            xr.status     = 'NOT_APPLICABLE_TRUNCATED';
            xr.reason     = sprintf(['The required pre-event prefix is k = %d, ' ...
                'but the stored data does not cover it in every run ' ...
                '(size(X,2) = %s, size(Usafe,2) = %s, K_applied = %s). The ' ...
                'window is not shortened to fit.'], kPre, ...
                mat2str(nX), mat2str(nU), mat2str(kApp));
            xr.applicable = false;
        else
            xr.status     = 'COMPARED_PRE_EVENT';
            xr.reason     = sprintf(['Compared over the full pre-event prefix ' ...
                'k = 1..%d (earliest D9 event at k = %d); every run stores at ' ...
                'least that prefix.'], kPre, min(kEvent));
            xr.applicable = true;
            kState = kPre;  kCtrl = kPre;
        end
    elseif all(completed) && all(noEvent)
        % completed(i) already required K_applied == expectedSteps. Confirm the
        % stored arrays match that horizon exactly: K+1 states and K controls.
        if any(nX ~= expectedSteps + 1) || any(nU ~= expectedSteps)
            xr.status     = 'NOT_APPLICABLE_TRUNCATED';
            xr.reason     = sprintf(['Every run reports a completed NO_EVENT ' ...
                'horizon, but the stored array lengths do not match it ' ...
                '(expected size(X,2) = %d and size(Usafe,2) = %d; got %s and ' ...
                '%s).'], expectedSteps + 1, expectedSteps, mat2str(nX), mat2str(nU));
            xr.applicable = false;
        else
            xr.status     = 'COMPARED_FULL_HORIZON';
            xr.reason     = sprintf(['All %d runs are completed, eligible ' ...
                'NO_EVENT runs (K_applied = %d, t_end = Tsim), so the entire ' ...
                'horizon is comparable.'], A, expectedSteps);
            xr.applicable = true;
            kState = expectedSteps + 1;  kCtrl = expectedSteps;
        end
    else
        xr.status     = 'NOT_APPLICABLE_TRUNCATED';
        xr.reason     = sprintf(['No D9 event fired, but not every run is a ' ...
            'completed NO_EVENT run (completed: %s; events: %s). A full-horizon ' ...
            'comparison would misdescribe a truncated or aborted run.'], ...
            mat2str(completed), strjoin({runs.event}, '/'));
        xr.applicable = false;
    end
    xr.k_compared   = kState;
    xr.k_compared_u = kCtrl;
    xr.tol          = tol;

    % ---- measurement -------------------------------------------------------
    if xr.applicable
        xr.max_dX = 0;  xr.max_dU = 0;
        xr.pair_dX = zeros(A);  xr.pair_dU = zeros(A);
        for i = 1:A
            for j = i+1:A
                dX = max(max(abs(runs(i).X(:,1:kState)     - runs(j).X(:,1:kState))));
                dU = max(max(abs(runs(i).Usafe(:,1:kCtrl) - runs(j).Usafe(:,1:kCtrl))));
                xr.pair_dX(i,j) = dX;  xr.pair_dX(j,i) = dX;
                xr.pair_dU(i,j) = dU;  xr.pair_dU(j,i) = dU;
                xr.max_dX = max(xr.max_dX, dX);
                xr.max_dU = max(xr.max_dU, dU);
            end
        end
        xr.within_tol = (xr.max_dX <= tol) && (xr.max_dU <= tol);
        if xr.within_tol
            xr.verdict = 'CONSISTENT';
        else
            xr.verdict = 'UNEXPECTED DIFFERENCE';
        end
    else
        % NO COMPARISON WAS PERFORMED, so there is no measurement. NaN is used
        % rather than zero/true so that a not-applicable diagnostic can never be
        % misread as "measured, and perfectly consistent". NaN is not a failure:
        % every consumer is guarded by xr.applicable, which short-circuits first.
        xr.max_dX  = NaN;      xr.max_dU  = NaN;
        xr.pair_dX = NaN(A);   xr.pair_dU = NaN(A);
        xr.within_tol = NaN;
        xr.verdict    = 'NOT APPLICABLE';
    end
    xr.is_diagnostic_only = true;
    xr.note = ['Implementation-integrity diagnostic. NOT part of F1-F5 and not ' ...
               'part of the frozen sweep verdict.'];
end

% =====================================================================
function h = git_head_now(repoRoot)
% Repository HEAD, queried at execution time. Never hard-coded, and never
% presented as evidence about the untracked Task 4 sources.
    h = 'UNAVAILABLE';
    try
        [st, o] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
        if st == 0
            o = strtrim(o);
            if ~isempty(regexp(o, '^[0-9a-f]{40}$', 'once')), h = o; end
        end
    catch
        % A missing git is a provenance gap to record, not a reason to stop the
        % scientific run; it is reported as UNAVAILABLE.
    end
end

% =====================================================================
function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

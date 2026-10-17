function summary = task4_alpha_sweep()
% TASK4_ALPHA_SWEEP  The predeclared three-alpha T4-D9 sweep, executed once.
%
%   This harness exists to remove MANUAL EXECUTION AMBIGUITY from the
%   manuscript-grade sweep. It chooses nothing. Every number it uses is either
%   read from the frozen production configuration or asserted against it, and
%   every scientific decision is delegated to the existing production functions:
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
%   FROZEN SWEEP CONTRACT (predeclared, not decided here)
%       Tsim        400 s
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
%   an F-trigger.
%
%   OUTPUT PROTECTION. Destinations are predeclared and unique to the sweep. The
%   immutable first diagnostic result is never a destination, and that is
%   asserted, not assumed. If any destination already exists the harness ABORTS
%   before running anything: it does not overwrite, it does not append to a
%   foreign file, and it does not retry.
%
%   CROSS-RUN INTEGRITY DIAGNOSTIC. alpha moves the D9 detector band; it does not
%   enter the continuous controller until a D9 branch changes the active row set.
%   Before the earliest D9 event among the compared runs the trajectories must
%   therefore agree to numerical precision. That check is an IMPLEMENTATION
%   INTEGRITY diagnostic only. It is NOT part of F1-F5, it does not enter the
%   verdict, and it does not redefine the frozen scientific classifier. If it
%   fails, the harness STOPS after preserving all evidence so the discrepancy can
%   be investigated; it is never tuned around.
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
%   RUN IDENTITY. Each saved run carries `run_identity`, assembled only from
%   fields the production run returned (config, alpha, eps_rho, eps_h, s_cap).
%   The caller's parameter set is saved separately as `p_base` and is NOT the run
%   identity: SIMULATE_TASK4 applies opt.alpha to its own local copy, so
%   p_base.t4.alpha stays at the development default in every file of the sweep.
%
%   ARTIFACT STATE. Each per-run file is written immediately after its run and is
%   marked RAW_RUN_ONLY_UNCLASSIFIED. Once all three runs, the frozen classifier
%   and the cross-run diagnostic exist, a finalization record replaces that marker
%   with one of
%       COMPLETE                       xrun applicable and within tolerance
%       INTEGRITY_FAILURE              xrun applicable and outside tolerance
%       FINALIZED_XRUN_NOT_APPLICABLE  xrun could not be applied
%   This is execution-status metadata only. None of the three is a scientific
%   outcome, none of them is FAIL, and they sit beside the classifier outcome and
%   never inside it. The three per-run artifacts are finalized FIRST and the
%   summary is written LAST, so a summary claiming finalization cannot coexist
%   with a run file still marked RAW_RUN_ONLY_UNCLASSIFIED.
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
    TSIM        = 400;
    ALPHA_ORDER = [1e-2, 1e-3, 1e-4];          % predeclared EXECUTION order
    X0_EXPECTED = [0; -10; 0; 0; 0; 0];
    % Predeclared filename tags. 'm' spells the MINUS sign explicitly, because a
    % bare "1e2" reads as a positive exponent. The authoritative numerical alpha
    % is out.alpha / run_identity.alpha, never the filename.
    RUN_TAGS    = {'alpha1em2', 'alpha1em3', 'alpha1em4'};

    % Implementation-integrity tolerance for the cross-run diagnostic. This is a
    % SOFTWARE tolerance on quantities that should be bit-identical, not a design
    % margin, not a safety margin and not a scientific threshold. No verdict,
    % classification or reported physical result depends on it.
    XRUN_TOL = 1e-12;

    p_base = params_task4();

    %% ---- CONTRACT ASSERTIONS -------------------------------------------
    % The frozen configuration already stores the predeclared alpha set. Assert
    % it matches; never silently replace it with a locally written literal.
    assert(isfield(p_base.t4, 'alpha_set'), 'task4_alpha_sweep:no_alpha_set', ...
        'The frozen configuration carries no p_base.t4.alpha_set to check against.');
    assert(isequal(sort(p_base.t4.alpha_set(:).'), sort(ALPHA_ORDER)), ...
        'task4_alpha_sweep:alpha_set', ...
        ['The frozen p_base.t4.alpha_set = [%s] is not the predeclared sweep set ' ...
         '[%s]. The harness refuses to run against a changed set; it does not ' ...
         'overwrite it.'], num2str(p_base.t4.alpha_set, '%g '), num2str(ALPHA_ORDER, '%g '));
    assert(numel(unique(ALPHA_ORDER)) == numel(ALPHA_ORDER), ...
        'task4_alpha_sweep:order', 'The predeclared execution order repeats an alpha.');
    assert(numel(RUN_TAGS) == numel(ALPHA_ORDER), 'task4_alpha_sweep:tags', ...
        'Filename tags and the alpha order are not the same length.');

    % The frozen scenario supplies x0. Assert it is the predeclared state rather
    % than hard-coding a literal that could drift away from the configuration.
    x0 = [p_base.scenario.r0; p_base.scenario.v0];
    assert(isequal(x0, X0_EXPECTED), 'task4_alpha_sweep:x0', ...
        ['The frozen scenario initial state is [%s], not the predeclared sweep ' ...
         'state [%s].'], num2str(x0(:).', '%g '), num2str(X0_EXPECTED(:).', '%g '));

    % Same parameter-drift gate the H-1 diagnostic used. Its purpose is to refuse
    % to run if anything result-relevant moved since the freeze.
    drift_ok = p_base.t4.s_cap == 0.106226 && p_base.t4.kappa1 == 0.20 && p_base.t4.kappa2 == 0.20 ...
        && p_base.t4.Tw == 1.0 && p_base.t4.M == 50 && p_base.t4.gamma == 100 ...
        && abs(p_base.t4.nu0 - sqrt(3)) < 1e-15 && all(p_base.t4.theta_hat0 == 0) ...
        && p_base.t4.dwell_samples == 0 ...
        && p_base.cbf.k1 == 0.04 && p_base.cbf.k2 == 0.04 && p_base.cbf.delta == 0 ...
        && p_base.chaser.u_max == 0.01 && p_base.ctrl.Ts == 0.1 && p_base.mpc.N == 100 ...
        && abs(p_base.geom.r_safe - 0.70) < 1e-15;
    assert(drift_ok, 'task4_alpha_sweep:drift', ...
        'A frozen parameter differs from the freeze record. Refusing to run.');

    %% ---- OUTPUT PROTECTION: resolve and guard destinations UP FRONT -----
    % Resolved and checked BEFORE any simulation, so a pre-existing destination
    % costs a second rather than three runs.
    outDir      = fullfile(repoRoot, 'results', 'task4', 'sweep');
    runFiles    = cell(1, numel(ALPHA_ORDER));
    for i = 1:numel(ALPHA_ORDER)
        runFiles{i} = fullfile(outDir, sprintf('task4_sweep_400s_%s.mat', RUN_TAGS{i}));
    end
    summaryFile = fullfile(outDir, 'task4_sweep_400s_summary.mat');
    protectedFile = fullfile(repoRoot, 'results', 'task4', ...
                             'task4_first_diagnostic_400s_alpha1e3.mat');

    dests = [runFiles, {summaryFile}];
    for i = 1:numel(dests)
        % The immutable first diagnostic must never be a destination. Both sides
        % were built from the canonical repoRoot resolved above, so a '..'
        % segment cannot disguise one as the other.
        assert(~strcmpi(dests{i}, protectedFile), ...
            'task4_alpha_sweep:protected', ...
            ['Destination %d resolves to the immutable first diagnostic result. ' ...
             'Refusing.'], i);
        if exist(dests{i}, 'file')
            error('task4_alpha_sweep:exists', ...
                ['ABORT: destination already exists:\n    %s\n' ...
                 'The harness never overwrites, never appends to a foreign file ' ...
                 'and never retries. Move or archive the existing result and ' ...
                 'invoke the sweep again deliberately.'], dests{i});
        end
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    %% ---- PROVENANCE, QUERIED AT EXECUTION TIME --------------------------
    head  = git_head_now(repoRoot);        % never hard-coded
    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
    head_caveat = ['Repository HEAD does not establish the integrity of the ' ...
                   'Task 4 sources: they are untracked. Byte hashes are checked ' ...
                   'externally before and after this execution.'];

    fprintf('=============================================================\n');
    fprintf(' TASK 4 THREE-ALPHA D9 SWEEP - PREDECLARED, EXECUTED ONCE\n');
    fprintf('=============================================================\n');
    fprintf('   Tsim                    %g s\n', TSIM);
    fprintf('   alpha execution order   [%s]  (%s)\n', ...
        num2str(ALPHA_ORDER, '%g '), p_base.t4.alpha_status);
    fprintf('   x0                      r = [%g %g %g] m, v = [%g %g %g] m/s\n', x0(1:3), x0(4:6));
    fprintf('   s_cap %.6f m | r_safe %.6f m | kappa [%.2f %.2f] | Ts %.2f s | N %d\n', ...
        p_base.t4.s_cap, p_base.geom.r_safe, p_base.t4.kappa1, p_base.t4.kappa2, p_base.ctrl.Ts, p_base.mpc.N);
    fprintf('   HEAD at execution time  %s\n', head);
    fprintf('   NOTE  %s\n', head_caveat);
    fprintf('   destinations            %s\n', outDir);
    fprintf('=============================================================\n');

    %% ---- RUN LOOP: fixed order, no retry, no tuning ---------------------
    runs   = [];
    scans  = [];
    ics    = [];
    idents = [];
    for i = 1:numel(ALPHA_ORDER)
        a = ALPHA_ORDER(i);
        fprintf('\n RUN %d/%d   alpha = %.0e\n', i, numel(ALPHA_ORDER), a);

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
            'task4_alpha_sweep:taxonomy', ...
            ['Run %d returned event = ''%s'', which is outside the frozen D9 ' ...
             'taxonomy (NORMAL | GUARD_BREACH | NO_EVENT) and its ' ...
             'NOT_EVALUATED marker.'], i, out.event);
        assert(out.alpha == a, 'task4_alpha_sweep:alpha_echo', ...
            'Run %d was asked for alpha = %g but reports alpha = %g.', i, a, out.alpha);

        fprintf('   run complete in %.1f s   D9 event : %s   eligibility : %s\n', ...
            rt, out.event, out.eligibility);

        % (5) existing independent F5 replay. (6) its source binding to this exact
        % run is established inside F5_HCAP_SCAN and re-checked by TASK4_CLASSIFY.
        scan = f5_hcap_scan(out, p_base);
        fprintf('   independent scan : %s   agree %d   F5 branch %s\n', ...
            scan.independent_event, scan.classification_agree, scan.F5_branch);

        % Per-run evidence is written immediately, so an interruption later in the
        % sweep cannot destroy a completed run. The destination was guarded above
        % and is re-checked here against anything that appeared in the meantime.
        if exist(runFiles{i}, 'file')
            error('task4_alpha_sweep:exists_late', ...
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
                      'ic', ic, 'git_head_at_execution', head, ...
                      'head_caveat', head_caveat, 'stamp', stamp, ...
                      'harness', 'task4_alpha_sweep');
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

    % ---- EXECUTION-STATUS metadata, kept strictly beside the science --------
    % This describes the state of the ARTIFACT, never the scientific outcome.
    % PASS / INCONCLUSIVE / FAIL and F1-F5 live in `classifier` and are untouched.
    % A NOT_APPLICABLE diagnostic is not an integrity FAILURE: the check could not
    % run, it did not fail, so the reason is recorded in cross_run.status instead.
    if ~xrun.applicable
        artifact_status = 'FINALIZED_XRUN_NOT_APPLICABLE';
    elseif xrun.within_tol
        artifact_status = 'COMPLETE';
    else
        artifact_status = 'INTEGRITY_FAILURE';
    end
    artifact_status_note = ['Execution-status metadata for this artifact. It is ' ...
        'independent of the scientific classifier outcome, which is in the ' ...
        '`classifier` variable.'];

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
        save(runFiles{i}, 'classifier', 'cross_run', 'artifact_status', ...
                          'artifact_status_note', '-append');
    end
    fprintf('\n finalized all %d run files: classifier + cross-run diagnostic, status %s\n', ...
        numel(runFiles), artifact_status);

    %% ---- SUMMARY OUTPUT, WRITTEN LAST -----------------------------------
    summary = struct( ...
        'Tsim',                 TSIM, ...
        'alpha_order',          ALPHA_ORDER, ...
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
        'artifact_status',      artifact_status, ...
        'xrun_tol',             XRUN_TOL, ...
        'run_files',            {runFiles}, ...
        'git_head_at_execution', head, ...
        'head_caveat',          head_caveat, ...
        'stamp',                stamp, ...
        'harness',              'task4_alpha_sweep');

    if exist(summaryFile, 'file')
        error('task4_alpha_sweep:exists_late', ...
            'ABORT: summary destination appeared during the sweep: %s', summaryFile);
    end
    save(summaryFile, 'summary', 'p_base', 'artifact_status', ...
                      'artifact_status_note', '-v7.3');
    fprintf(' sweep summary saved to %s   [%s]\n', summaryFile, artifact_status);

    % The integrity diagnostic is reported and the evidence is on disk BEFORE the
    % harness stops on it, so an unexpected difference can be investigated rather
    % than re-run. It is not a scientific outcome and never becomes one.
    if xrun.applicable && ~xrun.within_tol
        error('task4_alpha_sweep:cross_run', ...
            ['STOP: pre-event cross-run differences exceed the declared software ' ...
             'integrity tolerance (max |dX| = %.6e, max |dU| = %.6e, tol = %.0e). ' ...
             'All evidence has been saved. Investigate the implementation; do not ' ...
             'tune around this and do not rerun as though nothing happened.'], ...
            xrun.max_dX, xrun.max_dU, XRUN_TOL);
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

function res = baseline_tuning(opt)
% BASELINE_TUNING  The frozen APF development search (protocol Sec. 4, 5, 6).
%   res = baseline_tuning(opt)
%
%   IT CHOOSES NOTHING. The lattice, the enumeration order, the refinement
%   order, the budget, the eligibility precondition, the T1 -> T7 total order
%   and the stopping rule are all frozen elsewhere and are called from here:
%       BASELINE_LATTICE / _VALUE / _PROPOSE   search space and proposals
%       BASELINE_SCENARIOS                     D1-D5
%       SIMULATE_BASELINE                      the closed loop
%       BASELINE_METRICS                       the per-scenario T inputs
%       BASELINE_SELECTION / BASELINE_ORDER_BETTER   the total order
%       APF_R1_MARGIN                          the DIAGNOSTIC-ONLY R1 margin
%
%   REQUIRED OPTIONS - none of these has a default, on purpose:
%       expected_aggregate        the ONE frozen baseline-support aggregate
%                                 SHA-256 from Source-Freeze Record B
%       verification_gate         path to the saved V1-V11 gate .mat
%       verification_gate_sha256  its frozen SHA-256
%
%   WHY THE AGGREGATE IS SUPPLIED AND NOT CHOSEN HERE. The listing form that
%   coreutils sha256sum emits differs between builds (two-space text form versus
%   " *" binary form), so the code computes BOTH and this harness refuses to
%   pick one. Record B freezes exactly one value from the reference procedure;
%   that supplied value is asserted against the two independently computed forms
%   and is what every binding and artifact then carries. The code never promotes
%   one of its own computed forms to "canonical".
%
%   V1-V11 MUST HAVE PASSED (protocol Sec. 14.1). Scientific tuning starts only
%   after ONE COMPLETE PASS of V1..V11, so the gate file is hash-verified,
%   loaded, and required to report pass == true against the SAME protocol SHA
%   and the SAME frozen aggregate. Its hash is stored in the binding, so the
%   tuning record names the gate it was authorised by.
%
%   BUDGET (Sec. 4.4)
%       coarse       108 candidates x 5 scenarios          = 540 runs (exact)
%       refinement   <= 3 rounds x 8 proposals x 5 scenarios <= 120 runs
%       TOTAL                                              <= 660 runs
%   The total is a BOUND, not an exact count: out-of-bracket proposals are
%   rejected and already-evaluated lattice points are not re-run. There is NO
%   order-dependent truncation - every in-bracket unseen proposal in every round
%   is evaluated.
%
%   NUMERICAL ELIGIBILITY IS A PRECONDITION, NOT A RANKING KEY (Sec. 6.1).
%   A candidate is eligible only if all five runs complete the full horizon with
%   no NaN/Inf and no integrator failure. Ineligible candidates stay in the
%   search log but do not enter scientific ranking. Safety or proximity failure
%   NEVER removes an otherwise eligible candidate. If ZERO eligible candidates
%   exist the search STOPS and reports a development/integrity failure; it does
%   NOT retune using the evaluation IC.
%
%   ============ ATOMICITY, AND WHY VISIBILITY IS RESTRICTED BY ROUND ==========
%
%   CANDIDATE ATOMIC. A candidate becomes checkpoint-complete only after ALL
%   FIVE D1-D5 runs have finished AND its full frozen metric vector exists. A
%   partially evaluated candidate is never written to the checkpoint: it is
%   discarded and rerun from the first scenario. There is no within-candidate
%   resume, so no candidate can be ranked on an incomplete scenario set and the
%   T1/T3 counts can never be computed over a partial base.
%
%   ROUND ATOMIC, ENFORCED BY ROUND-RESTRICTED VISIBILITY. Every incumbent in
%   this file is computed by BEST_OF_UPTO(st, r), which sees ONLY candidates
%   whose round index is <= r. A naive global "best over everything evaluated so
%   far" is WRONG on resume: after an interruption the checkpoint can already
%   hold some candidates of an incomplete round, and a global best would let
%   those retroactively move the post-coarse incumbent - which then changes the
%   proposal set of the very round they belong to. Restricting visibility by
%   round makes the reconstruction identical to the uninterrupted execution.
%
%   ROUND STATE IS FROZEN AT OPEN. The first time a round is opened, its
%   incumbent_before, shift, proposal_levels, proposal_ids and rejected list are
%   computed once and checkpointed. On resume an INCOMPLETE round is replayed
%   from those STORED values EXACTLY: nothing is recomputed from the current
%   candidate set, and only the missing checkpoint-complete IDs from the stored
%   proposal set are executed.
%
%   ROUND CLOSURE IS ONE STATE TRANSITION. incumbent_after, improved,
%   decided_at_level, the stopping decision and complete = true are written
%   TOGETHER in a single checkpoint write. Writing complete = true first and the
%   decision afterwards would leave a window in which a crash produces a round
%   that claims to be finished but carries no decision.
%
%   A COMPLETE ROUND IS REPLAYED, NOT RECOMPUTED. Its stored incumbent_after and
%   stored improved/stopped decision are used directly. Calling a global best_of
%   there could see candidates from a later incomplete round and silently move
%   an incumbent the frozen search had already fixed.
%
%   THE CHECKPOINT IS WRITTEN ATOMICALLY: a temporary file in the same directory
%   is written and then moved over the target, so an interruption cannot leave a
%   truncated .mat. This is execution resilience only; it changes no scientific
%   semantics.
%
%   THE CHECKPOINT IS BOUND TO THE CONTRACT. It stores the protocol SHA-256, the
%   SUPPLIED frozen baseline aggregate, the verification-gate SHA-256 and a hash
%   of the lattice definition. If any of them differs on resume the run ABORTS:
%   a checkpoint may only ever save time, never change what is searched.
%
%   THE EVALUATION IC IS NEVER USED HERE. allow_eval_x0 is never passed, and
%   BASELINE_SCENARIOS plus SIMULATE_BASELINE each refuse it independently.
%
%   Optional: out_dir (default <repo>/results/task4/baselines_tuning),
%   resume (true), dry_run (false), verbose (true).

    assert(nargin >= 1 && isstruct(opt), 'baseline_tuning:opt', ...
        'An options struct is required.');
    req = {'expected_aggregate', 'verification_gate', 'verification_gate_sha256'};
    for i = 1:numel(req)
        assert(isfield(opt, req{i}) && ~isempty(opt.(req{i})), ...
            'baseline_tuning:required_option', ...
            ['opt.%s is REQUIRED and has no default. The frozen ' ...
             'baseline-support aggregate and the passed V1-V11 gate are ' ...
             'external identities; this harness refuses to invent either.'], req{i});
    end
    if ~isfield(opt, 'resume'),  opt.resume  = true;  end
    if ~isfield(opt, 'dry_run'), opt.dry_run = false; end
    if ~isfield(opt, 'verbose'), opt.verbose = true;  end

    thisDir  = fileparts(mfilename('fullpath'));            % src/baselines/search
    repoRoot = fileparts(fileparts(fileparts(thisDir)));    % <repo>
    w = what(repoRoot);  if ~isempty(w), repoRoot = w(1).path; end
    if ~isfield(opt, 'out_dir') || isempty(opt.out_dir)
        opt.out_dir = fullfile(repoRoot, 'results', 'task4', 'baselines_tuning');
    end

    p   = baseline_config();
    lat = baseline_lattice(p);
    S   = baseline_scenarios(p);
    nS  = numel(S);

    % ---- tracked production worktree must match frozen HEAD ----------------
    % Runs BEFORE any scientific development run. Complements the HEAD:src
    % tree-object identity: that proves nothing under src/ was COMMITTED, this
    % proves nothing tracked under src/ was EDITED. Untracked src/baselines/**
    % is ignored, as protocol Sec. 15.3 requires it to be.
    trackedSrc = baseline_tracked_src_gate(repoRoot);

    % ---- contract binding: protocol -----------------------------------------
    protoSha = baseline_sha256(fullfile(repoRoot, p.bl.protocol_file));
    assert(strcmpi(protoSha, p.bl.protocol_sha256), 'baseline_tuning:protocol_sha', ...
        ['The protocol record hashes to %s, not the frozen %s. Refusing to ' ...
         'search against a changed contract.'], protoSha, p.bl.protocol_sha256);

    % ---- contract binding: the SUPPLIED frozen baseline aggregate -----------
    expAgg = lower(char(opt.expected_aggregate));
    man    = baseline_manifest();
    if strcmpi(expAgg, man.aggregate_sha256)
        aggForm = 'text (two-space separator)';
    elseif strcmpi(expAgg, man.aggregate_sha256_binary)
        aggForm = 'binary (space-asterisk separator)';
    else
        error('baseline_tuning:aggregate', ...
            ['ABORT: the frozen baseline-support aggregate\n    %s\nmatches ' ...
             'NEITHER independently computed listing form:\n    %s  (text)\n' ...
             '    %s  (binary)\nThe source under src/baselines/** is not the ' ...
             'source Record B froze.'], expAgg, man.aggregate_sha256, ...
            man.aggregate_sha256_binary);
    end

    % ---- contract binding: the V1-V11 gate ----------------------------------
    gateSha = baseline_sha256(opt.verification_gate);
    assert(strcmpi(gateSha, char(opt.verification_gate_sha256)), ...
        'baseline_tuning:gate_sha', ...
        ['ABORT: the verification gate hashes to\n    %s\nbut the frozen ' ...
         'identity supplied is\n    %s'], gateSha, lower(char(opt.verification_gate_sha256)));
    G = load(opt.verification_gate, 'gate');
    assert(isfield(G, 'gate'), 'baseline_tuning:gate_shape', ...
        'The verification gate file carries no `gate` variable.');
    assert(islogical(G.gate.pass) || isnumeric(G.gate.pass), ...
        'baseline_tuning:gate_pass_class', 'gate.pass is not a logical.');
    assert(G.gate.pass == true, 'baseline_tuning:gate_failed', ...
        ['ABORT: the V1-V11 verification gate did NOT pass. Scientific tuning ' ...
         'starts only after ONE COMPLETE PASS of V1..V11 (protocol Sec. 14.1).']);
    assert(strcmpi(G.gate.protocol_sha, protoSha), 'baseline_tuning:gate_protocol', ...
        ['ABORT: the verification gate was produced under protocol SHA %s, not ' ...
         'the frozen %s.'], G.gate.protocol_sha, protoSha);
    assert(strcmpi(G.gate.baseline_aggregate_sha, expAgg), ...
        'baseline_tuning:gate_aggregate', ...
        ['ABORT: the verification gate was produced against baseline aggregate ' ...
         '%s, not the frozen %s supplied here. The gate does not authorise ' ...
         'this source set.'], G.gate.baseline_aggregate_sha, expAgg);

    binding = struct( ...
        'protocol_sha256',         protoSha, ...
        'aggregate_sha256',        expAgg, ...        % the SUPPLIED frozen value
        'aggregate_listing_form',  aggForm, ...
        'aggregate_text_form',     man.aggregate_sha256, ...
        'aggregate_binary_form',   man.aggregate_sha256_binary, ...
        'verification_gate',       opt.verification_gate, ...
        'verification_gate_sha256', gateSha, ...
        'lattice_sha256',          lattice_hash(lat), ...
        'tracked_src_gate',        trackedSrc, ...
        'n_scenarios',             nS, ...
        'Tsim',                    p.bl.T_eval);

    if ~exist(opt.out_dir, 'dir'), mkdir(opt.out_dir); end
    ckptFile   = fullfile(opt.out_dir, 'baseline_tuning_checkpoint.mat');
    recordFile = fullfile(opt.out_dir, 'baseline_tuning_record.mat');

    % ---- resume or start clean ---------------------------------------------
    st = fresh_state(binding);
    if opt.resume && exist(ckptFile, 'file') == 2
        loaded = load(ckptFile, 'state');
        st = loaded.state;
        assert(isequal(st.binding, binding), 'baseline_tuning:binding', ...
            ['The checkpoint at %s was written under a different contract ' ...
             '(protocol / aggregate / verification gate / lattice). A ' ...
             'checkpoint may only save time, never change what is searched. ' ...
             'Move it aside and restart the search deliberately.'], ckptFile);
        if opt.verbose
            fprintf(' resuming: %d checkpoint-complete candidates, coarse_complete = %d, %d closed round(s)\n', ...
                numel(st.cands), st.coarse_complete, sum([st.rounds.complete]));
        end
    end

    % ---- capture-point tables, built once per distinct target identity -----
    tables = cell(1, nS);
    if ~opt.dry_run
        for j = 1:nS
            tables{j} = table_for(S, j, tables, p);
        end
    end

    if opt.verbose
        fprintf('=============================================================\n');
        fprintf(' APF DEVELOPMENT SEARCH - frozen lattice, frozen order\n');
        fprintf('   coarse candidates   %d   x %d scenarios = %d runs\n', ...
            lat.n_coarse, nS, lat.n_coarse*nS);
        fprintf('   refinement          <= %d rounds, shifts [%s]\n', ...
            lat.max_rounds, num2str(lat.shifts, '%d '));
        fprintf('   horizon             %g s   (%d control steps)\n', ...
            p.bl.T_eval, p.bl.geom.K);
        fprintf('   protocol            %s\n', protoSha);
        fprintf('   frozen aggregate    %s   [%s]\n', expAgg, aggForm);
        fprintf('   V1-V11 gate         %s   PASS\n', gateSha);
        fprintf('   tracked src worktree matches frozen HEAD\n');
        fprintf('   checkpoint          %s\n', ckptFile);
        fprintf('=============================================================\n');
    end

    if opt.dry_run
        res = struct('dry_run', true, 'lattice', lat, 'scenarios', {{S.id}}, ...
            'binding', binding, 'planned_coarse_runs', lat.n_coarse*nS, ...
            'note', 'Enumeration only. No simulation was executed.');
        return
    end

    % ---- a FINALIZED tuning record is never overwritten --------------------
    % Checked here, after the dry-run inspection path and BEFORE the first
    % scientific development run. The CHECKPOINT file is deliberately NOT
    % guarded: it is the resume mechanism and stays governed by the frozen
    % resume semantics. Only the finalized record is protected, because
    % overwriting it would destroy the hash-frozen search the evaluation gain
    % set is drawn from.
    assert(exist(recordFile, 'file') ~= 2, 'baseline_tuning:record_exists', ...
        ['ABORT: a finalized tuning record already exists:\n    %s\n' ...
         'It is NOT overwritten. If a genuinely new search is required after a ' ...
         'source change or a new aggregate, point opt.out_dir at a clean ' ...
         'tuning namespace; do not destroy the existing finalized record.'], ...
        recordFile);

    % ================= COARSE PHASE (round 0) ===============================
    if ~st.coarse_complete
        for i = 1:lat.n_coarse
            id = i;                                 % IDs 1..108, frozen order
            if is_complete(st, id), continue, end
            rec = evaluate_candidate(p, S, tables, lat, lat.coarse(i, :), id, 0, opt.verbose);
            st  = commit_candidate(st, rec, ckptFile);
        end
        % COARSE CLOSURE, ONE TRANSITION. The post-coarse incumbent is computed
        % from COARSE candidates only (round <= 0) and is FROZEN into the state.
        % It is never recomputed afterwards, so a later partial refinement
        % candidate cannot alter it on resume.
        if any([st.cands.eligible])
            st.coarse_incumbent = best_of_upto(st, 0);
        else
            st.coarse_incumbent = [];
        end
        st.coarse_complete = true;
        st = save_state(st, ckptFile);
    end

    % ---- eligibility gate ---------------------------------------------------
    if isempty(st.coarse_incumbent)
        st.outcome = 'DEVELOPMENT_INTEGRITY_FAILURE';
        st.outcome_note = ['ZERO numerically eligible candidates in the coarse ' ...
            'grid. The search STOPS before final evaluation. Retuning using the ' ...
            'evaluation IC is forbidden and was not attempted.'];
        res = finish(st, p, lat, S, man, recordFile, opt.verbose);
        return
    end

    % ================= REFINEMENT ROUNDS ====================================
    for r = 1:lat.max_rounds
        ridx = find_round(st, r);

        % ---- an already CLOSED round is REPLAYED from its stored decision ---
        if ~isempty(ridx) && st.rounds(ridx).complete
            if ~st.rounds(ridx).improved
                st.stop_round  = r;
                st.stop_reason = sprintf(['No newly evaluated candidate ' ...
                    'strictly improved the incumbent under the COMPLETE ' ...
                    'T1 -> T7 order in round %d. STOP. (Replayed from the ' ...
                    'stored round decision; no incumbent was recomputed.)'], r);
                break
            end
            continue                                % stored decision: continue
        end

        % ---- open the round ONCE; on resume reuse the STORED plan exactly ---
        if isempty(ridx)
            before = incumbent_before_round(st, r);
            shift  = lat.shifts(r);
            seen   = levels_upto(st, r-1);
            [prop, rej] = baseline_lattice_propose(lat, before.levels, shift, seen);
            nextId = next_id(st);
            ids    = nextId + (0:size(prop, 1) - 1);
            st     = open_round(st, r, shift, before, prop, ids, rej, ckptFile);
            ridx   = find_round(st, r);
        end
        R = st.rounds(ridx);                        % the STORED plan, verbatim

        % ---- execute only the missing IDs of the STORED proposal set --------
        for q = 1:numel(R.proposal_ids)
            if is_complete(st, R.proposal_ids(q)), continue, end
            rec = evaluate_candidate(p, S, tables, lat, R.proposal_levels(q, :), ...
                                     R.proposal_ids(q), r, opt.verbose);
            st  = commit_candidate(st, rec, ckptFile);
        end

        % ---- ROUND CLOSURE: decision + complete in ONE state transition -----
        after = best_of_upto(st, r);
        [improved, level] = baseline_order_better(after, R.incumbent_before);
        st.rounds(ridx).incumbent_after  = after;
        st.rounds(ridx).improved         = improved;
        st.rounds(ridx).decided_at_level = level;
        st.rounds(ridx).complete         = true;
        st = save_state(st, ckptFile);              % single write, all of it

        if opt.verbose
            fprintf(' round %d (shift %d): %d proposals, %d rejected -> incumbent %s\n', ...
                r, R.shift, numel(R.proposal_ids), numel(R.rejected), ...
                tern(improved, sprintf('MOVED to id %d at T%d', after.id, level), 'unchanged'));
        end

        if ~improved
            st.stop_round  = r;
            st.stop_reason = sprintf(['No newly evaluated candidate strictly ' ...
                'improved the incumbent under the COMPLETE T1 -> T7 order in ' ...
                'round %d. STOP.'], r);
            break
        end
    end

    if isempty(st.stop_reason)
        st.stop_reason = sprintf('The maximum of %d refinement rounds was reached.', ...
            lat.max_rounds);
    end
    st.outcome = 'SEARCH_COMPLETE';
    res = finish(st, p, lat, S, man, recordFile, opt.verbose);
end

% =====================================================================
function b = incumbent_before_round(st, r)
% The incumbent a round starts from: the FROZEN post-coarse incumbent for
% round 1, and the STORED incumbent_after of the previous round thereafter.
% Never a fresh global best - that is the whole point of round atomicity.
    if r == 1
        b = st.coarse_incumbent;
    else
        j = find_round(st, r-1);
        assert(~isempty(j) && st.rounds(j).complete, 'baseline_tuning:round_order', ...
            'Round %d was opened before round %d was closed.', r, r-1);
        b = st.rounds(j).incumbent_after;
    end
    assert(~isempty(b), 'baseline_tuning:no_incumbent', ...
        'Round %d has no incumbent to refine from.', r);
end

% =====================================================================
function b = best_of_upto(st, r)
% The best candidate over the numerically ELIGIBLE candidates of rounds 0..r.
% Visibility is restricted so that a partially completed later round can never
% influence an earlier round's incumbent on resume.
    vis = st.cands([st.cands.eligible] & [st.cands.round] <= r);
    assert(~isempty(vis), 'baseline_tuning:no_eligible', ...
        'best_of_upto(%d) found no numerically eligible candidate.', r);
    bi = 1;
    for i = 2:numel(vis)
        if baseline_order_better(vis(i).vector, vis(bi).vector)
            bi = i;
        end
    end
    b = struct('id', vis(bi).id, 'levels', vis(bi).levels, ...
               'theta', vis(bi).theta, 'vector', vis(bi).vector, ...
               'order', vis(bi).order, 'round', vis(bi).round);
end

% =====================================================================
function L = levels_upto(st, r)
% Lattice points already evaluated in rounds 0..r, used for de-duplication.
% Restricted by round for the same reason best_of_upto is.
    vis = st.cands([st.cands.round] <= r);
    if isempty(vis)
        L = zeros(0, 4);
    else
        L = reshape([vis.levels], 4, []).';
    end
end

% =====================================================================
function n = next_id(st)
    if isempty(st.cands), n = 1; else, n = max([st.cands.id]) + 1; end
end

% =====================================================================
function j = find_round(st, r)
    if isempty(st.rounds), j = []; else, j = find([st.rounds.index] == r, 1); end
end

% =====================================================================
function rec = evaluate_candidate(p, S, tables, lat, levels, id, roundIdx, verbose)
% ONE CANDIDATE, ALL FIVE SCENARIOS, ATOMICALLY. The returned record is only
% ever handed to COMMIT_CANDIDATE after every scenario and the full metric
% vector exist; a failure part-way through this function leaves nothing behind.
%
% AN INTEGRATOR FAILURE DOES NOT ABORT THE SEARCH. SIMULATE_BASELINE returns a
% gracefully terminated run marked numerically ineligible, the remaining
% scenarios still execute, and the candidate is logged but not ranked.
    theta = baseline_lattice_value(lat, levels);
    gains = apf_gains(theta, p);
    r1    = apf_r1_margin(gains, p);               % DIAGNOSTIC ONLY

    nS = numel(S);
    mCell = cell(1, nS);
    eligible = true;
    perScenario = struct('id', {}, 'eligible', {}, 'summary', {});

    t0 = tic;
    for j = 1:nS
        run = simulate_baseline(p, struct( ...
            'method',    'apf', ...
            'x0',        S(j).x0, ...
            'Tsim',      p.bl.T_eval, ...
            'gains',     gains, ...
            'r1',        r1, ...
            'truthIC',   S(j).targetIC, ...
            'previewIC', S(j).previewIC, ...
            'tables',    tables{j}));
        eligible = eligible && run.numerically_eligible;

        if run.numerically_eligible
            m = baseline_metrics(run, p);
        else
            m = [];
        end
        mCell{j} = pack_metric(m);
        perScenario(j) = struct('id', S(j).id, 'eligible', run.numerically_eligible, ...
            'summary', scenario_summary(run, m));
    end
    dt = toc(t0);
    mAll = [mCell{:}];                              % 1xnS struct array

    rec.id       = id;
    rec.levels   = levels(:).';
    rec.theta    = theta;
    rec.gains    = struct('k_a', gains.k_a, 'k_d', gains.k_d, 'k_r', gains.k_r, ...
                          'in_bracket', gains.in_bracket);
    rec.round    = roundIdx;
    rec.eligible = eligible;
    rec.runtime_s = dt;
    rec.per_scenario = perScenario;
    rec.r1 = struct('margin', r1.r1_margin, 'M', r1.M, 'M_plus', r1.M_plus, ...
                    'M_minus', r1.M_minus, 'k_a', r1.k_a, ...
                    'antipodal_dominates', r1.antipodal_dominates, ...
                    'stationary_locations', r1.stationary_locations, ...
                    'tangential_flag', r1.tangential_flag);

    if eligible
        sel = baseline_selection(mAll, id);
        rec.order  = sel;
        rec.vector = sel.vector;
    else
        % Kept in the log, excluded from ranking. NaN records "not ranked",
        % never "ranked and worst".
        rec.order  = [];
        rec.vector = nan(1, 7);
    end

    if verbose
        fprintf('   id %4d  round %d  levels [%2d %2d %2d %2d]  %s  %.1f s\n', ...
            id, roundIdx, levels(1), levels(2), levels(3), levels(4), ...
            tern(eligible, sprintf('T = [%g %.3g %g %.3g %.3g %.3g %d]', rec.vector), ...
                 'INELIGIBLE (logged, not ranked)'), dt);
    end
end

% =====================================================================
function m = pack_metric(m0)
% The subset BASELINE_SELECTION consumes, plus the fields it logs. An ineligible
% candidate contributes a struct of NaNs that the selection never sees.
    f = {'T1_no_violation', 'T2_deficit', 'T3_proximity', 'T4_shortfall', ...
         'T5_dv_Isel', 'T6_clip_Isel', 'I_sel_count', 'empty_selection', ...
         't_viol', 'p_safe', 'K_safe_count'};
    if isempty(m0)
        for i = 1:numel(f), m.(f{i}) = NaN; end
        m.T1_no_violation = false;
        m.T3_proximity    = false;
        m.empty_selection = false;
        return
    end
    for i = 1:numel(f), m.(f{i}) = m0.(f{i}); end
end

% =====================================================================
function s = scenario_summary(run, m)
    if isempty(m)
        s = struct('completed', run.completed, 'K', run.K, ...
            'numerical_failure', run.numerical_failure, ...
            'failure_k', run.failure_k, ...
            'failure_reason', run.failure_reason);
        return
    end
    s = struct( ...
        'completed',            run.completed, ...
        'K',                    run.K, ...
        'no_observed_body_violation', m.no_observed_body_violation, ...
        'min_h_body',           m.min_h_body, ...
        'min_clearance',        m.min_clearance, ...
        't_viol',               m.t_viol, ...
        'p_safe',               m.p_safe, ...
        'kstar',                m.kstar, ...
        't_kstar',              m.t_kstar, ...
        'proximity_achieved',   m.proximity_achieved, ...
        'rho_dot_truth_kstar',  m.rho_dot_truth_kstar, ...
        'rho_truth_final',      m.rho_truth_final, ...
        'I_sel_case',           m.I_sel_case, ...
        'I_sel_count',          m.I_sel_count, ...
        'empty_selection',      m.empty_selection, ...
        'DeltaV_Isel',          m.DeltaV_Isel, ...
        'DeltaV_full',          m.DeltaV_full, ...
        'clip_fraction_Isel',   m.clip_fraction_Isel, ...
        'clip_fraction_full',   m.clip_fraction_full, ...
        'max_utilisation',      m.utilisation.max_ratio);
end

% =====================================================================
function st = fresh_state(binding)
    st.binding          = binding;
    st.cands            = struct('id', {}, 'levels', {}, 'theta', {}, 'gains', {}, ...
                                 'round', {}, 'eligible', {}, 'runtime_s', {}, ...
                                 'per_scenario', {}, 'r1', {}, 'order', {}, 'vector', {});
    st.rounds           = struct('index', {}, 'shift', {}, 'incumbent_before', {}, ...
                                 'proposal_levels', {}, 'proposal_ids', {}, ...
                                 'rejected', {}, 'complete', {}, ...
                                 'incumbent_after', {}, 'improved', {}, ...
                                 'decided_at_level', {});
    st.coarse_complete  = false;
    st.coarse_incumbent = [];
    st.stop_round       = [];
    st.stop_reason      = '';
    st.outcome          = 'IN_PROGRESS';
    st.outcome_note     = '';
end

% =====================================================================
function tf = is_complete(st, id)
    tf = ~isempty(st.cands) && any([st.cands.id] == id);
end

% =====================================================================
function st = commit_candidate(st, rec, ckptFile)
% ATOMIC WRITE POINT. Reached only after all five scenarios and the full metric
% vector exist, so the checkpoint can never hold a partial candidate.
    st.cands(end+1) = rec;
    st = save_state(st, ckptFile);
end

% =====================================================================
function st = open_round(st, r, shift, before, prop, ids, rej, ckptFile)
% Called ONLY when the round does not exist yet. Its plan is frozen here and is
% replayed verbatim on every later resume.
    entry = struct('index', r, 'shift', shift, 'incumbent_before', before, ...
        'proposal_levels', prop, 'proposal_ids', ids, 'rejected', rej, ...
        'complete', false, 'incumbent_after', [], 'improved', [], ...
        'decided_at_level', []);
    st.rounds(end+1) = entry;
    st = save_state(st, ckptFile);
end

% =====================================================================
function st = save_state(st, ckptFile)
% The single place the checkpoint is written, and it is written ATOMICALLY: the
% state goes to a temporary file in the same directory and is then moved over
% the target. An interruption therefore leaves either the previous complete
% checkpoint or the new complete one, never a truncated .mat.
    state = st;
    tmp = [ckptFile '.tmp'];
    save(tmp, 'state', '-v7.3');
    [ok, msg] = movefile(tmp, ckptFile, 'f');
    assert(ok, 'baseline_tuning:checkpoint_replace', ...
        'Could not replace the checkpoint %s: %s', ckptFile, msg);
end

% =====================================================================
function tbl = table_for(S, j, tables, p)
% Reuse an already-built table set whenever an earlier scenario declared exactly
% the same truth AND preview target identities.
    for q = 1:j-1
        if ~isempty(tables{q}) ...
                && isequal(S(q).targetIC.q(:),  S(j).targetIC.q(:)) ...
                && isequal(S(q).targetIC.w(:),  S(j).targetIC.w(:)) ...
                && isequal(S(q).targetIC.I,     S(j).targetIC.I) ...
                && isequal(S(q).previewIC.q(:), S(j).previewIC.q(:)) ...
                && isequal(S(q).previewIC.w(:), S(j).previewIC.w(:)) ...
                && isequal(S(q).previewIC.I,    S(j).previewIC.I)
            tbl = tables{q};
            return
        end
    end
    tbl = baseline_capture_tables(p, S(j).targetIC, S(j).previewIC, p.bl.T_eval);
end

% =====================================================================
function h = lattice_hash(lat)
% A deterministic hash of the lattice DEFINITION, so a resumed search cannot
% silently continue against a changed search space.
    txt = '';
    for i = 1:numel(lat.axes)
        a = lat.axes(i);
        txt = [txt sprintf('%s|%.17g|%.17g|%d|%s\n', a.name, a.v_min, a.v_max, ...
                           a.L, mat2str(a.coarse_levels))];                 %#ok<AGROW>
    end
    txt = [txt sprintf('coarse|%s\n', mat2str(lat.coarse))];
    txt = [txt sprintf('shifts|%s|rounds|%d\n', mat2str(lat.shifts), lat.max_rounds)];
    h = baseline_sha256(uint8(txt), false);
end

% =====================================================================
function res = finish(st, p, lat, S, man, recordFile, verbose)
    res.binding      = st.binding;
    res.outcome      = st.outcome;
    res.outcome_note = st.outcome_note;
    res.stop_round   = st.stop_round;
    res.stop_reason  = st.stop_reason;
    res.candidates   = st.cands;
    res.rounds       = st.rounds;
    res.coarse_incumbent = st.coarse_incumbent;
    res.n_candidates = numel(st.cands);
    res.n_runs       = numel(st.cands) * numel(S);
    res.n_scenarios  = numel(S);
    res.Tsim         = p.bl.T_eval;
    res.scenarios    = {S.id};
    res.lattice      = lat;
    res.manifest     = rmfield(man, {'listing_text', 'listing_text_binary'});
    res.s_cap_wording = p.bl.s_cap_wording;
    res.n_ineligible = sum(~[st.cands.eligible]);

    assert(res.n_runs <= 660, 'baseline_tuning:budget', ...
        'The search executed %d full-horizon runs, above the frozen bound of 660.', ...
        res.n_runs);

    % The SELECTED WINNER is the incumbent of the LAST CLOSED round, or the
    % frozen post-coarse incumbent when no refinement round closed. It is read
    % from the stored round decisions, never recomputed from the candidate set.
    res.winner = st.coarse_incumbent;
    if ~isempty(st.rounds)
        closed = st.rounds([st.rounds.complete]);
        if ~isempty(closed)
            res.winner = closed(end).incumbent_after;
        end
    end

    if ~isempty(res.winner)
        res.null_result_wording = ['The selected primary APF gain set is the ' ...
            'ordering-optimal member of the frozen family on the frozen ' ...
            'development set within the predeclared budget. If it does not ' ...
            'achieve proximity on all five development scenarios, that is ' ...
            'reported as failure of the selected literature-grounded APF ' ...
            'family to achieve proximity on the frozen development set within ' ...
            'the predeclared tuning/search budget, together with the achieved ' ...
            'T1, T3 and T4 values. No broader claim about artificial potential ' ...
            'fields is licensed, no bracket is widened, and no retuning against ' ...
            'the evaluation scenario occurs.'];
    else
        res.null_result_wording = '';
    end

    res.stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');    %#ok<TNOW1,DATST>
    save(recordFile, 'res', '-v7.3');
    if verbose
        fprintf('\n search record saved to %s\n', recordFile);
        if ~isempty(res.winner)
            fprintf(' WINNER  id %d (round %d)  levels [%s]  T = %s\n', ...
                res.winner.id, res.winner.round, num2str(res.winner.levels, '%d '), ...
                mat2str(res.winner.vector, 6));
        else
            fprintf(2, ' NO numerically eligible candidate: %s\n', res.outcome_note);
        end
        if res.n_ineligible > 0
            fprintf(' %d candidate(s) logged but NOT ranked (numerically ineligible)\n', ...
                res.n_ineligible);
        end
    end
end

% =====================================================================
function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

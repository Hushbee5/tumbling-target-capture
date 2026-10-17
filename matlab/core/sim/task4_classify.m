function cls = task4_classify(runs, scans, p)
% TASK4_CLASSIFY  Ordered F1-F5 outcome classifier for the T4-D9 alpha sweep.
%   cls = task4_classify(runs, scans, p) applies the frozen ordered rule of
%   notes/task4_freeze_record.md Sec. 8.6 to a set of runs, one per alpha.
%
%     runs   1xA struct array of SIMULATE_TASK4 outputs, one per alpha
%     scans  1xA struct array of F5_HCAP_SCAN outputs, aligned with runs
%
%   ORDERED RULE
%     Step 1  FAIL / D9 REOPEN if any of F1-F5 holds
%     Step 2  PASS         if all alpha produce NORMAL   and no F1-F5
%     Step 3  INCONCLUSIVE if all alpha produce NO_EVENT and no F1-F5
%
%     F1  qualitative classification differs across alpha
%     F2  any GUARD_BREACH event
%     F3  any QP infeasibility while h_cap is still active
%     F4  h_body < 0 at any sampled point
%     F5  sampled h_cap < 0 while h_cap is enforced, OR detector / post-hoc scan
%         disagreement (supplied by F5_HCAP_SCAN, an independent code path)
%
%   Per-trigger meaning, kept distinct because the triggers implicate different
%   parts of the system:
%     F1 -> detector alpha-sensitivity
%     F2 -> sampled guard / envelope failure
%     F3 -> QP / input-feasibility failure
%     F4 -> physical body-safety failure
%     F5 -> EITHER a sampled guard violation OR a detector / post-hoc software
%           consistency defect, depending on which branch fired
%
%   This function CLASSIFIES; it does not run the sweep, choose alpha, or select
%   a horizon. If the outcome is INCONCLUSIVE the horizon must not be extended
%   iteratively until a handoff occurs; horizon selection is a separate,
%   currently unfrozen design decision.
%
%   NO sampled-data or intersample invariance theorem is claimed by any outcome.

    A = numel(runs);
    assert(numel(scans) == A, 'task4_classify:pair', ...
        'Got %d runs but %d scans; they must be aligned.', A, numel(scans));

    % ---- SYNTHETIC runs are refused FIRST, ahead of every other check: a
    % synthetic unit-path fixture is never evidence, whatever shape the sweep has.
    for i = 1:A
        assert(~(isfield(runs(i),'synthetic') && runs(i).synthetic), ...
            'task4_classify:synthetic', ...
            ['Run %d is a SYNTHETIC inadmissible-IC fixture and cannot be ' ...
             'classified. Synthetic fixtures exercise code paths; they are ' ...
             'never evidence.'], i);
    end

    % ---- SWEEP WELL-FORMEDNESS. The frozen classifier is defined for the
    % predeclared three-alpha sweep and for nothing else. A malformed sweep must
    % never be able to emit PASS or INCONCLUSIVE, so these are hard errors rather
    % than outcomes.
    want = sort(p.t4.alpha_set(:).');
    assert(A == numel(want), 'task4_classify:count', ...
        ['The frozen classifier requires exactly %d runs, one per predeclared ' ...
         'alpha [%s]; got %d.'], numel(want), num2str(want, '%g '), A);
    got = sort(arrayfun(@(r) r.alpha, runs));
    assert(numel(unique(got)) == numel(got), 'task4_classify:duplicate', ...
        'Duplicate alpha values in the sweep: [%s].', num2str(got, '%g '));
    assert(isequal(got, want), 'task4_classify:alphaset', ...
        ['Sweep alphas [%s] are not exactly the predeclared set [%s]. Missing, ' ...
         'extra or foreign alpha values are not classifiable.'], ...
        num2str(got, '%g '), num2str(want, '%g '));

    % ---- "EVERYTHING ELSE IDENTICAL" replay rule. alpha is the ONLY thing the
    % sweep may vary. Any other difference makes the three runs incomparable, so
    % a verdict drawn from them would be meaningless.
    for i = 1:A
        assert(isfield(runs(i), 'config'), 'task4_classify:config', ...
            ['Run %d carries no run-configuration metadata, so the ' ...
             '"everything else identical" rule cannot be checked.'], i);
    end
    ref = runs(1).config;
    for i = 2:A
        d = struct_field_diff(ref, runs(i).config);
        assert(isempty(d), 'task4_classify:mismatch', ...
            ['Run %d differs from run 1 in more than alpha: %s. The frozen ' ...
             'replay rule requires everything except alpha to be identical.'], ...
            i, strjoin(d, ', '));
    end

    % ---- SCAN/RUN ALIGNMENT. Each F5 scan carries the alpha of the run it was
    % built from. Verifying it here makes a permuted, stale or otherwise
    % misordered scan impossible to consume silently against the wrong run.
    for i = 1:A
        assert(isfield(scans(i), 'source_alpha'), 'task4_classify:scan_id', ...
            'Scan %d carries no source_alpha, so it cannot be aligned to a run.', i);
        assert(scans(i).source_alpha == runs(i).alpha, 'task4_classify:scan_align', ...
            ['Scan %d was built from a run with alpha = %g but is paired with a ' ...
             'run with alpha = %g. Misaligned scans are refused, never silently ' ...
             'assigned.'], i, scans(i).source_alpha, runs(i).alpha);
        % source_alpha alone cannot separate two runs that share an alpha but
        % differ in configuration, so bind the scan to the EXACT source run.
        assert(isfield(scans(i), 'source_config'), 'task4_classify:scan_source', ...
            'Scan %d carries no source_config, so it cannot be bound to a run.', i);
        ds = struct_field_diff(scans(i).source_config, runs(i).config);
        assert(isempty(ds), 'task4_classify:scan_source', ...
            ['Scan %d was built from a DIFFERENT run than the one it is paired ' ...
             'with (same alpha, differing configuration: %s). A stale scan is ' ...
             'refused, never consumed.'], i, strjoin(ds, ', '));
    end

    % PRE-RUN VALIDATION ELIGIBILITY, checked ahead of the ordered F-rule.
    % A run refused at the initial-admissibility gate has NO D9 outcome at all -
    % the detector never ran - so it cannot be folded into PASS, INCONCLUSIVE or
    % FAIL, and it must not be treated as a fourth D9 outcome. D9 remains frozen
    % with exactly NORMAL, GUARD_BREACH and NO_EVENT.
    inel = arrayfun(@(r) isfield(r,'eligibility') && ~strcmp(r.eligibility,'ELIGIBLE'), runs);
    if any(inel)
        cls.outcome = 'INELIGIBLE';       % outside the D9 outcome taxonomy
        cls.alphas  = arrayfun(@(r) r.alpha, runs);
        cls.events  = {runs.event};
        cls.eligibility = {runs.eligibility};
        cls.F1 = false;  cls.F2 = false;  cls.F3 = false;
        cls.F4 = false;  cls.F5 = false;
        cls.note = ['At least one run was refused at the initial-admissibility ' ...
                    'gate and is INELIGIBLE for validation. D9 was NOT ' ...
                    'EVALUATED for it, so it carries no D9 outcome; no F1-F5 ' ...
                    'trigger is evaluated and no PASS, INCONCLUSIVE or FAIL ' ...
                    'verdict is produced. Such a run is evidence about neither ' ...
                    'safety nor the detector.'];
        return
    end

    % Every run reaching this point is ELIGIBLE, so its detector did run and its
    % scan must have had something to compare against.
    for i = 1:A
        assert(isfield(scans(i),'comparable') && scans(i).comparable, ...
            'task4_classify:scan_incomparable', ...
            ['Scan %d reports comparable = false for an ELIGIBLE run, so its F5 ' ...
             'classification branch was never evaluated and must not be consumed.'], i);
    end

    ev = cell(1, A);
    f2 = false(1, A);  f3 = false(1, A);  f4 = false(1, A);  f5 = false(1, A);
    for i = 1:A
        r = runs(i);
        ev{i} = r.event;
        f2(i) = strcmp(r.event, 'GUARD_BREACH');
        % F3 has TWO sources and needs both. The per-step arrays cover only the
        % steps at which a command was APPLIED, so a run that ends on a QP
        % failure has its failing step outside them by construction; the
        % run-level qp_failure record is the authoritative source for exactly
        % that case. Reading only the arrays would silently drop the event.
        f3(i) = any(r.qp_infeasible & r.cap_enforced) ...
                || (isfield(r,'qp_failure') && r.qp_failure.occurred ...
                    && r.qp_failure.cap_active);
        f4(i) = any(r.h_body(~isnan(r.h_body)) < 0);
        f5(i) = scans(i).F5;
    end

    cls.alphas   = arrayfun(@(r) r.alpha, runs);
    cls.events   = ev;
    cls.F1 = numel(unique(ev)) > 1;
    cls.F2 = any(f2);   cls.F2_per_alpha = f2;
    cls.F3 = any(f3);   cls.F3_per_alpha = f3;
    cls.F4 = any(f4);   cls.F4_per_alpha = f4;
    cls.F5 = any(f5);   cls.F5_per_alpha = f5;
    cls.F5_branches = {scans.F5_branch};

    cls.meaning = struct( ...
        'F1', 'detector alpha-sensitivity', ...
        'F2', 'sampled guard / envelope failure', ...
        'F3', 'QP / input-feasibility failure', ...
        'F4', 'physical body-safety failure', ...
        'F5', 'sampled guard violation OR detector/post-hoc software defect');

    anyF = cls.F1 || cls.F2 || cls.F3 || cls.F4 || cls.F5;

    if anyF
        cls.outcome = 'FAIL';
        cls.note = 'D9 REOPENS. See the per-trigger meanings; do not merge them.';
    elseif all(strcmp(ev, 'NORMAL'))
        cls.outcome = 'PASS';
        cls.note = ['alpha may be frozen as a validated numerical ' ...
                    'event-detection parameter.'];
    elseif all(strcmp(ev, 'NO_EVENT'))
        cls.outcome = 'INCONCLUSIVE';
        cls.note = ['The detector was not exercised near handoff within the ' ...
                    'chosen diagnostic horizon. D9 is not disproved; alpha ' ...
                    'remains unfrozen. Do NOT extend the horizon iteratively ' ...
                    'until a handoff occurs.'];
    else
        % Unreachable while F1 is computed as above; kept as a hard guard so a
        % future edit cannot silently create an unclassified case.
        cls.outcome = 'FAIL';
        cls.note = 'Mixed classification not caught by F1 - classifier defect.';
    end
end


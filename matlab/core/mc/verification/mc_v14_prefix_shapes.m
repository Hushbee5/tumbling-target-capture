function R = mc_v14_prefix_shapes(~)
% MC_V14_PREFIX_SHAPES  Termination shapes: mask, F5a window and availability. NON-SCIENTIFIC.
%   From ONE real 5 s fixture run (hand-written fixture target, 50 applied
%   steps), MC_VT_PREFIX builds the shapes the frozen pack produces for a
%   zero-applied-step prefix, an in-loop guard breach, a QP abort, a terminal
%   breach and a NORMAL release. For each: the B4 contract holds, the status is
%   the frozen precedence's, and the outputs are evaluated end to end.
%
%   F5a (F6) - expected values are fixed BY CONSTRUCTION in this fixture, not
%   computed with the production helper; the frozen enforcement window is
%   f5_hcap_scan.m:133-138:
%     breach sample negative           -> TRUE  (old 1:K_applied window: FALSE)
%     QP-abort sample negative         -> TRUE
%     terminal sample negative         -> TRUE
%     NORMAL handoff sample negative   -> TRUE  (the handoff sample is inside)
%     negative only AFTER the handoff  -> FALSE (outside the window)
%     no negative sample (control)     -> FALSE
%   F10 - with no applied step the utilisation metrics are NOT_APPLICABLE
%   (NO_APPLIED_STEP), never AVAILABLE with an empty payload; every AVAILABLE
%   metric carries a finite scalar (t_viol may be +Inf, the frozen
%   "no violation observed").

    R.name = 'V14 termination shapes: mask, F5a window, availability';
    ch = {};
    c = mc_constants();
    pBL = baseline_config();
    fx = mc_vt_fixture_target();
    Tsim = 5;  K = round(Tsim / c.design.Ts);
    A = mc_shared_tables(fx.row, 'U', pBL, Tsim);
    P = mc_invoke_proposed(fx.row, A, Tsim);
    full = P.out;
    ch{end+1} = mc_vt_check('real 5 s fixture run is COMPLETE with every h_cap sample positive', ...
        strcmp(mc_classify_proposed('RETURNED', full, K), 'COMPLETE') && all(full.h_cap > 0) ...
        && strcmp(full.event, 'NO_EVENT'), sprintf('min h_cap %.4g', min(full.h_cap)));

    shapes = {
    % label                         kind              k   hcapIndex  want status             want F5a
    'control (no negative h_cap)'   'NONE'            0   0          'COMPLETE'              false
    'in-loop breach sample'         'GUARD_BREACH'    20  20         'GUARD_BREACH_ABORT'    true
    'QP-abort sample'               'QP_ABORT'        20  20         'QP_INFEASIBLE_ABORT'   true
    'zero applied steps'            'ZERO_STEP'       1   0          'QP_INFEASIBLE_ABORT'   false
    'terminal breach sample'        'TERMINAL_BREACH' 0   K+1        'COMPLETE'              true
    'NORMAL handoff sample'         'NORMAL_RELEASE'  30  30         'COMPLETE'              true
    'negative only after handoff'   'NORMAL_RELEASE'  30  33         'COMPLETE'              false
    };
    for s = 1:size(shapes, 1)
        [label, kind, k, hIdx, wantSt, wantF5] = shapes{s, :};
        if strcmp(kind, 'NONE')
            o = full;
        else
            o = mc_vt_prefix(full, kind, k);
        end
        if hIdx > 0
            o.h_cap(hIdx) = -1e-4;                      % the sample under test is negative
        end
        [st, info] = mc_classify_proposed('RETURNED', o, K);
        maskOk = ~isempty(info.mask) && isempty(info.mask.nonfinite) && isempty(info.mask.structure);
        ch{end+1} = mc_vt_check(sprintf('%s: B4 contract holds; status %s', label, wantSt), ...
            maskOk && strcmp(st, wantSt), sprintf('%s (%s)', st, info.reason)); %#ok<AGROW>
        Ro = mc_run_outputs('proposed', 'U', st, struct('out', o, 'act_thresh', P.act_thresh), A.tabs, pBL);
        got = Ro.diagnostics.F5a_sampled_h_cap_neg_window;
        ch{end+1} = mc_vt_check(sprintf('%s: F5a = %d over the frozen window', label, wantF5), ...
            isequal(got, wantF5), sprintf('F5a %d, window end k = %d, K_applied %d', got, ...
            Ro.diagnostics.F5a_window_end_k, o.K_applied)); %#ok<AGROW>
        ch{end+1} = mc_vt_check(sprintf('%s: every AVAILABLE metric is a finite scalar', label), ...
            payloads_ok(Ro.metrics)); %#ok<AGROW>
        if strcmp(kind, 'ZERO_STEP')
            u = {'utilisation_max_ratio', 'utilisation_mean_ratio', 'utilisation_fraction'};
            okU = all(cellfun(@(n) strcmp(Ro.metrics.(n).marker, 'NOT_APPLICABLE') ...
                && strcmp(Ro.metrics.(n).reason, 'NO_APPLIED_STEP') && isempty(Ro.metrics.(n).value), u));
            ch{end+1} = mc_vt_check('zero applied steps: utilisation NOT_APPLICABLE / NO_APPLIED_STEP, no payload', ...
                okU && strcmp(Ro.metrics.min_h_body.marker, 'AVAILABLE') ...
                && strcmp(Ro.metrics.DeltaV_full.marker, 'NOT_APPLICABLE')); %#ok<AGROW>
            ch{end+1} = mc_vt_check('zero applied steps: the run is a prefix, not a numerical failure', ...
                Ro.prefix && ~strcmp(st, 'NUMERICAL_FAILURE')); %#ok<AGROW>
        end
        if any(strcmp(kind, {'GUARD_BREACH', 'QP_ABORT'}))
            ch{end+1} = mc_vt_check(sprintf('%s: prefix metrics AVAILABLE; DeltaV_full NOT_APPLICABLE', label), ...
                Ro.prefix && strcmp(Ro.metrics.min_h_body.marker, 'AVAILABLE') ...
                && strcmp(Ro.metrics.DeltaV_full.marker, 'NOT_APPLICABLE') ...
                && strcmp(Ro.metrics.utilisation_max_ratio.marker, 'AVAILABLE')); %#ok<AGROW>
        end
    end

    % what the superseded window (h_cap over the first K_applied samples, masked by
    % cap_enforced) would have reported for the breach shape - the defect F6
    o = mc_vt_prefix(full, 'GUARD_BREACH', 20);
    o.h_cap(20) = -1e-4;
    en = logical(o.cap_enforced);
    old = any(o.h_cap(1:o.K_applied) < 0 & en(1:o.K_applied));
    ch{end+1} = mc_vt_check('the superseded K_applied window would have MISSED the breach sample', ...
        ~old, sprintf('old window reported %d', old));
    R.checks = [ch{:}];
end

% =====================================================================
function ok = payloads_ok(M)
    ok = true;
    fn = fieldnames(M);
    for i = 1:numel(fn)
        e = M.(fn{i});
        if strcmp(e.marker, 'AVAILABLE')
            v = e.value;
            ok = ok && isnumeric(v) && isscalar(v) && ~isnan(v) ...
                 && (isfinite(v) || (strcmp(fn{i}, 't_viol') && v == Inf));
        else
            ok = ok && isempty(e.value);
        end
    end
end

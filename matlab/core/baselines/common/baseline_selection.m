function sel = baseline_selection(scenarioMetrics, candidateId)
% BASELINE_SELECTION  The frozen T1 -> T7 ordering vector for one candidate.
%   sel = baseline_selection(scenarioMetrics, candidateId) aggregates the
%   per-scenario metric structs returned by BASELINE_METRICS over the five
%   frozen development scenarios into the ordering vector of protocol Sec. 6.4.
%
%       T1  # scenarios with NO_OBSERVED_BODY_VIOLATION                  MAX
%       T2  body-violation deficit  sum_j max( 0 , -min_h_body_j )       MIN
%       T3  # scenarios with PROXIMITY_ACHIEVED                          MAX
%       T4  mean_j max( p_safe_j - s_cap , 0 )                           MIN
%       T5  mean_j  Delta-v accumulated over I_sel_j                     MIN
%       T6  mean_j  APF clipping fraction over I_sel_j                   MIN
%       T7  candidate ID                                                 MIN
%
%   T2 IS ZERO FOR EVERY 5/5 NO-VIOLATION CANDIDATE, so it does not reward
%   unnecessary conservatism. T4 uses the SAFE PREFIX and T5/T6 use the
%   SELECTION HORIZON, so post-violation behaviour cannot influence primary gain
%   selection at any level. Full-800 s Delta-v and clipping remain logged
%   evaluation diagnostics regardless.
%
%   T7 GUARANTEES A UNIQUE WINNER, so exactly one primary APF gain set is always
%   selected, even when no candidate is safe-and-proximate on all five scenarios.
%
%   NO EVALUATION INFORMATION MAY ENTER THIS SELECTION, and none can: the input
%   is the development-scenario metrics and an integer ID, nothing else.
%
%   R1 IS NOT IN THE ORDERING. This file must never reference APF_R1_MARGIN.
%   V5e verifies that by static inspection, so the absence is a checked property
%   rather than an intention.
%
%   NO TOLERANCE ANYWHERE. Comparison is exact; a tolerance-based T5 tie-break is
%   explicitly DEFERRED by protocol Sec. 17 and T7 already resolves ties uniquely.
%
%   sel fields:
%       vector      1x7 [T1 T2 T3 T4 T5 T6 T7]
%       direction   1x7 (+1 = larger is better, -1 = smaller is better)
%       names       1x7 cellstr
%       per_scenario  the raw inputs, kept so the log is auditable
%       eligible    numerical eligibility, propagated from the caller's runs

    assert(isstruct(scenarioMetrics) && ~isempty(scenarioMetrics), ...
        'baseline_selection:input', ...
        'scenarioMetrics must be a non-empty struct array, one entry per scenario.');
    assert(isscalar(candidateId) && isfinite(candidateId) ...
           && candidateId == round(candidateId) && candidateId > 0, ...
        'baseline_selection:id', 'candidateId must be a positive integer.');

    J = numel(scenarioMetrics);

    noViol = false(1, J);
    prox   = false(1, J);
    defic  = zeros(1, J);
    short  = zeros(1, J);
    dv     = zeros(1, J);
    clipf  = zeros(1, J);
    for j = 1:J
        noViol(j) = logical(scenarioMetrics(j).T1_no_violation);
        defic(j)  = scenarioMetrics(j).T2_deficit;
        prox(j)   = logical(scenarioMetrics(j).T3_proximity);
        short(j)  = scenarioMetrics(j).T4_shortfall;
        dv(j)     = scenarioMetrics(j).T5_dv_Isel;
        clipf(j)  = scenarioMetrics(j).T6_clip_Isel;
    end

    assert(all(isfinite(defic)) && all(isfinite(short)) && all(isfinite(dv)), ...
        'baseline_selection:nonfinite', ...
        ['A T2/T4/T5 input is non-finite. Such a candidate is not numerically ' ...
         'eligible and must be excluded before ranking, not ranked.']);
    assert(all(isfinite(clipf)), 'baseline_selection:clip', ...
        ['T6 is the APF clipping fraction and is NaN for a method with no ' ...
         'post-command clip. Only the APF family is tuned, so a NaN here means ' ...
         'the wrong runs were handed to the ordering.']);

    T1 = sum(noViol);
    T2 = sum(defic);
    T3 = sum(prox);
    T4 = mean(short);
    T5 = mean(dv);
    T6 = mean(clipf);
    T7 = candidateId;

    sel.vector    = [T1, T2, T3, T4, T5, T6, T7];
    sel.direction = [+1, -1, +1, -1, -1, -1, -1];
    sel.names     = {'T1_no_violation_count', 'T2_deficit_sum', ...
                     'T3_proximity_count',    'T4_mean_shortfall', ...
                     'T5_mean_dv_Isel',       'T6_mean_clip_Isel', ...
                     'T7_candidate_id'};
    sel.n_scenarios = J;
    sel.per_scenario = struct( ...
        'no_violation', noViol, 'deficit', defic, 'proximity', prox, ...
        'shortfall', short, 'dv_Isel', dv, 'clip_Isel', clipf, ...
        'I_sel_count',     [scenarioMetrics.I_sel_count], ...
        'empty_selection', [scenarioMetrics.empty_selection], ...
        't_viol',          [scenarioMetrics.t_viol], ...
        'p_safe',          [scenarioMetrics.p_safe], ...
        'K_safe_count',    [scenarioMetrics.K_safe_count]);
    sel.candidate_id = candidateId;
    sel.note = ['T1-T4 are RANKING quantities in a lexicographic order, not ' ...
        'defined pass conditions. Safety or proximity failure NEVER removes an ' ...
        'otherwise numerically eligible candidate.'];
end

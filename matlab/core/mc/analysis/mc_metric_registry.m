function R = mc_metric_registry()
% MC_METRIC_REGISTRY  THE one authority for the continuous per-run MC metrics.
%   R = mc_metric_registry() lists every continuous method-neutral metric of
%   protocol Sec. 6.1 that is summarised (Sec. 8.3), compared within a
%   condition (Sec. 8.4) and compared across conditions (Sec. 8.5), with its
%   availability domain. MC_RUN_OUTPUTS produces exactly these entries and
%   MC_AGGREGATE consumes exactly these entries, so the three analyses can
%   never cover different metric sets.
%
%   domain
%     PROXIMITY_TRUE  AVAILABLE only when geometric proximity is achieved
%     COMPLETE_ONLY   AVAILABLE only for a COMPLETE run (not for prefixes)
%     AVAILABLE       AVAILABLE for every valid trajectory, prefixes included
%     APPLIED_STEPS   as AVAILABLE, but NOT_APPLICABLE when no control step
%                     was applied (an empty utilisation history)
%   inf_allowed  +Inf is a defined AVAILABLE value (t_viol: no violation
%                observed); NaN is never an AVAILABLE value
%   complete_scope  additionally summarised over COMPLETE runs only (Sec. 8.3)

    raw = {
    % name                      domain            inf_allowed  complete_scope  note
    't_kstar'                   'PROXIMITY_TRUE'  false        false  'proximity milestone time'
    'DeltaV_to_proximity'       'PROXIMITY_TRUE'  false        false  'impulse to the milestone'
    'rho_dot_truth_kstar'       'PROXIMITY_TRUE'  false        false  'signed, reporting only'
    'DeltaV_full'               'COMPLETE_ONLY'   false        false  'full-horizon impulse'
    'rho_truth_final'           'COMPLETE_ONLY'   false        false  'terminal truth range'
    'min_h_body'                'AVAILABLE'       false        true   'over the executed inspected union'
    'min_clearance_union'       'AVAILABLE'       false        true   'sqrt(min_h_body + r_safe^2) - r_safe (R13)'
    't_viol'                    'AVAILABLE'       true         false  '+Inf = no violation observed'
    'utilisation_max_ratio'     'APPLIED_STEPS'   false        false  'actuator utilisation'
    'utilisation_mean_ratio'    'APPLIED_STEPS'   false        false  'actuator utilisation'
    'utilisation_fraction'      'APPLIED_STEPS'   false        false  'frozen 1e-9 threshold'
    };
    R = struct('name', raw(:, 1), 'domain', raw(:, 2), 'inf_allowed', raw(:, 3), ...
               'complete_scope', raw(:, 4), 'note', raw(:, 5));
end

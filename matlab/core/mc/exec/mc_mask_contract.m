function C = mc_mask_contract()
% MC_MASK_CONTRACT  Explicit field / domain contract for B4 (protocol Sec. 7.2.1).
%   C = mc_mask_contract() returns one entry for EVERY field of an ELIGIBLE
%   simulate_task4 output (the pack at simulate_task4.m:390-451), each
%   classified by source inspection of the frozen code. It is evaluated ONLY
%   for an ELIGIBLE returned out, AFTER IC_REFUSED (B3) has been decided; it is
%   never a blanket isfinite over the struct.
%
%   DOMAINS, with ns = numel(out.t) = K_applied + 1 state samples,
%   ka = K_applied applied steps and ni = (n_sub - 1) * ka intersample points
%   (simulate_task4.m:391-392, 338-347):
%     STATE:r    r x ns      control-grid state samples actually reached
%     APPLIED:r  r x ka      control steps whose command was applied
%     INTER:r    r x ni      strict-interior points of the applied intervals
%     FIXED:rxc  fixed size  SCALAR  1 x 1
%
%   RULES
%     FINITE               required finite on the whole domain  -> else B4
%     FINITE_WHERE_ENFORCED  finite where out.cap_enforced; STRUCTURALLY
%                          NaN where the capture row was not in the QP -> B4
%                          only for a non-finite value on an enforced step
%     FINITE_OR_NAN        finite, or NaN as the frozen "not available"
%                          encoding; +-Inf -> B4
%     FINITE_OR_EMPTY_NO_RECORDS  finite scalar when estimator.records >= 1;
%                          PERMITTED EMPTY when no complete Tw window exists
%     LOGICAL, LOGICAL_SCALAR, CHAR, EVENTS, EVENT, ELIGIBLE, TRUE, FALSE
%                          type / value contracts (no finiteness notion)
%     IC, EVENT_LOG, HANDOFF, QP_FAILURE, STRUCT  structured contracts
%     PROVENANCE           excluded from the finiteness audit; the preview
%                          table inside it is checked by the POST-RUN table
%                          assertion instead (Sec. 5)
%   A missing, extra, mis-sized or mis-typed field is NOT a numerical failure:
%   it is an unexpected state of the frozen output and maps to HARNESS_ERROR.
%
%   STRUCTURALLY NOT-APPLICABLE VALUES IN AN ELIGIBLE out, all permitted:
%     feas_cap           NaN wherever cap_enforced is false (:165, :281-284)
%     feas_joint         NaN when the diagnostic LP returns flag ~= 1
%                        (cbf_qp_two_row.m:69-73); the QP result does not
%                        depend on it
%     estimator.resid    empty when rec.n == 0, i.e. a horizon shorter than one
%                        Tw window (cl_records.m:50-51, 73); never for 800 s
%     qp_failure.*       every field except occurred is empty when no QP
%                        failure occurred (:210-212)
%     qp_failure.joint_margin  NaN under the same LP rule when a failure occurred
%     event_log          [] when event == NO_EVENT;  handoff  [] unless NORMAL
%   The IC-refusal NaN fields d_safe, v_rel_cp and estimator.resid
%   (simulate_task4.m:496, 497, 525) never reach this contract: B3 has
%   already classified that output as IC_REFUSED.

    raw = { ...
    % path                     rule                          domain        source (simulate_task4.m unless named)
    't'                        'FINITE'                      'STATE:1'     ':394'
    'X'                        'FINITE'                      'STATE:6'     ':394'
    'qT'                       'FINITE'                      'STATE:4'     ':395'
    'wT'                       'FINITE'                      'STATE:3'     ':395'
    'Umpc'                     'FINITE'                      'APPLIED:3'   ':396, set at applied steps :316'
    'Usafe'                    'FINITE'                      'APPLIED:3'   ':396, :316'
    'h_body'                   'FINITE'                      'STATE:1'     ':397; loop :231, terminal :356'
    'psi1_body'                'FINITE'                      'STATE:1'     ':397; :231, :357'
    'psi2_body'                'FINITE'                      'APPLIED:1'   ':397; :318'
    'h_cap'                    'FINITE'                      'STATE:1'     ':398; :232, :359 - every sample, enforced or not'
    'psi1_cap'                 'FINITE'                      'STATE:1'     ':398; :232, :359'
    'psi2_cap'                 'FINITE'                      'APPLIED:1'   ':398; :319-320 - every applied step, enforced or not'
    'd_safe'                   'FINITE'                      'STATE:1'     ':399; :231, :356'
    'rho'                      'FINITE'                      'STATE:1'     ':400; :233, :360'
    'rho_dot'                  'FINITE'                      'STATE:1'     ':400; capture_barrier.m:78-82 (0 at contact)'
    'v_rel_cp'                 'FINITE'                      'STATE:1'     ':400; capture_barrier.m:87'
    'eta'                      'FINITE'                      'APPLIED:1'   ':401; :232'
    'nu'                       'FINITE'                      'APPLIED:1'   ':401; :223, cl_estimator_step.m:51'
    'lambda_min'               'FINITE'                      'APPLIED:1'   ':401; :223, 0 with an empty stack (cl_estimator_step.m:40-47)'
    'theta_hat'                'FINITE'                      'APPLIED:3'   ':402; :223'
    'theta_true'               'FINITE'                      'FIXED:3x1'   ':402; params_task4.m:66-69'
    'dev_inf'                  'FINITE'                      'APPLIED:1'   ':403; cbf_qp_two_row.m:120'
    'active'                   'LOGICAL'                     'APPLIED:1'   ':403'
    'cap_enforced'             'LOGICAL'                     'APPLIED:1'   ':404; :163, :273'
    'qp_infeasible'            'LOGICAL'                     'APPLIED:1'   ':404'
    'feas_body'                'FINITE'                      'APPLIED:1'   ':405; :278, cbf_qp_two_row.m:57'
    'feas_cap'                 'FINITE_WHERE_ENFORCED'       'APPLIED:1'   ':405; :165, :281-284'
    'feas_joint'               'FINITE_OR_NAN'               'APPLIED:1'   ':406; :280, cbf_qp_two_row.m:69-73'
    'row_active_body'          'LOGICAL'                     'APPLIED:1'   ':407'
    'row_active_cap'           'LOGICAL'                     'APPLIED:1'   ':407; false where not enforced'
    'events'                   'EVENTS'                      'APPLIED:1'   ':408; handoff_detector'
    'ic'                       'IC'                          'SCALAR'      ':417; task4_ic_admissibility.m'
    'synthetic'                'FALSE'                       'SCALAR'      ':418; MC never sets allow_inadmissible_ic'
    'eligibility'              'ELIGIBLE'                    'SCALAR'      ':419'
    'd9_evaluated'             'TRUE'                        'SCALAR'      ':420'
    'event'                    'EVENT'                       'SCALAR'      ':421'
    'event_log'                'EVENT_LOG'                   'SCALAR'      ':422; log_event :538-557'
    'handoff'                  'HANDOFF'                     'SCALAR'      ':425'
    'handoff_done'             'LOGICAL_SCALAR'              'SCALAR'      ':426'
    'guard_validation'         'CHAR'                        'SCALAR'      ':427'
    'aborted'                  'LOGICAL_SCALAR'              'SCALAR'      ':428'
    'abort_reason'             'CHAR'                        'SCALAR'      ':428'
    'alpha'                    'FINITE'                      'SCALAR'      ':429'
    'eps_rho'                  'FINITE'                      'SCALAR'      ':429'
    'eps_h'                    'FINITE'                      'SCALAR'      ':430'
    's_cap'                    'FINITE'                      'SCALAR'      ':430'
    'alpha_status'             'CHAR'                        'SCALAR'      ':431'
    'kappa'                    'FINITE'                      'FIXED:1x2'   ':432'
    'estimator'                'STRUCT'                      'SCALAR'      ':435-439'
    'estimator.records'        'FINITE'                      'SCALAR'      ':435; rec.n'
    'estimator.resid'          'FINITE_OR_EMPTY_NO_RECORDS'  'SCALAR'      ':435; cl_records.m:50-51, 73'
    'estimator.t_end'          'FINITE'                      'SCALAR'      ':436'
    'estimator.E_end'          'FINITE'                      'SCALAR'      ':436'
    'estimator.theta_hat_end'  'FINITE'                      'FIXED:3x1'   ':437'
    'estimator.nu_end'         'FINITE'                      'SCALAR'      ':438'
    'estimator.Tw'             'FINITE'                      'SCALAR'      ':439'
    'estimator.M'              'FINITE'                      'SCALAR'      ':439'
    'estimator.gamma'          'FINITE'                      'SCALAR'      ':439'
    'qp_failure'               'QP_FAILURE'                  'SCALAR'      ':440; :210-212, :295-305'
    'K_applied'                'FINITE'                      'SCALAR'      ':441'
    'K_evaluated'              'FINITE'                      'SCALAR'      ':442'
    'K_detector'               'FINITE'                      'SCALAR'      ':443'
    't_end'                    'FINITE'                      'SCALAR'      ':444'
    'N'                        'FINITE'                      'SCALAR'      ':445'
    'K'                        'FINITE'                      'SCALAR'      ':445'
    'Tsim'                     'FINITE'                      'SCALAR'      ':445'
    'config'                   'PROVENANCE'                  'SCALAR'      ':446; POST-RUN table assertion (Sec. 5)'
    'inter'                    'STRUCT'                      'SCALAR'      ':449-450'
    'inter.t'                  'FINITE'                      'INTER:1'     ':343, :449'
    'inter.h_body'             'FINITE'                      'INTER:1'     ':344, :449'
    'inter.h_cap_diag'         'FINITE'                      'INTER:1'     ':345, :449 (diagnostic only)'
    'inter.r'                  'FINITE'                      'INTER:3'     ':346, :450'
    };

    C = struct('path', raw(:, 1), 'rule', raw(:, 2), 'domain', raw(:, 3), 'source', raw(:, 4));
end

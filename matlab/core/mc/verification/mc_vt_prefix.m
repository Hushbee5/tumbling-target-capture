function o = mc_vt_prefix(out, kind, k)
% MC_VT_PREFIX  Shape-faithful proposed outputs for the termination shapes (fixtures).
%   o = mc_vt_prefix(out, kind, k) derives, from a REAL complete simulate_task4
%   output with K applied steps, the output the frozen pack would produce
%   (simulate_task4.m:390-451, :239-258, :286-313, :363-386) for:
%
%     'GUARD_BREACH'    in-loop breach detected at state sample k (2 <= k <= K):
%                       ns = k state samples, ka = k-1 applied steps, aborted,
%                       event GUARD_BREACH, event_log at k, guard FAILED
%     'QP_ABORT'        two-row QP infeasible at step k (1 <= k <= K): ns = k,
%                       ka = k-1, aborted, qp_failure recorded at k (cap active)
%     'ZERO_STEP'       'QP_ABORT' at k = 1: one state sample, NO applied step
%     'TERMINAL_BREACH' a completed run whose terminal sample K+1 fires the
%                       detector: not aborted, event GUARD_BREACH at K+1
%     'NORMAL_RELEASE'  a completed run with a NORMAL handoff at sample k: the
%                       capture row is released from step k on
%
%   Only bookkeeping and the event are synthesised; every retained history is
%   the real run's own data, sliced exactly as the frozen pack slices it.

    K = out.K_applied;
    o = out;
    switch kind
        case {'GUARD_BREACH', 'QP_ABORT', 'ZERO_STEP'}
            if strcmp(kind, 'ZERO_STEP'), k = 1; end
            ns = k;  ka = k - 1;
            o = slice(out, ns, ka);
            o.aborted = true;
            o.t_end = o.t(end);
            o.estimator.t_end = o.t(end);
            if strcmp(kind, 'GUARD_BREACH')
                o.event = 'GUARD_BREACH';
                o.guard_validation = 'FAILED';
                o.abort_reason = 'fixture: in-loop GUARD_BREACH';
                o.event_log = event_log(out, k, 'GUARD_BREACH');
                o.handoff = [];
                o.handoff_done = false;
                o.K_evaluated = ka;
                o.K_detector = k;
            else
                o.abort_reason = 'fixture: two-row QP infeasible';
                o.qp_failure = struct('occurred', true, 'k', k, 't', out.t(k), 'cap_active', true, ...
                    'status', -1, 'exitflag', -2, 'feasible', false, ...
                    'feas_margin', [out.feas_body(k), out.feas_cap(k)], ...
                    'joint_margin', out.feas_joint(k), 'row_names', {{'body', 'cap'}});
                o.K_evaluated = k;
                o.K_detector = k;
            end
        case 'TERMINAL_BREACH'
            o.event = 'GUARD_BREACH';
            o.guard_validation = 'FAILED';
            o.event_log = event_log(out, K + 1, 'GUARD_BREACH');
            o.handoff = [];
            o.handoff_done = false;
            o.aborted = false;
            o.K_detector = K + 1;
        case 'NORMAL_RELEASE'
            o.event = 'NORMAL';
            o.event_log = event_log(out, k, 'NORMAL');
            o.handoff = o.event_log;
            o.handoff_done = true;
            o.cap_enforced(k:end) = false;
            o.feas_cap(k:end) = NaN;
            o.row_active_cap(k:end) = false;
            o.events{k} = 'NORMAL';
        otherwise
            error('mc:vt:prefix', 'Unknown prefix kind ''%s''.', kind);
    end
end

% =====================================================================
function o = slice(out, ns, ka)
    o = out;
    st = {'t', 'X', 'qT', 'wT', 'h_body', 'psi1_body', 'h_cap', 'psi1_cap', 'd_safe', ...
          'rho', 'rho_dot', 'v_rel_cp'};
    ap = {'Umpc', 'Usafe', 'psi2_body', 'psi2_cap', 'eta', 'nu', 'lambda_min', 'theta_hat', ...
          'dev_inf', 'active', 'cap_enforced', 'qp_infeasible', 'feas_body', 'feas_cap', ...
          'feas_joint', 'row_active_body', 'row_active_cap', 'events'};
    for i = 1:numel(st)
        o.(st{i}) = out.(st{i})(:, 1:ns);
    end
    for i = 1:numel(ap)
        o.(ap{i}) = out.(ap{i})(:, 1:ka);
    end
    ni = (out.config.opt.n_sub - 1) * ka;
    if ni == 0
        o.inter = struct('t', [], 'h_body', [], 'h_cap_diag', [], 'r', zeros(3, 0));
    else
        o.inter = struct('t', out.inter.t(1:ni), 'h_body', out.inter.h_body(1:ni), ...
                         'h_cap_diag', out.inter.h_cap_diag(1:ni), 'r', out.inter.r(:, 1:ni));
    end
    o.K_applied = ka;
    o.K = ka;
end

% =====================================================================
function s = event_log(out, k, kind)
    kk = min(k, numel(out.t));
    ka = max(1, min(kk, numel(out.nu)));
    s = struct('t', out.t(kk), 'k', k, 'event', kind, 'rho', out.rho(kk), ...
        'rho_dot', out.rho_dot(kk), 'v_rel_cp', out.v_rel_cp(kk), 'nu', out.nu(ka), ...
        'h_body', out.h_body(kk), 'psi1_body', out.psi1_body(kk), 'h_cap', out.h_cap(kk), ...
        'psi1_cap', out.psi1_cap(kk), 'alpha', out.alpha, 'eps_rho', out.eps_rho, ...
        'theta_hat', out.theta_hat(:, ka), 'eta', out.eta(ka), 's_cap', out.s_cap);
end

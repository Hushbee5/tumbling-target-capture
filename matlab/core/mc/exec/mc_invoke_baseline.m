function B = mc_invoke_baseline(method, row, A, Tsim, pBL, theta95)
% MC_INVOKE_BASELINE  One guarded invocation of a frozen baseline.
%   B = mc_invoke_baseline(method, row, A, Tsim, pBL, theta95) implements the
%   NOMINAL MPC and PRIMARY APF blocks of protocol Sec. 5:
%
%     run = simulate_baseline(pBL, struct('method', 'nominal_mpc', 'x0', x0_i, ...
%             'Tsim', Tsim, 'truthIC', truthIC_i, 'previewIC', prevIC_ic, 'tables', tabs_ic))
%     run = simulate_baseline(pBL, struct('method', 'apf', 'x0', x0_i, 'Tsim', Tsim, ...
%             'gains', apf_gains(theta_95, pBL), 'truthIC', truthIC_i, ...
%             'previewIC', prevIC_ic, 'tables', tabs_ic))
%
%   inside MC_R18_INVOKE. theta95 must come from MC_LOAD_APF_WINNER (the
%   hash-frozen tuning record, R10). The frozen simulator re-checks the table
%   identities itself (simulate_baseline.m:104-119) and refuses the evaluation
%   initial condition (simulate_baseline.m:74-82); allow_eval_x0 is never set.
%   Its own internal try/catch turns an ode45 failure - promoted or not - into
%   a graceful numerical failure (Sec. 10.5).
%
%   B fields: guard (MC_R18_INVOKE result without .value), run (or []), wall_s.

    assert(strcmp(A.status, 'TABLES_OK'), 'mc:baseline:level_a', ...
        'A baseline may run only after a TABLES_OK Level-A result.');
    switch method
        case 'nominal_mpc'
            opt = struct('method', 'nominal_mpc', 'x0', row.x0, ...
                    'Tsim', Tsim, 'truthIC', A.truthIC, 'previewIC', A.prevIC, 'tables', A.tabs);
        case 'apf'
            assert(isstruct(theta95) && all(isfield(theta95, {'omega_n', 'zeta', 'beta', 'kappa'})), ...
                'mc:baseline:theta', 'theta95 must be the frozen APF winner theta.');
            opt = struct('method', 'apf', 'x0', row.x0, 'Tsim', Tsim, ...
                    'gains', apf_gains(theta95, pBL), 'truthIC', A.truthIC, ...
                    'previewIC', A.prevIC, 'tables', A.tabs);
        otherwise
            error('mc:baseline:method', 'Unknown baseline method ''%s''.', method);
    end

    t0 = tic;
    r = mc_r18_invoke(@() simulate_baseline(pBL, opt));
    B.wall_s = toc(t0);
    B.guard  = rmfield(r, 'value');
    B.run    = [];
    if strcmp(r.status, 'RETURNED')
        % The POST-RUN assertion (MC_POSTRUN_CHECK) is applied by MC_RUN_PAIR
        % only after the POST_EXECUTION ledger entry is durable.
        B.run = r.value;
    end
end

function mc_postrun_check(method, obj, A, row)
% MC_POSTRUN_CHECK  The POST-RUN assertions of protocol Sec. 5, once a run returned.
%   mc_postrun_check(method, obj, A, row)
%
%   proposed   out.config.custom_tbl == true and
%              isequal(out.config.opt.tbl, tabs_ic.tbl_preview)
%              -> the proposed upper layer consumed exactly the shared table
%   baselines  the returned run describes the requested method and x0 and the
%              shared tables' target identities (simulate_baseline.m:356)
%
%   Called by MC_RUN_PAIR AFTER the POST_EXECUTION ledger entry is durable, so a
%   failure here can never erase the knowledge that the controller executed.
%   Each failure throws 'mc:integrity:*' (recorded as HARNESS_ERROR).

    switch method
        case 'proposed'
            out = obj.out;
            if isempty(out), return, end
            assert(isstruct(out) && isfield(out, 'config') && isfield(out.config, 'custom_tbl') ...
                && isequal(out.config.custom_tbl, true) && isfield(out.config.opt, 'tbl') ...
                && isequal(out.config.opt.tbl, A.tabs.tbl_preview), ...
                'mc:integrity:postrun_table', ...
                'POST-RUN: the proposed upper layer did not consume exactly tabs_ic.tbl_preview.');
        case {'nominal_mpc', 'apf'}
            run = obj;
            if isempty(run), return, end
            assert(isstruct(run) && isfield(run, 'method') && strcmp(run.method, method) ...
                && isequal(run.x0, row.x0(:)) && isequal(run.target_identity, A.tabs.identity), ...
                'mc:integrity:baseline_postrun', ...
                'POST-RUN: the baseline run does not describe the requested method, x0 or tables.');
        otherwise
            error('mc:integrity:method', 'Unknown method ''%s''.', method);
    end
end

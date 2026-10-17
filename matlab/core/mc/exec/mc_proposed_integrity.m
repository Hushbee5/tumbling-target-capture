function mc_proposed_integrity(out, tabs)
% MC_PROPOSED_INTEGRITY  MC per-run integrity assertions of Sec. 6.1 (proposed).
%   mc_proposed_integrity(out, tabs) asserts, before any metric call:
%
%     out.config.custom_tbl == true  and  isequal(out.config.opt.tbl, tabs.tbl_preview)
%         -> the proposed upper layer consumed exactly the shared preview table
%     isequal(out.qT, tabs.qT(:, 1:numel(out.t)))  and the same for wT
%         -> the proposed method and the baselines saw the identical truth
%            target, which simulate_task4 still propagates internally
%
%   Each failure throws 'mc:integrity:*', which the orchestrator records as
%   HARNESS_ERROR; the campaign stops. The cross-condition truth identity
%   (U versus M of the same trial) is asserted by the orchestrator from the
%   stored truth hashes; the intersample assertions live in
%   MC_PROPOSED_ADAPTER.

    ns = numel(out.t);
    assert(isequal(out.config.custom_tbl, true) && isequal(out.config.opt.tbl, tabs.tbl_preview), ...
        'mc:integrity:shared_table', ...
        'The proposed run did not consume exactly tabs_ic.tbl_preview.');
    assert(size(tabs.qT, 2) >= ns && isequal(out.qT, tabs.qT(:, 1:ns)) ...
        && isequal(out.wT, tabs.wT(:, 1:ns)), 'mc:integrity:truth_identity', ...
        'The proposed truth attitude/rate differs from the shared truth tables.');
end

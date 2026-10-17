function W = mc_load_apf_winner(pBL, recordPath)
% MC_LOAD_APF_WINNER  Read the frozen primary APF winner from the tuning record.
%   W = mc_load_apf_winner(pBL)               the frozen record in results/
%   W = mc_load_apf_winner(pBL, recordPath)   an explicit path (fixtures)
%
%   R10: load_frozen_gains is a LOCAL function of baseline_evaluate.m, so the
%   MC needs an additive loader. This one mirrors its checks
%   (baseline_evaluate.m:398-577) step for step and then asserts EXACT
%   equality with the approved winner of protocol Sec. 1 through
%   MC_APF_WINNER_CHECK. There is no second gain authority: every value used
%   is READ from the hash-frozen record; the approved values are only compared
%   against. Any mismatch is a hard stop.
%
%     1. the record hashes to the frozen tuning-record SHA-256;
%     2. outcome SEARCH_COMPLETE; bound to protocol Object A, the R7 aggregate
%        and V1-V11 Gate #2; 5 scenarios; Tsim = 800 s;
%     3. the winner is an ELIGIBLE candidate contained in the record, with
%        matching levels, ordering vector, round and theta;
%     4. the winner is the stored TERMINAL INCUMBENT decision (stored-state
%        replay only; nothing is reranked or retuned);
%     5. theta is taken from the MATCHED CANDIDATE; gains = apf_gains(theta, pBL);
%     6. id, levels, theta and derived gains equal the approved values exactly.
%
%   W fields: theta, gains, provenance.

    c = mc_constants();
    root = mc_repo_root();
    k = find(strcmp(c.files(:, 1), 'tuning_record'), 1);
    if nargin < 2 || isempty(recordPath)
        recordPath = fullfile(root, strrep(c.files{k, 2}, '/', filesep));
    end

    gsha = baseline_sha256(recordPath);
    assert(strcmpi(gsha, c.files{k, 3}), 'mc:apf:record_sha', ...
        'HARD STOP: the tuning record hashes to %s, not the frozen %s.', gsha, c.files{k, 3});

    G = load(recordPath, 'res');
    assert(isfield(G, 'res'), 'mc:apf:record_shape', 'The tuning record carries no `res`.');
    R = G.res;

    kA = find(strcmp(c.files(:, 1), 'object_a'), 1);
    kG = find(strcmp(c.files(:, 1), 'gate2'), 1);
    assert(strcmp(R.outcome, 'SEARCH_COMPLETE'), 'mc:apf:outcome', ...
        'HARD STOP: tuning outcome is ''%s'', not SEARCH_COMPLETE.', R.outcome);
    assert(strcmpi(R.binding.protocol_sha256, c.files{kA, 3}) ...
        && strcmpi(R.binding.protocol_sha256, pBL.bl.protocol_sha256), ...
        'mc:apf:binding_protocol', 'HARD STOP: the record is not bound to protocol Object A.');
    assert(strcmpi(R.binding.aggregate_sha256, c.r7.aggregate), 'mc:apf:binding_aggregate', ...
        'HARD STOP: the record is not bound to the R7 aggregate.');
    assert(strcmpi(R.binding.verification_gate_sha256, c.files{kG, 3}), 'mc:apf:binding_gate', ...
        'HARD STOP: the record is not bound to V1-V11 Gate #2.');
    assert(R.n_scenarios == 5 && R.Tsim == 800, 'mc:apf:record_scope', ...
        'HARD STOP: the record does not describe the frozen 5-scenario 800 s search.');

    % ---- the winner is an ELIGIBLE candidate contained in the record --------
    assert(isstruct(R.winner) && ~isempty(R.winner), 'mc:apf:winner', ...
        'HARD STOP: the record carries no selected gain set.');
    ids = [R.candidates.id];
    j = find(ids == R.winner.id, 1);
    assert(~isempty(j), 'mc:apf:winner_absent', 'HARD STOP: the winner is not a stored candidate.');
    assert(R.candidates(j).eligible, 'mc:apf:winner_ineligible', ...
        'HARD STOP: the winner is a numerically ineligible candidate.');
    assert(isequal(R.candidates(j).levels, R.winner.levels) ...
        && isequaln(R.candidates(j).vector, R.winner.vector) ...
        && isequal(R.candidates(j).round, R.winner.round), 'mc:apf:winner_consistency', ...
        'HARD STOP: the winner disagrees with the candidate it names.');
    tf = {'omega_n', 'zeta', 'beta', 'kappa'};
    for q = 1:numel(tf)
        wv = R.winner.theta.(tf{q});
        cv = R.candidates(j).theta.(tf{q});
        assert(isa(wv, 'double') && isa(cv, 'double') && isequal(wv, cv), ...
            'mc:apf:winner_theta', 'HARD STOP: winner theta.%s differs from its candidate.', tf{q});
    end

    % ---- the winner is the stored TERMINAL INCUMBENT decision -----------------
    if ~isempty(R.rounds)
        assert(all(logical([R.rounds.complete])), 'mc:apf:round_incomplete', ...
            'HARD STOP: a stored refinement round is incomplete.');
        idxs = [R.rounds.index];
        assert(isequal(idxs, 1:numel(idxs)) && numel(idxs) <= 3, 'mc:apf:round_order', ...
            'HARD STOP: stored round indices are not 1..n with n <= 3.');
        term = R.rounds(end).incumbent_after;
    else
        term = R.coarse_incumbent;
    end
    assert(~isempty(term) && isequal(term.id, R.winner.id) ...
        && isequal(term.levels, R.winner.levels) && isequaln(term.vector, R.winner.vector) ...
        && isequal(term.round, R.winner.round), 'mc:apf:winner_not_terminal', ...
        'HARD STOP: the winner is not the stored terminal incumbent decision.');
    for q = 1:numel(tf)
        assert(isa(term.theta.(tf{q}), 'double') && isequal(term.theta.(tf{q}), R.winner.theta.(tf{q})), ...
            'mc:apf:terminal_theta', 'HARD STOP: terminal theta.%s differs from the winner.', tf{q});
    end

    % ---- theta from the MATCHED CANDIDATE, then exact approval check ----------
    cth   = R.candidates(j).theta;
    theta = struct('omega_n', cth.omega_n, 'zeta', cth.zeta, 'beta', cth.beta, 'kappa', cth.kappa);
    gains = apf_gains(theta, pBL);
    mc_apf_winner_check(R.winner.id, R.winner.levels, theta, gains);

    W.theta = theta;
    W.gains = gains;
    W.provenance = struct('record', c.files{k, 2}, 'record_sha256', gsha, ...
        'winner_id', R.winner.id, 'winner_levels', R.winner.levels, ...
        'winner_round', R.winner.round, 'outcome', R.outcome, ...
        'theta_source', 'matched candidate record (verified equal to winner.theta)', ...
        'note', 'READ from the hash-frozen tuning record; nothing recomputed or retuned.');
end

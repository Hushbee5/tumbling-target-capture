function g = mc_campaign_guard(ctx, stage, condition, trialId)
% MC_CAMPAIGN_GUARD  Live authority check at EVERY callable campaign boundary.
%   g = mc_campaign_guard(ctx, stage)
%   g = mc_campaign_guard(ctx, stage, condition, trialId)
%
%   stage: 'operator' | 'closure' | 'aggregate' | 'shard_start' | 'pair' |
%          'method'                                   (BOUNDARY stages)
%          'write'                                    (every checkpoint writer)
%
%   EVERY STAGE
%     - the context hashes to its seal and the seal was ISSUED by MC_CONTEXT in
%       this session ('mc:campaign:ctx_mutated' / 'ctx_unregistered'); the
%       issuance registry is local to MC_CONTEXT, so no caller can register a
%       recomposed or re-sealed context;
%     - SCIENTIFIC: never in a verification session, no fault point armed, no
%       runner override; VERIFICATION: root outside the repository, the
%       VERIFICATION binding, a fixture table, a short horizon.
%
%   BOUNDARY STAGES, SCIENTIFIC - LIVE RE-DERIVATION of every scientific field,
%   never trusting the context:
%     - MC_PREFLIGHT('execution', ctx.inputs) passes NOW (checkpoint check
%       scoped to the (condition, trial) for 'pair' / 'method', full otherwise);
%     - the binding rebuilt from that preflight equals ctx.binding;
%     - the canonical CSV, re-read against the SHA-256 declared in the committed
%       freeze record, equals ctx.trials bitwise (every trial row);
%     - Tsim, K, the trial set 1:100 and the checkpoint root equal the frozen
%       constants; pBL equals baseline_config(); the APF winner re-read from the
%       hash-frozen tuning record equals ctx.apf.
%   'shard_start', 'pair', 'method': every HARNESS_ERROR incident is
%   acknowledged (MC_INCIDENT_GATE). 'shard_start' and 'pair' of Condition M:
%   the COMPLETE Condition-U checkpoint re-proves from scratch
%   (MC_CLOSE_CONDITION 'verify').
%
%   THE LIVE LEASE. When a boundary stage has passed every check, g.lease holds
%   a LIVE LEASE for this sealed context: an ONCLEANUP object that ends the
%   lease when the caller's variable holding g is cleared (normal return or
%   error). The 'write' stage - called by every checkpoint writer
%   (MC_ATOMIC_WRITE into the scientific tree, MC_RECORD_WRITE, MC_ATTEMPT_LEDGER,
%   MC_RESERVATION, MC_SHARD_LOCK) - performs the seal checks above and then
%   REFUSES ('mc:campaign:no_live_authority') unless a lease for this context is
%   active in this process. A write can therefore never substitute the seal for
%   live authority: it happens only inside a boundary whose live checks passed.
%   The lease store is local to this file; it can be granted only by the checks
%   above, and a lease object can only end a lease, never create one. The
%   'write' stage re-runs nothing heavy and calls no writer, so there is no
%   guard/write recursion. Callers hold g in a variable for the boundary's
%   duration.

    if nargin < 3, condition = ''; end
    if nargin < 4, trialId = []; end
    assert(any(strcmp(stage, {'operator', 'closure', 'aggregate', 'shard_start', 'pair', ...
        'method', 'write'})), 'mc:campaign:stage', 'Unknown guard stage ''%s''.', stage);
    c = mc_constants();
    root = mc_repo_root();

    d = mc_context_seal(ctx);
    assert(isfield(ctx, 'seal') && isstruct(ctx.seal) && isfield(ctx.seal, 'digest') ...
        && strcmp(ctx.seal.digest, d), 'mc:campaign:ctx_mutated', ...
        'REFUSED: the campaign context was modified after MC_CONTEXT sealed it.');
    assert(mc_context('is_issued', d), 'mc:campaign:ctx_unregistered', ...
        'REFUSED: this context was not issued by MC_CONTEXT in this MATLAB session.');

    g = struct('stage', stage, 'kind', ctx.kind, 'preflight', [], 'lease', []);
    switch ctx.kind
        case 'scientific'
            assert(~mc_rng_sentinel('in_verification'), 'mc:campaign:verification_session', ...
                'REFUSED: no scientific campaign step runs in a verification session.');
            assert(~mc_fault_hook('armed'), 'mc:campaign:fault_hook_armed', ...
                'REFUSED: a verification fault-injection point is armed.');
            assert(isstruct(ctx.runner_override) && isempty(fieldnames(ctx.runner_override)), ...
                'mc:campaign:runner_override', 'REFUSED: a scientific context carries a runner override.');
            assert(strcmp(ctx.record_kind, 'SCIENTIFIC'), 'mc:campaign:record_kind', ...
                'REFUSED: a scientific context must write SCIENTIFIC records.');
            if ~strcmp(stage, 'write')
                g.preflight = live_scientific(ctx, stage, condition, trialId, c, root);
            end
        case 'verification'
            rootAbs = mc_abs_path(ctx.root);
            assert(~strncmpi(rootAbs, [root filesep], numel(root) + 1) && ~strcmpi(rootAbs, root), ...
                'mc:campaign:verification_root', 'REFUSED: a verification root lies inside the repository.');
            assert(isequal(ctx.binding, mc_binding('VERIFICATION')) ...
                && strcmp(ctx.record_kind, 'VERIFICATION') && ctx.Tsim > 0 && ctx.Tsim <= 60 ...
                && any(strcmp(ctx.trials.kind, {'FIXTURE', 'SYNTHETIC'})), ...
                'mc:campaign:verification_ctx', 'REFUSED: not a valid verification context.');
        otherwise
            error('mc:campaign:kind', 'Unknown context kind ''%s''.', ctx.kind);
    end

    if strcmp(stage, 'write')
        assert(live_lease('active', d), 'mc:campaign:no_live_authority', ...
            ['REFUSED: a checkpoint write outside an active guarded boundary. Every write ' ...
             'happens inside a boundary (shard, pair, method, closure, operator action) ' ...
             'whose live checks passed in this process.']);
        return
    end

    if any(strcmp(stage, {'shard_start', 'pair', 'method'}))
        assert(any(strcmp(condition, c.design.conditions)), 'mc:campaign:condition', ...
            'Unknown condition ''%s''.', condition);
        mc_incident_gate(ctx);
        if strcmp(condition, 'M') && any(strcmp(stage, {'shard_start', 'pair'}))
            mc_close_condition(ctx, 'U', 'verify');
        end
    end
    g.lease = live_lease('grant', d);
end

% =====================================================================
function pre = live_scientific(ctx, stage, condition, trialId, c, root)
    if any(strcmp(stage, {'pair', 'method'})) && ~isempty(trialId)
        scope = struct('condition', condition, 'trial_id', trialId);
    else
        scope = 'full';
    end
    pre = mc_preflight('execution', ctx.inputs, struct('checkpoint_scope', scope));
    assert(isequal(pre.authorised, true), 'mc:campaign:preflight', ...
        'REFUSED: the execution preflight no longer passes.');
    assert(isequal(ctx.binding, mc_binding('SCIENTIFIC', pre)), 'mc:campaign:binding_stale', ...
        'REFUSED: the context binding differs from the live binding.');
    T = mc_trial_csv_read(fullfile(root, strrep(c.csv.path, '/', filesep)), ...
                          c.design.N_PHYSICAL, pre.verified.trial_csv_sha256);
    assert(strcmp(trial_digest(T), trial_digest(ctx.trials)), 'mc:campaign:trials_stale', ...
        'REFUSED: the context trial rows differ from the committed canonical CSV.');
    ck = mc_abs_path(fullfile(root, strrep(c.mc.dest_dir, '/', filesep), 'checkpoint'));
    assert(ctx.Tsim == c.design.Tsim && ctx.K_expected == c.design.K ...
        && isequal(ctx.trial_ids, 1:c.design.N_PHYSICAL) && strcmpi(mc_abs_path(ctx.root), ck), ...
        'mc:campaign:constants', 'REFUSED: horizon, trial set or checkpoint root is not the frozen one.');
    assert(isequal(ctx.pBL, baseline_config()), 'mc:campaign:pBL_stale', ...
        'REFUSED: pBL differs from baseline_config().');
    W = mc_load_apf_winner(ctx.pBL);
    assert(isequal(W.theta, ctx.apf.theta) && isequal(W.gains, ctx.apf.gains), ...
        'mc:campaign:apf_stale', 'REFUSED: the APF gains differ from the frozen tuning record.');
end

% =====================================================================
function d = trial_digest(T)
    d = mc_value_sha256(struct('n', T.n, 'trial_id', T.trial_id, 'U', T.U, 'r0', T.r0, ...
        'v0', T.v0, 'q0', T.q0, 'w0', T.w0, 'Idiag', T.Idiag));
end

% =====================================================================
function out = live_lease(action, d)
% Live leases per sealed-context digest: a count of the boundaries whose live
% checks passed and that are still in progress. LOCAL: 'grant' is reachable only
% from the end of the guard above; the ONCLEANUP object it returns can only
% call 'release'.
    persistent L
    if isempty(L)
        L = containers.Map('KeyType', 'char', 'ValueType', 'double');
    end
    out = [];
    switch action
        case 'grant'
            if isKey(L, d), L(d) = L(d) + 1; else, L(d) = 1; end
            out = onCleanup(@() live_lease('release', d));
        case 'release'
            if isKey(L, d)
                L(d) = L(d) - 1;
                if L(d) <= 0, remove(L, d); end
            end
        case 'active'
            out = isKey(L, d) && L(d) > 0;
    end
end

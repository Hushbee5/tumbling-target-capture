function C = mc_close_condition(ctx, condition, mode)
% MC_CLOSE_CONDITION  Close, or re-verify, the checkpoint of one condition.
%   C = mc_close_condition(ctx, condition, 'close')   write the closure once
%   C = mc_close_condition(ctx, condition, 'verify')  FULL re-proof
%
%   The closure is a completeness and binding check, not a licence for any
%   change (protocol Sec. 10.3). BOTH modes re-prove the live checkpoint from
%   scratch with MC_CONDITION_REPROOF - the records, every unit's complete
%   attempt history (MC_ATTEMPT_LEDGER 'state'), the reservations, an inventory
%   of every checkpoint location (MC_CHECKPOINT_INVENTORY) and the incident
%   gate; nothing is trusted from the closure file itself.
%
%   'close'  if no closure exists: (for M, first the U closure must verify)
%            re-prove, then write <root>/<cond>_CLOSED.mat once, atomically:
%            schema task4_mc_closure_v2, condition, binding, trial ids, methods,
%            n_expected = N x 3, the record manifest (every record's file,
%            SHA-256, status, attempt) and its digest, the HISTORY (every other
%            artefact of the condition - ledger files, rulings, reservations and
%            releases, shard locks and logs, the plan, its incidents and their
%            acknowledgements, residue - with its SHA-256) and its digest, and
%            the canonical trial-table identity.
%   'verify' the closure file must exist and be well formed - exact schema,
%            this condition, this binding and trial set, n_expected = N x 3,
%            exactly n_expected manifest entries, matching manifest and history
%            digests and canonical trial-table identity - AND its manifest and
%            history must equal the freshly re-proven ones exactly
%            ('mc:closure:changed'): no record and no historical artefact can
%            change, appear or vanish after the closure.

    gClose = mc_campaign_guard(ctx, 'closure'); %#ok<NASGU>   % live lease for the write below
    c = mc_constants();
    f = fullfile(ctx.root, sprintf('%s_CLOSED.mat', condition));
    switch mode
        case 'verify'
            assert(isfile(f), 'mc:closure:missing', ...
                'The %s checkpoint is not closed; the next step may not proceed.', condition);
            if strcmp(condition, 'M')
                mc_close_condition(ctx, 'U', 'verify');
            end
            C = load_closure(f);
            nExp = numel(ctx.trial_ids) * numel(c.design.methods);
            assert(strcmp(C.condition, condition) && isequal(C.binding, ctx.binding) ...
                && isequal(C.trial_ids, ctx.trial_ids) && isequal(C.methods, c.design.methods) ...
                && isequal(C.n_expected, nExp) && numel(C.manifest) == nExp ...
                && strcmp(C.manifest_sha256, mc_value_sha256(C.manifest)) ...
                && strcmp(C.history_sha256, mc_value_sha256(C.history)) ...
                && strcmp(C.canonical_csv_sha256, ctx.binding.trial_csv_sha256), ...
                'mc:closure:malformed', 'The %s closure is malformed or bound elsewhere.', condition);
            P = mc_condition_reproof(ctx, condition);
            assert(isequal(C.manifest, P.manifest) && isequal(C.history, P.history), ...
                'mc:closure:changed', 'ABORT: the live %s checkpoint no longer matches its closure.', condition);
        case 'close'
            if isfile(f)
                C = mc_close_condition(ctx, condition, 'verify');
                return
            end
            if strcmp(condition, 'M')
                mc_close_condition(ctx, 'U', 'verify');
            end
            P = mc_condition_reproof(ctx, condition);
            C = struct('schema', 'task4_mc_closure_v2', 'condition', condition, ...
                'binding', ctx.binding, 'trial_ids', ctx.trial_ids, ...
                'methods', {c.design.methods}, 'n_expected', numel(ctx.trial_ids) * numel(c.design.methods), ...
                'manifest', P.manifest, 'manifest_sha256', P.manifest_sha256, ...
                'history', P.history, 'history_sha256', P.history_sha256, ...
                'canonical_csv_sha256', ctx.binding.trial_csv_sha256, ...
                'created_utc', mc_utc_now(), 'process', mc_process_identity(), ...
                'note', 'Completeness and binding closure only; not a licence for any change.');
            opts = struct();
            if strcmp(ctx.kind, 'scientific'), opts.ctx = ctx; end
            mc_atomic_write(f, struct('closure', C), 'mat', opts);
        otherwise
            error('mc:closure:mode', 'Unknown mode ''%s''.', mode);
    end
end

% =====================================================================
function C = load_closure(f)
    need = {'schema', 'condition', 'binding', 'trial_ids', 'methods', 'n_expected', ...
            'manifest', 'manifest_sha256', 'history', 'history_sha256', 'canonical_csv_sha256', ...
            'created_utc', 'process', 'note'};
    S = load(f);
    assert(isfield(S, 'closure') && isstruct(S.closure) && isscalar(S.closure) ...
        && isempty(setxor(fieldnames(S.closure), need)) ...
        && strcmp(S.closure.schema, 'task4_mc_closure_v2') && isstruct(S.closure.manifest) ...
        && all(isfield(S.closure.manifest, {'file', 'sha256', 'status', 'attempt'})) ...
        && isstruct(S.closure.history) && all(isfield(S.closure.history, {'file', 'sha256'})), ...
        'mc:closure:malformed', 'File %s is not a well-formed task4_mc_closure_v2 closure.', f);
    C = S.closure;
end

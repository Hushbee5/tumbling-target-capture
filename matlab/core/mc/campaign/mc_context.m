function ctx = mc_context(kind, varargin)
% MC_CONTEXT  Issue a SEALED campaign context: scientific or verification.
%   ctx = mc_context('scientific', inputs)
%       inputs: the four frozen identities of the authorising invocation
%       (protocol Sec. 11): protocol_sha256, mc_source_aggregate,
%       mc_impl_commit, freeze_record_sha256. Refused in any session that has
%       run the verification suite. MC_PREFLIGHT('execution', inputs) must pass;
%       the canonical CSV SHA-256 is read from the committed freeze record.
%       Horizon 800 s, trial ids 1..100, checkpoint root
%       results/task4/mc/checkpoint, trial inputs loaded from the verified
%       canonical CSV (never regenerated from RNG).
%
%   ctx = mc_context('verification', ckptRoot, Tsim, T, trialIds)
%   ctx = mc_context('verification', ckptRoot, Tsim, T, trialIds, opts)
%       NON-SCIENTIFIC fixture context for the verification suite only:
%       ckptRoot OUTSIDE the repository, 0 < Tsim <= 60 s on the control grid,
%       T a FIXTURE or SYNTHETIC table, every record bound VERIFICATION_ONLY.
%       opts.runner_override: struct of function handles, per method, that
%       replace the method invocation (fault-injection fixtures only).
%
%   tf = mc_context('is_issued', digest)
%       true iff THIS function issued a context with that seal digest in this
%       MATLAB session (queried by MC_CAMPAIGN_GUARD).
%
%   THE SEAL. ctx.seal.digest = MC_CONTEXT_SEAL(ctx). The digest of every
%   issued context is recorded in a registry that is a LOCAL function of this
%   file: no other file, command, function handle or current folder can add a
%   digest to it (a private/ folder would not be enough - it is callable from
%   inside itself). The only way into the registry is a successful issuance
%   above: for 'scientific', a passed execution preflight. MC_CAMPAIGN_GUARD
%   refuses a context whose sealed fields changed afterwards or whose digest
%   this function never issued, and for a scientific context it also
%   re-derives every scientific field from live repository state at every
%   boundary. The context carries no mutable authority: incident
%   acknowledgements, shard plans and locks, reservations and attempt rulings
%   live on disk as immutable, hash-bound files.

    mlock;                          % the issuance registry survives CLEAR
    if strcmp(kind, 'is_issued')
        assert(numel(varargin) == 1, 'mc:context:inputs', 'Usage: mc_context(''is_issued'', digest).');
        ctx = issued_registry('contains', varargin{1});
        return
    end
    c = mc_constants();
    root = mc_repo_root();
    ctx.kind = kind;
    ctx.pBL  = baseline_config();
    W = mc_load_apf_winner(ctx.pBL);
    ctx.apf  = struct('theta', W.theta, 'gains', W.gains);
    ctx.runner_override = struct();
    ctx.inputs = struct();

    switch kind
        case 'scientific'
            assert(~mc_rng_sentinel('in_verification'), 'mc:context:verification_session', ...
                ['REFUSED: the verification suite has run in this MATLAB session; a ' ...
                 'scientific campaign may only start from a fresh process.']);
            assert(numel(varargin) == 1 && isstruct(varargin{1}), 'mc:context:inputs', ...
                'The scientific context needs the four authorising identities.');
            inputs = varargin{1};
            pre = mc_preflight('execution', inputs);
            assert(isequal(pre.authorised, true), 'mc:context:not_authorised', ...
                'REFUSED: the execution preflight did not pass.');
            ctx.inputs      = struct('protocol_sha256', inputs.protocol_sha256, ...
                                     'mc_source_aggregate', inputs.mc_source_aggregate, ...
                                     'mc_impl_commit', inputs.mc_impl_commit, ...
                                     'freeze_record_sha256', inputs.freeze_record_sha256);
            ctx.root        = mc_abs_path(fullfile(root, strrep(c.mc.dest_dir, '/', filesep), 'checkpoint'));
            ctx.Tsim        = c.design.Tsim;
            ctx.K_expected  = c.design.K;
            ctx.trial_ids   = 1:c.design.N_PHYSICAL;
            ctx.trials      = mc_trial_csv_read(fullfile(root, strrep(c.csv.path, '/', filesep)), ...
                                  c.design.N_PHYSICAL, pre.verified.trial_csv_sha256);
            ctx.binding     = mc_binding('SCIENTIFIC', pre);
            ctx.record_kind = 'SCIENTIFIC';

        case 'verification'
            assert(any(numel(varargin) == [4 5]), 'mc:context:inputs', ...
                'Usage: mc_context(''verification'', ckptRoot, Tsim, T, trialIds[, opts]).');
            [ckptRoot, Tsim, T, trialIds] = varargin{1:4};
            opts = struct();
            if numel(varargin) == 5 && isstruct(varargin{5}), opts = varargin{5}; end
            rootAbs = mc_abs_path(ckptRoot);
            assert(~strncmpi(rootAbs, [root filesep], numel(root) + 1) && ~strcmpi(rootAbs, root), ...
                'mc:context:verification_root', ...
                'REFUSED: a verification checkpoint root must lie outside the repository.');
            nSteps = Tsim / c.design.Ts;
            assert(isscalar(Tsim) && Tsim > 0 && Tsim <= 60 && abs(nSteps - round(nSteps)) < 1e-9, ...
                'mc:context:verification_horizon', ...
                'REFUSED: verification uses a short on-grid horizon, 0 < Tsim <= 60 s.');
            assert(isstruct(T) && any(strcmp(T.kind, {'FIXTURE', 'SYNTHETIC'})), ...
                'mc:context:verification_table', ...
                'REFUSED: verification may use only a FIXTURE or SYNTHETIC trial table.');
            assert(isnumeric(trialIds) && ~isempty(trialIds) && all(ismember(trialIds, T.trial_id)), ...
                'mc:context:trial_ids', 'trialIds must be rows of the fixture table.');
            ctx.root        = rootAbs;
            ctx.Tsim        = Tsim;
            ctx.K_expected  = round(nSteps);
            ctx.trial_ids   = sort(trialIds(:).');
            ctx.trials      = T;
            ctx.binding     = mc_binding('VERIFICATION');
            ctx.record_kind = 'VERIFICATION';
            if isfield(opts, 'runner_override') && isstruct(opts.runner_override)
                ctx.runner_override = opts.runner_override;
            end

        otherwise
            error('mc:context:kind', 'Unknown context kind ''%s''.', kind);
    end

    ctx.env  = struct('matlab_version', version, 'computer', computer, ...
                      'max_num_comp_threads', NaN, 'process', mc_process_identity(), 'shard_id', '');
    ctx.seal = struct('digest', mc_context_seal(ctx), 'issued_utc', mc_utc_now());
    issued_registry('register', ctx.seal.digest);
end

% =====================================================================
function out = issued_registry(action, digest)
% The seal digests issued by MC_CONTEXT in this session. LOCAL to this file: it
% is reachable only from the issuance code above and from the read-only
% 'is_issued' query. There is no removal action.
    persistent reg
    if isempty(reg), reg = {}; end
    switch action
        case 'register'
            if ~any(strcmp(reg, digest))
                reg{end+1} = digest;
            end
            out = true;
        case 'contains'
            out = ischar(digest) && any(strcmp(reg, digest));
    end
end

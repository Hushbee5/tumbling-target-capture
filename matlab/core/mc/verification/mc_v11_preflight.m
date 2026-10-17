function R = mc_v11_preflight(~)
% MC_V11_PREFLIGHT  Preflight in verification mode; scientific modes refuse (Sec. 11).
%   NON-SCIENTIFIC. The verification-mode preflight must pass every check it
%   can evaluate before the MC source is frozen - and never authorise.
%   BEFORE the source freeze, the generation and execution preflights must
%   refuse even the CURRENT state (worktree aggregate, HEAD), because HEAD
%   holds no src/mc and no freeze record or CSV exists - rejected by the
%   checks themselves, not by a placeholder. State-independent refusals use
%   inputs that can never be valid. The scientific trial-table generator and
%   the scientific campaign context are refused FIRST by the session firewall
%   (MC_RNG_SENTINEL), so this fixture stays safe after the source freeze and
%   when called on its own. The freeze-record parser contract is unit-tested
%   on a synthetic text.

    R.name = 'V11 preflight: verification mode passes, scientific modes refuse';
    ch = {};
    c = mc_constants();
    root = mc_repo_root();
    % Belt and braces: this fixture is safe even when called on its own, and even
    % after the MC source has been committed - the session firewall is raised
    % first, and no scientific entry point is ever called with inputs that
    % could be valid.
    mc_rng_sentinel('enter_verification');
    never = struct('protocol_sha256', c.protocol.sha256, ...
                   'mc_source_aggregate', repmat('0', 1, 64), ...    % can never be the aggregate
                   'mc_impl_commit', c.anchor.commit, ...            % holds no src/mc, ever
                   'freeze_record_sha256', repmat('0', 1, 64));

    P = mc_preflight('verification');
    for i = 1:numel(P.checks)
        k = P.checks(i);
        ch{end+1} = mc_vt_check(sprintf('verification preflight %s: %s', k.id, k.name), ...
            k.pass, k.detail); %#ok<AGROW>
    end
    ch{end+1} = mc_vt_check('verification mode never authorises', isequal(P.authorised, false));
    ch{end+1} = mc_vt_check('informational: src/mc aggregate of the working tree (MATLAB)', true, ...
        sprintf('%s over %d files', P.verified.mc_source_aggregate_worktree, ...
        numel(P.verified.mc_source_files)));

    % ---- the PREFLIGHT itself (it never generates or executes anything) -------
    % State-dependent: before the MC source is committed, even the CURRENT
    % worktree aggregate and HEAD must be refused, because HEAD holds no src/mc.
    head = mc_git(root, 'rev-parse HEAD');
    committed = ~isempty(mc_git(root, 'ls-files -- src/mc', true));
    cur = struct('protocol_sha256', c.protocol.sha256, ...
                 'mc_source_aggregate', P.verified.mc_source_aggregate_worktree, ...
                 'mc_impl_commit', head);
    if ~committed
        [ok, got] = mc_vt_throws(@() mc_preflight('generation', cur), 'mc:preflight:*');
        ch{end+1} = mc_vt_check('BEFORE source freeze: generation preflight refuses even the current state', ok, got);
        curE = cur;  curE.freeze_record_sha256 = repmat('0', 1, 64);
        [ok, got] = mc_vt_throws(@() mc_preflight('execution', curE), 'mc:preflight:*');
        ch{end+1} = mc_vt_check('BEFORE source/trial freeze: execution preflight refuses', ok, got);
    else
        ch{end+1} = mc_vt_check('state-dependent refusal not applicable: src/mc is committed', true, ...
            'informational (post-freeze state)');
    end
    % State-independent refusals, with inputs that can never be valid.
    [ok, got] = mc_vt_throws(@() mc_preflight('generation', rmfield(never, 'freeze_record_sha256')), ...
        'mc:preflight:*');
    ch{end+1} = mc_vt_check('generation preflight refuses a commit holding no src/mc and a zero aggregate', ...
        ok, got);
    n2 = never;  n2.mc_impl_commit = repmat('a', 1, 40);
    [ok, got] = mc_vt_throws(@() mc_preflight('generation', rmfield(n2, 'freeze_record_sha256')), ...
        'mc:preflight:*');
    ch{end+1} = mc_vt_check('generation preflight refuses a non-existent commit', ok, got);
    n3 = never;  n3.protocol_sha256 = repmat('0', 1, 64);
    [ok, got] = mc_vt_throws(@() mc_preflight('generation', rmfield(n3, 'freeze_record_sha256')), ...
        'mc:preflight:protocol_input');
    ch{end+1} = mc_vt_check('a protocol SHA-256 other than the frozen one is refused', ok, got);
    [ok, got] = mc_vt_throws(@() mc_preflight('execution', never), 'mc:preflight:*');
    ch{end+1} = mc_vt_check('execution preflight refuses never-valid identities', ok, got);
    [ok, got] = mc_vt_throws(@() mc_preflight('execution', rmfield(never, 'freeze_record_sha256')), ...
        'mc:preflight:inputs');
    ch{end+1} = mc_vt_check('execution preflight requires all four authorising identities', ok, got);

    % ---- scientific entry points: the session firewall refuses FIRST -------------
    [ok, got] = mc_vt_throws(@() mc_scientific_trial_table(rmfield(never, 'freeze_record_sha256')), ...
        'mc:rng:verification_session');
    ch{end+1} = mc_vt_check('the generation transaction is refused by the session firewall', ok, got);
    [ok, got] = mc_vt_throws(@() mc_scientific_trial_table(struct('mode', 'generation', ...
        'authorised', true)), 'mc:rng:verification_session');
    ch{end+1} = mc_vt_check('a forged "authorised" struct is refused by the session firewall', ok, got);
    [ok, got] = mc_vt_throws(@() mc_context('scientific', never), 'mc:context:verification_session');
    ch{end+1} = mc_vt_check('the scientific campaign context is refused by the session firewall', ok, got);
    ch{end+1} = mc_vt_check('the scientific stream was never approached (sentinel unset)', ...
        ~mc_rng_sentinel('query'));
    ch{end+1} = mc_vt_check('no canonical CSV and no results/task4/mc exist', ...
        ~isfile(fullfile(root, strrep(c.csv.path, '/', filesep))) ...
        && ~isfolder(fullfile(root, strrep(c.mc.dest_dir, '/', filesep))));
    [ok, got] = mc_vt_throws(@() mc_binding('SCIENTIFIC', struct('mode', 'execution', ...
        'authorised', false)), 'mc:binding:not_authorised');
    ch{end+1} = mc_vt_check('a scientific binding cannot be built without a passed preflight', ok, got);

    txt = sprintf(['# fixture\n```\ncanonical CSV path                results/task4/mc/task4_mc_trials.csv\n' ...
        'canonical CSV SHA-256             %s\nfrozen MC protocol SHA-256        %s\n' ...
        'MC-source aggregate               %s\nMC implementation commit SHA      %s\n' ...
        'seed                              116075   (RandStream ''mt19937ar'')\n' ...
        'N_PHYSICAL                        100\n' ...
        'mapping implementation file       src/mc/trials/mc_trial_mapping.m\n' ...
        'mapping implementation SHA-256    %s\n' ...
        'scientific method runs at freeze  ZERO\n```\n'], ...
        repmat('1', 1, 64), c.protocol.sha256, repmat('2', 1, 64), repmat('3', 1, 40), repmat('4', 1, 64));
    F = mc_freeze_record_parse(txt);
    ch{end+1} = mc_vt_check('freeze-record parser reads every declared identity', ...
        strcmp(F.csv_path, c.csv.path) && strcmp(F.csv_sha256, repmat('1', 1, 64)) ...
        && strcmp(F.protocol_sha256, c.protocol.sha256) && F.seed == 116075 ...
        && F.N_PHYSICAL == 100 && strcmp(F.mc_impl_commit, repmat('3', 1, 40)) ...
        && strcmp(F.mapping_file, 'src/mc/trials/mc_trial_mapping.m') ...
        && strcmp(F.mapping_sha256, repmat('4', 1, 64)) && strcmp(F.runs_at_freeze, 'ZERO'));
    dup = [txt sprintf('seed   999\n')];
    [ok, got] = mc_vt_throws(@() mc_freeze_record_parse(dup), 'mc:freeze:label');
    ch{end+1} = mc_vt_check('freeze-record parser refuses a repeated label', ok, got);
    [ok, got] = mc_vt_throws(@() mc_freeze_record_parse(strrep(txt, 'N_PHYSICAL', 'N_TRIALS')), ...
        'mc:freeze:label');
    ch{end+1} = mc_vt_check('freeze-record parser refuses a missing label', ok, got);
    R.checks = [ch{:}];
end

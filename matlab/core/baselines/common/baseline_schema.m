function rep = baseline_schema(art, method, metrics)
% BASELINE_SCHEMA  Validate a baseline artifact against protocol V11a-V11f.
%   rep = baseline_schema(art, method, metrics) checks the logging schema of one
%   artifact assembled by BASELINE_ARTIFACT. It raises nothing: every check is
%   reported, so a failing artifact can be inspected rather than lost.
%
%   metrics is the ACTUAL metric struct that was saved beside the artifact. It
%   is required because V11c is a claim about BOTH objects: psi1_body, psi2_body
%   and d_safe must be absent from the artifact AND from the metric struct. A
%   checker that only ever saw the artifact could not test the second half of
%   that clause, so it would be reporting a weaker property under the same name.
%
%   V11a  every field present with the EXACT frozen class and size, including
%         the nested method-specific blocks. The class test is exact: where the
%         schema says 'double', only a double passes. This is also deliberately
%         not a shallow "is it a struct" test - the frozen schema names the APF
%         decomposition and the solver-status fields individually, so each is
%         checked individually for presence, class and size.
%   V11b  BOTH preview and truth capture-point identities stored AND a VALID
%         V2c audit block (Ep, Ev and their argmax indices and times). Presence
%         alone is not a pass.
%   V11c  psi1_body, psi2_body and d_safe are ABSENT from the artifact and from
%         the metric struct
%   V11d  DIAGNOSTIC_ONLY is used for exactly one thing - the terminal a_cp_ff
%         column - and that column is NOT an element of a_cp_ff_ctrl
%   V11e  no field is named or aliased 'alpha'
%   V11f  every field name is a valid MATLAB identifier (isvarname == true)
%
%   rep fields: v11a..v11f (each with pass and detail), pass, missing, wrong,
%   bad_names, alpha_paths, forbidden_paths, diagnostic_only_paths.

    if nargin < 2 || isempty(method)
        if isfield(art, 'method'), method = art.method; else, method = ''; end
    end
    if nargin < 3, metrics = []; end

    K  = size(art.u_applied, 2);
    ns = numel(art.t);

    % ---- V11a: presence, class and size ------------------------------------
    req = { ...
      't',                     'double', [1 ns]
      'x0',                    'double', [6 1]
      'config',                'struct', []
      'run_identity',          'struct', []
      'meta',                  'struct', []
      'git_head',              'char',   []
      'stamp',                 'char',   []
      'X',                     'double', [6 ns]
      'v',                     'double', [3 ns]
      'u_cmd',                 'double', [3 K]
      'u_applied',             'double', [3 K]
      'qT',                    'double', [4 ns]
      'wT',                    'double', [3 ns]
      'p_cp_preview',          'double', [3 ns]
      'v_cp_preview',          'double', [3 ns]
      'a_cp_ff_ctrl',          'double', [3 K]
      'a_cp_ff_terminal',      'double', [3 1]
      'a_cp_ff_terminal_tag',  'char',   []
      'p_cp_truth',            'double', [3 ns]
      'v_cp_truth',            'double', [3 ns]
      'rho_truth',             'double', [1 ns]
      'clearance',             'double', [1 ns]
      'h_body',                'double', [1 ns]
      'inter_t',               'double', [1 9*K]
      'inter_h_body',          'double', [1 9*K]
      'inter_r',               'double', [3 9*K]
      'DeltaV_cumulative',     'double', [1 K]
      'DeltaV_to_proximity',   'double', [1 1]
      'DeltaV_full',           'double', [1 1]
      'kstar',                 'double', []
      't_kstar',               'double', [1 1]
      'rho_dot_truth_kstar',   'double', [1 1]
      't_viol',                'double', [1 1]
      'K_safe_count',          'double', [1 1]
      'p_safe',                'double', [1 1]
      'I_sel_count',           'double', [1 1]
      'empty_selection',       'logical',[1 1]
      'utilisation',           'struct', []
      'protocol_sha',          'char',   []
      'baseline_aggregate_sha','char',   []
      'artifact_status',       'char',   []
      'note',                  'char',   []
      };

    [missing, wrong] = check_fields(art, req, 'art');

    % kstar is [] when no proximity milestone was reached, and a scalar
    % otherwise. Both are correct; only a wrong SHAPE is a defect.
    if isfield(art, 'kstar') && ~isempty(art.kstar) && ~isscalar(art.kstar)
        wrong{end+1} = 'art.kstar: expected [] or a scalar';
    end

    % ---- V11a: the NESTED method-specific blocks ---------------------------
    switch method
        case 'nominal_mpc'
            if ~isfield(art, 'mpc_solver_status')
                missing{end+1} = 'mpc_solver_status';
            else
                ssReq = { ...
                  'exitflag',   'double', [1 K]
                  'solve_time', 'double', [1 K]
                  'cost',       'double', [1 K]
                  'n_failed',   'double', [1 1]
                  'note',       'char',   [] };
                [m2, w2] = check_fields(art.mpc_solver_status, ssReq, ...
                                        'mpc_solver_status');
                missing = [missing, m2];  wrong = [wrong, w2];
            end
            if isfield(art, 'apf')
                wrong{end+1} = 'apf: present on a nominal-MPC artifact';
            end

        case 'apf'
            if ~isfield(art, 'apf')
                missing{end+1} = 'apf';
            else
                a = art.apf;
                apfReq = { ...
                  'c1',                         'double',  [3 K]
                  'c2',                         'double',  [3 K]
                  'c3',                         'double',  [3 K]
                  'c4',                         'double',  [3 K]
                  'clip_flags',                 'logical', [1 K]
                  'clip_per_axis',              'logical', [3 K]
                  'direction_distortion_angle', 'double',  [1 K]
                  'excluded_angle_count',       'double',  [1 1]
                  'theta',                      'struct',  []
                  'derived',                    'struct',  []
                  'r1_margin',                  'double',  [1 1]
                  'r1_stationary_locations',    'double',  [] };
                [m2, w2] = check_fields(a, apfReq, 'apf');
                missing = [missing, m2];  wrong = [wrong, w2];

                if isfield(a, 'theta')
                    thReq = {'omega_n','double',[1 1]; 'zeta','double',[1 1]; ...
                             'beta','double',[1 1];    'kappa','double',[1 1]};
                    [m3, w3] = check_fields(a.theta, thReq, 'apf.theta');
                    missing = [missing, m3];  wrong = [wrong, w3];
                end
                if isfield(a, 'derived')
                    dvReq = {'k_a','double',[1 1]; 'k_d','double',[1 1]; ...
                             'k_r','double',[1 1]};
                    [m3, w3] = check_fields(a.derived, dvReq, 'apf.derived');
                    missing = [missing, m3];  wrong = [wrong, w3];
                end
                % r1_stationary_locations is REQUIRED to be a non-empty row when
                % the margin is negative, and REQUIRED to be empty otherwise.
                % Protocol Sec. 6.4 logs locations only when r1_margin < 0.
                if isfield(a, 'r1_margin') && isfield(a, 'r1_stationary_locations')
                    loc = a.r1_stationary_locations;
                    if a.r1_margin < 0 && isempty(loc)
                        wrong{end+1} = ['apf.r1_stationary_locations: empty ' ...
                            'while r1_margin < 0, when locations are required'];
                    elseif a.r1_margin >= 0 && ~isempty(loc)
                        wrong{end+1} = ['apf.r1_stationary_locations: non-empty ' ...
                            'while r1_margin >= 0, when no location exists'];
                    elseif ~isempty(loc) && size(loc, 1) ~= 1
                        wrong{end+1} = 'apf.r1_stationary_locations: expected a row vector';
                    end
                end
            end
            if isfield(art, 'mpc_solver_status')
                wrong{end+1} = 'mpc_solver_status: present on an APF artifact';
            end
    end

    rep.v11a = check(isempty(missing) && isempty(wrong), ...
        sprintf('%d missing {%s}; %d wrong {%s}', numel(missing), ...
                strjoin_or(missing, 'none'), numel(wrong), strjoin_or(wrong, 'none')));
    rep.missing = missing;
    rep.wrong   = wrong;

    % ---- V11b: both identities AND a VALID V2c audit block -----------------
    hasBoth = isfield(art, 'config') && isfield(art.config, 'target_identity') ...
        && isfield(art.config.target_identity, 'truth') ...
        && isfield(art.config.target_identity, 'preview');
    [okV2c, v2cDetail] = check_v2c(art);
    rep.v11b = check(hasBoth && okV2c, sprintf(...
        'both target identities stored = %d; V2c audit: %s', hasBoth, v2cDetail));
    rep.v2c_attached = okV2c;

    % ---- V11c: forbidden fields absent from artifact AND metric struct -----
    forbidden = {'psi1_body', 'psi2_body', 'd_safe'};
    hitsArt = field_paths(art, forbidden, false, 'art');
    if isempty(metrics)
        hitsMet = {};
        metNote = 'metric struct NOT SUPPLIED - the V11c claim about it is untested';
        metOk   = false;
    else
        hitsMet = field_paths(metrics, forbidden, false, 'metrics');
        metNote = sprintf('metric struct inspected (%d fields)', ...
                          numel(fieldnames(metrics)));
        metOk   = true;
    end
    hits = [hitsArt, hitsMet];
    rep.v11c = check(isempty(hits) && metOk, ...
        sprintf('%s; hits: %s', metNote, strjoin_or(hits, 'none present')));
    rep.forbidden_paths = hits;

    % ---- V11d: DIAGNOSTIC_ONLY used for exactly one thing ------------------
    doPaths = diagnostic_only_paths(art, 'art');
    okTag  = isscalar(doPaths) && strcmp(doPaths{1}, 'art.a_cp_ff_terminal_tag');
    okCols = size(art.a_cp_ff_ctrl, 2) == K;
    rep.v11d = check(okTag && okCols, sprintf(...
        'DIAGNOSTIC_ONLY at {%s}; a_cp_ff_ctrl has %d columns (K = %d)', ...
        strjoin_or(doPaths, 'nowhere'), size(art.a_cp_ff_ctrl, 2), K));
    rep.diagnostic_only_paths = doPaths;

    % ---- V11e: no field named or aliased 'alpha' ---------------------------
    alphaHits = field_paths(art, {'alpha'}, true, 'art');
    if ~isempty(metrics)
        alphaHits = [alphaHits, field_paths(metrics, {'alpha'}, true, 'metrics')];
    end
    rep.v11e = check(isempty(alphaHits), strjoin_or(alphaHits, 'no alpha field'));
    rep.alpha_paths = alphaHits;

    % ---- V11f: every field name is a valid MATLAB identifier ---------------
    badNames = invalid_names(art, 'art');
    if ~isempty(metrics)
        badNames = [badNames, invalid_names(metrics, 'metrics')];
    end
    rep.v11f = check(isempty(badNames), strjoin_or(badNames, 'all valid'));
    rep.bad_names = badNames;

    rep.pass = rep.v11a.pass && rep.v11b.pass && rep.v11c.pass ...
            && rep.v11d.pass && rep.v11e.pass && rep.v11f.pass;
    rep.method = method;
end

% =====================================================================
function [missing, wrong] = check_fields(s, req, prefix)
% Presence, EXACT class and size for one flat field specification.
%
% THE CLASS TEST IS EXACT. An earlier spelling accepted any numeric class where
% the frozen schema says 'double':
%     ~isa(val, cls) && ~(strcmp(cls, 'double') && isnumeric(val))
% That relaxation would have passed a single, an int32 or a logical wherever
% 'double' is required, so a silently downcast history could reach the metric
% and ranking layer while the schema reported a clean pass. The frozen schema
% names one class per field, and only that class passes.
    missing = {};
    wrong   = {};
    for i = 1:size(req, 1)
        nm = req{i, 1};
        if ~isfield(s, nm)
            missing{end+1} = [prefix '.' nm];                       %#ok<AGROW>
            continue
        end
        val = s.(nm);
        cls = req{i, 2};
        if ~isa(val, cls)
            wrong{end+1} = sprintf('%s.%s: class %s, expected exactly %s', ...
                prefix, nm, class(val), cls);                       %#ok<AGROW>
            continue
        end
        sz = req{i, 3};
        if ~isempty(sz) && ~isequal(size(val), sz)
            wrong{end+1} = sprintf('%s.%s: size %s, expected %s', prefix, nm, ...
                mat2str(size(val)), mat2str(sz));                   %#ok<AGROW>
        end
    end
end

% =====================================================================
function [ok, detail] = check_v2c(art)
% V11b requires a VALID audit block, not merely a field called v2c. Every
% quantity the protocol names is checked for presence, class and finiteness.
    if ~isfield(art, 'meta') || ~isfield(art.meta, 'v2c')
        ok = false;
        detail = 'meta.v2c ABSENT';
        return
    end
    v = art.meta.v2c;
    need = {'Ep', 'Ev', 'argmax_index_p', 'argmax_t_p', ...
            'argmax_index_v', 'argmax_t_v', 'n_samples'};
    miss = need(~isfield(v, need));
    if ~isempty(miss)
        ok = false;
        detail = sprintf('meta.v2c incomplete, missing {%s}', strjoin(miss, ', '));
        return
    end
    vals = [v.Ep, v.Ev, v.argmax_index_p, v.argmax_t_p, ...
            v.argmax_index_v, v.argmax_t_v, v.n_samples];
    if ~all(isnumeric(vals)) || ~all(isfinite(vals))
        ok = false;
        detail = 'meta.v2c present but carries non-finite or non-numeric values';
        return
    end
    if v.n_samples < 2
        ok = false;
        detail = sprintf('meta.v2c audited only %d sample(s)', v.n_samples);
        return
    end
    ok = true;
    detail = sprintf(['Ep = %.6e m at index %d (t = %.4f s), Ev = %.6e m/s at ' ...
        'index %d (t = %.4f s), over %d samples'], v.Ep, v.argmax_index_p, ...
        v.argmax_t_p, v.Ev, v.argmax_index_v, v.argmax_t_v, v.n_samples);
end

% =====================================================================
function c = check(ok, detail)
    c.pass   = logical(ok);
    c.detail = detail;
end

% =====================================================================
function s = strjoin_or(c, fallback)
    if isempty(c), s = fallback; else, s = strjoin(c(:).', ', '); end
end

% =====================================================================
function hits = field_paths(s, names, alsoSubstring, rootName)
% Recursive search for field NAMES. With alsoSubstring true, a name CONTAINING
% one of the targets also counts - that is what "named or aliased 'alpha'"
% means: alpha_set, eps_alpha and alphaBand must all be caught, not just an
% exact match.
    hits = walk(s, rootName);
    function out = walk(x, path)
        out = {};
        if isstruct(x)
            for e = 1:numel(x)
                fn = fieldnames(x(e));
                for i = 1:numel(fn)
                    nm = fn{i};
                    hit = false;
                    for q = 1:numel(names)
                        if alsoSubstring
                            hit = hit || contains(lower(nm), lower(names{q}));
                        else
                            hit = hit || strcmpi(nm, names{q});
                        end
                    end
                    sub = [path '.' nm];
                    if hit, out{end+1} = sub; end                  %#ok<AGROW>
                    out = [out, walk(x(e).(nm), sub)];             %#ok<AGROW>
                end
            end
        elseif iscell(x)
            for i = 1:numel(x)
                out = [out, walk(x{i}, sprintf('%s{%d}', path, i))]; %#ok<AGROW>
            end
        end
    end
end

% =====================================================================
function out = diagnostic_only_paths(x, path)
% Every char field whose value is exactly 'DIAGNOSTIC_ONLY'.
    out = {};
    if ischar(x)
        if strcmp(strtrim(x), 'DIAGNOSTIC_ONLY'), out = {path}; end
        return
    end
    if isstruct(x)
        for e = 1:numel(x)
            fn = fieldnames(x(e));
            for i = 1:numel(fn)
                out = [out, diagnostic_only_paths(x(e).(fn{i}), ...
                       [path '.' fn{i}])];                         %#ok<AGROW>
            end
        end
    elseif iscell(x)
        for i = 1:numel(x)
            out = [out, diagnostic_only_paths(x{i}, ...
                   sprintf('%s{%d}', path, i))];                   %#ok<AGROW>
        end
    end
end

% =====================================================================
function out = invalid_names(x, path)
% Recursive isvarname check over every field name.
    out = {};
    if isstruct(x)
        for e = 1:numel(x)
            fn = fieldnames(x(e));
            for i = 1:numel(fn)
                sub = [path '.' fn{i}];
                if ~isvarname(fn{i})
                    out{end+1} = sub;                              %#ok<AGROW>
                end
                out = [out, invalid_names(x(e).(fn{i}), sub)];     %#ok<AGROW>
            end
        end
    elseif iscell(x)
        for i = 1:numel(x)
            out = [out, invalid_names(x{i}, sprintf('%s{%d}', path, i))]; %#ok<AGROW>
        end
    end
end

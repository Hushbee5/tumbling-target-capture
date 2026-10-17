function res = v10_nominal_mpc_path(p, V, runMpc)
% V10_NOMINAL_MPC_PATH  V10: the nominal-MPC baseline is the intended ablation.
%
%   V10a COMPLETE-PATH INCLUSION
%        The union of the static closures of { simulate_baseline setup ,
%        controller_nominal_mpc } restricted to the nominal-MPC branch MUST
%        CONTAIN: mpc_condensed , capture_reference_preview , mpc_step
%        controller_nominal_mpc.m is NOT required to transitively contain
%        mpc_condensed, since M = mpc_condensed(p, N) is legitimately built once
%        in the simulator's setup.
%
%   V10b COMPLETE-PATH EXCLUSION
%        MUST CONTAIN NONE OF: cbf_qp_two_row , cbf_qp_filter , capture_barrier ,
%        handoff_detector , cl_records , cl_estimator_init , cl_estimator_step ,
%        task4_ic_admissibility , f5_hcap_scan , task4_classify
%        Runtime proof by the same shadowing + precedence-assertion mechanism as
%        V9b, with THESE stubs installed but NOT quadprog, which the MPC
%        legitimately uses.
%
%   V10c COMMAND IDENTITY
%        PASS isequal(u_applied, u_mpc) at EVERY control step of the Tsim_V run.
%        No post-clip is applied: M.lb/M.ub already enforce the identical box.
%
%   V10d BOX IDENTITY
%        PASS M.lb == -u_max*ones(3N,1) and M.ub == +u_max*ones(3N,1)
%
%   V10e SOLVER STATUS LOGGING
%        PASS the frozen mpc_step solver/info status is recorded at EVERY
%        control step and is present in the artifact schema.
%        PASS NO baseline-specific solver fallback, retry, warm-start override
%        or option change is introduced anywhere. Static inspection confirms the
%        frozen mpc_step call path is used unmodified.

    EXCLUDED_10 = {'cbf_qp_two_row', 'cbf_qp_filter', 'capture_barrier', ...
                   'handoff_detector', 'cl_records', 'cl_estimator_init', ...
                   'cl_estimator_step', 'task4_ic_admissibility', ...
                   'f5_hcap_scan', 'task4_classify'};
    REQUIRED_10 = {'mpc_condensed', 'capture_reference_preview', 'mpc_step'};

    checks = struct('name', {}, 'pass', {}, 'detail', {});

    % ---- the union closure --------------------------------------------------
    targets = {'simulate_baseline.m', 'controller_nominal_mpc.m'};
    names   = {};
    for i = 1:numel(targets)
        f = which(targets{i});
        assert(~isempty(f), 'v10:resolve', '%s is not on the path.', targets{i});
        fl = matlab.codetools.requiredFilesAndProducts(f);
        for q = 1:numel(fl)
            [~, nm] = fileparts(fl{q});
            names{end+1} = nm;                                 %#ok<AGROW>
        end
    end
    names = unique(names);

    % ---- V10a ---------------------------------------------------------------
    missing = setdiff(REQUIRED_10, names);
    checks(end+1) = baseline_check('V10a complete-path inclusion of the frozen MPC layers', ...
        isempty(missing), ['union closure of {%s} has %d file(s); missing ' ...
        'required: {%s}. controller_nominal_mpc is NOT required to ' ...
        'transitively contain mpc_condensed: M is built once in the simulator ' ...
        'setup.'], strjoin(targets, ', '), numel(names), strjoin_or(missing, 'none'));

    % ---- V10b static --------------------------------------------------------
    hits = intersect(names, EXCLUDED_10);
    checks(end+1) = baseline_check('V10b complete-path exclusion (static)', ...
        isempty(hits), 'excluded-name hits: {%s}', strjoin_or(hits, 'none'));

    % ---- V10b runtime, by shadowing WITHOUT quadprog -----------------------
    try
        fx = baseline_shadow_fixture(EXCLUDED_10);  %#ok<NASGU>
        runOpt = struct('method', 'nominal_mpc', 'x0', V.VP(:, 1), 'Tsim', V.Tsim_V);
        runV = simulate_baseline(p, runOpt);
        ok10b = runV.completed;
        detail = sprintf(['all %d forbidden names resolved to the temporary ' ...
            'PLAIN stub directory before the run (quadprog deliberately NOT ' ...
            'stubbed: the MPC legitimately uses it); the nominal-MPC ' ...
            'Tsim_V = %g s run then COMPLETED (K = %d) with no stub error'], ...
            numel(EXCLUDED_10), V.Tsim_V, runV.K);
        clear fx
    catch err
        ok10b  = false;
        detail = sprintf('%s: %s', err.identifier, err.message);
    end
    checks(end+1) = baseline_check('V10b nominal-MPC runtime exclusion by path shadowing', ...
        ok10b, '%s', detail);

    % ---- V10c ---------------------------------------------------------------
    okC = isequal(runMpc.u_applied, runMpc.u_cmd);
    checks(end+1) = baseline_check('V10c isequal(u_applied, u_mpc) at every control step', ...
        okC, ['bitwise identical over %d control steps; no post-clip is ' ...
        'applied because M.lb/M.ub already enforce the identical box'], runMpc.K);

    % ---- V10d ---------------------------------------------------------------
    N    = p.bl.N;
    M    = mpc_condensed(p, N);
    umax = p.chaser.u_max;
    okD  = isequal(M.lb, -umax*ones(3*N, 1)) && isequal(M.ub, umax*ones(3*N, 1));
    checks(end+1) = baseline_check('V10d box identity M.lb/M.ub == -/+ u_max*ones(3N,1)', ...
        okD, 'N = %d, u_max = %g; lb range [%g %g], ub range [%g %g], 3N = %d', ...
        N, umax, min(M.lb), max(M.lb), min(M.ub), max(M.ub), 3*N);

    % ---- V10e : logging -----------------------------------------------------
    ss = runMpc.mpc_solver_status;
    okLog = isfield(ss, 'exitflag') && numel(ss.exitflag) == runMpc.K ...
         && all(~isnan(ss.exitflag));
    checks(end+1) = baseline_check('V10e solver status recorded at EVERY control step', ...
        okLog, ['%d exitflag entries for %d control steps; %d step(s) reported ' ...
        'a failed solve'], numel(ss.exitflag), runMpc.K, ss.n_failed);

    % ---- V10e : static inspection of the call path -------------------------
    src  = fileread(which('controller_nominal_mpc.m'));
    code = strip_comments(src);
    forbiddenTokens = {'optimoptions', 'quadprog', 'U_warm', 'optimset'};
    found = {};
    for i = 1:numel(forbiddenTokens)
        if contains(code, forbiddenTokens{i})
            found{end+1} = forbiddenTokens{i};                  %#ok<AGROW>
        end
    end
    nCalls = numel(regexp(code, 'mpc_step\s*\(', 'start'));
    % The frozen signature is mpc_step(x, Pref, Vref, M, p); a sixth argument
    % would be a warm-start override, which V10e forbids.
    hasSixth = ~isempty(regexp(code, ...
        'mpc_step\s*\([^;]*,[^;]*,[^;]*,[^;]*,[^;]*,[^;]*\)', 'once'));
    okStatic = isempty(found) && nCalls == 1 && ~hasSixth;
    checks(end+1) = baseline_check('V10e no baseline-specific solver behaviour (static)', ...
        okStatic, ['forbidden tokens found: {%s}; mpc_step call sites: %d; ' ...
        'warm-start argument present: %d. The frozen mpc_step call path is used ' ...
        'unmodified, with no fallback, retry, warm-start override or option ' ...
        'change.'], strjoin_or(found, 'none'), nCalls, hasSixth);

    res.name     = 'V10 - nominal-MPC path inclusion, exclusion and identity';
    res.checks   = checks;
    res.pass     = all([checks.pass]);
    res.closure  = names;
    res.excluded = EXCLUDED_10;
    res.required = REQUIRED_10;
end

% =====================================================================
function code = strip_comments(src)
% Remove whole-line and trailing MATLAB comments so that a forbidden token
% mentioned in the documentation is not mistaken for a call. Deliberately
% simple: it does not need to handle transposes or strings containing '%',
% because a false POSITIVE here would only make the test stricter.
    lines = regexp(src, '\r?\n', 'split');
    keep  = cell(1, numel(lines));
    for i = 1:numel(lines)
        L = lines{i};
        q = strfind(L, '%');
        if ~isempty(q), L = L(1:q(1)-1); end
        keep{i} = L;
    end
    code = strjoin(keep, newline);
end

% =====================================================================
function s = strjoin_or(c, fallback)
    if isempty(c), s = fallback; else, s = strjoin(c(:).', ', '); end
end

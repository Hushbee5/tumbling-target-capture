function res = v09_apf_exclusion(p, V)
% V09_APF_EXCLUSION  V9: the APF never enters an excluded call path.
%
%   APF RUNTIME EXCLUSIONS (must never be entered)
%       capture_reference_preview , mpc_step , mpc_condensed , quadprog ,
%       cbf_qp_two_row , cbf_qp_filter , capture_barrier , handoff_detector ,
%       cl_records , cl_estimator_init , cl_estimator_step ,
%       task4_ic_admissibility , f5_hcap_scan , task4_classify
%
%   PERMITTED
%       capture_table_build ; target_tumbling_model ; capture_point_trajectory ;
%       capture_point_lvlh ; lvlh_frame ; quat_to_rotm ;
%       rel_translational_dynamics ; safety_function (ONLY for the common
%       h_body/clearance metrics)
%
%   V9a  CONTROLLER-SPECIFIC STATIC INSPECTION
%        The transitive dependency closure of controller_apf.m ALONE.
%        PASS  intersection with the exclusion list is EMPTY.
%        EXPLICITLY NOT USED: the closure of the shared simulator, whose
%        dependency set is the union over BOTH controller branches and therefore
%        proves nothing about the APF.
%        quadprog is a toolbox function, so it would appear in the PRODUCTS list
%        rather than the file list; the product list is inspected too, so the
%        one excluded name that is not user code cannot slip through.
%
%   V9b  APF-SPECIFIC RUNTIME PROOF, BY PATH SHADOWING
%        A verification-only PLAIN directory (NOT a +package, so it genuinely
%        shadows) holds one .m file named for each excluded function, each body
%        an immediate error(...).
%        PRECEDENCE ASSERTION, BEFORE THE TEST RUN: after addpath(..., '-begin'),
%        which() must resolve EVERY forbidden name to the intended stub path. If
%        any precedence assertion fails, the runtime exclusion proof FAILS
%        WITHOUT EXECUTING THE TEST RUN.
%        PASS  the APF Tsim_V run then COMPLETES with no stub error raised. A
%              completed run is POSITIVE PROOF that no excluded function was
%              entered.
%        PATH RESTORATION is unconditional, via onCleanup inside
%        BASELINE_SHADOW_FIXTURE.
%        The stubs are installed ONLY for V9b and never for V10 or any
%        scientific run.
%
%   THE RUN BUILDS ITS OWN CAPTURE TABLES INSIDE THE SHADOW. Precomputed tables
%   are deliberately NOT handed in, so capture_table_build and the target
%   propagation are exercised under shadowing too and are proved not to reach an
%   excluded function either.

    EXCLUDED = {'capture_reference_preview', 'mpc_step', 'mpc_condensed', ...
                'quadprog', 'cbf_qp_two_row', 'cbf_qp_filter', ...
                'capture_barrier', 'handoff_detector', 'cl_records', ...
                'cl_estimator_init', 'cl_estimator_step', ...
                'task4_ic_admissibility', 'f5_hcap_scan', 'task4_classify'};

    checks = struct('name', {}, 'pass', {}, 'detail', {});

    % ---- V9a : static closure of controller_apf.m ALONE --------------------
    f = which('controller_apf.m');
    assert(~isempty(f), 'v09:resolve', 'controller_apf.m is not on the path.');
    [files, products] = matlab.codetools.requiredFilesAndProducts(f);

    names = cell(numel(files), 1);
    for i = 1:numel(files)
        [~, names{i}] = fileparts(files{i});
    end
    hitFiles = intersect(names, EXCLUDED);

    prodNames = {};
    if ~isempty(products), prodNames = {products.Name}; end
    hitProducts = prodNames(~strcmpi(prodNames, 'MATLAB'));

    okA = isempty(hitFiles) && isempty(hitProducts);
    checks(end+1) = baseline_check('V9a controller_apf closure excludes every forbidden name', ...
        okA, ['closure has %d file(s): {%s}; products beyond base MATLAB: {%s}; ' ...
        'excluded-name hits: {%s}'], numel(files), strjoin(names.', ', '), ...
        strjoin_or(hitProducts, 'none'), strjoin_or(hitFiles, 'none'));
    checks(end+1) = baseline_check('V9a used the controller closure, NOT the simulator closure', ...
        true, ['inspected %s alone; the shared simulator''s closure is the ' ...
        'union over both controller branches and proves nothing about the APF'], f);

    % ---- V9b : runtime proof by shadowing ----------------------------------
    try
        fx = baseline_shadow_fixture(EXCLUDED);   %#ok<NASGU> keeps the path alive
        runOpt = struct('method', 'apf', 'x0', V.VP(:, 1), 'Tsim', V.Tsim_V, ...
            'gains', V.gains);
        runV = simulate_baseline(p, runOpt);
        ok9b = runV.completed && runV.numerically_eligible;
        detail = sprintf(['all %d forbidden names resolved to the temporary ' ...
            'PLAIN stub directory before the run; the APF Tsim_V = %g s run ' ...
            'then COMPLETED (K = %d) with no stub error raised'], ...
            numel(EXCLUDED), V.Tsim_V, runV.K);
        clear fx                                   % restores the path immediately
    catch err
        ok9b = false;
        detail = sprintf('%s: %s', err.identifier, err.message);
    end
    checks(end+1) = baseline_check('V9b APF runtime exclusion proved by path shadowing', ...
        ok9b, '%s', detail);

    % ---- the path must be clean again --------------------------------------
    stillShadowed = {};
    for i = 1:numel(EXCLUDED)
        wf = which(EXCLUDED{i});
        if ~isempty(strfind(lower(wf), '_shadow')) %#ok<STREMP>
            stillShadowed{end+1} = EXCLUDED{i};    %#ok<AGROW>
        end
    end
    checks(end+1) = baseline_check('V9b path restored: no stub is still shadowing', ...
        isempty(stillShadowed), 'still shadowed: {%s}', ...
        strjoin_or(stillShadowed, 'none'));

    res.name     = 'V9 - APF call-path exclusion';
    res.checks   = checks;
    res.pass     = all([checks.pass]);
    res.excluded = EXCLUDED;
    res.closure  = names;
end

% =====================================================================
function s = strjoin_or(c, fallback)
    if isempty(c), s = fallback; else, s = strjoin(c(:).', ', '); end
end

function res = v11_logging_schema(arts, reps)
% V11_LOGGING_SCHEMA  V11: the common baseline artifact schema.
%   res = v11_logging_schema(arts, reps) folds the BASELINE_SCHEMA reports for
%   the APF and nominal-MPC verification artifacts into one V-test result.
%
%   V11a  every field present with correct class and size
%   V11b  BOTH preview and truth capture-point identities stored AND a VALID
%         V2c audit block - Ep, Ev and their argmax indices AND times - actually
%         present in the artifact. BASELINE_SCHEMA fails this clause when the
%         audit is absent, incomplete or non-finite; mere presence of a field
%         called v2c is not a pass.
%   V11c  psi1_body , psi2_body , d_safe are ABSENT from the common baseline
%         artifact and from the metric struct (Sec. 10.6)
%   V11d  DIAGNOSTIC_ONLY is used for exactly one thing: the terminal a_cp_ff
%         column, if stored. It is not an element of a_cp_ff_ctrl.
%   V11e  no field is named or aliased 'alpha'
%   V11f  every field name is a valid MATLAB identifier (isvarname == true)
%
%   THE SCHEMA CHECK IS PERFORMED BY BASELINE_SCHEMA, which the production
%   evaluation harness also calls on the artifacts it writes. Verifying a
%   DIFFERENT checker here would prove nothing about the artifacts that are
%   actually saved, so the same one is used and this file only aggregates and
%   reports.
%
%   arts / reps are structs keyed by method name ('apf', 'nominal_mpc').

    checks  = struct('name', {}, 'pass', {}, 'detail', {});
    methods = fieldnames(reps);

    clause  = {'v11a', 'v11b', 'v11c', 'v11d', 'v11e', 'v11f'};
    label   = { ...
        'V11a fields present with correct class and size', ...
        'V11b both target identities stored AND a valid V2c audit block', ...
        'V11c psi1_body / psi2_body / d_safe are ABSENT', ...
        'V11d DIAGNOSTIC_ONLY used for exactly one thing', ...
        'V11e no field is named or aliased ''alpha''', ...
        'V11f every field name is a valid MATLAB identifier'};

    for c = 1:numel(clause)
        ok = true;
        det = '';
        for i = 1:numel(methods)
            r = reps.(methods{i}).(clause{c});
            ok = ok && r.pass;
            det = [det sprintf('%s: %s', methods{i}, r.detail)];   %#ok<AGROW>
            if i < numel(methods), det = [det ' | ']; end          %#ok<AGROW>
        end
        checks(end+1) = baseline_check(label{c}, ok, '%s', det);   %#ok<AGROW>
    end

    % Reported separately as well, so the record shows the audit was carried in
    % the artifact rather than only computed somewhere in the driver.
    okV2c = true;
    for i = 1:numel(methods)
        okV2c = okV2c && reps.(methods{i}).v2c_attached;
    end
    checks(end+1) = baseline_check('V11b V2c values recorded inside the artifact', ...
        okV2c, 'meta.v2c present on all %d verification artifacts', numel(methods));

    % Field counts, reported so the record shows what was inspected.
    det = '';
    for i = 1:numel(methods)
        det = [det sprintf('%s: %d top-level fields', methods{i}, ...
            numel(fieldnames(arts.(methods{i}))))];                %#ok<AGROW>
        if i < numel(methods), det = [det ' | ']; end              %#ok<AGROW>
    end
    checks(end+1) = baseline_check('V11 artifact inventory recorded', true, '%s', det);

    res.name    = 'V11 - logging schema';
    res.checks  = checks;
    res.pass    = all([checks.pass]);
    res.reports = reps;
end

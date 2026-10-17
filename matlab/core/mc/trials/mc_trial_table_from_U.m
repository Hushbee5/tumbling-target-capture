function T = mc_trial_table_from_U(U, kind)
% MC_TRIAL_TABLE_FROM_U  Derive every physical trial row from a 15 x n draw matrix.
%   T = mc_trial_table_from_U(U, kind) applies MC_TRIAL_MAPPING to each column
%   of U in increasing trial order, in ONE pass, and stores the 15 raw draws
%   beside the derived fields (protocol Sec. 3.4). It draws nothing itself.
%
%   kind is a PROVENANCE LABEL ONLY: 'FIXTURE' | 'SYNTHETIC' | 'DERIVED'. It
%   authorises nothing anywhere; in particular 'SCIENTIFIC' is refused
%   ('mc:trials:kind'), and no writer in src/mc accepts a caller-supplied table
%   at a protected destination (MC_TRIAL_CSV_WRITE, MC_ATOMIC_WRITE).
%
%   COLLISION RULE (Sec. 3.4). If any derived x0 equals the historical
%   evaluation initial condition [0;-10;0;0;0;0], generation STOPS with
%   'mc:trials:eval_ic_collision' and nothing is resampled. The test is
%   ISEQUAL (value equality), at least as strict as bit equality.

    c = mc_constants();
    if nargin < 2 || isempty(kind), kind = 'DERIVED'; end
    assert(any(strcmp(kind, {'FIXTURE', 'SYNTHETIC', 'DERIVED'})), 'mc:trials:kind', ...
        'Table kind ''%s'' is not a permitted label (FIXTURE | SYNTHETIC | DERIVED).', kind);
    assert(isa(U, 'double') && isreal(U) && ismatrix(U) && size(U, 1) == c.design.n_draws ...
        && size(U, 2) >= 1, 'mc:trials:U', 'U must be a real double 15 x n matrix.');
    assert(all(U(:) > 0 & U(:) < 1), 'mc:trials:draw_range', ...
        'Every draw must lie in the open interval (0, 1).');

    n = size(U, 2);
    T.kind     = kind;
    T.n        = n;
    T.trial_id = 1:n;
    T.U        = U;
    T.r0       = zeros(3, n);
    T.v0       = zeros(3, n);
    T.q0       = zeros(4, n);
    T.w0       = zeros(3, n);
    T.Idiag    = zeros(3, n);
    for i = 1:n
        row = mc_trial_mapping(U(:, i));
        if isequal(row.x0, c.design.eval_x0)
            error('mc:trials:eval_ic_collision', ...
                ['STOP: trial %d reproduces the historical evaluation initial ' ...
                 'condition [0;-10;0;0;0;0]. Trial-table generation stops; ' ...
                 'nothing is resampled (protocol Sec. 3.4).'], i);
        end
        T.r0(:, i)    = row.r0;
        T.v0(:, i)    = row.v0;
        T.q0(:, i)    = row.q0;
        T.w0(:, i)    = row.w0;
        T.Idiag(:, i) = row.Idiag;
    end
end

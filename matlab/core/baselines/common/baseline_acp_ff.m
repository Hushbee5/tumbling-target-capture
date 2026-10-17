function ff = baseline_acp_ff(v_cp_preview, Ts)
% BASELINE_ACP_FF  Capture-point feedforward acceleration stencil (Sec. 3.4, C1).
%   ff = baseline_acp_ff(v_cp_preview, Ts) differentiates the PREVIEW
%   capture-point velocity on the control-state grid to produce the feedforward
%   term a_cp_ff the APF control law applies.
%
%   INPUT  v_cp_preview  3x(K+1), column k+1 holds v_cp_preview[k], k = 0..K
%   OUTPUT ff.a_ctrl     3xK, column k+1 holds a_cp_ff[k], k = 0..K-1
%
%   FROZEN STENCIL, zero-based physical time:
%       k = 0        a[0] = ( -3*v[0] + 4*v[1] - v[2] ) / (2*Ts)      forward
%       k = 1..K-1   a[k] = (  v[k+1] - v[k-1] ) / (2*Ts)             central
%   Both are second-order accurate.
%
%   THE CONTROLLER NEVER READS PAST THE STATE GRID. The largest preview index
%   any applied column touches is k+1 at k = K-1, i.e. v[K], which exists on the
%   K+1 state-grid samples. The preview table's extension of (N+2)*Ts beyond the
%   horizon gives additional margin but is deliberately NOT relied upon; V2a
%   asserts the no-overrun property directly.
%
%   a_cp_ff DERIVES ONLY FROM v_cp_preview - the same preview table the MPC
%   consumes - never from the truth capture-point history. Truth geometry is
%   reserved for method-neutral evaluation metrics (protocol Sec. 7).
%
%   TERMINAL COLUMN, DIAGNOSTIC ONLY. ff.a_terminal holds a value at the
%   terminal state k = K, produced by the backward mirror of the frozen k = 0
%   forward stencil:
%       a[K] = ( 3*v[K] - 4*v[K-1] + v[K-2] ) / (2*Ts)
%   THE PROTOCOL DOES NOT FREEZE THIS STENCIL. It freezes only that IF such a
%   column is stored it must be tagged DIAGNOSTIC_ONLY and must never generate
%   an applied command. The mirror is chosen because it is the second-order
%   counterpart of the frozen endpoint rule; it is a diagnostic choice, not a
%   frozen one, and no applied control ever reads it. ff.a_ctrl is asserted to
%   have exactly K columns, so the terminal value cannot be an element of it.
%
%   ff fields:
%       a_ctrl        3xK   applied-column feedforward, k = 0..K-1
%       a_terminal    3x1   DIAGNOSTIC ONLY, k = K
%       terminal_tag  'DIAGNOSTIC_ONLY'
%       K, Ts, max_preview_index_read, note

    assert(isnumeric(v_cp_preview) && size(v_cp_preview, 1) == 3, ...
        'baseline_acp_ff:shape', 'v_cp_preview must be 3x(K+1).');
    assert(isscalar(Ts) && isfinite(Ts) && Ts > 0, 'baseline_acp_ff:Ts', ...
        'Ts must be a positive finite scalar.');

    nCols = size(v_cp_preview, 2);
    K     = nCols - 1;
    assert(K >= 2, 'baseline_acp_ff:tooshort', ...
        ['The frozen k = 0 forward stencil needs v[0], v[1] and v[2], so at ' ...
         'least K = 2 applied intervals are required; got K = %d.'], K);

    a = zeros(3, K);

    % k = 0 : forward three-point, second order
    a(:, 1) = ( -3*v_cp_preview(:, 1) + 4*v_cp_preview(:, 2) - v_cp_preview(:, 3) ) / (2*Ts);

    % k = 1..K-1 : central, second order. MATLAB column k+1 holds physical k,
    % so v[k+1] is column k+2 and v[k-1] is column k.
    if K >= 2
        kk = 2:K;                                   % MATLAB columns for k = 1..K-1
        a(:, kk) = ( v_cp_preview(:, kk+1) - v_cp_preview(:, kk-1) ) / (2*Ts);
    end

    % Terminal DIAGNOSTIC ONLY column: backward mirror of the k = 0 rule.
    a_term = ( 3*v_cp_preview(:, K+1) - 4*v_cp_preview(:, K) + v_cp_preview(:, K-1) ) / (2*Ts);

    assert(size(a, 2) == K, 'baseline_acp_ff:columns', ...
        'a_cp_ff_ctrl has %d columns, not the required K = %d.', size(a, 2), K);

    ff.a_ctrl       = a;
    ff.a_terminal   = a_term;
    ff.terminal_tag = 'DIAGNOSTIC_ONLY';
    ff.K            = K;
    ff.Ts           = Ts;
    % Largest preview column any APPLIED column reads: k+1 at k = K-1, i.e.
    % physical index K -> MATLAB column K+1. Recorded so V2a can assert it.
    ff.max_preview_index_read = K;                  % physical, zero-based
    ff.note = ['a_cp_ff derives only from v_cp_preview. a_terminal is ' ...
        'DIAGNOSTIC_ONLY, is not an element of a_ctrl, and never generates an ' ...
        'applied command; its backward stencil is a diagnostic choice and is ' ...
        'not frozen by the protocol.'];
end

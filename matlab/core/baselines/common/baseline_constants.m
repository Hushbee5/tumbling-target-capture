function g = baseline_constants(p)
% BASELINE_CONSTANTS  Frozen geometric constants of protocol Sec. 2.1, derived.
%   g = baseline_constants(p) returns the derived geometry the APF family, the
%   search bracket and the metric layer all depend on, computed from the frozen
%   configuration and cross-checked against the values the protocol states.
%
%   WHICH SPELLING IS AUTHORITATIVE. The protocol states some of these as EXACT
%   decimals and others as formulas:
%
%       c^2      = 0.65 m^2   (exact)          frozen decimal, asserted against
%                                              p_cp_body' * p_cp_body
%       h_goal   = 0.16 m^2   (exact)          frozen decimal, asserted against
%                                              c^2 - r_safe^2
%       r_safe^2                                computed from p.geom.r_safe
%       c        = sqrt(c^2) = 0.80622577482985502 m ,  CONSTANT in t
%       E_max    = 10 + sqrt(0.65)              generator input, Sec. 4.2
%       omega_min= p.orbit.n                    AUTHORITATIVE, never rebuilt
%                                               from an orbital period
%       omega_max= sqrt(u_max / E_max)          generator, Sec. 4.2
%
%   The frozen decimals are used AS the constants, not merely as checks, because
%   the beta bracket is generated as {0.5, 1, 2}/h_goal and the protocol prints
%   the resulting levels as exactly {3.125, 6.25, 12.5}. Dividing by the literal
%   0.16 reproduces those three doubles bit-for-bit; dividing by the subtraction
%   (0.65 - 0.49), which differs from 0.16 by ~2.8e-17, does not. The
%   subtraction is therefore kept as an ASSERTION on the frozen value rather
%   than as its source.
%
%   Everything here is a consequence of frozen inputs. Nothing is tuned, and no
%   value in this file may be changed to make a later result more convenient.

    assert(nargin >= 1 && isstruct(p), 'baseline_constants:p', ...
        'A parameter struct is required.');

    tol = 1e-14;

    % ---- capture-point geometry --------------------------------------------
    pb   = p.target.p_cp_body(:);
    c2_geom = pb.' * pb;
    g.c2 = 0.65;                                   % [m^2] FROZEN, exact decimal
    assert(abs(g.c2 - c2_geom) <= tol, 'baseline_constants:c2', ...
        ['The frozen c^2 = %.17g m^2 disagrees with the configured capture ' ...
         'point geometry ||p_cp_body||^2 = %.17g m^2.'], g.c2, c2_geom);

    g.c = sqrt(g.c2);                              % [m] ||p_cp(t)||, constant in t
    assert(abs(g.c - 0.80622577482985502) <= 1e-15, 'baseline_constants:c', ...
        'c = %.17g m is not the frozen 0.80622577482985502 m.', g.c);

    % ---- keep-out geometry --------------------------------------------------
    g.r_safe  = p.geom.r_safe;                     % [m]
    g.r_safe2 = g.r_safe^2;                        % [m^2]
    assert(abs(g.r_safe - 0.70) <= 1e-15, 'baseline_constants:r_safe', ...
        'r_safe = %.17g m is not the frozen 0.70 m.', g.r_safe);
    assert(abs(g.r_safe2 - 0.49) <= tol, 'baseline_constants:r_safe2', ...
        'r_safe^2 = %.17g m^2 is not the frozen 0.49 m^2.', g.r_safe2);

    % ---- goal barrier value -------------------------------------------------
    g.h_goal = 0.16;                               % [m^2] FROZEN, exact decimal
    assert(abs(g.h_goal - (g.c2 - g.r_safe2)) <= tol, 'baseline_constants:h_goal', ...
        ['The frozen h_goal = %.17g m^2 disagrees with c^2 - r_safe^2 = ' ...
         '%.17g m^2.'], g.h_goal, g.c2 - g.r_safe2);

    % ---- actuator, sampling -------------------------------------------------
    g.u_max = p.chaser.u_max;                      % [m/s^2] per-axis box
    g.Ts    = p.ctrl.Ts;                           % [s]
    assert(abs(g.u_max - 0.01) <= 1e-15, 'baseline_constants:u_max', ...
        'u_max = %.17g m/s^2 is not the frozen 0.01 m/s^2.', g.u_max);
    assert(abs(g.Ts - 0.1) <= 1e-15, 'baseline_constants:Ts', ...
        'Ts = %.17g s is not the frozen 0.1 s.', g.Ts);

    % ---- search-bracket generator inputs (protocol Sec. 4.2) ---------------
    % E_max is the largest development range the attractive term must not
    % exhaust authority at: 10 m of acquisition distance plus the capture-point
    % radius c.
    g.E_max     = 10 + g.c;                        % [m]
    assert(abs(g.E_max - 10.80622577482985502) <= 1e-14, 'baseline_constants:E_max', ...
        'E_max = %.17g m is not the frozen 10.80622577482985502 m.', g.E_max);

    % omega_min IS the orbital mean motion, taken from the configuration and
    % never reconstructed from a period. The assertion below is a drift guard on
    % the configuration, not an alternative definition.
    g.omega_min = p.orbit.n;                       % [rad/s]
    assert(abs(g.omega_min - 1.131366653611e-3) <= 1e-15, ...
        'baseline_constants:omega_min', ...
        ['p.orbit.n = %.17g rad/s is not the authoritative frozen ' ...
         '1.131366653611e-3 rad/s.'], g.omega_min);
    g.omega_max = sqrt(g.u_max / g.E_max);         % [rad/s]

    % ---- horizon bookkeeping ------------------------------------------------
    % T_eval = 800 s, bound to the polhode period 796.213883 s by the frozen
    % horizon-selection rule. It is recorded, not re-derived.
    g.T_eval          = 800;                       % [s]
    g.polhode_period  = 796.213883;                % [s] recorded provenance only
    g.K               = round(g.T_eval / g.Ts);    % applied control intervals
    g.n_states        = g.K + 1;
    g.n_controls      = g.K;
    g.n_sub           = 10;                        % subintervals per control step
    g.n_interior_per  = g.n_sub - 1;               % 9 STRICT-interior points
    g.n_interior      = g.n_interior_per * g.K;
    g.n_inspected     = g.n_states + g.n_interior; % the inspected union, Sec. 6.2
    assert(g.K == 8000 && g.n_states == 8001 && g.n_interior == 72000, ...
        'baseline_constants:grid', ...
        ['Horizon bookkeeping gives K = %d, states = %d, interior = %d; the ' ...
         'frozen values are 8000 / 8001 / 72000.'], g.K, g.n_states, g.n_interior);
end

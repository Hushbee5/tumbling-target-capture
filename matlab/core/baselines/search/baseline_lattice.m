function lat = baseline_lattice(p)
% BASELINE_LATTICE  The frozen APF search space (protocol Sec. 4).
%   lat = baseline_lattice(p) builds the bracket endpoints, the integer lattice
%   and the 108-candidate coarse grid in the frozen lexicographic order. It
%   invents nothing: every endpoint comes from a generator formula over frozen
%   constants, and the enumeration order is the one the protocol fixes.
%
%   GENERATOR FORMULAS ARE AUTHORITATIVE (Sec. 4.2). The decimals printed in the
%   protocol are DESCRIPTIVE ONLY and must never replace the generators:
%
%       omega_min = p.orbit.n
%       E_max     = 10 + sqrt(0.65)
%       omega_max = sqrt( u_max / E_max )
%       zeta  in [ 0.5 , 2 ]
%       beta  in [ 0.5/h_goal , 2/h_goal ]   = [ 3.125 , 12.5 ]  1/m^2
%       kappa in [ 0.1 , 10 ]
%
%   INTEGER LATTICE (Sec. 4.3):
%       omega axis            l in 0..24 ,  coarse {0, 8, 16, 24}
%       zeta / beta / kappa   l in 0..16 ,  coarse {0, 8, 16}
%       value generator       v(l) = v_min * (v_max/v_min)^(l/L)
%       refinement shifts     {4, 2, 1} , one shift per round, three rounds
%
%   With L = 24 on the omega axis, the coarse levels {0,8,16,24} reproduce
%   omega_i = omega_min*(omega_max/omega_min)^((i-1)/3), i = 1..4, exactly - the
%   two spellings of the omega grid in Sec. 4.2 and 4.3 agree by construction,
%   and that agreement is asserted here rather than assumed.
%
%   COARSE GRID = 4 x 3 x 3 x 3 = 108 candidates, enumerated in the frozen
%   lexicographic order (omega_n, zeta, beta, kappa) with omega outermost, and
%   receiving IDs 1..108 in that order.
%
%   BRACKET RULES, from frozen constants only:
%       omega_n >= p.orbit.n      the loop must outpace the drift it rejects
%       k_a*E_max <= u_max        the attractive term alone must not exhaust
%                                 authority at the largest development range
%   The upper omega endpoint satisfies k_a*E_max = u_max BY CONSTRUCTION.
%
%   THE ENVELOPE IS NEVER WIDENED. Refinement adds intermediate integer levels
%   inside these brackets and nothing else; out-of-bracket proposals are
%   rejected by BASELINE_LATTICE_PROPOSE.
%
%   lat fields:
%       axes        1x4 struct: name, v_min, v_max, L, coarse_levels
%       coarse      108x4 integer level matrix, in the frozen order
%       coarse_theta 1x108 struct array of theta values, same order
%       n_coarse, shifts, max_rounds, order_note

    if isfield(p, 'bl') && isfield(p.bl, 'geom')
        g = p.bl.geom;
    else
        g = baseline_constants(p);
    end

    lat.axes(1) = axis_def('omega_n', g.omega_min,     g.omega_max,    24, [0 8 16 24]);
    lat.axes(2) = axis_def('zeta',    0.5,             2,              16, [0 8 16]);
    lat.axes(3) = axis_def('beta',    0.5 / g.h_goal,  2 / g.h_goal,   16, [0 8 16]);
    lat.axes(4) = axis_def('kappa',   0.1,             10,             16, [0 8 16]);

    % ---- the two spellings of the omega grid must agree --------------------
    ratio = g.omega_max / g.omega_min;
    for i = 1:4
        fromLevels = baseline_lattice_value(lat, [lat.axes(1).coarse_levels(i) 0 0 0]);
        fromSec42  = g.omega_min * ratio^((i-1)/3);
        assert(abs(fromLevels.omega_n - fromSec42) <= 1e-12 * fromSec42, ...
            'baseline_lattice:omega_spellings', ...
            ['Coarse omega level %d gives %.17g rad/s but the Sec. 4.2 ' ...
             'generator gives %.17g rad/s.'], lat.axes(1).coarse_levels(i), ...
            fromLevels.omega_n, fromSec42);
    end

    % ---- the beta bracket must reproduce the printed coarse levels ---------
    bLev = zeros(1, 3);
    for i = 1:3
        th = baseline_lattice_value(lat, [0 0 lat.axes(3).coarse_levels(i) 0]);
        bLev(i) = th.beta;
    end
    assert(isequal(bLev, [3.125, 6.25, 12.5]), 'baseline_lattice:beta_levels', ...
        'The coarse beta levels are %s, not the frozen [3.125 6.25 12.5].', ...
        mat2str(bLev, 17));

    % ---- coarse enumeration, frozen lexicographic order --------------------
    lo = lat.axes(1).coarse_levels;
    lz = lat.axes(2).coarse_levels;
    lb = lat.axes(3).coarse_levels;
    lk = lat.axes(4).coarse_levels;

    n = numel(lo) * numel(lz) * numel(lb) * numel(lk);
    C = zeros(n, 4);
    row = 0;
    for a = 1:numel(lo)
        for b = 1:numel(lz)
            for c = 1:numel(lb)
                for d = 1:numel(lk)
                    row = row + 1;
                    C(row, :) = [lo(a), lz(b), lb(c), lk(d)];
                end
            end
        end
    end
    assert(row == 108, 'baseline_lattice:count', ...
        'The coarse grid enumerated %d candidates, not the frozen 108.', row);

    lat.coarse   = C;
    lat.n_coarse = n;
    theta(n) = baseline_lattice_value(lat, C(n, :));
    for i = 1:n
        theta(i) = baseline_lattice_value(lat, C(i, :));
    end
    lat.coarse_theta = theta;

    lat.shifts     = [4, 2, 1];      % one shift per round, three rounds
    lat.max_rounds = 3;
    lat.order_note = ['IDs 1..108 are the coarse candidates in the frozen ' ...
        'lexicographic order (omega_n, zeta, beta, kappa), omega outermost. ' ...
        'Refinement order is round -> axis {omega, zeta, beta, kappa} -> sign ' ...
        '{-, +}, and every valid unseen candidate receives the next sequential ' ...
        'ID. The search envelope is NEVER widened.'];
end

% =====================================================================
function a = axis_def(name, vmin, vmax, L, coarse)
    assert(vmax > vmin && vmin > 0, 'baseline_lattice:bracket', ...
        'Axis %s has a degenerate bracket [%g, %g].', name, vmin, vmax);
    assert(all(coarse >= 0) && all(coarse <= L), 'baseline_lattice:coarse', ...
        'Axis %s has a coarse level outside 0..%d.', name, L);
    a.name          = name;
    a.v_min         = vmin;
    a.v_max         = vmax;
    a.L             = L;
    a.coarse_levels = coarse;
end

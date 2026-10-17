function theta = baseline_lattice_value(lat, levels)
% BASELINE_LATTICE_VALUE  Integer lattice levels -> APF search parameters.
%   theta = baseline_lattice_value(lat, levels) applies the frozen value
%   generator of protocol Sec. 4.3 on each of the four axes:
%
%       v(l) = v_min * (v_max/v_min)^(l/L) ,  L = 24 (omega) , 16 (others)
%
%   levels is a 1x4 vector of INTEGER levels in the axis order
%   (omega_n, zeta, beta, kappa). Non-integer or out-of-bracket levels are
%   refused: the lattice is the search space, and a value off it would not be a
%   member of the frozen family.
%
%   THE GENERATOR IS AUTHORITATIVE. The decimals in the protocol are descriptive
%   and are never substituted for this formula. At l = 0 and l = L the generator
%   returns the bracket endpoints exactly, so the endpoints are not special
%   cases either.
%
%   theta fields: omega_n [rad/s], zeta [-], beta [1/m^2], kappa [-], levels

    assert(isnumeric(levels) && numel(levels) == 4, 'baseline_lattice_value:levels', ...
        'levels must be a 1x4 vector; got %d element(s).', numel(levels));
    levels = double(levels(:).');

    theta = struct();
    for i = 1:4
        a = lat.axes(i);
        l = levels(i);
        assert(isfinite(l) && l == round(l), 'baseline_lattice_value:integer', ...
            'Level %g on axis %s is not an integer.', l, a.name);
        assert(l >= 0 && l <= a.L, 'baseline_lattice_value:bracket', ...
            ['Level %d on axis %s is outside the frozen bracket 0..%d. The ' ...
             'search envelope is never widened.'], l, a.name, a.L);
        theta.(a.name) = a.v_min * (a.v_max / a.v_min)^(l / a.L);
    end

    theta.levels = levels;
end

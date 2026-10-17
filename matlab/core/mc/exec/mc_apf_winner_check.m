function mc_apf_winner_check(id, levels, theta, gains)
% MC_APF_WINNER_CHECK  Hard stop unless the APF gain set IS the approved winner.
%   mc_apf_winner_check(id, levels, theta, gains) asserts EXACT (bitwise
%   double) equality with the approved candidate-95 values of protocol Sec. 1:
%
%     id 95, levels [24 8 8 8],
%     omega_n = 0.030420264193385706   zeta = 1   beta = 6.25   kappa = 1
%     k_a = 0.0009253924735953845  k_d = 0.06084052838677141
%     k_r = 0.0025154775451671006
%
%   The comparison values are the approved record; the executed values are
%   whatever was read from the tuning record. No tolerance is applied.

    c = mc_constants();
    assert(isequal(id, c.apf.winner_id), 'mc:apf:winner_id', ...
        'HARD STOP: APF winner id %g is not the approved %d.', id, c.apf.winner_id);
    assert(isnumeric(levels) && isequal(levels(:).', c.apf.levels), 'mc:apf:levels', ...
        'HARD STOP: APF winner levels %s are not the approved %s.', mat2str(levels), ...
        mat2str(c.apf.levels));
    tf = fieldnames(c.apf.theta);
    for q = 1:numel(tf)
        v = theta.(tf{q});
        assert(isa(v, 'double') && isscalar(v) && isequal(v, c.apf.theta.(tf{q})), ...
            'mc:apf:theta', 'HARD STOP: theta.%s = %.17g differs from the approved %.17g.', ...
            tf{q}, v, c.apf.theta.(tf{q}));
    end
    gf = fieldnames(c.apf.derived);
    for q = 1:numel(gf)
        v = gains.(gf{q});
        assert(isa(v, 'double') && isscalar(v) && isequal(v, c.apf.derived.(gf{q})), ...
            'mc:apf:derived', 'HARD STOP: %s = %.17g differs from the approved %.17g.', ...
            gf{q}, v, c.apf.derived.(gf{q}));
    end
end

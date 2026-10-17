function gains = apf_gains(theta, p)
% APF_GAINS  Reparameterised APF gains, protocol Sec. 4.1.
%   gains = apf_gains(theta, p) maps the search parameters
%
%       theta.omega_n  [rad/s]  attractive natural frequency
%       theta.zeta     [-]      damping ratio
%       theta.beta     [1/m^2]  repulsion decay in the h variable
%       theta.kappa    [-]      fractional goal stiffening
%
%   onto the physical gains of the Candidate-A potential:
%
%       k_a = omega_n^2
%       k_d = 2*zeta*omega_n
%       k_r = kappa*k_a*exp(+beta*h_goal)
%
%   P = I is FIXED and is not a search parameter: k_r and P appear only as the
%   product k_r*P, so tuning both would be over-parameterised.
%
%   BRACKET RULES, from frozen constants only (Sec. 4.2):
%       omega_n >= p.orbit.n        the loop must outpace the drift it rejects
%       k_a*E_max <= u_max          the attractive term alone must not exhaust
%                                   authority at the largest development range
%   The upper omega endpoint satisfies k_a*E_max = u_max BY CONSTRUCTION, so the
%   second rule is checked with a relative tolerance and equality passes. These
%   are reported as flags rather than raised as errors: the integer lattice
%   never proposes an out-of-bracket point (BASELINE_LATTICE rejects those), and
%   the deliberately OFF-lattice verification gain set theta_V must remain
%   usable here without being mistaken for a tuning candidate.
%
%   gains fields:
%       k_a, k_d, k_r, beta, kappa, omega_n, zeta
%       H_goal        analytic goal Hessian k_a*(1+kappa)*I  (V1c-B expectation)
%       h_goal, E_max, u_max, in_bracket, bracket

    assert(isstruct(theta) && all(isfield(theta, {'omega_n', 'zeta', 'beta', 'kappa'})), ...
        'apf_gains:theta', ...
        'theta must be a struct with fields omega_n, zeta, beta and kappa.');
    fn = {'omega_n', 'zeta', 'beta', 'kappa'};
    for i = 1:numel(fn)
        v = theta.(fn{i});
        assert(isscalar(v) && isreal(v) && isfinite(v) && v > 0, 'apf_gains:value', ...
            'theta.%s must be a positive finite real scalar; got %g.', fn{i}, v);
    end

    if isfield(p, 'bl') && isfield(p.bl, 'geom')
        g = p.bl.geom;
    else
        g = baseline_constants(p);
    end

    gains.omega_n = theta.omega_n;
    gains.zeta    = theta.zeta;
    gains.beta    = theta.beta;
    gains.kappa   = theta.kappa;

    gains.k_a = theta.omega_n^2;
    gains.k_d = 2 * theta.zeta * theta.omega_n;
    gains.k_r = theta.kappa * gains.k_a * exp(theta.beta * g.h_goal);

    assert(isfinite(gains.k_r), 'apf_gains:k_r', ...
        ['k_r = kappa*k_a*exp(beta*h_goal) overflowed for beta = %g, ' ...
         'kappa = %g, k_a = %g.'], theta.beta, theta.kappa, gains.k_a);

    % Analytic goal Hessian of Sec. 3.2. Provided here, next to the gains it is
    % built from, so V1c-B compares an independent finite-difference Jacobian of
    % the analytic gradient against a value neither of them recomputed.
    gains.H_goal = gains.k_a * (1 + theta.kappa) * eye(3);

    gains.h_goal = g.h_goal;
    gains.E_max  = g.E_max;
    gains.u_max  = g.u_max;

    relTol = 1e-12;
    okOmega = theta.omega_n >= g.omega_min * (1 - relTol);
    okAuth  = gains.k_a * g.E_max <= g.u_max * (1 + relTol);
    gains.in_bracket = okOmega && okAuth;
    gains.bracket = struct( ...
        'omega_min',        g.omega_min, ...
        'omega_max',        g.omega_max, ...
        'omega_ok',         okOmega, ...
        'authority_ok',     okAuth, ...
        'authority_ratio',  (gains.k_a * g.E_max) / g.u_max, ...
        'note', ['Bracket compliance is REPORTED here, not enforced. ' ...
                 'BASELINE_LATTICE rejects out-of-bracket proposals; the ' ...
                 'off-lattice verification gain set theta_V is legitimately ' ...
                 'evaluated through this function.']);
end

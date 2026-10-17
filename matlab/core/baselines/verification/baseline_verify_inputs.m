function V = baseline_verify_inputs(p)
% BASELINE_VERIFY_INPUTS  The frozen verification inputs of protocol Sec. 14.0.
%   V = baseline_verify_inputs(p) returns theta_V, the verification test points,
%   the test times and the verification horizon. Every value is transcribed from
%   the protocol; nothing here is chosen, tuned or derived from a run.
%
%   theta_V IS DELIBERATELY OFF-LATTICE, so it cannot be confused with a tuning
%   candidate:
%       omega_n = 5.0e-3 rad/s        zeta = 0.8
%       beta    = 1/h_goal = 6.25 1/m^2         kappa = 1.0
%       k_a = 2.5e-5 ,  k_d = 8.0e-3 ,  k_r = kappa*k_a*exp(beta*h_goal)
%
%   VERIFICATION TEST POINTS, dedicated and distinct from the evaluation IC AND
%   from D1-D5:
%       VP1  x = [  3.0 ;  1.0 ; -2.0 ;  0.010 ; -0.005 ;  0.002 ]
%       VP2  x = [  0.9 ;  0.0 ;  0.0 ;  0     ;  0     ;  0     ]
%       VP3  x = [ -1.5 ;  0.0 ;  0.0 ;  0     ;  0.001 ;  0     ]
%       VP4  x = [  0.0 ;  0.0 ;  1.2 ;  0.003 ;  0     ;  0     ]
%   VP5 was REMOVED from the protocol: no approved verification test used it and
%   its eps was never frozen. It is not reinstated here.
%
%       TEST TIMES     t_V = { 0 , 37.4 , 400.0 , 799.9 } s
%       VERIFY HORIZON Tsim_V = 5.0 s  ->  K_V = 50 , states 51 , interior 450
%
%   [0; -10; 0; 0; 0; 0] IS FORBIDDEN THROUGHOUT V1-V11, and this function
%   asserts that no verification point equals it.
%
%   V fields: theta, gains, VP (6x4), VP_names, t_V, k_V (zero-based grid
%   indices of t_V), Tsim_V, K_V, n_states_V, n_interior_V, fd (frozen step
%   sizes and tolerances).

    g = p.bl.geom;

    V.theta = struct('omega_n', 5.0e-3, 'zeta', 0.8, ...
                     'beta', 1 / g.h_goal, 'kappa', 1.0);
    assert(abs(V.theta.beta - 6.25) <= 1e-14, 'baseline_verify_inputs:beta', ...
        'beta_V = %.17g is not the frozen 1/h_goal = 6.25 1/m^2.', V.theta.beta);

    V.gains = apf_gains(V.theta, p);
    assert(abs(V.gains.k_a - 2.5e-5) <= 1e-19, 'baseline_verify_inputs:k_a', ...
        'k_a = %.17g is not the frozen 2.5e-5 1/s^2.', V.gains.k_a);
    assert(abs(V.gains.k_d - 8.0e-3) <= 1e-17, 'baseline_verify_inputs:k_d', ...
        'k_d = %.17g is not the frozen 8.0e-3 1/s.', V.gains.k_d);

    V.VP = [ 3.0,   0.9,  -1.5,   0.0
             1.0,   0.0,   0.0,   0.0
            -2.0,   0.0,   0.0,   1.2
             0.010, 0.0,   0.0,   0.003
            -0.005, 0.0,   0.001, 0.0
             0.002, 0.0,   0.0,   0.0  ];
    V.VP_names = {'VP1', 'VP2', 'VP3', 'VP4'};

    for i = 1:size(V.VP, 2)
        assert(~isequal(V.VP(:, i), p.bl.eval_x0), 'baseline_verify_inputs:forbidden', ...
            '%s equals the FORBIDDEN evaluation initial condition.', V.VP_names{i});
    end

    V.t_V     = [0, 37.4, 400.0, 799.9];
    V.Tsim_V  = 5.0;
    V.K_V     = round(V.Tsim_V / p.ctrl.Ts);
    V.n_states_V   = V.K_V + 1;
    V.n_interior_V = (p.bl.n_sub - 1) * V.K_V;
    assert(V.K_V == 50 && V.n_states_V == 51 && V.n_interior_V == 450, ...
        'baseline_verify_inputs:horizon', ...
        ['Tsim_V = %g s at Ts = %g s gives K_V = %d, states %d, interior %d; ' ...
         'the frozen values are 50 / 51 / 450.'], V.Tsim_V, p.ctrl.Ts, ...
        V.K_V, V.n_states_V, V.n_interior_V);

    % Zero-based control-grid indices of the test times, on the 800 s grid.
    kv = V.t_V / p.ctrl.Ts;
    assert(all(abs(kv - round(kv)) <= 1e-9), 'baseline_verify_inputs:t_V_grid', ...
        'A test time in t_V is not an integer multiple of Ts.');
    V.k_V = round(kv);
    assert(all(V.k_V >= 0 & V.k_V <= g.K), 'baseline_verify_inputs:t_V_range', ...
        'A test time in t_V lies outside the 800 s control grid.');

    % ---- frozen step sizes and tolerances, all named in Sec. 14 ------------
    V.fd = struct( ...
        'delta_grad',      1e-5, ...        % V1a central-difference step [m]
        'delta_hessian',   1e-4, ...        % V1c-B Jacobian step [m]
        'grad_rel_tol',    1e-6, ...        % V1a relative tolerance
        'grad_abs_tol',    1e-14, ...       % V1a absolute floor
        'hessian_rel_tol', 1e-5, ...        % V1c-B relative tolerance
        'stencil_tol',     1e-14, ...       % V2a mixed tolerance factor
        'v2b_w0',          0.05, ...        % V2b surrogate frequency [rad/s]
        'v2b_Ts',          [0.1, 0.05, 0.025], ...
        'v2b_ratio',       [3.5, 4.5], ...  % V2b acceptance window
        'v2c_tol_p',       1e-6, ...        % V2c position tolerance [m]
        'v2c_tol_v',       1e-6, ...        % V2c velocity tolerance [m/s]
        'v3_tol',          1e-12, ...       % V3c/V3d relative tolerance
        ...                                 % V3c linearity scalings. The
        ...                                 % protocol calls these "alpha"; the
        ...                                 % field is named v3_scalings so that
        ...                                 % no stored field anywhere in the
        ...                                 % baseline namespace carries the
        ...                                 % name or an alias of 'alpha'
        ...                                 % (protocol Sec. 9 and V11e).
        'v3_scalings',     [-2, 0.5, 3], ...
        'v5a_tol',         1e-12, ...       % V5a mixed tolerance factor
        'v5b_tol',         1e-8, ...        % V5b maximum agreement
        'v5c_ref',         15.194482592, ...% V5c reference value
        'v5c_tol',         1e-6, ...        % V5c relative tolerance
        'v8_tol',          1e-14, ...       % V8 summation-order tolerance
        'v2a_central_k',   17);             % V2a deterministic central index

    V.withdrawn = { ...
        'V1b', ['Convergence-ratio test WITHDRAWN by the protocol. At VP1, ' ...
                '||r||^2 = 14 and h = 13.51, so at beta = 6.25 the repulsive ' ...
                'contribution exp(-84.4375) ~ 2.6e-37 is essentially absent ' ...
                'and the potential is locally dominated by the exactly ' ...
                'quadratic attractive term, whose third derivative vanishes. A ' ...
                'second-order truncation ratio is not a valid universal ' ...
                'expectation there. NOT RUN, and no numerical margin estimate ' ...
                'is claimed.']
        'VP5', ['REMOVED by the protocol: no approved verification test used ' ...
                'it and its eps was never frozen. NOT reinstated.'] };
end

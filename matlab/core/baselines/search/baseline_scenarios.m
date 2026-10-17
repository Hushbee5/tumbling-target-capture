function S = baseline_scenarios(p)
% BASELINE_SCENARIOS  The frozen D1-D5 development scenario set (protocol Sec. 5).
%   S = baseline_scenarios(p) returns a 1x5 struct array, one entry per frozen
%   development scenario. It chooses nothing: every initial condition below is
%   transcribed from the protocol table, and the target attitude, body rate and
%   inertia come from the frozen configuration.
%
%   PLANT, ACTUATOR AND GEOMETRY ARE IDENTICAL TO EVALUATION IN ALL FIVE:
%   r_safe, u_max, Ts, n_sub, p_cp_body, target inertia I, integrator and
%   tolerances, T = 800 s. Target inertia I and body-frame w0 are unchanged in
%   EVERY scenario - only x0 varies, and in D5 also the target's initial phase.
%
%   | ID | x0 = [r; v]                          | Target     |
%   | D1 | [10; 0; 0; 0; 0; 0]                  | production |
%   | D2 | [0; -5; 0; 0; 0; 0]                  | production |
%   | D3 | [0; -8; 6; 0; 0; 0]                  | production |
%   | D4 | [-7; -7; 0; 0.002; 0.002; 0]         | production |
%   | D5 | [6; -6; 0; 0; 0; 0]                  | q0_D5      |
%
%   q0_D5, EXACT. Scalar-first quaternions, Hamilton product,
%   q_dev = q_rot (x) q_prod, with q_rot a rotation of +pi/2 about the BODY
%   3-axis:
%       q_rot  = [ cos(pi/4) ; 0 ; 0 ; sin(pi/4) ]
%       q_prod = the production q0 (the identity quaternion)
%       q0_D5  = [ 0.70710678118654752 ; 0 ; 0 ; 0.70710678118654752 ]
%   Stored normalised to unit norm in double precision. Because the production
%   q0 is the IDENTITY the result is independent of the multiplication
%   convention; the convention is implemented anyway, so the RULE is in the code
%   and not merely its answer. If the production q0 ever stopped being the
%   identity, the convention would matter - so that premise is asserted here
%   rather than assumed.
%
%   D5 IS A PHASE CASE, NOT AN UNCERTAINTY EXPERIMENT. q0_D5 is applied
%   consistently to BOTH the truth target propagation AND the shared preview
%   table, so preview and truth still describe the same target.
%
%   THE EVALUATION IC [0; -10; 0; 0; 0; 0] IS FORBIDDEN in development and in
%   verification. This function asserts that no scenario equals it, and
%   SIMULATE_BASELINE refuses it independently at the point of use.
%
%   THE ANTIPODAL BRANCH IS NOT DELIBERATELY SEEDED here; it is monitored
%   analytically through the R1 diagnostic (APF_R1_MARGIN).
%
%   S(i) fields: id, x0, targetIC (q, w, I), previewIC, rationale

    q_prod = p.target.q0(:);
    assert(isequal(q_prod, [1; 0; 0; 0]), 'baseline_scenarios:q_prod', ...
        ['The production q0 is %s, not the identity quaternion. q0_D5 is only ' ...
         'convention-independent when q_prod is the identity, so the D5 ' ...
         'construction must be re-derived before use.'], mat2str(q_prod(:).'));

    q_rot = [cos(pi/4); 0; 0; sin(pi/4)];
    q0_D5 = quat_mul_hamilton(q_rot, q_prod);
    q0_D5 = q0_D5 / norm(q0_D5);
    assert(abs(q0_D5(1) - 0.70710678118654752) <= 1e-15 ...
        && abs(q0_D5(4) - 0.70710678118654752) <= 1e-15 ...
        && all(abs(q0_D5(2:3)) <= 1e-15), 'baseline_scenarios:q0_D5', ...
        'q0_D5 = %s does not match the frozen value.', mat2str(q0_D5(:).', 17));

    w0 = p.target.w0(:);       % unchanged in ALL scenarios
    I  = p.target.I;           % unchanged in ALL scenarios

    prod_ic = struct('q', q_prod, 'w', w0, 'I', I);
    d5_ic   = struct('q', q0_D5,  'w', w0, 'I', I);

    defs = { ...
      'D1', [10;  0;  0;  0;      0;      0], prod_ic, ...
        ['Radial approach. CW drift is anisotropic; exercises the radial drift ' ...
         'term and the sign of the a_CW compensation.']
      'D2', [ 0; -5;  0;  0;      0;      0], prod_ic, ...
        ['Reduced acquisition distance. Same approach direction as evaluation ' ...
         'at a shorter range; tests rapid establishment of a safe moving-goal ' ...
         'approach with little transit distance available. Starts from ZERO ' ...
         'relative velocity.']
      'D3', [ 0; -8;  6;  0;      0;      0], prod_ic, ...
        ['Non-collinear 3-D / out-of-plane case. Cross-track decouples in CW; ' ...
         'exercises the gradient structure where e is not parallel to r, so no ' ...
         'stationary point can exist.']
      'D4', [-7; -7;  0;  0.002;  0.002;  0], prod_ic, ...
        ['Oblique, non-rest start. Tests the damping term and transient ' ...
         'clipping at acquisition.']
      'D5', [ 6; -6;  0;  0;      0;      0], d5_ic, ...
        ['Capture-point phase. Phases p_cp(t) differently across the window ' ...
         'without changing the tumble regime.']
      };

    S = struct('id', {}, 'x0', {}, 'targetIC', {}, 'previewIC', {}, 'rationale', {});
    for i = 1:size(defs, 1)
        x0 = defs{i, 2};
        assert(~isequal(x0, p.bl.eval_x0), 'baseline_scenarios:forbidden_ic', ...
            ['Development scenario %s equals the FORBIDDEN evaluation initial ' ...
             'condition [0; -10; 0; 0; 0; 0].'], defs{i, 1});
        assert(norm(x0(1:3)) >= 5, 'baseline_scenarios:wellposed', ...
            ['Development scenario %s starts at ||r0|| = %.4f m, below the 5 m ' ...
             'the safe-prefix well-posedness argument relies on.'], ...
            defs{i, 1}, norm(x0(1:3)));

        S(i).id        = defs{i, 1};
        S(i).x0        = x0;
        S(i).targetIC  = defs{i, 3};
        % D5 is a PHASE case: the same q0_D5 goes to truth AND preview.
        S(i).previewIC = defs{i, 3};
        S(i).rationale = defs{i, 4};
    end

    assert(numel(S) == 5, 'baseline_scenarios:count', ...
        'The frozen development set has 5 scenarios; built %d.', numel(S));
end

% =====================================================================
function q = quat_mul_hamilton(a, b)
% Hamilton product of two SCALAR-FIRST quaternions, q = a (x) b.
%   a = [a0; av] , b = [b0; bv]
%   q0 = a0*b0 - av'*bv ,  qv = a0*bv + b0*av + cross(av, bv)
    a = a(:); b = b(:);
    a0 = a(1); av = a(2:4);
    b0 = b(1); bv = b(2:4);
    q = [ a0*b0 - av.'*bv ;
          a0*bv + b0*av + cross(av, bv) ];
end

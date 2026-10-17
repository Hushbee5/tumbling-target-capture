function step = controller_apf(x, p_cp_preview, v_cp_preview, a_cp_ff, gains, p)
% CONTROLLER_APF  The APF baseline control law, protocol Sec. 3.3.
%   step = controller_apf(x, p_cp_preview, v_cp_preview, a_cp_ff, gains, p)
%   computes one applied command from the current state and the PREVIEW
%   capture-point information at the same control instant.
%
%       u_cmd = -a_CW(x) + a_cp_ff(t) - grad U(r,t) - k_d*( v - v_cp_preview(t) )
%       u     = baseline_sat_box( u_cmd , u_max )
%
%   NOMINAL VERSUS TRUTH CLOSED LOOP. edot_dot = -grad U - k_d*edot is the
%   intended NOMINAL COMPENSATED dynamics only. On the truth plant, before
%   saturation,
%       edot_dot = -grad U - k_d*edot + Delta_a_model + Delta_a_ff
%       Delta_a_model = a_truth(x) - a_CW(x)
%       Delta_a_ff    = a_cp_ff(t) - a_cp_true(t)
%   with an additional actuation residual u - u_cmd under saturation. Nothing in
%   this file claims those residuals are zero.
%
%   PREVIEW ONLY. The control error and the feedforward term use PREVIEW
%   capture-point information exclusively (Sec. 7). This controller never sees
%   truth geometry, and it is deliberately NOT forced to consume the MPC's
%   shaped Pref/Vref: the APF is a literature-grounded ALTERNATIVE architecture,
%   not an ablation (Sec. 8).
%
%   V9a DEPENDENCY DISCIPLINE. The transitive dependency closure of THIS FILE
%   ALONE must not intersect the APF runtime exclusion list. It calls only
%   BASELINE_CW_DRIFT (-> rel_translational_dynamics, permitted), APF_POTENTIAL,
%   BASELINE_SAT_BOX and BASELINE_DIRECTION_ANGLE. It must never acquire a call
%   to capture_reference_preview, mpc_step, mpc_condensed, quadprog, any cbf_*,
%   capture_barrier, handoff_detector, any cl_*, task4_ic_admissibility,
%   f5_hcap_scan or task4_classify.
%
%   step fields:
%       u_cmd 3x1, u_applied 3x1, clipped, clip_per_axis 3x1
%       c1..c4  the four terms of the sum, in the frozen order (V8)
%       angle   direction-distortion angle [rad], NaN where undefined
%       U, gradU, h_body_potential (the h used INSIDE the potential)

    x = x(:);
    assert(numel(x) == 6, 'controller_apf:x', ...
        'x must be a 6-vector [r; v]; got %d element(s).', numel(x));

    r = x(1:3);
    v = x(4:6);

    r_safe = p.geom.r_safe;
    u_max  = p.chaser.u_max;

    % --- the four frozen components, in order --------------------------------
    c1 = -baseline_cw_drift(x, p);                       % model compensation
    c2 =  a_cp_ff(:);                                    % capture-point feedforward
    [U, gradU, parts] = apf_potential(r, p_cp_preview(:), gains, r_safe);
    c3 = -gradU;                                         % potential descent
    c4 = -gains.k_d * ( v - v_cp_preview(:) );           % damping on the error rate

    u_cmd = c1 + c2 + c3 + c4;

    % --- actuator: per-axis box, the APF-side enforcement of the identical
    %     actuator constraint both methods are held to (Sec. 8) ---------------
    [u_applied, clipped, per_axis] = baseline_sat_box(u_cmd, u_max);

    step.u_cmd         = u_cmd;
    step.u_applied     = u_applied;
    step.clipped       = clipped;
    step.clip_per_axis = per_axis;
    step.c1 = c1;  step.c2 = c2;  step.c3 = c3;  step.c4 = c4;
    step.angle  = baseline_direction_angle(u_applied, u_cmd);
    step.U      = U;
    step.gradU  = gradU;
    step.h_body_potential = parts.h;   % ||r||^2 - r_safe^2 as seen by U
end

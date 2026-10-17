function step = controller_nominal_mpc(x, tk, N, M, p, tbl)
% CONTROLLER_NOMINAL_MPC  The nominal-MPC baseline step: MPC with no safety filter.
%   step = controller_nominal_mpc(x, tk, N, M, p, tbl) calls the FROZEN Task 3
%   layers unmodified and returns their command as the applied command.
%
%       x -> [capture_reference_preview] -> Pref/Vref -> [mpc_step] -> u_mpc
%       u_applied = u_mpc                              (no HOCBF-QP, no clip)
%
%   THIS IS A CLEAN ONE-LAYER ABLATION (protocol Sec. 8): same MPC, same truth
%   plant, HOCBF-QP removed. Nothing else differs from the proposed method's
%   guidance layer, and nothing here reimplements it.
%
%   NO POST-COMMAND CLIP (V10c). The identical per-axis box |u_i| <= u_max is
%   already enforced INSIDE the optimiser by M.lb / M.ub (V10d), so clipping the
%   result afterwards would be a second, different actuator model. The fairness
%   requirement is the identical actuator CONSTRAINT, not a literally shared
%   clipping operator; the APF side enforces the same box with BASELINE_SAT_BOX.
%   isequal(u_applied, u_mpc) therefore holds bitwise at every step.
%
%   NO BASELINE-SPECIFIC SOLVER BEHAVIOUR (V10e). There is no fallback, no
%   retry, no warm-start override and no option change anywhere in this file.
%   mpc_step is called with its frozen signature and whatever it returns is what
%   is applied and recorded - including its zero command on a failed solve,
%   which is the FROZEN PATH'S OWN behaviour and not a baseline invention.
%
%   D9 AND alpha ARE ABSENT (Sec. 9). No handoff logic, no detector, no band
%   parameter enters this controller or its logging.
%
%   step fields:
%       u_cmd, u_applied  3x1  (identical by construction)
%       solver            exitflag / solve_time / cost from the frozen mpc_step
%       ref               s_cp and the preview point, for diagnostics only

    x = x(:);
    assert(numel(x) == 6, 'controller_nominal_mpc:x', ...
        'x must be a 6-vector [r; v]; got %d element(s).', numel(x));

    [Pref, Vref, refinfo] = capture_reference_preview(tk, x, N, p, tbl);
    [u_mpc, info] = mpc_step(x, Pref, Vref, M, p);

    step.u_cmd     = u_mpc(:);
    step.u_applied = u_mpc(:);          % identical bits: no post-clip is applied
    step.solver = struct( ...
        'exitflag',   info.exitflag, ...
        'solve_time', info.solve_time, ...
        'cost',       info.cost, ...
        'failed',     isempty(info.U) || info.exitflag <= 0);
    step.ref = struct('s_cp', refinfo.s_cp, 'p_cp', refinfo.p_cp, ...
                      'v_cp', refinfo.v_cp, 'c_shaped', refinfo.c_shaped, ...
                      'env_infeasible', refinfo.env_infeasible);
end

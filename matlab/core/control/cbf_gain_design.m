function out = cbf_gain_design(p, d_max, verbose)
% CBF_GAIN_DESIGN  Reporting-only sizing calculation for the HOCBF gains.
%   out = cbf_gain_design(p, d_max) evaluates the braking-based sizing heuristic
%   of notes/task2_spec_hocbf_qp.md Sec. 2.2 for the configuration in p.
%
%   IMPORTANT: this function is diagnostic only. It is never called by params.m
%   and never sets p.cbf.k1/k2. The gains are fixed literals (decision R1) so
%   that a u_max sensitivity sweep varies actuator authority alone; letting the
%   gain track u_max would confound that experiment (spec Sec. 2.4).
%
%   Returned fields:
%     k_heuristic   sqrt(2*u_max/d_max)      conservative bound, phi = 1
%     phi           (rho + r_safe)/(2*rho)   exact envelope factor at rho
%     k_exact_local k_heuristic/phi          larger, local exact-factor value
%     k_used        the gains actually configured
%     ratio         k_used / k_heuristic     <= 1 means inside the conservative bound
%
%   Note on the two senses of "conservative" (spec Sec. 2.1a): -k*d is NOT a
%   conservative representation of the exact admissible speed envelope (it admits
%   faster inward motion than -k*d*phi). It is the gain BOUND obtained by setting
%   phi = 1 that is conservative, because 1/phi >= 1.

    if nargin < 2 || isempty(d_max)
        d_max = norm(p.scenario.r0) - p.geom.r_safe;
    end
    if nargin < 3, verbose = true; end

    rho = d_max + p.geom.r_safe;

    out.d_max         = d_max;
    out.rho           = rho;
    out.u_max         = p.chaser.u_max;
    out.k_heuristic   = sqrt(2*p.chaser.u_max / d_max);
    out.phi           = (rho + p.geom.r_safe) / (2*rho);
    out.k_exact_local = out.k_heuristic / out.phi;
    out.k_used        = max(p.cbf.k1, p.cbf.k2);
    out.ratio         = out.k_used / out.k_heuristic;

    if verbose
        fprintf('  CBF gain sizing (diagnostic only, does not set params):\n');
        fprintf('    u_max = %.4g m/s^2, d_max = %.3f m, rho = %.3f m, phi = %.3f\n', ...
            out.u_max, out.d_max, out.rho, out.phi);
        fprintf('    k_heuristic (phi = 1, conservative bound) = %.4f 1/s\n', out.k_heuristic);
        fprintf('    k with exact local factor  (k_heur/phi)   = %.4f 1/s\n', out.k_exact_local);
        fprintf('    k configured                              = %.4f 1/s  (ratio %.3f)\n', ...
            out.k_used, out.ratio);
    end
end

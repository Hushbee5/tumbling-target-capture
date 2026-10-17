function y = apf_r1_phi(x, k_r, beta, r_safe, c)
% APF_R1_PHI  The R1 signed-axis function Phi(x), protocol Sec. 3.2.
%
%       Phi(x) = k_r*exp(-beta*(x^2 - r_safe^2)) * [ beta*x*(x-c) - 1 ]
%
%   An off-goal stationary point of the frozen-time landscape exists on the
%   SIGNED line r = x*n_hat, n_hat = p_cp/c, exactly where k_a = Phi(x).
%
%   THIS IS THE ONLY IMPLEMENTATION. APF_R1_MARGIN calls it rather than keeping
%   a private copy, so the function V5a compares against an independent
%   transcription is genuinely the function the diagnostic uses. Two copies
%   could agree with the test and disagree with each other.
%
%   V5a's comparison is a FROZEN MIXED ABSOLUTE/RELATIVE test applied at every
%   point:
%       | Phi_impl - Phi_ref |  <=  1e-12 * max( k_a , |Phi_ref| )
%   A pure relative test would be UNDEFINED where Phi_ref == 0, which DOES occur
%   at x = +/-20 because the exponential underflows IEEE double to exactly zero.
%   The k_a floor makes the test well posed at those points instead of
%   degenerate.
%
%   x may be an array; the result has the same shape.

    y = k_r .* exp(-beta .* (x.^2 - r_safe^2)) .* ( beta .* x .* (x - c) - 1 );
end

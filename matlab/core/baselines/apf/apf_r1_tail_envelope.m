function bound = apf_r1_tail_envelope(x, beta, kappa, c)
% APF_R1_TAIL_ENVELOPE  Closed-form tail bound on |Phi(x)|/k_a (V5b-TAIL).
%   bound = apf_r1_tail_envelope(x, beta, kappa, c) evaluates
%
%       |Phi(x)|/k_a  <=  kappa * exp( beta*(c^2 - x^2) ) * ( beta*|x|*(|x|+c) + 1 )
%
%   using c^2 = h_goal + r_safe^2, exactly as written in protocol Sec. 14, V5b-TAIL.
%
%   WHY THIS EXISTS. The true R1 domain is unbounded, so the finite reference
%   domain [r_safe, 20] and [-20, -r_safe] must be JUSTIFIED, not assumed. The
%   right-hand side above is monotone DECREASING in |x| for |x| >= 20 at every
%   beta in the frozen bracket, because the Gaussian factor dominates the
%   quadratic factor there; its value at |x| = 20 therefore bounds the whole tail.
%
%   SCOPE IS THE FULL REFINEMENT ENVELOPE, NOT THE COARSE LEVELS.
%       beta  in [ 3.125 , 12.5 ]        kappa in [ 0.1 , 10 ]
%   Refinement adds intermediate integer-lattice values inside that bracket, and
%   the search envelope is never widened (Sec. 4.4), so every value the search
%   can ever reach lies inside it.
%
%   WORST CORNER at fixed |x| >= 20, with A = x^2 - c^2 and B = |x|*(|x|+c):
%       d/d(kappa)  > 0                              -> worst at kappa = 10
%       d/d(beta) propto B - A*(beta*B + 1) < 0 for beta > 1.01e-4
%                                                    -> worst at beta = 3.125
%   The sign-change point at |x| = 20 is beta = 1.009e-4, far below the bracket
%   floor, so the envelope is strictly decreasing in beta across the entire
%   bracket. The worst corner is (beta = 3.125, kappa = 10) - NOT a coarse-level
%   corner in general - and it evaluates to |Phi|/k_a <= 10^(-537.87) at |x| = 20.
%
%   PREDECLARED NEGLIGIBLE LEVEL
%       |Phi(x)|/k_a  <  1e-30   for all |x| >= 20, for EVERY (beta,kappa) in
%       the full frozen refinement envelope.
%   Consequence: no omitted tail maximum can affect M, and since a stationary
%   root requires Phi(x)/k_a = 1 >> 1e-30, NO ROOT CAN LIE IN THE TAIL.
%
%   This is a numerical-domain justification for a DIAGNOSTIC. It is not
%   presented as a scientific theorem.
%
%   The result may UNDERFLOW to exactly 0 in IEEE double (the exponent at
%   |x| = 20, beta = 3.125 is -1247.9, far past the subnormal limit ~exp(-745)).
%   That underflow is the expected behaviour and is itself the evidence: 0 < 1e-30.

    ax    = abs(x);
    bound = kappa .* exp( beta .* (c.^2 - ax.^2) ) .* ( beta .* ax .* (ax + c) + 1 );
end

function w = mc_wilson(x, n)
% MC_WILSON  Wilson 95 % interval, exactly as protocol Sec. 8.2 writes it.
%   w = mc_wilson(x, n) with integer 0 <= x <= n:
%
%       p_hat      = x / n ,   z = 1.959963984540054
%       centre     = ( p_hat + z^2/(2n) ) / ( 1 + z^2/n )
%       half-width = ( z / (1 + z^2/n) ) * sqrt( p_hat*(1 - p_hat)/n + z^2/(4 n^2) )
%       interval   = [ centre - half-width , centre + half-width ]
%
%   n = 0 (for example an evaluated rate with no evaluable run) returns NaN
%   fields with defined = false; it is never reported as a zero rate.
%   w fields: x, n, p_hat, centre, half_width, lo, hi, z, defined.

    c = mc_constants();
    z = c.stats.wilson_z;
    assert(isscalar(x) && isscalar(n) && x == round(x) && n == round(n) && x >= 0 ...
        && n >= 0 && x <= n, 'mc:wilson:args', 'Need integers 0 <= x <= n.');
    w = struct('x', x, 'n', n, 'p_hat', NaN, 'centre', NaN, 'half_width', NaN, ...
               'lo', NaN, 'hi', NaN, 'z', z, 'defined', false);
    if n == 0
        return
    end
    p  = x / n;
    ce = (p + z^2/(2*n)) / (1 + z^2/n);
    hw = (z / (1 + z^2/n)) * sqrt(p*(1 - p)/n + z^2/(4*n^2));
    w.p_hat = p;  w.centre = ce;  w.half_width = hw;
    w.lo = ce - hw;  w.hi = ce + hw;  w.defined = true;
end

function [Q, undefined] = mc_quantile7(v, p, mode)
% MC_QUANTILE7  Hyndman-Fan type 7 sample quantiles, implemented explicitly (R14).
%   Q = mc_quantile7(v, p)                  v: finite values (the default)
%   [Q, undefined] = mc_quantile7(v, p, 'extended')
%                                           v: values in the EXTENDED reals
%
%       x = sort(v),  n = numel(x),  h = (n - 1) * p + 1,  j = floor(h),
%       g = h - j,    Q = (1 - g) * x(j) + g * x(j + 1)   (Q = x(n) when j >= n)
%
%   i.e. linear interpolation between order statistics (the R / NumPy
%   default). MATLAB's own QUANTILE uses a different definition and is never
%   called. An empty v returns NaN (reported with its denominator 0).
%
%   'extended' evaluates the SAME definition on order statistics that may be
%   +Inf or -Inf (e.g. t_viol = +Inf, "no violation observed", Sec. 6.1). Every
%   case follows from the formula itself, with the term of weight 0 omitted:
%     g = 0                   Q = x(j)          (0 * Inf contributes nothing)
%     x(j) == x(j+1)          Q = x(j)          (also +Inf,+Inf and -Inf,-Inf)
%     x(j) finite, x(j+1) = +Inf, 0 < g < 1     Q = +Inf
%     x(j) = -Inf, x(j+1) finite, 0 < g < 1     Q = -Inf
%     x(j) = -Inf, x(j+1) = +Inf, 0 < g < 1     UNDEFINED (-Inf + Inf): Q = NaN
%                                               and undefined(i) = true
%   No value is replaced by a finite surrogate. NaN is never an input.

    if nargin < 3, mode = 'finite'; end
    assert(all(p >= 0 & p <= 1), 'mc:quantile:p', 'Probabilities must lie in [0, 1].');
    v = v(:);
    switch mode
        case 'finite'
            assert(all(isfinite(v)), 'mc:quantile:nonfinite', ...
                'Quantiles are taken over AVAILABLE finite values only.');
        case 'extended'
            assert(~any(isnan(v)), 'mc:quantile:nan', 'NaN is never an AVAILABLE value.');
        otherwise
            error('mc:quantile:mode', 'Unknown quantile mode ''%s''.', mode);
    end
    Q = nan(size(p));
    undefined = false(size(p));
    n = numel(v);
    if n == 0
        return
    end
    x = sort(v);
    for i = 1:numel(p)
        h  = (n - 1) * p(i) + 1;
        lo = floor(h);
        g  = h - lo;
        if lo >= n || g == 0
            Q(i) = x(min(lo, n));
            continue
        end
        a = x(lo);
        b = x(lo + 1);
        if a == b
            Q(i) = a;
        elseif isinf(a) && isinf(b)
            undefined(i) = true;                % -Inf and +Inf: the weighted sum is undefined
        elseif isinf(b)
            Q(i) = b;                            % finite, +Inf
        elseif isinf(a)
            Q(i) = a;                            % -Inf, finite
        else
            Q(i) = a + g * (b - a);
        end
    end
end

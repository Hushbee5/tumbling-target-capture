function [angle, stats] = baseline_direction_angle(u_applied, u_cmd)
% BASELINE_DIRECTION_ANGLE  APF direction-distortion angle, numerically guarded.
%   [angle, stats] = baseline_direction_angle(u_applied, u_cmd) implements
%   protocol Sec. 10.5 exactly, for a single pair (3x1) or a whole history
%   (3xK, one column per applied control interval).
%
%       if u_cmd == 0  OR  u_applied == 0        ->  angle = NaN
%       elseif isequal(u_applied, u_cmd)         ->  angle = 0   (returned
%                                                    EXPLICITLY, not computed
%                                                    through acos)
%       else
%           cs    = dot(u_applied,u_cmd) / ( norm(u_applied)*norm(u_cmd) )
%           cs    = min(1, max(-1, cs))          MANDATORY clamp before acos
%           angle = acos(cs)
%       end
%
%   WHY THE EXPLICIT ZERO. For an unclipped step u_applied and u_cmd are the
%   same bits, and the quotient can still land a few ulp above 1. acos of such a
%   value is COMPLEX. Returning 0 by inspection removes that failure mode
%   entirely instead of relying on the clamp to catch it; the clamp is kept as
%   well, because a nearly-parallel clipped pair can also overshoot.
%
%   WHY NaN AND NOT ZERO ON A ZERO COMMAND. The angle between a zero vector and
%   anything is undefined. Reporting 0 would silently claim perfect direction
%   preservation at exactly the samples where no direction exists. NaN samples
%   are EXCLUDED from every angle statistic and the excluded count is reported,
%   never quietly dropped.
%
%   stats fields (computed over the finite angles only):
%       n_total, n_excluded, n_used, max, mean, note
%   A history with no usable sample yields NaN statistics and n_used = 0 - not
%   zeros, which would read as "measured, and perfectly aligned".

    assert(isnumeric(u_applied) && isnumeric(u_cmd), ...
        'baseline_direction_angle:type', 'Both inputs must be numeric.');
    if isvector(u_applied), u_applied = u_applied(:); end
    if isvector(u_cmd),     u_cmd     = u_cmd(:);     end
    assert(size(u_applied, 1) == 3 && size(u_cmd, 1) == 3, ...
        'baseline_direction_angle:shape', 'Both inputs must have 3 rows.');
    assert(size(u_applied, 2) == size(u_cmd, 2), ...
        'baseline_direction_angle:count', ...
        'Applied and commanded histories differ in length (%d vs %d).', ...
        size(u_applied, 2), size(u_cmd, 2));

    K     = size(u_cmd, 2);
    angle = nan(1, K);

    for k = 1:K
        a = u_applied(:, k);
        c = u_cmd(:, k);

        if all(c == 0) || all(a == 0)
            angle(k) = NaN;                       % undefined, recorded as such
        elseif isequal(a, c)
            angle(k) = 0;                         % EXPLICIT, never through acos
        else
            cs = (a.' * c) / (norm(a) * norm(c));
            cs = min(1, max(-1, cs));             % MANDATORY clamp
            angle(k) = acos(cs);
        end
    end

    if nargout > 1
        ok = isfinite(angle);
        stats.n_total    = K;
        stats.n_excluded = sum(~ok);
        stats.n_used     = sum(ok);
        if stats.n_used > 0
            stats.max  = max(angle(ok));
            stats.mean = mean(angle(ok));
        else
            stats.max  = NaN;
            stats.mean = NaN;
        end
        stats.note = ['Angles are in radians. NaN samples (zero commanded or ' ...
            'zero applied vector) are EXCLUDED from these statistics and are ' ...
            'counted in n_excluded. NaN statistics mean no usable sample ' ...
            'existed, not a zero angle.'];
    end
end

function [better, level] = baseline_order_better(a, b)
% BASELINE_ORDER_BETTER  Strict comparison under the COMPLETE T1 -> T7 order.
%   [better, level] = baseline_order_better(a, b) returns true when the ordering
%   vector a STRICTLY improves on b under the frozen lexicographic order of
%   protocol Sec. 6.4, and the 1-based level at which the decision was made.
%
%   a and b are either the 1x7 vectors or the structs BASELINE_SELECTION
%   returns. The direction vector is
%       [ +1  -1  +1  -1  -1  -1  -1 ]
%   i.e. T1 and T3 are maximised and T2, T4, T5, T6, T7 are minimised.
%
%   EXACT COMPARISON, NO TOLERANCE. A tolerance-based T5 tie-break is explicitly
%   DEFERRED by protocol Sec. 17, and T7 (candidate ID, minimised) already makes
%   the order total: two distinct candidates can never tie at every level, so
%   exactly one primary APF gain set is always selected.
%
%   USED FOR THE STOPPING RULE TOO. After each COMPLETED refinement round the
%   new incumbent is compared against the incumbent that existed BEFORE that
%   round with this same COMPLETE order. If no newly evaluated candidate
%   strictly improves it, the search STOPS. The withdrawn "no T5 improvement
%   once T1-T4 are satisfied" clause is not implemented anywhere, because T1-T4
%   are ranking quantities and "satisfied" was undefined for them.
%
%   level is 0 when the two vectors are identical at every level, which can only
%   happen when a candidate is compared with itself.

    va = as_vector(a);
    vb = as_vector(b);
    dir = [+1, -1, +1, -1, -1, -1, -1];

    better = false;
    level  = 0;
    for i = 1:7
        if va(i) == vb(i)
            continue
        end
        level  = i;
        if dir(i) > 0
            better = va(i) > vb(i);
        else
            better = va(i) < vb(i);
        end
        return
    end
end

% =====================================================================
function v = as_vector(x)
    if isstruct(x)
        assert(isfield(x, 'vector'), 'baseline_order_better:struct', ...
            'A selection struct must carry a 1x7 vector field.');
        v = x.vector;
    else
        v = x;
    end
    v = v(:).';
    assert(numel(v) == 7 && all(isfinite(v)), 'baseline_order_better:shape', ...
        'An ordering vector must be a finite 1x7 vector; got %d element(s).', numel(v));
end

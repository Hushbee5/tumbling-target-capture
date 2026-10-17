function [proposals, rejected] = baseline_lattice_propose(lat, incumbentLevels, shift, seenLevels)
% BASELINE_LATTICE_PROPOSE  One refinement round's proposals, in the frozen order.
%   [proposals, rejected] = baseline_lattice_propose(lat, incumbentLevels, ...
%                                                    shift, seenLevels)
%
%   Implements protocol Sec. 4.4:
%       "Refinement proposes l_axis +/- shift along each of the four axes from
%        the incumbent; out-of-bracket proposals are REJECTED; already-evaluated
%        lattice points are NOT re-run; the search envelope is NEVER widened."
%
%   REFINEMENT ORDER, frozen and preserved:
%       round -> axis {omega, zeta, beta, kappa} -> sign {-, +}
%   Every valid unseen candidate in that order receives the next sequential ID
%   from the caller. At most 8 proposals per round (4 axes x 2 signs), so the
%   refinement budget is at most 3 rounds x 8 proposals x 5 scenarios = 120 runs.
%
%   THERE IS NO ORDER-DEPENDENT TRUNCATION. Every in-bracket unseen proposal in
%   every round is returned; the caller evaluates all of them. The <= 660 total
%   is a bound produced by rejection and de-duplication, not by stopping early
%   inside a round.
%
%   seenLevels is an Nx4 matrix of every lattice point already evaluated in this
%   search (coarse and refinement). A proposal matching any row is dropped as a
%   duplicate, never re-run.
%
%   proposals  Mx4 integer levels, in the frozen order
%   rejected   struct array recording every dropped proposal and WHY, so the
%              search log shows the rejections as well as the evaluations

    assert(isnumeric(incumbentLevels) && numel(incumbentLevels) == 4, ...
        'baseline_lattice_propose:incumbent', 'incumbentLevels must be 1x4.');
    assert(isscalar(shift) && shift == round(shift) && shift > 0, ...
        'baseline_lattice_propose:shift', 'shift must be a positive integer.');
    if nargin < 4 || isempty(seenLevels), seenLevels = zeros(0, 4); end

    base = double(incumbentLevels(:).');
    proposals = zeros(0, 4);
    rejected  = struct('levels', {}, 'axis', {}, 'sign', {}, 'reason', {});

    signs = [-1, +1];                    % frozen sign order: minus first
    for ax = 1:4                         % frozen axis order: omega, zeta, beta, kappa
        for si = 1:2
            cand = base;
            cand(ax) = base(ax) + signs(si) * shift;

            if cand(ax) < 0 || cand(ax) > lat.axes(ax).L
                rejected(end+1) = struct('levels', cand, 'axis', lat.axes(ax).name, ...
                    'sign', signs(si), 'reason', sprintf( ...
                    'out of bracket: level %d outside 0..%d', cand(ax), lat.axes(ax).L)); %#ok<AGROW>
                continue
            end

            if is_seen(cand, seenLevels) || is_seen(cand, proposals)
                rejected(end+1) = struct('levels', cand, 'axis', lat.axes(ax).name, ...
                    'sign', signs(si), ...
                    'reason', 'already evaluated: duplicate lattice point');   %#ok<AGROW>
                continue
            end

            proposals(end+1, :) = cand;                                        %#ok<AGROW>
        end
    end
end

% =====================================================================
function tf = is_seen(cand, table)
    if isempty(table)
        tf = false;
        return
    end
    tf = any(all(bsxfun(@eq, table, cand), 2));
end

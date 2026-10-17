function scan = f5_hcap_scan(out, p)
% F5_HCAP_SCAN  Independent post-hoc D9 replay for the T4-D9 F5 trigger.
%   scan = f5_hcap_scan(out, p) rebuilds the capture geometry FROM THE LOGGED RAW
%   STATE, replays the frozen D9 predicates over it, and compares both the
%   sampled h_cap sign AND the resulting classification with what the in-loop
%   detector produced.
%
%   THE FROZEN F5 RULE HAS TWO BRANCHES (freeze record Sec. 8.6):
%       (1) sampled h_cap < 0 while h_cap is enforced, OR
%       (2) the detector classification disagrees with an independent post-hoc scan.
%   Checking only (1) would let an erroneous NORMAL or a missed NORMAL pass
%   unnoticed into a D9 PASS, because neither produces a negative h_cap.
%
%   WHY IT DUPLICATES WORK, AND WHAT IT IS NOT. At sample level h_cap >= 0 is
%   mathematically equivalent to rho >= s_cap, and the replayed predicates are
%   the frozen ones, so this file adds NO physical information. Its independence
%   is in the CODE PATH only: it is a SOFTWARE-CONSISTENCY check, not a second
%   physical safety criterion, and it establishes no sampled-data or intersample
%   invariance theorem of any kind.
%
%   INDEPENDENCE IS ENFORCED BY CONSTRUCTION. This function deliberately does NOT
%   call HANDOFF_DETECTOR and does NOT call CAPTURE_BARRIER, and it never reads
%   out.rho, out.rho_dot, out.h_cap or out.events. It rebuilds p_cp, v_cp, d,
%   rho, rho_dot and h_cap directly from out.X, out.qT, out.wT and out.t using
%   the frozen geometry primitives (LVLH_FRAME, QUAT_TO_ROTM).
%
%   ENFORCEMENT WINDOW for branch (1), freeze record Sec. 8.6: every sample from
%   the start of the run up to and including the sample at which either h_cap was
%   disabled by a NORMAL handoff, or the run terminated.
%
%   LIMITATION, STATED SO THE RESULT IS NOT OVER-READ: the scan is over SAMPLED
%   values. It cannot detect an excursion in which h_cap dips below zero and
%   returns between two samples.
%
%   Fields:
%     window, rho, rho_dot, h_cap   independently rebuilt, over the scan window
%     independent_event             NORMAL | GUARD_BREACH | NO_EVENT
%     independent_event_k           sample index of the independent event, or []
%     event_rho, event_rho_dot, event_h_cap
%                                   the three quantities at that sample, or []
%     breach_found                  branch (1): any sampled h_cap < 0 in the window
%     first_breach_k                first offending sample, or []
%     min_h_cap                     minimum over the enforcement window
%     detector_event                what the in-loop detector concluded
%     classification_agree          branch (2): independent_event == detector_event
%     F5                            the trigger
%     F5_branch                     'none' | 'sampled-violation'
%                                   | 'classification-disagreement'
%                                   | 'sampled-violation+classification-disagreement'
%     source_alpha                  the alpha of the run this scan was built from,
%                                   so a misordered scan cannot be consumed
%     comparable                    false for a run whose detector never ran
%     max_rho_mismatch              |rho_scan - out.rho| over the window, a
%                                   numerical cross-check of the two code paths
%                                   (diagnostic only, not part of any verdict)

    % ---- PARAMETER-SET BINDING. The scan reconstructs geometry from p, so a p
    % that does not belong to this run would analyse it with unrelated target or
    % orbit geometry and still look self-consistent. Sanitize the supplied p the
    % same way RUN_CONFIG did and require an exact match with the one recorded by
    % the run itself.
    assert(isfield(out, 'config') && isfield(out.config, 'p'), ...
        'f5_hcap_scan:no_config', ...
        'The run carries no recorded configuration, so p cannot be bound to it.');
    pChk = p;
    for fn = {'alpha', 'eps_rho', 'eps_h'}
        if isfield(pChk.t4, fn{1}), pChk.t4 = rmfield(pChk.t4, fn{1}); end
    end
    dp = struct_field_diff(out.config.p, pChk);
    assert(isempty(dp), 'f5_hcap_scan:p_mismatch', ...
        ['The supplied p differs from the one that produced this run: %s. The ' ...
         'scan refuses to analyse a run with unrelated parameters.'], ...
        strjoin(dp, ', '));

    pb  = p.target.p_cp_body(:);
    wL  = [0; 0; p.orbit.n];
    eps_rho = out.eps_rho;          % the alpha in force for THIS run
    s_cap   = out.s_cap;

    % ---- SOURCE BINDING. source_alpha alone cannot distinguish two runs that
    % share an alpha but differ in configuration, so the full run configuration
    % is carried and checked by TASK4_CLASSIFY.
    scan.source_alpha  = out.alpha;
    scan.source_config = out.config;
    scan.detector_event = out.event;

    % A run refused at the initial-admissibility gate has no D9 outcome at all -
    % the detector never ran - so there is nothing to agree or disagree with.
    scan.comparable = ~(isfield(out,'d9_evaluated') && ~out.d9_evaluated);

    nS = numel(out.t);

    % --- independent geometry rebuild over every logged sample --------------
    rho = zeros(1, nS);  rho_dot = zeros(1, nS);
    for k = 1:nS
        [~, R_LI, ~] = lvlh_frame(out.t(k), p);
        R    = R_LI * quat_to_rotm(out.qT(:,k));
        p_cp = R * pb;
        wBL  = out.wT(:,k) - R.' * wL;
        v_cp = R * cross(wBL, pb);
        d    = out.X(1:3,k) - p_cp;
        dd   = out.X(4:6,k) - v_cp;
        rho(k) = norm(d);
        if rho(k) < eps
            rho_dot(k) = 0;
        else
            rho_dot(k) = (d.'*dd) / rho(k);
        end
    end
    h_cap_all = rho.^2 - s_cap^2;

    % --- independent chronological replay of the FROZEN D9 predicates -------
    % Latches at the first event, exactly as the frozen taxonomy requires. The
    % predicates below are the frozen ones, rewritten here rather than called.
    ev = 'NO_EVENT';  evk = [];
    for k = 1:nS
        if rho(k) < s_cap
            ev = 'GUARD_BREACH';  evk = k;  break
        elseif rho(k) <= s_cap + eps_rho && rho_dot(k) <= 0
            ev = 'NORMAL';        evk = k;  break
        end
    end
    scan.independent_event   = ev;
    scan.independent_event_k = evk;
    if isempty(evk)
        scan.event_rho = [];  scan.event_rho_dot = [];  scan.event_h_cap = [];
    else
        scan.event_rho = rho(evk);  scan.event_rho_dot = rho_dot(evk);
        scan.event_h_cap = h_cap_all(evk);
    end

    % --- branch (1): sampled h_cap over the enforcement window --------------
    if strcmp(out.event, 'NORMAL') && ~isempty(out.handoff)
        kEnd = min(out.handoff.k, nS);
    else
        kEnd = nS;
    end
    w = 1:kEnd;
    scan.window  = w;
    scan.rho     = rho(w);
    scan.rho_dot = rho_dot(w);
    scan.h_cap   = h_cap_all(w);
    scan.min_h_cap = min(scan.h_cap);

    bad = find(scan.h_cap < 0, 1);
    scan.breach_found = ~isempty(bad);
    if isempty(bad), scan.first_breach_k = []; else, scan.first_breach_k = w(bad); end

    % --- branch (2): classification agreement -------------------------------
    if scan.comparable
        scan.classification_agree = strcmp(scan.independent_event, scan.detector_event);
    else
        scan.classification_agree = true;   % nothing to compare; see `comparable`
    end

    % --- combine ------------------------------------------------------------
    disagree = ~scan.classification_agree;
    scan.F5  = scan.breach_found || disagree;
    if scan.breach_found && disagree
        scan.F5_branch = 'sampled-violation+classification-disagreement';
    elseif scan.breach_found
        scan.F5_branch = 'sampled-violation';
    elseif disagree
        scan.F5_branch = 'classification-disagreement';
    else
        scan.F5_branch = 'none';
    end

    % --- numerical cross-check of the two code paths (diagnostic only) ------
    if isfield(out, 'rho') && numel(out.rho) >= kEnd
        scan.max_rho_mismatch = max(abs(rho(w) - out.rho(w)));
    else
        scan.max_rho_mismatch = NaN;
    end
end

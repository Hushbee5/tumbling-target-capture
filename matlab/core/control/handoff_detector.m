function ev = handoff_detector(rho, rho_dot, handoff_done, p)
% HANDOFF_DETECTOR  The frozen T4-D9 commitment-guard handoff detector.
%   ev = handoff_detector(rho, rho_dot, handoff_done, p) returns one of
%
%     'NORMAL'        handoff_done == false
%                     AND s_cap <= rho <= s_cap + epsilon_rho
%                     AND rho_dot <= 0
%
%     'GUARD_BREACH'  handoff_done == false
%                     AND rho < s_cap
%
%     'NONE'          neither trigger fired at this sample
%
%   exactly as frozen in notes/task4_freeze_record.md Sec. 8.2. The two triggers
%   are mutually exclusive by construction, since the NORMAL band requires
%   rho >= s_cap and the breach requires rho < s_cap.
%
%   NO DWELL. The present ideal-model baseline has no navigation-noise, relay,
%   hardware-switching or contact model that would justify a dwell constant, and
%   no frozen internal timescale sets one (freeze record Sec. 8.3). Do not add
%   one here.
%
%   THE rho_dot <= 0 CONJUNCT is a SIGN TEST with no threshold. It exists because
%   the capture point rotates with the target, so rho is not monotone and the
%   detector must not fire on a receding pass. A consequence, which the claim
%   language depends on: the firing sample need NOT be the first sample inside
%   the band, so a NORMAL event may never be described as "first entered".
%
%   'NONE' accumulated over a whole run is what the run-level classifier reports
%   as NO_EVENT. NO_EVENT means only that no sample satisfied the NORMAL trigger
%   and no sampled breach was detected before the run ended. It is NOT evidence
%   that the neighbourhood was never visited, because a receding sample inside
%   the band does not fire the trigger.
%
%   D9 HAS EXACTLY THREE OUTCOMES: NORMAL, GUARD_BREACH, NO_EVENT. Nothing may be
%   added to that taxonomy. A run refused by the pre-run initial-admissibility
%   gate has NO D9 outcome at all - the detector never ran - and is recorded
%   separately as a validation-eligibility status (see TASK4_IC_ADMISSIBILITY).
%
%   This function has NO explicit dependence on theta, theta_hat or nu: it reads
%   the instantaneous rho and rho_dot only. The closed-loop trajectory that
%   produces them may of course depend indirectly on the adaptive controller and
%   on the target truth, so the detector's FUNCTIONAL FORM is uncertainty-free,
%   not its outcome.

    if handoff_done
        ev = 'NONE';
        return
    end

    if rho < p.t4.s_cap
        ev = 'GUARD_BREACH';
    elseif rho <= p.t4.s_cap + p.t4.eps_rho && rho_dot <= 0
        ev = 'NORMAL';
    else
        ev = 'NONE';
    end
end

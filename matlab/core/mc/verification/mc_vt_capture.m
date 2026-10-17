function cap = mc_vt_capture()
% MC_VT_CAPTURE  Real NON-SCIENTIFIC outputs of the three methods, once per session.
%   cap = mc_vt_capture() runs the frozen proposed method, nominal MPC and
%   primary APF ONCE on trial 1 of the fixture-seed-911 table (not the
%   scientific seed; not the evaluation IC), Condition U, 3 s horizon, and
%   caches the invocation results. Fixtures that exercise the campaign
%   machinery (failure injection, reservations, closure corruption) replay
%   these results through a verification-only runner override, so NO
%   controller runs inside those fixtures.
%
%   cap fields: T, row, A (Level A), P (proposed invocation), Bm, Ba (baseline
%   invocations), Tsim.

    persistent C
    if isempty(C)
        T = mc_fixture_trial_table(911, 2);
        row = mc_trial_row(T, 1);
        pBL = baseline_config();
        W = mc_load_apf_winner(pBL);
        Tsim = 3;
        A  = mc_shared_tables(row, 'U', pBL, Tsim);
        P  = mc_invoke_proposed(row, A, Tsim);
        Bm = mc_invoke_baseline('nominal_mpc', row, A, Tsim, pBL, W.theta);
        Ba = mc_invoke_baseline('apf', row, A, Tsim, pBL, W.theta);
        C = struct('T', T, 'row', row, 'A', A, 'P', P, 'Bm', Bm, 'Ba', Ba, 'Tsim', Tsim);
    end
    cap = C;
end

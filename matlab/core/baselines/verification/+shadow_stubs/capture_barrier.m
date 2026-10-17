function varargout = capture_barrier(varargin) %#ok<STOUT>
% CAPTURE_BARRIER  V9/V10 SHADOW STUB. Verification fixture only.
%
%   THIS IS NOT AN IMPLEMENTATION OF ANYTHING. It exists so that the V9b and
%   V10b runtime exclusion proofs of protocol Sec. 14 can be positive proofs
%   rather than assertions: a plain directory holding one stub per excluded
%   function is placed at the FRONT of the MATLAB path, every forbidden name is
%   asserted through which() to resolve to that directory, and the test run then
%   has to COMPLETE. A completed run is proof that no excluded function was
%   entered, because entering one would raise the error below.
%
%   WHERE THIS FILE LIVES, AND WHY IT IS IN A '+' FOLDER.
%   Every validator and Task 4 harness in this repository calls
%   addpath(genpath(<src>)), and genpath descends alphabetically, so a PLAIN
%   directory of stubs under src/baselines would be pushed onto the path ahead
%   of src/control and ahead of the toolboxes by ordinary project code - which
%   would shadow quadprog, mpc_step, mpc_condensed and
%   capture_reference_preview globally and break validate_task2, validate_task3
%   and the Stop-hook regression gate. genpath refuses to descend into a folder
%   whose name begins with '+', so the stubs are STORED here and BASELINE_
%   SHADOW_FIXTURE copies the ones a given test needs into a fresh temporary
%   PLAIN directory at test time. The directory that actually shadows is
%   therefore plain, exactly as the protocol requires, and the stored copies
%   are still .m files under src/baselines/** so they remain inside the
%   recursive provenance manifest of Sec. 15.1.
%
%   THE STUBS ARE INSTALLED ONLY FOR V9b/V10b AND NEVER FOR ANY SCIENTIFIC RUN.
%   The installing fixture restores the original MATLAB path UNCONDITIONALLY
%   through onCleanup and deletes the temporary directory.

    error('shadow_stubs:capture_barrier', ...
        ['FORBIDDEN CALL PATH: capture_barrier was entered during a V9b/V10b ' ...
         'runtime exclusion test. The method under test is required NOT to ' ...
         'reach this function, so the exclusion proof FAILS. This stub is a ' ...
         'verification fixture and implements nothing.']);
end

function info = mc_trial_csv_write(T, dest)
% MC_TRIAL_CSV_WRITE  Write a NON-SCIENTIFIC trial table in the canonical byte contract.
%   info = mc_trial_csv_write(T, dest) writes MC_TRIAL_CSV_BYTES(T) atomically
%   and never over an existing file (MC_ATOMIC_WRITE).
%
%   IT CAN NEVER PUBLISH THE SCIENTIFIC TABLE. Whatever T carries - any kind
%   label, n = 100, trial_id 1..100 - a destination that is the canonical CSV,
%   the freeze record, or anything under results/task4/mc is refused FIRST
%   ('mc:csv:protected_path'), before anything is created. The canonical CSV
%   is published only by the local transaction inside MC_SCIENTIFIC_TRIAL_TABLE,
%   which draws its own table from the scientific stream after the live
%   generation preflight; no caller-supplied table can reach it.
%
%   info fields: path, sha256, bytes (of the bytes actually on disk).

    cls = mc_protected_path(dest);
    assert(strcmp(cls, 'NONE'), 'mc:csv:protected_path', ...
        'REFUSED: %s is a protected scientific destination (%s); this writer is for fixtures only.', ...
        dest, cls);
    bytes = mc_trial_csv_bytes(T);
    info  = mc_atomic_write(mc_abs_path(dest), bytes, 'bytes');
end

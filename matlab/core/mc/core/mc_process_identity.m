function id = mc_process_identity()
% MC_PROCESS_IDENTITY  The identity of this MATLAB process, fixed for its lifetime.
%   id = mc_process_identity() returns struct(pid, start_utc, nonce). The
%   nonce (process id + first-call timestamp) is what reservations and attempt
%   ledgers record as their owner; a later process can never present the same
%   nonce. The function locks itself in memory so CLEAR cannot change it. No
%   random number is drawn.

    persistent pid0 start0 nonce0
    mlock;
    if isempty(nonce0)
        pid0   = feature('getpid');
        start0 = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyyMMdd''T''HHmmss.SSSSSS'));
        nonce0 = sprintf('%d_%s', pid0, start0);
    end
    id = struct('pid', pid0, 'start_utc', start0, 'nonce', nonce0);
end

function s = mc_utc_now()
% MC_UTC_NOW  Current UTC time as an ISO-8601 character vector.
%   Operational bookkeeping only; no scientific quantity depends on it.
    s = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
end

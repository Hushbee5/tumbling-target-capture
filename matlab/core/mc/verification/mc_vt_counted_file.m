function X = mc_vt_counted_file(file, key, X)
% MC_VT_COUNTED_FILE  Return X unchanged and append one call line to a file.
%   Used by verification-only runner overrides in CHILD PROCESSES, where an
%   in-memory counter (MC_VT_COUNTED) cannot be shared: each process counts into
%   its own file, so the parent can prove which process invoked what.
    fid = fopen(file, 'a');
    assert(fid > 0, 'mc:vt:count_file', 'Cannot append to %s.', file);
    fprintf(fid, '%d %s\n', feature('getpid'), key);
    fclose(fid);
end

function info = mc_atomic_write(dest, payload, kind, opts)
% MC_ATOMIC_WRITE  Write one file atomically and NEVER over an existing file.
%   info = mc_atomic_write(dest, bytes, 'bytes')        raw uint8 payload
%   info = mc_atomic_write(dest, S,     'mat')          fields of struct S become
%                                                       the saved variables (-v7)
%   info = mc_atomic_write(dest, payload, kind, opts)   opts.ctx   campaign context
%                                                       opts.hook  fault-hook name
%
%   PROTECTED DESTINATIONS (MC_PROTECTED_PATH), checked FIRST, before anything
%   is created:
%     CANONICAL_CSV, FREEZE_RECORD   refused ALWAYS ('mc:io:protected_path'); the
%                                    canonical CSV is published only by the local
%                                    transaction inside MC_SCIENTIFIC_TRIAL_TABLE
%     SCIENTIFIC_TREE                refused unless opts.ctx is a sealed, ISSUED
%                                    SCIENTIFIC context with an active LIVE LEASE
%                                    (MC_CAMPAIGN_GUARD 'write': the write happens
%                                    inside a boundary whose live checks passed)
%                                    and dest lies inside its checkpoint root
%
%   PROCEDURE (protocol Sec. 10.4, as baseline_tuning.m:591-602 but with NO
%   REPLACEMENT): refuse an existing dest; write a temporary sibling; rename it
%   with java.io.File.renameTo, which on Windows fails when the target exists,
%   re-checking existence around it; verify the bytes at dest. An interruption
%   leaves no dest (at worst a stale '.tmp-' file, never taken for a completed
%   file) or the complete dest. The temporary name uses the process id and a
%   timestamp; no random number is drawn.
%
%   info fields: path, sha256, bytes.

    if nargin < 4 || isempty(opts), opts = struct(); end
    assert(ischar(dest) && ~isempty(dest), 'mc:io:dest', 'dest must be a path.');

    cls = mc_protected_path(dest);
    switch cls
        case {'CANONICAL_CSV', 'FREEZE_RECORD'}
            error('mc:io:protected_path', ...
                'REFUSED: %s (%s) may only be written by its authorised transaction.', dest, cls);
        case 'SCIENTIFIC_TREE'
            ok = isfield(opts, 'ctx') && isstruct(opts.ctx) && isfield(opts.ctx, 'kind') ...
                 && strcmp(opts.ctx.kind, 'scientific');
            assert(ok, 'mc:io:protected_path', ...
                'REFUSED: %s lies in the scientific tree; a sealed scientific context is required.', dest);
            mc_campaign_guard(opts.ctx, 'write');
            ck = mc_abs_path(opts.ctx.root);
            assert(strncmpi(mc_abs_path(dest), [ck filesep], numel(ck) + 1), 'mc:io:protected_path', ...
                'REFUSED: %s is outside the campaign checkpoint %s.', dest, ck);
    end

    assert(~isfile(dest) && ~isfolder(dest), 'mc:io:exists', ...
        'REFUSED: %s already exists. A completed file is never overwritten.', dest);
    folder = fileparts(dest);
    assert(isfolder(folder), 'mc:io:folder', 'Destination folder %s does not exist.', folder);

    [~, ~, ext] = fileparts(dest);
    stamp = char(datetime('now', 'Format', 'yyyyMMddHHmmssSSSSSS'));
    tmp = sprintf('%s.tmp-%d-%s%s', dest(1:end-numel(ext)), feature('getpid'), stamp, ext);
    assert(~isfile(tmp), 'mc:io:tmp_exists', 'Temporary file %s already exists.', tmp);
    cleanupTmp = onCleanup(@() delete_if_exists(tmp));

    switch kind
        case 'bytes'
            assert(isa(payload, 'uint8'), 'mc:io:payload', 'bytes payload must be uint8.');
            fid = fopen(tmp, 'wb');
            assert(fid > 0, 'mc:io:open', 'Could not open %s for writing.', tmp);
            n = fwrite(fid, payload(:), 'uint8');
            st = fclose(fid);
            assert(n == numel(payload) && st == 0, 'mc:io:write', 'Short or failed write to %s.', tmp);
        case 'mat'
            assert(isstruct(payload) && isscalar(payload), 'mc:io:payload', ...
                'mat payload must be a scalar struct.');
            assert(strcmpi(ext, '.mat'), 'mc:io:ext', 'A MAT payload needs a .mat dest.');
            save(tmp, '-struct', 'payload', '-v7');
        otherwise
            error('mc:io:kind', 'Unknown payload kind ''%s''.', kind);
    end
    wantSha = baseline_sha256(tmp);

    if isfield(opts, 'hook') && ~isempty(opts.hook)
        mc_fault_hook('hit', opts.hook);          % verification fixtures only
    end

    assert(~isfile(dest), 'mc:io:exists', ...
        'REFUSED: %s appeared during the write. A completed file is never overwritten.', dest);
    ok = java.io.File(tmp).renameTo(java.io.File(dest));
    assert(logical(ok) && isfile(dest) && ~isfile(tmp), 'mc:io:rename', ...
        'Atomic rename %s -> %s failed; the destination was not written.', tmp, dest);

    gotSha = baseline_sha256(dest);
    assert(strcmp(gotSha, wantSha), 'mc:io:verify', ...
        'The bytes at %s do not hash to the bytes that were written.', dest);
    d = dir(dest);
    info = struct('path', dest, 'sha256', gotSha, 'bytes', d.bytes);
end

% =====================================================================
function delete_if_exists(f)
    if isfile(f)
        delete(f);
    end
end

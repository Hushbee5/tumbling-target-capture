function [hex, backend] = baseline_sha256(bytesOrPath, isPath)
% BASELINE_SHA256  SHA-256 of a file's raw bytes, or of a uint8 byte vector.
%   hex             = baseline_sha256(path)              hashes the file bytes
%   hex             = baseline_sha256(bytes, false)      hashes a uint8 vector
%   [hex, backend]  = baseline_sha256(...)               also reports the engine
%
%   Returns a 64-character LOWERCASE hex string, byte-identical to what GNU
%   coreutils sha256sum reports for the same bytes.
%
%   WHY THIS EXISTS. The baseline-support provenance chain (protocol Sec. 15.1)
%   is a byte aggregate over src/baselines/**, and base MATLAB ships no file
%   hash. This function is the single hashing primitive used by
%   BASELINE_MANIFEST and BASELINE_PREFLIGHT so that only one implementation can
%   ever be wrong.
%
%   RAW BYTES, ALWAYS. The file is opened with 'rb' and read as uint8. No line
%   ending, encoding or whitespace normalisation happens anywhere. A CRLF/LF
%   conversion therefore CHANGES the hash, exactly as recorded for the 17 frozen
%   Task 4 production files; a mismatch must be diagnosed, never assumed to be
%   tampering.
%
%   BACKENDS, in order:
%     'java'     java.security.MessageDigest - exact, available whenever the JVM
%                is present (the default for matlab -batch)
%     'certutil' Windows certutil -hashfile <f> SHA256 - used only when the JVM
%                is absent AND a path was supplied
%   Neither is a reimplementation of SHA-256: both are standard library
%   implementations. If neither is available the function ERRORS rather than
%   returning a weaker digest.

    if nargin < 2, isPath = true; end

    if isPath
        f = bytesOrPath;
        assert(ischar(f) || isstring(f), 'baseline_sha256:path', ...
            'A file path must be a character vector or string.');
        f = char(f);
        assert(exist(f, 'file') == 2, 'baseline_sha256:missing', ...
            'File does not exist: %s', f);
        fid = fopen(f, 'rb');
        assert(fid > 0, 'baseline_sha256:open', 'Could not open %s for reading.', f);
        cleanup = onCleanup(@() fclose(fid));
        bytes = fread(fid, Inf, '*uint8');
        clear cleanup                                  % close before any hashing
    else
        bytes = bytesOrPath(:);
        assert(isa(bytes, 'uint8'), 'baseline_sha256:bytes', ...
            'Byte input must be uint8; got %s.', class(bytes));
    end

    if usejava('jvm')
        md = java.security.MessageDigest.getInstance('SHA-256');
        md.update(bytes);
        raw = typecast(md.digest(), 'uint8');          % int8 -> uint8
        hex = lower(reshape(sprintf('%02x', raw), 1, []));
        backend = 'java';
        return
    end

    % ---- JVM-free fallback: Windows certutil, file paths only ---------------
    assert(isPath, 'baseline_sha256:nojvm_bytes', ...
        ['No JVM is available, so a raw byte vector cannot be hashed. Run ' ...
         'MATLAB with the JVM enabled for byte hashing.']);
    [st, txt] = system(sprintf('certutil -hashfile "%s" SHA256', f));
    assert(st == 0, 'baseline_sha256:certutil', ...
        'Neither the JVM nor certutil could hash %s (certutil exit %d).', f, st);
    tok = regexp(txt, '(?m)^\s*([0-9a-fA-F]{64})\s*$', 'tokens', 'once');
    assert(~isempty(tok), 'baseline_sha256:certutil_parse', ...
        'Could not parse a SHA-256 digest out of certutil output for %s.', f);
    hex = lower(tok{1});
    backend = 'certutil';
end

function S = mc_record_scan(root, condition, binding, trialIds)
% MC_RECORD_SCAN  Inventory of the records of one condition, for resume and closure.
%   S = mc_record_scan(root, condition, binding, trialIds)
%
%   Every regular file in <root>/<condition> must be either a record named
%   <cond>_t<NNN>_<method>.mat or a STALE temporary file left by an
%   interrupted atomic write (name containing '.tmp-'); anything else aborts.
%   A stale temporary file is NOT a record: its (trial, method) is pending and
%   may be rerun from scratch (Sec. 10.4). Every record found is read with
%   MC_RECORD_READ, so a binding mismatch aborts.
%
%   S.present  logical numel(trialIds) x 3, method order proposed,
%              nominal_mpc, apf
%   S.paths    cellstr of the same shape ('' where absent)
%   S.status   cellstr of the same shape ('' where absent)
%   S.stale_tmp  cellstr of stale temporary files
%   S.outside    records of trial ids outside trialIds (reported, not read)

    c = mc_constants();
    methods = c.design.methods;
    n = numel(trialIds);
    S = struct('present', false(n, 3), 'paths', {repmat({''}, n, 3)}, ...
               'status', {repmat({''}, n, 3)}, 'stale_tmp', {{}}, 'outside', {{}});
    folder = fullfile(root, condition);
    if ~isfolder(folder)
        return
    end
    d = dir(folder);
    for i = 1:numel(d)
        if d(i).isdir
            continue
        end
        name = d(i).name;
        if contains(name, '.tmp-')
            S.stale_tmp{end+1} = fullfile(folder, name);
            continue
        end
        tok = regexp(name, ['^' condition '_t(\d{3})_(proposed|nominal_mpc|apf)\.mat$'], ...
                     'tokens', 'once');
        assert(~isempty(tok), 'mc:record:unknown_file', ...
            'ABORT: unexpected file %s in the %s checkpoint folder.', name, condition);
        tid = str2double(tok{1});
        mi  = find(strcmp(methods, tok{2}), 1);
        ti  = find(trialIds == tid, 1);
        if isempty(ti)
            S.outside{end+1} = fullfile(folder, name);
            continue
        end
        f = fullfile(folder, name);
        rec = mc_record_read(f, binding);
        S.present(ti, mi) = true;
        S.paths{ti, mi}   = f;
        S.status{ti, mi}  = rec.status;
    end
end

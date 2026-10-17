function rec = mc_record_read(f, binding)
% MC_RECORD_READ  Load one record and verify it against the expected binding.
%   rec = mc_record_read(f, binding) refuses a record whose schema is
%   unknown, whose content disagrees with its file name, or whose binding is
%   not ISEQUAL to the expected binding ('mc:record:binding'). Any mismatch
%   ABORTS (protocol Sec. 10.4).

    assert(isfile(f), 'mc:record:missing', 'Record not found: %s', f);
    S = load(f, 'rec');
    assert(isfield(S, 'rec'), 'mc:record:schema', 'File %s carries no record.', f);
    rec = S.rec;
    assert(isstruct(rec) && isfield(rec, 'schema') && strcmp(rec.schema, 'task4_mc_run_record_v2'), ...
        'mc:record:schema', 'File %s is not a task4_mc_run_record_v2 record.', f);
    [~, name] = fileparts(f);
    want = sprintf('%s_t%03d_%s', rec.condition, rec.trial_id, rec.method);
    assert(strcmp(name, want), 'mc:record:identity', ...
        'Record %s describes %s.', name, want);
    assert(isequal(rec.binding, binding), 'mc:record:binding', ...
        'ABORT: record %s is bound to a different provenance than this campaign.', name);
end

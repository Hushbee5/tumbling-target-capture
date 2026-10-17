function F = mc_freeze_record_parse(txt)
% MC_FREEZE_RECORD_PARSE  Read the declared identities of the trial-table freeze record.
%   F = mc_freeze_record_parse(txt) parses the text of
%   notes/task4_mc_trial_table_freeze_record.md for the entries of protocol
%   Sec. 10.1.1, each on its own line as '<label>  <value>':
%
%     canonical CSV path                results/task4/mc/task4_mc_trials.csv
%     canonical CSV SHA-256             <64 lowercase hex>
%     frozen MC protocol SHA-256        <64 lowercase hex>
%     MC-source aggregate               <64 lowercase hex>
%     MC implementation commit SHA      <40 lowercase hex>
%     seed                              116075   (RandStream 'mt19937ar')
%     N_PHYSICAL                        100
%     mapping implementation file       src/mc/trials/mc_trial_mapping.m
%     mapping implementation SHA-256    <64 lowercase hex>
%     scientific method runs at freeze  ZERO
%
%   The two mapping lines carry the "15-draw mapping identity" of Sec. 10.1.1:
%   the SHA-256 of the src/mc file that implements Sec. 3.4 (the protocol side
%   of that identity is the frozen protocol SHA-256 above). Each label must
%   occur EXACTLY ONCE at the start of a line (leading spaces allowed); a
%   missing or repeated label, or a malformed value, aborts with
%   'mc:freeze:label'. This is the parsing contract the future freeze record
%   must satisfy; the record itself does not exist yet.

    F = struct();
    F.csv_path            = one(txt, 'canonical CSV path',             '(\S+)');
    F.csv_sha256          = one(txt, 'canonical CSV SHA-256',          '([0-9a-f]{64})');
    F.protocol_sha256     = one(txt, 'frozen MC protocol SHA-256',     '([0-9a-f]{64})');
    F.mc_source_aggregate = one(txt, 'MC-source aggregate',            '([0-9a-f]{64})');
    F.mc_impl_commit      = one(txt, 'MC implementation commit SHA',   '([0-9a-f]{40})');
    F.seed                = str2double(one(txt, 'seed',                '(\d+)'));
    F.N_PHYSICAL          = str2double(one(txt, 'N_PHYSICAL',          '(\d+)'));
    F.mapping_file        = one(txt, 'mapping implementation file',    '(\S+)');
    F.mapping_sha256      = one(txt, 'mapping implementation SHA-256', '([0-9a-f]{64})');
    F.runs_at_freeze      = one(txt, 'scientific method runs at freeze', '(\S+)');
end

% =====================================================================
function v = one(txt, label, valuePattern)
    pat = ['(?m)^[ \t]*' regexptranslate('escape', label) '[ \t]+' valuePattern ...
           '[ \t]*(?:\([^\n]*\))?[ \t]*\r?$'];
    tok = regexp(txt, pat, 'tokens');
    assert(numel(tok) == 1, 'mc:freeze:label', ...
        'The freeze record must declare ''%s'' exactly once (found %d).', label, numel(tok));
    v = tok{1}{1};
end

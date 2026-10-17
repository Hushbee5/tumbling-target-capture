function b = mc_binding(kind, pre)
% MC_BINDING  The provenance binding carried by every checkpoint record.
%   b = mc_binding('VERIFICATION')       non-scientific fixture records
%   b = mc_binding('SCIENTIFIC', pre)    pre = a PASSED MC_PREFLIGHT('execution')
%
%   Protocol Sec. 10.4: the checkpoint binds the protocol SHA, the MC-source
%   aggregate and implementation commit, the trial CSV SHA, the trial-table
%   freeze-record SHA and the frozen identity set of Section 1; any mismatch
%   ABORTS (MC_RECORD_READ compares the whole binding with ISEQUAL).
%
%   A VERIFICATION binding carries explicit non-identities in the four
%   scientific slots. They are not hexadecimal, so they can never satisfy a
%   scientific check, and a VERIFICATION record can never be read under a
%   SCIENTIFIC binding.

    c = mc_constants();
    b.schema          = 'task4_mc_binding_v1';
    b.protocol_path   = c.protocol.path;
    b.protocol_sha256 = c.protocol.sha256;
    ids = struct();
    for k = 1:size(c.files, 1)
        ids.(c.files{k, 1}) = c.files{k, 3};
    end
    ids.production17_aggregate = c.production17.aggregate;
    ids.r7_aggregate           = c.r7.aggregate;
    ids.anchor_commit          = c.anchor.commit;
    ids.anchor_src_tree        = c.anchor.src_tree;
    b.identity_set = ids;

    switch kind
        case 'VERIFICATION'
            b.mode                 = 'VERIFICATION_ONLY';
            b.mc_source_aggregate  = 'NOT_FROZEN__VERIFICATION_ONLY';
            b.mc_impl_commit       = 'NOT_FROZEN__VERIFICATION_ONLY';
            b.trial_csv_sha256     = 'FIXTURE_TABLE__NOT_SCIENTIFIC';
            b.freeze_record_sha256 = 'NOT_APPLICABLE__VERIFICATION_ONLY';
        case 'SCIENTIFIC'
            assert(nargin >= 2 && isstruct(pre) && isfield(pre, 'mode') ...
                && strcmp(pre.mode, 'execution') && isequal(pre.authorised, true), ...
                'mc:binding:not_authorised', ...
                'REFUSED: a scientific binding requires a PASSED execution preflight.');
            b.mode                 = 'SCIENTIFIC';
            b.mc_source_aggregate  = pre.verified.mc_source_aggregate;
            b.mc_impl_commit       = pre.verified.mc_impl_commit;
            b.trial_csv_sha256     = pre.verified.trial_csv_sha256;
            b.freeze_record_sha256 = pre.verified.freeze_record_sha256;
        otherwise
            error('mc:binding:kind', 'Unknown binding kind ''%s''.', kind);
    end
end

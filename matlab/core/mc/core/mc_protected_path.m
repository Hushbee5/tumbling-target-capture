function cls = mc_protected_path(p)
% MC_PROTECTED_PATH  Classify a destination against the scientific artefacts.
%   cls = mc_protected_path(p) returns
%     'CANONICAL_CSV'    results/task4/mc/task4_mc_trials.csv - writable ONLY by
%                        the scientific publish transaction inside
%                        MC_SCIENTIFIC_TRIAL_TABLE (a local function there)
%     'FREEZE_RECORD'    notes/task4_mc_trial_table_freeze_record.md - written
%                        by a person for review; no src/mc writer may create it
%     'SCIENTIFIC_TREE'  anything else under results/task4/mc - writable only
%                        with an issued SCIENTIFIC campaign context inside a
%                        live-verified boundary (MC_CAMPAIGN_GUARD 'write')
%     'NONE'             anywhere else
%   Paths are compared in canonical absolute form (MC_ABS_PATH), case-
%   insensitively, so no second spelling of a protected location slips through.

    c = mc_constants();
    root = mc_repo_root();
    a   = mc_abs_path(p);
    csv = mc_abs_path(fullfile(root, strrep(c.csv.path, '/', filesep)));
    fr  = mc_abs_path(fullfile(root, strrep(c.freeze_record.path, '/', filesep)));
    sci = mc_abs_path(fullfile(root, strrep(c.mc.dest_dir, '/', filesep)));
    if strcmpi(a, csv)
        cls = 'CANONICAL_CSV';
    elseif strcmpi(a, fr)
        cls = 'FREEZE_RECORD';
    elseif strcmpi(a, sci) || strncmpi(a, [sci filesep], numel(sci) + 1)
        cls = 'SCIENTIFIC_TREE';
    else
        cls = 'NONE';
    end
end

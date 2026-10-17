function R = mc_v18_freeze_history(tmpRoot)
% MC_V18_FREEZE_HISTORY  Trial-freeze provenance from Git history (F8). NON-SCIENTIFIC.
%   Synthetic TEMPORARY repositories (never the project repository) with the
%   canonical relative paths. MC_TRIAL_FREEZE_HISTORY must accept exactly the
%   valid history - implementation commit, then ONE later commit adding the
%   CSV and the freeze record together, parent holding neither, never touched
%   again - and refuse each violation. The freeze-record parser must extract
%   the mapping-implementation file and SHA-256, and refuse a record without
%   them.

    R.name = 'V18 trial-freeze Git history and mapping binding';
    ch = {};
    c = mc_constants();
    csv = c.csv.path;  fr = c.freeze_record.path;  map = 'src/mc/trials/mc_trial_mapping.m';

    r = new_repo(tmpRoot, 'valid');
    commit(r, {map, 'mapping'}, 'impl');  I = head(r);
    commit(r, {csv, 'csv'; fr, 'record'}, 'freeze');  T = head(r);
    H = mc_trial_freeze_history(r, csv, fr, I);
    ch{end+1} = mc_vt_check('valid history: accepted, freeze commit identified', ...
        H.pass && strcmp(H.trial_commit, T) && isfinite(H.trial_commit_time), strjoin(H.reasons, '; '));

    r = new_repo(tmpRoot, 'separate');
    commit(r, {map, 'mapping'}, 'impl');  I = head(r);
    commit(r, {csv, 'csv'}, 'csv only');
    commit(r, {fr, 'record'}, 'record only');
    ch{end+1} = refused(mc_trial_freeze_history(r, csv, fr, I), 'CSV and record in different commits');

    r = new_repo(tmpRoot, 'modified');
    commit(r, {map, 'mapping'}, 'impl');  I = head(r);
    commit(r, {csv, 'csv'; fr, 'record'}, 'freeze');
    commit(r, {fr, 'record edited'}, 'edit record');
    ch{end+1} = refused(mc_trial_freeze_history(r, csv, fr, I), 'freeze record modified afterwards');

    r = new_repo(tmpRoot, 'impl_after');
    commit(r, {'README.md', 'x'}, 'root');
    commit(r, {csv, 'csv'; fr, 'record'}, 'freeze');
    commit(r, {map, 'mapping'}, 'impl');  I = head(r);
    ch{end+1} = refused(mc_trial_freeze_history(r, csv, fr, I), 'implementation commit after the freeze');

    r = new_repo(tmpRoot, 'impl_same');
    commit(r, {'README.md', 'x'}, 'root');
    commit(r, {map, 'mapping'; csv, 'csv'; fr, 'record'}, 'impl and freeze together');  I = head(r);
    ch{end+1} = refused(mc_trial_freeze_history(r, csv, fr, I), 'implementation commit IS the freeze commit');

    r = new_repo(tmpRoot, 'readded');
    commit(r, {map, 'mapping'}, 'impl');  I = head(r);
    commit(r, {csv, 'early csv'}, 'early');
    mc_vt_git(r, ['rm -q -- ' csv]);  mc_vt_git(r, 'commit -q -m drop');
    commit(r, {csv, 'csv'; fr, 'record'}, 'freeze');
    ch{end+1} = refused(mc_trial_freeze_history(r, csv, fr, I), 'CSV added, deleted and re-added');

    txt = sprintf(['canonical CSV path  %s\ncanonical CSV SHA-256  %s\nfrozen MC protocol SHA-256  %s\n' ...
        'MC-source aggregate  %s\nMC implementation commit SHA  %s\nseed  116075\nN_PHYSICAL  100\n' ...
        'mapping implementation file  %s\nmapping implementation SHA-256  %s\n' ...
        'scientific method runs at freeze  ZERO\n'], csv, repmat('1', 1, 64), c.protocol.sha256, ...
        repmat('2', 1, 64), repmat('3', 1, 40), map, repmat('4', 1, 64));
    F = mc_freeze_record_parse(txt);
    ch{end+1} = mc_vt_check('parser extracts the mapping implementation file and SHA-256', ...
        strcmp(F.mapping_file, map) && strcmp(F.mapping_sha256, repmat('4', 1, 64)));
    [ok, got] = mc_vt_throws(@() mc_freeze_record_parse(regexprep(txt, 'mapping implementation SHA-256[^\n]*\n', '')), ...
        'mc:freeze:label');
    ch{end+1} = mc_vt_check('parser refuses a record without the mapping SHA-256', ok, got);
    R.checks = [ch{:}];
end

% =====================================================================
function r = new_repo(tmpRoot, tag)
    r = fullfile(tmpRoot, ['v18_' tag]);
    mkdir(r);
    mc_vt_git(r, 'init -q');
end

function commit(r, files, msg)
    for i = 1:size(files, 1)
        mc_vt_write_text(r, files{i, 1}, sprintf('%s\n', files{i, 2}));
        mc_vt_git(r, ['add -- ' files{i, 1}]);
    end
    [~, e] = mc_vt_git(r, sprintf('commit -q -m "%s"', msg));
    assert(e == 0, 'mc:vt:commit', 'Fixture commit failed in %s.', r);
end

function h = head(r)
    h = mc_vt_git(r, 'rev-parse HEAD');
end

function c = refused(H, label)
    c = mc_vt_check(['history refused: ' label], ~H.pass && ~isempty(H.reasons), strjoin(H.reasons, '; '));
end

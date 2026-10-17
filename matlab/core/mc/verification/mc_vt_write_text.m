function mc_vt_write_text(root, rel, txt)
% MC_VT_WRITE_TEXT  Write ASCII text (LF) to <root>/<rel>, creating folders. Fixtures only.
    f = fullfile(root, strrep(rel, '/', filesep));
    if ~isfolder(fileparts(f)), mkdir(fileparts(f)); end
    fid = fopen(f, 'wb');
    assert(fid > 0, 'mc:vt:write', 'Cannot write %s.', f);
    fwrite(fid, uint8(txt), 'uint8');
    fclose(fid);
end

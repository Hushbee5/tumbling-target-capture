function X = mc_vt_counted(cnt, key, X)
% MC_VT_COUNTED  Return X unchanged and count one call under key (fixture overrides).
%   Used by verification-only runner overrides to prove whether - and how often -
%   the campaign machinery invoked a method. cnt is a containers.Map (a handle).
    if ~isKey(cnt, key), cnt(key) = 0; end
    cnt(key) = cnt(key) + 1;
end

function [ok, got] = mc_vt_throws(fn, id)
% MC_VT_THROWS  True iff calling fn() throws an error whose identifier is id.
%   [ok, got] = mc_vt_throws(fn, id). id may end in '*' to accept any
%   identifier with that prefix. got is the identifier actually thrown, or
%   'NO_ERROR'.
    got = 'NO_ERROR';
    try
        fn();
    catch ME
        got = ME.identifier;
    end
    if endsWith(id, '*')
        ok = startsWith(got, id(1:end-1));
    else
        ok = strcmp(got, id);
    end
end

function s = mc_exception_summary(ME)
% MC_EXCEPTION_SUMMARY  Plain-struct record of a caught exception.
%   s = mc_exception_summary(ME) keeps the identifier, the message and the
%   top of the stack (file, name, line) so a record can be saved and read
%   back without MException objects. An empty input yields an empty struct.

    s = struct('identifier', '', 'message', '', 'stack', struct('file', {}, ...
               'name', {}, 'line', {}));
    if isempty(ME)
        return
    end
    s.identifier = ME.identifier;
    s.message    = ME.message;
    st = ME.stack;
    n  = min(numel(st), 8);
    for i = 1:n
        s.stack(i).file = st(i).file;
        s.stack(i).name = st(i).name;
        s.stack(i).line = st(i).line;
    end
end

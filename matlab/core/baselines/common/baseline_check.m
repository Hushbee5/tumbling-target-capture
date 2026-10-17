function c = baseline_check(name, pass, fmt, varargin)
% BASELINE_CHECK  One verification check result, in a uniform shape.
%   c = baseline_check(name, pass, fmt, ...) builds the record every V-test in
%   src/baselines/verification returns.
%
%   c.name    the V-test clause, e.g. 'V1a gradient vs independent central FD'
%   c.pass    logical
%   c.detail  the measured numbers, ALWAYS formatted, whether the check passed
%             or failed
%
%   THE DETAIL IS RECORDED ON A PASS TOO. A verification record that only shows
%   numbers when something broke cannot be audited: the reviewer has no way to
%   tell a comfortable margin from one that barely held. Every check therefore
%   reports its measured value and its threshold.

    c.name   = name;
    c.pass   = logical(pass);
    if nargin < 3
        c.detail = '';
    else
        c.detail = sprintf(fmt, varargin{:});
    end
end

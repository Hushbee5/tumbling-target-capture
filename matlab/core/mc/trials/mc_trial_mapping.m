function row = mc_trial_mapping(u)
% MC_TRIAL_MAPPING  The frozen 15-draw -> physical-trial mapping (protocol Sec. 3.4).
%   row = mc_trial_mapping(u) evaluates, for ONE trial with u = U(:, i), EXACTLY
%   the MATLAB expressions of protocol Sec. 3.4, in that order. This file is
%   the single implementation of the mapping; the trial-table freeze record
%   binds its SHA-256 (Sec. 10.1.1).
%
%   The DERIVED fields are the execution inputs. Recomputing them from the raw
%   draws is an audit, never a source of trial inputs (Sec. 3.4, 10.1).
%
%   row fields: r0, v0, x0, q0, w0, Idiag, I_true, I_nom

    assert(isa(u, 'double') && isreal(u) && numel(u) == 15, 'mc:mapping:u', ...
        'u must be a real double 15-vector.');
    u = u(:);

    r0 = [0; -10; 0] + (2*u(1:3) - 1);                 % [m]
    v0 = 0.01 * (2*u(4:6) - 1);                        % [m/s]
    x0 = [r0; v0];

    % Shoemake (1992), components written in HAMILTON SCALAR-FIRST order [s; x; y; z]
    a  = sqrt(1 - u(7));
    b  = sqrt(u(7));
    q0 = [ b*cos(2*pi*u(9)) ;
           a*sin(2*pi*u(8)) ;
           a*cos(2*pi*u(8)) ;
           b*sin(2*pi*u(9)) ];
    q0 = q0 / norm(q0);
    % sign canonicalisation, storage only; deterministic tie rule for q0(1) == 0
    if q0(1) < 0 || ( q0(1) == 0 && q0(1 + find(q0(2:4) ~= 0, 1)) < 0 )
        q0 = -q0;
    end

    % isotropic direction on S^2
    z   = 2*u(10) - 1;
    phi = 2*pi*u(11);
    d   = [ sqrt(1 - z^2)*cos(phi) ; sqrt(1 - z^2)*sin(phi) ; z ];
    % magnitude uniform on (1, 5) deg/s, converted to rad/s
    wmag_deg = 1 + 4*u(12);
    w0  = (wmag_deg * pi / 180) * d;                   % [rad/s], body frame

    % principal inertia
    s      = 0.85 + 0.30*u(13:15);
    Idiag  = [20; 25; 30] .* s;                        % [kg m^2]
    I_true = diag(Idiag);
    I_nom  = diag([20, 25, 30]);                       % = params().target.I

    row = struct('r0', r0, 'v0', v0, 'x0', x0, 'q0', q0, 'w0', w0, ...
                 'Idiag', Idiag, 'I_true', I_true, 'I_nom', I_nom);
end

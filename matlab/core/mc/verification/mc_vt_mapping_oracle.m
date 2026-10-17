function row = mc_vt_mapping_oracle(u)
% MC_VT_MAPPING_ORACLE  An INDEPENDENT test implementation of protocol Sec. 3.4.
%   row = mc_vt_mapping_oracle(u) re-derives the physical row from the 15
%   draws with deliberately DIFFERENT arithmetic from MC_TRIAL_MAPPING, so the
%   generator audit does not validate the production mapping against itself:
%     r0   component-wise, -1 + 2u (x, z) and -11 + 2u (y)
%     q0   Shoemake in its native (x, y, z, w) order, then permuted to [w;x;y;z],
%          normalised, and sign-canonicalised by an explicit first-non-zero rule
%     d    spherical coordinates: theta = acos(2u10 - 1), phi = 2 pi u11
%     |w|  deg2rad(1 + 4 u12)
%     I    [20 25 30] .* (0.85 + 0.3 u) written element by element
%   Agreement is required to a few ulp (the formulas differ in rounding), and
%   hand-derived rows are checked exactly by MC_V02_GENERATOR_AUDIT.

    u = u(:);
    r0 = [-1 + 2*u(1); -11 + 2*u(2); -1 + 2*u(3)];
    v0 = [0.02*u(4) - 0.01; 0.02*u(5) - 0.01; 0.02*u(6) - 0.01];

    x = sqrt(1 - u(7)) * sin(2*pi*u(8));
    y = sqrt(1 - u(7)) * cos(2*pi*u(8));
    z = sqrt(u(7))     * sin(2*pi*u(9));
    w = sqrt(u(7))     * cos(2*pi*u(9));
    q = [w; x; y; z];
    q = q ./ sqrt(q.' * q);
    k = find(q ~= 0, 1, 'first');
    if q(k) < 0
        q = -q;
    end

    theta = acos(2*u(10) - 1);
    phi   = 2*pi*u(11);
    d     = [sin(theta)*cos(phi); sin(theta)*sin(phi); cos(theta)];
    w0    = deg2rad(1 + 4*u(12)) * d;

    Idiag = [20*(0.85 + 0.3*u(13)); 25*(0.85 + 0.3*u(14)); 30*(0.85 + 0.3*u(15))];
    row = struct('r0', r0, 'v0', v0, 'q0', q, 'w0', w0, 'Idiag', Idiag);
end

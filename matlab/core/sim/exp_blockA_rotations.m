% EXP_BLOCKA_ROTATIONS  Hands-on experiments for Block A (A1-A6).
%   Run the whole file, or one section at a time (Ctrl+Enter) as you work
%   through notes/block_A_notes.md. Every section prints numbers you can
%   check against the expectations written next to them.
%
%   A1/A2  rotation direction: R (body->world) vs R.' (world->body)
%   A2     rotation-matrix properties: orthogonality, determinant
%   A3     quaternion <-> axis-angle round trip; q and -q
%   A4     constant angular velocity -> capture point traces a circle
%   A5     symmetric vs asymmetric inertia -> tumbling off/on
%   A6     crude fixed-step Euler vs ode45
%
%   Conventions: notes/conventions.md (Hamilton scalar-first, R = body->world).

clear; clc; close all;
thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..')));
p = params();

%% A1/A2 -- rotation direction (the one that must stick)
fprintf('=== A1/A2  R yonu:  v_world = R * v_body ===\n');
q90z = quat_from_axis_angle([0;0;1], pi/2);     % 90 deg about body z
R    = quat_to_rotm(q90z);
vb   = [1; 0; 0];                               % vector along body x
fprintf('  v_body      = [%6.3f %6.3f %6.3f]\n', vb);
fprintf('  R   * v_body = [%6.3f %6.3f %6.3f]   <- DOGRU  (body -> world)\n', R*vb);
fprintf('  R.'' * v_body = [%6.3f %6.3f %6.3f]   <- TERS   (world -> body)\n', R.'*vb);
fprintf('  aradaki fark = %.3f m   ("fark etmez" olsaydi 0 cikardi)\n', norm(R*vb - R.'*vb));
fprintf('  R.'' * (R * v_body) = [%6.3f %6.3f %6.3f]  <- ileri-geri, basa doner\n', R.'*(R*vb));

%% A2 -- rotation-matrix properties
fprintf('\n=== A2  R ozellikleri ===\n');
fprintf('  norm(R.''*R - I) = %.3e   (0 olmali: ortogonal, uzunluk korunur)\n', norm(R.'*R - eye(3)));
fprintf('  det(R) - 1      = %.3e   (0 olmali: gercek donme, ayna degil)\n', det(R) - 1);

%% A3 -- quaternion <-> axis-angle, and q vs -q
fprintf('\n=== A3  quaternion <-> axis-angle ===\n');
theta_in = deg2rad(90);  axis_in = [0;0;1];
q        = quat_from_axis_angle(axis_in, theta_in);
theta_out = 2*acos(q(1));                        % geri cozum: aci
axis_out  = q(2:4) / norm(q(2:4));               % geri cozum: eksen
fprintf('  q = [%.4f %.4f %.4f %.4f]  (q0 = cos(theta/2) = %.4f)\n', q, cos(theta_in/2));
fprintf('  geri cozum: aci = %.1f deg, eksen = [%.0f %.0f %.0f]\n', ...
    rad2deg(theta_out), axis_out);
fprintf('  norm(R(q) - R(-q)) = %.3e   (0: q ve -q AYNI fiziksel yonelim)\n', ...
    norm(quat_to_rotm(q) - quat_to_rotm(-q)));

%% A4 -- constant angular velocity: capture point must trace a clean circle
fprintf('\n=== A4  sabit w -> capture point daire cizer ===\n');
pA4 = p;
pA4.target.w0    = [0; 0; deg2rad(10)];          % 10 deg/s about principal z
pA4.sim.T_final  = 36;                           % exactly one full turn
[~, qA4, wA4] = target_tumbling_model(pA4);
pcpA4 = capture_point_trajectory(qA4, wA4, pA4);
fprintf('  w sabit mi?      max|w - w0| = %.3e rad/s   (~0 beklenir)\n', ...
    max(vecnorm(wA4 - pA4.target.w0)));
fprintf('  capture yaricapi = %.6f .. %.6f m           (sabit beklenir)\n', ...
    min(vecnorm(pcpA4)), max(vecnorm(pcpA4)));
fprintf('  z bileseni       = %.6f .. %.6f m           (z ekseni donusu: sabit)\n', ...
    min(pcpA4(3,:)), max(pcpA4(3,:)));

figure('Name','A4 sabit w','Color','w');
plot3(pcpA4(1,:), pcpA4(2,:), pcpA4(3,:), 'b-', 'LineWidth', 1.4); hold on;
plot3(0,0,0,'k+','MarkerSize',10);
axis equal; grid on; view(35,25);
xlabel('x [m]'); ylabel('y [m]'); zlabel('z [m]');
title('A4: sabit w -> capture point duzgun daire');

%% A5 -- symmetric vs asymmetric inertia: the source of tumbling
fprintf('\n=== A5  inertia: simetrik vs asimetrik (ayni w0) ===\n');
pSym = p;  pSym.target.I = diag([25 25 25]);     % spherical: no cross-coupling
pAsy = p;  pAsy.target.I = diag([20 25 30]);     % asymmetric: tumbling
[tS, ~, wS] = target_tumbling_model(pSym);
[tA, ~, wA] = target_tumbling_model(pAsy);
fprintf('  simetrik  diag(25,25,25): max|w - w0| = %.3e rad/s  (~0: TUMBLING YOK)\n', ...
    max(vecnorm(wS - pSym.target.w0)));
fprintf('  asimetrik diag(20,25,30): max|w - w0| = %.3e rad/s  (buyuk: TUMBLING VAR)\n', ...
    max(vecnorm(wA - pAsy.target.w0)));

figure('Name','A5 inertia etkisi','Color','w');
subplot(2,1,1);
plot(tS, rad2deg(wS)', 'LineWidth', 1.2); grid on;
ylabel('w [deg/s]'); title('A5: simetrik inertia -> w sabit'); legend('w_x','w_y','w_z');
subplot(2,1,2);
plot(tA, rad2deg(wA)', 'LineWidth', 1.2); grid on;
xlabel('t [s]'); ylabel('w [deg/s]'); title('asimetrik inertia -> w salinir (tumbling)');

%% A5b -- asymmetric inertia ALONE does not mean tumbling
fprintf('\n=== A5b  ana eksen donusu vs tumbling (I ayni, sadece w0 degisiyor) ===\n');
fprintf('  I = diag([20 25 30]) -- asagidaki TUM kosularda ayni (asimetrik)\n');
pB = p;  pB.sim.T_final = 200;
spin = { 'x ekseni (I=20, en kucuk)   ', [0.10; 0.00; 0.00];
         'y ekseni (I=25, ORTA)       ', [0.00; 0.10; 0.00];
         'z ekseni (I=30, en buyuk)   ', [0.00; 0.00; 0.10];
         'genel yon (3 eksene yayilmis)', [0.06; 0.06; 0.06] };
for k = 1:size(spin,1)
    pk = pB;  pk.target.w0 = spin{k,2};
    [~, ~, wk] = target_tumbling_model(pk);
    fprintf('  %-30s -> max|w - w0| = %.3e rad/s\n', spin{k,1}, ...
        max(vecnorm(wk - spin{k,2})));
end
fprintf('  -> Saf ana eksen donusunde w SABIT: I*w, w ile ayni yonde oldugundan\n');
fprintf('     w x (I*w) = 0. Tumbling icin w birden fazla ana eksene yayilmali.\n');

% Which principal axis is stable? (intermediate axis theorem)
fprintf('\n  --- ayni bozucu (0.001) eklenince: hangi eksen kararli? ---\n');
pC = p;  pC.sim.T_final = 3000;  pC.sim.dt = 1;
pert = { 'z (I=30, EN BUYUK) + bozucu', [0.001; 0.001; 0.100], 3;
         'y (I=25, ORTA)     + bozucu', [0.001; 0.100; 0.001], 2 };
for k = 1:2
    pk = pC;  pk.target.w0 = pert{k,2};
    ax = pert{k,3};  other = setdiff(1:3, ax);
    [~, ~, wk] = target_tumbling_model(pk);
    fprintf('  %s:\n', pert{k,1});
    fprintf('     ana eksen w_%d : %+.3f -> [%+.3f .. %+.3f] rad/s\n', ...
        ax, pert{k,2}(ax), min(wk(ax,:)), max(wk(ax,:)));
    fprintf('     bozucu buyudu : 0.0010 -> %.4f rad/s\n', max(max(abs(wk(other,:)))));
end
fprintf('  -> En buyuk (ve en kucuk) ana eksen KARARLI; ORTA eksen KARARSIZ:\n');
fprintf('     bozucu buyur, donme isaret degistirir = Dzhanibekov / intermediate\n');
fprintf('     axis theorem. Gercek uzay copu bu yuzden genelde karmasik tumbler.\n');

%% A6 -- crude fixed-step Euler vs ode45
fprintf('\n=== A6  kaba Euler (dt = 1 s, renormalize YOK) vs ode45 ===\n');
I  = p.target.I;
y  = [p.target.q0; p.target.w0];
dtE = 1.0;
nE  = round(p.sim.T_final / dtE);
H0  = quat_to_rotm(y(1:4)) * (I * y(5:7));       % initial angular momentum (world)
qErrE = 0; HdriftE = 0;
for k = 1:nE
    qk = y(1:4);  wk = y(5:7);
    dy = [0.5 * Omega_local(wk) * qk;
          I \ ( -cross(wk, I*wk) )];
    y  = y + dtE * dy;                            % forward Euler, no renormalization
    qErrE   = max(qErrE, abs(norm(y(1:4)) - 1));
    Hk      = quat_to_rotm(y(1:4)) * (I * y(5:7));
    HdriftE = max(HdriftE, norm(Hk - H0) / norm(H0));
end

[~, qO, wO] = target_tumbling_model(p);           % ode45 reference
qErrO = max(abs(sqrt(sum(qO.^2,1)) - 1));
HdriftO = 0;
for k = 1:size(qO,2)
    Hk = quat_to_rotm(qO(:,k)) * (I * wO(:,k));
    HdriftO = max(HdriftO, norm(Hk - H0) / norm(H0));
end
fprintf('  Euler  dt=1s : quaternion norm hatasi = %.3e , acisal momentum drift = %.3e\n', ...
    qErrE, HdriftE);
fprintf('  ode45        : quaternion norm hatasi = %.3e , acisal momentum drift = %.3e\n', ...
    qErrO, HdriftO);
fprintf('  oran (Euler/ode45): norm hatasi %.1e kat kotu\n', qErrE / max(qErrO, eps));

fprintf('\nBitti. Beklentiler icin notes/block_A_notes.md.\n');

%% ----- local functions -----
function M = Omega_local(w)
% Quaternion-rate matrix for scalar-first q with body-frame w (conventions.md).
    wx = w(1); wy = w(2); wz = w(3);
    M = [ 0,  -wx, -wy, -wz;
          wx,  0,   wz, -wy;
          wy, -wz,  0,   wx;
          wz,  wy, -wx,  0 ];
end

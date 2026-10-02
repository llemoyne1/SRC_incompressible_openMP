clear; close all; clc;

%% ============================================================
%  Comparison x24O / x24m at step 901
%  Pressure proxy:
%
%       p* = rho2 * (kBT_g / m_g)
%
%  x24O : kBT/m = 0.8
%  x24m : kBT/m = 3.2
%
%  Grid: 400 x 256
%% ============================================================

NX = 400;
NY = 256;

Lx = 1.5625;
Ly = 1.0;

dx = Lx / NX;
dy = Ly / NY;

x = ((0:NX-1) + 0.5) * dx;
y = ((0:NY-1) + 0.5) * dy;

% Jet axis
xAxis = 0.78125;
[~, ixAxis] = min(abs(x - xAxis));

%% ============================================================
% Files
%% ============================================================

fileK = '../runs/0493x24k_sato_short_nozzle_forced_long_seed493205/' + ...
        "restart_short_nozzle_forced_long/output/recordings/" + ...
        "record_step_0000000001/step_0000000901_field_rho2.f32";
fileO = "E:\SRC_MPCD_dev\SRC_GPU-SURF\runs\0493x24o_sato_machquarter_forced_seed493205\restart_machquarter_forced\output\recordings\record_step_0000000001\step_0000000901_field_rho2.f32";
fileM = '../runs/0493x24m_sato_machhalf_forced_seed493205/' + ...
        "restart_machhalf_forced/output/recordings/" + ...
        "record_step_0000000001/step_0000000901_field_rho2.f32";

%% ============================================================
% Read float32 fields
%% ============================================================

rho2K = read_f32_field(fileO, NX, NY);
rho2M = read_f32_field(fileM, NX, NY);

%% ============================================================
% Pressure proxy
%% ============================================================

kBT_over_m_K = 0.8;
kBT_over_m_M = 3.2;

pK = rho2K * kBT_over_m_K;
pM = rho2M * kBT_over_m_M;

%% ============================================================
% Global diagnostics
%% ============================================================

fprintf('\n===== x24O / x24m pressure proxy comparison =====\n');

fprintf('x24O: rho2 max = %.9g\n', max(rho2K(:)));
fprintf('x24m: rho2 max = %.9g\n', max(rho2M(:)));

fprintf('x24O: p* max   = %.9g\n', max(pK(:)));
fprintf('x24m: p* max   = %.9g\n', max(pM(:)));

fprintf('ratio rho2max O/M = %.9g\n', ...
    max(rho2K(:)) / max(rho2M(:)));

fprintf('ratio p*max M/O   = %.9g\n', ...
    max(pM(:)) / max(pK(:)));

%% ============================================================
% Common colour scale
%% ============================================================

pMax = max([pK(:); pM(:)]);

%% ============================================================
% Map x24k
%% ============================================================

figure;
imagesc(x, y, pK');
axis xy equal tight;
colorbar;
clim([0 pMax]);

xlabel('x');
ylabel('y');

title(sprintf( ...
    'x24O pressure proxy p^* = \\rho_2 k_BT/m | step 901 | k_BT/m = %.1f', ...
    kBT_over_m_K));

hold on;
xline(xAxis, '--w');
hold off;

%% ============================================================
% Map x24m
%% ============================================================

figure;
imagesc(x, y, pM');
axis xy equal tight;
colorbar;
clim([0 pMax]);

xlabel('x');
ylabel('y');

title(sprintf( ...
    'x24m pressure proxy p^* = \\rho_2 k_BT/m | step 901 | k_BT/m = %.1f', ...
    kBT_over_m_M));

hold on;
xline(xAxis, '--w');
hold off;

%% ============================================================
% Absolute difference
%% ============================================================

dp = pM - pK;

figure;
imagesc(x, y, dp');
axis xy equal tight;
colorbar;

xlabel('x');
ylabel('y');

title('Pressure proxy difference: p^*_{x24m} - p^*_{x24O}');

hold on;
xline(xAxis, '--O');
hold off;

%% ============================================================
% Relative difference
%
% Avoid meaningless ratios where both fields are almost zero.
%% ============================================================

pRef = max(pK, pM);

mask = pRef > 0.02 * pMax;

rel = nan(size(pK));
rel(mask) = (pM(mask) - pK(mask)) ./ pRef(mask);

figure;
imagesc(x, y, 100 * rel');
axis xy equal tight;
colorbar;
clim([-100 100]);

xlabel('x');
ylabel('y');

title('Relative pressure-proxy difference [%]');

hold on;
xline(xAxis, '--O');
hold off;

%% ============================================================
% Axial profiles
%% ============================================================

pAxisK = pK(ixAxis, :);
pAxisM = pM(ixAxis, :);

rhoAxisK = rho2K(ixAxis, :);
rhoAxisM = rho2M(ixAxis, :);

figure;

plot(y, pAxisK, 'LineWidth', 1.5);
hold on;
plot(y, pAxisM, 'LineWidth', 1.5);

grid on;

xlabel('y');
ylabel('p^* = \rho_2 k_BT/m');

legend('x24O : k_BT/m = 0.8', ...
       'x24m : k_BT/m = 3.2', ...
       'Location', 'best');

title(sprintf( ...
    'Axial pressure proxy | x = %.5f | step 901', ...
    x(ixAxis)));

%% ============================================================
% Axial rho2 profiles for comparison
%% ============================================================

figure;

plot(y, rhoAxisK, 'LineWidth', 1.5);
hold on;
plot(y, rhoAxisM, 'LineWidth', 1.5);

grid on;

xlabel('y');
ylabel('\rho_2');

legend('x24O', 'x24m', 'Location', 'best');

title(sprintf( ...
    'Axial gas-density field | x = %.5f | step 901', ...
    x(ixAxis)));

%% ============================================================
% Local diagnostics near maximum-pressure region
%% ============================================================

[pKmax, idxK] = max(pK(:));
[iK, jK] = ind2sub(size(pK), idxK);

[pMmax, idxM] = max(pM(:));
[iM, jM] = ind2sub(size(pM), idxM);

fprintf('\nMaximum p* locations:\n');

fprintf('x24O: p*=%.9g at x=%.9g y=%.9g\n', ...
    pKmax, x(iK), y(jK));

fprintf('x24m: p*=%.9g at x=%.9g y=%.9g\n', ...
    pMmax, x(iM), y(jM));
% --- Reference pressure proxy from quiet upper lateral gas ----------------

maskRef = ...
    (repmat(y, NX, 1) > 0.90) & ...
    ~(repmat(x(:), 1, NY) > 0.70 & repmat(x(:), 1, NY) < 0.86);

pRefK = mean(pK(maskRef));
pRefM = mean(pM(maskRef));

dpGaugeK = pK - pRefK;
dpGaugeM = pM - pRefM;

fprintf('\nGauge reference:\n');
fprintf('x24O pRef* = %.9g\n', pRefK);
fprintf('x24m pRef* = %.9g\n', pRefM);

fprintf('x24O max Delta p* = %.9g\n', max(dpGaugeK(:)));
fprintf('x24m max Delta p* = %.9g\n', max(dpGaugeM(:)));
fprintf('ratio max Delta p* M/O = %.9g\n', ...
    max(dpGaugeM(:))/max(dpGaugeK(:)));

% --- Common-scale gauge pressure maps ------------------------------------

dpMax = max([dpGaugeK(:); dpGaugeM(:)]);

figure;
imagesc(x, y, dpGaugeK');
axis xy equal tight;
colorbar;
clim([0 dpMax]);
xlabel('x'); ylabel('y');
title('\Delta p^* x24O | step 901');

figure;
imagesc(x, y, dpGaugeM');
axis xy equal tight;
colorbar;
clim([0 dpMax]);
xlabel('x'); ylabel('y');
title('\Delta p^* x24m | step 901');

% --- Axial gauge-pressure comparison -------------------------------------

figure;
plot(y, dpGaugeK(ixAxis,:), 'LineWidth', 1.5);
hold on;
plot(y, dpGaugeM(ixAxis,:), 'LineWidth', 1.5);
grid on;

xlabel('y');
ylabel('\Delta p^*');

legend('x24O','x24m','Location','best');
title(sprintf('Axial gauge-pressure proxy | x = %.5f | step 901',x(ixAxis)));

%% ============================================================
% Helper
%% ============================================================

function F = read_f32_field(filename, NX, NY)

    fid = fopen(filename, 'rb');

    if fid < 0
        error('Cannot open file: %s', filename);
    end

    data = fread(fid, NX * NY, 'single=>double');

    fclose(fid);

    if numel(data) ~= NX * NY
        error( ...
            'Unexpected field size in %s: got %d values, expected %d', ...
            filename, numel(data), NX * NY);
    end

    % LiveVis field storage: x-fastest
    F = reshape(data, [NX, NY]);

end
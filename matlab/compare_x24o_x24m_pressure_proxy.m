clear; close all; clc;

%% ============================================================
%  Comparison x24O / x24m at matched physical time
%
%  Pressure proxy:
%
%       p* = rho2 * (kBT_g / m_g)
%
%  x24m:
%       dt      = 4e-4
%       step    = 901
%       t       = 0.3604
%       kBT/m   = 3.2
%
%  x24O:
%       dt      = 2e-4
%       step    = 1801
%       t       = 0.3602
%       kBT/m   = 12.8
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
% Run parameters
%% ============================================================

dtO = 2.0e-4;
stepO = 1801;
timeO = stepO * dtO;
kBT_over_m_O = 12.8;

dtM = 4.0e-4;
stepM = 901;
timeM = stepM * dtM;
kBT_over_m_M = 3.2;

fprintf('\n===== matched-time comparison =====\n');
fprintf('x24O: step=%d dt=%.7g t=%.7g kBT/m=%.7g\n', ...
    stepO, dtO, timeO, kBT_over_m_O);
fprintf('x24m: step=%d dt=%.7g t=%.7g kBT/m=%.7g\n', ...
    stepM, dtM, timeM, kBT_over_m_M);
fprintf('Delta t physical = %.7g\n', abs(timeO-timeM));

%% ============================================================
% Files
%% ============================================================

fileO = '../runs/0493x24o_sato_machquarter_forced_seed493205/' + ...
        "restart_machquarter_forced/output/recordings/" + ...
        "record_step_0000000001/step_0000001801_field_rho2.f32";

fileM = '../runs/0493x24m_sato_machhalf_forced_seed493205/' + ...
        "restart_machhalf_forced/output/recordings/" + ...
        "record_step_0000000001/step_0000000901_field_rho2.f32";

%% ============================================================
% Read rho2 fields
%% ============================================================

rho2O = read_f32_field(fileO, NX, NY);
rho2M = read_f32_field(fileM, NX, NY);

%% ============================================================
% Pressure proxies
%% ============================================================

pO = rho2O * kBT_over_m_O;
pM = rho2M * kBT_over_m_M;

%% ============================================================
% Global diagnostics
%% ============================================================

fprintf('\n===== x24O / x24m pressure proxy comparison =====\n');

rhoMaxO = max(rho2O(:));
rhoMaxM = max(rho2M(:));

pMaxO = max(pO(:));
pMaxM = max(pM(:));

fprintf('x24O: rho2 max = %.9g\n', rhoMaxO);
fprintf('x24m: rho2 max = %.9g\n', rhoMaxM);

fprintf('x24O: p* max   = %.9g\n', pMaxO);
fprintf('x24m: p* max   = %.9g\n', pMaxM);

fprintf('ratio rho2max O/M = %.9g\n', rhoMaxO / rhoMaxM);
fprintf('ratio p*max O/M   = %.9g\n', pMaxO / pMaxM);

%% ============================================================
% Common colour scale for absolute pressure proxy
%% ============================================================

pMaxCommon = max([pO(:); pM(:)]);

%% ============================================================
% Map x24O
%% ============================================================

figure;
imagesc(x, y, pO');
axis xy equal tight;
colorbar;
clim([0 pMaxCommon]);

xlabel('x');
ylabel('y');

title(sprintf( ...
    'x24O pressure proxy p^* = \\rho_2 k_BT/m | step %d | t = %.4f | k_BT/m = %.1f', ...
    stepO, timeO, kBT_over_m_O));

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
clim([0 pMaxCommon]);

xlabel('x');
ylabel('y');

title(sprintf( ...
    'x24m pressure proxy p^* = \\rho_2 k_BT/m | step %d | t = %.4f | k_BT/m = %.1f', ...
    stepM, timeM, kBT_over_m_M));

hold on;
xline(xAxis, '--w');
hold off;

%% ============================================================
% Absolute difference
%% ============================================================

dp = pO - pM;

figure;
imagesc(x, y, dp');
axis xy equal tight;
colorbar;

xlabel('x');
ylabel('y');

title(sprintf( ...
    'Pressure proxy difference p^*_{x24O} - p^*_{x24m} | t \\approx %.4f', ...
    0.5*(timeO+timeM)));

hold on;
xline(xAxis, '--k');
hold off;

%% ============================================================
% Relative difference
%
% Avoid meaningless ratios where both fields are almost zero.
%% ============================================================

pRefLocal = max(pO, pM);

mask = pRefLocal > 0.02 * pMaxCommon;

rel = nan(size(pO));
rel(mask) = (pO(mask) - pM(mask)) ./ pRefLocal(mask);

figure;
imagesc(x, y, 100 * rel');
axis xy equal tight;
colorbar;
clim([-100 100]);

xlabel('x');
ylabel('y');

title('Relative pressure-proxy difference [%]');

hold on;
xline(xAxis, '--k');
hold off;

%% ============================================================
% Axial pressure-proxy profiles
%% ============================================================

pAxisO = pO(ixAxis, :);
pAxisM = pM(ixAxis, :);

figure;

plot(y, pAxisO, 'LineWidth', 1.5);
hold on;
plot(y, pAxisM, 'LineWidth', 1.5);

grid on;

xlabel('y');
ylabel('p^* = \rho_2 k_BT/m');

legend( ...
    sprintf('x24O : t=%.4f, k_BT/m=%.1f', timeO, kBT_over_m_O), ...
    sprintf('x24m : t=%.4f, k_BT/m=%.1f', timeM, kBT_over_m_M), ...
    'Location', 'best');

title(sprintf( ...
    'Axial pressure proxy | x = %.5f | matched physical time', ...
    x(ixAxis)));

%% ============================================================
% Axial rho2 profiles
%% ============================================================

rhoAxisO = rho2O(ixAxis, :);
rhoAxisM = rho2M(ixAxis, :);

figure;

plot(y, rhoAxisO, 'LineWidth', 1.5);
hold on;
plot(y, rhoAxisM, 'LineWidth', 1.5);

grid on;

xlabel('y');
ylabel('\rho_2');

legend( ...
    sprintf('x24O : t=%.4f', timeO), ...
    sprintf('x24m : t=%.4f', timeM), ...
    'Location', 'best');

title(sprintf( ...
    'Axial gas-density field | x = %.5f | matched physical time', ...
    x(ixAxis)));

%% ============================================================
% Maximum locations
%% ============================================================

[pOmax, idxO] = max(pO(:));
[iO, jO] = ind2sub(size(pO), idxO);

[pMmax, idxM] = max(pM(:));
[iM, jM] = ind2sub(size(pM), idxM);

fprintf('\nMaximum p* locations:\n');

fprintf('x24O: p*=%.9g at x=%.9g y=%.9g\n', ...
    pOmax, x(iO), y(jO));

fprintf('x24m: p*=%.9g at x=%.9g y=%.9g\n', ...
    pMmax, x(iM), y(jM));

%% ============================================================
% Gauge-pressure proxy
%
% Reference region:
%   upper lateral gas, away from the nozzle.
%% ============================================================

X = repmat(x(:), 1, NY);
Y = repmat(y, NX, 1);

maskRef = ...
    (Y > 0.90) & ...
    ~(X > 0.70 & X < 0.86);

pRefO = mean(pO(maskRef));
pRefM = mean(pM(maskRef));

dpGaugeO = pO - pRefO;
dpGaugeM = pM - pRefM;

fprintf('\nGauge reference:\n');
fprintf('x24O pRef* = %.9g\n', pRefO);
fprintf('x24m pRef* = %.9g\n', pRefM);

fprintf('x24O max Delta p* = %.9g\n', max(dpGaugeO(:)));
fprintf('x24m max Delta p* = %.9g\n', max(dpGaugeM(:)));

fprintf('ratio max Delta p* O/M = %.9g\n', ...
    max(dpGaugeO(:)) / max(dpGaugeM(:)));

%% ============================================================
% Common-scale gauge pressure maps
%% ============================================================

dpMaxCommon = max([dpGaugeO(:); dpGaugeM(:)]);

figure;
imagesc(x, y, dpGaugeO');
axis xy equal tight;
colorbar;
clim([0 dpMaxCommon]);

xlabel('x');
ylabel('y');

title(sprintf( ...
    '\\Delta p^* x24O | step %d | t = %.4f', ...
    stepO, timeO));

hold on;
xline(xAxis, '--w');
hold off;

figure;
imagesc(x, y, dpGaugeM');
axis xy equal tight;
colorbar;
clim([0 dpMaxCommon]);

xlabel('x');
ylabel('y');

title(sprintf( ...
    '\\Delta p^* x24m | step %d | t = %.4f', ...
    stepM, timeM));

hold on;
xline(xAxis, '--w');
hold off;

%% ============================================================
% Axial gauge-pressure comparison
%% ============================================================

figure;

plot(y, dpGaugeO(ixAxis,:), 'LineWidth', 1.5);
hold on;
plot(y, dpGaugeM(ixAxis,:), 'LineWidth', 1.5);

grid on;

xlabel('y');
ylabel('\Delta p^*');

legend( ...
    sprintf('x24O : t=%.4f', timeO), ...
    sprintf('x24m : t=%.4f', timeM), ...
    'Location', 'best');

title(sprintf( ...
    'Axial gauge-pressure proxy | x = %.5f | matched physical time', ...
    x(ixAxis)));

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
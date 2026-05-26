function out = validate_density_wave_virial_channel(varargin)
%VALIDATE_DENSITY_WAVE_VIRIAL_CHANNEL Analyze a channel density-wave virial test.
%
% Intended to be launched from matlab/.
%
% The test starts from a low-k density modulation in x with fixed top/bottom
% solid_thermal walls. It measures whether the virial pressure kick accelerates
% relaxation of the density mode and produces a visible velocity response.

p = inputParser;
p.FunctionName = 'validate_density_wave_virial_channel';
addParameter(p, 'runDirs', { ...
    '../runs/density_wave_channel_q9_filtered', ...
    '../runs/density_wave_channel_q9_virial_K0p500_beta0p20', ...
    '../runs/density_wave_channel_q9_virial_K1p000_beta0p50'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'labels', { ...
    'q9_filtered', ...
    'K0p500_b0p20', ...
    'K1p000_b0p50'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 32, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ny', 32, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'modeX', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'tailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

runDirs = cellstr(string(opts.runDirs));
labels = cellstr(string(opts.labels));
if numel(runDirs) ~= numel(labels)
    error('validate_density_wave_virial_channel:labelMismatch', ...
        'runDirs and labels must have the same length.');
end

S = cell(numel(runDirs), 1);
M = cell(numel(runDirs), 1);
rows = cell(numel(runDirs), 1);
for k = 1:numel(runDirs)
    f = fullfile(runDirs{k}, 'summary_runtime.csv');
    if ~isfile(f)
        error('validate_density_wave_virial_channel:missingSummary', ...
            'Cannot find summary file: %s', f);
    end
    S{k} = readtable(f);
    M{k} = local_density_mode_timeseries(runDirs{k}, opts);
    rows{k} = local_summary_metrics(S{k}, M{k}, labels{k}, runDirs{k}, opts.tailFraction);
end

metrics = vertcat(rows{:});
fprintf('\n=== Density-wave channel Q9/virial validation ===\n');
disp(metrics);

if opts.makePlots
    local_plot(S, M, labels);
end

out = struct();
out.runDirs = runDirs;
out.labels = labels;
out.summaries = S;
out.modeSeries = M;
out.metrics = metrics;
end

function row = local_summary_metrics(T, M, label, runDir, tailFraction)
n = height(T);
i0 = max(1, floor((1 - tailFraction) * n) + 1);
tail = i0:n;

modeStart = first_finite_positive_abs_or_nan(M.densityCosMode);
modeEnd = last_finite_or_nan_table(M, 'densityCosMode');
modeAbsRatio = abs(modeEnd) / abs(modeStart);
modeTailMeanAbsRatio = mean(abs(M.densityCosMode(max(1, floor((1-tailFraction)*height(M))+1):end)), 'omitnan') / abs(modeStart);

uxSinStart = first_finite_or_nan_table(M, 'uxSinMode');
uxSinEnd = last_finite_or_nan_table(M, 'uxSinMode');
[uxSinPeakAbs, timeUxSinPeakAbs] = local_peak_abs(M, 'uxSinMode');
integralAbsUxSinMode = local_integral_abs(M, 'uxSinMode');
filteredStdStart = first_finite_positive_or_nan_table(M, 'densityFilteredStd');
filteredStdEnd = last_finite_or_nan_table(M, 'densityFilteredStd');

[virialKickRmsPeak, timeVirialKickRmsPeak] = local_peak_value(T, 'virialDuAppliedRms');
virialKickMaxPeak = local_peak_value_scalar(T, 'virialDuAppliedMaxAbs');
virialOverThermalPeak = local_peak_value_scalar(T, 'virialDuOverThermalRms');

row = table(string(label), string(runDir), n, first_finite_or_nan(T, 'time'), last_finite_or_nan(T, 'time'), ...
    modeStart, modeEnd, modeAbsRatio, modeTailMeanAbsRatio, ...
    uxSinStart, uxSinEnd, uxSinPeakAbs, timeUxSinPeakAbs, integralAbsUxSinMode, ...
    filteredStdStart, filteredStdEnd, safe_ratio(filteredStdEnd, filteredStdStart), ...
    last_finite_or_nan(T, 'kBTEstimate'), mean_omitnan(T, 'kBTEstimate', tail), ...
    last_finite_or_nan(T, 'q6DivAfterProjectedFluxRms'), last_finite_or_nan(T, 'q6ResidualRel'), ...
    last_finite_or_nan(T, 'q9ResidualRel'), last_finite_or_nan(T, 'q9TargetDivergenceFilterRatio'), ...
    last_finite_or_nan(T, 'q9CorrectionVelocityRms'), last_finite_or_nan(T, 'q9CorrectionVelocityMaxAbs'), ...
    last_finite_or_nan(T, 'virialEnabled'), last_finite_or_nan(T, 'virialKickApplied'), ...
    last_finite_or_nan(T, 'PvirMean'), last_finite_or_nan(T, 'PtotMean'), last_finite_or_nan(T, 'gradPdriveRms'), ...
    last_finite_or_nan(T, 'virialDuAppliedRms'), mean_omitnan(T, 'virialDuAppliedRms', tail), ...
    last_finite_or_nan(T, 'virialDuAppliedMaxAbs'), last_finite_or_nan(T, 'virialDuOverThermalRms'), ...
    virialKickRmsPeak, timeVirialKickRmsPeak, virialKickMaxPeak, virialOverThermalPeak, ...
    last_finite_or_nan(T, 'maxParticleAbsVx'), last_finite_or_nan(T, 'maxParticleAbsVy'), ...
    last_finite_or_nan(T, 'maxYWallReflectionsPerParticle'), ...
    'VariableNames', {'run','runDir','nRows','timeStart','timeEnd', ...
    'densityCosModeStart','densityCosModeEnd','densityCosModeAbsRatio','densityCosModeTailMeanAbsRatio', ...
    'uxSinModeStart','uxSinModeEnd','uxSinModePeakAbs','timeUxSinModePeakAbs','integralAbsUxSinMode', ...
    'filteredStdStart','filteredStdEnd','filteredStdRatio', ...
    'kBTEnd','kBTTailMean','q6DivAfterEnd','q6ResidualEnd','q9ResidualEnd','q9TargetFilterRatioEnd', ...
    'q9CorrectionVelocityRmsEnd','q9CorrectionVelocityMaxEnd', ...
    'virialEnabled','virialKickApplied','PvirMeanEnd','PtotMeanEnd','gradPdriveRmsEnd', ...
    'virialDuAppliedRmsEnd','virialDuAppliedRmsTailMean','virialDuAppliedMaxEnd','virialDuOverThermalRmsEnd', ...
    'virialDuAppliedRmsPeak','timeVirialDuAppliedRmsPeak','virialDuAppliedMaxPeak','virialDuOverThermalRmsPeak', ...
    'maxParticleAbsVxEnd','maxParticleAbsVyEnd','yWallReflectionMaxPerParticleEnd'});
end

function M = local_density_mode_timeseries(runDir, opts)
frames = list_smpcd_dumps(runDir);
if isempty(frames)
    error('validate_density_wave_virial_channel:noDumps', 'No dumps found in %s.', runDir);
end

n = height(frames);
time = frames.time;
step = frames.step;
densityCosMode = nan(n,1);
uxSinMode = nan(n,1);
densityFilteredStd = nan(n,1);
rawStdN = nan(n,1);

for k = 1:n
    state = read_smpcd_state(frames.fullPath{k});
    F = bin_smpcd_state(state, 'Lx', opts.Lx, 'Ly', opts.Ly, ...
        'Nx', opts.Nx, 'Ny', opts.Ny, 'periodicX', true, 'periodicY', false);
    N = F.N;
    rawStdN(k) = std(N(:));
    [densityCosMode(k), densityFilteredStd(k)] = local_density_lowk_metrics(N, opts.modeX);
    uxSinMode(k) = local_velocity_sine_mode(F.Ux, opts.modeX);
end

M = table(step, time, densityCosMode, abs(densityCosMode)./abs(densityCosMode(1)), ...
    uxSinMode, rawStdN, densityFilteredStd, ...
    'VariableNames', {'step','time','densityCosMode','densityCosModeAbsRatio','uxSinMode','rawStdN','densityFilteredStd'});
end

function [amp, filteredStd] = local_density_lowk_metrics(N, modeX)
[Ny, Nx] = size(N);
x = ((0:Nx-1) + 0.5) / Nx;
cosBasis = cos(2*pi*modeX*x);
sinBasis = sin(2*pi*modeX*x);
Cos = repmat(cosBasis, Ny, 1);
Sin = repmat(sinBasis, Ny, 1);
dN = N - mean(N(:));
a = sum(dN(:).*Cos(:)) / sum(Cos(:).^2);
b = sum(dN(:).*Sin(:)) / sum(Sin(:).^2);
low = a*Cos + b*Sin;
amp = a;
filteredStd = std(low(:));
end

function amp = local_velocity_sine_mode(Ux, modeX)
[Ny, Nx] = size(Ux);
x = ((0:Nx-1) + 0.5) / Nx;
Sin = repmat(sin(2*pi*modeX*x), Ny, 1);
valid = isfinite(Ux);
if ~any(valid(:))
    amp = NaN;
    return;
end
amp = sum(Ux(valid).*Sin(valid)) / sum(Sin(valid).^2);
end

function local_plot(S, M, labels)
figure('Name', 'Density-wave Q9/virial channel validation');
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; hold on;
for k = 1:numel(M)
    plot(M{k}.time, M{k}.densityCosModeAbsRatio, 'DisplayName', labels{k});
end
hold off; grid on; xlabel('time'); ylabel('|A_\rho|/|A_{\rho,0}|'); title('Density mode decay'); legend('Interpreter','none');

nexttile; hold on;
for k = 1:numel(M)
    plot(M{k}.time, M{k}.uxSinMode, 'DisplayName', labels{k});
end
hold off; grid on; xlabel('time'); ylabel('U_x sine mode'); title('Velocity response');

nexttile; hold on;
for k = 1:numel(M)
    plot(M{k}.time, M{k}.densityFilteredStd, 'DisplayName', labels{k});
end
hold off; grid on; xlabel('time'); ylabel('low-k std(N)'); title('Low-k density std');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('virialDuAppliedRms', S{k}.Properties.VariableNames)
        semilogy(S{k}.time, max(S{k}.virialDuAppliedRms, eps), 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('virial du RMS'); title('Virial kick RMS');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('kBTEstimate', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.kBTEstimate, 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('kBT'); title('Temperature');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('maxParticleAbsVx', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.maxParticleAbsVx, 'DisplayName', labels{k});
    end
    if ismember('maxParticleAbsVy', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.maxParticleAbsVy, '--', 'DisplayName', [labels{k} ' |vy|']);
    end
end
hold off; grid on; xlabel('time'); ylabel('max particle speed component'); title('Particle velocity safety');
end

function v = first_finite_or_nan(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'first');
    if ~isempty(idx), v = x(idx); end
end
end

function v = last_finite_or_nan(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'last');
    if ~isempty(idx), v = x(idx); end
end
end

function v = mean_omitnan(T, name, idx)
if ismember(name, T.Properties.VariableNames)
    v = mean(T.(name)(idx), 'omitnan');
else
    v = NaN;
end
end

function r = safe_ratio(a, b)
if isfinite(a) && isfinite(b) && abs(b) > 0
    r = a / b;
else
    r = NaN;
end
end

function v = first_finite_or_nan_table(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'first');
    if ~isempty(idx), v = x(idx); end
end
end

function v = last_finite_or_nan_table(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'last');
    if ~isempty(idx), v = x(idx); end
end
end

function v = first_finite_positive_or_nan_table(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x) & x > 0, 1, 'first');
    if ~isempty(idx), v = x(idx); end
end
end

function v = first_finite_positive_abs_or_nan(x)
idx = find(isfinite(x) & abs(x) > 0, 1, 'first');
if isempty(idx)
    v = NaN;
else
    v = x(idx);
end
end

function [peakAbs, timePeak] = local_peak_abs(T, name)
peakAbs = NaN;
timePeak = NaN;
if ~ismember(name, T.Properties.VariableNames) || ~ismember('time', T.Properties.VariableNames)
    return;
end
x = T.(name);
mask = isfinite(x) & isfinite(T.time);
if ~any(mask)
    return;
end
vals = abs(x(mask));
times = T.time(mask);
[peakAbs, idx] = max(vals);
timePeak = times(idx);
end

function integralAbs = local_integral_abs(T, name)
integralAbs = NaN;
if ~ismember(name, T.Properties.VariableNames) || ~ismember('time', T.Properties.VariableNames)
    return;
end
x = T.(name);
t = T.time;
mask = isfinite(x) & isfinite(t);
if nnz(mask) < 2
    return;
end
integralAbs = trapz(t(mask), abs(x(mask)));
end

function [peakValue, timePeak] = local_peak_value(T, name)
peakValue = NaN;
timePeak = NaN;
if ~ismember(name, T.Properties.VariableNames) || ~ismember('time', T.Properties.VariableNames)
    return;
end
x = T.(name);
t = T.time;
mask = isfinite(x) & isfinite(t);
if ~any(mask)
    return;
end
[peakValue, idx] = max(x(mask));
times = t(mask);
timePeak = times(idx);
end

function peakValue = local_peak_value_scalar(T, name)
peakValue = NaN;
if ~ismember(name, T.Properties.VariableNames)
    return;
end
x = T.(name);
mask = isfinite(x);
if ~any(mask)
    return;
end
peakValue = max(x(mask));
end

function out = validate_liquid_closure_dynamic_suite(varargin)
%VALIDATE_LIQUID_CLOSURE_DYNAMIC_SUITE Compare Q6/Q9/virial on TG and Poiseuille.
%
%   out = validate_liquid_closure_dynamic_suite('makePlots', true)
%
%   Defaults assume this function is called from matlab/ and therefore use
%   ../runs/... paths. The corresponding C++ runs can be launched from the
%   repository root with:
%
%     ./scripts/run_liquid_closure_dynamic_validation.sh
%
%   The suite is intentionally a validation/post-processing wrapper. It does
%   not modify solver parameters and does not try to make the periodic
%   immersed-circle case a canonical von-Karman benchmark.

p = inputParser;
p.FunctionName = 'validate_liquid_closure_dynamic_suite';
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'tgRunDirs', { ...
    '../runs/taylor_green_high_snr_classic_64x64_g80_short', ...
    '../runs/taylor_green_high_snr_q6_64x64_g80_short', ...
    '../runs/taylor_green_high_snr_q9_filtered_64x64_g80_short', ...
    '../runs/taylor_green_high_snr_q9_virial_K0p500_beta0p20_64x64_g80_short'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'tgLabels', {'classic','q6','q9_filtered','q9_virial'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'poiseuilleRunDirs', { ...
    '../runs/poiseuille_y_classic_solid_thermal_long', ...
    '../runs/poiseuille_y_q6_solid_thermal_long', ...
    '../runs/poiseuille_y_q9_filtered_solid_thermal_long', ...
    '../runs/poiseuille_y_q9_virial_K0p500_beta0p20_solid_thermal_long'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'poiseuilleLabels', {'classic','q6','q9_filtered','q9_virial'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'fitStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'excludeWallCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parse(p, varargin{:});
opts = p.Results;

tgRunDirs = cellstr(string(opts.tgRunDirs));
tgLabels = cellstr(string(opts.tgLabels));
poiseuilleRunDirs = cellstr(string(opts.poiseuilleRunDirs));
poiseuilleLabels = cellstr(string(opts.poiseuilleLabels));

if numel(tgRunDirs) ~= numel(tgLabels)
    error('validate_liquid_closure_dynamic_suite:tgMismatch', 'tgRunDirs and tgLabels must match.');
end
if numel(poiseuilleRunDirs) ~= numel(poiseuilleLabels)
    error('validate_liquid_closure_dynamic_suite:poiseuilleMismatch', 'poiseuilleRunDirs and poiseuilleLabels must match.');
end

tg = local_analyze_tg_group(tgRunDirs, tgLabels);
pois = local_analyze_poiseuille_group(poiseuilleRunDirs, poiseuilleLabels, opts.fitStartFraction, opts.excludeWallCells);

fprintf('\n=== Liquid-closure dynamic validation: Taylor-Green ===\n');
disp(tg.summary);
fprintf('\n=== Liquid-closure dynamic validation: Poiseuille ===\n');
disp(pois.summary);

if opts.makePlots
    local_plot_suite(tg, pois);
end

out = struct();
out.taylorGreen = tg;
out.poiseuille = pois;
out.summary = struct('taylorGreen', tg.summary, 'poiseuille', pois.summary);
end

function group = local_analyze_tg_group(runDirs, labels)
runs = cell(numel(runDirs), 1);
rows = cell(numel(runDirs), 1);
for k = 1:numel(runDirs)
    runs{k} = local_analyze_tg_run(runDirs{k}, labels{k});
    rows{k} = local_tg_summary_row(runs{k});
end
group = struct('runs', {runs}, 'summary', vertcat(rows{:}));
end

function run = local_analyze_tg_run(runDir, label)
frames = list_smpcd_dumps(runDir);
if isempty(frames) || height(frames) == 0
    error('validate_liquid_closure_dynamic_suite:noTGDumps', 'No dumps found in %s.', runDir);
end
params = parse_smpcd_kv(fullfile(runDir, 'params_used.kv'));
runtime = local_read_summary(runDir);
Lx = local_param(params, 'Lx', 1.0);
Ly = local_param(params, 'Ly', 1.0);
Nx = local_param(params, 'Nx', 64);
Ny = local_param(params, 'Ny', 64);

n = height(frames);
step = frames.step;
time = frames.time;
amplitude = nan(n,1);
correlation = nan(n,1);
divRms = nan(n,1);
omegaRms = nan(n,1);
for i = 1:n
    state = read_smpcd_state(char(frames.fullPath(i)));
    F = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
        'periodicX', true, 'periodicY', true);
    m = local_tg_metrics(F);
    amplitude(i) = m.amplitude;
    correlation(i) = m.correlation;
    divRms(i) = m.divRms;
    omegaRms(i) = m.omegaRms;
end
metrics = table(step, time, amplitude, correlation, divRms, omegaRms);
run = struct('label', string(label), 'runDir', string(runDir), 'metrics', metrics, 'runtime', runtime);
end

function row = local_tg_summary_row(run)
M = run.metrics;
T = run.runtime;
amp0 = first_finite_positive_abs(M.amplitude);
ampEnd = last_finite(M.amplitude);
row = table(run.label, run.runDir, height(M), M.time(1), M.time(end), ...
    amp0, ampEnd, safe_ratio(ampEnd, amp0), last_finite(M.correlation), ...
    last_finite(M.divRms), last_finite(M.omegaRms), ...
    last_finite_col(T, 'stdN'), last_finite_col(T, 'kBTEstimate'), ...
    last_finite_col(T, 'q6DivAfterProjectedFluxRms'), last_finite_col(T, 'q6ResidualRel'), ...
    last_finite_col(T, 'q9ResidualRel'), last_finite_col(T, 'q9TargetDivergenceFilterRatio'), ...
    last_finite_col(T, 'q9CorrectionVelocityRms'), last_finite_col(T, 'q9CorrectionVelocityMaxAbs'), ...
    last_finite_col(T, 'virialEnabled'), last_finite_col(T, 'virialKickApplied'), ...
    last_finite_col(T, 'PtotMean'), last_finite_col(T, 'virialDuAppliedRms'), ...
    last_finite_col(T, 'virialDuAppliedMaxAbs'), last_finite_col(T, 'virialDuOverThermalRms'), ...
    'VariableNames', {'run','runDir','nFrames','timeStart','timeEnd', ...
    'amplitudeStart','amplitudeEnd','amplitudeRatio','correlationEnd', ...
    'divRmsEnd','omegaRmsEnd','stdNEnd','kBTEnd', ...
    'q6RuntimeDivAfterEnd','q6RuntimeResidualEnd','q9RuntimeResidualEnd','q9TargetFilterRatioEnd', ...
    'q9CorrectionVelocityRmsEnd','q9CorrectionVelocityMaxEnd', ...
    'virialEnabled','virialKickApplied','PtotMeanEnd','virialDuAppliedRmsEnd', ...
    'virialDuAppliedMaxEnd','virialDuOverThermalRmsEnd'});
end

function group = local_analyze_poiseuille_group(runDirs, labels, fitStartFraction, excludeWallCells)
runs = cell(numel(runDirs), 1);
rows = cell(numel(runDirs), 1);
for k = 1:numel(runDirs)
    prof = analyze_poiseuille_profile(runDirs{k}, ...
        'flowComponent', 'Ux', ...
        'profileDirection', 'y', ...
        'fitStartFraction', fitStartFraction, ...
        'excludeWallCells', excludeWallCells, ...
        'makePlots', false, ...
        'plotConvergence', false);
    runtime = local_read_summary(runDirs{k});
    runs{k} = struct('label', string(labels{k}), 'runDir', string(runDirs{k}), 'profile', prof, 'runtime', runtime);
    rows{k} = local_poiseuille_summary_row(runs{k});
end
group = struct('runs', {runs}, 'summary', vertcat(rows{:}));
end

function row = local_poiseuille_summary_row(run)
P = run.profile;
T = run.runtime;
row = table(run.label, run.runDir, height(P.frameTable), first_finite_col(T, 'time'), last_finite_col(T, 'time'), ...
    P.uCenter, P.uMax, P.fit.r2, P.fit.nuEff, last_finite_col(T, 'kBTEstimate'), ...
    last_finite_col(T, 'stdN'), last_finite_col(T, 'q6DivAfterProjectedFluxRms'), ...
    last_finite_col(T, 'q6ResidualRel'), last_finite_col(T, 'q9ResidualRel'), ...
    last_finite_col(T, 'q9TargetDivergenceFilterRatio'), last_finite_col(T, 'q9CorrectionVelocityRms'), ...
    last_finite_col(T, 'q9CorrectionVelocityMaxAbs'), last_finite_col(T, 'virialEnabled'), ...
    last_finite_col(T, 'virialKickApplied'), last_finite_col(T, 'PtotMean'), ...
    last_finite_col(T, 'gradPdriveRms'), last_finite_col(T, 'virialDuAppliedRms'), ...
    last_finite_col(T, 'virialDuAppliedMaxAbs'), last_finite_col(T, 'virialDuOverThermalRms'), ...
    last_finite_col(T, 'maxParticleAbsVx'), last_finite_col(T, 'maxParticleAbsVy'), ...
    last_finite_col(T, 'maxYWallReflectionsPerParticle'), ...
    'VariableNames', {'run','runDir','nFrames','timeStart','timeEnd', ...
    'uCenter','uMax','fitR2','nuEff','kBTEnd','stdNEnd', ...
    'q6RuntimeDivAfterEnd','q6RuntimeResidualEnd','q9RuntimeResidualEnd','q9TargetFilterRatioEnd', ...
    'q9CorrectionVelocityRmsEnd','q9CorrectionVelocityMaxEnd','virialEnabled','virialKickApplied', ...
    'PtotMeanEnd','gradPdriveRmsEnd','virialDuAppliedRmsEnd','virialDuAppliedMaxEnd', ...
    'virialDuOverThermalRmsEnd','maxParticleAbsVxEnd','maxParticleAbsVyEnd','yWallReflectionMaxPerParticleEnd'});
end

function m = local_tg_metrics(F)
Ux = F.Ux;
Uy = F.Uy;
valid = isfinite(Ux) & isfinite(Uy) & F.N > 0;
Ux0 = Ux; Uy0 = Uy;
Ux0(~valid) = 0;
Uy0(~valid) = 0;
[X, Y] = meshgrid(F.xc, F.yc);
bx = sin(2*pi*X/F.Lx) .* cos(2*pi*Y/F.Ly);
by = -cos(2*pi*X/F.Lx) .* sin(2*pi*Y/F.Ly);
num = sum(Ux0(valid).*bx(valid) + Uy0(valid).*by(valid));
den = sum(bx(valid).^2 + by(valid).^2);
amplitude = num / max(den, eps);
correlation = num / max(sqrt(sum(Ux0(valid).^2 + Uy0(valid).^2)) * sqrt(den), eps);
div = (circshift(Ux0, [0 -1]) - circshift(Ux0, [0 1]))/(2*F.dx) + ...
      (circshift(Uy0, [-1 0]) - circshift(Uy0, [1 0]))/(2*F.dy);
omega = (circshift(Uy0, [0 -1]) - circshift(Uy0, [0 1]))/(2*F.dx) - ...
        (circshift(Ux0, [-1 0]) - circshift(Ux0, [1 0]))/(2*F.dy);
m = struct('amplitude', amplitude, 'correlation', correlation, ...
    'divRms', sqrt(mean(div(valid).^2)), 'omegaRms', sqrt(mean(omega(valid).^2)));
end

function local_plot_suite(tg, pois)
figure('Name', 'Liquid closure dynamic suite');
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; hold on;
for k = 1:numel(tg.runs)
    r = tg.runs{k};
    plot(r.metrics.time, r.metrics.amplitude ./ first_finite_positive_abs(r.metrics.amplitude), 'DisplayName', char(r.label));
end
hold off; grid on; xlabel('time'); ylabel('A/A_0'); title('TG amplitude'); legend('Interpreter','none');

nexttile; hold on;
for k = 1:numel(tg.runs)
    r = tg.runs{k};
    plot(r.metrics.time, r.metrics.correlation, 'DisplayName', char(r.label));
end
hold off; grid on; xlabel('time'); ylabel('correlation'); title('TG pattern');

nexttile; hold on;
for k = 1:numel(tg.runs)
    r = tg.runs{k};
    if ismember('virialDuAppliedRms', r.runtime.Properties.VariableNames)
        semilogy(r.runtime.time, max(r.runtime.virialDuAppliedRms, eps), 'DisplayName', char(r.label));
    end
end
hold off; grid on; xlabel('time'); ylabel('du RMS'); title('TG virial kick');

nexttile; hold on;
for k = 1:numel(pois.runs)
    r = pois.runs{k};
    plot(r.profile.coord, r.profile.avgProfile, 'DisplayName', char(r.label));
end
hold off; grid on; xlabel('y'); ylabel('Ux'); title('Poiseuille mean profiles'); legend('Interpreter','none');

nexttile; hold on;
for k = 1:numel(pois.runs)
    r = pois.runs{k};
    if ismember('q9CorrectionVelocityRms', r.runtime.Properties.VariableNames)
        semilogy(r.runtime.time, max(r.runtime.q9CorrectionVelocityRms, eps), 'DisplayName', char(r.label));
    end
end
hold off; grid on; xlabel('time'); ylabel('Q9 du RMS'); title('Poiseuille Q9 kick');

nexttile; hold on;
for k = 1:numel(pois.runs)
    r = pois.runs{k};
    if ismember('virialDuAppliedRms', r.runtime.Properties.VariableNames)
        semilogy(r.runtime.time, max(r.runtime.virialDuAppliedRms, eps), 'DisplayName', char(r.label));
    end
end
hold off; grid on; xlabel('time'); ylabel('virial du RMS'); title('Poiseuille virial kick');
end

function T = local_read_summary(runDir)
f = fullfile(runDir, 'summary_runtime.csv');
if isfile(f)
    T = readtable(f);
else
    T = table();
end
end

function v = local_param(params, name, defaultValue)
if isfield(params, name)
    v = double(params.(name));
else
    v = defaultValue;
end
end

function v = first_finite_col(T, name)
v = NaN;
if istable(T) && ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'first');
    if ~isempty(idx), v = x(idx); end
end
end

function v = last_finite_col(T, name)
v = NaN;
if istable(T) && ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'last');
    if ~isempty(idx), v = x(idx); end
end
end

function v = first_finite_positive_abs(x)
idx = find(isfinite(x) & abs(x) > 0, 1, 'first');
if isempty(idx), v = NaN; else, v = x(idx); end
end

function v = last_finite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx), v = NaN; else, v = x(idx); end
end

function r = safe_ratio(a, b)
if isfinite(a) && isfinite(b) && abs(b) > 0
    r = a / b;
else
    r = NaN;
end
end

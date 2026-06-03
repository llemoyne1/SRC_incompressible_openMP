function out = analyze_open_channel_rect_obstacle_resampling_0138b(runRoot, varargin)
%ANALYZE_OPEN_CHANNEL_RECT_OBSTACLE_RESAMPLING_0138B Post-process open-channel-rect-obstacle runs.
%
% Usage from repository matlab/ directory:
%   analyze_open_channel_rect_obstacle_resampling_0138b('../runs/open_channel_rect_obstacle_resampling_0138b');
%
% The analyzer reads V1/V2 .smpcd dumps, bins only role=Fluid particles,
% overlays the immersed obstacle, and reports channel/wake/solid diagnostics.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','open_channel_rect_obstacle_resampling_0138b');
end
runRoot = char(strrep(string(runRoot), '\\', filesep));

p = inputParser;
p.FunctionName = 'analyze_open_channel_rect_obstacle_resampling_0138b';
addParameter(p, 'labels', {'classic','q6','q6_resampling'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'wakeXOffsetOverR', 1.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'wakeLengthOverR', 5.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'wallBandCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'probeXOverR', 4.0, @(x) isnumeric(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;
labels = cellstr(opt.labels);

analysisDir = fullfile(runRoot, 'analysis');
if ~isfolder(analysisDir)
    mkdir(analysisDir);
end

runs = struct([]);
for i = 1:numel(labels)
    label = labels{i};
    runDir = fullfile(runRoot, label);
    if ~isfolder(runDir)
        fprintf('[0138B] skipping missing run directory: %s\n', runDir);
        continue;
    end
    r = local_analyze_run(runDir, label, opt.wakeXOffsetOverR, opt.wakeLengthOverR, round(opt.wallBandCells), opt.probeXOverR);
    runs = [runs; r]; %#ok<AGROW>
    writetable(r.metrics, fullfile(analysisDir, sprintf('open_channel_rect_obstacle_metrics_%s.csv', label)));
    writetable(r.profile, fullfile(analysisDir, sprintf('open_channel_rect_obstacle_profile_%s.csv', label)));
end

summary = local_make_summary(runs);
writetable(summary, fullfile(analysisDir, 'open_channel_rect_obstacle_summary_0138b.csv'));

out = struct();
out.runRoot = runRoot;
out.analysisDir = analysisDir;
out.runs = runs;
out.summary = summary;

disp('=== Open-channel obstacle resampling 0138B summary ===');
disp(summary);
fprintf('[0138B] Analysis written to: %s\n', analysisDir);

if logical(opt.makePlots) && ~isempty(runs)
    local_plot_timeseries(runs, analysisDir);
    local_plot_final_fields(runs, analysisDir);
    local_plot_profiles(runs, analysisDir);
end
end

function run = local_analyze_run(runDir, label, wakeXOffsetOverR, wakeLengthOverR, wallBandCells, probeXOverR)
paramsFile = fullfile(runDir, 'params_used.kv');
if ~isfile(paramsFile)
    error('analyze_open_channel_rect_obstacle_resampling_0138b:missingParams', 'Cannot find params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsFile);
Lx = double(params.Lx); Ly = double(params.Ly);
Nx = double(params.Nx); Ny = double(params.Ny);
xMin = local_getfield(params, 'immersedSolidXMin', 0.85);
xMax = local_getfield(params, 'immersedSolidXMax', 1.10);
yMin = local_getfield(params, 'immersedSolidYMin', 0.38);
yMax = local_getfield(params, 'immersedSolidYMax', 0.62);
cx = 0.5 * (xMin + xMax);
cy = 0.5 * (yMin + yMax);
D  = max(xMax - xMin, yMax - yMin);
bodyAx = local_getfield(params, 'bodyAccelerationX', 0.0);

frames = list_smpcd_dumps(runDir);
if height(frames) == 0
    error('analyze_open_channel_rect_obstacle_resampling_0138b:noFrames', 'No state_step_*.smpcd dumps found in %s', runDir);
end
summaryFile = fullfile(runDir, 'summary_runtime.csv');
if isfile(summaryFile)
    runtime = readtable(summaryFile);
else
    runtime = table();
end

n = height(frames);
caseCol = repmat(string(label), n, 1);
step = frames.step;
time = frames.time;
meanUx = nan(n,1); meanUy = nan(n,1); centerUx = nan(n,1);
wakeMeanUx = nan(n,1); wakeMinUx = nan(n,1); wakeBackflowFraction = nan(n,1);
wakeUyRms = nan(n,1); wakeOmegaRms = nan(n,1);
probeUx = nan(n,1); probeUy = nan(n,1); probeOmega = nan(n,1);
solidLeakMass = nan(n,1); solidLeakCount = nan(n,1);
wallBandUxMean = nan(n,1); wallBandSpeedRms = nan(n,1); wallBandMassStd = nan(n,1);
stdN = nan(n,1); resampMRelRms = nan(n,1); q6Div = nan(n,1); kBT = nan(n,1);
resampExtractionOps = nan(n,1); resampInsertionOps = nan(n,1); resampRemapCells = nan(n,1); resampMassGuardParticles = nan(n,1);
lastFields = [];

for i = 1:n
    state = read_smpcd_state(char(frames.fullPath(i)));
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
        'periodicX', false, 'periodicY', false, 'fluidOnly', true);
    [XX, YY] = meshgrid(fields.xc, fields.yc);
    solidMask = (XX >= xMin) & (XX <= xMax) & (YY >= yMin) & (YY <= yMax);
    fluidMask = ~solidMask;
    xRel = XX - xMax;
    wakeMask = (xRel > wakeXOffsetOverR * D) & (xRel < wakeLengthOverR * D) & fluidMask;
    if ~any(wakeMask(:))
        wakeMask = (XX > xMax + wakeXOffsetOverR * D) & fluidMask;
    end
    centerBand = abs(YY - cy) <= max(0.5 * (Ly / Ny), 0.5 * (yMax-yMin));
    wallBand = (YY <= wallBandCells * (Ly / Ny)) | (YY >= Ly - wallBandCells * (Ly / Ny));
    probeX = min(max(xMax + probeXOverR * D, fields.xc(1)), fields.xc(end));
    [~, iprobe] = min(abs(fields.xc - probeX));
    [~, jprobe] = min(abs(fields.yc - cy));

    meanUx(i) = mean(fields.Ux(fluidMask), 'omitnan');
    meanUy(i) = mean(fields.Uy(fluidMask), 'omitnan');
    centerUx(i) = mean(fields.Ux(centerBand & fluidMask), 'omitnan');
    wakeMeanUx(i) = mean(fields.Ux(wakeMask), 'omitnan');
    wakeMinUx(i) = min(fields.Ux(wakeMask), [], 'omitnan');
    wakeBackflowFraction(i) = mean(fields.Ux(wakeMask) < 0, 'omitnan');
    wakeUyRms(i) = sqrt(mean(fields.Uy(wakeMask).^2, 'omitnan'));
    wakeOmegaRms(i) = sqrt(mean(fields.omega(wakeMask).^2, 'omitnan'));
    probeUx(i) = fields.Ux(jprobe, iprobe);
    probeUy(i) = fields.Uy(jprobe, iprobe);
    probeOmega(i) = fields.omega(jprobe, iprobe);
    solidLeakMass(i) = sum(fields.mass(solidMask), 'omitnan');
    solidLeakCount(i) = sum(fields.N(solidMask), 'omitnan');
    wallBandUxMean(i) = mean(abs(fields.Ux(wallBand)), 'omitnan');
    wallBandSpeedRms(i) = sqrt(mean(fields.speed(wallBand).^2, 'omitnan'));
    wallBandMassStd(i) = std(fields.mass(wallBand), 0, 'omitnan');

    lastFields = fields;
    lastFields.solidMask = solidMask;
    lastFields.wakeMask = wakeMask;
    lastFields.wallBand = wallBand;
    lastFields.rectXMin = xMin; lastFields.rectXMax = xMax; lastFields.rectYMin = yMin; lastFields.rectYMax = yMax;

    if ~isempty(runtime) && ismember('step', runtime.Properties.VariableNames)
        j = find(runtime.step == step(i), 1, 'first');
        if ~isempty(j)
            stdN(i) = local_runtime(runtime, j, 'stdN');
            resampMRelRms(i) = local_runtime(runtime, j, 'resampMRelRms');
            q6Div(i) = local_runtime(runtime, j, 'q6DivAfterProjectedFluxRms');
            kBT(i) = local_runtime(runtime, j, 'kBTEstimate');
            resampExtractionOps(i) = local_runtime(runtime, j, 'resampExtractionApplyOpsApplied');
            resampInsertionOps(i) = local_runtime(runtime, j, 'resampInsertionApplyOpsApplied');
            resampRemapCells(i) = local_runtime(runtime, j, 'resampRemapCellsRemapped');
            resampMassGuardParticles(i) = local_runtime(runtime, j, 'resampMassGuardParticlesAdjusted');
        end
    end
end

metrics = table(caseCol, step, time, meanUx, meanUy, centerUx, wakeMeanUx, wakeMinUx, wakeBackflowFraction, wakeUyRms, wakeOmegaRms, probeUx, probeUy, probeOmega, ...
    solidLeakMass, solidLeakCount, wallBandUxMean, wallBandSpeedRms, wallBandMassStd, ...
    stdN, resampMRelRms, q6Div, kBT, resampExtractionOps, resampInsertionOps, resampRemapCells, resampMassGuardParticles, ...
    'VariableNames', {'case','step','time','meanUx','meanUy','centerUx','wakeMeanUx','wakeMinUx','wakeBackflowFraction','wakeUyRms','wakeOmegaRms','probeUx','probeUy','probeOmega', ...
    'solidLeakMass','solidLeakCount','wallBandUxMean','wallBandSpeedRms','wallBandMassStd', ...
    'stdN','resampMRelRms','q6DivAfterProjectedFluxRms','kBTEstimate','resampExtractionOps','resampInsertionOps','resampRemapCells','resampMassGuardParticles'});

profile = local_profile_from_fields(lastFields, label);

run = struct();
run.label = label;
run.runDir = runDir;
run.params = params;
run.bodyAccelerationX = bodyAx;
run.frames = frames;
run.metrics = metrics;
run.profile = profile;
run.finalFields = lastFields;
end

function P = local_profile_from_fields(f, label)
Ny = numel(f.yc);
caseCol = repmat(string(label), Ny, 1);
y = f.yc(:);
meanUx = mean(f.Ux, 2, 'omitnan');
meanUy = mean(f.Uy, 2, 'omitnan');
meanMass = mean(f.mass, 2, 'omitnan');
meanN = mean(f.N, 2, 'omitnan');
P = table(caseCol, y, meanUx, meanUy, meanMass, meanN, 'VariableNames', {'case','y','meanUx','meanUy','meanMass','meanN'});
end

function summary = local_make_summary(runs)
if isempty(runs)
    summary = table();
    return;
end
n = numel(runs);
caseName = strings(n,1);
nFrames = nan(n,1);
finalMeanUx = nan(n,1); finalCenterUx = nan(n,1);
finalWakeMeanUx = nan(n,1); finalWakeMinUx = nan(n,1); finalWakeBackflowFraction = nan(n,1);
finalWakeUyRms = nan(n,1); finalWakeOmegaRms = nan(n,1);
probeUyRmsLate = nan(n,1); probeOmegaRmsLate = nan(n,1); probeDominantFrequency = nan(n,1); probeStrouhal = nan(n,1);
finalSolidLeakMass = nan(n,1); maxSolidLeakMass = nan(n,1);
finalWallBandUxMean = nan(n,1); finalWallBandMassStd = nan(n,1);
finalStdN = nan(n,1); finalResampMRelRms = nan(n,1); maxResampMRelRms = nan(n,1); finalQ6Div = nan(n,1);
totalExtracted = nan(n,1); totalInserted = nan(n,1); totalRemapCells = nan(n,1); totalMassGuardAdjusted = nan(n,1);
for i = 1:n
    T = runs(i).metrics;
    caseName(i) = string(runs(i).label);
    nFrames(i) = height(T);
    finalMeanUx(i) = T.meanUx(end);
    finalCenterUx(i) = T.centerUx(end);
    finalWakeMeanUx(i) = T.wakeMeanUx(end);
    finalWakeMinUx(i) = T.wakeMinUx(end);
    finalWakeBackflowFraction(i) = T.wakeBackflowFraction(end);
    finalWakeUyRms(i) = T.wakeUyRms(end);
    finalWakeOmegaRms(i) = T.wakeOmegaRms(end);
    lateMask = T.time >= (T.time(1) + 0.5 * (T.time(end) - T.time(1)));
    probeUyRmsLate(i) = sqrt(mean(T.probeUy(lateMask).^2, 'omitnan'));
    probeOmegaRmsLate(i) = sqrt(mean(T.probeOmega(lateMask).^2, 'omitnan'));
    [probeDominantFrequency(i), probeStrouhal(i)] = local_probe_frequency(T.time(lateMask), T.probeUy(lateMask), T.meanUx(lateMask), runs(i).params);
    finalSolidLeakMass(i) = T.solidLeakMass(end);
    maxSolidLeakMass(i) = max(T.solidLeakMass, [], 'omitnan');
    finalWallBandUxMean(i) = T.wallBandUxMean(end);
    finalWallBandMassStd(i) = T.wallBandMassStd(end);
    finalStdN(i) = T.stdN(end);
    finalResampMRelRms(i) = T.resampMRelRms(end);
    maxResampMRelRms(i) = max(T.resampMRelRms, [], 'omitnan');
    finalQ6Div(i) = T.q6DivAfterProjectedFluxRms(end);
    totalExtracted(i) = sum(T.resampExtractionOps, 'omitnan');
    totalInserted(i) = sum(T.resampInsertionOps, 'omitnan');
    totalRemapCells(i) = sum(T.resampRemapCells, 'omitnan');
    totalMassGuardAdjusted(i) = sum(T.resampMassGuardParticles, 'omitnan');
end
summary = table(caseName, nFrames, finalMeanUx, finalCenterUx, finalWakeMeanUx, finalWakeMinUx, finalWakeBackflowFraction, ...
    finalWakeUyRms, finalWakeOmegaRms, probeUyRmsLate, probeOmegaRmsLate, probeDominantFrequency, probeStrouhal, finalSolidLeakMass, maxSolidLeakMass, finalWallBandUxMean, finalWallBandMassStd, ...
    finalStdN, finalResampMRelRms, maxResampMRelRms, finalQ6Div, totalExtracted, totalInserted, totalRemapCells, totalMassGuardAdjusted);
end

function local_plot_timeseries(runs, analysisDir)
fig = figure('Name', '0138B open-channel rectangular obstacle timeseries', 'Visible', 'on');
tiledlayout(6,1);
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.meanUx); end
ylabel('mean Ux'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.wakeOmegaRms); end
ylabel('wake omega RMS'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.wakeBackflowFraction); end
ylabel('wake backflow frac.'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.probeUy); end
ylabel('probe Uy'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.resampMRelRms); end
ylabel('resamp MRelRMS'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.solidLeakMass); end
ylabel('solid leak mass'); xlabel('time'); legend({runs.label}, 'Location', 'best');
saveas(fig, fullfile(analysisDir, 'open_channel_rect_obstacle_0138b_timeseries.png'));
end

function local_plot_final_fields(runs, analysisDir)
for i = 1:numel(runs)
    f = runs(i).finalFields;
    fig = figure('Name', ['0138B final fields ' runs(i).label], 'Visible', 'on');
    tiledlayout(3,2);
    local_field_tile(f, f.speed, 'speed');
    local_field_tile(f, f.Ux, 'Ux');
    local_field_tile(f, f.Uy, 'Uy');
    local_field_tile(f, f.omega, 'vorticity');
    local_field_tile(f, f.mass, 'cell mass');
    local_field_tile(f, f.N, 'cell population');
    saveas(fig, fullfile(analysisDir, sprintf('open_channel_rect_obstacle_0138b_final_fields_%s.png', runs(i).label)));
end
end

function local_plot_profiles(runs, analysisDir)
fig = figure('Name', '0138B open-channel rectangular obstacle final profiles', 'Visible', 'on');
tiledlayout(1,2);
nexttile; hold on; grid on;
for i = 1:numel(runs)
    plot(runs(i).profile.meanUx, runs(i).profile.y);
end
xlabel('mean Ux'); ylabel('y'); title('streamwise profile'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs)
    plot(runs(i).profile.meanMass, runs(i).profile.y);
end
xlabel('mean cell mass'); ylabel('y'); title('mass profile'); legend({runs.label}, 'Location', 'best');
saveas(fig, fullfile(analysisDir, 'open_channel_rect_obstacle_0138b_profiles.png'));
end

function local_field_tile(f, A, ttl)
nexttile;
imagesc(f.xc, f.yc, A);
set(gca, 'YDir', 'normal'); axis equal tight; colorbar;
title(ttl); xlabel('x'); ylabel('y');
hold on; local_draw_rect(f.rectXMin, f.rectXMax, f.rectYMin, f.rectYMax, 'k-', 1.5); hold off;
end

function local_draw_rect(xMin, xMax, yMin, yMax, style, lw)
plot([xMin xMax xMax xMin xMin], [yMin yMin yMax yMax yMin], style, 'LineWidth', lw);
end

function [freq, St] = local_probe_frequency(t, y, meanUx, params)
freq = NaN; St = NaN;
if numel(t) < 5 || all(~isfinite(y))
    return;
end
t = t(:); y = y(:);
ok = isfinite(t) & isfinite(y);
t = t(ok); y = y(ok);
if numel(t) < 5 || t(end) <= t(1)
    return;
end
y = y - mean(y, 'omitnan');
if all(abs(y) < 1e-14)
    return;
end
dt = median(diff(t));
if ~isfinite(dt) || dt <= 0
    return;
end
Y = abs(fft(y));
Y(1) = 0;
n = numel(Y);
maxK = floor(n/2);
if maxK < 2
    return;
end
[~, k] = max(Y(2:maxK));
k = k + 1;
freq = (k - 1) / (n * dt);
D = max(local_getfield(params, 'immersedSolidXMax', 1.10) - local_getfield(params, 'immersedSolidXMin', 0.85), local_getfield(params, 'immersedSolidYMax', 0.62) - local_getfield(params, 'immersedSolidYMin', 0.38));
U = mean(meanUx, 'omitnan');
if isfinite(U) && abs(U) > 1e-14
    St = freq * D / abs(U);
end
end

function v = local_getfield(s, name, default)
if isfield(s, name)
    v = double(s.(name));
else
    v = default;
end
end

function v = local_runtime(T, row, name)
if ismember(name, T.Properties.VariableNames)
    v = T.(name)(row);
else
    v = NaN;
end
end

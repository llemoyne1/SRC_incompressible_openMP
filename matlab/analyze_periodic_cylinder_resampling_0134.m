function out = analyze_periodic_cylinder_resampling_0134(runRoot, varargin)
%ANALYZE_PERIODIC_CYLINDER_RESAMPLING_0134 Post-process periodic immersed-cylinder runs.
%
% Usage from the repository matlab/ directory:
%   analyze_periodic_cylinder_resampling_0134('../runs/periodic_cylinder_resampling_0134');
%
% The analyzer reads V1/V2 .smpcd dumps, bins only role=Fluid particles,
% overlays the immersed cylinder, and reports simple wake/diagnostic metrics.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','periodic_cylinder_resampling_0134');
end
runRoot = char(strrep(string(runRoot), '\\', filesep));

p = inputParser;
p.FunctionName = 'analyze_periodic_cylinder_resampling_0134';
addParameter(p, 'labels', {'classic','q6','q6_resampling'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'wakeXOffsetOverR', 1.0, @(x) isnumeric(x) && isscalar(x));
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
        fprintf('[0134] skipping missing run directory: %s\n', runDir);
        continue;
    end
    r = local_analyze_run(runDir, label, opt.wakeXOffsetOverR);
    runs = [runs; r]; %#ok<AGROW>
    writetable(r.metrics, fullfile(analysisDir, sprintf('periodic_cylinder_metrics_%s.csv', label)));
end

summary = local_make_summary(runs);
writetable(summary, fullfile(analysisDir, 'periodic_cylinder_summary_0134.csv'));

out = struct();
out.runRoot = runRoot;
out.analysisDir = analysisDir;
out.runs = runs;
out.summary = summary;

disp('=== Periodic cylinder resampling 0134 summary ===');
disp(summary);
fprintf('[0134] Analysis written to: %s\n', analysisDir);

if logical(opt.makePlots) && ~isempty(runs)
    local_plot_timeseries(runs, analysisDir);
    local_plot_final_fields(runs, analysisDir);
end
end

function run = local_analyze_run(runDir, label, wakeXOffsetOverR)
paramsFile = fullfile(runDir, 'params_used.kv');
if ~isfile(paramsFile)
    error('analyze_periodic_cylinder_resampling_0134:missingParams', 'Cannot find params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsFile);
Lx = double(params.Lx); Ly = double(params.Ly);
Nx = double(params.Nx); Ny = double(params.Ny);
cx = local_getfield(params, 'immersedSolidCx', 0.5 * Lx);
cy = local_getfield(params, 'immersedSolidCy', 0.5 * Ly);
R  = local_getfield(params, 'immersedSolidR', 0.12);
bodyAx = local_getfield(params, 'bodyAccelerationX', 0.0);

frames = list_smpcd_dumps(runDir);
if height(frames) == 0
    error('analyze_periodic_cylinder_resampling_0134:noFrames', 'No state_step_*.smpcd dumps found in %s', runDir);
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
meanUx = nan(n,1); meanUy = nan(n,1);
wakeMeanUx = nan(n,1); wakeUyRms = nan(n,1); wakeOmegaRms = nan(n,1);
solidLeakMass = nan(n,1); solidLeakCount = nan(n,1);
stdN = nan(n,1); resampMRelRms = nan(n,1); q6Div = nan(n,1); kBT = nan(n,1);
resampExtractionOps = nan(n,1); resampInsertionOps = nan(n,1); resampRemapCells = nan(n,1); resampMassGuardParticles = nan(n,1);
lastFields = [];

for i = 1:n
    state = read_smpcd_state(char(frames.fullPath(i)));
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
        'periodicX', true, 'periodicY', true, 'fluidOnly', true);
    [XX, YY] = meshgrid(fields.xc, fields.yc);
    solidMask = ((XX - cx).^2 + (YY - cy).^2) < R^2;
    wakeMask = (XX > cx + wakeXOffsetOverR * R) & ~solidMask;

    meanUx(i) = mean(fields.Ux(~solidMask), 'omitnan');
    meanUy(i) = mean(fields.Uy(~solidMask), 'omitnan');
    wakeMeanUx(i) = mean(fields.Ux(wakeMask), 'omitnan');
    wakeUyRms(i) = sqrt(mean(fields.Uy(wakeMask).^2, 'omitnan'));
    wakeOmegaRms(i) = sqrt(mean(fields.omega(wakeMask).^2, 'omitnan'));
    solidLeakMass(i) = sum(fields.mass(solidMask), 'omitnan');
    solidLeakCount(i) = sum(fields.N(solidMask), 'omitnan');
    lastFields = fields;
    lastFields.solidMask = solidMask;
    lastFields.cylinderCx = cx; lastFields.cylinderCy = cy; lastFields.cylinderR = R;

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

metrics = table(caseCol, step, time, meanUx, meanUy, wakeMeanUx, wakeUyRms, wakeOmegaRms, solidLeakMass, solidLeakCount, ...
    stdN, resampMRelRms, q6Div, kBT, resampExtractionOps, resampInsertionOps, resampRemapCells, resampMassGuardParticles, ...
    'VariableNames', {'case','step','time','meanUx','meanUy','wakeMeanUx','wakeUyRms','wakeOmegaRms','solidLeakMass','solidLeakCount', ...
    'stdN','resampMRelRms','q6DivAfterProjectedFluxRms','kBTEstimate','resampExtractionOps','resampInsertionOps','resampRemapCells','resampMassGuardParticles'});

run = struct();
run.label = label;
run.runDir = runDir;
run.params = params;
run.bodyAccelerationX = bodyAx;
run.frames = frames;
run.metrics = metrics;
run.finalFields = lastFields;
end

function summary = local_make_summary(runs)
if isempty(runs)
    summary = table();
    return;
end
n = numel(runs);
caseName = strings(n,1);
nFrames = nan(n,1);
finalMeanUx = nan(n,1); finalWakeMeanUx = nan(n,1); finalWakeUyRms = nan(n,1); finalWakeOmegaRms = nan(n,1);
finalSolidLeakMass = nan(n,1); maxSolidLeakMass = nan(n,1);
finalStdN = nan(n,1); finalResampMRelRms = nan(n,1); maxResampMRelRms = nan(n,1); finalQ6Div = nan(n,1);
totalExtracted = nan(n,1); totalInserted = nan(n,1); totalRemapCells = nan(n,1); totalMassGuardAdjusted = nan(n,1);
for i = 1:n
    T = runs(i).metrics;
    caseName(i) = string(runs(i).label);
    nFrames(i) = height(T);
    finalMeanUx(i) = T.meanUx(end);
    finalWakeMeanUx(i) = T.wakeMeanUx(end);
    finalWakeUyRms(i) = T.wakeUyRms(end);
    finalWakeOmegaRms(i) = T.wakeOmegaRms(end);
    finalSolidLeakMass(i) = T.solidLeakMass(end);
    maxSolidLeakMass(i) = max(T.solidLeakMass, [], 'omitnan');
    finalStdN(i) = T.stdN(end);
    finalResampMRelRms(i) = T.resampMRelRms(end);
    maxResampMRelRms(i) = max(T.resampMRelRms, [], 'omitnan');
    finalQ6Div(i) = T.q6DivAfterProjectedFluxRms(end);
    totalExtracted(i) = sum(T.resampExtractionOps, 'omitnan');
    totalInserted(i) = sum(T.resampInsertionOps, 'omitnan');
    totalRemapCells(i) = sum(T.resampRemapCells, 'omitnan');
    totalMassGuardAdjusted(i) = sum(T.resampMassGuardParticles, 'omitnan');
end
summary = table(caseName, nFrames, finalMeanUx, finalWakeMeanUx, finalWakeUyRms, finalWakeOmegaRms, ...
    finalSolidLeakMass, maxSolidLeakMass, finalStdN, finalResampMRelRms, maxResampMRelRms, finalQ6Div, ...
    totalExtracted, totalInserted, totalRemapCells, totalMassGuardAdjusted);
end

function local_plot_timeseries(runs, analysisDir)
fig = figure('Name', '0134 periodic cylinder timeseries', 'Visible', 'on');
tiledlayout(4,1);
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.meanUx); end
ylabel('mean Ux'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.wakeOmegaRms); end
ylabel('wake omega RMS'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.resampMRelRms); end
ylabel('resamp MRelRMS'); legend({runs.label}, 'Location', 'best');
nexttile; hold on; grid on;
for i = 1:numel(runs), plot(runs(i).metrics.time, runs(i).metrics.stdN); end
ylabel('std(N)'); xlabel('time'); legend({runs.label}, 'Location', 'best');
saveas(fig, fullfile(analysisDir, 'periodic_cylinder_0134_timeseries.png'));
end

function local_plot_final_fields(runs, analysisDir)
for i = 1:numel(runs)
    f = runs(i).finalFields;
    fig = figure('Name', ['0134 final fields ' runs(i).label], 'Visible', 'on');
    tiledlayout(3,2);
    local_field_tile(f, f.speed, 'speed');
    local_field_tile(f, f.Ux, 'Ux');
    local_field_tile(f, f.Uy, 'Uy');
    local_field_tile(f, f.omega, 'vorticity');
    local_field_tile(f, f.mass, 'cell mass');
    local_field_tile(f, f.N, 'cell population');
    saveas(fig, fullfile(analysisDir, sprintf('periodic_cylinder_0134_final_fields_%s.png', runs(i).label)));
end
end

function local_field_tile(f, A, ttl)
nexttile;
imagesc(f.xc, f.yc, A);
set(gca, 'YDir', 'normal'); axis equal tight; colorbar;
title(ttl); xlabel('x'); ylabel('y');
hold on; local_draw_circle(f.cylinderCx, f.cylinderCy, f.cylinderR, 'k-', 1.5); hold off;
end

function local_draw_circle(cx, cy, R, style, lw)
th = linspace(0, 2*pi, 256);
plot(cx + R*cos(th), cy + R*sin(th), style, 'LineWidth', lw);
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

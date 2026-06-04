function out = analyze_poiseuille_wallvp_resampling_0131(runRoot, varargin)
%ANALYZE_POISEUILLE_WALLVP_RESAMPLING_0131 Post-process 0131 channel runs.
%
% Usage from the repository matlab/ directory:
%   analyze_poiseuille_wallvp_resampling_0131('../runs/poiseuille_wallvp_resampling_0131');
%
% The analyzer reads V1/V2 .smpcd dumps, bins only role=Fluid particles, builds
% x-averaged Ux(y) profiles and fits a Poiseuille parabola
%   Ux(y) = Uslip + C y (Ly-y),  nu_eff = bodyAccelerationX/(2C).

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','poiseuille_wallvp_resampling_0131');
end
runRoot = char(strrep(string(runRoot), '\\', filesep));

p = inputParser;
p.FunctionName = 'analyze_poiseuille_wallvp_resampling_0131';
addParameter(p, 'labels', {'classic','q6','q6_resampling'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'excludeWallCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'fitStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(p, 'fitStartTime', NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
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
        fprintf('[0131] skipping missing run directory: %s\n', runDir);
        continue;
    end
    r = local_analyze_run(runDir, label, opt.excludeWallCells, opt.fitStartFraction, opt.fitStartTime);
    runs = [runs; r]; %#ok<AGROW>
    writetable(r.metrics, fullfile(analysisDir, sprintf('poiseuille_metrics_%s.csv', label)));
    writetable(r.profileTable, fullfile(analysisDir, sprintf('poiseuille_profile_%s.csv', label)));
end

summary = local_make_summary(runs);
writetable(summary, fullfile(analysisDir, 'poiseuille_summary_0131.csv'));

out = struct();
out.runRoot = runRoot;
out.analysisDir = analysisDir;
out.runs = runs;
out.summary = summary;

disp('=== Poiseuille wallVP resampling 0131 summary ===');
disp(summary);
fprintf('[0131] Analysis written to: %s\n', analysisDir);

if logical(opt.makePlots) && ~isempty(runs)
    local_plot_profiles(runs, analysisDir);
    local_plot_timeseries(runs, analysisDir);
    local_plot_final_fields(runs, analysisDir);
end
end

function run = local_analyze_run(runDir, label, excludeWallCells, fitStartFraction, fitStartTime)
paramsFile = fullfile(runDir, 'params_used.kv');
if ~isfile(paramsFile)
    error('analyze_poiseuille_wallvp_resampling_0131:missingParams', 'Cannot find params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsFile);
Lx = double(params.Lx);
Ly = double(params.Ly);
Nx = double(params.Nx);
Ny = double(params.Ny);
bodyAx = local_getfield(params, 'bodyAccelerationX', 0.0);
if bodyAx == 0 && isfield(params, 'bodyForceX')
    bodyAx = double(params.bodyForceX);
end

frames = list_smpcd_dumps(runDir);
if height(frames) == 0
    error('analyze_poiseuille_wallvp_resampling_0131:noFrames', 'No state_step_*.smpcd dumps found in %s', runDir);
end
summaryFile = fullfile(runDir, 'summary_runtime.csv');
if isfile(summaryFile)
    runtime = readtable(summaryFile);
else
    runtime = table();
end

n = height(frames);
yc = [];
UxProfiles = [];
NProfiles = [];
MProfiles = [];
labelCol = repmat(string(label), n, 1);
step = frames.step;
time = frames.time;
meanUx = nan(n,1);
centerUx = nan(n,1);
maxUx = nan(n,1);
minUx = nan(n,1);
stdN = nan(n,1);
resampMRelRms = nan(n,1);
q6DivAfterProjectedFluxRms = nan(n,1);
kBTEstimate = nan(n,1);
resampExtractionOps = nan(n,1);
resampInsertionOps = nan(n,1);
resampRemapCells = nan(n,1);
resampMassGuardParticles = nan(n,1);
lastFields = [];

for i = 1:n
    state = read_smpcd_state(char(frames.fullPath(i)));
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
        'periodicX', true, 'periodicY', false, 'fluidOnly', true);
    if isempty(yc)
        yc = fields.yc(:);
        UxProfiles = nan(Ny, n);
        NProfiles = nan(Ny, n);
        MProfiles = nan(Ny, n);
    end
    ux = mean(fields.Ux, 2, 'omitnan');
    nn = mean(fields.N, 2, 'omitnan');
    mm = mean(fields.mass, 2, 'omitnan');
    UxProfiles(:, i) = ux;
    NProfiles(:, i) = nn;
    MProfiles(:, i) = mm;
    meanUx(i) = mean(fields.Ux(:), 'omitnan');
    [~, cidx] = min(abs(yc - 0.5*Ly));
    centerUx(i) = ux(cidx);
    maxUx(i) = max(ux, [], 'omitnan');
    minUx(i) = min(ux, [], 'omitnan');
    lastFields = fields;

    if ~isempty(runtime) && ismember('step', runtime.Properties.VariableNames)
        j = find(runtime.step == step(i), 1, 'first');
        if ~isempty(j)
            stdN(i) = local_runtime(runtime, j, 'stdN');
            resampMRelRms(i) = local_runtime(runtime, j, 'resampMRelRms');
            q6DivAfterProjectedFluxRms(i) = local_runtime(runtime, j, 'q6DivAfterProjectedFluxRms');
            kBTEstimate(i) = local_runtime(runtime, j, 'kBTEstimate');
            resampExtractionOps(i) = local_runtime(runtime, j, 'resampExtractionApplyOpsApplied');
            resampInsertionOps(i) = local_runtime(runtime, j, 'resampInsertionApplyOpsApplied');
            resampRemapCells(i) = local_runtime(runtime, j, 'resampRemapCellsRemapped');
            resampMassGuardParticles(i) = local_runtime(runtime, j, 'resampMassGuardParticlesAdjusted');
        end
    end
end

metrics = table(labelCol, step, time, meanUx, centerUx, maxUx, minUx, stdN, resampMRelRms, ...
    q6DivAfterProjectedFluxRms, kBTEstimate, resampExtractionOps, resampInsertionOps, resampRemapCells, resampMassGuardParticles, ...
    'VariableNames', {'case','step','time','meanUx','centerUx','maxUx','minUx','stdN','resampMRelRms', ...
    'q6DivAfterProjectedFluxRms','kBTEstimate','resampExtractionOps','resampInsertionOps','resampRemapCells','resampMassGuardParticles'});

if isnan(fitStartTime)
    tmax = max(time(isfinite(time)));
    if isempty(tmax) || ~isfinite(tmax)
        fitStartTime = -inf;
    else
        fitStartTime = fitStartFraction * tmax;
    end
end
fitFrames = find(time >= fitStartTime);
if isempty(fitFrames)
    fitFrames = max(1, floor(0.5*n)):n;
end
meanProfile = mean(UxProfiles(:, fitFrames), 2, 'omitnan');
meanNProfile = mean(NProfiles(:, fitFrames), 2, 'omitnan');
meanMProfile = mean(MProfiles(:, fitFrames), 2, 'omitnan');
fit = local_fit_poiseuille(yc, meanProfile, Ly, bodyAx, excludeWallCells);
profileTable = table(yc(:), meanProfile(:), fit.fitUx(:), meanNProfile(:), meanMProfile(:), ...
    'VariableNames', {'y','meanUx','fitUx','meanN','meanMass'});

run = struct();
run.label = label;
run.runDir = runDir;
run.params = params;
run.frames = frames;
run.metrics = metrics;
run.y = yc;
run.UxProfiles = UxProfiles;
run.profileTable = profileTable;
run.fit = fit;
run.fitStartTime = fitStartTime;
run.fitFrameCount = numel(fitFrames);
run.finalFields = lastFields;
end

function fit = local_fit_poiseuille(y, ux, Ly, bodyAx, excludeWallCells)
y = y(:);
ux = ux(:);
n = numel(y);
lo = 1 + round(excludeWallCells);
hi = n - round(excludeWallCells);
if lo > hi
    lo = 1;
    hi = n;
end
idx = (lo:hi).';
idx = idx(isfinite(ux(idx)));
z = y(idx) .* (Ly - y(idx));
A = [ones(numel(idx),1), z];
coef = A \ ux(idx);
slip = coef(1);
C = coef(2);
fitUx = slip + C .* y .* (Ly - y);
resid = ux(idx) - (slip + C .* z);
ssRes = sum(resid.^2);
ssTot = sum((ux(idx) - mean(ux(idx))).^2);
r2 = 1 - ssRes / max(ssTot, eps);
rmsResidual = sqrt(mean(resid.^2));
signal = max(ux(idx)) - min(ux(idx));
snr = signal / max(rmsResidual, eps);
if C ~= 0 && sign(C) == sign(bodyAx)
    nuEff = bodyAx / (2.0 * C);
else
    nuEff = NaN;
end
fit = struct();
fit.excludeWallCells = excludeWallCells;
fit.slipUx = slip;
fit.curvatureCoeff = C;
fit.nuEff = nuEff;
fit.r2 = r2;
fit.rmsResidual = rmsResidual;
fit.signalToResidual = snr;
fit.centerUxFit = slip + C * (0.5*Ly) * (Ly - 0.5*Ly);
fit.fitUx = fitUx;
end

function summary = local_make_summary(runs)
if isempty(runs)
    summary = table();
    return;
end
n = numel(runs);
caseName = strings(n,1);
nFrames = nan(n,1);
fitStartTime = nan(n,1);
fitFrameCount = nan(n,1);
finalMeanUx = nan(n,1);
finalCenterUx = nan(n,1);
lateMeanUx = nan(n,1);
lateCenterUx = nan(n,1);
nuEff = nan(n,1);
r2 = nan(n,1);
signalToResidual = nan(n,1);
slipUx = nan(n,1);
finalStdN = nan(n,1);
finalResampMRelRms = nan(n,1);
maxResampMRelRms = nan(n,1);
finalQ6Div = nan(n,1);
totalExtracted = nan(n,1);
totalInserted = nan(n,1);
totalRemapCells = nan(n,1);
totalMassGuardAdjusted = nan(n,1);
for i = 1:n
    T = runs(i).metrics;
    caseName(i) = string(runs(i).label);
    nFrames(i) = height(T);
    fitStartTime(i) = runs(i).fitStartTime;
    fitFrameCount(i) = runs(i).fitFrameCount;
    finalMeanUx(i) = T.meanUx(end);
    finalCenterUx(i) = T.centerUx(end);
    lateMeanUx(i) = mean(T.meanUx(T.time >= runs(i).fitStartTime), 'omitnan');
    lateCenterUx(i) = mean(T.centerUx(T.time >= runs(i).fitStartTime), 'omitnan');
    nuEff(i) = runs(i).fit.nuEff;
    r2(i) = runs(i).fit.r2;
    signalToResidual(i) = runs(i).fit.signalToResidual;
    slipUx(i) = runs(i).fit.slipUx;
    finalStdN(i) = T.stdN(end);
    finalResampMRelRms(i) = T.resampMRelRms(end);
    maxResampMRelRms(i) = max(T.resampMRelRms, [], 'omitnan');
    finalQ6Div(i) = T.q6DivAfterProjectedFluxRms(end);
    totalExtracted(i) = sum(T.resampExtractionOps, 'omitnan');
    totalInserted(i) = sum(T.resampInsertionOps, 'omitnan');
    totalRemapCells(i) = sum(T.resampRemapCells, 'omitnan');
    totalMassGuardAdjusted(i) = sum(T.resampMassGuardParticles, 'omitnan');
end
summary = table(caseName, nFrames, fitStartTime, fitFrameCount, finalMeanUx, finalCenterUx, ...
    lateMeanUx, lateCenterUx, nuEff, r2, signalToResidual, slipUx, finalStdN, ...
    finalResampMRelRms, maxResampMRelRms, finalQ6Div, totalExtracted, totalInserted, totalRemapCells, totalMassGuardAdjusted);
end

function v = local_runtime(runtime, row, col)
if ismember(col, runtime.Properties.VariableNames)
    v = runtime.(col)(row);
else
    v = nan;
end
end

function v = local_getfield(s, name, default)
if isfield(s, name)
    v = double(s.(name));
else
    v = default;
end
end

function local_plot_profiles(runs, analysisDir)
fig = figure('Name','Poiseuille 0131 late profiles','Visible','on');
hold on; grid on;
for i = 1:numel(runs)
    P = runs(i).profileTable;
    plot(P.meanUx, P.y, 'DisplayName', runs(i).label);
    plot(P.fitUx, P.y, '--', 'HandleVisibility', 'off');
end
xlabel('Ux'); ylabel('y'); legend('Location','best');
saveas(fig, fullfile(analysisDir, 'poiseuille_0131_late_profiles.png'));
end

function local_plot_timeseries(runs, analysisDir)
fig = figure('Name','Poiseuille 0131 diagnostics','Visible','on');
tiledlayout(fig, 3, 1);
nexttile; hold on; grid on;
for i = 1:numel(runs)
    T = runs(i).metrics;
    plot(T.time, T.centerUx, 'DisplayName', runs(i).label);
end
xlabel('time'); ylabel('center Ux'); legend('Location','best');
nexttile; hold on; grid on;
for i = 1:numel(runs)
    T = runs(i).metrics;
    semilogy(T.time, max(T.resampMRelRms, realmin), 'DisplayName', runs(i).label);
end
xlabel('time'); ylabel('resamp MRelRMS'); legend('Location','best');
nexttile; hold on; grid on;
for i = 1:numel(runs)
    T = runs(i).metrics;
    plot(T.time, T.stdN, 'DisplayName', runs(i).label);
end
xlabel('time'); ylabel('std(N)'); legend('Location','best');
saveas(fig, fullfile(analysisDir, 'poiseuille_0131_timeseries.png'));
end

function local_plot_final_fields(runs, analysisDir)
for i = 1:numel(runs)
    f = runs(i).finalFields;
    if isempty(f)
        continue;
    end
    fig = figure('Name',sprintf('Poiseuille 0131 final fields: %s', runs(i).label),'Visible','on');
    tiledlayout(fig, 2, 2);
    nexttile; imagesc(f.xc, f.yc, f.speed); axis image xy; colorbar; title('speed'); xlabel('x'); ylabel('y');
    nexttile; imagesc(f.xc, f.yc, f.Ux); axis image xy; colorbar; title('Ux'); xlabel('x'); ylabel('y');
    nexttile; imagesc(f.xc, f.yc, f.mass); axis image xy; colorbar; title('cell mass'); xlabel('x'); ylabel('y');
    nexttile; imagesc(f.xc, f.yc, f.N); axis image xy; colorbar; title('cell population'); xlabel('x'); ylabel('y');
    saveas(fig, fullfile(analysisDir, sprintf('poiseuille_0131_final_fields_%s.png', runs(i).label)));
end
end

function suite = validate_von_karman_long_comparison(varargin)
%VALIDATE_VON_KARMAN_LONG_COMPARISON Compare classic vs Q9/virial periodic-cylinder runs.
%
% suite = validate_von_karman_long_comparison()
%
% The diagnostics deliberately mirror the backward-step reliability logic:
% coherent vorticity, total/fluctuating vorticity, low-k content, wake
% population reliability, and immersed-solid/projection leak checks.

p = inputParser;
p.FunctionName = 'validate_von_karman_long_comparison';
addParameter(p, 'runDirs', { ...
    '../runs/von_karman_classic_long_320x64', ...
    '../runs/von_karman_q9_virial_long_320x64'}, @(c) iscell(c) || isstring(c));
addParameter(p, 'labels', {'classic','Q9/virial'}, @(c) iscell(c) || isstring(c));
addParameter(p, 'timeAverageStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'wakeXMinDiameters', 1.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'wakeXMaxMarginDiameters', 1.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'lowKMaxIndex', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'outputDir', '../runs/von_karman_long_comparison_analysis', @(s) ischar(s) || isstring(s));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

runDirs = cellfun(@char, cellstr(string(opt.runDirs)), 'UniformOutput', false);
labels = cellfun(@char, cellstr(string(opt.labels)), 'UniformOutput', false);
if numel(labels) ~= numel(runDirs)
    labels = runDirs;
end

outDir = char(opt.outputDir);
if ~exist(outDir, 'dir'), mkdir(outDir); end

rows = cell(numel(runDirs), 1);
analyses = cell(numel(runDirs), 1);
for i = 1:numel(runDirs)
    analyses{i} = local_analyze_one(runDirs{i}, labels{i}, opt, outDir);
    rows{i} = analyses{i}.row;
end
summary = vertcat(rows{:});
writetable(summary, fullfile(outDir, 'von_karman_long_comparison_summary.csv'));
disp(summary);

suite = struct();
suite.summary = summary;
suite.analyses = analyses;
suite.outputDir = outDir;
suite.options = opt;

if opt.makePlots
    local_plot_suite(summary, outDir);
end
end

function out = local_analyze_one(runDir, label, opt, outDir)
paramsPath = fullfile(runDir, 'params_used.kv');
if ~exist(paramsPath, 'file')
    error('Missing params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsPath);
summaryPath = fullfile(runDir, 'summary_runtime.csv');
if ~exist(summaryPath, 'file')
    error('Missing summary_runtime.csv in %s', runDir);
end
runtime = readtable(summaryPath);
frames = list_smpcd_dumps(runDir);
if isempty(frames)
    error('No .smpcd dumps in %s', runDir);
end

Lx = local_get_num(params, 'Lx');
Ly = local_get_num(params, 'Ly');
Nx = local_get_num(params, 'Nx');
Ny = local_get_num(params, 'Ny');
cx = local_get_first_num(params, {'immersedSolidCx','immersedCircleCx'}, 0.35);
cy = local_get_first_num(params, {'immersedSolidCy','immersedCircleCy'}, 0.20);
R  = local_get_first_num(params, {'immersedSolidR','immersedCircleR'}, 0.04);
D = 2 * R;

nFrames = height(frames);
startIdx = min(nFrames, max(1, floor(opt.timeAverageStartFraction * nFrames) + 1));
selectedIdx = startIdx:round(opt.frameStride):nFrames;
if isempty(selectedIdx), selectedIdx = nFrames; end

omegaSum = zeros(Ny, Nx);
omegaSqSum = zeros(Ny, Nx);
uxSum = zeros(Ny, Nx);
uySum = zeros(Ny, Nx);
NSum = zeros(Ny, Nx);
NSqSum = zeros(Ny, Nx);

for ii = 1:numel(selectedIdx)
    st = read_smpcd_state(frames.fullPath{selectedIdx(ii)});
    fld = bin_smpcd_state(st, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
        'periodicX', true, 'periodicY', true);
    omegaSum = omegaSum + fld.omega;
    omegaSqSum = omegaSqSum + fld.omega.^2;
    uxSum = uxSum + local_nan_to_zero(fld.Ux);
    uySum = uySum + local_nan_to_zero(fld.Uy);
    NSum = NSum + fld.N;
    NSqSum = NSqSum + fld.N.^2;
end
nAvg = numel(selectedIdx);
omegaMean = omegaSum / nAvg;
omegaTotalRmsField = sqrt(max(omegaSqSum / nAvg, 0));
omegaFluctRmsField = sqrt(max(omegaSqSum / nAvg - omegaMean.^2, 0));
UxMean = uxSum / nAvg;
UyMean = uySum / nAvg;
NMean = NSum / nAvg;
NTemporalStd = sqrt(max(NSqSum / nAvg - NMean.^2, 0));

[xcGrid, ycGrid] = meshgrid(((0:Nx-1)+0.5)*Lx/Nx, ((0:Ny-1)+0.5)*Ly/Ny);
solidMask = (xcGrid - cx).^2 + (ycGrid - cy).^2 <= R^2;
wakeMask = xcGrid >= cx + opt.wakeXMinDiameters * D & ...
           xcGrid <= Lx - opt.wakeXMaxMarginDiameters * D & ~solidMask;
if ~any(wakeMask(:))
    wakeMask = ~solidMask;
end

omegaMeanWake = omegaMean(wakeMask);
omegaTotalWake = omegaTotalRmsField(wakeMask);
omegaFluctWake = omegaFluctRmsField(wakeMask);
UxWake = UxMean(wakeMask);
UyWake = UyMean(wakeMask);
NMeanWake = NMean(wakeMask);
NTemporalStdWake = NTemporalStd(wakeMask);

omegaRmsWake = local_rms(omegaMeanWake);
omegaTotalRmsWake = local_rms(omegaTotalWake);
omegaFluctRmsWake = local_rms(omegaFluctWake);
omegaTemporalMeanFractionWake = omegaRmsWake / max(omegaTotalRmsWake, eps);
omegaFluctToMeanRatioWake = omegaFluctRmsWake / max(omegaRmsWake, eps);
omegaMeanLowKFractionWake = local_lowk_fraction(omegaMean, wakeMask, opt.lowKMaxIndex);

NRef = mean(NMean(~solidMask), 'omitnan');
popP05Wake = prctile(NMeanWake, 5);
popMinWake = min(NMeanWake);
popCvWake = std(NMeanWake, 0, 'omitnan') / max(mean(NMeanWake, 'omitnan'), eps);
popP05WakeOverRef = popP05Wake / max(NRef, eps);
popBelow5Wake = mean(NMeanWake < 5, 'omitnan');
popLowHalfRefWake = mean(NMeanWake < 0.5 * NRef, 'omitnan');
popTemporalCvMeanWake = mean(NTemporalStdWake ./ max(NMeanWake, eps), 'omitnan');

late = runtime(max(1, floor(0.5*height(runtime))+1):end, :);
method = local_get_string(params, 'method', 'classic');
q6Leak = local_late_mean(late, 'q6ImmersedSolidLeakProjectedFluxRms');
q9Leak = local_late_mean(late, 'q9ImmersedSolidLeakMassFluxRms');
virialDuThermal = local_late_mean(late, 'virialDuOverThermalRms');

maxInside = local_max_particles_inside_circle(frames, cx, cy, R);

row = table(string(label), string(runDir), string(method), nFrames, nAvg, maxInside, ...
    local_late_mean(late, 'kBTEstimate'), local_late_mean(late, 'meanVx'), local_late_mean(late, 'meanVy'), ...
    NRef, popCvWake, popMinWake, popP05Wake, popP05WakeOverRef, popBelow5Wake, popLowHalfRefWake, popTemporalCvMeanWake, ...
    mean(UxWake, 'omitnan'), local_rms(UyWake), local_rms(hypot(UxWake, UyWake)), ...
    omegaRmsWake, omegaTotalRmsWake, omegaFluctRmsWake, omegaTemporalMeanFractionWake, omegaFluctToMeanRatioWake, omegaMeanLowKFractionWake, ...
    q6Leak, q9Leak, virialDuThermal, ...
    'VariableNames', {'caseLabel','runDir','method','nFrames','nAveragedFrames','maxParticlesInsideCircle', ...
    'kBTMeanLate','meanVxLate','meanVyLate', ...
    'populationReferenceNFluid','populationCvWake','populationMinWake','populationP05Wake','populationP05WakeOverReference','populationBelow5FractionWake','populationLowHalfRefFractionWake','populationTemporalCvMeanWake', ...
    'meanUxWake','uyRmsWake','speedRmsWake', ...
    'omegaRmsWake','omegaTotalRmsWake','omegaFluctRmsWake','omegaTemporalMeanFractionWake','omegaFluctToMeanRatioWake','omegaMeanLowKFractionWake', ...
    'q6ImmersedSolidLeakProjectedFluxRmsLate','q9ImmersedSolidLeakMassFluxRmsLate','virialDuOverThermalRmsLate'});

out = struct();
out.row = row;
out.params = params;
out.runtime = runtime;
out.frames = frames;
out.fields = struct('omegaMean', omegaMean, 'omegaFluctRms', omegaFluctRmsField, ...
    'UxMean', UxMean, 'UyMean', UyMean, 'NMean', NMean, 'NTemporalStd', NTemporalStd, ...
    'wakeMask', wakeMask, 'solidMask', solidMask, 'x', xcGrid, 'y', ycGrid);

prefix = regexprep(label, '[^A-Za-z0-9]+', '_');
writetable(local_field_table(xcGrid, ycGrid, omegaMean, UxMean, UyMean, NMean, wakeMask, solidMask), ...
    fullfile(outDir, ['von_karman_fields_', prefix, '.csv']));
end

function v = local_get_num(params, key)
if isfield(params, key)
    v = str2double(string(params.(key)));
else
    error('Missing parameter %s', key);
end
end

function v = local_get_first_num(params, keys, defaultValue)
v = defaultValue;
for i = 1:numel(keys)
    if isfield(params, keys{i})
        tmp = str2double(string(params.(keys{i})));
        if ~isnan(tmp), v = tmp; return; end
    end
end
end

function s = local_get_string(params, key, defaultValue)
if isfield(params, key), s = char(string(params.(key))); else, s = defaultValue; end
end

function A = local_nan_to_zero(A)
A(~isfinite(A)) = 0;
end

function r = local_rms(x)
x = x(isfinite(x));
if isempty(x), r = NaN; else, r = sqrt(mean(x.^2)); end
end

function m = local_late_mean(T, varName)
if istable(T) && ismember(varName, T.Properties.VariableNames)
    m = mean(T.(varName), 'omitnan');
else
    m = NaN;
end
end

function maxInside = local_max_particles_inside_circle(frames, cx, cy, R)
maxInside = 0;
for k = 1:height(frames)
    st = read_smpcd_state(frames.fullPath{k});
    inside = (double(st.x(:)) - cx).^2 + (double(st.y(:)) - cy).^2 < (R * (1 - 1e-10))^2;
    maxInside = max(maxInside, nnz(inside));
end
end

function frac = local_lowk_fraction(A, mask, kmax)
B = A;
B(~isfinite(B)) = 0;
B(~mask) = 0;
F = fft2(B);
[ny, nx] = size(B);
[kx, ky] = meshgrid(0:nx-1, 0:ny-1);
kx = min(kx, nx-kx);
ky = min(ky, ny-ky);
low = (kx.^2 + ky.^2) <= kmax^2;
E = abs(F).^2;
Etot = sum(E(:));
if Etot <= 0, frac = NaN; else, frac = sum(E(low), 'all') / Etot; end
end

function T = local_field_table(X, Y, Om, Ux, Uy, N, wakeMask, solidMask)
T = table(X(:), Y(:), Om(:), Ux(:), Uy(:), N(:), wakeMask(:), solidMask(:), ...
    'VariableNames', {'x','y','omegaMean','UxMean','UyMean','NMean','wakeMask','solidMask'});
end

function local_plot_suite(summary, outDir)
fig = figure('Name', 'von Karman long comparison metrics');
tiledlayout(2,3);
labels = categorical(summary.caseLabel);
nexttile; bar(labels, summary.omegaRmsWake); ylabel('RMS mean \omega'); title('Coherent wake vorticity'); grid on;
nexttile; bar(labels, summary.omegaFluctToMeanRatioWake); ylabel('fluct / mean'); title('Vorticity fluctuation ratio'); grid on;
nexttile; bar(labels, summary.omegaMeanLowKFractionWake); ylabel('low-k fraction'); title('Large-scale vorticity content'); grid on;
nexttile; bar(labels, summary.populationP05WakeOverReference); ylabel('P05/reference'); title('Wake population lower tail'); grid on;
nexttile; bar(labels, summary.populationBelow5FractionWake); ylabel('fraction'); title('Wake cells N<5'); grid on;
nexttile; bar(labels, summary.q6ImmersedSolidLeakProjectedFluxRmsLate + summary.q9ImmersedSolidLeakMassFluxRmsLate); ylabel('leak RMS'); title('Projection solid leak'); grid on;
exportgraphics(fig, fullfile(outDir, 'von_karman_long_comparison_metrics.png'), 'Resolution', 150);
end

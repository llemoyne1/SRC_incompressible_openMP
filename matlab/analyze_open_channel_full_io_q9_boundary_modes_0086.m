function R = analyze_open_channel_full_io_q9_boundary_modes_0086(varargin)
%ANALYZE_OPEN_CHANNEL_FULL_IO_Q9_BOUNDARY_MODES_0086
% Runtime and dump-based diagnostics for the 0086 full-IO/slip Q9 boundary-mode sweep.
%
% This analysis combines:
%   - runtime summary metrics, as in 0085;
%   - column-wise density diagnostics from .smpcd dumps, to locate vertical
%     density bands and test whether they track the Q9 open-boundary exclusion
%     interface.
%
% Example:
%   R = analyze_open_channel_full_io_q9_boundary_modes_0086( ...
%       'root','..', ...
%       'runRoot','runs/open_channel_full_io_q9_boundary_modes_0086_g30', ...
%       'caseGlob','openchan_*', ...
%       'makePlots',true, ...
%       'showFigures',true, ...
%       'closeFigures',false);

opts = local_parse_options(varargin{:});
root = char(opts.root);
runRoot = char(opts.runRoot);
runPath = runRoot;
if ~exist(runPath, 'dir')
    runPath = fullfile(root, runRoot);
end
if ~exist(runPath, 'dir')
    error('Cannot find runRoot: %s', runRoot);
end

outDir = fullfile(runPath, 'analysis_0086_q9_boundary_modes');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

caseDirs = dir(fullfile(runPath, char(opts.caseGlob)));
caseDirs = caseDirs([caseDirs.isdir]);
caseDirs = caseDirs(~ismember({caseDirs.name}, {'.','..'}));
if isempty(caseDirs)
    error('No case directories matching %s in %s', char(opts.caseGlob), runPath);
end

summaryRows = table();
allRuntime = table();
allColumnRows = table();
columnSummaryRows = table();

for i = 1:numel(caseDirs)
    caseName = caseDirs(i).name;
    casePath = fullfile(caseDirs(i).folder, caseDirs(i).name);
    runtimeFile = fullfile(casePath, 'summary_runtime.csv');
    params = local_read_params(casePath);

    if exist(runtimeFile, 'file')
        T = readtable(runtimeFile, 'VariableNamingRule','preserve');
        if ~isempty(T)
            T.caseLabel = repmat(string(caseName), height(T), 1);
            allRuntime = [allRuntime; T]; %#ok<AGROW>
            summaryRows = [summaryRows; local_summarize_runtime_case(caseName, T, params, opts.lateFraction)]; %#ok<AGROW>
        end
    else
        warning('Skipping runtime summary for %s: missing summary_runtime.csv', caseName);
    end

    try
        C = local_column_timeseries(caseName, casePath, params, opts);
    catch ME
        warning('Column diagnostics failed for %s: %s', caseName, ME.message);
        C = table();
    end
    if ~isempty(C)
        writetable(C, fullfile(outDir, sprintf('column_diagnostics_%s.csv', caseName)));
        allColumnRows = [allColumnRows; C]; %#ok<AGROW>
        columnSummaryRows = [columnSummaryRows; local_summarize_columns(caseName, C, params, opts.lateFraction)]; %#ok<AGROW>
    end
end

if ~isempty(summaryRows)
    writetable(summaryRows, fullfile(outDir, 'open_channel_full_io_q9_boundary_modes_runtime_summary_0086.csv'));
end
if ~isempty(allRuntime)
    writetable(allRuntime, fullfile(outDir, 'open_channel_full_io_q9_boundary_modes_runtime_all_cases_0086.csv'));
end
if ~isempty(allColumnRows)
    writetable(allColumnRows, fullfile(outDir, 'open_channel_full_io_q9_boundary_modes_column_timeseries_0086.csv'));
end
if ~isempty(columnSummaryRows)
    writetable(columnSummaryRows, fullfile(outDir, 'open_channel_full_io_q9_boundary_modes_column_summary_0086.csv'));
end

if opts.makePlots
    if ~isempty(allRuntime)
        local_plot_metric(allRuntime, outDir, 'Np', opts);
        local_plot_metric(allRuntime, outDir, 'meanN', opts);
        local_plot_metric(allRuntime, outDir, 'stdN', opts);
        local_plot_metric(allRuntime, outDir, 'maxN', opts);
        local_plot_metric(allRuntime, outDir, 'kBTEstimate', opts);
        local_plot_metric(allRuntime, outDir, 'maxParticleSpeed', opts);
        local_plot_metric(allRuntime, outDir, 'q9CorrectionVelocityMaxAbs', opts);
        local_plot_metric(allRuntime, outDir, 'q9CorrectionVelocityRawMaxAbs', opts);
        local_plot_metric(allRuntime, outDir, 'q9VelocityLimitedCells', opts);
        local_plot_metric(allRuntime, outDir, 'q9LowMassSuppressedCells', opts);
        local_plot_metric(allRuntime, outDir, 'q9LowMassRampedCells', opts);
        local_plot_metric(allRuntime, outDir, 'q9OpenBoundaryExcludedCells', opts);
        local_plot_metric(allRuntime, outDir, 'virialOpenBoundaryExcludedCells', opts);
    end
    if ~isempty(allColumnRows)
        local_plot_metric(allColumnRows, outDir, 'maxColumnMeanN', opts, 'column');
        local_plot_metric(allColumnRows, outDir, 'maxColumnMeanNRelToGamma', opts, 'column');
        local_plot_metric(allColumnRows, outDir, 'xOfMaxColumnMeanN', opts, 'column');
        local_plot_metric(allColumnRows, outDir, 'rightBandMeanN', opts, 'column');
        local_plot_metric(allColumnRows, outDir, 'rightBandMaxN', opts, 'column');
        local_plot_metric(allColumnRows, outDir, 'rightInterfaceActiveMeanN', opts, 'column');
        local_plot_metric(allColumnRows, outDir, 'rightInterfaceExcludedMeanN', opts, 'column');
        local_plot_metric(allColumnRows, outDir, 'rightInterfaceJumpN', opts, 'column');
    end
end

R = struct();
R.runPath = runPath;
R.outDir = outDir;
R.runtimeSummary = summaryRows;
R.runtime = allRuntime;
R.columnSummary = columnSummaryRows;
R.columnTimeseries = allColumnRows;

fprintf('\n0086 Q9 boundary-mode analysis written to:\n  %s\n', outDir);
if ~isempty(summaryRows)
    disp(summaryRows(:, local_display_columns(summaryRows)));
end
if ~isempty(columnSummaryRows)
    disp(columnSummaryRows(:, local_display_columns_columns(columnSummaryRows)));
end
end

function opts = local_parse_options(varargin)
opts = struct();
opts.root = '..';
opts.runRoot = 'runs/open_channel_full_io_q9_boundary_modes_0086_g30';
opts.caseGlob = 'openchan_*';
opts.lateFraction = 0.50;
opts.frameStride = 1;
opts.rightBandCells = NaN;
opts.makePlots = true;
opts.showFigures = true;
opts.closeFigures = false;
opts.figureVisible = 'on';

if mod(numel(varargin),2) ~= 0
    error('Options must be name/value pairs.');
end
for k = 1:2:numel(varargin)
    name = lower(char(varargin{k}));
    value = varargin{k+1};
    switch name
        case 'root'
            opts.root = value;
        case 'runroot'
            opts.runRoot = value;
        case 'caseglob'
            opts.caseGlob = value;
        case 'latefraction'
            opts.lateFraction = value;
        case 'framestride'
            opts.frameStride = value;
        case 'rightbandcells'
            opts.rightBandCells = value;
        case 'makeplots'
            opts.makePlots = logical(value);
        case 'showfigures'
            opts.showFigures = logical(value);
        case 'closefigures'
            opts.closeFigures = logical(value);
        otherwise
            error('Unknown option: %s', name);
    end
end
if opts.showFigures
    opts.figureVisible = 'on';
else
    opts.figureVisible = 'off';
end
end

function params = local_read_params(casePath)
params = containers.Map('KeyType','char', 'ValueType','char');
files = {fullfile(casePath, 'params_used.kv'), fullfile(casePath, 'params.kv')};
for f = 1:numel(files)
    if exist(files{f}, 'file')
        params = local_parse_kv_file(files{f});
        return;
    end
end
end

function params = local_parse_kv_file(path)
params = containers.Map('KeyType','char', 'ValueType','char');
fid = fopen(path, 'r');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    line = strtrim(line);
    if isempty(line) || startsWith(line, '#')
        continue;
    end
    eq = strfind(line, '=');
    if isempty(eq)
        continue;
    end
    key = strtrim(line(1:eq(1)-1));
    val = strtrim(line(eq(1)+1:end));
    cmt = strfind(val, '#');
    if ~isempty(cmt)
        val = strtrim(val(1:cmt(1)-1));
    end
    params(key) = val;
end
end

function row = local_summarize_runtime_case(caseName, T, params, lateFraction)
if ismember('time', T.Properties.VariableNames)
    t = T.time;
else
    t = (1:height(T))';
end
lateStart = min(t) + (max(t)-min(t)) * (1 - lateFraction);
late = t >= lateStart;
if ~any(late)
    late = true(size(t));
end

row = table();
row.caseLabel = string(caseName);
row.method = string(local_param(params, 'method', 'unknown'));
row.q9OpenBoundaryExclusionCellsParam = local_param_num(params, 'q9OpenBoundaryExclusionCells', NaN);
row.virialOpenBoundaryExclusionCellsParam = local_param_num(params, 'virialOpenBoundaryExclusionCells', NaN);
row.q9DensityRelaxationBetaParam = local_param_num(params, 'q9DensityRelaxationBeta', NaN);
row.nStepsParam = local_param_num(params, 'nSteps', NaN);
row.tFinal = t(end);
row.NpInitial = local_first(T, 'Np');
row.NpFinal = local_last(T, 'Np');
row.NpDelta = row.NpFinal - row.NpInitial;
row.NpDeltaRel = row.NpDelta / max(row.NpInitial, eps);
row.NpSlopeLate = local_slope(t(late), local_col(T, 'Np', late));
row.meanNFinal = local_last(T, 'meanN');
row.meanNLateMean = local_mean(T, 'meanN', late);
row.stdNFinal = local_last(T, 'stdN');
row.stdNLateMean = local_mean(T, 'stdN', late);
row.stdNSlopeLate = local_slope(t(late), local_col(T, 'stdN', late));
row.maxNFinal = local_last(T, 'maxN');
row.maxNMaxAll = local_max(T, 'maxN');
row.kBTFinal = local_last(T, 'kBTEstimate');
row.kBTMaxAll = local_max(T, 'kBTEstimate');
row.maxParticleSpeedMaxAll = local_max(T, 'maxParticleSpeed');
row.meanVxLateMean = local_mean(T, 'meanVx', late);
row.meanVyLateMean = local_mean(T, 'meanVy', late);
row.q6AppliedFinal = local_last(T, 'q6Applied');
row.q9AppliedFinal = local_last(T, 'q9Applied');
row.virialKickAppliedFinal = local_last(T, 'virialKickApplied');
row.q9OpenBoundaryExcludedCellsFinal = local_last(T, 'q9OpenBoundaryExcludedCells');
row.virialOpenBoundaryExcludedCellsFinal = local_last(T, 'virialOpenBoundaryExcludedCells');
row.q9CorrectionVelocityMaxAbsMaxAll = local_max(T, 'q9CorrectionVelocityMaxAbs');
row.q9CorrectionVelocityRawMaxAbsMaxAll = local_max(T, 'q9CorrectionVelocityRawMaxAbs');
row.q9VelocityLimitedCellsLateMean = local_mean(T, 'q9VelocityLimitedCells', late);
row.q9LowMassSuppressedLateMean = local_mean(T, 'q9LowMassSuppressedCells', late);
row.q9LowMassRampedLateMean = local_mean(T, 'q9LowMassRampedCells', late);
row.q9DensityStdRatioLateMean = local_mean(T, 'q9DensityStdRatioEstimate', late);
row.virialRhoDefectRelRmsLateMean = local_mean(T, 'virialRhoDefectRelRms', late);
end

function rows = local_column_timeseries(caseName, casePath, params, opts)
runtimePath = fullfile(casePath, 'summary_runtime.csv');
if ~exist(runtimePath, 'file')
    rows = table();
    return;
end
frames = list_smpcd_dumps(casePath, 'summaryFile', runtimePath);
if isempty(frames)
    rows = table();
    return;
end
idxList = 1:round(opts.frameStride):height(frames);
if idxList(end) ~= height(frames)
    idxList = [idxList height(frames)]; %#ok<AGROW>
end

geom.Lx = local_param_num(params, 'Lx', 1.0);
geom.Ly = local_param_num(params, 'Ly', 1.0);
geom.Nx = round(local_param_num(params, 'Nx', 32));
geom.Ny = round(local_param_num(params, 'Ny', 32));
geom.dx = geom.Lx / geom.Nx;
geom.dy = geom.Ly / geom.Ny;
geom.xc = ((0:geom.Nx-1) + 0.5) * geom.dx;

gamma = local_param_num(params, 'inletTargetOccupancy', local_param_num(params, 'q9ReferenceGamma', NaN));
if ~isfinite(gamma) || gamma <= 0
    gamma = NaN;
end
q9Excl = max(0, round(local_param_num(params, 'q9OpenBoundaryExclusionCells', 0)));
reservoirCells = max(1, round(local_param_num(params, 'inletReservoirCells', 3)));
rightBandCells = round(opts.rightBandCells);
if ~isfinite(rightBandCells) || rightBandCells <= 0
    rightBandCells = max(1, max(q9Excl, reservoirCells));
end
rightBandCells = min(geom.Nx, rightBandCells);

rows = table();
for kk = 1:numel(idxList)
    idx = idxList(kk);
    state = read_smpcd_state(frames.fullPath{idx});
    fields = bin_smpcd_state(state, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', geom.Nx, 'Ny', geom.Ny, ...
        'periodicX', false, 'periodicY', false);
    if isfield(fields, 'N')
        N = fields.N;
    else
        N = zeros(geom.Ny, geom.Nx);
    end
    rows = [rows; local_one_column_row(caseName, idx, frames.time(idx), N, geom, gamma, q9Excl, rightBandCells)]; %#ok<AGROW>
end
end

function row = local_one_column_row(caseName, frameIndex, t, N, geom, gamma, q9Excl, rightBandCells)
colMass = sum(N, 1, 'omitnan');
colMeanN = mean(N, 1, 'omitnan');
colMaxN = max(N, [], 1, 'omitnan');
[mc, imax] = max(colMeanN);
[mx, imaxMax] = max(colMaxN);
[minc, imin] = min(colMeanN);

rightIx = max(1, geom.Nx-rightBandCells+1):geom.Nx;
rightBandMeanN = mean(N(:, rightIx), 'all', 'omitnan');
rightBandMaxN = max(N(:, rightIx), [], 'all', 'omitnan');
rightBandMass = sum(N(:, rightIx), 'all', 'omitnan');

if q9Excl > 0
    activeIx = max(1, geom.Nx - q9Excl);
    excludedIx = min(geom.Nx, geom.Nx - q9Excl + 1);
else
    activeIx = geom.Nx;
    excludedIx = geom.Nx;
end
rightInterfaceX = geom.Lx - q9Excl * geom.dx;
rightInterfaceActiveMeanN = mean(N(:, activeIx), 'omitnan');
rightInterfaceExcludedMeanN = mean(N(:, excludedIx), 'omitnan');
rightInterfaceJumpN = rightInterfaceExcludedMeanN - rightInterfaceActiveMeanN;

if isfinite(gamma) && gamma > 0
    maxColumnMeanNRelToGamma = mc / gamma;
    rightBandMeanNRelToGamma = rightBandMeanN / gamma;
else
    maxColumnMeanNRelToGamma = NaN;
    rightBandMeanNRelToGamma = NaN;
end

row = table(string(caseName), frameIndex, t, gamma, q9Excl, rightInterfaceX, ...
    mc, maxColumnMeanNRelToGamma, geom.xc(imax), mx, geom.xc(imaxMax), minc, geom.xc(imin), ...
    rightBandCells, rightBandMass, rightBandMeanN, rightBandMeanNRelToGamma, rightBandMaxN, ...
    activeIx, excludedIx, rightInterfaceActiveMeanN, rightInterfaceExcludedMeanN, rightInterfaceJumpN, ...
    'VariableNames', {'caseLabel','frameIndex','time','gamma','q9OpenBoundaryExclusionCells','rightInterfaceX', ...
    'maxColumnMeanN','maxColumnMeanNRelToGamma','xOfMaxColumnMeanN','maxColumnMaxN','xOfMaxColumnMaxN','minColumnMeanN','xOfMinColumnMeanN', ...
    'rightBandCells','rightBandMass','rightBandMeanN','rightBandMeanNRelToGamma','rightBandMaxN', ...
    'rightInterfaceActiveIx','rightInterfaceExcludedIx','rightInterfaceActiveMeanN','rightInterfaceExcludedMeanN','rightInterfaceJumpN'});
end

function summary = local_summarize_columns(caseName, C, params, lateFraction)
if isempty(C)
    summary = table();
    return;
end
t = C.time;
lateStart = min(t) + (max(t)-min(t)) * (1 - lateFraction);
late = t >= lateStart;
if ~any(late)
    late = true(size(t));
end
summary = table();
summary.caseLabel = string(caseName);
summary.method = string(local_param(params, 'method', 'unknown'));
summary.q9OpenBoundaryExclusionCellsParam = local_param_num(params, 'q9OpenBoundaryExclusionCells', NaN);
summary.q9DensityRelaxationBetaParam = local_param_num(params, 'q9DensityRelaxationBeta', NaN);
summary.gamma = C.gamma(end);
summary.tFinal = C.time(end);
summary.maxColumnMeanNLateMean = mean(C.maxColumnMeanN(late), 'omitnan');
summary.maxColumnMeanNMaxAll = max(C.maxColumnMeanN, [], 'omitnan');
summary.maxColumnMeanNRelToGammaLateMean = mean(C.maxColumnMeanNRelToGamma(late), 'omitnan');
summary.xOfMaxColumnMeanNLateMean = mean(C.xOfMaxColumnMeanN(late), 'omitnan');
summary.xOfMaxColumnMeanNFinal = C.xOfMaxColumnMeanN(end);
summary.rightBandMeanNLateMean = mean(C.rightBandMeanN(late), 'omitnan');
summary.rightBandMeanNRelToGammaLateMean = mean(C.rightBandMeanNRelToGamma(late), 'omitnan');
summary.rightBandMaxNMaxAll = max(C.rightBandMaxN, [], 'omitnan');
summary.rightInterfaceActiveMeanNLateMean = mean(C.rightInterfaceActiveMeanN(late), 'omitnan');
summary.rightInterfaceExcludedMeanNLateMean = mean(C.rightInterfaceExcludedMeanN(late), 'omitnan');
summary.rightInterfaceJumpNLateMean = mean(C.rightInterfaceJumpN(late), 'omitnan');
summary.rightInterfaceJumpNMaxAbsAll = max(abs(C.rightInterfaceJumpN), [], 'omitnan');
end

function v = local_param(params, key, defaultValue)
if isa(params, 'containers.Map') && isKey(params, key)
    v = params(key);
else
    v = defaultValue;
end
end

function v = local_param_num(params, key, defaultValue)
raw = local_param(params, key, '');
if isempty(raw)
    v = defaultValue;
    return;
end
v = str2double(raw);
if ~isfinite(v)
    v = defaultValue;
end
end

function v = local_col(T, name, mask)
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    v = x(mask);
else
    v = NaN(nnz(mask),1);
end
end

function v = local_first(T, name)
if ismember(name, T.Properties.VariableNames), v = T.(name)(1); else, v = NaN; end
end
function v = local_last(T, name)
if ismember(name, T.Properties.VariableNames), v = T.(name)(end); else, v = NaN; end
end
function v = local_mean(T, name, mask)
if ismember(name, T.Properties.VariableNames), v = mean(T.(name)(mask), 'omitnan'); else, v = NaN; end
end
function v = local_max(T, name)
if ismember(name, T.Properties.VariableNames), v = max(T.(name), [], 'omitnan'); else, v = NaN; end
end
function m = local_slope(t, y)
t = t(:); y = y(:);
ok = isfinite(t) & isfinite(y);
if nnz(ok) < 2
    m = NaN;
    return;
end
p = polyfit(t(ok), y(ok), 1);
m = p(1);
end

function local_plot_metric(T, outDir, metric, opts, prefix)
if nargin < 5
    prefix = 'runtime';
end
if isempty(T) || ~ismember(metric, T.Properties.VariableNames) || ~ismember('time', T.Properties.VariableNames)
    return;
end
fig = figure('Visible', opts.figureVisible);
hold on;
cases = unique(T.caseLabel, 'stable');
for i = 1:numel(cases)
    rows = T.caseLabel == cases(i);
    plot(T.time(rows), T.(metric)(rows), '-o', 'DisplayName', char(cases(i)));
end
hold off;
grid on;
xlabel('time');
ylabel(metric, 'Interpreter','none');
title(sprintf('0086 %s: %s', prefix, metric), 'Interpreter','none');
legend('Interpreter','none', 'Location','best');
saveas(fig, fullfile(outDir, sprintf('%s_%s.png', prefix, metric)));
if opts.closeFigures
    close(fig);
end
end

function cols = local_display_columns(T)
wanted = {'caseLabel','method','q9OpenBoundaryExclusionCellsParam','q9DensityRelaxationBetaParam', ...
    'tFinal','NpDeltaRel','stdNFinal','maxNFinal','kBTMaxAll','q9VelocityLimitedCellsLateMean','q9DensityStdRatioLateMean'};
cols = wanted(ismember(wanted, T.Properties.VariableNames));
end

function cols = local_display_columns_columns(T)
wanted = {'caseLabel','method','q9OpenBoundaryExclusionCellsParam','q9DensityRelaxationBetaParam', ...
    'maxColumnMeanNRelToGammaLateMean','xOfMaxColumnMeanNFinal','rightBandMeanNRelToGammaLateMean','rightInterfaceJumpNLateMean'};
cols = wanted(ismember(wanted, T.Properties.VariableNames));
end

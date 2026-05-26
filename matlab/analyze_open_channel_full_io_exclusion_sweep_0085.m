function R = analyze_open_channel_full_io_exclusion_sweep_0085(varargin)
%ANALYZE_OPEN_CHANNEL_FULL_IO_EXCLUSION_SWEEP_0085
% Compare the 0085 full-inlet/full-outlet slip-channel exclusion sweep.
%
% The diagnostic is intentionally based on runtime summaries only.  It is meant
% to answer whether the density/velocity defect seen near the outlet follows the
% Q9/virial open-boundary exclusion layer.
%
% Example:
%   R = analyze_open_channel_full_io_exclusion_sweep_0085( ...
%       'root','..', ...
%       'runRoot','runs/open_channel_full_io_exclusion_sweep_0085', ...
%       'caseGlob','openchan_*', ...
%       'makePlots',true, ...
%       'showFigures',true, ...
%       'closeFigures',false);

opts = local_parse_options(varargin{:});
root = char(opts.root);
runRoot = char(opts.runRoot);
runPath = fullfile(root, runRoot);
outDir = fullfile(runPath, 'analysis_0085_exclusion_sweep');
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

for i = 1:numel(caseDirs)
    caseName = caseDirs(i).name;
    casePath = fullfile(runPath, caseName);
    runtimeFile = fullfile(casePath, 'summary_runtime.csv');
    if ~exist(runtimeFile, 'file')
        warning('Skipping %s: no summary_runtime.csv', caseName);
        continue;
    end

    T = readtable(runtimeFile, 'VariableNamingRule','preserve');
    if isempty(T)
        warning('Skipping %s: empty runtime summary', caseName);
        continue;
    end

    T.caseLabel = repmat(string(caseName), height(T), 1);
    allRuntime = [allRuntime; T]; %#ok<AGROW>

    params = local_read_params(casePath);
    row = local_summarize_case(caseName, T, params, opts.lateFraction);
    summaryRows = [summaryRows; row]; %#ok<AGROW>
end

if isempty(summaryRows)
    error('No usable runtime summaries found in %s', runPath);
end

writetable(summaryRows, fullfile(outDir, 'open_channel_full_io_exclusion_sweep_summary_0085.csv'));
writetable(allRuntime, fullfile(outDir, 'open_channel_full_io_exclusion_sweep_runtime_all_cases_0085.csv'));

if opts.makePlots
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
    local_plot_metric(allRuntime, outDir, 'virialRhoDefectRelRms', opts);
end

R = struct();
R.runPath = runPath;
R.outDir = outDir;
R.summary = summaryRows;
R.runtime = allRuntime;

fprintf('\n0085 exclusion sweep summary written to:\n  %s\n', outDir);
disp(summaryRows(:, local_display_columns(summaryRows)));
end

function opts = local_parse_options(varargin)
opts = struct();
opts.root = '..';
opts.runRoot = 'runs/open_channel_full_io_exclusion_sweep_0085';
opts.caseGlob = 'openchan_*';
opts.lateFraction = 0.50;
opts.makePlots = true;
opts.showFigures = true;
opts.closeFigures = false;
opts.figureVisible = 'on';

if mod(numel(varargin),2) ~= 0
    error('Options must be name/value pairs.');
end
for k = 1:2:numel(varargin)
    name = char(varargin{k});
    value = varargin{k+1};
    switch lower(name)
        case 'root'
            opts.root = value;
        case 'runroot'
            opts.runRoot = value;
        case 'caseglob'
            opts.caseGlob = value;
        case 'latefraction'
            opts.lateFraction = value;
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

function row = local_summarize_case(caseName, T, params, lateFraction)
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
row.bcBottom = string(local_param(params, 'bcBottom', ''));
row.bcTop = string(local_param(params, 'bcTop', ''));
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

function v = local_param(params, key, defaultValue)
if isa(params, 'containers.Map') && isKey(params, key)
    v = params(key);
else
    v = defaultValue;
end
end

function v = local_param_num(params, key, defaultValue)
raw = local_param(params, key, '');
v = str2double(raw);
if isnan(v)
    v = defaultValue;
end
end

function v = local_col(T, name, mask)
if nargin < 3
    mask = true(height(T),1);
end
if ismember(name, T.Properties.VariableNames)
    v = T.(name)(mask);
else
    v = nan(sum(mask),1);
end
end

function v = local_first(T, name)
c = local_col(T, name);
if isempty(c)
    v = NaN;
else
    v = c(1);
end
end

function v = local_last(T, name)
c = local_col(T, name);
if isempty(c)
    v = NaN;
else
    v = c(end);
end
end

function v = local_mean(T, name, mask)
c = local_col(T, name, mask);
v = mean(c, 'omitnan');
end

function v = local_max(T, name)
c = local_col(T, name);
v = max(c, [], 'omitnan');
end

function m = local_slope(x, y)
valid = isfinite(x) & isfinite(y);
if nnz(valid) < 2
    m = NaN;
    return;
end
p = polyfit(x(valid), y(valid), 1);
m = p(1);
end

function cols = local_display_columns(S)
preferred = {'caseLabel','method','q9OpenBoundaryExclusionCellsParam', ...
    'virialOpenBoundaryExclusionCellsParam','NpDeltaRel','NpSlopeLate', ...
    'stdNLateMean','maxNMaxAll','kBTMaxAll', ...
    'q9CorrectionVelocityMaxAbsMaxAll','q9VelocityLimitedCellsLateMean'};
cols = preferred(ismember(preferred, S.Properties.VariableNames));
end

function local_plot_metric(T, outDir, metric, opts)
if ~ismember(metric, T.Properties.VariableNames)
    return;
end
if ~ismember('caseLabel', T.Properties.VariableNames) || ~ismember('time', T.Properties.VariableNames)
    return;
end
fig = figure('Visible', opts.figureVisible, 'Name', ['0085 ' metric]);
hold on;
cases = unique(string(T.caseLabel), 'stable');
for i = 1:numel(cases)
    m = string(T.caseLabel) == cases(i);
    plot(T.time(m), T.(metric)(m), '-o', 'DisplayName', char(cases(i)));
end
hold off;
grid on;
xlabel('time');
ylabel(metric, 'Interpreter','none');
title(['0085 exclusion sweep: ' metric], 'Interpreter','none');
legend('Location','best', 'Interpreter','none');
set(fig, 'Color','w');
try
    exportgraphics(fig, fullfile(outDir, ['runtime_' metric '.png']), 'Resolution', 150);
catch
    saveas(fig, fullfile(outDir, ['runtime_' metric '.png']));
end
if opts.closeFigures
    close(fig);
end
end

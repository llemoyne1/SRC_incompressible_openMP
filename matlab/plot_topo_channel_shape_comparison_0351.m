function S = plot_topo_channel_shape_comparison_0351(summaryCsv, varargin)
%PLOT_TOPO_CHANNEL_SHAPE_COMPARISON_0351 Plot 0349 shape-comparison stats.
%
% S = plot_topo_channel_shape_comparison_0351(summaryCsv, 'OutputDir', outDir)
%
% Input summary columns:
%   shape, chiFile, benchmarkCsv, windowStatsCsv
%
% 0351b: make CSV import/path handling more robust for interactive MATLAB runs
% launched either from repository root or from the matlab/ directory.

p = inputParser;
p.addRequired('summaryCsv', @(x) ischar(x) || isstring(x));
p.addParameter('OutputDir', '', @(x) ischar(x) || isstring(x));
p.addParameter('ShowFigures', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('Prefix', 'channel_shapes_0351', @(x) ischar(x) || isstring(x));
p.addParameter('SavePng', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('SavePdf', true, @(x) islogical(x) || isnumeric(x));
p.parse(summaryCsv, varargin{:});
opt = p.Results;

summaryCsv = char(opt.summaryCsv);
summaryCsvResolved = local_resolve_existing_path(summaryCsv, pwd, pwd);
if isempty(summaryCsvResolved)
    error('plot_topo_channel_shape_comparison_0351:MissingFile', 'Missing summary CSV: %s', summaryCsv);
end

summary = local_read_csv(summaryCsvResolved);
statsCol = local_find_column(summary, 'windowStatsCsv');
shapeCol = local_find_column(summary, 'shape');
if isempty(statsCol)
    names = strjoin(summary.Properties.VariableNames, ', ');
    error('plot_topo_channel_shape_comparison_0351:MissingColumn', ...
        'Missing windowStatsCsv in %s. Detected columns: %s', summaryCsvResolved, names);
end
if isempty(shapeCol)
    names = strjoin(summary.Properties.VariableNames, ', ');
    error('plot_topo_channel_shape_comparison_0351:MissingColumn', ...
        'Missing shape in %s. Detected columns: %s', summaryCsvResolved, names);
end

summaryDir = fileparts(summaryCsvResolved);
repoRoot = local_infer_repo_root_from_summary(summaryDir);

rows = cell(height(summary), 1);
for i = 1:height(summary)
    statsPath0 = local_table_string(summary, statsCol, i);
    statsPath = local_resolve_existing_path(statsPath0, pwd, repoRoot);
    if isempty(statsPath)
        statsPath = local_resolve_existing_path(statsPath0, summaryDir, repoRoot);
    end
    if isempty(statsPath)
        error('plot_topo_channel_shape_comparison_0351:MissingStats', ...
              'Missing stats CSV: %s. Tried cwd=%s and repoRoot=%s', statsPath0, pwd, repoRoot);
    end
    st = local_read_csv(statsPath);
    if height(st) < 1
        error('plot_topo_channel_shape_comparison_0351:EmptyStats', 'Empty stats CSV: %s', statsPath);
    end
    rows{i} = st(1, :);
end

shape = strings(height(summary), 1);
for i = 1:height(summary)
    shape(i) = string(local_table_string(summary, shapeCol, i));
end

S = table;
S.shape = shape;
S.dragProxy_mean = local_extract(rows, 'dragProxy_mean');
S.dragProxy_std = local_extract(rows, 'dragProxy_std');
S.liftProxy_mean = local_extract(rows, 'liftProxy_mean');
S.liftProxy_std = local_extract(rows, 'liftProxy_std');
S.darcyPower_mean = local_extract(rows, 'darcyPower_mean');
S.darcyPower_std = local_extract(rows, 'darcyPower_std');
S.solidLeakOverSpeed_mean = local_extract(rows, 'solidLeakOverSpeed_mean');
S.meanChi_mean = local_extract(rows, 'meanChi_mean');
S.meanAlpha_mean = local_extract(rows, 'meanAlpha_mean');

if strlength(string(opt.OutputDir)) == 0
    outDir = fullfile(fileparts(summaryCsvResolved), 'plots_0351');
else
    outDir = char(opt.OutputDir);
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

prefix = char(opt.Prefix);
visibleMode = local_visible_mode(opt.ShowFigures);

outCsv = fullfile(outDir, [prefix '_compact.csv']);
writetable(S, outCsv);

fig = figure('Name', 'Shape drag proxy comparison', 'Visible', visibleMode);
bar(categorical(S.shape), S.dragProxy_mean);
grid on;
ylabel('dragProxy mean');
title('Channel shape comparison: drag proxy');
local_save_figure(fig, outDir, [prefix '_drag_proxy'], opt.SavePng, opt.SavePdf);

fig = figure('Name', 'Shape Darcy power comparison', 'Visible', visibleMode);
bar(categorical(S.shape), S.darcyPower_mean);
grid on;
ylabel('darcyPower mean');
title('Channel shape comparison: Darcy power');
local_save_figure(fig, outDir, [prefix '_darcy_power'], opt.SavePng, opt.SavePdf);

fig = figure('Name', 'Shape lift proxy comparison', 'Visible', visibleMode);
bar(categorical(S.shape), S.liftProxy_mean);
grid on;
ylabel('liftProxy mean');
title('Channel shape comparison: lift proxy');
local_save_figure(fig, outDir, [prefix '_lift_proxy'], opt.SavePng, opt.SavePdf);

fprintf('[0351-matlab] summaryCsv=%s\n', summaryCsvResolved);
fprintf('[0351-matlab] outputDir=%s\n', outDir);
fprintf('[0351-matlab] compactCsv=%s\n', outCsv);
end

function T = local_read_csv(path)
try
    opts = detectImportOptions(path, 'FileType', 'text', 'Delimiter', ',');
    try
        opts.VariableNamingRule = 'preserve';
    catch
    end
    T = readtable(path, opts);
catch
    try
        T = readtable(path, 'FileType', 'text', 'Delimiter', ',', ...
                      'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
    catch
        T = readtable(path, 'FileType', 'text', 'Delimiter', ',', ...
                      'ReadVariableNames', true);
    end
end
end

function col = local_find_column(T, wanted)
names = T.Properties.VariableNames;
col = '';
idx = find(strcmp(names, wanted), 1);
if isempty(idx)
    idx = find(strcmpi(names, wanted), 1);
end
if isempty(idx)
    cw = regexprep(lower(wanted), '[^a-z0-9]', '');
    for k = 1:numel(names)
        ck = regexprep(lower(names{k}), '[^a-z0-9]', '');
        if strcmp(ck, cw)
            idx = k;
            break;
        end
    end
end
if ~isempty(idx)
    col = names{idx};
end
end

function s = local_table_string(T, col, i)
v = T.(col);
if iscell(v)
    s = char(v{i});
elseif isstring(v)
    s = char(v(i));
elseif iscategorical(v)
    s = char(string(v(i)));
else
    s = char(string(v(i)));
end
end

function repoRoot = local_infer_repo_root_from_summary(summaryDir)
% Expected summaryDir is <repo>/runs/topo_darcy_channel_shapes_0349.
[parent1, last1] = fileparts(summaryDir);
[parent2, last2] = fileparts(parent1);
if strcmp(last2, 'runs') || strcmp(last2, 'run')
    repoRoot = parent2;
elseif strcmp(last1, 'runs') || strcmp(last1, 'run')
    repoRoot = parent1;
else
    repoRoot = pwd;
end
end

function resolved = local_resolve_existing_path(path0, baseDir, repoRoot)
path0 = char(path0);
candidates = {};
if isabsolute_path(path0)
    candidates{end+1} = path0; %#ok<AGROW>
else
    candidates{end+1} = path0; %#ok<AGROW>
    candidates{end+1} = fullfile(baseDir, path0); %#ok<AGROW>
    candidates{end+1} = fullfile(repoRoot, path0); %#ok<AGROW>
end
resolved = '';
for i = 1:numel(candidates)
    c = candidates{i};
    if isfile(c)
        resolved = local_canonical(c);
        return;
    end
end
end

function tf = isabsolute_path(p)
if ispc
    tf = numel(p) >= 2 && p(2) == ':';
else
    tf = ~isempty(p) && p(1) == filesep;
end
end

function p = local_canonical(p0)
[ok, info] = fileattrib(p0);
if ok
    p = info.Name;
else
    p = p0;
end
end

function visibleMode = local_visible_mode(showFigures)
if logical(showFigures)
    visibleMode = 'on';
else
    visibleMode = 'off';
end
end

function v = local_extract(rows, name)
v = nan(numel(rows), 1);
for i = 1:numel(rows)
    T = rows{i};
    col = local_find_column(T, name);
    if ~isempty(col)
        val = T.(col);
        v(i) = val(1);
    end
end
end

function local_save_figure(fig, outDir, basename, savePng, savePdf)
if logical(savePng)
    png = fullfile(outDir, [basename '.png']);
    saveas(fig, png);
    fprintf('[0351-matlab] wrote %s\n', png);
end
if logical(savePdf)
    pdf = fullfile(outDir, [basename '.pdf']);
    set(fig, 'PaperPositionMode', 'auto');
    try
        print(fig, pdf, '-dpdf', '-bestfit');
    catch
        print(fig, pdf, '-dpdf');
    end
    fprintf('[0351-matlab] wrote %s\n', pdf);
end
end

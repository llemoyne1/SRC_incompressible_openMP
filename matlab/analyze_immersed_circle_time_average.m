function out = analyze_immersed_circle_time_average(runDir, varargin)
%ANALYZE_IMMERSED_CIRCLE_TIME_AVERAGE Time-average and RMS fields for an immersed-circle run.
%
%   out = analyze_immersed_circle_time_average(runDir)
%
%   This MATLAB-only post-processing helper reconstructs binned fields from
%   .smpcd dumps, optionally applies a spatial box filter, and computes mean
%   and RMS fields over a selected time window.
%
%   Optional name/value pairs:
%     'timeAverageStartFraction' : fraction of frames discarded from start, default 0.5
%     'frameStride'              : keep every nth frame, default 1
%     'fieldList'                : cell/string array among {'Ux','Uy','speed','omega','rho'}
%     'filterType'               : 'none' or 'box', default 'box'
%     'filterWidth'              : odd integer >= 1, default 3
%     'showPlots'                : true/false, default true
%     'saveMat'                  : true/false, default false
%     'savePrefix'               : .mat prefix, default 'immersed_circle_time_average'
%     'circleCx','circleCy','circleR' : optional overrides
%
%   The circle outline is only overlaid for visual guidance. No masking is
%   applied to the data, so cell-binning artefacts near the boundary remain
%   visible.

p = inputParser;
p.FunctionName = 'analyze_immersed_circle_time_average';
addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'timeAverageStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'fieldList', {'Ux','Uy','omega'}, @(c) iscell(c) || isstring(c) || ischar(c));
addParameter(p, 'filterType', 'box', @(s) ischar(s) || isstring(s));
addParameter(p, 'filterWidth', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'showPlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'saveMat', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'savePrefix', 'immersed_circle_time_average', @(s) ischar(s) || isstring(s));
addParameter(p, 'circleCx', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'circleCy', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'circleR',  [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
parse(p, runDir, varargin{:});
opts = p.Results;

runDir = char(opts.runDir);
paramsPath = fullfile(runDir, 'params_used.kv');
if ~exist(paramsPath, 'file')
    error('Cannot find params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsPath);
frameTable = list_smpcd_dumps(runDir);
if isempty(frameTable)
    error('No .smpcd dumps found in %s', runDir);
end

Nx = local_get_num(params, 'Nx');
Ny = local_get_num(params, 'Ny');
Lx = local_get_num(params, 'Lx');
Ly = local_get_num(params, 'Ly');

circleCx = local_get_override_or_param(opts.circleCx, params, {'immersedCircleCx'}, 0.5);
circleCy = local_get_override_or_param(opts.circleCy, params, {'immersedCircleCy'}, 0.5);
circleR  = local_get_override_or_param(opts.circleR,  params, {'immersedCircleR'},  0.12);

fieldList = local_to_cellstr(opts.fieldList);
fieldList = local_validate_field_list(fieldList);

nFrames = height(frameTable);
startIdx = min(nFrames, max(1, floor(opts.timeAverageStartFraction * nFrames) + 1));
selectedIdx = startIdx:round(opts.frameStride):nFrames;
if isempty(selectedIdx)
    selectedIdx = nFrames;
end

acc = struct();
for k = 1:numel(fieldList)
    fld = fieldList{k};
    acc.(fld).sum = zeros(Ny, Nx);
    acc.(fld).sumSq = zeros(Ny, Nx);
end

for ii = 1:numel(selectedIdx)
    idx = selectedIdx(ii);
    state = read_smpcd_state(frameTable.fullPath{idx});
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);

    for k = 1:numel(fieldList)
        fld = fieldList{k};
        A = local_extract_field(fields, fld);
        A = local_apply_filter(A, opts.filterType, opts.filterWidth);
        acc.(fld).sum = acc.(fld).sum + A;
        acc.(fld).sumSq = acc.(fld).sumSq + A.^2;
    end
end

nAvg = numel(selectedIdx);
meanFields = struct();
rmsFields = struct();
for k = 1:numel(fieldList)
    fld = fieldList{k};
    meanFields.(fld) = acc.(fld).sum / nAvg;
    varField = max(acc.(fld).sumSq / nAvg - meanFields.(fld).^2, 0.0);
    rmsFields.(fld) = sqrt(varField);
end

[Xc, Yc] = local_cell_centers(Lx, Ly, Nx, Ny);

out = struct();
out.runDir = runDir;
out.params = params;
out.frameTable = frameTable;
out.selectedIdx = selectedIdx;
out.nFrames = nFrames;
out.nAveragedFrames = nAvg;
out.timeWindow = [frameTable.time(selectedIdx(1)), frameTable.time(selectedIdx(end))];
out.meanFields = meanFields;
out.rmsFields = rmsFields;
out.Xc = Xc;
out.Yc = Yc;
out.circle = struct('cx', circleCx, 'cy', circleCy, 'r', circleR);
out.options = opts;

if opts.showPlots
    local_plot_fields(out, fieldList);
end

if opts.saveMat
    savePath = fullfile(runDir, [char(opts.savePrefix), '.mat']);
    save(savePath, 'out');
    fprintf('[analyze_immersed_circle_time_average] saved %s\n', savePath);
end
end

function c = local_to_cellstr(x)
if iscell(x)
    c = cellfun(@char, x, 'UniformOutput', false);
elseif isstring(x)
    c = cellstr(x);
elseif ischar(x)
    c = {x};
else
    error('Invalid fieldList.');
end
end

function fieldList = local_validate_field_list(fieldList)
allowed = {'Ux','Uy','speed','omega','rho'};
for k = 1:numel(fieldList)
    if ~ismember(fieldList{k}, allowed)
        error('Unsupported field ''%s''.', fieldList{k});
    end
end
end

function val = local_get_num(params, key)
if isfield(params, key)
    val = str2double(string(params.(key)));
else
    error('Missing parameter %s in params_used.kv', key);
end
end

function val = local_get_override_or_param(overrideVal, params, keys, defaultVal)
if ~isempty(overrideVal)
    val = overrideVal;
    return;
end
for i = 1:numel(keys)
    key = keys{i};
    if isfield(params, key)
        val = str2double(string(params.(key)));
        if ~isnan(val)
            return;
        end
    end
end
val = defaultVal;
end

function A = local_extract_field(fields, fld)
switch fld
    case 'Ux'
        A = fields.Ux;
    case 'Uy'
        A = fields.Uy;
    case 'speed'
        if isfield(fields, 'speed')
            A = fields.speed;
        else
            A = hypot(fields.Ux, fields.Uy);
        end
    case 'omega'
        A = fields.omega;
    case 'rho'
        if isfield(fields, 'rho')
            A = fields.rho;
        elseif isfield(fields, 'mass')
            A = fields.mass;
        else
            A = fields.N;
        end
    otherwise
        error('Unsupported field %s', fld);
end
end

function A = local_apply_filter(A, filterType, filterWidth)
filterType = char(string(filterType));
filterWidth = max(1, round(filterWidth));
if mod(filterWidth, 2) == 0
    filterWidth = filterWidth + 1;
end
switch lower(filterType)
    case 'none'
        return;
    case 'box'
        K = ones(filterWidth, filterWidth) / (filterWidth * filterWidth);
        A = conv2(A, K, 'same');
    otherwise
        error('Unknown filterType %s', filterType);
end
end

function [Xc, Yc] = local_cell_centers(Lx, Ly, Nx, Ny)
dx = Lx / Nx;
dy = Ly / Ny;
x = ((0:Nx-1) + 0.5) * dx;
y = ((0:Ny-1) + 0.5) * dy;
[Xc, Yc] = meshgrid(x, y);
end

function local_plot_fields(out, fieldList)
n = numel(fieldList);
figure('Name', sprintf('Immersed circle time averages: %s', out.runDir), 'Color', 'w');
tiledlayout(n, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for k = 1:n
    fld = fieldList{k};
    nexttile;
    local_plot_one(out.Xc, out.Yc, out.meanFields.(fld), out.circle, sprintf('mean %s', fld));
    nexttile;
    local_plot_one(out.Xc, out.Yc, out.rmsFields.(fld), out.circle, sprintf('rms %s', fld));
end
sgtitle(sprintf('%s | averaged frames: %d | t=[%.4g, %.4g]', ...
    out.runDir, out.nAveragedFrames, out.timeWindow(1), out.timeWindow(2)), ...
    'Interpreter', 'none');
end

function local_plot_one(Xc, Yc, A, circle, ttl)
imagesc(Xc(1,:), Yc(:,1), A);
axis image;
set(gca, 'YDir', 'normal');
colorbar;
hold on;
th = linspace(0, 2*pi, 256);
plot(circle.cx + circle.r*cos(th), circle.cy + circle.r*sin(th), 'k-', 'LineWidth', 1.0);
hold off;
title(ttl, 'Interpreter', 'none');
xlabel('x'); ylabel('y');
end

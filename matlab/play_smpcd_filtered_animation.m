function out = play_smpcd_filtered_animation(runDir, varargin)
%PLAY_SMPCD_FILTERED_ANIMATION Play a filtered animation from .smpcd dumps.
%
%   out = play_smpcd_filtered_animation(runDir, ...)
%
%   Optional name/value pairs:
%     'field'                    : 'omega','Ux','Uy','speed','rho', default 'omega'
%     'frameStride'              : use every nth frame, default 1
%     'timeAverageStartFraction' : discard first fraction of frames, default 0.0
%     'filterType'               : 'none' or 'box', default 'box'
%     'filterWidth'              : odd integer >= 1, default 3
%     'temporalHalfWindow'       : moving-average half-window in frames, default 0
%     'pauseTime'                : pause in seconds between frames, default 0.05
%     'clim'                     : two-element color limits or [], default []
%     'showVelocityVectors'      : true/false, default false
%     'vectorStride'             : stride for quiver display, default 4
%     'circleCx','circleCy','circleR' : optional overrides
%
%   Filtering is only for visual inspection. Raw dump data are not modified.

p = inputParser;
p.FunctionName = 'play_smpcd_filtered_animation';
addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'field', 'Ux', @(s) ischar(s) || isstring(s));
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'timeAverageStartFraction', 0.0, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'filterType', 'box', @(s) ischar(s) || isstring(s));
addParameter(p, 'filterWidth', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'temporalHalfWindow', 3, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'pauseTime', 0.05, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'clim', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
addParameter(p, 'showVelocityVectors', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'vectorStride', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
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

Nx = str2double(string(params.Nx));
Ny = str2double(string(params.Ny));
Lx = str2double(string(params.Lx));
Ly = str2double(string(params.Ly));

circleCx = local_get_override_or_param(opts.circleCx, params, {'immersedCircleCx'}, 0.5);
circleCy = local_get_override_or_param(opts.circleCy, params, {'immersedCircleCy'}, 0.5);
circleR  = local_get_override_or_param(opts.circleR,  params, {'immersedCircleR'},  0.12);
circleVx = local_get_override_or_param([], params, {'immersedCircleVx'}, 0.0);
circleVy = local_get_override_or_param([], params, {'immersedCircleVy'}, 0.0);

nFrames = height(frameTable);
startIdx = min(nFrames, max(1, floor(opts.timeAverageStartFraction * nFrames) + 1));
selectedIdx = startIdx:round(opts.frameStride):nFrames;
if isempty(selectedIdx)
    selectedIdx = nFrames;
end

fieldData = cell(numel(selectedIdx), 1);
UxData = cell(numel(selectedIdx), 1);
UyData = cell(numel(selectedIdx), 1);
times = zeros(numel(selectedIdx), 1);

for ii = 1:numel(selectedIdx)
    idx = selectedIdx(ii);
    state = read_smpcd_state(frameTable.fullPath{idx});
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);
    fieldData{ii} = local_extract_field(fields, char(string(opts.field)));
    fieldData{ii} = local_apply_filter(fieldData{ii}, opts.filterType, opts.filterWidth);
    UxData{ii} = fields.Ux;
    UyData{ii} = fields.Uy;
    times(ii) = frameTable.time(idx);
end

if opts.temporalHalfWindow > 0
    fieldData = local_apply_temporal_smoothing(fieldData, round(opts.temporalHalfWindow));
end

[Xc, Yc] = local_cell_centers(Lx, Ly, Nx, Ny);
figure('Name', sprintf('Filtered animation: %s', runDir), 'Color', 'w');
for ii = 1:numel(selectedIdx)
    imagesc(Xc(1,:), Yc(:,1), fieldData{ii});
    axis image;
    set(gca, 'YDir', 'normal');
    if ~isempty(opts.clim)
        caxis(opts.clim);
    end
    colorbar;
    hold on;
    th = linspace(0, 2*pi, 256);
    cxt = circleCx + circleVx * times(ii);
    cyt = circleCy + circleVy * times(ii);
    plot(cxt + circleR*cos(th), cyt + circleR*sin(th), 'k-', 'LineWidth', 1.0);
    plot(circleCx + circleVx * times, circleCy + circleVy * times, 'k:', 'LineWidth', 0.8);
    if opts.showVelocityVectors
        ss = max(1, round(opts.vectorStride));
        quiver(Xc(1:ss:end,1:ss:end), Yc(1:ss:end,1:ss:end), ...
               UxData{ii}(1:ss:end,1:ss:end), UyData{ii}(1:ss:end,1:ss:end), ...
               'k');
    end
    hold off;
    title(sprintf('%s | filtered %s | frame %d/%d | t=%.4g', ...
        runDir, char(string(opts.field)), ii, numel(selectedIdx), times(ii)), ...
        'Interpreter', 'none');
    xlabel('x'); ylabel('y');
    drawnow;
    pause(opts.pauseTime);
end

out = struct();
out.runDir = runDir;
out.selectedIdx = selectedIdx;
out.times = times;
out.options = opts;
end

function outCells = local_apply_temporal_smoothing(inCells, halfWindow)
n = numel(inCells);
outCells = cell(size(inCells));
for i = 1:n
    i0 = max(1, i - halfWindow);
    i1 = min(n, i + halfWindow);
    A = zeros(size(inCells{i}));
    for j = i0:i1
        A = A + inCells{j};
    end
    outCells{i} = A / (i1 - i0 + 1);
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
    case {'Ux','ux'}
        A = fields.Ux;
    case {'Uy','uy'}
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

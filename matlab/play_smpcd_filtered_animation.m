function out = play_smpcd_filtered_animation(runDir, varargin)
%PLAY_SMPCD_FILTERED_ANIMATION Play a filtered animation from .smpcd dumps.
%
%   out = play_smpcd_filtered_animation(runDir, ...)
%
%   Optional name/value pairs:
%     'field'                    : 'omega','Ux','Uy','speed','rho','N','solidFraction','solidAny','q6Active','q6Excluded','q9Active','q9Excluded',
%                                  'q9OpenExcluded','q9ImmersedHalo','q9LowMassSuppressed','inletReservoir', 'outletReservoir','maskCode', default 'Uy'
%     'frameStride'              : use every nth frame, default 1
%     'timeAverageStartFraction' : discard first fraction of frames, default 0.0
%     'filterType'               : 'none' or 'box', default 'box'
%     'filterWidth'              : odd integer >= 1, default 3
%     'filterDiscreteFields'     : filter N/mask fields too, default false
%     'temporalHalfWindow'       : moving-average half-window in frames, default 3
%     'pauseTime'                : pause in seconds between frames, default 0.05
%     'clim'                     : two-element color limits or [], default []
%     'showVelocityVectors'      : true/false, default true
%     'maskVelocityVectors'      : hide vectors in Q6-inactive cells, default true
%     'vectorStride'             : stride for quiver display, default 3
%     'maskOverlay'              : 'none','solid','q6','q9','all', default 'solid'
%     'solidSampleSubdiv'        : sub-cell samples per direction for masks, default 5
%     'writeMaskStats'           : write mask diagnostics CSV in runDir, default false
%     'circleCx','circleCy','circleR' : optional circle overrides
%
%   Filtering is only for visual inspection. Raw dump data are not modified.
%
%   Practical diagnostics:
%     play_smpcd_filtered_animation(runDir,'field','N','filterType','none')
%     play_smpcd_filtered_animation(runDir,'field','q9Active','maskOverlay','all')
%     play_smpcd_filtered_animation(runDir,'field','maskCode','clim',[0 6])
%
%   maskCode convention:
%     0 = Q6-inactive / solid-excluded cell
%     1 = Q9-active cell
%     2 = Q9 excluded by open-boundary reservoir band
%     3 = Q9 excluded by immersed-solid halo
%     4 = Q9 suppressed by low cell mass/population
%     5 = Q6-active but Q9-inactive for another reason
%     6 = inlet hard reservoir band
%     7 = outlet/open reservoir band

p = inputParser;
p.FunctionName = 'play_smpcd_filtered_animation';
addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'field', 'rho', @(s) ischar(s) || isstring(s));
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'timeAverageStartFraction', 0.0, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'filterType', 'box', @(s) ischar(s) || isstring(s));
addParameter(p, 'filterWidth', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'filterDiscreteFields', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'temporalHalfWindow', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'pauseTime', 0.05, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'clim', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
addParameter(p, 'showVelocityVectors', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'maskVelocityVectors', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'vectorStride', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'maskOverlay', 'solid', @(s) ischar(s) || isstring(s));
addParameter(p, 'solidSampleSubdiv', 5, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'writeMaskStats', false, @(x) islogical(x) || isnumeric(x));
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

dx = Lx / Nx;
dy = Ly / Ny;

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

fld = char(string(opts.field));
fieldIsDiscrete = local_is_discrete_field(fld);
applySpatialFilter = ~(fieldIsDiscrete && ~logical(opts.filterDiscreteFields));
applyTemporalFilter = ~(fieldIsDiscrete && ~logical(opts.filterDiscreteFields));

fieldData = cell(numel(selectedIdx), 1);
UxData = cell(numel(selectedIdx), 1);
UyData = cell(numel(selectedIdx), 1);
maskData = cell(numel(selectedIdx), 1);
times = zeros(numel(selectedIdx), 1);
maskStats = repmat(local_empty_mask_stats(), numel(selectedIdx), 1);

for ii = 1:numel(selectedIdx)
    idx = selectedIdx(ii);
    state = read_smpcd_state(frameTable.fullPath{idx});
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);
    times(ii) = frameTable.time(idx);
    masks = local_build_projection_masks(params, fields, Lx, Ly, Nx, Ny, times(ii), opts);
    maskData{ii} = masks;
    A = local_extract_field(fields, masks, fld);
    if applySpatialFilter
        A = local_apply_filter(A, opts.filterType, opts.filterWidth);
    end
    fieldData{ii} = A;
    UxData{ii} = fields.Ux;
    UyData{ii} = fields.Uy;
    if logical(opts.maskVelocityVectors)
        UxData{ii}(~masks.q6Active) = NaN;
        UyData{ii}(~masks.q6Active) = NaN;
    end
    maskStats(ii) = local_mask_stats(fields, masks, times(ii));
end

if opts.temporalHalfWindow > 0 && applyTemporalFilter
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
    elseif local_is_binary_field(fld)
        caxis([0 1]);
    elseif strcmpi(fld, 'maskCode')
        caxis([0 7]);
    end
    colorbar;
    hold on;
    local_draw_immersed_geometry(params, times(ii), Lx, Ly, circleCx, circleCy, circleR, circleVx, circleVy);
    local_draw_mask_overlay(Xc, Yc, maskData{ii}, opts.maskOverlay);
    if opts.showVelocityVectors
        ss = max(1, round(opts.vectorStride));
        quiver(Xc(1:ss:end,1:ss:end), Yc(1:ss:end,1:ss:end), ...
               UxData{ii}(1:ss:end,1:ss:end), UyData{ii}(1:ss:end,1:ss:end), ...
               'k');
    end
    hold off;
    title(sprintf('%s | filtered %s | frame %d/%d | t=%.4g', ...
        runDir, fld, ii, numel(selectedIdx), times(ii)), ...
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
out.maskStats = struct2table(maskStats);
if logical(opts.writeMaskStats)
    out.maskStatsPath = fullfile(runDir, 'filtered_animation_mask_stats.csv');
    writetable(out.maskStats, out.maskStatsPath);
end
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
val = local_get_num_param(params, keys, defaultVal);
end

function val = local_get_num_param(params, keys, defaultVal)
val = defaultVal;
for i = 1:numel(keys)
    key = keys{i};
    if isfield(params, key)
        candidate = str2double(string(params.(key)));
        if ~isnan(candidate)
            val = candidate;
            return;
        end
    end
end
end

function val = local_get_string_param(params, keys, defaultVal)
val = char(string(defaultVal));
for i = 1:numel(keys)
    key = keys{i};
    if isfield(params, key)
        val = char(string(params.(key)));
        return;
    end
end
end

function val = local_get_bool_param(params, keys, defaultVal)
val = logical(defaultVal);
for i = 1:numel(keys)
    key = keys{i};
    if isfield(params, key)
        s = lower(strtrim(char(string(params.(key)))));
        val = any(strcmp(s, {'1','true','yes','on','y'}));
        return;
    end
end
end

function A = local_extract_field(fields, masks, fld)
f = lower(char(string(fld)));
switch f
    case {'ux','u_x'}
        A = fields.Ux;
    case {'uy','u_y'}
        A = fields.Uy;
    case 'speed'
        if isfield(fields, 'speed')
            A = fields.speed;
        else
            A = hypot(fields.Ux, fields.Uy);
        end
    case {'omega','vorticity'}
        A = fields.omega;
    case {'rho','density'}
        if isfield(fields, 'rho')
            A = fields.rho;
        elseif isfield(fields, 'mass')
            A = fields.mass;
        else
            A = fields.N;
        end
    case {'n','count','counts','occupancy'}
        A = fields.N;
    case {'nminustarget','countminustarget'}
        A = fields.N - masks.targetN;
    case {'solidfraction','fluidfraction'}
        if strcmp(f, 'fluidfraction')
            A = masks.fluidFraction;
        else
            A = masks.solidFraction;
        end
    case {'solidany','immersedany','immersed'}
        A = double(masks.solidAny);
    case {'q6active','projectionactive'}
        A = double(masks.q6Active);
    case {'q6excluded','q6solidexcluded','solidexcluded'}
        A = double(masks.q6Excluded);
    case {'q9active','massfluxactive'}
        A = double(masks.q9Active);
    case {'q9excluded'}
        A = double(masks.q9Excluded);
    case {'q9openexcluded','openexcluded','reservoirexcluded'}
        A = double(masks.q9OpenExcluded);
    case {'q9immersedhalo','q9halo','immersedhalo'}
        A = double(masks.q9ImmersedHalo);
    case {'q9lowmasssuppressed','lowmasssuppressed'}
        A = double(masks.q9LowMassSuppressed);
    case {'inletreservoir','inletband'}
        A = double(masks.inletReservoir);
    case {'outletreservoir','outletband','openband'}
        A = double(masks.outletReservoir);
    case {'maskcode','q9maskcode'}
        A = masks.maskCode;
    otherwise
        error('Unsupported field %s', fld);
end
end

function tf = local_is_discrete_field(fld)
f = lower(char(string(fld)));
tf = any(strcmp(f, {'n','count','counts','occupancy','solidfraction','fluidfraction', ...
    'solidany','immersedany','immersed','q6active','projectionactive', ...
    'q6excluded','q6solidexcluded','solidexcluded','q9active','massfluxactive', ...
    'q9excluded','q9openexcluded','openexcluded','reservoirexcluded', ...
    'q9immersedhalo','q9halo','immersedhalo','q9lowmasssuppressed', ...
    'lowmasssuppressed','inletreservoir','inletband','outletreservoir', ...
    'outletband','openband','maskcode','q9maskcode'}));
end

function tf = local_is_binary_field(fld)
f = lower(char(string(fld)));
tf = any(strcmp(f, {'solidany','immersedany','immersed','q6active','projectionactive', ...
    'q6excluded','q6solidexcluded','solidexcluded','q9active','massfluxactive', ...
    'q9excluded','q9openexcluded','openexcluded','reservoirexcluded', ...
    'q9immersedhalo','q9halo','immersedhalo','q9lowmasssuppressed', ...
    'lowmasssuppressed','inletreservoir','inletband','outletreservoir', ...
    'outletband','openband'}));
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

function masks = local_build_projection_masks(params, fields, Lx, Ly, Nx, Ny, time, opts)
[Xc, Yc] = local_cell_centers(Lx, Ly, Nx, Ny);
solidFraction = local_solid_fraction(params, Lx, Ly, Nx, Ny, time, opts, Xc, Yc);
solidAny = solidFraction > 0;
fluidFraction = max(0, min(1, 1 - solidFraction));
threshold = local_get_num_param(params, {'projectionImmersedSolidFluidFractionThreshold', ...
    'immersedSolidFluidFractionThreshold'}, 0.50);
maskEnabled = local_get_bool_param(params, {'projectionImmersedSolidMaskEnable'}, false);
immersedEnabled = local_immersed_enabled(params, solidAny);
if immersedEnabled && maskEnabled
    q6Active = fluidFraction >= threshold;
else
    q6Active = true(Ny, Nx);
end
q6Excluded = ~q6Active;

inletCells = max(0, round(local_get_num_param(params, {'inletReservoirCells', 'inletDensityControlCells'}, 0)));
inletReservoir = local_boundary_band(params, Nx, Ny, inletCells, {'inlet','input'});
outletReservoir = local_boundary_band(params, Nx, Ny, inletCells, {'outlet','output','open'});

q9OpenN = max(0, round(local_get_num_param(params, {'q9OpenBoundaryExclusionCells', 'q9ReservoirExclusionCells'}, 0)));
q9OpenExcluded = local_boundary_band(params, Nx, Ny, q9OpenN, {'inlet','input','outlet','output','open'});

q9HaloN = max(0, round(local_get_num_param(params, {'q9ImmersedSolidHaloCells', 'q9SolidHaloCells'}, 0)));
if q9HaloN > 0
    haloKernel = ones(2*q9HaloN + 1, 2*q9HaloN + 1);
    q9ImmersedHalo = conv2(double(q6Excluded | solidAny), haloKernel, 'same') > 0;
    q9ImmersedHalo = q9ImmersedHalo & q6Active;
else
    q9ImmersedHalo = false(Ny, Nx);
end

minMass = local_get_num_param(params, {'q9MinCellMassForCorrection', 'q9MinMassForCorrection'}, 0.0);
if minMass > 0 && isfield(fields, 'N')
    q9LowMassSuppressed = fields.N < minMass;
else
    q9LowMassSuppressed = false(Ny, Nx);
end
q9LowMassSuppressed = q9LowMassSuppressed & q6Active & ~q9OpenExcluded & ~q9ImmersedHalo;

q9Active = q6Active & ~q9OpenExcluded & ~q9ImmersedHalo & ~q9LowMassSuppressed;
q9Excluded = q6Active & ~q9Active;

targetN = local_get_num_param(params, {'inletTargetOccupancy', 'gamma', 'targetOccupancy'}, NaN);
if isnan(targetN)
    targetN = 0;
end

maskCode = zeros(Ny, Nx);
maskCode(q9Active) = 1;
maskCode(q9OpenExcluded & q6Active) = 2;
maskCode(q9ImmersedHalo & q6Active) = 3;
maskCode(q9LowMassSuppressed & q6Active) = 4;
maskCode(q9Excluded & maskCode == 0) = 5;
maskCode(inletReservoir & q6Active) = 6;
maskCode(outletReservoir & q6Active) = 7;

masks = struct();
masks.solidFraction = solidFraction;
masks.fluidFraction = fluidFraction;
masks.solidAny = solidAny;
masks.q6Active = q6Active;
masks.q6Excluded = q6Excluded;
masks.q9Active = q9Active;
masks.q9Excluded = q9Excluded;
masks.q9OpenExcluded = q9OpenExcluded & q6Active;
masks.q9ImmersedHalo = q9ImmersedHalo;
masks.q9LowMassSuppressed = q9LowMassSuppressed;
masks.inletReservoir = inletReservoir & q6Active;
masks.outletReservoir = outletReservoir & q6Active;
masks.maskCode = maskCode;
masks.targetN = targetN;
end

function tf = local_immersed_enabled(params, solidAny)
shape = lower(strtrim(local_get_string_param(params, {'immersedSolidShape','immersedShape'}, 'none')));
tfShape = ~any(strcmp(shape, {'none','off','false','0',''}));
tfFlag = local_get_bool_param(params, {'immersedSolidEnable', 'immersedEnable'}, false);
tf = tfFlag || tfShape || any(solidAny(:));
end

function solidFraction = local_solid_fraction(params, Lx, Ly, Nx, Ny, time, opts, Xc, Yc)
subdiv = max(1, round(opts.solidSampleSubdiv));
solidFraction = zeros(Ny, Nx);
if subdiv == 1
    solidFraction = double(local_geometry_solid_at(params, Xc, Yc, time, opts));
    return;
end

dx = Lx / Nx;
dy = Ly / Ny;
off = ((0:subdiv-1) + 0.5) / subdiv - 0.5;
for iy = 1:subdiv
    for ix = 1:subdiv
        Xs = Xc + off(ix) * dx;
        Ys = Yc + off(iy) * dy;
        solidFraction = solidFraction + double(local_geometry_solid_at(params, Xs, Ys, time, opts));
    end
end
solidFraction = solidFraction / (subdiv * subdiv);
end

function inside = local_geometry_solid_at(params, X, Y, time, opts)
inside = false(size(X));
shape = lower(strtrim(local_get_string_param(params, {'immersedSolidShape','immersedShape'}, 'none')));

hasRect = local_has_any_param(params, {'immersedRectXMin','immersedRectangleXMin', ...
    'immersedSolidRectXMin','immersedSolidRectangleXMin','immersedSolidXMin', ...
    'solidRectXMin','rectXMin','stepXMin'});
if strcmp(shape, 'rectangle') || strcmp(shape, 'rect') || hasRect
    xMin = local_get_num_param(params, {'immersedRectXMin','immersedRectangleXMin', ...
        'immersedSolidRectXMin','immersedSolidRectangleXMin','immersedSolidXMin', ...
        'solidRectXMin','rectXMin','stepXMin'}, NaN);
    xMax = local_get_num_param(params, {'immersedRectXMax','immersedRectangleXMax', ...
        'immersedSolidRectXMax','immersedSolidRectangleXMax','immersedSolidXMax', ...
        'solidRectXMax','rectXMax','stepXMax'}, NaN);
    yMin = local_get_num_param(params, {'immersedRectYMin','immersedRectangleYMin', ...
        'immersedSolidRectYMin','immersedSolidRectangleYMin','immersedSolidYMin', ...
        'solidRectYMin','rectYMin','stepYMin'}, NaN);
    yMax = local_get_num_param(params, {'immersedRectYMax','immersedRectangleYMax', ...
        'immersedSolidRectYMax','immersedSolidRectangleYMax','immersedSolidYMax', ...
        'solidRectYMax','rectYMax','stepYMax'}, NaN);
    vx = local_get_num_param(params, {'immersedRectVx','immersedRectangleVx','immersedSolidVx'}, 0.0);
    vy = local_get_num_param(params, {'immersedRectVy','immersedRectangleVy','immersedSolidVy'}, 0.0);
    if all(~isnan([xMin xMax yMin yMax]))
        xMin = xMin + vx*time; xMax = xMax + vx*time;
        yMin = yMin + vy*time; yMax = yMax + vy*time;
        inside = inside | (X >= min(xMin,xMax) & X <= max(xMin,xMax) & ...
                           Y >= min(yMin,yMax) & Y <= max(yMin,yMax));
    end
end

hasCircle = local_has_any_param(params, {'immersedCircleCx','immersedCircleCy','immersedCircleR'});
if strcmp(shape, 'circle') || hasCircle || ~isempty(opts.circleR)
    cx = local_get_override_or_param(opts.circleCx, params, {'immersedCircleCx'}, 0.5);
    cy = local_get_override_or_param(opts.circleCy, params, {'immersedCircleCy'}, 0.5);
    r  = local_get_override_or_param(opts.circleR,  params, {'immersedCircleR'}, 0.12);
    vx = local_get_num_param(params, {'immersedCircleVx','immersedSolidVx'}, 0.0);
    vy = local_get_num_param(params, {'immersedCircleVy','immersedSolidVy'}, 0.0);
    cx = cx + vx*time;
    cy = cy + vy*time;
    inside = inside | ((X - cx).^2 + (Y - cy).^2 <= r*r);
end
end

function tf = local_has_any_param(params, keys)
tf = false;
for i = 1:numel(keys)
    if isfield(params, keys{i})
        tf = true;
        return;
    end
end
end

function band = local_boundary_band(params, Nx, Ny, nCells, names)
band = false(Ny, Nx);
if nCells <= 0
    return;
end
nX = min(Nx, nCells);
nY = min(Ny, nCells);
if local_bc_matches(params, 'bcLeft', names)
    band(:, 1:nX) = true;
end
if local_bc_matches(params, 'bcRight', names)
    band(:, Nx-nX+1:Nx) = true;
end
if local_bc_matches(params, 'bcBottom', names)
    band(1:nY, :) = true;
end
if local_bc_matches(params, 'bcTop', names)
    band(Ny-nY+1:Ny, :) = true;
end
end

function tf = local_bc_matches(params, key, names)
bc = lower(strtrim(local_get_string_param(params, {key}, 'periodic')));
tf = any(strcmp(bc, names));
end

function local_draw_immersed_geometry(params, time, Lx, Ly, circleCx, circleCy, circleR, circleVx, circleVy)
shape = lower(strtrim(local_get_string_param(params, {'immersedSolidShape','immersedShape'}, 'none')));
hasRect = local_has_any_param(params, {'immersedRectXMin','immersedRectangleXMin', ...
    'immersedSolidRectXMin','immersedSolidRectangleXMin','immersedSolidXMin', ...
    'solidRectXMin','rectXMin','stepXMin'});
if strcmp(shape, 'rectangle') || strcmp(shape, 'rect') || hasRect
    xMin = local_get_num_param(params, {'immersedRectXMin','immersedRectangleXMin', ...
        'immersedSolidRectXMin','immersedSolidRectangleXMin','immersedSolidXMin', ...
        'solidRectXMin','rectXMin','stepXMin'}, NaN);
    xMax = local_get_num_param(params, {'immersedRectXMax','immersedRectangleXMax', ...
        'immersedSolidRectXMax','immersedSolidRectangleXMax','immersedSolidXMax', ...
        'solidRectXMax','rectXMax','stepXMax'}, NaN);
    yMin = local_get_num_param(params, {'immersedRectYMin','immersedRectangleYMin', ...
        'immersedSolidRectYMin','immersedSolidRectangleYMin','immersedSolidYMin', ...
        'solidRectYMin','rectYMin','stepYMin'}, NaN);
    yMax = local_get_num_param(params, {'immersedRectYMax','immersedRectangleYMax', ...
        'immersedSolidRectYMax','immersedSolidRectangleYMax','immersedSolidYMax', ...
        'solidRectYMax','rectYMax','stepYMax'}, NaN);
    vx = local_get_num_param(params, {'immersedRectVx','immersedRectangleVx','immersedSolidVx'}, 0.0);
    vy = local_get_num_param(params, {'immersedRectVy','immersedRectangleVy','immersedSolidVy'}, 0.0);
    if all(~isnan([xMin xMax yMin yMax]))
        xMin = xMin + vx*time; xMax = xMax + vx*time;
        yMin = yMin + vy*time; yMax = yMax + vy*time;
        plot([xMin xMax xMax xMin xMin], [yMin yMin yMax yMax yMin], 'k-', 'LineWidth', 1.2);
    end
elseif strcmp(shape, 'circle') || local_has_any_param(params, {'immersedCircleCx','immersedCircleCy','immersedCircleR'})
    th = linspace(0, 2*pi, 256);
    cxt = circleCx + circleVx * time;
    cyt = circleCy + circleVy * time;
    plot(cxt + circleR*cos(th), cyt + circleR*sin(th), 'k-', 'LineWidth', 1.0);
end
xlim([0 Lx]); ylim([0 Ly]);
end

function local_draw_mask_overlay(Xc, Yc, masks, overlayMode)
mode = lower(strtrim(char(string(overlayMode))));
if strcmp(mode, 'none')
    return;
end
if any(strcmp(mode, {'solid','all'}))
    local_contour_mask(Xc, Yc, masks.solidAny, 'k-', 1.2);
end
if any(strcmp(mode, {'q6','all'}))
    local_contour_mask(Xc, Yc, masks.q6Active, 'w--', 0.9);
end
if any(strcmp(mode, {'q9','all'}))
    local_contour_mask(Xc, Yc, masks.q9Active, 'm-', 0.8);
    local_contour_mask(Xc, Yc, masks.q9OpenExcluded, 'c--', 0.8);
    local_contour_mask(Xc, Yc, masks.q9ImmersedHalo, 'r:', 1.0);
end
end

function local_contour_mask(Xc, Yc, M, lineSpec, lineWidth)
if isempty(M) || all(M(:) == M(1))
    return;
end
contour(Xc, Yc, double(M), [0.5 0.5], lineSpec, 'LineWidth', lineWidth);
end

function stats = local_empty_mask_stats()
stats = struct();
stats.time = NaN;
stats.meanN = NaN;
stats.stdN = NaN;
stats.minN = NaN;
stats.maxN = NaN;
stats.solidAnyCells = NaN;
stats.q6ActiveCells = NaN;
stats.q6ExcludedCells = NaN;
stats.q9ActiveCells = NaN;
stats.q9ExcludedCells = NaN;
stats.q9OpenExcludedCells = NaN;
stats.q9ImmersedHaloCells = NaN;
stats.q9LowMassSuppressedCells = NaN;
stats.inletReservoirCells = NaN;
stats.outletReservoirCells = NaN;
stats.inletReservoirMeanN = NaN;
stats.inletReservoirStdN = NaN;
stats.inletReservoirMinN = NaN;
stats.inletReservoirMaxN = NaN;
stats.inletReservoirEmptyFraction = NaN;
stats.q9ActiveMeanN = NaN;
stats.q9ActiveStdN = NaN;
stats.q9ExcludedMeanN = NaN;
stats.q9ExcludedStdN = NaN;
end

function stats = local_mask_stats(fields, masks, time)
stats = local_empty_mask_stats();
stats.time = time;
N = fields.N;
stats.meanN = mean(N(:));
stats.stdN = std(double(N(:)));
stats.minN = min(N(:));
stats.maxN = max(N(:));
stats.solidAnyCells = nnz(masks.solidAny);
stats.q6ActiveCells = nnz(masks.q6Active);
stats.q6ExcludedCells = nnz(masks.q6Excluded);
stats.q9ActiveCells = nnz(masks.q9Active);
stats.q9ExcludedCells = nnz(masks.q9Excluded);
stats.q9OpenExcludedCells = nnz(masks.q9OpenExcluded);
stats.q9ImmersedHaloCells = nnz(masks.q9ImmersedHalo);
stats.q9LowMassSuppressedCells = nnz(masks.q9LowMassSuppressed);
stats.inletReservoirCells = nnz(masks.inletReservoir);
stats.outletReservoirCells = nnz(masks.outletReservoir);
if any(masks.inletReservoir(:))
    Nv = double(N(masks.inletReservoir));
    stats.inletReservoirMeanN = mean(Nv);
    stats.inletReservoirStdN = std(Nv);
    stats.inletReservoirMinN = min(Nv);
    stats.inletReservoirMaxN = max(Nv);
    stats.inletReservoirEmptyFraction = mean(Nv == 0);
end
if any(masks.q9Active(:))
    Nv = double(N(masks.q9Active));
    stats.q9ActiveMeanN = mean(Nv);
    stats.q9ActiveStdN = std(Nv);
end
if any(masks.q9Excluded(:))
    Nv = double(N(masks.q9Excluded));
    stats.q9ExcludedMeanN = mean(Nv);
    stats.q9ExcludedStdN = std(Nv);
end
end

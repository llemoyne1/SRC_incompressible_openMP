function report = make_periodic_cylinder_dynamic_visual_report_0105(runDirs, varargin)
%MAKE_PERIODIC_CYLINDER_DYNAMIC_VISUAL_REPORT_0105 Dynamic cylinder visual report.
%
%   make_periodic_cylinder_dynamic_visual_report_0105()
%   make_periodic_cylinder_dynamic_visual_report_0105({'../runs/...'}, ...)
%
% The script creates visible MATLAB figures and saves PNG contact sheets in
% each run directory under visual_0105/.  It intentionally shows both global
% and cylinder-zoom views, without post-processing filters that could hide
% startup artifacts near the immersed solid.

if nargin < 1
    runDirs = {};
end

p = inputParser;
p.FunctionName = 'make_periodic_cylinder_dynamic_visual_report_0105';
addOptional(p, 'runDirs', {}, @(x) iscell(x) || isstring(x) || ischar(x));
addParameter(p, 'maxFrames', 10, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'sampleMode', 'uniform', @(x) ischar(x) || isstring(x));
addParameter(p, 'zoomHalfWidth', 0.32, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'zoomHalfHeight', 0.24, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'fields', {}, @(x) iscell(x) || isstring(x) || ischar(x));
addParameter(p, 'visible', true, @(x) islogical(x) || isnumeric(x));
parse(p, runDirs, varargin{:});
opts = p.Results;

if ischar(opts.runDirs) || isstring(opts.runDirs)
    runDirs = cellstr(string(opts.runDirs));
elseif isempty(opts.runDirs)
    runDirs = { ...
        '../runs/periodic_cylinder_q9_dynamic_visual_96x48_0105', ...
        '../runs/periodic_cylinder_q9_virial_dynamic_visual_96x48_0105'};
else
    runDirs = opts.runDirs;
end

if ischar(opts.fields) || isstring(opts.fields)
    fields = cellstr(string(opts.fields));
elseif isempty(opts.fields)
    fields = {'N','speed','speedFluidActive','omega', ...
              'q9CorrectionLimiterRatio','q9LowMassSuppressed', ...
              'q9SafetyActive','q9ImmersedSolidAdjacentActive','q9ImmersedSolidCut'};
else
    fields = opts.fields;
end

report = struct();
report.generated = struct('runDir', {}, 'outputDir', {}, 'frames', {}, 'globalPng', {}, 'zoomPng', {});
for ir = 1:numel(runDirs)
    runDir = char(runDirs{ir});
    if ~isfolder(runDir)
        warning('Run directory not found, skipping: %s', runDir);
        continue;
    end
    paramsPath = fullfile(runDir, 'params_used.kv');
    if ~isfile(paramsPath)
        warning('Missing params_used.kv, skipping: %s', runDir);
        continue;
    end
    params = parse_smpcd_kv(paramsPath);
    frames = list_smpcd_dumps(runDir);
    if isempty(frames)
        warning('No state dumps found in %s', runDir);
        continue;
    end
    idx = local_choose_frame_indices(frames, round(opts.maxFrames), round(opts.frameStride), char(opts.sampleMode));

    outDir = fullfile(runDir, 'visual_0105');
    if ~isfolder(outDir)
        mkdir(outDir);
    end

    runReport = struct();
    runReport.runDir = runDir;
    runReport.outputDir = outDir;
    runReport.frames = frames.step(idx);
    runReport.globalPng = strings(0,1);
    runReport.zoomPng = strings(0,1);

    for jf = 1:numel(fields)
        fieldName = char(fields{jf});
        [fig, pngPath] = local_make_contact_sheet(runDir, params, frames, idx, fieldName, outDir, logical(opts.visible), false, opts.zoomHalfWidth, opts.zoomHalfHeight);
        drawnow;
        exportgraphics(fig, pngPath, 'Resolution', 150);
        runReport.globalPng(end+1,1) = string(pngPath); %#ok<AGROW>

        [figZ, pngPathZ] = local_make_contact_sheet(runDir, params, frames, idx, fieldName, outDir, logical(opts.visible), true, opts.zoomHalfWidth, opts.zoomHalfHeight);
        drawnow;
        exportgraphics(figZ, pngPathZ, 'Resolution', 150);
        runReport.zoomPng(end+1,1) = string(pngPathZ); %#ok<AGROW>
    end
    report.generated(end+1) = runReport; %#ok<AGROW>
end
end

function idx = local_choose_frame_indices(frames, maxFrames, frameStride, sampleMode)
n = height(frames);
if n <= 0
    idx = [];
    return;
end
mode = lower(strtrim(sampleMode));
switch mode
    case {'uniform','even','linspace'}
        m = min(maxFrames, n);
        idx = unique(round(linspace(1, n, m)), 'stable');
    otherwise
        idx = 1:max(1, frameStride):n;
        idx = idx(1:min(numel(idx), maxFrames));
end
idx = idx(:)';
end

function [fig, pngPath] = local_make_contact_sheet(runDir, params, frames, idx, fieldName, outDir, visible, zoomMode, zoomHalfWidth, zoomHalfHeight)
Nx = local_num_param(params, 'Nx', NaN);
Ny = local_num_param(params, 'Ny', NaN);
Lx = local_num_param(params, 'Lx', NaN);
Ly = local_num_param(params, 'Ly', NaN);
if any(isnan([Nx Ny Lx Ly]))
    error('Missing Nx/Ny/Lx/Ly in %s/params_used.kv', runDir);
end
Nx = round(Nx); Ny = round(Ny);
xc = ((0:Nx-1) + 0.5) * Lx / Nx;
yc = ((0:Ny-1) + 0.5) * Ly / Ny;

visFlag = 'off';
if visible
    visFlag = 'on';
end
viewName = 'global';
if zoomMode
    viewName = 'zoom';
end
fig = figure('Name', sprintf('%s | %s | %s', runDir, fieldName, viewName), 'Color', 'w', 'Visible', visFlag);
nt = numel(idx);
ncols = min(5, nt);
nrows = ceil(nt / ncols);
tl = tiledlayout(fig, nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s | %s | %s', runDir, fieldName, viewName), 'Interpreter', 'none');

allData = cell(nt, 1);
for k = 1:nt
    state = read_smpcd_state(char(frames.fullPath(idx(k))));
    raw = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);
    diag = local_read_q9_diag(runDir, frames.step(idx(k)), Nx, Ny);
    allData{k} = local_extract_field(raw, diag, fieldName);
end
[clim, isBinary] = local_field_clim(allData, fieldName);

for k = 1:nt
    nexttile(tl);
    imagesc(xc, yc, allData{k});
    set(gca, 'YDir', 'normal');
    axis image tight;
    hold on;
    local_draw_circle(params);
    hold off;
    if zoomMode
        local_apply_zoom(params, zoomHalfWidth, zoomHalfHeight, Lx, Ly);
    end
    if ~isempty(clim)
        caxis(clim);
    elseif isBinary
        caxis([0 1]);
    end
    colorbar;
    title(sprintf('step=%d, t=%.4g', round(frames.step(idx(k))), frames.time(idx(k))), 'Interpreter', 'none');
    xlabel('x'); ylabel('y');
end
safeField = regexprep(fieldName, '[^A-Za-z0-9_]+', '_');
pngPath = fullfile(outDir, sprintf('dynamic_%s_%s.png', viewName, safeField));
end

function A = local_extract_field(raw, diag, fieldName)
key = lower(strtrim(fieldName));
sz = size(raw.N);
switch key
    case {'n','count','occupancy'}
        A = raw.N;
    case {'nfluidactive','nactive'}
        A = raw.N;
        active = local_diag_or_nan(diag, 'q9ImmersedSolidActive', sz);
        if any(isfinite(active(:)))
            A(active < 0.5) = NaN;
        end
    case {'speed'}
        A = raw.speed;
    case {'speedfluidactive','speedactive'}
        A = raw.speed;
        active = local_diag_or_nan(diag, 'q9ImmersedSolidActive', sz);
        if any(isfinite(active(:)))
            A(active < 0.5) = NaN;
        end
    case {'omega','vorticity'}
        A = raw.omega;
    case {'ux','u_x'}
        A = raw.Ux;
    case {'uy','u_y'}
        A = raw.Uy;
    case {'rho','density'}
        A = raw.rho;
    case {'q9correctionlimiterratio','q9limiterratio'}
        A = local_diag_or_nan(diag, 'q9CorrectionLimiterRatio', sz);
    case {'q9lowmasssuppressed'}
        A = local_diag_or_nan(diag, 'q9LowMassSuppressed', sz);
    case {'q9safetyactive'}
        A = local_diag_or_nan(diag, 'q9SafetyActive', sz);
    case {'q9limiteractive'}
        A = local_diag_or_nan(diag, 'q9LimiterActive', sz);
    case {'q9immersedsolidadjacentactive','q9immersedsolidadjacent','q9solidadjacent'}
        A = local_diag_or_nan(diag, 'q9ImmersedSolidAdjacentActive', sz);
    case {'q9immersedsolidcut','q9solidcut'}
        A = local_diag_or_nan(diag, 'q9ImmersedSolidCut', sz);
    case {'q9immersedsolidactive','q9solidactive'}
        A = local_diag_or_nan(diag, 'q9ImmersedSolidActive', sz);
    case {'q9correctionappliedmag'}
        A = local_diag_or_nan(diag, 'q9CorrectionAppliedMag', sz);
    case {'q9correctionrawmag'}
        A = local_diag_or_nan(diag, 'q9CorrectionRawMag', sz);
    otherwise
        error('Unsupported field for report: %s', fieldName);
end
end

function A = local_diag_or_nan(diag, name, sz)
if isfield(diag, name)
    A = diag.(name);
else
    A = nan(sz);
end
end

function [clim, isBinary] = local_field_clim(data, fieldName)
key = lower(strtrim(fieldName));
isBinary = any(strcmp(key, {'q9lowmasssuppressed','q9safetyactive','q9limiteractive', ...
    'q9immersedsolidadjacentactive','q9immersedsolidadjacent','q9solidadjacent', ...
    'q9immersedsolidcut','q9solidcut','q9immersedsolidactive','q9solidactive'}));
clim = [];
if isBinary
    clim = [0 1];
    return;
end
vals = [];
for k = 1:numel(data)
    x = data{k};
    vals = [vals; x(isfinite(x))]; %#ok<AGROW>
end
if isempty(vals)
    return;
end
if any(strcmp(key, {'omega','vorticity'}))
    m = max(abs(vals));
    if m > 0
        clim = [-m m];
    end
elseif any(strcmp(key, {'q9correctionlimiterratio','q9limiterratio'}))
    clim = [0 max(1, prctile(vals, 99))];
elseif any(strcmp(key, {'n','count','occupancy','nfluidactive','nactive'}))
    clim = [max(0, prctile(vals, 1)) prctile(vals, 99)];
elseif any(strcmp(key, {'speed','speedfluidactive','speedactive'}))
    clim = [0 prctile(vals, 99)];
    if clim(2) <= clim(1)
        clim = [];
    end
end
end

function diag = local_read_q9_diag(runDir, step, Nx, Ny)
diag = struct();
path = local_q9_diag_path(runDir, step);
if isempty(path)
    return;
end
fid = fopen(path, 'rb');
if fid < 0
    return;
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
magic = fread(fid, 8, '*char')';
if numel(magic) < 7 || ~strcmp(magic(1:7), 'Q9DG001')
    return;
end
header = fread(fid, 6, 'int32=>int32');
if numel(header) ~= 6
    return;
end
version = double(header(1));
nxFile = double(header(3));
nyFile = double(header(4));
nFloatFields = double(header(5));
nFlagFields = double(header(6));
if version ~= 1 || nxFile ~= Nx || nyFile ~= Ny || nFloatFields ~= 8 || nFlagFields < 5
    return;
end
nc = Nx * Ny;
readFloat = @() reshape(fread(fid, nc, 'single=>double'), [Nx, Ny])';
readFlag = @() reshape(fread(fid, nc, 'uint8=>double'), [Nx, Ny])';
diag.cellMass = readFloat();
diag.q9CorrectionRawDUx = readFloat();
diag.q9CorrectionRawDUy = readFloat();
diag.q9CorrectionAppliedDUx = readFloat();
diag.q9CorrectionAppliedDUy = readFloat();
diag.q9CorrectionRawMag = readFloat();
diag.q9CorrectionAppliedMag = readFloat();
diag.q9CorrectionLimiterRatio = readFloat();
diag.q9LimiterActive = readFlag();
diag.q9LowMassSuppressed = readFlag();
diag.q9LowMassRamped = readFlag();
diag.q9MassFloorApplied = readFlag();
diag.q9SafetyActive = readFlag();
if nFlagFields >= 6
    diag.q9ImmersedSolidActive = readFlag();
end
if nFlagFields >= 7
    diag.q9ImmersedSolidCut = readFlag();
end
if nFlagFields >= 8
    diag.q9ImmersedSolidAdjacentActive = readFlag();
end
end

function path = local_q9_diag_path(runDir, step)
path = '';
s = round(step);
candidates = { ...
    fullfile(runDir, sprintf('q9_diagnostics_step_%08d.q9bin', s)), ...
    fullfile(runDir, sprintf('q9_diagnostics_step_%08d.bin', s)), ...
    fullfile(runDir, sprintf('q9_diagnostics_step_%08d.csv', s))};
for k = 1:numel(candidates)
    if isfile(candidates{k})
        path = candidates{k};
        return;
    end
end
files = dir(fullfile(runDir, 'q9_diagnostics_step_*.q9bin'));
for k = 1:numel(files)
    tok = regexp(files(k).name, '^q9_diagnostics_step_(\d+)\.q9bin$', 'tokens', 'once');
    if ~isempty(tok) && str2double(tok{1}) == s
        path = fullfile(files(k).folder, files(k).name);
        return;
    end
end
end

function val = local_num_param(params, key, defaultVal)
val = defaultVal;
if isfield(params, key)
    x = str2double(string(params.(key)));
    if isfinite(x)
        val = x;
    end
end
end

function local_draw_circle(params)
cx = local_num_param(params, 'immersedSolidCx', NaN);
cy = local_num_param(params, 'immersedSolidCy', NaN);
r  = local_num_param(params, 'immersedSolidR',  NaN);
if any(isnan([cx cy r])) || r <= 0
    return;
end
th = linspace(0, 2*pi, 256);
plot(cx + r*cos(th), cy + r*sin(th), 'k-', 'LineWidth', 1.2);
end

function local_apply_zoom(params, halfWidth, halfHeight, Lx, Ly)
cx = local_num_param(params, 'immersedSolidCx', NaN);
cy = local_num_param(params, 'immersedSolidCy', NaN);
if any(isnan([cx cy]))
    return;
end
xlim([max(0, cx - halfWidth), min(Lx, cx + halfWidth)]);
ylim([max(0, cy - halfHeight), min(Ly, cy + halfHeight)]);
end

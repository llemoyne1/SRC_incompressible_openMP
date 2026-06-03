function report = make_periodic_cylinder_startup_visual_report_0104(runDirs, varargin)
%MAKE_PERIODIC_CYLINDER_STARTUP_VISUAL_REPORT_0104 Early-time visual report.
%
%   make_periodic_cylinder_startup_visual_report_0104()
%   make_periodic_cylinder_startup_visual_report_0104({'../runs/...'}, ...)
%
% The script creates visible MATLAB figures and saves PNG contact sheets in
% each run directory under visual_0104/.  It is intentionally diagnostic:
% filtering is disabled by default so that startup artifacts are not hidden.

p = inputParser;
p.FunctionName = 'make_periodic_cylinder_startup_visual_report_0104';
addOptional(p, 'runDirs', {}, @(x) iscell(x) || isstring(x) || ischar(x));
addParameter(p, 'maxFrames', 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'fields', {}, @(x) iscell(x) || isstring(x) || ischar(x));
addParameter(p, 'visible', true, @(x) islogical(x) || isnumeric(x));
parse(p, runDirs, varargin{:});
opts = p.Results;

if ischar(opts.runDirs) || isstring(opts.runDirs)
    runDirs = cellstr(string(opts.runDirs));
elseif isempty(opts.runDirs)
    runDirs = { ...
        '../runs/periodic_cylinder_q9_startup_visual_96x48_0104', ...
        '../runs/periodic_cylinder_q9_virial_startup_visual_96x48_0104'};
else
    runDirs = opts.runDirs;
end

if ischar(opts.fields) || isstring(opts.fields)
    fields = cellstr(string(opts.fields));
elseif isempty(opts.fields)
    fields = {'N','speed','omega', ...
              'q9CorrectionLimiterRatio','q9LowMassSuppressed', ...
              'q9SafetyActive','q9ImmersedSolidAdjacentActive','q9ImmersedSolidCut'};
else
    fields = opts.fields;
end

report = struct();
% Keep a homogeneous structure array.  MATLAB cannot append a non-empty
% struct to struct([]) when the existing array has no declared fields.
report.generated = struct('runDir', {}, 'outputDir', {}, 'frames', {}, 'png', {});
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
    idx = 1:max(1, round(opts.frameStride)):height(frames);
    idx = idx(1:min(numel(idx), round(opts.maxFrames)));

    outDir = fullfile(runDir, 'visual_0104');
    if ~isfolder(outDir)
        mkdir(outDir);
    end

    runReport = struct();
    runReport.runDir = runDir;
    runReport.outputDir = outDir;
    runReport.frames = frames.step(idx);
    runReport.png = strings(0,1);

    for jf = 1:numel(fields)
        fieldName = char(fields{jf});
        [fig, pngPath] = local_make_contact_sheet(runDir, params, frames, idx, fieldName, outDir, logical(opts.visible));
        drawnow;
        exportgraphics(fig, pngPath, 'Resolution', 150);
        runReport.png(end+1,1) = string(pngPath); %#ok<AGROW>
    end
    report.generated(end+1) = runReport; %#ok<AGROW>
end
end

function [fig, pngPath] = local_make_contact_sheet(runDir, params, frames, idx, fieldName, outDir, visible)
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
fig = figure('Name', sprintf('%s | %s', runDir, fieldName), 'Color', 'w', 'Visible', visFlag);
nt = numel(idx);
ncols = min(4, nt);
nrows = ceil(nt / ncols);
tl = tiledlayout(fig, nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s | %s', runDir, fieldName), 'Interpreter', 'none');

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
pngPath = fullfile(outDir, sprintf('startup_%s.png', safeField));
end

function A = local_extract_field(raw, diag, fieldName)
key = lower(strtrim(fieldName));
switch key
    case {'n','count','occupancy'}
        A = raw.N;
    case {'speed'}
        A = raw.speed;
    case {'omega','vorticity'}
        A = raw.omega;
    case {'ux','u_x'}
        A = raw.Ux;
    case {'uy','u_y'}
        A = raw.Uy;
    case {'rho','density'}
        A = raw.rho;
    case {'q9correctionlimiterratio','q9limiterratio'}
        A = local_diag_or_nan(diag, 'q9CorrectionLimiterRatio', size(raw.N));
    case {'q9lowmasssuppressed'}
        A = local_diag_or_nan(diag, 'q9LowMassSuppressed', size(raw.N));
    case {'q9safetyactive'}
        A = local_diag_or_nan(diag, 'q9SafetyActive', size(raw.N));
    case {'q9immersedsolidadjacentactive','q9immersedsolidadjacent','q9solidadjacent'}
        A = local_diag_or_nan(diag, 'q9ImmersedSolidAdjacentActive', size(raw.N));
    case {'q9immersedsolidcut','q9solidcut'}
        A = local_diag_or_nan(diag, 'q9ImmersedSolidCut', size(raw.N));
    case {'q9immersedsolidactive','q9solidactive'}
        A = local_diag_or_nan(diag, 'q9ImmersedSolidActive', size(raw.N));
    case {'q9correctionappliedmag'}
        A = local_diag_or_nan(diag, 'q9CorrectionAppliedMag', size(raw.N));
    case {'q9correctionrawmag'}
        A = local_diag_or_nan(diag, 'q9CorrectionRawMag', size(raw.N));
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
isBinary = any(strcmp(key, {'q9lowmasssuppressed','q9safetyactive', ...
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
elseif any(strcmp(key, {'n','count','occupancy'}))
    clim = [max(0, prctile(vals, 1)) prctile(vals, 99)];
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

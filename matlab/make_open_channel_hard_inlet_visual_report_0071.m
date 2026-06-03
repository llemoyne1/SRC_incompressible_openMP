function V = make_open_channel_hard_inlet_visual_report_0071(varargin)
%MAKE_OPEN_CHANNEL_HARD_INLET_VISUAL_REPORT_0071 Systematic PNG visual
%diagnostics for the 0071 straight-channel hard-inlet/passive-outlet runs.

p = inputParser;
p.FunctionName = 'make_open_channel_hard_inlet_visual_report_0071';
addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
addParameter(p, 'runRoot', 'runs/open_channel_hard_inlet_budget_0071', @(s) ischar(s) || isstring(s));
addParameter(p, 'caseGlob', 'openchan_*', @(s) ischar(s) || isstring(s));
addParameter(p, 'maxFramesPerCase', 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'fields', {'N','Ux','Uy','speed','omega','q6Active','q9Active','q9OpenExcluded','q9LowMassRamp','solidAny','maskCode'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'climN', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
parse(p, varargin{:});
opts = p.Results;

root = char(opts.root);
runRoot = char(opts.runRoot);
if ~exist(runRoot, 'dir')
    runRoot = fullfile(root, char(opts.runRoot));
end
if ~exist(runRoot, 'dir')
    error('Cannot find runRoot: %s', runRoot);
end

caseDirs = dir(fullfile(runRoot, char(opts.caseGlob)));
caseDirs = caseDirs([caseDirs.isdir]);
caseDirs = caseDirs(~startsWith({caseDirs.name}, '.'));
if isempty(caseDirs)
    error('No case directories matching %s in %s', char(opts.caseGlob), runRoot);
end

figRoot = fullfile(runRoot, 'visual_report_0071');
if ~exist(figRoot, 'dir'); mkdir(figRoot); end

created = strings(0,1);
for c = 1:numel(caseDirs)
    caseLabel = caseDirs(c).name;
    caseDir = fullfile(caseDirs(c).folder, caseDirs(c).name);
    paramsPath = fullfile(caseDir, 'params_used.kv');
    if ~exist(paramsPath, 'file')
        warning('Skipping %s: missing params_used.kv', caseLabel);
        continue;
    end
    params = parse_smpcd_kv(paramsPath);
    frames = list_smpcd_dumps(caseDir);
    if isempty(frames)
        warning('Skipping %s: no .smpcd dumps', caseLabel);
        continue;
    end
    n = height(frames);
    if n <= opts.maxFramesPerCase
        idxList = 1:n;
    else
        idxList = unique(round(linspace(1, n, opts.maxFramesPerCase)));
    end

    geom = local_geometry(params);
    caseFigDir = fullfile(figRoot, caseLabel);
    if ~exist(caseFigDir, 'dir'); mkdir(caseFigDir); end

    for kk = 1:numel(idxList)
        idx = idxList(kk);
        state = read_smpcd_state(frames.fullPath{idx});
        fields = bin_smpcd_state(state, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', geom.Nx, 'Ny', geom.Ny);
        masks = local_masks(fields, geom, params);
        outPng = fullfile(caseFigDir, sprintf('frame_%04d_t_%0.4g_panel.png', idx, frames.time(idx)));
        local_panel_figure(caseLabel, idx, frames.time(idx), geom, fields, masks, opts, outPng);
        created(end+1,1) = string(outPng); %#ok<AGROW>
    end
end

V = struct();
V.runRoot = runRoot;
V.outputDir = figRoot;
V.files = created;
end

function local_panel_figure(caseLabel, frameIndex, t, geom, fields, masks, opts, outPng)
fieldList = opts.fields;
if isstring(fieldList); fieldList = cellstr(fieldList); end
nF = numel(fieldList);
nCol = 3;
nRow = ceil(nF / nCol);
fig = figure('Visible','on','Color','w','Position',[50 50 420*nCol 330*nRow]);
for k = 1:nF
    fld = char(fieldList{k});
    subplot(nRow, nCol, k);
    A = local_extract(fld, fields, masks, geom);
    imagesc(geom.x, geom.y, A);
    axis image; set(gca,'YDir','normal');
    hold on;
    xline(geom.inletCells * geom.dx, 'k:');
    xline(geom.Lx - geom.outletCells * geom.dx, 'k:');
    hold off;
    title(fld, 'Interpreter','none'); xlabel('x'); ylabel('y'); colorbar;
    if strcmpi(fld,'N') && ~isempty(opts.climN)
        caxis(opts.climN);
    elseif any(strcmpi(fld, {'q6Active','q9Active','q9OpenExcluded','q9LowMassRamp','solidAny'}))
        caxis([0 1]);
    elseif strcmpi(fld,'maskCode')
        caxis([0 4]);
    end
end
sgtitle(sprintf('%s | frame %d | t=%.4g', caseLabel, frameIndex, t), 'Interpreter','none');
saveas(fig, outPng);
%close(fig);
end

function A = local_extract(fld, fields, masks, geom)
switch lower(fld)
    case 'n'
        A = local_field_or_zeros(fields, 'N', geom.Ny, geom.Nx);
    case 'ux'
        A = local_field_or_zeros(fields, 'Ux', geom.Ny, geom.Nx);
    case 'uy'
        A = local_field_or_zeros(fields, 'Uy', geom.Ny, geom.Nx);
    case 'speed'
        Ux = local_field_or_zeros(fields, 'Ux', geom.Ny, geom.Nx);
        Uy = local_field_or_zeros(fields, 'Uy', geom.Ny, geom.Nx);
        A = hypot(Ux, Uy);
    case 'omega'
        A = local_field_or_zeros(fields, 'omega', geom.Ny, geom.Nx);
    case 'rho'
        if isfield(fields,'rho'); A = fields.rho; else; A = local_field_or_zeros(fields,'N',geom.Ny,geom.Nx); end
    case 'solidany'
        A = double(masks.solid);
    case 'q6active'
        A = double(masks.q6Active);
    case 'q9active'
        A = double(masks.q9Active);
    case 'q9openexcluded'
        A = double(masks.q9OpenExcluded);
    case 'q9lowmassramp'
        A = masks.q9LowMassRamp;
    case 'maskcode'
        A = masks.maskCode;
    otherwise
        error('Unknown field %s', fld);
end
end

function geom = local_geometry(params)
geom.Nx = local_get_num(params, 'Nx', NaN);
geom.Ny = local_get_num(params, 'Ny', NaN);
geom.Lx = local_get_num(params, 'Lx', NaN);
geom.Ly = local_get_num(params, 'Ly', NaN);
geom.dx = geom.Lx / geom.Nx;
geom.dy = geom.Ly / geom.Ny;
geom.x = ((0:geom.Nx-1) + 0.5) * geom.dx;
geom.y = ((0:geom.Ny-1) + 0.5) * geom.dy;
[geom.X, geom.Y] = meshgrid(geom.x, geom.y);
geom.inletCells = max(1, round(local_get_num(params, 'inletReservoirCells', 3)));
geom.outletCells = geom.inletCells;
if isfield(params, 'outletDensityControlCells')
    geom.outletCells = max(1, round(local_get_num(params, 'outletDensityControlCells', geom.inletCells)));
end
geom.q9OpenCells = max(0, round(local_get_num(params, 'q9OpenBoundaryExclusionCells', 0)));
end

function masks = local_masks(fields, geom, params)
N = local_field_or_zeros(fields, 'N', geom.Ny, geom.Nx);
solid = false(geom.Ny, geom.Nx);
q9OpenExcluded = false(size(solid));
if geom.q9OpenCells > 0
    q9OpenExcluded(:, 1:min(geom.q9OpenCells, geom.Nx)) = true;
    q9OpenExcluded(:, max(1, geom.Nx-geom.q9OpenCells+1):geom.Nx) = true;
end
inletBand = false(size(solid));
inletBand(:, 1:min(geom.inletCells, geom.Nx)) = true;
outletBand = false(size(solid));
outletBand(:, max(1, geom.Nx-geom.outletCells+1):geom.Nx) = true;

r0 = local_get_num(params, 'q9LowMassRampStart', 1.0);
r1 = local_get_num(params, 'q9LowMassRampEnd', local_get_num(params, 'q9MinCellMassForCorrection', 8.0));
if r1 <= r0
    ramp = double(N >= r1);
else
    ramp = min(1, max(0, (N-r0)./(r1-r0)));
end

maskCode = zeros(size(solid));
maskCode(inletBand) = 1;
maskCode(outletBand) = 2;
maskCode(q9OpenExcluded) = 3;
maskCode(solid) = 4;

masks.solid = solid;
masks.q6Active = ~solid;
masks.q9OpenExcluded = q9OpenExcluded & ~solid;
masks.q9Active = ~solid & ~q9OpenExcluded;
masks.q9LowMassRamp = ramp;
masks.maskCode = maskCode;
end

function A = local_field_or_zeros(fields, name, ny, nx)
if isfield(fields, name)
    A = fields.(name);
elseif strcmp(name,'N') && isfield(fields,'mass')
    A = fields.mass;
else
    A = zeros(ny,nx);
end
end

function v = local_get_num(params, key, defaultVal)
v = defaultVal;
if isfield(params, key)
    tmp = str2double(string(params.(key)));
    if ~isnan(tmp); v = tmp; end
end
end

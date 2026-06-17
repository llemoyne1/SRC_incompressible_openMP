function out = show_topo_vk_dump_masked_0357(dumpFile, varargin)
%SHOW_TOPO_VK_DUMP_MASKED_0357 Display a VK dump with the same immersed circle mask as livevis.
%
% out = show_topo_vk_dump_masked_0357(dumpFile, 'field', 'Ux')
%
% This utility is intended for the 0356 autonomous Von-Karman/cylinder runner.
% It reads a .smpcd dump, reconstructs a binned field, then applies the
% immersed-circle display mask before plotting.  This makes dump inspection
% comparable to the live CUDA field visualization, which is geometry-aware.
%
% The raw particle dump is not modified.  Diagnostics report how many dumped
% fluid particles are inside the immersed circle before visual masking.
%
% Main options:
%   'paramsFile'          generated .kv file; auto-detected from dump path
%   'field'               Ux|Uy|speed|omega|N|rho, default Ux
%   'Lx','Ly','Nx','Ny'   optional overrides
%   'circle'              [xc yc R] override; inferred from params by default
%   'solidFillMode'       zero|nan, default zero
%   'showParticles'       overlay raw particles, default false
%   'showVelocityVectors' overlay quiver, default true
%   'savePng'             true/false, default false
%
% Example:
%   addpath(genpath('matlab'))
%   out = show_topo_vk_dump_masked_0357( ...
%     'runs/topo_von_karman_cylinder_0356_nx1200_ny640_g6_u0p9/output/state_step_00001000.smpcd', ...
%     'field','Ux','solidFillMode','zero','clim',[0 1.2]);

p = inputParser;
p.FunctionName = 'show_topo_vk_dump_masked_0357';
addRequired(p, 'dumpFile', @(s)ischar(s) || isstring(s));
addParameter(p, 'paramsFile', '', @(s)ischar(s) || isstring(s));
addParameter(p, 'field', 'Ux', @(s)ischar(s) || isstring(s));
addParameter(p, 'Lx', [], @isnumeric);
addParameter(p, 'Ly', [], @isnumeric);
addParameter(p, 'Nx', [], @isnumeric);
addParameter(p, 'Ny', [], @isnumeric);
addParameter(p, 'circle', [], @isnumeric);
addParameter(p, 'solidFillMode', 'zero', @(s)ischar(s) || isstring(s));
addParameter(p, 'clim', [], @isnumeric);
addParameter(p, 'showParticles', false, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'particleDecimation', 100, @isnumeric);
addParameter(p, 'showVelocityVectors', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'velocityDecimation', 16, @isnumeric);
addParameter(p, 'savePng', false, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'outputPrefix', '', @(s)ischar(s) || isstring(s));
addParameter(p, 'figureHandle', [], @(x)isempty(x) || ishghandle(x));
parse(p, dumpFile, varargin{:});
opts = p.Results;

dumpFile = char(opts.dumpFile);
assert(isfile(dumpFile), 'show_topo_vk_dump_masked_0357:missingDump', 'Missing dump: %s', dumpFile);

paramsFile = local_resolve_params_file(dumpFile, opts.paramsFile);
params = local_read_kv(paramsFile);
Lx = local_get_num(opts.Lx, params, 'Lx', NaN);
Ly = local_get_num(opts.Ly, params, 'Ly', NaN);
Nx = round(local_get_num(opts.Nx, params, 'Nx', NaN));
Ny = round(local_get_num(opts.Ny, params, 'Ny', NaN));
if ~isfinite(Lx) || ~isfinite(Ly) || ~isfinite(Nx) || ~isfinite(Ny)
    error('show_topo_vk_dump_masked_0357:missingGrid', 'Cannot resolve Lx/Ly/Nx/Ny; provide paramsFile or explicit values.');
end

circle = opts.circle;
if isempty(circle)
    cx = local_get_num([], params, 'immersedSolidCx', NaN);
    cy = local_get_num([], params, 'immersedSolidCy', NaN);
    r  = local_get_num([], params, 'immersedSolidR', NaN);
    circle = [cx cy r];
end
if numel(circle) ~= 3 || any(~isfinite(circle)) || circle(3) <= 0
    error('show_topo_vk_dump_masked_0357:badCircle', 'Cannot resolve immersed circle [cx cy R].');
end
circle = double(circle(:).');

state = read_smpcd_state(dumpFile);
fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, 'periodicX', true, 'periodicY', false, 'fluidOnly', true);
[fieldData, fieldLabel] = local_get_field(fields, char(opts.field));
[maskedData, solidMask] = local_apply_circle_mask(fieldData, fields, circle, char(opts.solidFillMode));

diag = local_circle_diagnostics(state, circle);
step = local_step_from_name(dumpFile);
time = NaN;
if isfinite(step)
    dt = local_get_num([], params, 'dt', NaN);
    if isfinite(dt), time = step * dt; end
end

if isempty(opts.figureHandle)
    fig = figure('Name', sprintf('VK dump masked 0357 | %s', fieldLabel), 'Color', 'w');
else
    fig = figure(opts.figureHandle); clf(fig);
end
ax = axes('Parent', fig);
imagesc(ax, fields.xc, fields.yc, maskedData);
set(ax, 'YDir', 'normal');
axis(ax, 'equal'); axis(ax, [0 Lx 0 Ly]); hold(ax, 'on');
cb = colorbar(ax); ylabel(cb, fieldLabel, 'Interpreter', 'none');
if ~isempty(opts.clim) && numel(opts.clim) == 2
    caxis(ax, opts.clim);
end
local_plot_circle(ax, circle);
if logical(opts.showVelocityVectors)
    d = max(1, round(opts.velocityDecimation));
    [Xc, Yc] = meshgrid(fields.xc, fields.yc);
    Ux = fields.Ux; Uy = fields.Uy;
    Ux(solidMask) = 0; Uy(solidMask) = 0;
    quiver(ax, Xc(1:d:end,1:d:end), Yc(1:d:end,1:d:end), Ux(1:d:end,1:d:end), Uy(1:d:end,1:d:end), 'k');
end
if logical(opts.showParticles)
    role = ones(numel(state.x),1,'uint8');
    if isfield(state,'role') && ~isempty(state.role), role = uint8(state.role(:)); end
    keep = role == uint8(1) & isfinite(state.x(:)) & isfinite(state.y(:));
    idx = find(keep);
    dec = max(1, round(opts.particleDecimation));
    idx = idx(1:dec:end);
    scatter(ax, double(state.x(idx)), double(state.y(idx)), 4, 'k', 'filled', 'MarkerFaceAlpha', 0.25, 'MarkerEdgeAlpha', 0.25);
end
xlabel(ax, 'x'); ylabel(ax, 'y');
title(ax, sprintf('%s masked | %s | step=%g | t=%g | rawInside=%d', fieldLabel, local_short_name(dumpFile), step, time, diag.rawInsideFluidCount), 'Interpreter', 'none');
hold(ax, 'off');
drawnow;

png = '';
if logical(opts.savePng)
    prefix = char(opts.outputPrefix);
    if isempty(prefix)
        [folder, base] = fileparts(dumpFile);
        outDir = fullfile(folder, 'masked_view_0357');
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        prefix = fullfile(outDir, sprintf('%s_%s_masked_0357', base, lower(fieldLabel)));
    else
        outDir = fileparts(prefix);
        if ~isempty(outDir) && ~exist(outDir, 'dir'), mkdir(outDir); end
    end
    png = [prefix '.png'];
    exportgraphics(fig, png, 'Resolution', 160);
end

out = struct();
out.dumpFile = dumpFile;
out.paramsFile = paramsFile;
out.state = state;
out.fields = fields;
out.maskedData = maskedData;
out.solidMask = solidMask;
out.circle = circle;
out.Lx = Lx; out.Ly = Ly; out.Nx = Nx; out.Ny = Ny;
out.step = step; out.time = time;
out.diagnostics = diag;
out.figure = fig;
out.axes = ax;
out.png = png;

fprintf('[0357-mask] dump=%s\n', dumpFile);
fprintf('[0357-mask] params=%s\n', paramsFile);
fprintf('[0357-mask] circle=[%.9g %.9g %.9g] rawInsideFluid=%d rawInsideFraction=%.6g meanUxInsideRaw=%.6g\n', ...
    circle(1), circle(2), circle(3), diag.rawInsideFluidCount, diag.rawInsideFluidFraction, diag.meanUxInsideRaw);
if ~isempty(png), fprintf('[0357-mask] png=%s\n', png); end
end

function paramsFile = local_resolve_params_file(dumpFile, requested)
requested = char(requested);
if ~isempty(requested)
    paramsFile = requested;
    assert(isfile(paramsFile), 'show_topo_vk_dump_masked_0357:missingParams', 'Missing paramsFile: %s', paramsFile);
    return;
end
outDir = fileparts(dumpFile);
runRoot = fileparts(outDir);
candidates = [dir(fullfile(runRoot, 'params', '*.kv')); dir(fullfile(runRoot, 'params_used.kv'))];
if isempty(candidates)
    error('show_topo_vk_dump_masked_0357:noParams', 'Could not auto-detect params file from dump path. Provide paramsFile.');
end
paramsFile = fullfile(candidates(1).folder, candidates(1).name);
end

function params = local_read_kv(filename)
params = struct();
if isempty(filename) || ~isfile(filename), return; end
lines = regexp(fileread(filename), '\r?\n', 'split');
for i = 1:numel(lines)
    line = regexprep(lines{i}, '#.*$', '');
    tok = regexp(line, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$', 'tokens', 'once');
    if isempty(tok), continue; end
    key = tok{1}; val = tok{2};
    params.(key) = val;
end
end

function v = local_get_num(override, params, key, defaultValue)
if ~isempty(override)
    v = double(override); return;
end
if isfield(params, key)
    v = str2double(params.(key));
    if isfinite(v), return; end
end
v = defaultValue;
end

function [data, label] = local_get_field(fields, field)
f = lower(strtrim(field));
switch f
    case {'n','count','occupancy'}
        data = fields.N; label = 'N';
    case {'rho','density'}
        data = fields.rho; label = 'rho';
    case {'ux','u_x'}
        data = fields.Ux; label = 'Ux';
    case {'uy','u_y'}
        data = fields.Uy; label = 'Uy';
    case {'speed','u'}
        data = fields.speed; label = 'speed';
    case {'omega','vorticity'}
        data = fields.omega; label = 'omega';
    otherwise
        error('show_topo_vk_dump_masked_0357:badField', 'Unsupported field: %s', field);
end
end

function [masked, solidMask] = local_apply_circle_mask(data, fields, circle, mode)
[Xc, Yc] = meshgrid(fields.xc, fields.yc);
solidMask = (Xc-circle(1)).^2 + (Yc-circle(2)).^2 <= circle(3)^2;
masked = data;
mode = lower(strtrim(mode));
switch mode
    case 'zero'
        masked(solidMask) = 0;
    case 'nan'
        masked(solidMask) = NaN;
    otherwise
        error('show_topo_vk_dump_masked_0357:badMaskMode', 'solidFillMode must be zero or nan.');
end
end

function diag = local_circle_diagnostics(state, circle)
x = double(state.x(:)); y = double(state.y(:)); vx = double(state.vx(:));
role = ones(numel(x),1,'uint8');
if isfield(state,'role') && ~isempty(state.role), role = uint8(state.role(:)); end
fluid = role == uint8(1) & isfinite(x) & isfinite(y);
inside = fluid & ((x-circle(1)).^2 + (y-circle(2)).^2 <= circle(3)^2);
diag = struct();
diag.rawFluidCount = nnz(fluid);
diag.rawInsideFluidCount = nnz(inside);
diag.rawInsideFluidFraction = nnz(inside) / max(1, nnz(fluid));
if any(inside)
    diag.meanUxInsideRaw = mean(vx(inside), 'omitnan');
else
    diag.meanUxInsideRaw = NaN;
end
end

function local_plot_circle(ax, circle)
th = linspace(0, 2*pi, 256);
plot(ax, circle(1)+circle(3)*cos(th), circle(2)+circle(3)*sin(th), 'k-', 'LineWidth', 1.5);
end

function step = local_step_from_name(filename)
[~, base] = fileparts(filename);
tok = regexp(base, 'state_step_(\d+)', 'tokens', 'once');
if isempty(tok), step = NaN; else, step = str2double(tok{1}); end
end

function name = local_short_name(filename)
[~, name, ext] = fileparts(filename);
name = [name ext];
end

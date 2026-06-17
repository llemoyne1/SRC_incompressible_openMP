function out = show_smpcd_dump_and_field_0337(dumpFile, varargin)
%SHOW_SMPCD_DUMP_AND_FIELD_0337 Display one .smpcd dump and one binned field.
%
%   out = show_smpcd_dump_and_field_0337(dumpFile, 'field', 'omega')
%
% This utility is meant for single-frame inspection.  It reads one .smpcd
% state, reconstructs a binned Eulerian field on the simulation grid, then
% opens two figures with consistent particle/display options:
%
%   1) a particle-only dump view;
%   2) the selected binned field, optionally with particle overlay/vectors.
%
% The function only requires read_smpcd_state.m and plot_smpcd_frame.m.  It
% includes its own light binner so it can be used even when bin_smpcd_state.m
% is not on the MATLAB path.
%
% Examples:
%   show_smpcd_dump_and_field_0337('runs/vk/output/state_step_00020000.smpcd', ...
%       'paramsFile','runs/vk/params_used.kv','field','omega');
%
%   show_smpcd_dump_and_field_0337('state_step_00005000.smpcd', ...
%       'Lx',1.5,'Ly',0.4,'Nx',360,'Ny',96, ...
%       'field','Ux','clim',[-0.1 0.1], ...
%       'particleRoleFilter','fluid','particleDecimation',20);
%
% Main field options:
%   'field'              : particles|N|rho|Ux|Uy|speed|omega|type, default omega
%   'fieldRoleFilter'    : fluid|all|inactive|latent|noninactive, default fluid
%   'Lx','Ly','Nx','Ny'  : grid/domain; inferred from paramsFile when possible
%   'paramsFile'         : params_used.kv or generated .kv file
%   'fieldFilterType'    : none|box, default none
%   'fieldFilterWidth'   : odd integer, default 3
%   'clim'               : color axis for field, [] = auto
%   'showVelocityVectors': true/false, default false
%
% Particle options are intentionally aligned with plot_smpcd_frame:
%   'particleColorMode'  : role|type|single|mass|masslog|speed|speedlog
%   'particleRoleFilter' : all|fluid|inactive|latent|noninactive
%   'particleDecimation' : decimation used for both panels unless overridden
%   'dumpParticleDecimation', 'fieldParticleDecimation'
%   'particleMarkerSize', 'particleMassMin/Max', 'particleSpeedMin/Max', ...
%
% Saving:
%   'savePng', true, 'outputPrefix', 'analysis/frame_00020000'
% writes outputPrefix_dump.png and outputPrefix_field_<field>.png.

p = inputParser;
p.FunctionName = 'show_smpcd_dump_and_field_0337';
addOptional(p, 'dumpFile', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'field', 'ux', @(s) ischar(s) || isstring(s));
addParameter(p, 'paramsFile', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', [], @isnumeric);
addParameter(p, 'Ly', [], @isnumeric);
addParameter(p, 'Nx', [], @isnumeric);
addParameter(p, 'Ny', [], @isnumeric);
addParameter(p, 'step', NaN, @isnumeric);
addParameter(p, 'time', NaN, @isnumeric);
addParameter(p, 'fieldRoleFilter', 'fluid', @(s) ischar(s) || isstring(s));
addParameter(p, 'fieldFilterType', 'box', @(s) ischar(s) || isstring(s));
addParameter(p, 'fieldFilterWidth', 10, @isnumeric);
addParameter(p, 'figurePrefix', 'SRC/MPCD single dump', @(s) ischar(s) || isstring(s));
addParameter(p, 'showParticlesOnField', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'showVelocityVectors', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'velocityDecimation', 1, @isnumeric);
addParameter(p, 'clim', [], @isnumeric);
addParameter(p, 'particleDecimation', 0, @isnumeric);
addParameter(p, 'dumpParticleDecimation', [], @isnumeric);
addParameter(p, 'fieldParticleDecimation', [], @isnumeric);
addParameter(p, 'particleMarkerSize', 6, @isnumeric);
addParameter(p, 'particleColorMode', 'role', @(s) ischar(s) || isstring(s));
addParameter(p, 'particleRoleFilter', 'fluid', @(s) ischar(s) || isstring(s));
addParameter(p, 'particleMassMin', -Inf, @isnumeric);
addParameter(p, 'particleMassMax', Inf, @isnumeric);
addParameter(p, 'particleSpeedMin', -Inf, @isnumeric);
addParameter(p, 'particleSpeedMax', Inf, @isnumeric);
addParameter(p, 'particleThresholdLogic', 'and', @(s) ischar(s) || isstring(s));
addParameter(p, 'particleLabelMode', 'none', @(s) ischar(s) || isstring(s));
addParameter(p, 'particleLabelMax', 30, @isnumeric);
addParameter(p, 'particleLabelFontSize', 8, @isnumeric);
addParameter(p, 'particleClim', [], @isnumeric);
addParameter(p, 'showParticleLegend', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'savePng', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'outputPrefix', '', @(s) ischar(s) || isstring(s));
parse(p, dumpFile, varargin{:});
opts = p.Results;

dumpFile = char(opts.dumpFile);
if isempty(dumpFile)
    [fn, fp] = uigetfile({'*.smpcd','SRC/MPCD dumps (*.smpcd)'; '*.*','All files'}, ...
        'Select one .smpcd dump');
    if isequal(fn, 0)
        error('show_smpcd_dump_and_field_0337:noInput', 'No dump file selected.');
    end
    dumpFile = fullfile(fp, fn);
end
if ~isfile(dumpFile)
    error('show_smpcd_dump_and_field_0337:missingDump', 'Cannot find dump file: %s', dumpFile);
end

paramsFile = local_resolve_params_file(dumpFile, opts.paramsFile);
params = local_read_params(paramsFile);
[Lx, Ly, Nx, Ny] = local_resolve_grid(opts, params, dumpFile, paramsFile);
[step, time] = local_resolve_step_time(dumpFile, opts, params);

state = read_smpcd_state(dumpFile);
fields = local_bin_smpcd_state_0337(state, Lx, Ly, Nx, Ny, opts.fieldRoleFilter);
fields = local_filter_selected_field(fields, opts.field, opts.fieldFilterType, opts.fieldFilterWidth);

fieldName = char(opts.field);
figPrefix = char(opts.figurePrefix);

particleArgs = local_particle_args(opts);
baseDecimation = max(1, round(opts.particleDecimation));
if isempty(opts.dumpParticleDecimation)
    dumpDecimation = baseDecimation;
else
    dumpDecimation = max(1, round(opts.dumpParticleDecimation));
end
if isempty(opts.fieldParticleDecimation)
    fieldDecimation = baseDecimation;
else
    fieldDecimation = max(1, round(opts.fieldParticleDecimation));
end

figDump = figure('Name', sprintf('%s | dump', figPrefix), 'Color', 'w');
hDump = plot_smpcd_frame(state, fields, ...
    'field', 'particles', ...
    'step', step, ...
    'time', time, ...
    'particleDecimation', dumpDecimation, ...
    'particleMarkerSize', opts.particleMarkerSize, ...
    particleArgs{:}, ...
    'figureHandle', figDump);

title(hDump.ax, sprintf('particles | %s | step=%g | t=%g', local_short_name(dumpFile), step, time), ...
    'Interpreter', 'none');

figField = figure('Name', sprintf('%s | field %s', figPrefix, fieldName), 'Color', 'w');
hField = plot_smpcd_frame(state, fields, ...
    'field', fieldName, ...
    'step', step, ...
    'time', time, ...
    'showParticles', logical(opts.showParticlesOnField), ...
    'particleDecimation', fieldDecimation, ...
    'particleMarkerSize', opts.particleMarkerSize, ...
    particleArgs{:}, ...
    'showVelocityVectors', logical(opts.showVelocityVectors), ...
    'velocityDecimation', opts.velocityDecimation, ...
    'clim', opts.clim, ...
    'figureHandle', figField);

title(hField.ax, sprintf('%s | %s | step=%g | t=%g', fieldName, local_short_name(dumpFile), step, time), ...
    'Interpreter', 'none');

drawnow;

if logical(opts.savePng)
    prefix = char(opts.outputPrefix);
    if isempty(prefix)
        [folder, base] = fileparts(dumpFile);
        outDir = fullfile(folder, 'single_frame_view');
        if ~exist(outDir, 'dir')
            mkdir(outDir);
        end
        prefix = fullfile(outDir, base);
    else
        outDir = fileparts(prefix);
        if ~isempty(outDir) && ~exist(outDir, 'dir')
            mkdir(outDir);
        end
    end
    dumpPng = sprintf('%s_dump.png', prefix);
    fieldPng = sprintf('%s_field_%s.png', prefix, lower(regexprep(fieldName, '[^A-Za-z0-9_]+', '_')));
    exportgraphics(figDump, dumpPng, 'Resolution', 160);
    exportgraphics(figField, fieldPng, 'Resolution', 160);
else
    dumpPng = '';
    fieldPng = '';
end

out = struct();
out.dumpFile = dumpFile;
out.paramsFile = paramsFile;
out.state = state;
out.fields = fields;
out.Lx = Lx;
out.Ly = Ly;
out.Nx = Nx;
out.Ny = Ny;
out.step = step;
out.time = time;
out.figureDump = figDump;
out.figureField = figField;
out.handleDump = hDump;
out.handleField = hField;
out.dumpPng = dumpPng;
out.fieldPng = fieldPng;
end

function args = local_particle_args(opts)
args = { ...
    'particleColorMode', char(opts.particleColorMode), ...
    'particleRoleFilter', char(opts.particleRoleFilter), ...
    'particleMassMin', opts.particleMassMin, ...
    'particleMassMax', opts.particleMassMax, ...
    'particleSpeedMin', opts.particleSpeedMin, ...
    'particleSpeedMax', opts.particleSpeedMax, ...
    'particleThresholdLogic', char(opts.particleThresholdLogic), ...
    'particleLabelMode', char(opts.particleLabelMode), ...
    'particleLabelMax', opts.particleLabelMax, ...
    'particleLabelFontSize', opts.particleLabelFontSize, ...
    'particleClim', opts.particleClim, ...
    'showParticleLegend', logical(opts.showParticleLegend)};
end

function fields = local_bin_smpcd_state_0337(state, Lx, Ly, Nx, Ny, roleFilter)
Nx = round(Nx);
Ny = round(Ny);
Lx = double(Lx);
Ly = double(Ly);
dx = Lx / Nx;
dy = Ly / Ny;

n = local_particle_count(state);
x = local_state_vector(state, 'x', n, NaN);
y = local_state_vector(state, 'y', n, NaN);
vx = local_state_vector(state, 'vx', n, NaN);
vy = local_state_vector(state, 'vy', n, NaN);
mass = local_state_vector(state, 'mass', n, 1.0);
role = local_state_vector(state, 'role', n, 1.0);
type = local_state_vector(state, 'type', n, 0.0);

mask = isfinite(x) & isfinite(y) & x >= 0 & x <= Lx & y >= 0 & y <= Ly;
mask = mask & local_role_filter_mask(role, n, roleFilter);
idx = find(mask);

ix = floor(x(idx) / dx) + 1;
iy = floor(y(idx) / dy) + 1;
ix = min(max(ix, 1), Nx);
iy = min(max(iy, 1), Ny);
lin = sub2ind([Ny, Nx], iy, ix);

N = accumarray(lin, 1, [Ny*Nx, 1], @sum, 0);
M = accumarray(lin, mass(idx), [Ny*Nx, 1], @sum, 0);
Mx = accumarray(lin, mass(idx).*vx(idx), [Ny*Nx, 1], @sum, 0);
My = accumarray(lin, mass(idx).*vy(idx), [Ny*Nx, 1], @sum, 0);

N = reshape(N, [Ny, Nx]);
M = reshape(M, [Ny, Nx]);
Mx = reshape(Mx, [Ny, Nx]);
My = reshape(My, [Ny, Nx]);
Ux = zeros(Ny, Nx);
Uy = zeros(Ny, Nx);
filled = M > 0;
Ux(filled) = Mx(filled) ./ M(filled);
Uy(filled) = My(filled) ./ M(filled);

% Dominant type by cell, for type/debug views.  This is intentionally simple;
% it favors the first encountered type when counts are equal.
dominantType = NaN(Ny, Nx);
if ~isempty(idx)
    uniqueTypes = unique(type(idx));
    bestCount = zeros(Ny, Nx);
    for kt = 1:numel(uniqueTypes)
        tv = uniqueTypes(kt);
        sel = type(idx) == tv;
        C = accumarray(lin(sel), 1, [Ny*Nx, 1], @sum, 0);
        C = reshape(C, [Ny, Nx]);
        take = C > bestCount;
        dominantType(take) = tv;
        bestCount(take) = C(take);
    end
end

[dUx_dy, ~] = gradient(Ux, dy, dx);
[~, dUy_dx] = gradient(Uy, dy, dx);
omega = dUy_dx - dUx_dy;

fields = struct();
fields.Lx = Lx;
fields.Ly = Ly;
fields.Nx = Nx;
fields.Ny = Ny;
fields.dx = dx;
fields.dy = dy;
fields.xc = ((0:Nx-1) + 0.5) * dx;
fields.yc = ((0:Ny-1) + 0.5) * dy;
fields.N = N;
fields.mass = M;
fields.rho = M / (dx * dy);
fields.Ux = Ux;
fields.Uy = Uy;
fields.speed = hypot(Ux, Uy);
fields.omega = omega;
fields.dominantType = dominantType;
fields.roleFilter = char(roleFilter);
end

function fields = local_filter_selected_field(fields, fieldName, filterType, filterWidth)
filterType = lower(strtrim(char(filterType)));
if strcmp(filterType, 'none')
    return;
end
filterWidth = max(1, round(filterWidth));
if mod(filterWidth, 2) == 0
    filterWidth = filterWidth + 1;
end
K = ones(filterWidth, filterWidth) / (filterWidth * filterWidth);
key = lower(strtrim(char(fieldName)));
switch key
    case {'n','count','occupancy'}
        name = 'N';
    case {'rho','density'}
        name = 'rho';
    case 'ux'
        name = 'Ux';
    case 'uy'
        name = 'Uy';
    case {'speed','u'}
        name = 'speed';
    case {'omega','vorticity'}
        name = 'omega';
    otherwise
        return;
end
switch filterType
    case 'box'
        fields.(name) = conv2(fields.(name), K, 'same');
    otherwise
        error('show_smpcd_dump_and_field_0337:badFilter', 'Unsupported fieldFilterType: %s', filterType);
end
end

function n = local_particle_count(state)
if isfield(state, 'Np') && ~isempty(state.Np)
    n = double(state.Np);
elseif isfield(state, 'x') && ~isempty(state.x)
    n = numel(state.x);
else
    n = 0;
end
if isfield(state, 'x') && ~isempty(state.x), n = min(n, numel(state.x)); end
if isfield(state, 'y') && ~isempty(state.y), n = min(n, numel(state.y)); end
end

function v = local_state_vector(state, name, n, fallback)
if isfield(state, name) && ~isempty(state.(name))
    v = state.(name)(:);
    v = v(1:min(n, numel(v)));
    if numel(v) < n
        v(end+1:n, 1) = fallback;
    end
else
    v = repmat(fallback, n, 1);
end
v = double(v);
end

function mask = local_role_filter_mask(role, n, roleFilter)
roleFilter = lower(strtrim(char(roleFilter)));
if all(isnan(role))
    mask = true(n, 1);
    return;
end
switch roleFilter
    case 'all'
        mask = true(n, 1);
    case 'fluid'
        mask = role == 1;
    case 'inactive'
        mask = role == 0;
    case 'latent'
        mask = role == 2;
    case 'noninactive'
        mask = role ~= 0;
    otherwise
        error('show_smpcd_dump_and_field_0337:badRoleFilter', 'Unknown role filter: %s', roleFilter);
end
end

function paramsFile = local_resolve_params_file(dumpFile, requested)
requested = char(requested);
if ~isempty(requested)
    if ~isfile(requested)
        error('show_smpcd_dump_and_field_0337:missingParams', 'Cannot find paramsFile: %s', requested);
    end
    paramsFile = requested;
    return;
end

folder = fileparts(dumpFile);
parents = {folder, fileparts(folder), fileparts(fileparts(folder))};
candidates = {};
for i = 1:numel(parents)
    if isempty(parents{i}) || strcmp(parents{i}, filesep)
        continue;
    end
    candidates{end+1} = fullfile(parents{i}, 'params_used.kv'); %#ok<AGROW>
    candidates{end+1} = fullfile(parents{i}, 'params.kv'); %#ok<AGROW>
end
for i = 1:numel(candidates)
    if isfile(candidates{i})
        paramsFile = candidates{i};
        return;
    end
end

% Last resort: if runRoot/params contains exactly one .kv, use it.
for i = 1:numel(parents)
    pdir = fullfile(parents{i}, 'params');
    if isfolder(pdir)
        files = dir(fullfile(pdir, '*.kv'));
        if numel(files) == 1
            paramsFile = fullfile(files(1).folder, files(1).name);
            return;
        end
    end
end
paramsFile = '';
end

function params = local_read_params(paramsFile)
params = struct();
if isempty(paramsFile)
    return;
end
if exist('parse_smpcd_kv', 'file') == 2
    try
        params = parse_smpcd_kv(paramsFile);
        return;
    catch ME
        warning('show_smpcd_dump_and_field_0337:parseSmpcdKvFailed', ...
            'parse_smpcd_kv failed for %s: %s. Falling back to local parser.', paramsFile, ME.message);
    end
end
fid = fopen(paramsFile, 'r');
if fid < 0
    return;
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    line = fgetl(fid);
    if ~ischar(line), break; end
    line = regexprep(line, '#.*$', '');
    line = strtrim(line);
    if isempty(line), continue; end
    tok = regexp(line, '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$', 'tokens', 'once');
    if isempty(tok), continue; end
    key = tok{1};
    val = strtrim(tok{2});
    num = str2double(val);
    if ~isnan(num)
        params.(key) = num;
    else
        params.(key) = val;
    end
end
end

function [Lx, Ly, Nx, Ny] = local_resolve_grid(opts, params, dumpFile, paramsFile)
Lx = opts.Lx; Ly = opts.Ly; Nx = opts.Nx; Ny = opts.Ny;
Lx = local_value_or_param(Lx, params, {'Lx','domainLx'});
Ly = local_value_or_param(Ly, params, {'Ly','domainLy'});
Nx = local_value_or_param(Nx, params, {'Nx','nx'});
Ny = local_value_or_param(Ny, params, {'Ny','ny'});
if isempty(Lx) || isempty(Ly) || isempty(Nx) || isempty(Ny) || any(isnan([Lx Ly Nx Ny]))
    if isempty(paramsFile)
        src = 'no params file found';
    else
        src = paramsFile;
    end
    error(['show_smpcd_dump_and_field_0337:missingGrid'], ...
        ['Missing Lx/Ly/Nx/Ny for %s. Provide them explicitly or provide ', ...
         'a paramsFile. Params source tried: %s'], dumpFile, src);
end
Nx = round(Nx); Ny = round(Ny);
end

function value = local_value_or_param(value, params, keys)
if ~isempty(value)
    value = double(value);
    return;
end
value = NaN;
for i = 1:numel(keys)
    key = keys{i};
    if isfield(params, key)
        value = str2double(string(params.(key)));
        if ~isnan(value)
            return;
        end
    end
end
end

function [step, time] = local_resolve_step_time(dumpFile, opts, params)
step = opts.step;
time = opts.time;
if isnan(step)
    [~, base] = fileparts(dumpFile);
    tok = regexp(base, 'step[_-]?(\d+)', 'tokens', 'once');
    if ~isempty(tok)
        step = str2double(tok{1});
    end
end
if isnan(time) && ~isnan(step)
    dt = local_value_or_param([], params, {'dt','timeStep'});
    if ~isnan(dt)
        time = step * dt;
    end
end
end

function name = local_short_name(path)
[folder, base, ext] = fileparts(path);
[~, parent] = fileparts(folder);
name = fullfile(parent, [base ext]);
end

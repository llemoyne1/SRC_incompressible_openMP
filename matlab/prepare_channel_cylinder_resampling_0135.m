function info = prepare_channel_cylinder_resampling_0135(varargin)
%PREPARE_CHANNEL_CYLINDER_RESAMPLING_0135 Build a periodic-x channel with an immersed cylinder.
%
% Reference workflow: MATLAB writes the .smpcd state in ../init/**,
% bash writes params*.kv and launches the C++ executable, MATLAB post-processes.
%
% Usage from repository matlab/ directory:
%   prepare_channel_cylinder_resampling_0135( ...
%       'output', '../init/channel_cylinder_resampling_0135/initial_state_channel_cylinder_0135.smpcd', ...
%       'Lx', 2.0, 'Ly', 1.0, 'Nx', 96, 'Ny', 48, 'gamma', 20, ...
%       'cylinderCx', 0.65, 'cylinderCy', 0.5, 'cylinderR', 0.12, ...
%       'populationMode', 'random', 'populationStd', 6.0, ...
%       'initialProfile', 'poiseuille', 'initialMeanUx', 0.02, ...
%       'kBT', 0.001, 'seed', 1350135, 'makePreview', true);
%
% The state contains only real particles in the fluid part of the channel.
% The wall and immersed-cylinder couplings are configured later by params.kv.

p = inputParser;
p.FunctionName = 'prepare_channel_cylinder_resampling_0135';
addParameter(p, 'output', fullfile('..','init','channel_cylinder_resampling_0135','initial_state_channel_cylinder_0135.smpcd'), @(s) ischar(s) || isstring(s));
addParameter(p, 'layoutCsv', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 2.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 96, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Ny', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kBT', 0.001, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'seed', 1350135, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'cylinderCx', 0.65, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'cylinderCy', 0.5, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'cylinderR', 0.12, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'populationMode', 'random', @(s) ischar(s) || isstring(s));
addParameter(p, 'populationStd', 6.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'populationMin', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'populationMax', 36, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'initialProfile', 'poiseuille', @(s) ischar(s) || isstring(s));
addParameter(p, 'initialMeanUx', 0.02, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'initialMeanUy', 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'removeGlobalThermalDrift', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'makePreview', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

output = char(strrep(string(opt.output), '\\', filesep));
if isempty(char(opt.layoutCsv))
    [outDir, ~, ~] = fileparts(output);
    layoutCsv = fullfile(outDir, 'initial_channel_cylinder_layout_0135.csv');
else
    layoutCsv = char(strrep(string(opt.layoutCsv), '\\', filesep));
end

Lx = double(opt.Lx); Ly = double(opt.Ly);
Nx = double(opt.Nx); Ny = double(opt.Ny);
gamma = double(opt.gamma);
dx = Lx / Nx; dy = Ly / Ny;
cx = double(opt.cylinderCx); cy = double(opt.cylinderCy); R = double(opt.cylinderR);
if cx - R <= 0 || cx + R >= Lx || cy - R <= 0 || cy + R >= Ly
    error('prepare_channel_cylinder_resampling_0135:badCylinder', 'Cylinder must lie strictly inside the channel.');
end

rng(double(opt.seed), 'twister');

[ixGrid, iyGrid] = meshgrid(1:Nx, 1:Ny);
xc = ((ixGrid - 0.5) * dx);
yc = ((iyGrid - 0.5) * dy);
fluidCell = ((xc - cx).^2 + (yc - cy).^2) >= R^2;
fluidIds = find(fluidCell(:));
nFluidCells = numel(fluidIds);
if nFluidCells == 0
    error('prepare_channel_cylinder_resampling_0135:noFluidCells', 'Cylinder masks all cells.');
end

targetTotal = round(nFluidCells * gamma);
mode = lower(strtrim(char(opt.populationMode)));
counts = zeros(Ny, Nx);
switch mode
    case {'exact','exact_per_cell'}
        counts(fluidCell) = round(gamma);
    case {'random','heterogeneous','random_population'}
        raw = round(gamma + double(opt.populationStd) .* randn(nFluidCells, 1));
        raw = max(round(double(opt.populationMin)), min(round(double(opt.populationMax)), raw));
        raw = local_adjust_counts_to_total(raw, targetTotal, round(double(opt.populationMin)), round(double(opt.populationMax)));
        counts(fluidIds) = raw;
    otherwise
        error('prepare_channel_cylinder_resampling_0135:badPopulationMode', 'Unknown populationMode: %s', mode);
end

Np = sum(counts(:));
x = zeros(Np, 1); y = zeros(Np, 1);
vx = zeros(Np, 1); vy = zeros(Np, 1);
type = zeros(Np, 1, 'uint32');
mass = double(opt.mass) * ones(Np, 1);
role = ones(Np, 1, 'uint8'); % Fluid
cellId = zeros(Np, 1);

sigma = sqrt(double(opt.kBT) / double(opt.mass));
profile = lower(strtrim(char(opt.initialProfile)));
idx = 0;
for j = 1:Ny
    for i = 1:Nx
        n = counts(j, i);
        if n <= 0
            continue;
        end
        x0 = (i - 1) * dx;
        y0 = (j - 1) * dy;
        ids = idx + (1:n);
        [xs, ys] = local_sample_cell_outside_circle(n, x0, y0, dx, dy, cx, cy, R);
        x(ids) = xs;
        y(ids) = ys;
        vxMean = local_initial_ux(ys, Ly, double(opt.initialMeanUx), profile);
        vx(ids) = vxMean + sigma * randn(n, 1);
        vy(ids) = double(opt.initialMeanUy) + sigma * randn(n, 1);
        cellId(ids) = i + Nx * (j - 1);
        idx = idx + n;
    end
end

if logical(opt.removeGlobalThermalDrift) && Np > 0
    vx = vx - mean(vx) + local_target_mean_ux(y, Ly, double(opt.initialMeanUx), profile);
    vy = vy - mean(vy) + double(opt.initialMeanUy);
end

state = struct('x', x, 'y', y, 'vx', vx, 'vy', vy, 'type', type, 'mass', mass, 'role', role);

outDir = fileparts(output);
if ~isempty(outDir) && ~isfolder(outDir)
    mkdir(outDir);
end
write_smpcd_state(output, state);

layoutDir = fileparts(layoutCsv);
if ~isempty(layoutDir) && ~isfolder(layoutDir)
    mkdir(layoutDir);
end
T = table();
T.cell = reshape(1:(Nx*Ny), [], 1);
T.ix = reshape(ixGrid.', [], 1);
T.iy = reshape(iyGrid.', [], 1);
T.xc = reshape(xc.', [], 1);
T.yc = reshape(yc.', [], 1);
T.isFluidCell = reshape(fluidCell.', [], 1);
T.nFluid = reshape(counts.', [], 1);
T.mass = T.nFluid * double(opt.mass);
T.distanceToCylinder = sqrt((T.xc - cx).^2 + (T.yc - cy).^2) - R;
writetable(T, layoutCsv);

if logical(opt.makePreview)
    fig = figure('Name', '0135 initial channel cylinder population', 'Visible', 'on'); %#ok<NASGU>
    imagesc(((0:Nx-1)+0.5)*dx, ((0:Ny-1)+0.5)*dy, counts);
    set(gca, 'YDir', 'normal'); axis equal tight; colorbar;
    title('initial cell population, channel cylinder'); xlabel('x'); ylabel('y');
    hold on; local_draw_circle(cx, cy, R, 'k-', 1.5); hold off;
    saveas(gcf, fullfile(layoutDir, 'initial_channel_cylinder_population_0135.png'));
end

info = struct();
info.output = output;
info.layoutCsv = layoutCsv;
info.Np = Np;
info.Nx = Nx;
info.Ny = Ny;
info.gamma = gamma;
info.nFluidCells = nFluidCells;
info.meanNFluidCells = mean(counts(fluidCell));
info.stdNFluidCells = std(double(counts(fluidCell)));
info.minNFluidCells = min(counts(fluidCell));
info.maxNFluidCells = max(counts(fluidCell));
info.cylinderCx = cx;
info.cylinderCy = cy;
info.cylinderR = R;
info.initialProfile = profile;

fprintf('[0135] wrote channel-cylinder initial state: %s\n', output);
fprintf('[0135] grid=%dx%d fluidCells=%d gamma=%g Np=%d Lx=%g Ly=%g kBT=%g\n', Nx, Ny, nFluidCells, gamma, Np, Lx, Ly, double(opt.kBT));
fprintf('[0135] population over fluid cells: mean=%g std=%g min=%g max=%g\n', info.meanNFluidCells, info.stdNFluidCells, info.minNFluidCells, info.maxNFluidCells);
fprintf('[0135] wrote layout CSV: %s\n', layoutCsv);
end

function ux = local_initial_ux(y, Ly, meanUx, profile)
switch profile
    case {'zero','rest'}
        ux = zeros(size(y));
    case {'uniform','flat'}
        ux = meanUx * ones(size(y));
    case {'poiseuille','poiseuille_y','poiseuille_mean'}
        eta = min(max(y ./ Ly, 0), 1);
        ux = 6.0 * meanUx .* eta .* (1.0 - eta);
    otherwise
        error('prepare_channel_cylinder_resampling_0135:badProfile', 'Unknown initialProfile: %s', profile);
end
end

function m = local_target_mean_ux(y, Ly, meanUx, profile)
switch profile
    case {'zero','rest'}
        m = 0.0;
    case {'uniform','flat'}
        m = meanUx;
    case {'poiseuille','poiseuille_y','poiseuille_mean'}
        m = mean(local_initial_ux(y, Ly, meanUx, profile));
    otherwise
        m = meanUx;
end
end

function counts = local_adjust_counts_to_total(counts, targetTotal, nMin, nMax)
counts = counts(:);
delta = targetTotal - sum(counts);
iter = 0;
while delta ~= 0
    iter = iter + 1;
    if iter > 1000000
        error('prepare_channel_cylinder_resampling_0135:adjustFailed', 'Failed to adjust counts to requested total.');
    end
    if delta > 0
        cand = find(counts < nMax);
        if isempty(cand), error('prepare_channel_cylinder_resampling_0135:maxTooLow', 'populationMax too low.'); end
        k = cand(randi(numel(cand)));
        counts(k) = counts(k) + 1;
        delta = delta - 1;
    else
        cand = find(counts > nMin);
        if isempty(cand), error('prepare_channel_cylinder_resampling_0135:minTooHigh', 'populationMin too high.'); end
        k = cand(randi(numel(cand)));
        counts(k) = counts(k) - 1;
        delta = delta + 1;
    end
end
end

function [xs, ys] = local_sample_cell_outside_circle(n, x0, y0, dx, dy, cx, cy, R)
xs = zeros(n,1); ys = zeros(n,1);
cellCenterX = x0 + 0.5 * dx;
cellCenterY = y0 + 0.5 * dy;
for q = 1:n
    ok = false;
    for a = 1:1000
        xt = x0 + dx * rand();
        yt = y0 + dy * rand();
        if (xt - cx)^2 + (yt - cy)^2 >= R^2
            xs(q) = xt; ys(q) = yt; ok = true; break;
        end
    end
    if ~ok
        theta = 2*pi*rand();
        xt = cellCenterX + 0.1 * min(dx,dy) * cos(theta);
        yt = cellCenterY + 0.1 * min(dx,dy) * sin(theta);
        if (xt - cx)^2 + (yt - cy)^2 < R^2
            xt = cellCenterX; yt = cellCenterY;
        end
        xs(q) = min(max(xt, x0 + eps), x0 + dx - eps);
        ys(q) = min(max(yt, y0 + eps), y0 + dy - eps);
    end
end
end

function local_draw_circle(cx, cy, R, style, lw)
th = linspace(0, 2*pi, 256);
plot(cx + R*cos(th), cy + R*sin(th), style, 'LineWidth', lw);
end

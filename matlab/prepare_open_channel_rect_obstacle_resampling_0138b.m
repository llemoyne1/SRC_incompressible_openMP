function info = prepare_open_channel_rect_obstacle_resampling_0138b(varargin)
%PREPARE_OPEN_CHANNEL_RECT_OBSTACLE_RESAMPLING_0138B Build an inlet/outlet channel with a fixed rectangular obstacle.
%
% This is the inlet/outlet-compatible replacement for the 0138 cylinder
% attempt.  The current C++ guard for Q6 + inlet/outlet + immersed solid
% requires a fixed rectangle, hard_cell_density inlet and projection masking.
%
% Usage from repository matlab/ directory:
%   prepare_open_channel_rect_obstacle_resampling_0138b( ...
%       'output', '../init/open_channel_rect_obstacle_resampling_0138b/initial_state_open_channel_rect_obstacle_0138b.smpcd', ...
%       'Lx', 4.0, 'Ly', 1.0, 'Nx', 192, 'Ny', 48, 'gamma', 20, ...
%       'rectXMin', 0.85, 'rectXMax', 1.10, 'rectYMin', 0.38, 'rectYMax', 0.62, ...
%       'populationMode', 'random', 'populationStd', 6.0, ...
%       'initialProfile', 'poiseuille', 'initialMeanUx', 0.05, ...
%       'kBT', 0.001, 'seed', 1380138, 'makePreview', true);

p = inputParser;
p.FunctionName = 'prepare_open_channel_rect_obstacle_resampling_0138b';
addParameter(p, 'output', fullfile('..','init','open_channel_rect_obstacle_resampling_0138b','initial_state_open_channel_rect_obstacle_0138b.smpcd'), @(s) ischar(s) || isstring(s));
addParameter(p, 'layoutCsv', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 4.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 192, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Ny', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kBT', 0.001, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'seed', 1380138, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'rectXMin', 0.85, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'rectXMax', 1.10, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'rectYMin', 0.38, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'rectYMax', 0.62, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'populationMode', 'random', @(s) ischar(s) || isstring(s));
addParameter(p, 'populationStd', 6.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'populationMin', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'populationMax', 36, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'initialProfile', 'poiseuille', @(s) ischar(s) || isstring(s));
addParameter(p, 'initialMeanUx', 0.05, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'initialMeanUy', 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'removeGlobalThermalDrift', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'makePreview', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

output = char(strrep(string(opt.output), '\\', filesep));
if isempty(char(opt.layoutCsv))
    [outDir, ~, ~] = fileparts(output);
    layoutCsv = fullfile(outDir, 'initial_open_channel_rect_obstacle_layout_0138b.csv');
else
    layoutCsv = char(strrep(string(opt.layoutCsv), '\\', filesep));
end

Lx = double(opt.Lx); Ly = double(opt.Ly);
Nx = double(opt.Nx); Ny = double(opt.Ny);
gamma = double(opt.gamma);
dx = Lx / Nx; dy = Ly / Ny;
xMin = double(opt.rectXMin); xMax = double(opt.rectXMax);
yMin = double(opt.rectYMin); yMax = double(opt.rectYMax);
if ~(xMin > 0 && xMax < Lx && yMin > 0 && yMax < Ly && xMin < xMax && yMin < yMax)
    error('prepare_open_channel_rect_obstacle_resampling_0138b:badRectangle', 'Rectangle must lie strictly inside the channel.');
end

rng(double(opt.seed), 'twister');

[ixGrid, iyGrid] = meshgrid(1:Nx, 1:Ny);
xc = ((ixGrid - 0.5) * dx);
yc = ((iyGrid - 0.5) * dy);
solidCell = (xc >= xMin) & (xc <= xMax) & (yc >= yMin) & (yc <= yMax);
fluidCell = ~solidCell;
fluidIds = find(fluidCell(:));
nFluidCells = numel(fluidIds);
if nFluidCells == 0
    error('prepare_open_channel_rect_obstacle_resampling_0138b:noFluidCells', 'Obstacle masks all cells.');
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
        error('prepare_open_channel_rect_obstacle_resampling_0138b:badPopulationMode', 'Unknown populationMode: %s', mode);
end

Np = sum(counts(:));
x = zeros(Np, 1); y = zeros(Np, 1);
vx = zeros(Np, 1); vy = zeros(Np, 1);
type = zeros(Np, 1, 'uint32');
mass = double(opt.mass) * ones(Np, 1);
role = ones(Np, 1, 'uint8');

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
        x(ids) = x0 + dx * rand(n, 1);
        y(ids) = y0 + dy * rand(n, 1);
        vxMean = local_initial_ux(y(ids), Ly, double(opt.initialMeanUx), profile);
        vx(ids) = vxMean + sigma * randn(n, 1);
        vy(ids) = double(opt.initialMeanUy) + sigma * randn(n, 1);
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
T.isSolidCell = reshape(solidCell.', [], 1);
T.nFluid = reshape(counts.', [], 1);
T.mass = T.nFluid * double(opt.mass);
writetable(T, layoutCsv);

if logical(opt.makePreview)
    fig = figure('Name', '0138B initial open-channel rectangle population', 'Visible', 'on'); %#ok<NASGU>
    imagesc(((0:Nx-1)+0.5)*dx, ((0:Ny-1)+0.5)*dy, counts);
    set(gca, 'YDir', 'normal'); axis equal tight; colorbar;
    title('initial cell population, open-channel rectangle'); xlabel('x'); ylabel('y');
    hold on; local_draw_rect(xMin, xMax, yMin, yMax, 'k-', 1.5); hold off;
    saveas(gcf, fullfile(layoutDir, 'initial_open_channel_rect_obstacle_population_0138b.png'));
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
info.rectXMin = xMin; info.rectXMax = xMax; info.rectYMin = yMin; info.rectYMax = yMax;
info.initialProfile = profile;

fprintf('[0138B] wrote open-channel-rectangle initial state: %s\n', output);
fprintf('[0138B] grid=%dx%d fluidCells=%d gamma=%g Np=%d Lx=%g Ly=%g kBT=%g\n', Nx, Ny, nFluidCells, gamma, Np, Lx, Ly, double(opt.kBT));
fprintf('[0138B] population over fluid cells: mean=%g std=%g min=%g max=%g\n', info.meanNFluidCells, info.stdNFluidCells, info.minNFluidCells, info.maxNFluidCells);
fprintf('[0138B] wrote layout CSV: %s\n', layoutCsv);
end

function ux = local_initial_ux(y, Ly, meanUx, profile)
switch profile
    case {'zero','rest'}
        ux = zeros(size(y));
    case {'uniform','flat','plug'}
        ux = meanUx * ones(size(y));
    case {'poiseuille','poiseuille_y','poiseuille_mean'}
        eta = min(max(y ./ Ly, 0), 1);
        ux = 6.0 * meanUx .* eta .* (1.0 - eta);
    otherwise
        error('prepare_open_channel_rect_obstacle_resampling_0138b:badProfile', 'Unknown initialProfile: %s', profile);
end
end

function m = local_target_mean_ux(y, Ly, meanUx, profile)
switch profile
    case {'zero','rest'}
        m = 0.0;
    case {'uniform','flat','plug'}
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
        error('prepare_open_channel_rect_obstacle_resampling_0138b:adjustFailed', 'Failed to adjust counts to requested total.');
    end
    if delta > 0
        cand = find(counts < nMax);
        if isempty(cand), error('prepare_open_channel_rect_obstacle_resampling_0138b:maxTooLow', 'populationMax too low.'); end
        k = cand(randi(numel(cand)));
        counts(k) = counts(k) + 1;
        delta = delta - 1;
    else
        cand = find(counts > nMin);
        if isempty(cand), error('prepare_open_channel_rect_obstacle_resampling_0138b:minTooHigh', 'populationMin too high.'); end
        k = cand(randi(numel(cand)));
        counts(k) = counts(k) - 1;
        delta = delta + 1;
    end
end
end

function local_draw_rect(xMin, xMax, yMin, yMax, style, lw)
plot([xMin xMax xMax xMin xMin], [yMin yMin yMax yMax yMin], style, 'LineWidth', lw);
end

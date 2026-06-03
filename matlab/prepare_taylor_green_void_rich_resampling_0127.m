function state = prepare_taylor_green_void_rich_resampling_0127(varargin)
%PREPARE_TAYLOR_GREEN_VOID_RICH_RESAMPLING_0127 Generate a V2 .smpcd state.
%
% The generated periodic Taylor--Green state contains a deliberately empty
% fluid pocket and a deliberately overloaded rich pocket.  It is intended to
% trigger the OpenMP weighted-resampling extraction/insertion path without
% involving walls, inlets/outlets or immersed solids.
%
% Usage from the repository matlab/ directory:
%
%   cd('matlab');
%   prepare_taylor_green_void_rich_resampling_0127( ...
%       'output', '../init/taylor_green_void_rich_resampling_0127/initial_state_tg_void_rich_0127.smpcd');
%
% Role convention written to the V2 .smpcd state:
%   0 = Inactive
%   1 = Fluid
%   2 = Latent
%
% By default no Latent particles are added.  The void pocket is created by
% relocating the Fluid particles originally present in the void-cell block to
% the rich-cell block.  Therefore the number of active Fluid particles is
% unchanged, the void block has zero Fluid particles, and the rich block is
% overpopulated.

p = inputParser;
p.FunctionName = 'prepare_taylor_green_void_rich_resampling_0127';
addParameter(p, 'output', fullfile('..','init','taylor_green_void_rich_resampling_0127','initial_state_tg_void_rich_0127.smpcd'), @(s) ischar(s) || isstring(s));
addParameter(p, 'layoutCsv', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 32, @(x) isnumeric(x) && isscalar(x) && x >= 4 && abs(x-round(x)) < eps);
addParameter(p, 'Ny', 32, @(x) isnumeric(x) && isscalar(x) && x >= 4 && abs(x-round(x)) < eps);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'flowAmplitude', 0.08, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'kxMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'kyMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'kBT', 0.001, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'seed', 1270127, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'voidIxRange', [], @(x) isnumeric(x) && (isempty(x) || numel(x)==2));
addParameter(p, 'voidIyRange', [], @(x) isnumeric(x) && (isempty(x) || numel(x)==2));
addParameter(p, 'richIxRange', [], @(x) isnumeric(x) && (isempty(x) || numel(x)==2));
addParameter(p, 'richIyRange', [], @(x) isnumeric(x) && (isempty(x) || numel(x)==2));
addParameter(p, 'latentPerVoidCell', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0 && abs(x-round(x)) < eps);
addParameter(p, 'latentMass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'makePreview', false, @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;

Nx = double(opt.Nx);
Ny = double(opt.Ny);
gamma = double(opt.gamma);
Lx = double(opt.Lx);
Ly = double(opt.Ly);
dx = Lx / Nx;
dy = Ly / Ny;

voidIx = default_range(opt.voidIxRange, max(1, floor(0.22*Nx)), max(1, floor(0.22*Nx)) + max(1, floor(0.12*Nx)) - 1, Nx);
voidIy = default_range(opt.voidIyRange, max(1, floor(0.22*Ny)), max(1, floor(0.22*Ny)) + max(1, floor(0.12*Ny)) - 1, Ny);
richIx = default_range(opt.richIxRange, max(1, floor(0.66*Nx)), max(1, floor(0.66*Nx)) + max(1, floor(0.12*Nx)) - 1, Nx);
richIy = default_range(opt.richIyRange, max(1, floor(0.66*Ny)), max(1, floor(0.66*Ny)) + max(1, floor(0.12*Ny)) - 1, Ny);

if ranges_overlap_2d(voidIx, voidIy, richIx, richIy)
    error('prepare_taylor_green_void_rich_resampling_0127:overlap', ...
        'Void and rich cell blocks must not overlap.');
end

% Build the clean exact-per-cell Taylor--Green state using the repository
% reference MATLAB generator, then rewrite it as V2 after imposing pockets.
state = generate_smpcd_state_taylor_green( ...
    'output', '', ...
    'Lx', Lx, 'Ly', Ly, ...
    'Nx', Nx, 'Ny', Ny, ...
    'gamma', gamma, ...
    'flowAmplitude', opt.flowAmplitude, ...
    'kxMode', opt.kxMode, 'kyMode', opt.kyMode, ...
    'kBT', opt.kBT, ...
    'mass', opt.mass, ...
    'type', uint32(0), ...
    'seed', opt.seed, ...
    'positionMode', 'uniform_per_cell', ...
    'removeMeanMomentum', false);

n0 = numel(state.x);
state.role = ones(n0, 1, 'uint8'); % all base particles are Fluid

cellIx = min(max(floor(double(state.x(:)) / dx) + 1, 1), Nx);
cellIy = min(max(floor(double(state.y(:)) / dy) + 1, 1), Ny);
voidMask = cellIx >= voidIx(1) & cellIx <= voidIx(2) & cellIy >= voidIy(1) & cellIy <= voidIy(2);
voidParticles = find(voidMask);

richCells = make_cell_list(richIx, richIy);
if isempty(voidParticles)
    error('prepare_taylor_green_void_rich_resampling_0127:noVoidParticles', ...
        'The selected void block contains no particles.');
end
if isempty(richCells)
    error('prepare_taylor_green_void_rich_resampling_0127:noRichCells', ...
        'The selected rich block is empty.');
end

rng(double(opt.seed) + 127, 'twister');
for q = 1:numel(voidParticles)
    i = voidParticles(q);
    c = richCells(1 + mod(q - 1, size(richCells,1)), :);
    state.x(i) = (c(1) - 1 + rand()) * dx;
    state.y(i) = (c(2) - 1 + rand()) * dy;
end

% Recompute velocities consistently at final positions.
[state.vx, state.vy] = local_taylor_green_velocity( ...
    state.x, state.y, Lx, Ly, opt.flowAmplitude, opt.kxMode, opt.kyMode);
if opt.kBT > 0
    sigma = sqrt(opt.kBT / opt.mass);
    rng(double(opt.seed) + 128, 'twister');
    state.vx = state.vx + sigma * randn(numel(state.x),1);
    state.vy = state.vy + sigma * randn(numel(state.y),1);
end

% Optional dormant latent particles in the void block. They are useful for a
% later wet/dry activation validation, but default to zero for the pure
% void/rich recycling case.
nLatent = round(double(opt.latentPerVoidCell)) * numel(voidIx(1):voidIx(2)) * numel(voidIy(1):voidIy(2));
if nLatent > 0
    latentX = zeros(nLatent,1);
    latentY = zeros(nLatent,1);
    latentVx = zeros(nLatent,1);
    latentVy = zeros(nLatent,1);
    latentMass = repmat(double(opt.latentMass), nLatent, 1);
    latentType = repmat(uint32(0), nLatent, 1);
    latentRole = repmat(uint8(2), nLatent, 1);
    voidCells = make_cell_list(voidIx, voidIy);
    rng(double(opt.seed) + 129, 'twister');
    for q = 1:nLatent
        c = voidCells(1 + mod(q - 1, size(voidCells,1)), :);
        latentX(q) = (c(1) - 1 + rand()) * dx;
        latentY(q) = (c(2) - 1 + rand()) * dy;
    end
    [latentVx, latentVy] = local_taylor_green_velocity( ...
        latentX, latentY, Lx, Ly, opt.flowAmplitude, opt.kxMode, opt.kyMode);

    state.x = [state.x(:); latentX];
    state.y = [state.y(:); latentY];
    state.vx = [state.vx(:); latentVx];
    state.vy = [state.vy(:); latentVy];
    state.type = [uint32(state.type(:)); latentType];
    state.mass = [double(state.mass(:)); latentMass];
    state.role = [uint8(state.role(:)); latentRole];
else
    state.x = state.x(:);
    state.y = state.y(:);
    state.vx = state.vx(:);
    state.vy = state.vy(:);
    state.type = uint32(state.type(:));
    state.mass = double(state.mass(:));
    state.role = uint8(state.role(:));
end

% Remove global mean momentum on Fluid particles only.
fluid = state.role == uint8(1);
M = sum(state.mass(fluid));
state.vx(fluid) = state.vx(fluid) - sum(state.mass(fluid).*state.vx(fluid)) / M;
state.vy(fluid) = state.vy(fluid) - sum(state.mass(fluid).*state.vy(fluid)) / M;

state.metadata.generator = 'prepare_taylor_green_void_rich_resampling_0127';
state.metadata.voidIxRange = voidIx;
state.metadata.voidIyRange = voidIy;
state.metadata.richIxRange = richIx;
state.metadata.richIyRange = richIy;
state.metadata.latentPerVoidCell = opt.latentPerVoidCell;

output = char(opt.output);
if ~isempty(output)
    outDir = fileparts(output);
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end
    write_smpcd_state(output, state);
end

layoutCsv = char(opt.layoutCsv);
if isempty(layoutCsv) && ~isempty(output)
    [outDir,~,~] = fileparts(output);
    layoutCsv = fullfile(outDir, 'initial_void_rich_layout_0127.csv');
end
if ~isempty(layoutCsv)
    layoutDir = fileparts(layoutCsv);
    if ~isempty(layoutDir) && ~isfolder(layoutDir)
        mkdir(layoutDir);
    end
    write_layout_csv(layoutCsv, state, Nx, Ny, Lx, Ly, voidIx, voidIy, richIx, richIy);
end

if opt.makePreview
    make_preview_figure(state, Nx, Ny, Lx, Ly, voidIx, voidIy, richIx, richIy, output);
end

counts = count_layout(state, Nx, Ny, Lx, Ly, voidIx, voidIy, richIx, richIy);
fprintf('Prepared Taylor--Green void/rich resampling state 0127:\n');
fprintf('  output        : %s\n', output);
fprintf('  grid          : %d x %d, gamma=%d\n', Nx, Ny, gamma);
fprintf('  particles     : total=%d fluid=%d latent=%d inactive=%d\n', ...
    numel(state.x), sum(state.role==1), sum(state.role==2), sum(state.role==0));
fprintf('  void cells    : ix=[%d,%d], iy=[%d,%d], fluid particles=%d\n', ...
    voidIx(1), voidIx(2), voidIy(1), voidIy(2), counts.voidFluid);
fprintf('  rich cells    : ix=[%d,%d], iy=[%d,%d], fluid particles=%d\n', ...
    richIx(1), richIx(2), richIy(1), richIy(2), counts.richFluid);
fprintf('  moved fluid particles from void to rich: %d\n', numel(voidParticles));
fprintf('  layout csv    : %s\n', layoutCsv);
end

function r = default_range(inputRange, a, b, maxVal)
if isempty(inputRange)
    r = [a, b];
else
    r = round(double(inputRange(:).'));
end
r(1) = max(1, min(maxVal, r(1)));
r(2) = max(1, min(maxVal, r(2)));
if r(2) < r(1)
    r = fliplr(r);
end
end

function tf = ranges_overlap_2d(ax, ay, bx, by)
tf = ax(1) <= bx(2) && bx(1) <= ax(2) && ay(1) <= by(2) && by(1) <= ay(2);
end

function cells = make_cell_list(ixRange, iyRange)
[ix, iy] = ndgrid(ixRange(1):ixRange(2), iyRange(1):iyRange(2));
cells = [ix(:), iy(:)];
end

function [vx, vy] = local_taylor_green_velocity(x, y, Lx, Ly, U0, kxMode, kyMode)
phaseX = 2*pi*double(kxMode)*double(x(:))/double(Lx);
phaseY = 2*pi*double(kyMode)*double(y(:))/double(Ly);
vx = double(U0) .* sin(phaseX) .* cos(phaseY);
vy = -double(U0) .* cos(phaseX) .* sin(phaseY);
end

function write_layout_csv(filename, state, Nx, Ny, Lx, Ly, voidIx, voidIy, richIx, richIy)
dx = Lx / Nx;
dy = Ly / Ny;
ix = min(max(floor(double(state.x(:)) / dx) + 1, 1), Nx);
iy = min(max(floor(double(state.y(:)) / dy) + 1, 1), Ny);
role = uint8(state.role(:));
mass = double(state.mass(:));

cellId = (1:Nx*Ny).';
cellIx = zeros(Nx*Ny,1);
cellIy = zeros(Nx*Ny,1);
zone = strings(Nx*Ny,1);
Nfluid = zeros(Nx*Ny,1);
Nlatent = zeros(Nx*Ny,1);
Ninactive = zeros(Nx*Ny,1);
Mfluid = zeros(Nx*Ny,1);

for j = 1:Ny
    for i = 1:Nx
        k = i + (j-1)*Nx;
        cellIx(k) = i;
        cellIy(k) = j;
        if i >= voidIx(1) && i <= voidIx(2) && j >= voidIy(1) && j <= voidIy(2)
            zone(k) = "void";
        elseif i >= richIx(1) && i <= richIx(2) && j >= richIy(1) && j <= richIy(2)
            zone(k) = "rich";
        else
            zone(k) = "background";
        end
        inCell = ix == i & iy == j;
        Nfluid(k) = sum(inCell & role == uint8(1));
        Nlatent(k) = sum(inCell & role == uint8(2));
        Ninactive(k) = sum(inCell & role == uint8(0));
        Mfluid(k) = sum(mass(inCell & role == uint8(1)));
    end
end

T = table(cellId, cellIx, cellIy, zone, Nfluid, Mfluid, Nlatent, Ninactive);
writetable(T, filename);
end

function counts = count_layout(state, Nx, Ny, Lx, Ly, voidIx, voidIy, richIx, richIy)
dx = Lx / Nx;
dy = Ly / Ny;
ix = min(max(floor(double(state.x(:)) / dx) + 1, 1), Nx);
iy = min(max(floor(double(state.y(:)) / dy) + 1, 1), Ny);
role = uint8(state.role(:));
void = ix >= voidIx(1) & ix <= voidIx(2) & iy >= voidIy(1) & iy <= voidIy(2);
rich = ix >= richIx(1) & ix <= richIx(2) & iy >= richIy(1) & iy <= richIy(2);
counts = struct();
counts.voidFluid = sum(void & role == uint8(1));
counts.richFluid = sum(rich & role == uint8(1));
end

function make_preview_figure(state, Nx, Ny, Lx, Ly, voidIx, voidIy, richIx, richIy, output)
layoutCsv = tempname;
write_layout_csv(layoutCsv, state, Nx, Ny, Lx, Ly, voidIx, voidIy, richIx, richIy);
T = readtable(layoutCsv);
delete(layoutCsv);
N = reshape(T.Nfluid, [Nx, Ny]).';
fig = figure('Name','TG void/rich initial population 0127','Color','w');
imagesc((0.5:Nx-0.5)*Lx/Nx, (0.5:Ny-0.5)*Ly/Ny, N);
axis image; set(gca,'YDir','normal'); colorbar;
xlabel('x'); ylabel('y'); title('initial Fluid population per cell');
hold on;
rectangle('Position', [(voidIx(1)-1)*Lx/Nx, (voidIy(1)-1)*Ly/Ny, numel(voidIx(1):voidIx(2))*Lx/Nx, numel(voidIy(1):voidIy(2))*Ly/Ny], 'EdgeColor','w', 'LineWidth',1.5);
rectangle('Position', [(richIx(1)-1)*Lx/Nx, (richIy(1)-1)*Ly/Ny, numel(richIx(1):richIx(2))*Lx/Nx, numel(richIy(1):richIy(2))*Ly/Ny], 'EdgeColor','k', 'LineWidth',1.5);
if ~isempty(output)
    [outDir,~,~] = fileparts(output);
    if ~isempty(outDir)
        saveas(fig, fullfile(outDir, 'initial_void_rich_population_0127.png'));
    end
end
end

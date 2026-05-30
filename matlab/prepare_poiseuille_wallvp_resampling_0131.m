function info = prepare_poiseuille_wallvp_resampling_0131(varargin)
%PREPARE_POISEUILLE_WALLVP_RESAMPLING_0131 Build a periodic-x channel state.
%
% Usage from the repository matlab/ directory:
%   prepare_poiseuille_wallvp_resampling_0131( ...
%       'output', '../init/poiseuille_wallvp_resampling_0131/initial_state_poiseuille_wallvp_0131.smpcd', ...
%       'Nx', 64, 'Ny', 32, 'gamma', 20, ...
%       'Lx', 2.0, 'Ly', 1.0, 'kBT', 0.001, 'seed', 1310131);
%
% The output is a V2 .smpcd state with all particles role=Fluid.  The C++
% executable does not generate initial states; this MATLAB preparer is the
% reference input-generation path for the 0131 Poiseuille validation.

p = inputParser;
p.FunctionName = 'prepare_poiseuille_wallvp_resampling_0131';
addParameter(p, 'output', fullfile('..','init','poiseuille_wallvp_resampling_0131','initial_state_poiseuille_wallvp_0131.smpcd'), @(s) ischar(s) || isstring(s));
addParameter(p, 'layoutCsv', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 2.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Ny', 32, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kBT', 0.001, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'seed', 1310131, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'initialCenterUx', 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'initialMeanUy', 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'removeGlobalThermalDrift', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

output = char(strrep(string(opt.output), '\\', filesep));
if isempty(char(opt.layoutCsv))
    [outDir, ~, ~] = fileparts(output);
    layoutCsv = fullfile(outDir, 'initial_poiseuille_layout_0131.csv');
else
    layoutCsv = char(strrep(string(opt.layoutCsv), '\\', filesep));
end

Lx = double(opt.Lx);
Ly = double(opt.Ly);
Nx = double(opt.Nx);
Ny = double(opt.Ny);
gamma = double(opt.gamma);
Np = Nx * Ny * gamma;
dx = Lx / Nx;
dy = Ly / Ny;

rng(double(opt.seed), 'twister');

x = zeros(Np, 1);
y = zeros(Np, 1);
vx = zeros(Np, 1);
vy = zeros(Np, 1);
type = zeros(Np, 1, 'uint32');
mass = double(opt.mass) * ones(Np, 1);
role = ones(Np, 1, 'uint8'); % Fluid

sigma = sqrt(double(opt.kBT) / double(opt.mass));
idx = 0;
cellId = zeros(Np, 1);
for j = 1:Ny
    y0 = (j - 1) * dy;
    for i = 1:Nx
        x0 = (i - 1) * dx;
        ids = idx + (1:gamma);
        x(ids) = x0 + dx * rand(gamma, 1);
        y(ids) = y0 + dy * rand(gamma, 1);
        yc = y(ids);
        if opt.initialCenterUx ~= 0
            profile = 4.0 * double(opt.initialCenterUx) .* (yc ./ Ly) .* (1.0 - yc ./ Ly);
        else
            profile = zeros(gamma, 1);
        end
        vx(ids) = profile + sigma * randn(gamma, 1);
        vy(ids) = double(opt.initialMeanUy) + sigma * randn(gamma, 1);
        cellId(ids) = i + Nx * (j - 1);
        idx = idx + gamma;
    end
end

if logical(opt.removeGlobalThermalDrift)
    vx = vx - mean(vx) + mean(4.0 * double(opt.initialCenterUx) .* (y ./ Ly) .* (1.0 - y ./ Ly));
    vy = vy - mean(vy) + double(opt.initialMeanUy);
end

state = struct();
state.x = x;
state.y = y;
state.vx = vx;
state.vy = vy;
state.type = type;
state.mass = mass;
state.role = role;

outDir = fileparts(output);
if ~isempty(outDir) && ~isfolder(outDir)
    mkdir(outDir);
end
write_smpcd_state(output, state);

layoutDir = fileparts(layoutCsv);
if ~isempty(layoutDir) && ~isfolder(layoutDir)
    mkdir(layoutDir);
end
[ix, iy] = meshgrid(1:Nx, 1:Ny);
T = table();
T.cell = reshape(1:(Nx*Ny), [], 1);
T.ix = reshape(ix.', [], 1);
T.iy = reshape(iy.', [], 1);
T.xc = ((T.ix - 0.5) * dx);
T.yc = ((T.iy - 0.5) * dy);
T.nFluid = gamma * ones(height(T), 1);
T.mass = gamma * double(opt.mass) * ones(height(T), 1);
writetable(T, layoutCsv);

info = struct();
info.output = output;
info.layoutCsv = layoutCsv;
info.Np = Np;
info.Nx = Nx;
info.Ny = Ny;
info.gamma = gamma;
info.Lx = Lx;
info.Ly = Ly;
info.kBT = double(opt.kBT);
info.initialMeanUx = mean(vx);
info.initialMeanUy = mean(vy);

fprintf('[0131] wrote Poiseuille wallVP initial state: %s\n', output);
fprintf('[0131] grid=%dx%d gamma=%g Np=%d Lx=%g Ly=%g kBT=%g\n', Nx, Ny, gamma, Np, Lx, Ly, double(opt.kBT));
fprintf('[0131] wrote layout CSV: %s\n', layoutCsv);
end

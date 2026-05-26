function state = generate_backward_step_exact_fluid_state_0072(varargin)
%GENERATE_BACKWARD_STEP_EXACT_FLUID_STATE_0072 Exact-per-fluid-cell backward-step state.
%
% This helper differs from generate_backward_step_state by placing exactly gamma
% particles in every non-solid cell and no particles in cells whose centers lie
% inside the rectangular bottom obstacle. It is intended for hard-inlet/open-outlet
% budget tests where the reference fluid-cell occupancy is gamma.
%
% Example from repository root:
%   cd matlab
%   generate_backward_step_exact_fluid_state_0072( ...
%       'output','../initial_state_backward_step_exact_fluid_48x24_g20_kbt0p0025_ux0p05.smpcd', ...
%       'Lx',2,'Ly',1,'Nx',48,'Ny',24,'gamma',20,'kBT',0.0025,'Ux',0.05);
%   cd ..

p = inputParser;
p.FunctionName = 'generate_backward_step_exact_fluid_state_0072';
addParameter(p, 'output', '../initial_state_backward_step_exact_fluid_48x24_g20_kbt0p0025_ux0p05.smpcd', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 2.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'Ny', 24, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'kBT', 0.0025, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'type', uint32(0), @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'seed', 12345, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'Ux', 0.05, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'Uy', 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'xMin', 0.25, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'xMax', 0.65, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'yMin', 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'yMax', 0.50, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'removeThermalMean', true, @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;

if ~(opt.xMax > opt.xMin && opt.yMax > opt.yMin)
    error('generate_backward_step_exact_fluid_state_0072:badRectangle', ...
        'Rectangle exclusion requires xMax>xMin and yMax>yMin.');
end

rng(double(opt.seed), 'twister');

Nx = double(opt.Nx);
Ny = double(opt.Ny);
gamma = double(opt.gamma);
dx = opt.Lx / Nx;
dy = opt.Ly / Ny;

xc = ((0:Nx-1) + 0.5) * dx;
yc = ((0:Ny-1) + 0.5) * dy;
[Xc, Yc] = meshgrid(xc, yc);
solidCell = Xc >= opt.xMin & Xc <= opt.xMax & Yc >= opt.yMin & Yc <= opt.yMax;
fluidCell = ~solidCell;
[iyFluid, ixFluid] = find(fluidCell); % MATLAB row=iy, col=ix, both one-based.

nFluidCells = numel(ixFluid);
Np = nFluidCells * gamma;
x = zeros(Np, 1);
y = zeros(Np, 1);

cursor = 1;
for c = 1:nFluidCells
    ix0 = ixFluid(c) - 1;
    iy0 = iyFluid(c) - 1;
    ids = cursor:(cursor + gamma - 1);
    x(ids) = (ix0 + rand(gamma, 1)) * dx;
    y(ids) = (iy0 + rand(gamma, 1)) * dy;
    cursor = cursor + gamma;
end

sigma = sqrt(opt.kBT / opt.mass);
vx = opt.Ux + sigma * randn(Np, 1);
vy = opt.Uy + sigma * randn(Np, 1);
if opt.removeThermalMean && Np > 0
    vx = vx - (mean(vx) - opt.Ux);
    vy = vy - (mean(vy) - opt.Uy);
end

state = struct();
state.x = x;
state.y = y;
state.vx = vx;
state.vy = vy;
state.type = repmat(uint32(opt.type), Np, 1);
state.mass = repmat(double(opt.mass), Np, 1);

if strlength(string(opt.output)) > 0
    write_smpcd_state(char(opt.output), state);
end

fprintf('[generate_backward_step_exact_fluid_state_0072] wrote %s\n', char(opt.output));
fprintf('  grid              : %d x %d\n', Nx, Ny);
fprintf('  solid cells       : %d\n', nnz(solidCell));
fprintf('  fluid cells       : %d\n', nFluidCells);
fprintf('  gamma             : %d\n', gamma);
fprintf('  particles         : %d\n', Np);
fprintf('  mean(vx), mean(vy): %.12g, %.12g\n', mean(vx), mean(vy));
fprintf('  obstacle          : [%g,%g] x [%g,%g]\n', opt.xMin, opt.xMax, opt.yMin, opt.yMax);
end

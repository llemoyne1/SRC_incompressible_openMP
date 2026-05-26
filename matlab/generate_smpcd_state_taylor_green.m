function state = generate_smpcd_state_taylor_green(varargin)
%GENERATE_SMPCD_STATE_TAYLOR_GREEN Generate a periodic Taylor--Green SRC/MPCD state.
%
%   state = generate_smpcd_state_taylor_green('output','initial_state_tg.smpcd', ...)
%
%   The imposed mean velocity is
%
%       u_x = U0 sin(2*pi*kx*x/Lx) cos(2*pi*ky*y/Ly)
%       u_y =-U0 cos(2*pi*kx*x/Lx) sin(2*pi*ky*y/Ly)
%
%   Optional Maxwellian thermal noise with temperature kBT is added on top of
%   the mean Taylor--Green field. The global mean momentum is removed by
%   default, without changing the spatially varying part of the field.

p = inputParser;
p.FunctionName = 'generate_smpcd_state_taylor_green';
addParameter(p, 'output', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Ny', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'flowAmplitude', 0.05, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'kxMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'kyMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'kBT', 0.01, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'type', uint32(0), @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'seed', 12345, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'positionMode', 'uniform_per_cell', @(s) ischar(s) || isstring(s));
addParameter(p, 'removeMeanMomentum', true, @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;

rng(double(opt.seed), 'twister');

Nx = double(opt.Nx);
Ny = double(opt.Ny);
gamma = double(opt.gamma);
Np = Nx * Ny * gamma;
dx = opt.Lx / Nx;
dy = opt.Ly / Ny;

positionMode = char(opt.positionMode);
switch positionMode
    case 'uniform_per_cell'
        [ix, iy] = ndgrid(0:Nx-1, 0:Ny-1);
        cellIx = repelem(ix(:), gamma);
        cellIy = repelem(iy(:), gamma);
        x = (cellIx + rand(Np,1)) * dx;
        y = (cellIy + rand(Np,1)) * dy;
    case 'uniform_random'
        x = opt.Lx * rand(Np,1);
        y = opt.Ly * rand(Np,1);
    otherwise
        error('generate_smpcd_state_taylor_green:badPositionMode', ...
            'Unknown positionMode: %s', positionMode);
end

kx = double(opt.kxMode);
ky = double(opt.kyMode);
phaseX = 2*pi*kx*x/opt.Lx;
phaseY = 2*pi*ky*y/opt.Ly;

vx = opt.flowAmplitude .* sin(phaseX) .* cos(phaseY);
vy = -opt.flowAmplitude .* cos(phaseX) .* sin(phaseY);

if opt.kBT > 0
    sigma = sqrt(opt.kBT / opt.mass);
    vx = vx + sigma * randn(Np,1);
    vy = vy + sigma * randn(Np,1);
end

type = repmat(uint32(opt.type), Np, 1);
mass = repmat(double(opt.mass), Np, 1);

if opt.removeMeanMomentum
    M = sum(mass);
    vx = vx - sum(mass .* vx) / M;
    vy = vy - sum(mass .* vy) / M;
end

state = struct();
state.x = x;
state.y = y;
state.vx = vx;
state.vy = vy;
state.type = type;
state.mass = mass;
state.metadata = struct( ...
    'flow', 'TaylorGreen', ...
    'flowAmplitude', opt.flowAmplitude, ...
    'kxMode', kx, ...
    'kyMode', ky, ...
    'kBT', opt.kBT);

if strlength(string(opt.output)) > 0
    write_smpcd_state(char(opt.output), state);
end
end

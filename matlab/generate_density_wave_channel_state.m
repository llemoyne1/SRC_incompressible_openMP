function state = generate_density_wave_channel_state(varargin)
%GENERATE_DENSITY_WAVE_CHANNEL_STATE Generate a channel state with a low-k density wave.
%
% Intended to be launched from matlab/. By default the state is written one
% level above matlab/, where the C++ executable is launched.
%
% The particle count per cell is deterministic and varies as
%
%   Ncell(x) ~= gamma * (1 + amplitude * cos(2*pi*mode*x/Lx)).
%
% The total number of particles is corrected exactly to Nx*Ny*gamma.

p = inputParser;
p.FunctionName = 'generate_density_wave_channel_state';
addParameter(p, 'output', '../initial_state_density_wave_x_32x32_g40_eps0p15.smpcd', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 32, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ny', 32, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'gamma', 40, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'densityAmplitude', 0.15, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'modeX', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kBT', 0.01, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'type', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'seed', 12345, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'removeMeanMomentum', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

rng(double(opts.seed), 'twister');

Nx = round(opts.Nx);
Ny = round(opts.Ny);
gamma = round(opts.gamma);
NpTarget = Nx * Ny * gamma;
dx = opts.Lx / Nx;
dy = opts.Ly / Ny;

xc = ((0:Nx-1) + 0.5) * dx;
targetX = gamma * (1.0 + opts.densityAmplitude * cos(2*pi*opts.modeX*xc/opts.Lx));
rawCounts = repmat(targetX(:).', Ny, 1);
baseCounts = floor(rawCounts);
frac = rawCounts - baseCounts;
counts = baseCounts;

residual = NpTarget - sum(counts(:));
if residual > 0
    [~, order] = sort(frac(:), 'descend');
    for k = 1:residual
        idx = order(mod(k-1, numel(order)) + 1);
        counts(idx) = counts(idx) + 1;
    end
elseif residual < 0
    [~, order] = sort(frac(:), 'ascend');
    remaining = -residual;
    kk = 1;
    while remaining > 0
        idx = order(mod(kk-1, numel(order)) + 1);
        if counts(idx) > 1
            counts(idx) = counts(idx) - 1;
            remaining = remaining - 1;
        end
        kk = kk + 1;
        if kk > 10*numel(order) && remaining > 0
            error('generate_density_wave_channel_state:countCorrectionFailed', ...
                'Could not remove enough particles while keeping positive cell counts.');
        end
    end
end

Np = sum(counts(:));
x = zeros(Np, 1);
y = zeros(Np, 1);
pos = 1;
for jy = 1:Ny
    for ix = 1:Nx
        n = counts(jy, ix);
        ids = pos:(pos+n-1);
        x(ids) = ((ix-1) + rand(n,1)) * dx;
        y(ids) = ((jy-1) + rand(n,1)) * dy;
        pos = pos + n;
    end
end

sigma = sqrt(opts.kBT / opts.mass);
vx = sigma * randn(Np,1);
vy = sigma * randn(Np,1);
mass = repmat(double(opts.mass), Np, 1);
type = repmat(uint32(opts.type), Np, 1);

if opts.removeMeanMomentum
    M = sum(mass);
    vx = vx - sum(mass .* vx) / M;
    vy = vy - sum(mass .* vy) / M;
end

state = struct('x', x, 'y', y, 'vx', vx, 'vy', vy, 'type', type, 'mass', mass);
write_smpcd_state(char(opts.output), state);

modeAmplitude = local_density_mode_from_counts(counts, opts.modeX);
fprintf('[generate_density_wave_channel_state] wrote %s\n', char(opts.output));
fprintf('  grid=%dx%d gamma=%d Np=%d densityAmplitude=%.6g modeX=%d\n', ...
    Nx, Ny, gamma, Np, opts.densityAmplitude, opts.modeX);
fprintf('  cell count min/mean/max = %g / %.6g / %g\n', min(counts(:)), mean(counts(:)), max(counts(:)));
fprintf('  measured count cosine mode amplitude = %.6g particles/cell\n', modeAmplitude);
end

function amp = local_density_mode_from_counts(N, modeX)
[Ny, Nx] = size(N);
x = ((0:Nx-1) + 0.5) / Nx;
basis = cos(2*pi*modeX*x);
B = repmat(basis, Ny, 1);
dN = N - mean(N(:));
amp = sum(dN(:).*B(:)) / sum(B(:).^2);
end

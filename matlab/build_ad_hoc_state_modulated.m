function [x, v, type, r0, info] = build_ad_hoc_state_modulated(params, varargin)
%BUILD_AD_HOC_STATE_MODULATED Generate an ad-hoc nonuniform initial state.
%
% The particle count per cell is drawn from a smooth deterministic weight map
% so that tranche 2 can exercise sparse and/or dense redistribution.

p = inputParser;
p.addParameter('seed', 1, @(z) isnumeric(z) && isscalar(z));
p.addParameter('amp', 0.35, @(z) isnumeric(z) && isscalar(z));
p.addParameter('mode', 'sinx', @(s) ischar(s) || isstring(s));
p.addParameter('zeroMeanVelocity', true, @(b) islogical(b) || isnumeric(b));
p.parse(varargin{:});
opt = p.Results;

rng(double(opt.seed), 'twister');
Nx = params.Nx; Ny = params.Ny; Nc = Nx * Ny;
aX = params.Lx / Nx;
aY = params.Ly / Ny;

[ixGrid, iyGrid] = meshgrid(1:Nx, 1:Ny);
mode = lower(char(string(opt.mode)));
switch mode
    case 'sinx'
        w = 1 + opt.amp * cos(2*pi*((ixGrid - 0.5)/Nx));
    case 'siny'
        w = 1 + opt.amp * cos(2*pi*((iyGrid - 0.5)/Ny));
    case 'checker'
        w = 1 + opt.amp * cos(2*pi*((ixGrid - 0.5)/Nx)) .* cos(2*pi*((iyGrid - 0.5)/Ny));
    otherwise
        error('Unknown modulation mode: %s', mode);
end
w = max(w, 1e-12);
w = w / sum(w(:));

nTarget = params.n;
raw = nTarget * w(:);
counts = floor(raw);
rem = nTarget - sum(counts);
if rem > 0
    frac = raw - counts;
    [~, ord] = sort(frac, 'descend');
    counts(ord(1:rem)) = counts(ord(1:rem)) + 1;
end
assert(sum(counts) == nTarget, 'Invalid particle allocation.');

x = zeros(nTarget, 2);
v = sqrt(params.kBT) * randn(nTarget, 2);
type = zeros(nTarget, 1, 'uint8');

k = 0;
for ix = 1:Nx
    for iy = 1:Ny
        c = iy + Ny*(ix-1);
        nHere = counts(c);
        if nHere <= 0
            continue;
        end
        ids = (k+1):(k+nHere);
        x0 = (ix - 1) * aX;
        y0 = (iy - 1) * aY;
        x(ids,1) = x0 + aX * rand(nHere,1);
        x(ids,2) = y0 + aY * rand(nHere,1);
        k = k + nHere;
    end
end
assert(k == nTarget, 'Particle filling mismatch.');

if opt.zeroMeanVelocity
    v(:,1) = v(:,1) - mean(v(:,1));
    v(:,2) = v(:,2) - mean(v(:,2));
end
r0 = x;

info = struct();
info.mode = mode;
info.amp = opt.amp;
info.counts = reshape(counts, [Ny, Nx]);
info.meanCount = mean(counts);
info.minCount = min(counts);
info.maxCount = max(counts);
end

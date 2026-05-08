function [xRef, vRef, xRed, vRed, type, r0, info] = build_ad_hoc_ref_red_states(params, varargin)
%BUILD_AD_HOC_REF_RED_STATES Build an ad hoc pair of states for liquid closure.
% ref is a modulated but smooth state; red is obtained by relocating a
% controlled fraction of particles to neighboring cells while keeping the
% same particle count and almost the same global velocity statistics.

p = inputParser;
p.addParameter('seed', 1, @(z) isnumeric(z) && isscalar(z));
p.addParameter('amp', 0.25, @(z) isnumeric(z) && isscalar(z));
p.addParameter('moveFrac', 0.08, @(z) isnumeric(z) && isscalar(z) && z >= 0 && z <= 1);
p.addParameter('mode', 'checker', @(s) ischar(s) || isstring(s));
p.addParameter('velocityBias', 0.05, @(z) isnumeric(z) && isscalar(z));
p.parse(varargin{:});
opt = p.Results;

[xRef, vRef, type, r0, initInfo] = build_ad_hoc_state_modulated(params, ...
    'seed', opt.seed, 'amp', opt.amp, 'mode', opt.mode, 'zeroMeanVelocity', true);

rng(double(opt.seed) + 12345, 'twister');
Nx = params.Nx; Ny = params.Ny;
aX = params.Lx / Nx;
aY = params.Ly / Ny;
n = params.n;

xRed = xRef;
vRed = vRef;

nMove = max(1, round(opt.moveFrac * n));
moveIds = randperm(n, nMove);

for kk = 1:nMove
    id = moveIds(kk);
    ix = floor(xRef(id,1) / aX) + 1;
    iy = floor(xRef(id,2) / aY) + 1;
    ix = min(max(ix,1), Nx);
    iy = min(max(iy,1), Ny);

    dxs = [-1 0 1 0];
    dys = [0 1 0 -1];
    pick = randi(4);
    jx = ix + dxs(pick);
    jy = iy + dys(pick);
    if strcmpi(params.boundary_left,'periodic') && strcmpi(params.boundary_right,'periodic')
        jx = mod(jx-1, Nx) + 1;
    else
        jx = min(max(jx,1), Nx);
    end
    if strcmpi(params.boundary_bottom,'periodic') && strcmpi(params.boundary_top,'periodic')
        jy = mod(jy-1, Ny) + 1;
    else
        jy = min(max(jy,1), Ny);
    end

    x0 = (jx - 1) * aX;
    y0 = (jy - 1) * aY;
    xRed(id,1) = x0 + aX * rand();
    xRed(id,2) = y0 + aY * rand();

    % Small velocity bias to create a momentum defect similar to a real redistribution.
    sgnx = sign(jx - ix); if sgnx == 0, sgnx = sign(randn()); end
    sgny = sign(jy - iy); if sgny == 0, sgny = sign(randn()); end
    vRed(id,1) = vRed(id,1) + opt.velocityBias * sgnx;
    vRed(id,2) = vRed(id,2) + opt.velocityBias * sgny;
end

vRed(:,1) = vRed(:,1) - mean(vRed(:,1));
vRed(:,2) = vRed(:,2) - mean(vRed(:,2));

info = struct();
info.initInfo = initInfo;
info.seed = opt.seed;
info.amp = opt.amp;
info.moveFrac = opt.moveFrac;
info.mode = char(string(opt.mode));
info.velocityBias = opt.velocityBias;
info.nMoved = nMove;
end

function meta = prepare_closed_capacity_uniform_overfill_0152(varargin)
%PREPARE_CLOSED_CAPACITY_UNIFORM_OVERFILL_0152 Prepare a uniformly overfilled closed box.
%
% This generator is intended for the closed-capacity wall-load validation.
% It writes a .smpcd V2 state with exactly gamma active Fluid particles per
% cell, but with a particle mass multiplied by massFactor.  Therefore the
% total fluid mass is
%
%   Mtot = Nx * Ny * gamma * mass * massFactor,
%
% while the closed-capacity reference mass used by the C++ runner remains
%   Mref = Nx * Ny * gamma * mass.
%
% This is a deliberately simple static test: the overfill is spatially
% uniform, so the virial pressure should be almost uniform on all solid
% walls and the net wall force should be close to zero.
%
% Typical use from repository_root/matlab:
%
%   prepare_closed_capacity_uniform_overfill_0152( ...
%       'output', '../init/closed_capacity_wall_load_0152/static_mf1p05.smpcd', ...
%       'Lx', 1.0, 'Ly', 1.0, 'Nx', 48, 'Ny', 48, ...
%       'gamma', 20, 'massFactor', 1.05, ...
%       'kBT', 0.0, 'velocityMode', 'zero', ...
%       'capacityMultiplier', 1.10, ...
%       'seed', 1520105, 'makePreview', true);

    p = inputParser;
    p.FunctionName = 'prepare_closed_capacity_uniform_overfill_0152';
    addParameter(p, 'output', '../init/closed_capacity_wall_load_0152/static_mf1p05.smpcd', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Nx', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'Ny', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'massFactor', 1.05, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'capacityMultiplier', 1.0, @(x) isnumeric(x) && isscalar(x) && x >= 1.0);
    addParameter(p, 'kBT', 0.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'type', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0 && abs(x-round(x)) < eps);
    addParameter(p, 'seed', 1520105, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'velocityMode', 'zero', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Ux', 0.0, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'Uy', 0.0, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'removeMeanMomentum', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'inactivePlacement', 'uniform_random', @(s) ischar(s) || isstring(s));
    addParameter(p, 'makePreview', true, @(x) islogical(x) || isnumeric(x));
    parse(p, varargin{:});
    opt = p.Results;

    output = char(opt.output);
    outDir = fileparts(output);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    rng(double(opt.seed), 'twister');

    Lx = double(opt.Lx);
    Ly = double(opt.Ly);
    Nx = round(double(opt.Nx));
    Ny = round(double(opt.Ny));
    gamma = round(double(opt.gamma));
    dx = Lx / Nx;
    dy = Ly / Ny;

    nCells = Nx * Ny;
    nFluid = nCells * gamma;
    nTotal = max(nFluid, round(double(opt.capacityMultiplier) * nFluid));
    nInactive = nTotal - nFluid;

    [ixGrid, iyGrid] = ndgrid(0:Nx-1, 0:Ny-1);
    cellIx = repelem(ixGrid(:), gamma);
    cellIy = repelem(iyGrid(:), gamma);

    xFluid = (double(cellIx) + rand(nFluid, 1)) * dx;
    yFluid = (double(cellIy) + rand(nFluid, 1)) * dy;

    particleMass = double(opt.mass) * double(opt.massFactor);

    switch lower(string(opt.velocityMode))
        case "maxwell"
            sigma = sqrt(double(opt.kBT) / particleMass);
            vxFluid = double(opt.Ux) + sigma * randn(nFluid, 1);
            vyFluid = double(opt.Uy) + sigma * randn(nFluid, 1);
        case "zero"
            vxFluid = double(opt.Ux) * ones(nFluid, 1);
            vyFluid = double(opt.Uy) * ones(nFluid, 1);
        otherwise
            error('prepare_closed_capacity_uniform_overfill_0152:badVelocityMode', ...
                'Unknown velocityMode: %s', char(opt.velocityMode));
    end

    if logical(opt.removeMeanMomentum)
        vxFluid = vxFluid - mean(vxFluid) + double(opt.Ux);
        vyFluid = vyFluid - mean(vyFluid) + double(opt.Uy);
    end

    switch lower(string(opt.inactivePlacement))
        case "uniform_random"
            xInactive = Lx * rand(nInactive, 1);
            yInactive = Ly * rand(nInactive, 1);
        case "none"
            if nInactive ~= 0
                error('prepare_closed_capacity_uniform_overfill_0152:inactiveNoneWithReserve', ...
                    'inactivePlacement="none" requires capacityMultiplier=1.0.');
            end
            xInactive = zeros(0, 1);
            yInactive = zeros(0, 1);
        otherwise
            error('prepare_closed_capacity_uniform_overfill_0152:badInactivePlacement', ...
                'Unknown inactivePlacement: %s. Supported values are uniform_random and none.', ...
                char(opt.inactivePlacement));
    end

    state = struct();
    state.x = [xFluid; xInactive];
    state.y = [yFluid; yInactive];
    state.vx = [vxFluid; zeros(nInactive, 1)];
    state.vy = [vyFluid; zeros(nInactive, 1)];
    state.type = repmat(uint32(round(double(opt.type))), nTotal, 1);
    state.mass = [particleMass * ones(nFluid, 1); double(opt.mass) * ones(nInactive, 1)];
    state.role = [ones(nFluid, 1, 'uint8'); zeros(nInactive, 1, 'uint8')];

    write_smpcd_state(output, state);

    meta = table();
    meta.output = string(output);
    meta.Lx = Lx;
    meta.Ly = Ly;
    meta.Nx = Nx;
    meta.Ny = Ny;
    meta.gamma = gamma;
    meta.mass = double(opt.mass);
    meta.massFactor = double(opt.massFactor);
    meta.particleMassFluid = particleMass;
    meta.capacityMultiplier = double(opt.capacityMultiplier);
    meta.nCells = nCells;
    meta.nSlots = nTotal;
    meta.nFluidInitial = nFluid;
    meta.nInactiveInitial = nInactive;
    meta.referenceMass = nCells * gamma * double(opt.mass);
    meta.totalFluidMass = nCells * gamma * particleMass;
    meta.overfillRatio = meta.totalFluidMass / meta.referenceMass - 1.0;
    meta.populationMinInitial = gamma;
    meta.populationMaxInitial = gamma;
    meta.populationMeanInitial = gamma;
    meta.kBT = double(opt.kBT);
    meta.velocityMode = string(opt.velocityMode);
    meta.Ux = double(opt.Ux);
    meta.Uy = double(opt.Uy);
    meta.removeMeanMomentum = logical(opt.removeMeanMomentum);
    meta.seed = double(opt.seed);

    [folder, base, ~] = fileparts(output);
    if isempty(folder)
        folder = '.';
    end
    metaPath = fullfile(folder, sprintf('%s_meta_0152.csv', base));
    writetable(meta, metaPath);

    if logical(opt.makePreview)
        fig = figure('Name', '0152 uniform overfill initial state', 'Visible', 'on');
        tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

        nexttile;
        nPlotFluid = min(nFluid, 8000);
        scatter(state.x(1:nPlotFluid), state.y(1:nPlotFluid), 2, '.');
        axis equal tight;
        xlim([0 Lx]); ylim([0 Ly]); grid on;
        title(sprintf('Fluid sample, mass factor %.4g', double(opt.massFactor)));
        xlabel('x'); ylabel('y');

        nexttile;
        bar([nFluid, nInactive]);
        set(gca, 'XTickLabel', {'Fluid','Inactive'});
        ylabel('particles'); grid on;
        title(sprintf('overfill %.4g %%', 100*meta.overfillRatio));

        previewPath = fullfile(folder, sprintf('%s_preview_0152.png', base));
        exportgraphics(fig, previewPath, 'Resolution', 160);
    end

    fprintf('[0152 prepare] wrote uniform overfill state: %s\n', output);
    fprintf('  grid=%dx%d gamma=%d massFactor=%.8g overfill=%.6g %%\n', ...
        Nx, Ny, gamma, double(opt.massFactor), 100*double(meta.overfillRatio));
    fprintf('  Mref=%.17g Mtot=%.17g slots=%d fluid=%d inactive=%d\n', ...
        double(meta.referenceMass), double(meta.totalFluidMass), nTotal, nFluid, nInactive);
end

function meta = prepare_injection_fill_fluid_uniform_0145(varargin)
%PREPARE_INJECTION_FILL_FLUID_UNIFORM_0145 Prepare a fully wet Fluid initial state.
%
% This generator is the full-fluid counterpart of
% prepare_injection_fill_resampling_0139.  It writes a .smpcd V2 state in
% which the initial physical domain is uniformly populated by active Fluid
% particles, with exactly gamma particles per Eulerian cell.
%
% The generated active population does not use the old inactivePlacement
% "cell_uniform" branch.  Instead, the per-cell population is built directly
% and vectorially from the Cartesian cell indices.
%
% Role convention in the output state:
%   role = 1 : Fluid    active SRC/MPCD particle
%   role = 0 : Inactive reserve/free pool slot, ignored by fluid operators
%
% Typical use from repository_root/matlab:
%
%   prepare_injection_fill_fluid_uniform_0145( ...
%       'output', '../init/injection_fill_resampling_0145/initial_state_fluid_uniform_0145.smpcd', ...
%       'Lx', 1.0, 'Ly', 1.0, ...
%       'Nx', 48, 'Ny', 48, 'gamma', 20, ...
%       'capacityMultiplier', 1.25, ...  % optional inactive reserve pool
%       'kBT', 0.001, ...
%       'seed', 1390145, ...
%       'makePreview', true);
%
% To use it with an existing shell runner:
%
%   FILL_INITIAL_STATE=init/injection_fill_resampling_0145/initial_state_fluid_uniform_0145.smpcd \
%       bash scripts/run_injection_fill_resampling_validation_0139_small.sh

    p = inputParser;
    p.FunctionName = 'prepare_injection_fill_fluid_uniform_0145';
    addParameter(p, 'output', '../init/injection_fill_resampling_0145/initial_state_fluid_uniform_0145.smpcd', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Nx', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'Ny', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'capacityMultiplier', 1.0, @(x) isnumeric(x) && isscalar(x) && x >= 1.0);
    addParameter(p, 'kBT', 0.001, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'type', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0 && abs(x-round(x)) < eps);
    addParameter(p, 'seed', 1390145, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'velocityMode', 'maxwell', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Ux', 0.0, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'Uy', 0.0, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'removeMeanMomentum', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'inactivePlacement', 'uniform_random', @(s) ischar(s) || isstring(s));
    addParameter(p, 'makePreview', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'inletYCenter', 0.5, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'inletHeightCells', 1.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
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

    % Exact gamma-per-cell active Fluid support.  This replaces the old
    % "cell_uniform" inactive-pool path by a direct vectorized construction.
    [ixGrid, iyGrid] = ndgrid(0:Nx-1, 0:Ny-1);
    cellIx = repelem(ixGrid(:), gamma);
    cellIy = repelem(iyGrid(:), gamma);

    xFluid = (double(cellIx) + rand(nFluid, 1)) * dx;
    yFluid = (double(cellIy) + rand(nFluid, 1)) * dy;

    switch lower(string(opt.velocityMode))
        case "maxwell"
            sigma = sqrt(double(opt.kBT) / double(opt.mass));
            vxFluid = double(opt.Ux) + sigma * randn(nFluid, 1);
            vyFluid = double(opt.Uy) + sigma * randn(nFluid, 1);
        case "zero"
            vxFluid = double(opt.Ux) * ones(nFluid, 1);
            vyFluid = double(opt.Uy) * ones(nFluid, 1);
        otherwise
            error('prepare_injection_fill_fluid_uniform_0145:badVelocityMode', ...
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
                error('prepare_injection_fill_fluid_uniform_0145:inactiveNoneWithReserve', ...
                    'inactivePlacement="none" requires capacityMultiplier=1.0.');
            end
            xInactive = zeros(0, 1);
            yInactive = zeros(0, 1);
        otherwise
            error('prepare_injection_fill_fluid_uniform_0145:badInactivePlacement', ...
                'Unknown inactivePlacement: %s. Supported values are uniform_random and none.', ...
                char(opt.inactivePlacement));
    end

    state = struct();
    state.x = [xFluid; xInactive];
    state.y = [yFluid; yInactive];
    state.vx = [vxFluid; zeros(nInactive, 1)];
    state.vy = [vyFluid; zeros(nInactive, 1)];
    state.type = repmat(uint32(round(double(opt.type))), nTotal, 1);
    state.mass = double(opt.mass) * ones(nTotal, 1);
    state.role = [ones(nFluid, 1, 'uint8'); zeros(nInactive, 1, 'uint8')];

    write_smpcd_state(output, state);

    inletYMin = max(0.0, double(opt.inletYCenter) - 0.5 * double(opt.inletHeightCells) * dy);
    inletYMax = min(Ly,  double(opt.inletYCenter) + 0.5 * double(opt.inletHeightCells) * dy);

    meta = table();
    meta.output = string(output);
    meta.Lx = Lx;
    meta.Ly = Ly;
    meta.Nx = Nx;
    meta.Ny = Ny;
    meta.gamma = gamma;
    meta.capacityMultiplier = double(opt.capacityMultiplier);
    meta.nCells = nCells;
    meta.nSlots = nTotal;
    meta.nFluidInitial = nFluid;
    meta.nInactiveInitial = nInactive;
    meta.populationMinInitial = gamma;
    meta.populationMaxInitial = gamma;
    meta.populationMeanInitial = gamma;
    meta.mass = double(opt.mass);
    meta.type = round(double(opt.type));
    meta.kBT = double(opt.kBT);
    meta.velocityMode = string(opt.velocityMode);
    meta.Ux = double(opt.Ux);
    meta.Uy = double(opt.Uy);
    meta.removeMeanMomentum = logical(opt.removeMeanMomentum);
    meta.inletYCenter = double(opt.inletYCenter);
    meta.inletHeightCells = double(opt.inletHeightCells);
    meta.inletYMin = inletYMin;
    meta.inletYMax = inletYMax;
    meta.seed = double(opt.seed);

    [folder, base, ~] = fileparts(output);
    if isempty(folder)
        folder = '.';
    end
    metaPath = fullfile(folder, sprintf('%s_meta_0145.csv', base));
    writetable(meta, metaPath);

    if logical(opt.makePreview)
        fig = figure('Name', '0145 full-fluid uniform initial state', 'Visible', 'on');
        tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

        nexttile;
        nPlotFluid = min(nFluid, 8000);
        scatter(state.x(1:nPlotFluid), state.y(1:nPlotFluid), 2, '.');
        axis equal tight;
        xlim([0 Lx]); ylim([0 Ly]); grid on;
        title(sprintf('Fluid sample: %d/%d', nPlotFluid, nFluid));
        xlabel('x'); ylabel('y');
        if inletYMax > inletYMin
            hold on;
            patch([0 0 0.08*Lx 0.08*Lx], [inletYMin inletYMax inletYMax inletYMin], ...
                [0.9 0.9 0.9], 'FaceAlpha', 0.25, 'EdgeColor', 'k');
            text(0.02*Lx, min(Ly, inletYMax + 0.03*Ly), 'reference inlet band');
        end

        nexttile;
        bar([nFluid, nInactive]);
        set(gca, 'XTickLabel', {'Fluid','Inactive'});
        ylabel('particles');
        title('initial roles'); grid on;

        previewPath = fullfile(folder, sprintf('%s_preview_0145.png', base));
        exportgraphics(fig, previewPath, 'Resolution', 160);
    end

    fprintf('[0145 prepare] wrote full-fluid uniform state: %s\n', output);
    fprintf('  slots=%d fluid=%d inactive=%d grid=%dx%d gamma=%d capacityMultiplier=%.6g\n', ...
        nTotal, nFluid, nInactive, Nx, Ny, gamma, double(opt.capacityMultiplier));
    fprintf('  initial per-cell Fluid population is exactly gamma=%d everywhere.\n', gamma);
end

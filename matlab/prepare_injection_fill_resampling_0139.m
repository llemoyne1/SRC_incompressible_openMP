function meta = prepare_injection_fill_resampling_0139(varargin)
%PREPARE_INJECTION_FILL_RESAMPLING_0139 Prepare an initially empty/inactive domain.
%
% The generated .smpcd V2 state contains a preallocated pool of inactive
% particles. No particle contributes to the fluid initially.  The OpenMP
% validation script then uses a one-cell hard inlet aperture to create active
% particles progressively, reproducing the MATLAB weighted-resampling
% injection/fill stress test in an inlet/outlet setting.
%
% Typical use from repository_root/matlab:
%
%   prepare_injection_fill_resampling_0139( ...
%       'output', '../init/injection_fill_resampling_0139/initial_state_injection_fill_0139.smpcd');

    p = inputParser;
    addParameter(p, 'output', '../init/injection_fill_resampling_0139/initial_state_injection_fill_0139.smpcd', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', 4.0, @isnumeric);
    addParameter(p, 'Ly', 1.0, @isnumeric);
    addParameter(p, 'Nx', 192, @isnumeric);
    addParameter(p, 'Ny', 48, @isnumeric);
    addParameter(p, 'gamma', 20, @isnumeric);
    addParameter(p, 'capacityMultiplier', 1.0, @isnumeric);
    addParameter(p, 'kBT', 0.001, @isnumeric);
    addParameter(p, 'mass', 1.0, @isnumeric);
    addParameter(p, 'seed', 1390139, @isnumeric);
    addParameter(p, 'inactivePlacement', 'uniform_random', @(s) ischar(s) || isstring(s));
    addParameter(p, 'makePreview', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'inletYCenter', 0.5, @isnumeric);
    addParameter(p, 'inletHeightCells', 1.0, @isnumeric);
    parse(p, varargin{:});
    opt = p.Results;

    output = char(opt.output);
    outDir = fileparts(output);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    rng(double(opt.seed), 'twister');

    Lx = double(opt.Lx); Ly = double(opt.Ly);
    Nx = double(opt.Nx); Ny = double(opt.Ny);
    gamma = double(opt.gamma);
    nSlots = max(1, round(Nx * Ny * gamma * double(opt.capacityMultiplier)));

    switch lower(string(opt.inactivePlacement))
        case "uniform_random"
            x = Lx * rand(nSlots, 1);
            y = Ly * rand(nSlots, 1);
        case "cell_uniform"
            nPerCell = max(1, round(gamma * double(opt.capacityMultiplier)));
            nSlots = Nx * Ny * nPerCell;
            x = zeros(nSlots, 1);
            y = zeros(nSlots, 1);
            q = 0;
            dx = Lx / Nx;
            dy = Ly / Ny;
            for iy = 1:Ny
                for ix = 1:Nx
                    ids = q + (1:nPerCell);
                    x(ids) = (ix - 1 + rand(nPerCell, 1)) * dx;
                    y(ids) = (iy - 1 + rand(nPerCell, 1)) * dy;
                    q = q + nPerCell;
                end
            end
        otherwise
            error('prepare_injection_fill_resampling_0139:badPlacement', ...
                'Unknown inactivePlacement: %s', opt.inactivePlacement);
    end

    % Inactive particles are excluded by OpenMP from streaming, collision,
    % Q6, thermostat, resampling deposits and fluid diagnostics.  Velocities
    % are initialized to zero to make accidental activation visually obvious.
    state = struct();
    state.x = x;
    state.y = y;
    state.vx = zeros(nSlots, 1);
    state.vy = zeros(nSlots, 1);
    state.type = zeros(nSlots, 1, 'uint32');
    state.mass = double(opt.mass) * ones(nSlots, 1);
    state.role = zeros(nSlots, 1, 'uint8'); % 0=Inactive, 1=Fluid, 2=Latent

    write_smpcd_state(output, state);

    dy = Ly / Ny;
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
    meta.nSlots = nSlots;
    meta.nFluidInitial = 0;
    meta.nInactiveInitial = nSlots;
    meta.inletYCenter = double(opt.inletYCenter);
    meta.inletHeightCells = double(opt.inletHeightCells);
    meta.inletYMin = inletYMin;
    meta.inletYMax = inletYMax;
    meta.seed = double(opt.seed);

    [folder, base, ~] = fileparts(output);
    metaPath = fullfile(folder, sprintf('%s_meta_0139.csv', base));
    writetable(meta, metaPath);

    if logical(opt.makePreview)
        fig = figure('Name', '0139 injection fill initial inactive pool', 'Visible', 'on');
        tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        nexttile;
        scatter(x(1:min(end, 5000)), y(1:min(end, 5000)), 2, '.');
        axis equal tight;
        xlim([0 Lx]); ylim([0 Ly]); grid on;
        title('inactive pool sample'); xlabel('x'); ylabel('y');
        hold on;
        patch([0 0 0.08*Lx 0.08*Lx], [inletYMin inletYMax inletYMax inletYMin], ...
            [0.9 0.9 0.9], 'FaceAlpha', 0.25, 'EdgeColor', 'k');
        text(0.02*Lx, min(Ly, inletYMax + 0.03*Ly), 'one-cell inlet aperture');

        nexttile;
        bar([0, nSlots]);
        set(gca, 'XTickLabel', {'Fluid','Inactive'});
        ylabel('particles');
        title('initial roles'); grid on;

        previewPath = fullfile(folder, sprintf('%s_preview_0139.png', base));
        exportgraphics(fig, previewPath, 'Resolution', 160);
    end

    fprintf('[0139 prepare] wrote inactive-pool state: %s\n', output);
    fprintf('  slots=%d fluid=0 inactive=%d grid=%dx%d gamma=%g inletY=[%.6g, %.6g]\n', ...
        nSlots, nSlots, Nx, Ny, gamma, inletYMin, inletYMax);
end

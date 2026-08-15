function out = play_smpcd_dumps(runDir, varargin)
%PLAY_SMPCD_DUMPS Sequentially display SRC/MPCD .smpcd dumps.
%
% out = play_smpcd_dumps('runs/periodic_base', 'field', 'omega')
%
% Particle overlay options:
%   'showParticles', true
%   'particleColorMode', 'role'      % role | type | single | mass | masslog | speed | speedlog
%   'particleRoleFilter', 'all'      % all | fluid | inactive | latent | noninactive
%   'particleMassMin', -Inf          % threshold filter for overlay particles
%   'particleMassMax', Inf
%   'particleSpeedMin', -Inf
%   'particleSpeedMax', Inf
%   'particleThresholdLogic', 'and'   % and | or, for active mass/speed filters
%   'particleLabelMode', 'none'       % none | id | mass | speed | mass_speed | role
%   'particleLabelMax', 30
%   'showParticleLegend', true
%
% Role color convention used by plot_smpcd_frame:
%   role = 0 : inactive slot, grey
%   role = 1 : fluid particle, red
%   role = 2 : latent particle, blue
%   other    : magenta
%
% The function returns the frame table and the last binned field. Use
% postprocess_smpcd_run for a higher-level workflow including summaries.

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'field', 'uy', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', [], @isnumeric);
    addParameter(p, 'Ly', [], @isnumeric);
    addParameter(p, 'Nx', [], @isnumeric);
    addParameter(p, 'Ny', [], @isnumeric);
    addParameter(p, 'paramsFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'frameStride', 1, @isnumeric);
    addParameter(p, 'pauseTime', 0.05, @isnumeric);
    addParameter(p, 'particleDecimation', 1000, @isnumeric);
    addParameter(p, 'particleMarkerSize', 3, @isnumeric);
    addParameter(p, 'showParticles', false, @islogical);
    addParameter(p, 'particleColorMode', 'role', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleRoleFilter', 'fluid', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleMassMin', -Inf, @isnumeric);
    addParameter(p, 'particleMassMax', Inf, @isnumeric);
    addParameter(p, 'particleSpeedMin', -Inf, @isnumeric);
    addParameter(p, 'particleSpeedMax', Inf, @isnumeric);
    addParameter(p, 'particleThresholdLogic', 'and', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleLabelMode', 'none', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleLabelMax', 30, @isnumeric);
    addParameter(p, 'particleLabelFontSize', 8, @isnumeric);
    addParameter(p, 'particleClim', [], @isnumeric);
    addParameter(p, 'showParticleLegend', true, @islogical);
    addParameter(p, 'showVelocityVectors', true, @islogical);
    addParameter(p, 'velocityDecimation', 5, @isnumeric);
    addParameter(p, 'clim', [-0.25 0.25], @isnumeric);
    parse(p, runDir, varargin{:});

    runDir = char(p.Results.runDir);
    [Lx, Ly, Nx, Ny] = local_resolve_grid(runDir, p.Results);

    frameTable = list_smpcd_dumps(runDir);
    if isempty(frameTable)
        error('play_smpcd_dumps:noFrames', 'No .smpcd dumps found in %s.', runDir);
    end

    frameStride = max(1, round(p.Results.frameStride));
    indices = 1:frameStride:height(frameTable);
    fig = figure('Name', sprintf('SRC/MPCD dumps: %s', runDir));
    lastFields = [];

    for kk = indices
        state = read_smpcd_state(char(frameTable.fullPath(kk)));
        fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);
        plot_smpcd_frame(state, fields, ...
            'field', char(p.Results.field), ...
            'step', frameTable.step(kk), ...
            'time', frameTable.time(kk), ...
            'particleDecimation', p.Results.particleDecimation, ...
            'particleMarkerSize', p.Results.particleMarkerSize, ...
            'showParticles', p.Results.showParticles, ...
            'particleColorMode', char(p.Results.particleColorMode), ...
            'particleRoleFilter', char(p.Results.particleRoleFilter), ...
            'particleMassMin', p.Results.particleMassMin, ...
            'particleMassMax', p.Results.particleMassMax, ...
            'particleSpeedMin', p.Results.particleSpeedMin, ...
            'particleSpeedMax', p.Results.particleSpeedMax, ...
            'particleThresholdLogic', char(p.Results.particleThresholdLogic), ...
            'particleLabelMode', char(p.Results.particleLabelMode), ...
            'particleLabelMax', p.Results.particleLabelMax, ...
            'particleLabelFontSize', p.Results.particleLabelFontSize, ...
            'particleClim', p.Results.particleClim, ...
            'showParticleLegend', p.Results.showParticleLegend, ...
            'showVelocityVectors', p.Results.showVelocityVectors, ...
            'velocityDecimation', p.Results.velocityDecimation, ...
            'clim', p.Results.clim, ...
            'figureHandle', fig);
        drawnow;
        pause(p.Results.pauseTime);
        lastFields = fields;
    end

    out = struct();
    out.frameTable = frameTable;
    out.lastFields = lastFields;
end

function [Lx, Ly, Nx, Ny] = local_resolve_grid(runDir, opts)
    Lx = opts.Lx;
    Ly = opts.Ly;
    Nx = opts.Nx;
    Ny = opts.Ny;
    if ~isempty(Lx) && ~isempty(Ly) && ~isempty(Nx) && ~isempty(Ny)
        return;
    end

    paramsFile = char(opts.paramsFile);
    if isempty(paramsFile)
        candidate = fullfile(runDir, 'params_used.kv');
        if isfile(candidate)
            paramsFile = candidate;
        end
    end
    if isempty(paramsFile) || ~isfile(paramsFile)
        error('play_smpcd_dumps:missingGrid', 'Provide Lx, Ly, Nx, Ny or a valid paramsFile.');
    end
    params = parse_smpcd_kv(paramsFile);
    Lx = local_get_param(params, 'Lx', Lx);
    Ly = local_get_param(params, 'Ly', Ly);
    Nx = local_get_param(params, 'Nx', Nx);
    Ny = local_get_param(params, 'Ny', Ny);
end

function value = local_get_param(params, name, fallback)
    if ~isempty(fallback)
        value = fallback;
    elseif isfield(params, name)
        value = params.(name);
    else
        error('play_smpcd_dumps:missingParam', 'Missing parameter: %s', name);
    end
end

function h = plot_smpcd_frame(state, fields, varargin)
%PLOT_SMPCD_FRAME Plot one SRC/MPCD particle dump and/or binned field.
%
% h = plot_smpcd_frame(state, fields, 'field', 'rho')
%
% Supported fields: particles, N, rho, Ux, Uy, speed, omega, type.
%
% Particle overlay options:
%   'particleColorMode', 'role'      % role | type | single | mass | masslog | speed | speedlog
%   'particleRoleFilter', 'all'      % all | fluid | inactive | latent | noninactive
%   'particleMassMin', -Inf          % threshold filter for overlay particles
%   'particleMassMax', Inf
%   'particleSpeedMin', -Inf
%   'particleSpeedMax', Inf
%   'particleThresholdLogic', 'and'   % and | or, for active mass/speed filters
%   'particleLabelMode', 'none'       % none | id | mass | speed | mass_speed | role
%   'particleLabelMax', 30
%   'particleClim', []               % color range for mass/speed overlays
%   'showParticleLegend', true
%
% Role color convention:
%   role = 0 : inactive slot, grey
%   role = 1 : fluid particle, red
%   role = 2 : latent particle, blue
%   other    : magenta
%
% Examples:
%   plot_smpcd_frame(state, fields, 'field', 'N', ...
%       'particleColorMode', 'masslog', 'particleMassMax', 0.25, ...
%       'particleRoleFilter', 'fluid', 'particleLabelMode', 'mass_speed');
%
%   plot_smpcd_frame(state, fields, 'field', 'N', ...
%       'particleColorMode', 'speed', 'particleSpeedMin', 5.0, ...
%       'particleRoleFilter', 'fluid');

    p = inputParser;
    addRequired(p, 'state', @isstruct);
    addRequired(p, 'fields', @isstruct);
    addParameter(p, 'field', 'rho', @(s) ischar(s) || isstring(s));
    addParameter(p, 'step', NaN, @isnumeric);
    addParameter(p, 'time', NaN, @isnumeric);
    addParameter(p, 'particleDecimation', 20, @isnumeric);
    addParameter(p, 'particleMarkerSize', 6, @isnumeric);
    addParameter(p, 'showParticles', true, @islogical);
    addParameter(p, 'particleColorMode', 'role', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleRoleFilter', 'all', @(s) ischar(s) || isstring(s));
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
    addParameter(p, 'velocityDecimation', 2, @isnumeric);
    addParameter(p, 'showVelocityVectors', false, @islogical);
    addParameter(p, 'clim', [], @isnumeric);
    addParameter(p, 'figureHandle', [], @(x) isempty(x) || ishghandle(x));
    parse(p, state, fields, varargin{:});

    fieldName = char(p.Results.field);
    if isempty(p.Results.figureHandle)
        h.fig = figure('Name', 'SRC/MPCD frame');
    else
        h.fig = figure(p.Results.figureHandle);
        clf(h.fig);
    end

    ax = axes('Parent', h.fig);
    hold(ax, 'on');
    particleHandles = [];
    particleInfo = struct('isScalarColor', false, 'scalarLabel', '', 'selectedCount', 0);

    switch lower(fieldName)
        case {'particles','particle'}
            [particleHandles, particleInfo] = local_plot_particles(ax, state, p.Results);
            titleText = 'particles';
            cb = [];

        case {'n','count','occupancy'}
            imagesc(ax, fields.xc, fields.yc, fields.N);
            set(ax, 'YDir', 'normal');
            titleText = 'N';
            cb = colorbar(ax);

        case {'rho','density'}
            imagesc(ax, fields.xc, fields.yc, fields.rho);
            set(ax, 'YDir', 'normal');
            titleText = 'rho';
            cb = colorbar(ax);

        case {'ux'}
            imagesc(ax, fields.xc, fields.yc, fields.Ux);
            set(ax, 'YDir', 'normal');
            titleText = 'Ux';
            cb = colorbar(ax);

        case {'uy'}
            imagesc(ax, fields.xc, fields.yc, fields.Uy);
            set(ax, 'YDir', 'normal');
            titleText = 'Uy';
            cb = colorbar(ax);

        case {'speed','u'}
            imagesc(ax, fields.xc, fields.yc, fields.speed);
            set(ax, 'YDir', 'normal');
            titleText = '|U|';
            cb = colorbar(ax);

        case {'omega','vorticity'}
            imagesc(ax, fields.xc, fields.yc, fields.omega);
            set(ax, 'YDir', 'normal');
            titleText = 'omega_z';
            cb = colorbar(ax);

        case {'type','dominanttype'}
            imagesc(ax, fields.xc, fields.yc, fields.dominantType);
            set(ax, 'YDir', 'normal');
            titleText = 'dominant type';
            cb = colorbar(ax);

        otherwise
            error('plot_smpcd_frame:unknownField', 'Unknown field: %s', fieldName);
    end

    if ~isempty(p.Results.clim) && numel(p.Results.clim) == 2 && ~strcmpi(fieldName, 'particles')
        caxis(ax, p.Results.clim);
    end

    if p.Results.showParticles && ~strcmpi(fieldName, 'particles')
        [particleHandles, particleInfo] = local_plot_particles(ax, state, p.Results);
    end

    if particleInfo.isScalarColor
        if ~isempty(p.Results.particleClim) && numel(p.Results.particleClim) == 2
            caxis(ax, p.Results.particleClim);
        end
        % If the background field also has a colorbar, MATLAB uses the same axes
        % colormap for image and scatter. For threshold debugging this is still
        % useful, but prefer field='particles' when a scalar particle colorbar is
        % the main diagnostic.
        cb2 = colorbar(ax);
        ylabel(cb2, particleInfo.scalarLabel, 'Interpreter', 'none');
        cb = cb2;
    end

    if p.Results.showVelocityVectors && ~strcmpi(fieldName, 'particles')
        d = max(1, round(p.Results.velocityDecimation));
        [Xc, Yc] = meshgrid(fields.xc, fields.yc);
        quiver(ax, Xc(1:d:end,1:d:end), Yc(1:d:end,1:d:end), ...
            fields.Ux(1:d:end,1:d:end), fields.Uy(1:d:end,1:d:end), 'k');
    end

    if p.Results.showParticleLegend && ~isempty(particleHandles) && ~particleInfo.isScalarColor
        local_show_particle_legend(ax, particleHandles);
    end

    axis(ax, 'equal');
    axis(ax, [0 fields.Lx 0 fields.Ly]);
    xlabel(ax, 'x');
    ylabel(ax, 'y');
    if ~isnan(p.Results.step)
        titleText = sprintf('%s, step=%g, t=%g', titleText, p.Results.step, p.Results.time);
    end
    if particleInfo.selectedCount > 0 && ~strcmpi(strtrim(char(p.Results.particleRoleFilter)), 'all')
        titleText = sprintf('%s | particles=%d', titleText, particleInfo.selectedCount);
    end
    title(ax, titleText, 'Interpreter', 'none');
    hold(ax, 'off');

    h.ax = ax;
    h.colorbar = cb;
    h.particles = particleHandles;
    h.particleInfo = particleInfo;
end

function [handles, info] = local_plot_particles(ax, state, opts)
    decimation = max(1, round(opts.particleDecimation));
    markerSize = max(0.1, opts.particleMarkerSize);
    colorMode = lower(strtrim(char(opts.particleColorMode)));
    roleFilter = char(opts.particleRoleFilter);
    handles = [];
    info = struct('isScalarColor', false, 'scalarLabel', '', 'selectedCount', 0);

    n = local_particle_count(state);
    if n <= 0
        return;
    end

    x = local_state_vector(state, 'x', n, NaN);
    y = local_state_vector(state, 'y', n, NaN);
    vx = local_state_vector(state, 'vx', n, NaN);
    vy = local_state_vector(state, 'vy', n, NaN);
    mass = local_state_vector(state, 'mass', n, 1.0);
    role = local_state_vector(state, 'role', n, NaN);
    type = local_state_vector(state, 'type', n, NaN);
    speed = hypot(vx, vy);

    baseMask = isfinite(x) & isfinite(y);
    baseMask = baseMask & local_role_filter_mask(role, n, roleFilter);
    baseMask = baseMask & local_threshold_mask(mass, speed, opts);

    idxAll = find(baseMask);
    info.selectedCount = numel(idxAll);
    if isempty(idxAll)
        return;
    end

    switch colorMode
        case 'role'
            handles = local_scatter_by_role(ax, x, y, role, baseMask, decimation, markerSize);

        case 'type'
            idx = idxAll(1:decimation:end);
            if all(isnan(type(idx)))
                handles = local_scatter_single(ax, x, y, idx, markerSize, [1.0 0.0 0.0], 'particles');
            else
                handles = scatter(ax, x(idx), y(idx), markerSize, type(idx), 'filled', ...
                    'DisplayName', 'particles by type');
            end

        case {'single','red'}
            idx = idxAll(1:decimation:end);
            handles = local_scatter_single(ax, x, y, idx, markerSize, [1.0 0.0 0.0], 'particles');

        case {'mass','masslog','speed','speedlog'}
            idx = idxAll(1:decimation:end);
            [values, label] = local_scalar_values(colorMode, mass, speed, idx);
            handles = scatter(ax, x(idx), y(idx), markerSize, values, 'filled', ...
                'DisplayName', sprintf('particles by %s', label));
            info.isScalarColor = true;
            info.scalarLabel = label;

        otherwise
            error('plot_smpcd_frame:badParticleColorMode', ...
                'Unknown particleColorMode: %s. Use role, type, single, mass, masslog, speed, or speedlog.', colorMode);
    end

    local_label_particles(ax, x, y, mass, speed, role, idxAll, opts);
end

function mask = local_threshold_mask(mass, speed, opts)
    massMin = opts.particleMassMin;
    massMax = opts.particleMassMax;
    speedMin = opts.particleSpeedMin;
    speedMax = opts.particleSpeedMax;

    massActive = isfinite(massMin) || isfinite(massMax);
    speedActive = isfinite(speedMin) || isfinite(speedMax);
    if ~massActive && ~speedActive
        mask = true(size(mass));
        return;
    end

    massOk = true(size(mass));
    if massActive
        massOk = isfinite(mass) & mass >= massMin & mass <= massMax;
    end

    speedOk = true(size(speed));
    if speedActive
        speedOk = isfinite(speed) & speed >= speedMin & speed <= speedMax;
    end

    switch lower(strtrim(char(opts.particleThresholdLogic)))
        case 'and'
            mask = true(size(mass));
            if massActive
                mask = mask & massOk;
            end
            if speedActive
                mask = mask & speedOk;
            end
        case 'or'
            mask = false(size(mass));
            if massActive
                mask = mask | massOk;
            end
            if speedActive
                mask = mask | speedOk;
            end
        otherwise
            error('plot_smpcd_frame:badParticleThresholdLogic', ...
                'Unknown particleThresholdLogic: %s. Use and or or.', opts.particleThresholdLogic);
    end
end

function [values, label] = local_scalar_values(colorMode, mass, speed, idx)
    switch colorMode
        case 'mass'
            values = mass(idx);
            label = 'particle mass';
        case 'masslog'
            values = log10(max(mass(idx), realmin));
            label = 'log10 particle mass';
        case 'speed'
            values = speed(idx);
            label = 'particle speed |v|';
        case 'speedlog'
            values = log10(max(speed(idx), realmin));
            label = 'log10 particle speed |v|';
        otherwise
            values = zeros(size(idx));
            label = '';
    end
end

function local_label_particles(ax, x, y, mass, speed, role, idxAll, opts)
    mode = lower(strtrim(char(opts.particleLabelMode)));
    if strcmp(mode, 'none') || isempty(idxAll)
        return;
    end

    maxLabels = max(0, round(opts.particleLabelMax));
    if maxLabels == 0
        return;
    end

    fontSize = max(4, round(opts.particleLabelFontSize));
    idx = idxAll(:);

    % Prefer the most suspicious particles when many pass the threshold: lowest
    % mass for mass labels, highest speed for speed labels, highest speed by
    % default for mixed labels.
    switch mode
        case 'mass'
            [~, order] = sort(mass(idx), 'ascend');
        case {'speed','mass_speed'}
            [~, order] = sort(speed(idx), 'descend');
        otherwise
            order = 1:numel(idx);
    end
    idx = idx(order(1:min(maxLabels, numel(order))));

    for kk = 1:numel(idx)
        ii = idx(kk);
        switch mode
            case 'id'
                label = sprintf('#%d', ii);
            case 'mass'
                label = sprintf('m=%.3g', mass(ii));
            case 'speed'
                label = sprintf('|v|=%.3g', speed(ii));
            case 'mass_speed'
                label = sprintf('m=%.3g\n|v|=%.3g', mass(ii), speed(ii));
            case 'role'
                label = sprintf('role=%g', role(ii));
            otherwise
                error('plot_smpcd_frame:badParticleLabelMode', ...
                    'Unknown particleLabelMode: %s. Use none, id, mass, speed, mass_speed, or role.', mode);
        end
        text(ax, x(ii), y(ii), label, 'FontSize', fontSize, ...
            'Color', [0 0 0], 'BackgroundColor', [1 1 1], ...
            'Margin', 1, 'Interpreter', 'none', 'Clipping', 'on');
    end
end

function n = local_particle_count(state)
    if isfield(state, 'Np') && ~isempty(state.Np)
        n = double(state.Np);
    elseif isfield(state, 'x') && ~isempty(state.x)
        n = numel(state.x);
    else
        n = 0;
    end
    if isfield(state, 'x') && ~isempty(state.x)
        n = min(n, numel(state.x));
    end
    if isfield(state, 'y') && ~isempty(state.y)
        n = min(n, numel(state.y));
    end
end

function v = local_state_vector(state, name, n, fallback)
    if isfield(state, name) && ~isempty(state.(name))
        v = state.(name)(:);
        v = v(1:min(n, numel(v)));
        if numel(v) < n
            v(end+1:n, 1) = fallback;
        end
    else
        v = repmat(fallback, n, 1);
    end
    v = double(v);
end

function mask = local_role_filter_mask(role, n, roleFilter)
    if all(isnan(role))
        mask = true(n, 1);
        return;
    end

    switch lower(strtrim(roleFilter))
        case {'all','*'}
            mask = true(n, 1);
        case {'fluid','active'}
            mask = (role == 1);
        case {'inactive'}
            mask = (role == 0);
        case {'latent'}
            mask = (role == 2);
        case {'noninactive','non-inactive','activeany','notinactive'}
            mask = (role ~= 0);
        otherwise
            error('plot_smpcd_frame:badParticleRoleFilter', ...
                'Unknown particleRoleFilter: %s. Use all, fluid, inactive, latent, or noninactive.', roleFilter);
    end
end

function handles = local_scatter_by_role(ax, x, y, role, baseMask, decimation, markerSize)
    handles = [];
    roleOrder = [0 1 2];
    present = unique(role(baseMask & isfinite(role)))';
    extra = setdiff(present, roleOrder, 'stable');
    roleOrder = [roleOrder extra];

    for rv = roleOrder
        mask = baseMask & (role == rv);
        idx = find(mask);
        idx = idx(1:decimation:end);
        label = local_role_label(rv);
        color = local_role_color(rv);
        h = local_scatter_single(ax, x, y, idx, markerSize, color, label);
        if ~isempty(h)
            handles = [handles h]; %#ok<AGROW>
        end
    end
end

function h = local_scatter_single(ax, x, y, idx, markerSize, color, label)
    if isempty(idx)
        h = [];
        return;
    end
    h = scatter(ax, x(idx), y(idx), markerSize, color, 'filled', 'DisplayName', label);
end

function label = local_role_label(roleValue)
    switch roleValue
        case 0
            label = 'role 0 inactive';
        case 1
            label = 'role 1 fluid';
        case 2
            label = 'role 2 latent';
        otherwise
            label = sprintf('role %g other', roleValue);
    end
end

function color = local_role_color(roleValue)
    switch roleValue
        case 0
            color = [0.55 0.55 0.55];
        case 1
            color = [1.00 0.00 0.00];
        case 2
            color = [0.00 0.45 0.90];
        otherwise
            color = [0.85 0.00 0.85];
    end
end

function local_show_particle_legend(ax, particleHandles)
    if isempty(particleHandles)
        return;
    end
    try
        legend(ax, particleHandles, 'Location', 'eastoutside', 'Interpreter', 'none');
    catch
        legend(ax, particleHandles, 'Interpreter', 'none');
    end
end

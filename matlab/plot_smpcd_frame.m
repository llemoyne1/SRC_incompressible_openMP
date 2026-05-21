function h = plot_smpcd_frame(state, fields, varargin)
%PLOT_SMPCD_FRAME Plot one SRC/MPCD particle dump and/or binned field.
%
% h = plot_smpcd_frame(state, fields, 'field', 'rho')
%
% Supported fields: particles, N, rho, Ux, Uy, speed, omega, type.

    p = inputParser;
    addRequired(p, 'state', @isstruct);
    addRequired(p, 'fields', @isstruct);
    addParameter(p, 'field', 'rho', @(s) ischar(s) || isstring(s));
    addParameter(p, 'step', NaN, @isnumeric);
    addParameter(p, 'time', NaN, @isnumeric);
    addParameter(p, 'particleDecimation', 20, @isnumeric);
    addParameter(p, 'showParticles', false, @islogical);
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

    switch lower(fieldName)
        case {'particles','particle'}
            local_plot_particles(ax, state, p.Results.particleDecimation);
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
        local_plot_particles(ax, state, p.Results.particleDecimation);
    end

    if p.Results.showVelocityVectors && ~strcmpi(fieldName, 'particles')
        d = max(1, round(p.Results.velocityDecimation));
        [Xc, Yc] = meshgrid(fields.xc, fields.yc);
        quiver(ax, Xc(1:d:end,1:d:end), Yc(1:d:end,1:d:end), ...
            fields.Ux(1:d:end,1:d:end), fields.Uy(1:d:end,1:d:end), 'k');
    end

    axis(ax, 'equal');
    axis(ax, [0 fields.Lx 0 fields.Ly]);
    xlabel(ax, 'x');
    ylabel(ax, 'y');
    if ~isnan(p.Results.step)
        titleText = sprintf('%s, step=%g, t=%g', titleText, p.Results.step, p.Results.time);
    end
    title(ax, titleText, 'Interpreter', 'none');
    hold(ax, 'off');

    h.ax = ax;
    h.colorbar = cb;
end

function local_plot_particles(ax, state, decimation)
    decimation = max(1, round(decimation));
    idx = 1:decimation:state.Np;
    if isfield(state, 'type') && ~isempty(state.type)
        scatter(ax, state.x(idx), state.y(idx), 6, double(state.type(idx)), 'filled');
    else
        scatter(ax, state.x(idx), state.y(idx), 6, 'filled');
    end
end

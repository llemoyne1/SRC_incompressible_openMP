function out = inspect_smpcd_particle_thresholds(runDir, varargin)
%INSPECT_SMPCD_PARTICLE_THRESHOLDS Inspect and plot particles selected by mass/speed thresholds.
%
% out = inspect_smpcd_particle_thresholds(runDir, 'particleMassMax', 0.25)
% out = inspect_smpcd_particle_thresholds(runDir, 'particleSpeedMin', 5.0)
%
% This helper is intended for debugging variable-mass SRC/MPCD dumps.  It reads
% one frame, selects particles by role and mass/speed thresholds, returns a
% table, and overlays the selected particles on a binned field.
%
% Useful examples:
%   % Low-mass fluid particles, labelled with mass and speed:
%   out = inspect_smpcd_particle_thresholds(runDir, ...
%       'field', 'N', 'particleRoleFilter', 'fluid', ...
%       'particleMassMax', 0.25, 'particleColorMode', 'masslog', ...
%       'particleLabelMode', 'mass_speed', 'topK', 100);
%
%   % Fast fluid particles:
%   out = inspect_smpcd_particle_thresholds(runDir, ...
%       'field', 'Ux', 'particleRoleFilter', 'fluid', ...
%       'particleSpeedMin', 5.0, 'particleColorMode', 'speed', ...
%       'particleLabelMode', 'mass_speed');
%
%   % Either low-mass OR fast particles:
%   out = inspect_smpcd_particle_thresholds(runDir, ...
%       'particleMassMax', 0.25, 'particleSpeedMin', 5.0, ...
%       'particleThresholdLogic', 'or');

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'frameIndex', Inf, @isnumeric);      % Inf = last frame
    addParameter(p, 'step', [], @isnumeric);             % optional exact/nearest step
    addParameter(p, 'field', 'N', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', [], @isnumeric);
    addParameter(p, 'Ly', [], @isnumeric);
    addParameter(p, 'Nx', [], @isnumeric);
    addParameter(p, 'Ny', [], @isnumeric);
    addParameter(p, 'paramsFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleRoleFilter', 'fluid', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleMassMin', -Inf, @isnumeric);
    addParameter(p, 'particleMassMax', Inf, @isnumeric);
    addParameter(p, 'particleSpeedMin', -Inf, @isnumeric);
    addParameter(p, 'particleSpeedMax', Inf, @isnumeric);
    addParameter(p, 'particleThresholdLogic', 'and', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleColorMode', 'masslog', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleLabelMode', 'mass_speed', @(s) ischar(s) || isstring(s));
    addParameter(p, 'particleLabelMax', 30, @isnumeric);
    addParameter(p, 'particleMarkerSize', 18, @isnumeric);
    addParameter(p, 'topK', Inf, @isnumeric);
    addParameter(p, 'sortBy', 'speed_desc', @(s) ischar(s) || isstring(s)); % speed_desc | mass_asc | mass_desc | id
    addParameter(p, 'outputCsv', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'showFigure', true, @islogical);
    addParameter(p, 'clim', [], @isnumeric);
    parse(p, runDir, varargin{:});

    runDir = char(p.Results.runDir);
    [Lx, Ly, Nx, Ny] = local_resolve_grid(runDir, p.Results);

    frameTable = list_smpcd_dumps(runDir);
    if isempty(frameTable)
        error('inspect_smpcd_particle_thresholds:noFrames', 'No .smpcd dumps found in %s.', runDir);
    end

    frameIdx = local_select_frame(frameTable, p.Results.frameIndex, p.Results.step);
    state = read_smpcd_state(char(frameTable.fullPath(frameIdx)));
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);

    tblAll = local_particle_table(state, Lx, Ly, Nx, Ny);
    mask = local_role_filter_mask(tblAll.role, char(p.Results.particleRoleFilter));
    mask = mask & local_threshold_mask(tblAll.mass, tblAll.speed, p.Results);
    tbl = tblAll(mask, :);
    tbl = local_sort_table(tbl, char(p.Results.sortBy));

    topK = round(p.Results.topK);
    if isfinite(topK) && topK >= 0 && height(tbl) > topK
        tbl = tbl(1:topK, :);
    end

    if ~isempty(char(p.Results.outputCsv))
        outCsv = char(p.Results.outputCsv);
        parentDir = fileparts(outCsv);
        if ~isempty(parentDir) && ~isfolder(parentDir)
            mkdir(parentDir);
        end
        writetable(tbl, outCsv);
    end

    if p.Results.showFigure
        plot_smpcd_frame(state, fields, ...
            'field', char(p.Results.field), ...
            'step', frameTable.step(frameIdx), ...
            'time', frameTable.time(frameIdx), ...
            'showParticles', true, ...
            'particleRoleFilter', char(p.Results.particleRoleFilter), ...
            'particleMassMin', p.Results.particleMassMin, ...
            'particleMassMax', p.Results.particleMassMax, ...
            'particleSpeedMin', p.Results.particleSpeedMin, ...
            'particleSpeedMax', p.Results.particleSpeedMax, ...
            'particleThresholdLogic', char(p.Results.particleThresholdLogic), ...
            'particleColorMode', char(p.Results.particleColorMode), ...
            'particleLabelMode', char(p.Results.particleLabelMode), ...
            'particleLabelMax', p.Results.particleLabelMax, ...
            'particleMarkerSize', p.Results.particleMarkerSize, ...
            'particleDecimation', 1, ...
            'clim', p.Results.clim);
    end

    fprintf('[inspect] runDir=%s frame=%d step=%g selected=%d\n', ...
        runDir, frameIdx, frameTable.step(frameIdx), height(tbl));
    if height(tbl) > 0
        disp(tbl(1:min(20, height(tbl)), :));
    end

    out = struct();
    out.table = tbl;
    out.frameTable = frameTable;
    out.frameIndex = frameIdx;
    out.state = state;
    out.fields = fields;
end

function idx = local_select_frame(frameTable, frameIndex, requestedStep)
    if ~isempty(requestedStep)
        [~, idx] = min(abs(frameTable.step - requestedStep));
        return;
    end
    if isinf(frameIndex)
        idx = height(frameTable);
    else
        idx = max(1, min(height(frameTable), round(frameIndex)));
    end
end

function tbl = local_particle_table(state, Lx, Ly, Nx, Ny)
    n = local_particle_count(state);
    id = (1:n)';
    x = local_state_vector(state, 'x', n, NaN);
    y = local_state_vector(state, 'y', n, NaN);
    vx = local_state_vector(state, 'vx', n, NaN);
    vy = local_state_vector(state, 'vy', n, NaN);
    mass = local_state_vector(state, 'mass', n, 1.0);
    role = local_state_vector(state, 'role', n, NaN);
    type = local_state_vector(state, 'type', n, NaN);
    speed = hypot(vx, vy);
    cellI = floor(x ./ Lx .* Nx) + 1;
    cellJ = floor(y ./ Ly .* Ny) + 1;
    cellI = max(1, min(Nx, cellI));
    cellJ = max(1, min(Ny, cellJ));
    tbl = table(id, role, type, x, y, vx, vy, speed, mass, cellI, cellJ);
end

function tbl = local_sort_table(tbl, sortBy)
    switch lower(strtrim(sortBy))
        case {'speed_desc','speed','fast'}
            tbl = sortrows(tbl, 'speed', 'descend');
        case {'mass_asc','lowmass','mass'}
            tbl = sortrows(tbl, 'mass', 'ascend');
        case {'mass_desc'}
            tbl = sortrows(tbl, 'mass', 'descend');
        case {'id','none'}
            % Preserve original order.
        otherwise
            error('inspect_smpcd_particle_thresholds:badSortBy', ...
                'Unknown sortBy: %s. Use speed_desc, mass_asc, mass_desc, or id.', sortBy);
    end
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
            if massActive, mask = mask & massOk; end
            if speedActive, mask = mask & speedOk; end
        case 'or'
            mask = false(size(mass));
            if massActive, mask = mask | massOk; end
            if speedActive, mask = mask | speedOk; end
        otherwise
            error('inspect_smpcd_particle_thresholds:badThresholdLogic', ...
                'Unknown particleThresholdLogic: %s. Use and or or.', opts.particleThresholdLogic);
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
    if isfield(state, 'x') && ~isempty(state.x), n = min(n, numel(state.x)); end
    if isfield(state, 'y') && ~isempty(state.y), n = min(n, numel(state.y)); end
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

function mask = local_role_filter_mask(role, roleFilter)
    if all(isnan(role))
        mask = true(size(role));
        return;
    end
    switch lower(strtrim(roleFilter))
        case {'all','*'}
            mask = true(size(role));
        case {'fluid','active'}
            mask = (role == 1);
        case {'inactive'}
            mask = (role == 0);
        case {'latent'}
            mask = (role == 2);
        case {'noninactive','non-inactive','activeany','notinactive'}
            mask = (role ~= 0);
        otherwise
            error('inspect_smpcd_particle_thresholds:badRoleFilter', ...
                'Unknown particleRoleFilter: %s. Use all, fluid, inactive, latent, or noninactive.', roleFilter);
    end
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
        error('inspect_smpcd_particle_thresholds:missingGrid', ...
            'Provide Lx, Ly, Nx, Ny or a valid paramsFile.');
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
        error('inspect_smpcd_particle_thresholds:missingParam', 'Missing parameter: %s', name);
    end
end

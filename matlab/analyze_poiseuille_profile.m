function out = analyze_poiseuille_profile(runDir, varargin)
%ANALYZE_POISEUILLE_PROFILE Time-average and fit a Poiseuille-like profile.
%
% out = analyze_poiseuille_profile('runs/poiseuille_y_bounceback_vp')
%
% The function reads state_step_*.smpcd dumps, bins them on the simulation grid,
% computes a 1-D mean velocity profile, averages selected frames after a
% transient, and fits a quadratic profile. It is intentionally kept in MATLAB so
% the C++ solver remains a compact producer of primitive dumps.
%
% Typical y-channel usage:
%   out = analyze_poiseuille_profile('runs/poiseuille_y_bounceback_vp', ...
%       'flowComponent', 'Ux', 'profileDirection', 'y', ...
%       'fitStartFraction', 0.5, 'excludeWallCells', 2);
%
% For a body acceleration g in the flow direction, the effective viscosity
% estimate is nu_eff = -g/(2*c2), where c2 is the quadratic coefficient of
% U(s) = c0 + c1*s + c2*s^2.

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'paramsFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'summaryFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'flowComponent', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'profileDirection', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'frameStride', 1, @isnumeric);
    addParameter(p, 'fitStartFraction', 0.5, @isnumeric);
    addParameter(p, 'fitStartStep', [], @isnumeric);
    addParameter(p, 'fitEndStep', [], @isnumeric);
    addParameter(p, 'excludeWallCells', 1, @isnumeric);
    addParameter(p, 'makePlots', true, @islogical);
    addParameter(p, 'saveMat', false, @islogical);
    addParameter(p, 'matFile', '', @(s) ischar(s) || isstring(s));
    parse(p, runDir, varargin{:});

    runDir = char(p.Results.runDir);
    if ~isfolder(runDir)
        error('analyze_poiseuille_profile:runDirNotFound', 'Cannot find run directory: %s', runDir);
    end

    paramsFile = char(p.Results.paramsFile);
    if isempty(paramsFile)
        candidate = fullfile(runDir, 'params_used.kv');
        if isfile(candidate)
            paramsFile = candidate;
        end
    end
    if isempty(paramsFile) || ~isfile(paramsFile)
        error('analyze_poiseuille_profile:missingParams', 'Cannot find params_used.kv. Pass paramsFile explicitly.');
    end
    params = parse_smpcd_kv(paramsFile);
    grid = local_grid_from_params(params);

    summaryFile = char(p.Results.summaryFile);
    if isempty(summaryFile)
        summaryFile = fullfile(runDir, 'summary_runtime.csv');
    end
    if isfile(summaryFile)
        summaryTable = readtable(summaryFile);
    else
        summaryTable = table();
    end

    frameTable = list_smpcd_dumps(runDir, 'summaryFile', summaryFile);
    if height(frameTable) == 0
        error('analyze_poiseuille_profile:noDumps', 'No state_step_*.smpcd dumps found in %s.', runDir);
    end

    frameStride = max(1, round(p.Results.frameStride));
    selected = 1:frameStride:height(frameTable);
    frameTable = frameTable(selected, :);

    flowComponent = lower(char(p.Results.flowComponent));
    if isempty(flowComponent)
        ax = abs(local_get_param(params, 'bodyAccelerationX', local_get_param(params, 'bodyForceX', 0.0)));
        ay = abs(local_get_param(params, 'bodyAccelerationY', local_get_param(params, 'bodyForceY', 0.0)));
        if ay > ax
            flowComponent = 'uy';
        else
            flowComponent = 'ux';
        end
    end
    if ~ismember(flowComponent, {'ux','uy'})
        error('analyze_poiseuille_profile:badFlowComponent', 'flowComponent must be Ux or Uy.');
    end

    profileDirection = lower(char(p.Results.profileDirection));
    if isempty(profileDirection)
        if strcmp(flowComponent, 'ux')
            profileDirection = 'y';
        else
            profileDirection = 'x';
        end
    end
    if ~ismember(profileDirection, {'x','y'})
        error('analyze_poiseuille_profile:badProfileDirection', 'profileDirection must be x or y.');
    end

    nFrames = height(frameTable);
    profiles = [];
    coord = [];
    for k = 1:nFrames
        state = read_smpcd_state(char(frameTable.fullPath(k)));
        fields = bin_smpcd_state(state, ...
            'Lx', grid.Lx, 'Ly', grid.Ly, 'Nx', grid.Nx, 'Ny', grid.Ny, ...
            'periodicX', local_is_periodic_x(params), ...
            'periodicY', local_is_periodic_y(params));
        if strcmp(flowComponent, 'ux')
            U = fields.Ux;
        else
            U = fields.Uy;
        end
        if strcmp(profileDirection, 'y')
            profile = mean(U, 2, 'omitnan');
            thisCoord = fields.yc(:);
        else
            profile = mean(U, 1, 'omitnan').';
            thisCoord = fields.xc(:);
        end
        if isempty(profiles)
            profiles = nan(numel(profile), nFrames);
            coord = thisCoord;
        end
        profiles(:, k) = profile(:);
    end

    steps = frameTable.step;
    startStep = p.Results.fitStartStep;
    if isempty(startStep)
        finiteSteps = steps(isfinite(steps));
        if isempty(finiteSteps)
            startStep = -Inf;
        else
            s0 = min(finiteSteps);
            s1 = max(finiteSteps);
            startStep = s0 + p.Results.fitStartFraction * (s1 - s0);
        end
    end
    endStep = p.Results.fitEndStep;
    if isempty(endStep)
        endStep = Inf;
    end
    avgMask = steps >= startStep & steps <= endStep;
    if ~any(avgMask)
        warning('analyze_poiseuille_profile:noAveragingFrames', 'No frame selected for averaging; using all frames.');
        avgMask(:) = true;
    end

    avgProfile = mean(profiles(:, avgMask), 2, 'omitnan');
    stdProfile = std(profiles(:, avgMask), 0, 2, 'omitnan');

    fit = local_quadratic_fit(coord, avgProfile, p.Results.excludeWallCells);
    acc = local_body_acceleration_for_component(params, flowComponent);
    if isfinite(acc) && abs(acc) > 0 && isfinite(fit.c2) && abs(fit.c2) > 0
        fit.nuEff = -acc / (2.0 * fit.c2);
    else
        fit.nuEff = NaN;
    end

    q = trapz(coord, avgProfile);
    meanVelocity = q / (max(coord) - min(coord));
    [uMax, idxMax] = max(avgProfile);
    uCenter = interp1(coord, avgProfile, 0.5 * (coord(1) + coord(end)), 'linear', 'extrap');

    profileTable = table(coord(:), avgProfile(:), stdProfile(:), fit.fitProfile(:), ...
        'VariableNames', {'coord','Umean','Ustd','Ufit'});

    out = struct();
    out.runDir = runDir;
    out.paramsFile = paramsFile;
    out.params = params;
    out.grid = grid;
    out.summaryTable = summaryTable;
    out.frameTable = frameTable;
    out.avgMask = avgMask;
    out.flowComponent = flowComponent;
    out.profileDirection = profileDirection;
    out.coord = coord;
    out.profiles = profiles;
    out.avgProfile = avgProfile;
    out.stdProfile = stdProfile;
    out.profileTable = profileTable;
    out.fit = fit;
    out.acceleration = acc;
    out.flowRatePerDepth = q;
    out.meanVelocity = meanVelocity;
    out.uMax = uMax;
    out.coordAtUMax = coord(idxMax);
    out.uCenter = uCenter;
    out.wallVelocityLow = avgProfile(1);
    out.wallVelocityHigh = avgProfile(end);

    if p.Results.makePlots
        local_plot_profile(out);
        local_plot_profile_evolution(out);
    end

    if p.Results.saveMat
        if isempty(p.Results.matFile)
            matFile = fullfile(runDir, 'poiseuille_profile.mat');
        else
            matFile = char(p.Results.matFile);
        end
        save(matFile, 'out', '-v7.3');
        fprintf('Saved Poiseuille profile analysis: %s\n', matFile);
    end
end

function fit = local_quadratic_fit(coord, profile, excludeWallCells)
    n = numel(coord);
    excludeWallCells = max(0, round(excludeWallCells));
    idx = (1+excludeWallCells):(n-excludeWallCells);
    idx = idx(:);
    valid = isfinite(profile(idx)) & isfinite(coord(idx));
    idx = idx(valid);
    if numel(idx) < 4
        error('analyze_poiseuille_profile:notEnoughFitPoints', 'Not enough profile points for quadratic fit.');
    end
    s = coord(idx);
    u = profile(idx);
    A = [ones(size(s)), s, s.^2];
    coeff = A \ u;
    fitProfile = [ones(size(coord)), coord(:), coord(:).^2] * coeff;
    residual = u - A * coeff;
    ssRes = sum(residual.^2);
    ssTot = sum((u - mean(u)).^2);
    if ssTot > 0
        r2 = 1.0 - ssRes / ssTot;
    else
        r2 = NaN;
    end
    fit = struct();
    fit.c0 = coeff(1);
    fit.c1 = coeff(2);
    fit.c2 = coeff(3);
    fit.polyCoeff = [coeff(3), coeff(2), coeff(1)];
    fit.fitProfile = fitProfile;
    fit.fitIndices = idx;
    fit.r2 = r2;
    fit.rmsResidual = sqrt(mean(residual.^2));
    fit.nuEff = NaN;
end

function local_plot_profile(out)
    figure('Name', ['Poiseuille profile: ' out.runDir]);
    hold on;
    errorbar(out.coord, out.avgProfile, out.stdProfile, 'o-', 'DisplayName', 'time-avg profile');
    plot(out.coord, out.fit.fitProfile, '-', 'LineWidth', 1.5, 'DisplayName', 'quadratic fit');
    xlabel(out.profileDirection);
    ylabel(upper(out.flowComponent));
    title(sprintf('Poiseuille profile, R^2=%.4g, nu_{eff}=%.4g', out.fit.r2, out.fit.nuEff), 'Interpreter', 'tex');
    legend('Location', 'best');
    grid on;
    hold off;
end

function local_plot_profile_evolution(out)
    figure('Name', ['Poiseuille profile evolution: ' out.runDir]);
    imagesc(out.frameTable.step, out.coord, out.profiles);
    set(gca, 'YDir', 'normal');
    xlabel('step');
    ylabel(out.profileDirection);
    title(['Profile evolution, ' upper(out.flowComponent)], 'Interpreter', 'none');
    colorbar;
end

function grid = local_grid_from_params(params)
    for name = {'Lx','Ly','Nx','Ny'}
        if ~isfield(params, name{1})
            error('analyze_poiseuille_profile:missingGrid', 'Missing %s in params.', name{1});
        end
    end
    grid.Lx = double(params.Lx);
    grid.Ly = double(params.Ly);
    grid.Nx = double(params.Nx);
    grid.Ny = double(params.Ny);
end

function value = local_get_param(params, name, defaultValue)
    if isfield(params, name)
        value = double(params.(name));
    else
        value = defaultValue;
    end
end

function acc = local_body_acceleration_for_component(params, component)
    if strcmp(component, 'ux')
        acc = local_get_param(params, 'bodyAccelerationX', local_get_param(params, 'bodyForceX', 0.0));
    else
        acc = local_get_param(params, 'bodyAccelerationY', local_get_param(params, 'bodyForceY', 0.0));
    end
end

function tf = local_is_periodic_x(params)
    if isfield(params, 'bcX')
        tf = strcmpi(string(params.bcX), 'periodic');
    elseif isfield(params, 'bcLeft') && isfield(params, 'bcRight')
        tf = strcmpi(string(params.bcLeft), 'periodic') && strcmpi(string(params.bcRight), 'periodic');
    else
        tf = true;
    end
end

function tf = local_is_periodic_y(params)
    if isfield(params, 'bcY')
        tf = strcmpi(string(params.bcY), 'periodic');
    elseif isfield(params, 'bcBottom') && isfield(params, 'bcTop')
        tf = strcmpi(string(params.bcBottom), 'periodic') && strcmpi(string(params.bcTop), 'periodic');
    else
        tf = true;
    end
end

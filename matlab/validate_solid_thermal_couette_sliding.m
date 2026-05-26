function out = validate_solid_thermal_couette_sliding(runY, runX, varargin)
%VALIDATE_SOLID_THERMAL_COUETTE_SLIDING Validate tangential solid-wall motion.
%
% out = validate_solid_thermal_couette_sliding( ...
%     'runs/couette_y_solid_thermal_long', ...
%     'runs/couette_x_solid_thermal_long');
%
% The y-channel run is expected to have periodic x, solid y-walls,
% bottom/top wall velocities in x, and profile Ux(y). The x-channel run is
% the transposed validation: periodic y, solid x-walls, left/right wall
% velocities in y, and profile Uy(x). Passing both tests with comparable
% linear profiles validates tangential sliding for the generic solid_thermal
% wall model.

    p = inputParser;
    addRequired(p, 'runY', @(s) ischar(s) || isstring(s));
    addRequired(p, 'runX', @(s) ischar(s) || isstring(s));
    addParameter(p, 'fitStartFraction', 0.5, @isnumeric);
    addParameter(p, 'fitStartStep', [], @isnumeric);
    addParameter(p, 'fitEndStep', [], @isnumeric);
    addParameter(p, 'excludeWallCells', 1, @isnumeric);
    addParameter(p, 'frameStride', 1, @isnumeric);
    addParameter(p, 'stationaryWindowFraction', 0.25, @isnumeric);
    addParameter(p, 'makePlots', true, @islogical);
    addParameter(p, 'saveTables', false, @islogical);
    addParameter(p, 'outputDir', '', @(s) ischar(s) || isstring(s));
    parse(p, runY, runX, varargin{:});

    commonArgs = { ...
        'fitStartFraction', p.Results.fitStartFraction, ...
        'fitStartStep', p.Results.fitStartStep, ...
        'fitEndStep', p.Results.fitEndStep, ...
        'excludeWallCells', p.Results.excludeWallCells, ...
        'frameStride', p.Results.frameStride, ...
        'stationaryWindowFraction', p.Results.stationaryWindowFraction};

    yRun = local_analyze_couette_run(runY, 'ux', 'y', 'bottom', 'top', commonArgs{:});
    xRun = local_analyze_couette_run(runX, 'uy', 'x', 'left', 'right', commonArgs{:});

    metricTable = local_metric_table(yRun, xRun);
    comparisonTable = local_comparison_table(yRun, xRun);

    disp(metricTable);
    disp(comparisonTable);

    if p.Results.makePlots
        local_plot_couette(yRun, xRun, comparisonTable);
    end

    if p.Results.saveTables
        outputDir = char(p.Results.outputDir);
        if isempty(outputDir)
            outputDir = pwd;
        end
        if ~isfolder(outputDir)
            mkdir(outputDir);
        end
        writetable(metricTable, fullfile(outputDir, 'solid_thermal_couette_sliding_metrics.csv'));
        writetable(comparisonTable, fullfile(outputDir, 'solid_thermal_couette_sliding_comparison.csv'));
    end

    out = struct();
    out.yRun = yRun;
    out.xRun = xRun;
    out.metricTable = metricTable;
    out.comparisonTable = comparisonTable;
end

function run = local_analyze_couette_run(runDir, flowComponent, profileDirection, lowFace, highFace, varargin)
    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addRequired(p, 'flowComponent', @(s) ischar(s) || isstring(s));
    addRequired(p, 'profileDirection', @(s) ischar(s) || isstring(s));
    addRequired(p, 'lowFace', @(s) ischar(s) || isstring(s));
    addRequired(p, 'highFace', @(s) ischar(s) || isstring(s));
    addParameter(p, 'fitStartFraction', 0.5, @isnumeric);
    addParameter(p, 'fitStartStep', [], @isnumeric);
    addParameter(p, 'fitEndStep', [], @isnumeric);
    addParameter(p, 'excludeWallCells', 1, @isnumeric);
    addParameter(p, 'frameStride', 1, @isnumeric);
    addParameter(p, 'stationaryWindowFraction', 0.25, @isnumeric);
    parse(p, runDir, flowComponent, profileDirection, lowFace, highFace, varargin{:});

    runDir = char(p.Results.runDir);
    if ~isfolder(runDir)
        error('validate_solid_thermal_couette_sliding:runDirNotFound', 'Cannot find run directory: %s', runDir);
    end

    paramsFile = fullfile(runDir, 'params_used.kv');
    if ~isfile(paramsFile)
        error('validate_solid_thermal_couette_sliding:missingParams', 'Cannot find params_used.kv in %s.', runDir);
    end
    params = parse_smpcd_kv(paramsFile);
    grid = local_grid_from_params(params);

    summaryFile = fullfile(runDir, 'summary_runtime.csv');
    if isfile(summaryFile)
        summaryTable = readtable(summaryFile);
    else
        summaryTable = table();
    end

    frameTable = list_smpcd_dumps(runDir, 'summaryFile', summaryFile);
    if height(frameTable) == 0
        error('validate_solid_thermal_couette_sliding:noDumps', 'No state_step_*.smpcd dumps found in %s.', runDir);
    end

    frameStride = max(1, round(p.Results.frameStride));
    frameTable = frameTable(1:frameStride:height(frameTable), :);

    nFrames = height(frameTable);
    profiles = [];
    coord = [];
    for k = 1:nFrames
        state = read_smpcd_state(char(frameTable.fullPath(k)));
        fields = bin_smpcd_state(state, ...
            'Lx', grid.Lx, 'Ly', grid.Ly, 'Nx', grid.Nx, 'Ny', grid.Ny, ...
            'periodicX', local_is_periodic_x(params), ...
            'periodicY', local_is_periodic_y(params));
        if strcmpi(flowComponent, 'ux')
            U = fields.Ux;
        else
            U = fields.Uy;
        end
        if strcmpi(profileDirection, 'y')
            profile = mean(U, 2, 'omitnan');
            thisCoord = fields.yc(:);
            domainLength = grid.Ly;
        else
            profile = mean(U, 1, 'omitnan').';
            thisCoord = fields.xc(:);
            domainLength = grid.Lx;
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
            startStep = min(finiteSteps) + p.Results.fitStartFraction * (max(finiteSteps) - min(finiteSteps));
        end
    end
    endStep = p.Results.fitEndStep;
    if isempty(endStep)
        endStep = Inf;
    end
    avgMask = steps >= startStep & steps <= endStep;
    if ~any(avgMask)
        warning('validate_solid_thermal_couette_sliding:emptyAverageWindow', ...
            'No frames selected by average window; using all frames.');
        avgMask = true(size(steps));
    end

    avgProfile = mean(profiles(:, avgMask), 2, 'omitnan');
    stdProfile = std(profiles(:, avgMask), 0, 2, 'omitnan');

    wallLow = local_wall_velocity(params, char(lowFace), char(flowComponent));
    wallHigh = local_wall_velocity(params, char(highFace), char(flowComponent));
    expectedSlope = (wallHigh - wallLow) / domainLength;

    fit = local_fit_linear(coord, avgProfile, p.Results.excludeWallCells, domainLength, wallLow, wallHigh);
    frameMetrics = local_frame_metrics(coord, profiles, steps, summaryTable, p.Results.excludeWallCells, domainLength, wallLow, wallHigh);
    stationarity = local_stationarity_table(frameMetrics, summaryTable, p.Results.stationaryWindowFraction);

    run = struct();
    run.runDir = runDir;
    run.params = params;
    run.grid = grid;
    run.summaryTable = summaryTable;
    run.frameTable = frameTable;
    run.flowComponent = lower(char(flowComponent));
    run.profileDirection = lower(char(profileDirection));
    run.coord = coord;
    run.profiles = profiles;
    run.avgMask = avgMask;
    run.avgProfile = avgProfile;
    run.stdProfile = stdProfile;
    run.fit = fit;
    run.frameMetrics = frameMetrics;
    run.stationarity = stationarity;
    run.wallVelocityLow = wallLow;
    run.wallVelocityHigh = wallHigh;
    run.expectedSlope = expectedSlope;
    run.domainLength = domainLength;
    run.uMean = mean(avgProfile, 'omitnan');
    run.uLow = avgProfile(1);
    run.uHigh = avgProfile(end);
    run.slipLow = run.uLow - wallLow;
    run.slipHigh = run.uHigh - wallHigh;
end

function fit = local_fit_linear(coord, profile, excludeWallCells, domainLength, wallLow, wallHigh)
    n = numel(coord);
    idx = true(n, 1);
    e = max(0, round(excludeWallCells));
    if e > 0 && 2 * e < n
        idx(1:e) = false;
        idx(end-e+1:end) = false;
    end
    idx = idx & isfinite(coord(:)) & isfinite(profile(:));
    if nnz(idx) < 2
        fit = struct('coeff', [NaN; NaN], 'fitProfile', nan(size(profile)), ...
            'r2', NaN, 'rmsResidual', NaN, 'slope', NaN, 'intercept', NaN, ...
            'expectedSlope', (wallHigh - wallLow) / domainLength, 'slopeRelError', NaN);
        return;
    end
    X = [ones(nnz(idx), 1), coord(idx)];
    coeff = X \ profile(idx);
    fitProfile = coeff(1) + coeff(2) * coord(:);
    residual = profile(idx) - fitProfile(idx);
    ssRes = sum(residual.^2);
    centered = profile(idx) - mean(profile(idx), 'omitnan');
    ssTot = sum(centered.^2);
    if ssTot > 0
        r2 = 1.0 - ssRes / ssTot;
    else
        r2 = NaN;
    end
    rmsResidual = sqrt(mean(residual.^2));
    expectedSlope = (wallHigh - wallLow) / domainLength;
    slopeRelError = abs(coeff(2) - expectedSlope) / local_scale([expectedSlope, coeff(2)]);

    fit = struct();
    fit.coeff = coeff;
    fit.fitProfile = fitProfile;
    fit.r2 = r2;
    fit.rmsResidual = rmsResidual;
    fit.slope = coeff(2);
    fit.intercept = coeff(1);
    fit.expectedSlope = expectedSlope;
    fit.slopeRelError = slopeRelError;
end

function T = local_frame_metrics(coord, profiles, steps, summaryTable, excludeWallCells, domainLength, wallLow, wallHigh)
    nFrames = size(profiles, 2);
    step = steps(:);
    slope = nan(nFrames, 1);
    r2 = nan(nFrames, 1);
    rmsResidual = nan(nFrames, 1);
    slopeRelError = nan(nFrames, 1);
    uMean = nan(nFrames, 1);
    slipLow = nan(nFrames, 1);
    slipHigh = nan(nFrames, 1);

    for k = 1:nFrames
        prof = profiles(:, k);
        f = local_fit_linear(coord, prof, excludeWallCells, domainLength, wallLow, wallHigh);
        slope(k) = f.slope;
        r2(k) = f.r2;
        rmsResidual(k) = f.rmsResidual;
        slopeRelError(k) = f.slopeRelError;
        uMean(k) = mean(prof, 'omitnan');
        slipLow(k) = prof(1) - wallLow;
        slipHigh(k) = prof(end) - wallHigh;
    end

    T = table(step, slope, r2, rmsResidual, slopeRelError, uMean, slipLow, slipHigh);

    if ~isempty(summaryTable) && ismember('step', summaryTable.Properties.VariableNames)
        summaryStep = summaryTable.step;
        candidates = {'kBTEstimate','kBT','totalMass','Px','Py','thermostatKBTAfter','thermostatScaleMean'};
        for c = 1:numel(candidates)
            name = candidates{c};
            if ismember(name, summaryTable.Properties.VariableNames)
                T.(name) = interp1(double(summaryStep), double(summaryTable.(name)), double(step), 'nearest', 'extrap');
            end
        end
    end
end

function T = local_stationarity_table(frameMetrics, summaryTable, tailFraction)
    names = {'slope','r2','slopeRelError','uMean','slipLow','slipHigh', ...
        'kBT','thermostatKBTAfter','thermostatScaleMean'};
    name = strings(numel(names), 1);
    meanValue = nan(numel(names), 1);
    stdValue = nan(numel(names), 1);
    slopePerStep = nan(numel(names), 1);
    relativeDriftOverTail = nan(numel(names), 1);
    firstValue = nan(numel(names), 1);
    lastValue = nan(numel(names), 1);
    nSamples = zeros(numel(names), 1);

    if isempty(frameMetrics) || height(frameMetrics) == 0
        T = table(name, meanValue, stdValue, slopePerStep, relativeDriftOverTail, firstValue, lastValue, nSamples);
        return;
    end

    nTail = max(1, round(max(0, min(1, tailFraction)) * height(frameMetrics)));
    tailIdx = (height(frameMetrics) - nTail + 1):height(frameMetrics);
    x = double(frameMetrics.step(tailIdx));
    if numel(unique(x)) < 2
        x = (1:numel(tailIdx)).';
    end

    for k = 1:numel(names)
        metric = names{k};
        source = '';
        if ismember(metric, frameMetrics.Properties.VariableNames)
            source = metric;
        elseif strcmp(metric, 'kBT') && ismember('kBTEstimate', frameMetrics.Properties.VariableNames)
            source = 'kBTEstimate';
        elseif ~isempty(summaryTable) && ismember(metric, summaryTable.Properties.VariableNames)
            % Fallback: sample from the raw summary tail if not present in frame metrics.
            valsSummary = double(summaryTable.(metric));
            valsSummary = valsSummary(max(1, end-nTail+1):end);
            stepsSummary = double(summaryTable.step(max(1, end-nTail+1):end));
            [meanValue(k), stdValue(k), slopePerStep(k), relativeDriftOverTail(k), firstValue(k), lastValue(k), nSamples(k)] = ...
                local_series_stats(valsSummary, stepsSummary);
            name(k) = string(metric);
            continue;
        end
        name(k) = string(metric);
        if isempty(source)
            continue;
        end
        vals = double(frameMetrics.(source)(tailIdx));
        [meanValue(k), stdValue(k), slopePerStep(k), relativeDriftOverTail(k), firstValue(k), lastValue(k), nSamples(k)] = ...
            local_series_stats(vals, x);
    end

    T = table(name, meanValue, stdValue, slopePerStep, relativeDriftOverTail, firstValue, lastValue, nSamples);
end

function [mu, sig, slopePerStep, relDrift, firstValue, lastValue, nSamples] = local_series_stats(vals, x)
    valid = isfinite(vals) & isfinite(x);
    vals = vals(valid);
    x = x(valid);
    nSamples = numel(vals);
    if isempty(vals)
        mu = NaN; sig = NaN; slopePerStep = NaN; relDrift = NaN; firstValue = NaN; lastValue = NaN;
        return;
    end
    mu = mean(vals, 'omitnan');
    sig = std(vals, 0, 'omitnan');
    firstValue = vals(1);
    lastValue = vals(end);
    if numel(vals) >= 2 && numel(unique(x)) >= 2
        c = polyfit(x(:), vals(:), 1);
        slopePerStep = c(1);
        relDrift = (c(1) * (max(x) - min(x))) / local_scale(vals);
    else
        slopePerStep = NaN;
        relDrift = NaN;
    end
end

function T = local_metric_table(yRun, xRun)
    runs = {yRun, xRun};
    label = ["y-walls Ux(y)"; "x-walls Uy(x)"];
    runDir = strings(2, 1);
    flowComponent = strings(2, 1);
    profileDirection = strings(2, 1);
    nFrames = zeros(2, 1);
    nAveragedFrames = zeros(2, 1);
    r2LinearMean = nan(2, 1);
    slopeMean = nan(2, 1);
    expectedSlope = nan(2, 1);
    slopeRelError = nan(2, 1);
    uMean = nan(2, 1);
    uLow = nan(2, 1);
    uHigh = nan(2, 1);
    wallLow = nan(2, 1);
    wallHigh = nan(2, 1);
    slipLow = nan(2, 1);
    slipHigh = nan(2, 1);
    rmsResidual = nan(2, 1);
    kBTTailMean = nan(2, 1);
    kBTTailRelDrift = nan(2, 1);
    thermostatKBTAfterTailMean = nan(2, 1);
    thermostatScaleMeanTailMean = nan(2, 1);

    for k = 1:2
        r = runs{k};
        runDir(k) = string(r.runDir);
        flowComponent(k) = string(r.flowComponent);
        profileDirection(k) = string(r.profileDirection);
        nFrames(k) = height(r.frameTable);
        nAveragedFrames(k) = sum(r.avgMask);
        r2LinearMean(k) = r.fit.r2;
        slopeMean(k) = r.fit.slope;
        expectedSlope(k) = r.fit.expectedSlope;
        slopeRelError(k) = r.fit.slopeRelError;
        uMean(k) = r.uMean;
        uLow(k) = r.uLow;
        uHigh(k) = r.uHigh;
        wallLow(k) = r.wallVelocityLow;
        wallHigh(k) = r.wallVelocityHigh;
        slipLow(k) = r.slipLow;
        slipHigh(k) = r.slipHigh;
        rmsResidual(k) = r.fit.rmsResidual;
        kBTTailMean(k) = local_stationarity_value(r.stationarity, 'kBT', 'meanValue');
        kBTTailRelDrift(k) = local_stationarity_value(r.stationarity, 'kBT', 'relativeDriftOverTail');
        thermostatKBTAfterTailMean(k) = local_stationarity_value(r.stationarity, 'thermostatKBTAfter', 'meanValue');
        thermostatScaleMeanTailMean(k) = local_stationarity_value(r.stationarity, 'thermostatScaleMean', 'meanValue');
    end

    T = table(label, runDir, flowComponent, profileDirection, nFrames, nAveragedFrames, ...
        r2LinearMean, slopeMean, expectedSlope, slopeRelError, uMean, uLow, uHigh, ...
        wallLow, wallHigh, slipLow, slipHigh, rmsResidual, kBTTailMean, ...
        kBTTailRelDrift, thermostatKBTAfterTailMean, thermostatScaleMeanTailMean);
end

function T = local_comparison_table(yRun, xRun)
    coord = yRun.coord(:);
    xProfile = interp1(xRun.coord(:), xRun.avgProfile(:), coord, 'linear', 'extrap');
    yProfile = yRun.avgProfile(:);
    diffProfile = yProfile - xProfile;
    scale = local_scale([yProfile(:); xProfile(:)]);

    slopeAbsDiff = abs(yRun.fit.slope - xRun.fit.slope);
    slopeRelDiff = slopeAbsDiff / local_scale([yRun.fit.slope, xRun.fit.slope]);
    slopeRelErrorMax = max(yRun.fit.slopeRelError, xRun.fit.slopeRelError);
    slipLowAbsDiff = abs(yRun.slipLow - xRun.slipLow);
    slipHighAbsDiff = abs(yRun.slipHigh - xRun.slipHigh);

    validDiff = diffProfile(isfinite(diffProfile));
    if isempty(validDiff)
        profileRmsDiff = NaN;
        profileMaxAbsDiff = NaN;
    else
        profileRmsDiff = sqrt(mean(validDiff.^2));
        profileMaxAbsDiff = max(abs(validDiff));
    end
    profileRmsDiffNormalized = profileRmsDiff / scale;
    profileMaxAbsDiffNormalized = profileMaxAbsDiff / scale;

    r2Min = min(yRun.fit.r2, xRun.fit.r2);
    kBTTailMeanY = local_stationarity_value(yRun.stationarity, 'kBT', 'meanValue');
    kBTTailMeanX = local_stationarity_value(xRun.stationarity, 'kBT', 'meanValue');
    kBTTailAbsDiff = abs(kBTTailMeanY - kBTTailMeanX);

    T = table(slopeAbsDiff, slopeRelDiff, slopeRelErrorMax, slipLowAbsDiff, slipHighAbsDiff, ...
        profileRmsDiff, profileRmsDiffNormalized, profileMaxAbsDiff, profileMaxAbsDiffNormalized, ...
        r2Min, kBTTailAbsDiff);
end

function local_plot_couette(yRun, xRun, comparisonTable)
    coord = yRun.coord(:);
    xProfileOnY = interp1(xRun.coord(:), xRun.avgProfile(:), coord, 'linear', 'extrap');
    yProfile = yRun.avgProfile(:);

    figure('Name', 'Solid thermal Couette sliding validation');
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    hold on;
    errorbar(yRun.coord, yRun.avgProfile, yRun.stdProfile, 'o-', 'DisplayName', 'y-walls: Ux(y)');
    errorbar(xRun.coord, xRun.avgProfile, xRun.stdProfile, 's-', 'DisplayName', 'x-walls: Uy(x)');
    plot(yRun.coord, yRun.fit.fitProfile, '-', 'DisplayName', 'fit y-walls');
    plot(xRun.coord, xRun.fit.fitProfile, '-', 'DisplayName', 'fit x-walls');
    plot(yRun.coord, yRun.wallVelocityLow + yRun.expectedSlope * yRun.coord, '--', 'DisplayName', 'expected linear');
    xlabel('transverse coordinate');
    ylabel('velocity');
    title('Mean Couette profiles');
    legend('Location', 'best', 'Interpreter', 'none');
    grid on;
    hold off;

    nexttile;
    hold on;
    plot(yRun.coord, local_normalize_couette(yRun.coord, yRun.avgProfile, yRun.wallVelocityLow, yRun.wallVelocityHigh), 'o-', ...
        'DisplayName', 'y-walls normalized');
    plot(xRun.coord, local_normalize_couette(xRun.coord, xRun.avgProfile, xRun.wallVelocityLow, xRun.wallVelocityHigh), 's-', ...
        'DisplayName', 'x-walls normalized');
    plot([0; 1], [0; 1], 'k--', 'DisplayName', 'ideal linear');
    xlabel('normalized transverse coordinate');
    ylabel('normalized velocity');
    title('Normalized linearity comparison');
    legend('Location', 'best', 'Interpreter', 'none');
    grid on;
    hold off;

    nexttile;
    plot(coord, yProfile - xProfileOnY, 'o-');
    xlabel('transverse coordinate');
    ylabel('Ux(y) - Uy(x)');
    title(sprintf('Profile difference, RMS/scale = %.3g', comparisonTable.profileRmsDiffNormalized(1)));
    grid on;

    nexttile;
    names = categorical({'slope rel diff','slope err max','profile RMS norm','profile max norm'});
    vals = [comparisonTable.slopeRelDiff(1), comparisonTable.slopeRelErrorMax(1), ...
        comparisonTable.profileRmsDiffNormalized(1), comparisonTable.profileMaxAbsDiffNormalized(1)];
    bar(names, vals);
    ylabel('relative metric');
    title('Sliding-wall metrics');
    grid on;
end

function y = local_normalize_couette(coord, profile, wallLow, wallHigh)
    denom = wallHigh - wallLow;
    if abs(denom) < eps
        denom = local_scale(profile);
    end
    y = (profile(:) - wallLow) ./ denom;
    coord = coord(:);
    c0 = min(coord);
    c1 = max(coord);
    if c1 > c0
        % Resample coordinates into [0,1] only through the x-axis values of the plot.
        % The caller uses physical coordinates; the ideal line is shown separately.
    end
end

function value = local_wall_velocity(params, face, component)
    face = lower(face);
    component = lower(component);
    if strcmp(component, 'ux')
        prefix = 'wallUx';
        legacyPrefix = 'wallVpUx';
    else
        prefix = 'wallUy';
        legacyPrefix = 'wallVpUy';
    end
    key = [prefix upper(face(1)) face(2:end)];
    legacyKey = [legacyPrefix upper(face(1)) face(2:end)];
    if isfield(params, key)
        value = double(params.(key));
    elseif isfield(params, legacyKey)
        value = double(params.(legacyKey));
    else
        value = 0.0;
    end
end

function grid = local_grid_from_params(params)
    for name = {'Lx','Ly','Nx','Ny'}
        if ~isfield(params, name{1})
            error('validate_solid_thermal_couette_sliding:missingGrid', 'Missing %s in params.', name{1});
        end
    end
    grid.Lx = double(params.Lx);
    grid.Ly = double(params.Ly);
    grid.Nx = double(params.Nx);
    grid.Ny = double(params.Ny);
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

function scale = local_scale(values)
    values = values(isfinite(values));
    if isempty(values)
        scale = eps;
    else
        scale = max(abs(values));
        if scale <= 0 || ~isfinite(scale)
            scale = eps;
        end
    end
end

function value = local_stationarity_value(stationarity, metricName, columnName)
    value = NaN;
    if isempty(stationarity) || ~ismember('name', stationarity.Properties.VariableNames) ...
            || ~ismember(columnName, stationarity.Properties.VariableNames)
        return;
    end
    idx = find(stationarity.name == string(metricName), 1, 'first');
    if ~isempty(idx)
        value = stationarity.(columnName)(idx);
    end
end

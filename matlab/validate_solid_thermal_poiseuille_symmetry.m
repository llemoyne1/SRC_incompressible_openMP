function out = validate_solid_thermal_poiseuille_symmetry(runY, runX, varargin)
%VALIDATE_SOLID_THERMAL_POISEUILLE_SYMMETRY Compare y-channel and x-channel Poiseuille runs.
%
% out = validate_solid_thermal_poiseuille_symmetry( ...
%     'runs/poiseuille_y_solid_thermal_long', ...
%     'runs/poiseuille_x_solid_thermal_long');
%
% The y-channel run is expected to have periodic x, solid y-walls,
% acceleration in x, and profile Ux(y). The x-channel run is the transposed
% validation: periodic y, solid x-walls, acceleration in y, and profile Uy(x).
% Passing both tests with comparable profiles and nu_eff validates that the
% generic solid_thermal boundary model is not hard-wired to a particular axis.

    p = inputParser;
    addRequired(p, 'runY', @(s) ischar(s) || isstring(s));
    addRequired(p, 'runX', @(s) ischar(s) || isstring(s));
    addParameter(p, 'fitStartFraction', 0.5, @isnumeric);
    addParameter(p, 'fitStartStep', [], @isnumeric);
    addParameter(p, 'fitEndStep', [], @isnumeric);
    addParameter(p, 'excludeWallCells', 2, @isnumeric);
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
        'stationaryWindowFraction', p.Results.stationaryWindowFraction, ...
        'plotConvergence', false, ...
        'makePlots', false};

    yRun = analyze_poiseuille_profile(runY, ...
        'flowComponent', 'Ux', ...
        'profileDirection', 'y', ...
        commonArgs{:});

    xRun = analyze_poiseuille_profile(runX, ...
        'flowComponent', 'Uy', ...
        'profileDirection', 'x', ...
        commonArgs{:});

    metricTable = local_metric_table(yRun, xRun);
    comparisonTable = local_comparison_table(yRun, xRun);

    disp(metricTable);
    disp(comparisonTable);

    if p.Results.makePlots
        local_plot_symmetry(yRun, xRun, comparisonTable);
    end

    if p.Results.saveTables
        outputDir = char(p.Results.outputDir);
        if isempty(outputDir)
            outputDir = pwd;
        end
        if ~isfolder(outputDir)
            mkdir(outputDir);
        end
        writetable(metricTable, fullfile(outputDir, 'solid_thermal_poiseuille_symmetry_metrics.csv'));
        writetable(comparisonTable, fullfile(outputDir, 'solid_thermal_poiseuille_symmetry_comparison.csv'));
    end

    out = struct();
    out.yRun = yRun;
    out.xRun = xRun;
    out.metricTable = metricTable;
    out.comparisonTable = comparisonTable;
end

function T = local_metric_table(yRun, xRun)
    runs = {yRun, xRun};
    label = ["y-walls Ux(y)"; "x-walls Uy(x)"];
    runDir = strings(2, 1);
    flowComponent = strings(2, 1);
    profileDirection = strings(2, 1);
    nFrames = zeros(2, 1);
    nAveragedFrames = zeros(2, 1);
    r2ProfileMean = nan(2, 1);
    nuEffProfileMean = nan(2, 1);
    uCenter = nan(2, 1);
    uMean = nan(2, 1);
    centerMinusWall = nan(2, 1);
    wallLow = nan(2, 1);
    wallHigh = nan(2, 1);
    wallAsymmetry = nan(2, 1);
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
        r2ProfileMean(k) = r.fit.r2;
        nuEffProfileMean(k) = r.fit.nuEff;
        uCenter(k) = r.uCenter;
        uMean(k) = r.meanVelocity;
        centerMinusWall(k) = r.uCenter - 0.5 * (r.wallVelocityLow + r.wallVelocityHigh);
        wallLow(k) = r.wallVelocityLow;
        wallHigh(k) = r.wallVelocityHigh;
        wallAsymmetry(k) = r.wallVelocityLow - r.wallVelocityHigh;
        rmsResidual(k) = r.fit.rmsResidual;
        kBTTailMean(k) = local_stationarity_value(r.stationarity, 'kBT', 'meanValue');
        kBTTailRelDrift(k) = local_stationarity_value(r.stationarity, 'kBT', 'relativeDriftOverTail');
        thermostatKBTAfterTailMean(k) = local_stationarity_value(r.stationarity, 'thermostatKBTAfter', 'meanValue');
        thermostatScaleMeanTailMean(k) = local_stationarity_value(r.stationarity, 'thermostatScaleMean', 'meanValue');
    end

    T = table(label, runDir, flowComponent, profileDirection, nFrames, nAveragedFrames, ...
        r2ProfileMean, nuEffProfileMean, uCenter, uMean, centerMinusWall, ...
        wallLow, wallHigh, wallAsymmetry, rmsResidual, kBTTailMean, ...
        kBTTailRelDrift, thermostatKBTAfterTailMean, thermostatScaleMeanTailMean);
end

function T = local_comparison_table(yRun, xRun)
    coord = yRun.coord(:);
    xProfile = interp1(xRun.coord(:), xRun.avgProfile(:), coord, 'linear', 'extrap');
    yProfile = yRun.avgProfile(:);
    diffProfile = yProfile - xProfile;
    scale = local_scale([yProfile(:); xProfile(:)]);

    nuY = yRun.fit.nuEff;
    nuX = xRun.fit.nuEff;
    nuEffAbsDiff = abs(nuY - nuX);
    nuEffRelDiff = nuEffAbsDiff / local_scale([nuY, nuX]);

    centerMinusWallY = yRun.uCenter - 0.5 * (yRun.wallVelocityLow + yRun.wallVelocityHigh);
    centerMinusWallX = xRun.uCenter - 0.5 * (xRun.wallVelocityLow + xRun.wallVelocityHigh);
    centerMinusWallAbsDiff = abs(centerMinusWallY - centerMinusWallX);
    centerMinusWallRelDiff = centerMinusWallAbsDiff / local_scale([centerMinusWallY, centerMinusWallX]);

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

    T = table(nuEffAbsDiff, nuEffRelDiff, centerMinusWallAbsDiff, centerMinusWallRelDiff, ...
        profileRmsDiff, profileRmsDiffNormalized, profileMaxAbsDiff, profileMaxAbsDiffNormalized, ...
        r2Min, kBTTailAbsDiff);
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

function local_plot_symmetry(yRun, xRun, comparisonTable)
    coord = yRun.coord(:);
    xProfileOnY = interp1(xRun.coord(:), xRun.avgProfile(:), coord, 'linear', 'extrap');
    yProfile = yRun.avgProfile(:);

    figure('Name', 'Solid thermal Poiseuille symmetry validation');
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    hold on;
    errorbar(yRun.coord, yRun.avgProfile, yRun.stdProfile, 'o-', 'DisplayName', 'y-walls: Ux(y)');
    errorbar(xRun.coord, xRun.avgProfile, xRun.stdProfile, 's-', 'DisplayName', 'x-walls: Uy(x)');
    plot(yRun.coord, yRun.fit.fitProfile, '-', 'DisplayName', 'fit y-walls');
    plot(xRun.coord, xRun.fit.fitProfile, '-', 'DisplayName', 'fit x-walls');
    xlabel('transverse coordinate');
    ylabel('velocity');
    title('Mean profiles');
    legend('Location', 'best', 'Interpreter', 'none');
    grid on;
    hold off;

    nexttile;
    scaleY = local_scale(yProfile);
    scaleX = local_scale(xRun.avgProfile(:));
    hold on;
    plot(yRun.coord, yRun.avgProfile ./ scaleY, 'o-', 'DisplayName', 'y-walls normalized');
    plot(xRun.coord, xRun.avgProfile ./ scaleX, 's-', 'DisplayName', 'x-walls normalized');
    xlabel('transverse coordinate');
    ylabel('normalized velocity');
    title('Normalized shape comparison');
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
    names = categorical({'nu rel diff','center-wall rel diff','profile RMS norm','profile max norm'});
    vals = [comparisonTable.nuEffRelDiff(1), comparisonTable.centerMinusWallRelDiff(1), ...
        comparisonTable.profileRmsDiffNormalized(1), comparisonTable.profileMaxAbsDiffNormalized(1)];
    bar(names, vals);
    ylabel('relative difference');
    title('Symmetry metrics');
    grid on;
end

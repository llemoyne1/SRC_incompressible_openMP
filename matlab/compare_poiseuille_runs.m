function out = compare_poiseuille_runs(runDirs, varargin)
%COMPARE_POISEUILLE_RUNS Compare time-averaged Poiseuille profiles.
%
% out = compare_poiseuille_runs({'runs/poiseuille_y_specular', ...
%                                'runs/poiseuille_y_bounceback', ...
%                                'runs/poiseuille_y_bounceback_vp'});

    p = inputParser;
    addRequired(p, 'runDirs', @(x) iscell(x) || isstring(x));
    addParameter(p, 'labels', {}, @(x) iscell(x) || isstring(x));
    addParameter(p, 'flowComponent', 'Ux', @(s) ischar(s) || isstring(s));
    addParameter(p, 'profileDirection', 'y', @(s) ischar(s) || isstring(s));
    addParameter(p, 'fitStartFraction', 0.5, @isnumeric);
    addParameter(p, 'excludeWallCells', 1, @isnumeric);
    addParameter(p, 'frameStride', 1, @isnumeric);
    addParameter(p, 'makePlots', true, @islogical);
    addParameter(p, 'plotConvergence', true, @islogical);
    addParameter(p, 'stationaryWindowFraction', 0.25, @isnumeric);
    parse(p, runDirs, varargin{:});

    if isstring(runDirs)
        runDirs = cellstr(runDirs(:));
    end
    labels = p.Results.labels;
    if isstring(labels)
        labels = cellstr(labels(:));
    end
    if isempty(labels)
        labels = runDirs;
    end
    if numel(labels) ~= numel(runDirs)
        error('compare_poiseuille_runs:badLabels', 'labels must have the same length as runDirs.');
    end

    results = cell(numel(runDirs), 1);
    for k = 1:numel(runDirs)
        results{k} = analyze_poiseuille_profile(runDirs{k}, ...
            'flowComponent', p.Results.flowComponent, ...
            'profileDirection', p.Results.profileDirection, ...
            'fitStartFraction', p.Results.fitStartFraction, ...
            'excludeWallCells', p.Results.excludeWallCells, ...
            'frameStride', p.Results.frameStride, ...
            'stationaryWindowFraction', p.Results.stationaryWindowFraction, ...
            'plotConvergence', false, ...
            'makePlots', false);
    end

    if p.Results.makePlots
        local_plot_profile_comparison(results, labels, p.Results.profileDirection, p.Results.flowComponent);
        if p.Results.plotConvergence
            local_plot_metric_comparison(results, labels);
        end
    end

    metricTable = local_metric_table(results, labels, runDirs);
    disp(metricTable);

    out = struct();
    out.results = results;
    out.metricTable = metricTable;
end

function T = local_metric_table(results, labels, runDirs)
    n = numel(results);
    label = strings(n,1);
    runDir = strings(n,1);
    nFrames = zeros(n,1);
    r2 = nan(n,1);
    nuEff = nan(n,1);
    nuEffTailMean = nan(n,1);
    nuEffTailStd = nan(n,1);
    nuEffTailRelDrift = nan(n,1);
    uMax = nan(n,1);
    uCenter = nan(n,1);
    uMean = nan(n,1);
    centerMinusWall = nan(n,1);
    wallLow = nan(n,1);
    wallHigh = nan(n,1);
    wallAsymmetry = nan(n,1);
    rmsResidual = nan(n,1);
    kBTTailMean = nan(n,1);
    kBTTailRelDrift = nan(n,1);
    thermostatKBTAfterTailMean = nan(n,1);
    thermostatScaleMeanTailMean = nan(n,1);
    r2TailMean = nan(n,1);
    for k = 1:n
        r = results{k};
        label(k) = string(labels{k});
        runDir(k) = string(runDirs{k});
        nFrames(k) = sum(r.avgMask);
        r2(k) = r.fit.r2;
        nuEff(k) = r.fit.nuEff;
        uMax(k) = r.uMax;
        uCenter(k) = r.uCenter;
        uMean(k) = r.meanVelocity;
        centerMinusWall(k) = r.uCenter - 0.5 * (r.wallVelocityLow + r.wallVelocityHigh);
        wallLow(k) = r.wallVelocityLow;
        wallHigh(k) = r.wallVelocityHigh;
        wallAsymmetry(k) = r.wallVelocityLow - r.wallVelocityHigh;
        rmsResidual(k) = r.fit.rmsResidual;
        nuEffTailMean(k) = local_stationarity_value(r.stationarity, 'nuEff', 'meanValue');
        nuEffTailStd(k) = local_stationarity_value(r.stationarity, 'nuEff', 'stdValue');
        nuEffTailRelDrift(k) = local_stationarity_value(r.stationarity, 'nuEff', 'relativeDriftOverTail');
        kBTTailMean(k) = local_stationarity_value(r.stationarity, 'kBT', 'meanValue');
        kBTTailRelDrift(k) = local_stationarity_value(r.stationarity, 'kBT', 'relativeDriftOverTail');
        thermostatKBTAfterTailMean(k) = local_stationarity_value(r.stationarity, 'thermostatKBTAfter', 'meanValue');
        thermostatScaleMeanTailMean(k) = local_stationarity_value(r.stationarity, 'thermostatScaleMean', 'meanValue');
        r2TailMean(k) = local_stationarity_value(r.stationarity, 'r2', 'meanValue');
    end
    T = table(label, runDir, nFrames, r2, r2TailMean, nuEff, nuEffTailMean, ...
        nuEffTailStd, nuEffTailRelDrift, uMax, uCenter, uMean, centerMinusWall, ...
        wallLow, wallHigh, wallAsymmetry, rmsResidual, kBTTailMean, kBTTailRelDrift, ...
        thermostatKBTAfterTailMean, thermostatScaleMeanTailMean);
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

function local_plot_profile_comparison(results, labels, profileDirection, flowComponent)
    figure('Name', 'Poiseuille profile comparison');
    hold on;
    for k = 1:numel(results)
        plot(results{k}.coord, results{k}.avgProfile, 'o-', 'DisplayName', labels{k});
    end
    xlabel(char(profileDirection));
    ylabel(char(flowComponent));
    title('Time-averaged Poiseuille profiles', 'Interpreter', 'none');
    legend('Location', 'best', 'Interpreter', 'none');
    grid on;
    hold off;
end

function local_plot_metric_comparison(results, labels)
    figure('Name', 'Poiseuille calibration metrics');
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    hold on;
    for k = 1:numel(results)
        fm = results{k}.frameMetrics;
        plot(fm.step, fm.nuEff, 'o-', 'DisplayName', labels{k});
    end
    xlabel('step');
    ylabel('\nu_{eff}', 'Interpreter', 'tex');
    title('Effective viscosity history');
    legend('Location', 'best', 'Interpreter', 'none');
    grid on;
    hold off;

    nexttile;
    hold on;
    for k = 1:numel(results)
        fm = results{k}.frameMetrics;
        plot(fm.step, fm.r2, 'o-', 'DisplayName', labels{k});
    end
    xlabel('step');
    ylabel('R^2');
    title('Quadratic fit quality');
    grid on;
    hold off;

    nexttile;
    hold on;
    for k = 1:numel(results)
        fm = results{k}.frameMetrics;
        plot(fm.step, fm.centerMinusWall, 'o-', 'DisplayName', labels{k});
    end
    xlabel('step');
    ylabel('center-wall velocity');
    title('No-slip indicator');
    grid on;
    hold off;

    nexttile;
    hold on;
    for k = 1:numel(results)
        fm = results{k}.frameMetrics;
        plot(fm.step, fm.kBT, 'o-', 'DisplayName', labels{k});
    end
    xlabel('step');
    ylabel('kBT');
    title('Thermal control');
    grid on;
    hold off;
end

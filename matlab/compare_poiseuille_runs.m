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
            'makePlots', false);
    end

    if p.Results.makePlots
        figure('Name', 'Poiseuille profile comparison');
        hold on;
        for k = 1:numel(results)
            plot(results{k}.coord, results{k}.avgProfile, 'o-', 'DisplayName', labels{k});
        end
        xlabel(char(p.Results.profileDirection));
        ylabel(char(p.Results.flowComponent));
        title('Time-averaged Poiseuille profiles', 'Interpreter', 'none');
        legend('Location', 'best', 'Interpreter', 'none');
        grid on;
        hold off;
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
    uMax = nan(n,1);
    uCenter = nan(n,1);
    uMean = nan(n,1);
    wallLow = nan(n,1);
    wallHigh = nan(n,1);
    rmsResidual = nan(n,1);
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
        wallLow(k) = r.wallVelocityLow;
        wallHigh(k) = r.wallVelocityHigh;
        rmsResidual(k) = r.fit.rmsResidual;
    end
    T = table(label, runDir, nFrames, r2, nuEff, uMax, uCenter, uMean, wallLow, wallHigh, rmsResidual);
end

function out = validate_minimal_piston(runDirs, varargin)
%VALIDATE_MINIMAL_PISTON Validate moving-top-wall piston summary diagnostics.
%
% out = validate_minimal_piston({ ...
%     '../runs/piston_y_solid_thermal_isothermal', ...
%     '../runs/piston_y_solid_thermal_unthermostatted'}, ...
%     'labels', {'isothermal','unthermostatted'}, ...
%     'makePlots', true);
%
% This validator intentionally uses summary_runtime.csv only. It checks the
% active-domain and conservation diagnostics that are not robustly recoverable
% from particle dumps alone once the fluid domain moves.

    if nargin < 1 || isempty(runDirs)
        runDirs = {'../runs/piston_y_solid_thermal_isothermal'};
    end

    p = inputParser;
    addRequired(p, 'runDirs', @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'labels', {}, @(x) iscell(x) || isstring(x));
    addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'saveTables', false, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'outputDir', '', @(s) ischar(s) || isstring(s));
    parse(p, runDirs, varargin{:});

    runDirs = local_cellstr(p.Results.runDirs);
    labels = local_cellstr(p.Results.labels);
    if isempty(labels)
        labels = runDirs;
    end
    if numel(labels) ~= numel(runDirs)
        error('validate_minimal_piston:labelMismatch', ...
            'labels must have the same length as runDirs.');
    end

    n = numel(runDirs);
    summaries = cell(n, 1);
    metricRows = cell(n, 1);
    for k = 1:n
        summaryFile = fullfile(runDirs{k}, 'summary_runtime.csv');
        if ~isfile(summaryFile)
            error('validate_minimal_piston:missingSummary', ...
                'Cannot find summary file: %s', summaryFile);
        end
        S = readtable(summaryFile);
        summaries{k} = S;
        metricRows{k} = local_metrics_for_run(labels{k}, runDirs{k}, S);
    end

    metricTable = vertcat(metricRows{:});
    disp(metricTable);

    if p.Results.makePlots
        local_plot_piston(summaries, labels);
    end

    if p.Results.saveTables
        outputDir = char(p.Results.outputDir);
        if isempty(outputDir)
            outputDir = pwd;
        end
        if ~isfolder(outputDir)
            mkdir(outputDir);
        end
        writetable(metricTable, fullfile(outputDir, 'minimal_piston_metrics.csv'));
    end

    out = struct();
    out.runDirs = runDirs;
    out.labels = labels;
    out.summaries = summaries;
    out.metricTable = metricTable;
end

function row = local_metrics_for_run(label, runDir, S)
    required = {'step','totalMass','fluidYMax','fluidArea','meanPhysicalDensity'};
    for k = 1:numel(required)
        if ~ismember(required{k}, S.Properties.VariableNames)
            error('validate_minimal_piston:missingColumn', ...
                'Run %s is missing required summary column: %s', runDir, required{k});
        end
    end

    t = local_time_axis(S);
    nRows = height(S);
    timeStart = t(1);
    timeEnd = t(end);

    yTopStart = S.fluidYMax(1);
    yTopEnd = S.fluidYMax(end);
    yTopRelChange = (yTopEnd - yTopStart) / local_scale([yTopStart, yTopEnd]);

    areaStart = S.fluidArea(1);
    areaEnd = S.fluidArea(end);
    areaRelChange = (areaEnd - areaStart) / local_scale([areaStart, areaEnd]);

    densityStart = S.meanPhysicalDensity(1);
    densityEnd = S.meanPhysicalDensity(end);
    densityRelChange = local_relative_change(densityStart, densityEnd);

    expectedDensityRelChange = local_relative_change(areaEnd, areaStart);
    densityAreaResidual = densityRelChange - expectedDensityRelChange;

    totalMassStart = S.totalMass(1);
    totalMassEnd = S.totalMass(end);
    totalMassRelDrift = (totalMassEnd - totalMassStart) / local_scale([totalMassStart, totalMassEnd]);

    kBTStart = NaN;
    kBTEnd = NaN;
    kBTMean = NaN;
    kBTRelDrift = NaN;
    if ismember('kBTEstimate', S.Properties.VariableNames)
        k = S.kBTEstimate;
        kBTStart = k(1);
        kBTEnd = k(end);
        kBTMean = mean(k, 'omitnan');
        kBTRelDrift = (kBTEnd - kBTStart) / local_scale(k);
    end

    thermostatKBTAfterMean = NaN;
    if ismember('thermostatKBTAfter', S.Properties.VariableNames)
        vals = S.thermostatKBTAfter;
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            thermostatKBTAfterMean = mean(vals, 'omitnan');
        end
    end

    numberDensityStart = S.Np(1) / areaStart;
    numberDensityEnd = S.Np(end) / areaEnd;
    pkinProxyStart = numberDensityStart * kBTStart;
    pkinProxyEnd = numberDensityEnd * kBTEnd;
    pkinProxyRelChange = local_relative_change(pkinProxyStart, pkinProxyEnd);

    hitsTopTotal = NaN;
    hitsBottomTotal = NaN;
    if ismember('hitsTop', S.Properties.VariableNames)
        hitsTopTotal = sum(S.hitsTop, 'omitnan');
    end
    if ismember('hitsBottom', S.Properties.VariableNames)
        hitsBottomTotal = sum(S.hitsBottom, 'omitnan');
    end

    row = table(string(label), string(runDir), nRows, timeStart, timeEnd, ...
        yTopStart, yTopEnd, yTopRelChange, ...
        areaStart, areaEnd, areaRelChange, ...
        densityStart, densityEnd, densityRelChange, expectedDensityRelChange, densityAreaResidual, ...
        totalMassStart, totalMassEnd, totalMassRelDrift, ...
        kBTStart, kBTEnd, kBTMean, kBTRelDrift, thermostatKBTAfterMean, ...
        numberDensityStart, numberDensityEnd, pkinProxyStart, pkinProxyEnd, pkinProxyRelChange, ...
        hitsBottomTotal, hitsTopTotal, ...
        'VariableNames', {'label','runDir','nRows','timeStart','timeEnd', ...
        'yTopStart','yTopEnd','yTopRelChange', ...
        'areaStart','areaEnd','areaRelChange', ...
        'densityStart','densityEnd','densityRelChange','expectedDensityRelChange','densityAreaResidual', ...
        'totalMassStart','totalMassEnd','totalMassRelDrift', ...
        'kBTStart','kBTEnd','kBTMean','kBTRelDrift','thermostatKBTAfterMean', ...
        'numberDensityStart','numberDensityEnd','pkinProxyStart','pkinProxyEnd','pkinProxyRelChange', ...
        'hitsBottomTotal','hitsTopTotal'});
end

function local_plot_piston(summaries, labels)
    figure('Name', 'Minimal piston validation');
    tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        plot(local_time_axis(S), S.fluidYMax, '-', 'DisplayName', labels{k});
    end
    hold off;
    xlabel('time'); ylabel('yTop'); title('Moving top boundary'); grid on;
    legend('Interpreter', 'none', 'Location', 'best');

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        plot(local_time_axis(S), S.fluidArea ./ S.fluidArea(1), '-', 'DisplayName', labels{k});
    end
    hold off;
    xlabel('time'); ylabel('A/A_0'); title('Active area ratio'); grid on;

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        plot(local_time_axis(S), S.meanPhysicalDensity ./ S.meanPhysicalDensity(1), '-', 'DisplayName', labels{k});
    end
    hold off;
    xlabel('time'); ylabel('\rho/\rho_0'); title('Mean density ratio'); grid on;

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        plot(local_time_axis(S), S.totalMass ./ S.totalMass(1), '-', 'DisplayName', labels{k});
    end
    hold off;
    xlabel('time'); ylabel('M/M_0'); title('Mass conservation'); grid on;

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        if ismember('kBTEstimate', S.Properties.VariableNames)
            plot(local_time_axis(S), S.kBTEstimate, '-', 'DisplayName', labels{k});
        end
    end
    hold off;
    xlabel('time'); ylabel('kBT'); title('Thermal response'); grid on;

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        t = local_time_axis(S);
        if ismember('kBTEstimate', S.Properties.VariableNames) && ismember('Np', S.Properties.VariableNames)
            numberDensity = S.Np ./ S.fluidArea;
            pkinProxy = numberDensity .* S.kBTEstimate;
            plot(t, pkinProxy ./ pkinProxy(1), '-', 'DisplayName', labels{k});
        end
    end
    hold off;
    xlabel('time'); ylabel('P_{kin,proxy}/P_0'); title('Ideal kinetic pressure proxy'); grid on;
end

function x = local_time_axis(S)
    if ismember('time', S.Properties.VariableNames)
        x = S.time;
    elseif ismember('t', S.Properties.VariableNames)
        x = S.t;
    else
        x = S.step;
    end
end

function out = local_cellstr(x)
    if isempty(x)
        out = {};
    elseif ischar(x) || isstring(x)
        out = cellstr(x);
    elseif iscell(x)
        out = cellfun(@char, x, 'UniformOutput', false);
    else
        error('validate_minimal_piston:badInput', 'Expected char, string or cell array of strings.');
    end
end

function rel = local_relative_change(startValue, endValue)
    if isfinite(startValue) && isfinite(endValue) && abs(startValue) > 0
        rel = endValue / startValue - 1.0;
    else
        rel = NaN;
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

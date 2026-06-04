function out = validate_active_fluid_domain_refactor(runDirs, varargin)
%VALIDATE_ACTIVE_FLUID_DOMAIN_REFACTOR Check active-fluid-domain runtime diagnostics.
%
% out = validate_active_fluid_domain_refactor({ ...
%     'runs/periodic_base', ...
%     'runs/active_domain_y_top_static', ...
%     'runs/active_domain_y_top_slow_motion'}, ...
%     'labels', {'full box','static yTop=0.95','moving yTop'}, ...
%     'makePlots', true);
%
% This helper is intentionally based on summary_runtime.csv. It checks the
% geometric quantities that are difficult to reconstruct from particle dumps
% alone once the active domain is time dependent: fluid bounds, fluid area and
% mean physical density. Detailed fields remain regular dump post-processing.

    if nargin < 1 || isempty(runDirs)
        runDirs = { ...
            'runs/periodic_base', ...
            'runs/active_domain_y_top_static', ...
            'runs/active_domain_y_top_slow_motion'};
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
        error('validate_active_fluid_domain_refactor:labelMismatch', ...
            'labels must have the same length as runDirs.');
    end

    n = numel(runDirs);
    summaries = cell(n, 1);
    metricRows = cell(n, 1);
    for k = 1:n
        summaryFile = fullfile(runDirs{k}, 'summary_runtime.csv');
        if ~isfile(summaryFile)
            error('validate_active_fluid_domain_refactor:missingSummary', ...
                'Cannot find summary file: %s', summaryFile);
        end
        S = readtable(summaryFile);
        summaries{k} = S;
        metricRows{k} = local_metrics_for_run(labels{k}, runDirs{k}, S);
    end

    metricTable = vertcat(metricRows{:});
    disp(metricTable);

    if p.Results.makePlots
        local_plot_active_domain(summaries, labels);
    end

    if p.Results.saveTables
        outputDir = char(p.Results.outputDir);
        if isempty(outputDir)
            outputDir = pwd;
        end
        if ~isfolder(outputDir)
            mkdir(outputDir);
        end
        writetable(metricTable, fullfile(outputDir, 'active_fluid_domain_refactor_metrics.csv'));
    end

    out = struct();
    out.runDirs = runDirs;
    out.labels = labels;
    out.summaries = summaries;
    out.metricTable = metricTable;
end

function row = local_metrics_for_run(label, runDir, S)
    required = {'step','totalMass','fluidXMin','fluidXMax','fluidYMin','fluidYMax','fluidArea','meanPhysicalDensity'};
    for k = 1:numel(required)
        if ~ismember(required{k}, S.Properties.VariableNames)
            error('validate_active_fluid_domain_refactor:missingColumn', ...
                'Run %s is missing required summary column: %s', runDir, required{k});
        end
    end

    x = local_time_axis(S);
    nRows = height(S);
    timeStart = x(1);
    timeEnd = x(end);

    fluidXMinStart = S.fluidXMin(1);
    fluidXMinEnd = S.fluidXMin(end);
    fluidXMaxStart = S.fluidXMax(1);
    fluidXMaxEnd = S.fluidXMax(end);
    fluidYMinStart = S.fluidYMin(1);
    fluidYMinEnd = S.fluidYMin(end);
    fluidYMaxStart = S.fluidYMax(1);
    fluidYMaxEnd = S.fluidYMax(end);
    fluidAreaStart = S.fluidArea(1);
    fluidAreaEnd = S.fluidArea(end);
    fluidAreaRelChange = (fluidAreaEnd - fluidAreaStart) / local_scale([fluidAreaStart, fluidAreaEnd]);
    densityStart = S.meanPhysicalDensity(1);
    densityEnd = S.meanPhysicalDensity(end);
    densityRelChange = (densityEnd - densityStart) / local_scale([densityStart, densityEnd]);

    totalMassStart = S.totalMass(1);
    totalMassEnd = S.totalMass(end);
    totalMassRelDrift = (totalMassEnd - totalMassStart) / local_scale([totalMassStart, totalMassEnd]);

    kBTMean = NaN;
    kBTRelDrift = NaN;
    if ismember('kBT', S.Properties.VariableNames)
        kBTMean = mean(S.kBT, 'omitnan');
        kBTRelDrift = (S.kBT(end) - S.kBT(1)) / local_scale(S.kBT);
    elseif ismember('kBTEstimate', S.Properties.VariableNames)
        kBTMean = mean(S.kBTEstimate, 'omitnan');
        kBTRelDrift = (S.kBTEstimate(end) - S.kBTEstimate(1)) / local_scale(S.kBTEstimate);
    end

    thermostatKBTAfterMean = NaN;
    if ismember('thermostatKBTAfter', S.Properties.VariableNames)
        vals = S.thermostatKBTAfter;
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            thermostatKBTAfterMean = mean(vals, 'omitnan');
        end
    end

    row = table(string(label), string(runDir), nRows, timeStart, timeEnd, ...
        fluidXMinStart, fluidXMinEnd, fluidXMaxStart, fluidXMaxEnd, ...
        fluidYMinStart, fluidYMinEnd, fluidYMaxStart, fluidYMaxEnd, ...
        fluidAreaStart, fluidAreaEnd, fluidAreaRelChange, ...
        densityStart, densityEnd, densityRelChange, ...
        totalMassStart, totalMassEnd, totalMassRelDrift, ...
        kBTMean, kBTRelDrift, thermostatKBTAfterMean, ...
        'VariableNames', {'label','runDir','nRows','timeStart','timeEnd', ...
        'fluidXMinStart','fluidXMinEnd','fluidXMaxStart','fluidXMaxEnd', ...
        'fluidYMinStart','fluidYMinEnd','fluidYMaxStart','fluidYMaxEnd', ...
        'fluidAreaStart','fluidAreaEnd','fluidAreaRelChange', ...
        'densityStart','densityEnd','densityRelChange', ...
        'totalMassStart','totalMassEnd','totalMassRelDrift', ...
        'kBTMean','kBTRelDrift','thermostatKBTAfterMean'});
end

function local_plot_active_domain(summaries, labels)
    figure('Name', 'Active fluid-domain refactor validation');
    tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        x = local_time_axis(S);
        if ismember('fluidYMax', S.Properties.VariableNames)
            plot(x, S.fluidYMax, '-', 'DisplayName', labels{k});
        end
    end
    hold off;
    xlabel('time'); ylabel('fluidYMax'); title('Active top bound'); grid on;
    legend('Interpreter', 'none', 'Location', 'best');

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        x = local_time_axis(S);
        plot(x, S.fluidArea, '-', 'DisplayName', labels{k});
    end
    hold off;
    xlabel('time'); ylabel('fluid area'); title('Active fluid area'); grid on;
    legend('Interpreter', 'none', 'Location', 'best');

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        x = local_time_axis(S);
        plot(x, S.meanPhysicalDensity, '-', 'DisplayName', labels{k});
    end
    hold off;
    xlabel('time'); ylabel('mean physical density'); title('Mass / active area'); grid on;
    legend('Interpreter', 'none', 'Location', 'best');

    nexttile;
    hold on;
    for k = 1:numel(summaries)
        S = summaries{k};
        x = local_time_axis(S);
        if ismember('kBT', S.Properties.VariableNames)
            plot(x, S.kBT, '-', 'DisplayName', labels{k});
        elseif ismember('kBTEstimate', S.Properties.VariableNames)
            plot(x, S.kBTEstimate, '-', 'DisplayName', labels{k});
        end
    end
    hold off;
    xlabel('time'); ylabel('kBT'); title('Thermal control'); grid on;
    legend('Interpreter', 'none', 'Location', 'best');
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
        error('validate_active_fluid_domain_refactor:badInput', 'Expected char, string or cell array of strings.');
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

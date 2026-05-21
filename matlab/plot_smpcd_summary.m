function summary = plot_smpcd_summary(runDir, varargin)
%PLOT_SMPCD_SUMMARY Plot runtime control diagnostics from summary_runtime.csv.
%
% summary = plot_smpcd_summary(runDir)

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'summaryFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'makePlots', true, @islogical);
    parse(p, runDir, varargin{:});

    runDir = char(p.Results.runDir);
    summaryFile = char(p.Results.summaryFile);
    if isempty(summaryFile)
        summaryFile = fullfile(runDir, 'summary_runtime.csv');
    end
    if ~isfile(summaryFile)
        error('plot_smpcd_summary:fileNotFound', 'Cannot find summary file: %s', summaryFile);
    end

    summary = readtable(summaryFile);
    if ~p.Results.makePlots
        return;
    end

    x = summary.step;
    if ismember('time', summary.Properties.VariableNames)
        x = summary.time;
        xLabel = 'time';
    elseif ismember('t', summary.Properties.VariableNames)
        x = summary.t;
        xLabel = 't';
    else
        xLabel = 'step';
    end

    figure('Name', 'SRC/MPCD runtime diagnostics');
    tiledlayout(5, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    local_plot_if_present(summary, x, {'kBT','kBTEstimate','meanKBT'}, 'kBT');
    xlabel(xLabel); grid on;

    nexttile;
    if all(ismember({'Px','Py'}, summary.Properties.VariableNames))
        plot(x, summary.Px, '-', x, summary.Py, '-');
        legend('Px','Py', 'Location', 'best');
    else
        text(0.5, 0.5, 'Px/Py unavailable', 'HorizontalAlignment', 'center');
    end
    title('total momentum'); xlabel(xLabel); grid on;

    nexttile;
    local_plot_if_present(summary, x, {'totalMass','mass'}, 'total mass');
    xlabel(xLabel); grid on;

    nexttile;
    if ismember('stdN', summary.Properties.VariableNames)
        plot(x, summary.stdN, '-');
        title('std(N)'); xlabel(xLabel); grid on;
    else
        text(0.5, 0.5, 'stdN unavailable', 'HorizontalAlignment', 'center');
    end

    nexttile;
    names = summary.Properties.VariableNames;
    hitNames = intersect({'hitsLeft','hitsRight','hitsBottom','hitsTop'}, names, 'stable');
    if ~isempty(hitNames)
        hold on;
        for k = 1:numel(hitNames)
            plot(x, summary.(hitNames{k}), '-');
        end
        hold off;
        legend(hitNames, 'Interpreter', 'none', 'Location', 'best');
        title('wall hits'); xlabel(xLabel); grid on;
    else
        text(0.5, 0.5, 'wall-hit diagnostics unavailable', 'HorizontalAlignment', 'center');
    end

    nexttile;
    if ismember('virtualParticleCount', summary.Properties.VariableNames)
        plot(x, summary.virtualParticleCount, '-');
        title('virtual particles'); xlabel(xLabel); grid on;
    else
        text(0.5, 0.5, 'virtual-particle diagnostics unavailable', 'HorizontalAlignment', 'center');
    end

    nexttile;
    if ismember('virtualMass', summary.Properties.VariableNames)
        plot(x, summary.virtualMass, '-');
        title('virtual mass'); xlabel(xLabel); grid on;
    else
        text(0.5, 0.5, 'virtual mass unavailable', 'HorizontalAlignment', 'center');
    end

    nexttile;
    if ismember('wallTime', summary.Properties.VariableNames)
        plot(x, summary.wallTime, '-');
        title('wall time'); xlabel(xLabel); ylabel('s'); grid on;
    elseif ismember('wallSeconds', summary.Properties.VariableNames)
        plot(x, summary.wallSeconds, '-');
        title('wall time'); xlabel(xLabel); ylabel('s'); grid on;
    elseif ismember('wall', summary.Properties.VariableNames)
        plot(x, summary.wall, '-');
        title('wall time'); xlabel(xLabel); ylabel('s'); grid on;
    else
        text(0.5, 0.5, 'wall time unavailable', 'HorizontalAlignment', 'center');
    end

    nexttile;
    names = summary.Properties.VariableNames;
    if all(ismember({'minN','maxN'}, names))
        plot(x, summary.minN, '-', x, summary.maxN, '-');
        legend('minN','maxN', 'Location', 'best');
        title('occupation extrema'); xlabel(xLabel); grid on;
    else
        text(0.5, 0.5, 'occupation extrema unavailable', 'HorizontalAlignment', 'center');
    end

    nexttile;
    names = summary.Properties.VariableNames;
    thermoNames = intersect({'thermostatKBTBefore','thermostatKBTAfter'}, names, 'stable');
    if ~isempty(thermoNames)
        hold on;
        for k = 1:numel(thermoNames)
            plot(x, summary.(thermoNames{k}), '-');
        end
        hold off;
        legend(thermoNames, 'Interpreter', 'none', 'Location', 'best');
        title('thermostat kBT'); xlabel(xLabel); grid on;
    else
        text(0.5, 0.5, 'thermostat kBT unavailable', 'HorizontalAlignment', 'center');
    end

    nexttile;
    scaleNames = intersect({'thermostatScaleMean','thermostatScaleMin','thermostatScaleMax'}, names, 'stable');
    if ~isempty(scaleNames)
        hold on;
        for k = 1:numel(scaleNames)
            plot(x, summary.(scaleNames{k}), '-');
        end
        hold off;
        legend(scaleNames, 'Interpreter', 'none', 'Location', 'best');
        title('thermostat scale'); xlabel(xLabel); grid on;
    else
        text(0.5, 0.5, 'thermostat scale unavailable', 'HorizontalAlignment', 'center');
    end

end

function local_plot_if_present(T, x, candidates, titleText)
    for k = 1:numel(candidates)
        name = candidates{k};
        if ismember(name, T.Properties.VariableNames)
            plot(x, T.(name), '-');
            title(titleText);
            grid on;
            return;
        end
    end
    text(0.5, 0.5, sprintf('%s unavailable', titleText), 'HorizontalAlignment', 'center');
    title(titleText);
end

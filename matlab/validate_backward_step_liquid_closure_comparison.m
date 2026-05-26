function suite = validate_backward_step_liquid_closure_comparison(varargin)
%VALIDATE_BACKWARD_STEP_LIQUID_CLOSURE_COMPARISON Compare Q6/Q9 and Q6/Q9/virial on the immersed step.
%
% Example from repository root:
%   ./scripts/run_backward_step_liquid_closure_comparison.sh
%   cd matlab
%   suite = validate_backward_step_liquid_closure_comparison();

p = inputParser;
addParameter(p, 'runDirs', { ...
    '../runs/backward_step_liquid_q9_selected_96x48', ...
    '../runs/backward_step_liquid_q9_virial_selected_96x48'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'labels', {'Q9 selected', 'Q9 selected + virial'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'outputDir', '../runs/backward_step_liquid_closure_comparison_analysis', @(s) ischar(s) || isstring(s));
parse(p, varargin{:});
opts = p.Results;

suite = validate_backward_step_masked_structure_suite( ...
    'runDirs', cellstr(string(opts.runDirs)), ...
    'labels', cellstr(string(opts.labels)), ...
    'makePlots', logical(opts.makePlots), ...
    'outputDir', char(opts.outputDir));

writetable(suite.summary, fullfile(char(opts.outputDir), 'backward_step_liquid_closure_comparison_summary.csv'));

if opts.makePlots
    local_plot_virial_comparison(suite, char(opts.outputDir));
end
end

function local_plot_virial_comparison(suite, outputDir)
tbl = suite.summary;
fig = figure('Name', 'Backward step liquid closure: Q9 vs Q9/virial');
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

local_bar_metric(tbl, 'populationP05ReversedOverReference', 'P05(N) reversed / ref', 'Population low-tail');
local_bar_metric(tbl, 'populationTemporalCvMeanReversed', 'temporal CV(N) reversed', 'Population intermittency');
local_bar_metric(tbl, 'omegaMeanLowKFractionDownstream', 'mean omega low-k fraction', 'Large-scale vorticity');
local_bar_metric(tbl, 'reversedLargestComponentFraction', 'largest reversed component fraction', 'Recirculation compactness');
local_bar_metric(tbl, 'virialDuOverThermalRmsLate', 'virial du RMS / u_{th}', 'Virial kick size');
local_bar_metric(tbl, 'virialRhoDefectRelRmsLate', 'rho defect rel RMS', 'Virial density defect');

saveas(fig, fullfile(outputDir, 'backward_step_liquid_closure_comparison_metrics.png'));
end

function local_bar_metric(tbl, metricName, ylab, ttl)
nexttile;
if ismember(metricName, tbl.Properties.VariableNames)
    bar(tbl.(metricName));
    set(gca, 'XTick', 1:height(tbl), 'XTickLabel', cellstr(tbl.caseLabel));
    xtickangle(20);
end
ylabel(ylab); title(ttl); grid on;
end

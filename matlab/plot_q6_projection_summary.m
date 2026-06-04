function T = plot_q6_projection_summary(runDir, varargin)
%PLOT_Q6_PROJECTION_SUMMARY Plot runtime diagnostics for the Q6 periodic adapter.
%
%   T = plot_q6_projection_summary(runDir)
%
%   Required input:
%     runDir : run directory containing summary_runtime.csv
%
%   Optional name/value pairs:
%     'makePlots' : true/false, default true

p = inputParser;
p.FunctionName = 'plot_q6_projection_summary';
addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, runDir, varargin{:});
opts = p.Results;

summaryFile = fullfile(char(opts.runDir), 'summary_runtime.csv');
if ~isfile(summaryFile)
    error('plot_q6_projection_summary:missingFile', ...
        'Cannot find summary_runtime.csv in %s', char(opts.runDir));
end

T = readtable(summaryFile);
required = {'step','time','q6Applied','q6Converged','q6ResidualRel', ...
    'q6DivBeforeRms','q6DivAfterProjectedFluxRms','q6DivAfterCellVelocityRms', ...
    'q6CorrectionVelocityRms','q6MomentumResidualBeforeCorrection','kBTEstimate','totalMass'};
for k = 1:numel(required)
    if ~ismember(required{k}, T.Properties.VariableNames)
        error('plot_q6_projection_summary:missingColumn', ...
            'Missing Q6 summary column: %s', required{k});
    end
end

if opts.makePlots
    plotMask = T.q6Applied > 0;
    if ~any(plotMask)
        plotMask = true(height(T), 1);
    end
    Tp = T(plotMask, :);

    figure('Name', 'Q6 projection summary');
    tiledlayout(3, 2, 'TileSpacing', 'compact');

    nexttile;
    semilogy(Tp.time, max(Tp.q6ResidualRel, realmin)); grid on;
    xlabel('time'); ylabel('residual rel.'); title('CG residual');

    nexttile;
    semilogy(Tp.time, max(Tp.q6DivBeforeRms, realmin), '-', ...
             Tp.time, max(Tp.q6DivAfterProjectedFluxRms, realmin), '-', ...
             Tp.time, max(Tp.q6DivAfterCellVelocityRms, realmin), '-');
    grid on; xlabel('time'); ylabel('RMS divergence');
    legend('before', 'projected faces', 'cell velocity', 'Location', 'best');
    title('Q6 divergence');

    nexttile;
    plot(Tp.time, Tp.q6CorrectionVelocityRms); grid on;
    xlabel('time'); ylabel('RMS'); title('velocity correction');

    nexttile;
    semilogy(Tp.time, max(Tp.q6MomentumResidualBeforeCorrection, realmin)); grid on;
    xlabel('time'); ylabel('|dP| before correction'); title('momentum correction residual');

    nexttile;
    plot(T.time, T.kBTEstimate); grid on;
    xlabel('time'); ylabel('kBT estimate'); title('thermal state');

    nexttile;
    plot(T.time, T.totalMass); grid on;
    xlabel('time'); ylabel('total mass'); title('mass conservation');
end

last = T(end, :);
fprintf('\n=== Q6 projection summary ===\n');
fprintf('runDir                         : %s\n', char(opts.runDir));
fprintf('last step                      : %d\n', last.step);
fprintf('q6 applied/converged           : %d / %d\n', last.q6Applied, last.q6Converged);
fprintf('q6 iterations/residualRel      : %d / %.6g\n', last.q6Iterations, last.q6ResidualRel);
fprintf('div before RMS                 : %.6g\n', last.q6DivBeforeRms);
fprintf('div after projected flux RMS   : %.6g\n', last.q6DivAfterProjectedFluxRms);
fprintf('div after cell velocity RMS    : %.6g\n', last.q6DivAfterCellVelocityRms);
fprintf('correction velocity RMS        : %.6g\n', last.q6CorrectionVelocityRms);
fprintf('momentum residual before corr. : %.6g\n', last.q6MomentumResidualBeforeCorrection);
fprintf('total mass                     : %.17g\n', last.totalMass);
fprintf('kBT estimate                   : %.6g\n', last.kBTEstimate);
fprintf('==============================\n\n');
end

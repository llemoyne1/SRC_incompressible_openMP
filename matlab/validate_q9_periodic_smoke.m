function out = validate_q9_periodic_smoke(varargin)
%VALIDATE_Q9_PERIODIC_SMOKE Compare Q6 and Q9 periodic smoke-test summaries.
%
% Run from the matlab/ directory after the C++ runs:
%   addpath('.')
%   out = validate_q9_periodic_smoke('makePlots', true);

p = inputParser;
p.FunctionName = 'validate_q9_periodic_smoke';
addParameter(p, 'q6RunDir', '../runs/periodic_q6_for_q9_smoke', @(s) ischar(s) || isstring(s));
addParameter(p, 'q9RunDir', '../runs/periodic_q9_smoke', @(s) ischar(s) || isstring(s));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

q6 = local_read_summary(opts.q6RunDir);
q9 = local_read_summary(opts.q9RunDir);

out = table();
out.run = ["q6"; "q9"];
out.nRows = [height(q6); height(q9)];
out.timeEnd = [q6.time(end); q9.time(end)];
out.stdNEnd = [q6.stdN(end); q9.stdN(end)];
out.kBTEnd = [q6.kBTEstimate(end); q9.kBTEstimate(end)];
out.q6RuntimeDivAfterEnd = [q6.q6DivAfterProjectedFluxRms(end); q9.q6DivAfterProjectedFluxRms(end)];
out.q9AppliedEnd = [0; q9.q9Applied(end)];
out.q9ResidualEnd = [NaN; q9.q9ResidualRel(end)];
out.q9MassFluxDivBeforeEnd = [NaN; q9.q9MassFluxDivBeforeRms(end)];
out.q9MassFluxDivAfterEnd = [NaN; q9.q9MassFluxDivAfterRms(end)];
out.q9TargetDivergenceEnd = [NaN; q9.q9TargetDivergenceRms(end)];
if ismember('q9TargetDivergenceRawRms', q9.Properties.VariableNames)
    out.q9TargetDivergenceRawEnd = [NaN; q9.q9TargetDivergenceRawRms(end)];
end
if ismember('q9TargetDivergenceFilterRatio', q9.Properties.VariableNames)
    out.q9TargetFilterRatioEnd = [NaN; q9.q9TargetDivergenceFilterRatio(end)];
end
out.q9DensityStdBeforeEnd = [NaN; q9.q9DensityStdBefore(end)];
out.q9DensityStdAfterEstimateEnd = [NaN; q9.q9DensityStdAfterEstimate(end)];
out.q9DensityStdRatioEstimateEnd = [NaN; q9.q9DensityStdRatioEstimate(end)];
out.q9CorrectionVelocityRmsEnd = [NaN; q9.q9CorrectionVelocityRms(end)];

disp('=== Periodic Q9 mass-flux projection smoke validation ===')
disp(out)

if opts.makePlots
    local_make_plots(q6, q9);
end
end

function T = local_read_summary(runDir)
summaryFile = fullfile(char(runDir), 'summary_runtime.csv');
if ~isfile(summaryFile)
    error('validate_q9_periodic_smoke:missingSummary', 'Missing summary file: %s', summaryFile);
end
T = readtable(summaryFile);
end

function local_make_plots(q6, q9)
figure('Name','Q9 periodic smoke summary');
tiledlayout(3,2, 'TileSpacing','compact', 'Padding','compact');

nexttile;
plot(q6.time, q6.stdN, '-'); hold on;
plot(q9.time, q9.stdN, '-'); hold off;
grid on; xlabel('t'); ylabel('std(N)'); legend('q6','q9', 'Location','best');
title('Occupancy fluctuations');

nexttile;
semilogy(q6.time(q6.q6Applied > 0), q6.q6DivAfterProjectedFluxRms(q6.q6Applied > 0), '-'); hold on;
semilogy(q9.time(q9.q6Applied > 0), q9.q6DivAfterProjectedFluxRms(q9.q6Applied > 0), '-'); hold off;
grid on; xlabel('t'); ylabel('Q6 div after'); legend('q6','q9', 'Location','best');
title('Velocity projection residual');

nexttile;
mask = q9.q9Applied > 0;
plot(q9.time(mask), q9.q9DensityStdBefore(mask), '-'); hold on;
plot(q9.time(mask), q9.q9DensityStdAfterEstimate(mask), '-'); hold off;
grid on; xlabel('t'); ylabel('cell mass std'); legend('before','after estimate', 'Location','best');
title('Q9 density relaxation estimate');

nexttile;
plot(q9.time(mask), q9.q9DensityStdRatioEstimate(mask), '-');
hold on;
if ismember('q9TargetDivergenceFilterRatio', q9.Properties.VariableNames)
    plot(q9.time(mask), q9.q9TargetDivergenceFilterRatio(mask), '--');
    legend('std after / before','target filtered/raw', 'Location','best');
end
hold off;
grid on; xlabel('t'); ylabel('ratio');
title('Q9 filtered target and relaxation estimate');

nexttile;
semilogy(q9.time(mask), q9.q9ResidualRel(mask), '-');
grid on; xlabel('t'); ylabel('Q9 residual rel');
title('Q9 elliptic solve residual');

nexttile;
plot(q6.time, q6.kBTEstimate, '-'); hold on;
plot(q9.time, q9.kBTEstimate, '-'); hold off;
grid on; xlabel('t'); ylabel('kBT estimate'); legend('q6','q9', 'Location','best');
title('Thermal stability');
end

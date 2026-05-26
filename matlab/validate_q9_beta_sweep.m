function out = validate_q9_beta_sweep(varargin)
%VALIDATE_Q9_BETA_SWEEP Analyze the periodic Q9 density-relaxation beta sweep.
%
% Run from the matlab/ directory after the C++ runs:
%   addpath('.')
%   out = validate_q9_beta_sweep('makePlots', true);
%
% The default run directories are deliberately written as ../runs/... because
% this script is meant to be launched from matlab/.

p = inputParser;
p.FunctionName = 'validate_q9_beta_sweep';
addParameter(p, 'q6RunDir', '../runs/periodic_q6_for_q9_beta_sweep', @(s) ischar(s) || isstring(s));
addParameter(p, 'q9Betas', [0.0005 0.0010 0.0020 0.0050 0.0100], @(x) isnumeric(x) && isvector(x));
addParameter(p, 'q9RunDirs', {}, @(x) iscell(x) || isstring(x));
addParameter(p, 'tailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

betas = opts.q9Betas(:)';
q9RunDirs = opts.q9RunDirs;
if isempty(q9RunDirs)
    q9RunDirs = cell(size(betas));
    for k = 1:numel(betas)
        q9RunDirs{k} = ['../runs/periodic_q9_beta_' local_beta_tag(betas(k)) '_filtered_sweep'];
    end
else
    q9RunDirs = cellstr(q9RunDirs);
end
if numel(q9RunDirs) ~= numel(betas)
    error('validate_q9_beta_sweep:badRunDirs', 'q9RunDirs and q9Betas must have the same length.');
end

runs = cell(1, 1 + numel(betas));
runs{1} = struct('name', 'q6', 'beta', NaN, 'dir', char(opts.q6RunDir), 'summary', local_read_summary(opts.q6RunDir));
for k = 1:numel(betas)
    runs{1+k} = struct('name', sprintf('q9_beta_%s', local_beta_tag(betas(k))), ...
                       'beta', betas(k), ...
                       'dir', q9RunDirs{k}, ...
                       'summary', local_read_summary(q9RunDirs{k}));
end

out = local_build_table(runs, opts.tailFraction);

disp('=== Periodic Q9 beta sweep validation ===')
disp(out)

if opts.makePlots
    local_make_plots(runs, opts.tailFraction);
end
end

function T = local_read_summary(runDir)
summaryFile = fullfile(char(runDir), 'summary_runtime.csv');
if ~isfile(summaryFile)
    error('validate_q9_beta_sweep:missingSummary', 'Missing summary file: %s', summaryFile);
end
T = readtable(summaryFile);
end

function out = local_build_table(runs, tailFraction)
n = numel(runs);
run = strings(n,1);
beta = NaN(n,1);
nRows = zeros(n,1);
timeEnd = NaN(n,1);
stdNStart = NaN(n,1);
stdNEnd = NaN(n,1);
stdNTailMean = NaN(n,1);
stdNTailRelToQ6 = NaN(n,1);
kBTEnd = NaN(n,1);
kBTTailMean = NaN(n,1);
q6DivAfterEnd = NaN(n,1);
q9ResidualTailMedian = NaN(n,1);
q9DensityStdRatioTailMean = NaN(n,1);
q9DensityStdRatioEnd = NaN(n,1);
q9DensityStdBeforeEnd = NaN(n,1);
q9DensityStdAfterEstimateEnd = NaN(n,1);
q9CorrectionVelocityRmsTailMean = NaN(n,1);
q9CorrectionVelocityMaxEnd = NaN(n,1);
q9MassFluxDivAfterEnd = NaN(n,1);
q9TargetDivergenceEnd = NaN(n,1);
q9TargetDivergenceRawEnd = NaN(n,1);
q9TargetFilterRatioEnd = NaN(n,1);
q9TargetFilterRatioTailMean = NaN(n,1);

for k = 1:n
    T = runs{k}.summary;
    tail = local_tail_mask(T, tailFraction);
    run(k) = string(runs{k}.name);
    beta(k) = runs{k}.beta;
    nRows(k) = height(T);
    timeEnd(k) = T.time(end);
    stdNStart(k) = T.stdN(1);
    stdNEnd(k) = T.stdN(end);
    stdNTailMean(k) = mean(T.stdN(tail), 'omitnan');
    kBTEnd(k) = T.kBTEstimate(end);
    kBTTailMean(k) = mean(T.kBTEstimate(tail), 'omitnan');
    if ismember('q6DivAfterProjectedFluxRms', T.Properties.VariableNames)
        q6DivAfterEnd(k) = T.q6DivAfterProjectedFluxRms(end);
    end
    if ismember('q9Applied', T.Properties.VariableNames)
        q9Mask = T.q9Applied > 0 & tail;
        if any(q9Mask)
            q9ResidualTailMedian(k) = median(T.q9ResidualRel(q9Mask), 'omitnan');
            q9DensityStdRatioTailMean(k) = mean(T.q9DensityStdRatioEstimate(q9Mask), 'omitnan');
            q9CorrectionVelocityRmsTailMean(k) = mean(T.q9CorrectionVelocityRms(q9Mask), 'omitnan');
            if ismember('q9TargetDivergenceFilterRatio', T.Properties.VariableNames)
                q9TargetFilterRatioTailMean(k) = mean(T.q9TargetDivergenceFilterRatio(q9Mask), 'omitnan');
            end
        end
        if T.q9Applied(end) > 0
            q9DensityStdRatioEnd(k) = T.q9DensityStdRatioEstimate(end);
            q9DensityStdBeforeEnd(k) = T.q9DensityStdBefore(end);
            q9DensityStdAfterEstimateEnd(k) = T.q9DensityStdAfterEstimate(end);
            q9CorrectionVelocityMaxEnd(k) = T.q9CorrectionVelocityMaxAbs(end);
            q9MassFluxDivAfterEnd(k) = T.q9MassFluxDivAfterRms(end);
            q9TargetDivergenceEnd(k) = T.q9TargetDivergenceRms(end);
            if ismember('q9TargetDivergenceRawRms', T.Properties.VariableNames)
                q9TargetDivergenceRawEnd(k) = T.q9TargetDivergenceRawRms(end);
            end
            if ismember('q9TargetDivergenceFilterRatio', T.Properties.VariableNames)
                q9TargetFilterRatioEnd(k) = T.q9TargetDivergenceFilterRatio(end);
            end
        end
    end
end

q6Tail = stdNTailMean(1);
if isfinite(q6Tail) && q6Tail > 0
    stdNTailRelToQ6 = stdNTailMean ./ q6Tail;
end

out = table(run, beta, nRows, timeEnd, stdNStart, stdNEnd, stdNTailMean, ...
    stdNTailRelToQ6, kBTEnd, kBTTailMean, q6DivAfterEnd, ...
    q9ResidualTailMedian, q9DensityStdRatioTailMean, q9DensityStdRatioEnd, ...
    q9DensityStdBeforeEnd, q9DensityStdAfterEstimateEnd, ...
    q9CorrectionVelocityRmsTailMean, q9CorrectionVelocityMaxEnd, ...
    q9MassFluxDivAfterEnd, q9TargetDivergenceEnd, q9TargetDivergenceRawEnd, ...
    q9TargetFilterRatioEnd, q9TargetFilterRatioTailMean);
end

function mask = local_tail_mask(T, tailFraction)
n = height(T);
first = max(1, floor((1 - tailFraction) * n) + 1);
mask = false(n,1);
mask(first:end) = true;
end

function local_make_plots(runs, tailFraction)
figure('Name','Q9 beta sweep summary');
tiledlayout(3,2, 'TileSpacing','compact', 'Padding','compact');

nexttile;
hold on;
for k = 1:numel(runs)
    T = runs{k}.summary;
    plot(T.time, T.stdN, '-', 'DisplayName', runs{k}.name);
end
hold off; grid on; xlabel('t'); ylabel('std(N)'); legend('Location','best');
title('Occupancy fluctuations');

nexttile;
hold on;
for k = 1:numel(runs)
    T = runs{k}.summary;
    if ismember('q6Applied', T.Properties.VariableNames)
        mask = T.q6Applied > 0;
        semilogy(T.time(mask), T.q6DivAfterProjectedFluxRms(mask), '-', 'DisplayName', runs{k}.name);
    end
end
hold off; grid on; xlabel('t'); ylabel('Q6 div after'); legend('Location','best');
title('Velocity projection residual');

nexttile;
hold on;
for k = 2:numel(runs)
    T = runs{k}.summary;
    if ismember('q9Applied', T.Properties.VariableNames)
        mask = T.q9Applied > 0;
    else
        mask = false(height(T), 1);
    end
    if any(mask)
        plot(T.time(mask), T.q9DensityStdRatioEstimate(mask), '-', 'DisplayName', runs{k}.name);
    end
end
hold off; grid on; xlabel('t'); ylabel('std after / before'); legend('Location','best');
title('Q9 per-step estimated relaxation');

nexttile;
hold on;
for k = 2:numel(runs)
    T = runs{k}.summary;
    if ismember('q9Applied', T.Properties.VariableNames)
        mask = T.q9Applied > 0;
    else
        mask = false(height(T), 1);
    end
    if any(mask)
        plot(T.time(mask), T.q9CorrectionVelocityRms(mask), '-', 'DisplayName', runs{k}.name);
    end
end
hold off; grid on; xlabel('t'); ylabel('RMS velocity kick'); legend('Location','best');
title('Q9 correction magnitude');

nexttile;
hold on;
for k = 2:numel(runs)
    T = runs{k}.summary;
    if ismember('q9Applied', T.Properties.VariableNames)
        mask = T.q9Applied > 0;
    else
        mask = false(height(T), 1);
    end
    if any(mask)
        semilogy(T.time(mask), T.q9ResidualRel(mask), '-', 'DisplayName', runs{k}.name);
    end
end
hold off; grid on; xlabel('t'); ylabel('Q9 residual rel'); legend('Location','best');
title('Q9 elliptic residual');

nexttile;
hold on;
for k = 1:numel(runs)
    T = runs{k}.summary;
    plot(T.time, T.kBTEstimate, '-', 'DisplayName', runs{k}.name);
end
hold off; grid on; xlabel('t'); ylabel('kBT estimate'); legend('Location','best');
title('Thermal stability');

% Mark the tail window used by the table in the first axis through a console note.
fprintf('Tail statistics use the last %.0f%% of each summary.\n', 100 * tailFraction);
end

function tag = local_beta_tag(beta)
if beta < 0 || ~isfinite(beta)
    error('validate_q9_beta_sweep:badBeta', 'Beta must be non-negative and finite.');
end
s = sprintf('%.4f', beta);
s = regexprep(s, '0+$', '');
s = regexprep(s, '\.$', '');
s = strrep(s, '.', 'p');
if strcmp(s, '0')
    tag = '0p0000';
else
    parts = split(string(s), 'p');
    if numel(parts) == 1
        tag = char(parts(1) + "p0000");
    else
        frac = char(parts(2));
        while numel(frac) < 4
            frac = [frac '0']; %#ok<AGROW>
        end
        tag = [char(parts(1)) 'p' frac(1:4)];
    end
end
end

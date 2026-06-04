function out = validate_taylor_green_q9_filtered_short(varargin)
%VALIDATE_TAYLOR_GREEN_Q9_FILTERED_SHORT Compare classic, Q6 and filtered Q9 TG runs.
%
%   out = validate_taylor_green_q9_filtered_short()
%
%   Defaults assume this function is called from the matlab/ directory and
%   therefore use ../runs/... paths.

p = inputParser;
p.FunctionName = 'validate_taylor_green_q9_filtered_short';
addParameter(p, 'classicRunDir', '../runs/taylor_green_high_snr_classic_64x64_g80_short', @(s) ischar(s) || isstring(s));
addParameter(p, 'q6RunDir', '../runs/taylor_green_high_snr_q6_64x64_g80_short', @(s) ischar(s) || isstring(s));
addParameter(p, 'q9RunDir', '../runs/taylor_green_high_snr_q9_filtered_64x64_g80_short', @(s) ischar(s) || isstring(s));
addParameter(p, 'kxMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kyMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'tailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'plotFinalFields', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

classic = local_analyze_run(char(string(opts.classicRunDir)), opts.kxMode, opts.kyMode, opts.tailFraction);
q6      = local_analyze_run(char(string(opts.q6RunDir)),      opts.kxMode, opts.kyMode, opts.tailFraction);
q9      = local_analyze_run(char(string(opts.q9RunDir)),      opts.kxMode, opts.kyMode, opts.tailFraction);

summary = local_make_summary(classic, q6, q9);

out = struct();
out.classic = classic;
out.q6 = q6;
out.q9 = q9;
out.summary = summary;

fprintf('\n=== Taylor-Green filtered Q9 validation ===\n');
disp(summary);
fprintf('Classic run : %s\n', classic.runDir);
fprintf('Q6 run      : %s\n', q6.runDir);
fprintf('Q9 run      : %s\n', q9.runDir);
fprintf('Tail statistics use the last %.0f%% of runtime rows.\n', 100*opts.tailFraction);
fprintf('==========================================\n\n');

if opts.makePlots
    local_plot_comparison(classic, q6, q9);
end
if opts.plotFinalFields
    local_plot_final_fields(classic, q6, q9);
end
end

function run = local_analyze_run(runDir, kxMode, kyMode, tailFraction)
paramsFile = fullfile(runDir, 'params_used.kv');
if ~isfile(paramsFile)
    error('validate_taylor_green_q9_filtered_short:missingParams', ...
        'Cannot find params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsFile);

for name = {'Lx','Ly','Nx','Ny'}
    if ~isfield(params, name{1})
        error('validate_taylor_green_q9_filtered_short:missingParam', ...
            'Missing %s in %s', name{1}, paramsFile);
    end
end

Lx = double(params.Lx);
Ly = double(params.Ly);
Nx = double(params.Nx);
Ny = double(params.Ny);

frames = list_smpcd_dumps(runDir);
if height(frames) == 0
    error('validate_taylor_green_q9_filtered_short:noFrames', ...
        'No state_step_*.smpcd dumps found in %s', runDir);
end

summaryFile = fullfile(runDir, 'summary_runtime.csv');
if isfile(summaryFile)
    runtime = readtable(summaryFile);
else
    runtime = table();
end

n = height(frames);
time = frames.time;
step = frames.step;
amplitude = nan(n,1);
correlation = nan(n,1);
gridKinetic = nan(n,1);
divRms = nan(n,1);
divMaxAbs = nan(n,1);
omegaRms = nan(n,1);
kBTEstimate = nan(n,1);
stdNRuntime = nan(n,1);
q6ResidualRel = nan(n,1);
q6DivAfterRms = nan(n,1);
q9ResidualRel = nan(n,1);
q9CorrectionVelocityRms = nan(n,1);
q9CorrectionVelocityMaxAbs = nan(n,1);
q9TargetFilterRatio = nan(n,1);

lastFields = [];
for i = 1:n
    state = read_smpcd_state(char(frames.fullPath(i)));
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
        'periodicX', true, 'periodicY', true);
    m = local_tg_metrics(fields, kxMode, kyMode);
    amplitude(i) = m.amplitude;
    correlation(i) = m.correlation;
    gridKinetic(i) = m.gridKinetic;
    divRms(i) = m.divRms;
    divMaxAbs(i) = m.divMaxAbs;
    omegaRms(i) = m.omegaRms;
    lastFields = fields;

    if ~isempty(runtime) && ismember('step', runtime.Properties.VariableNames)
        j = find(runtime.step == step(i), 1, 'first');
        if ~isempty(j)
            kBTEstimate(i) = local_table_value(runtime, 'kBTEstimate', j);
            stdNRuntime(i) = local_table_value(runtime, 'stdN', j);
            q6ResidualRel(i) = local_table_value(runtime, 'q6ResidualRel', j);
            q6DivAfterRms(i) = local_table_value(runtime, 'q6DivAfterProjectedFluxRms', j);
            q9ResidualRel(i) = local_table_value(runtime, 'q9ResidualRel', j);
            q9CorrectionVelocityRms(i) = local_table_value(runtime, 'q9CorrectionVelocityRms', j);
            q9CorrectionVelocityMaxAbs(i) = local_table_value(runtime, 'q9CorrectionVelocityMaxAbs', j);
            q9TargetFilterRatio(i) = local_table_value(runtime, 'q9TargetDivergenceFilterRatio', j);
        end
    end
end

metrics = table(step, time, amplitude, correlation, gridKinetic, divRms, divMaxAbs, omegaRms, ...
    kBTEstimate, stdNRuntime, q6ResidualRel, q6DivAfterRms, q9ResidualRel, ...
    q9CorrectionVelocityRms, q9CorrectionVelocityMaxAbs, q9TargetFilterRatio);

run = struct();
run.runDir = runDir;
run.params = params;
run.frames = frames;
run.runtime = runtime;
run.metrics = metrics;
run.tail = local_tail_stats(runtime, tailFraction);
run.lastFields = lastFields;
end

function m = local_tg_metrics(fields, kxMode, kyMode)
Ux = fields.Ux;
Uy = fields.Uy;
valid = isfinite(Ux) & isfinite(Uy) & fields.N > 0;
Ux0 = Ux; Uy0 = Uy;
Ux0(~valid) = 0;
Uy0(~valid) = 0;

[X, Y] = meshgrid(fields.xc, fields.yc);
bx = sin(2*pi*kxMode*X/fields.Lx) .* cos(2*pi*kyMode*Y/fields.Ly);
by = -cos(2*pi*kxMode*X/fields.Lx) .* sin(2*pi*kyMode*Y/fields.Ly);

num = sum(Ux0(valid).*bx(valid) + Uy0(valid).*by(valid));
den = sum(bx(valid).^2 + by(valid).^2);
amplitude = num / max(den, eps);

uNorm = sqrt(sum(Ux0(valid).^2 + Uy0(valid).^2));
bNorm = sqrt(den);
correlation = num / max(uNorm * bNorm, eps);

div = local_periodic_divergence(Ux0, Uy0, fields.dx, fields.dy);
omega = local_periodic_curl(Ux0, Uy0, fields.dx, fields.dy);

m = struct();
m.amplitude = amplitude;
m.correlation = correlation;
m.gridKinetic = mean(0.5*(Ux0(valid).^2 + Uy0(valid).^2));
m.divRms = sqrt(mean(div(valid).^2));
m.divMaxAbs = max(abs(div(valid)));
m.omegaRms = sqrt(mean(omega(valid).^2));
end

function div = local_periodic_divergence(Ux, Uy, dx, dy)
dUx = (circshift(Ux, [0 -1]) - circshift(Ux, [0 1])) / (2*dx);
dUy = (circshift(Uy, [-1 0]) - circshift(Uy, [1 0])) / (2*dy);
div = dUx + dUy;
end

function omega = local_periodic_curl(Ux, Uy, dx, dy)
dUy_dx = (circshift(Uy, [0 -1]) - circshift(Uy, [0 1])) / (2*dx);
dUx_dy = (circshift(Ux, [-1 0]) - circshift(Ux, [1 0])) / (2*dy);
omega = dUy_dx - dUx_dy;
end

function summary = local_make_summary(classic, q6, q9)
runs = {classic; q6; q9};
labels = string({'classic'; 'q6'; 'q9_filtered'});
n = numel(runs);

nFrames = nan(n,1);
timeStart = nan(n,1);
timeEnd = nan(n,1);
amplitudeStart = nan(n,1);
amplitudeEnd = nan(n,1);
amplitudeRatio = nan(n,1);
correlationEnd = nan(n,1);
divRmsEnd = nan(n,1);
omegaRmsEnd = nan(n,1);
stdNEnd = nan(n,1);
stdNTailMean = nan(n,1);
kBTEnd = nan(n,1);
kBTTailMean = nan(n,1);
q6RuntimeDivAfterEnd = nan(n,1);
q6RuntimeResidualEnd = nan(n,1);
q9RuntimeResidualEnd = nan(n,1);
q9TargetFilterRatioEnd = nan(n,1);
q9TargetFilterRatioTailMean = nan(n,1);
q9CorrectionVelocityRmsEnd = nan(n,1);
q9CorrectionVelocityRmsTailMean = nan(n,1);
q9CorrectionVelocityMaxEnd = nan(n,1);

for i = 1:n
    r = runs{i};
    M = r.metrics;
    nFrames(i) = height(M);
    timeStart(i) = M.time(1);
    timeEnd(i) = M.time(end);
    amplitudeStart(i) = M.amplitude(1);
    amplitudeEnd(i) = M.amplitude(end);
    amplitudeRatio(i) = amplitudeEnd(i) / amplitudeStart(i);
    correlationEnd(i) = M.correlation(end);
    divRmsEnd(i) = M.divRms(end);
    omegaRmsEnd(i) = M.omegaRms(end);
    stdNEnd(i) = local_last_finite(M.stdNRuntime);
    kBTEnd(i) = local_last_finite(M.kBTEstimate);
    q6RuntimeDivAfterEnd(i) = local_last_finite(M.q6DivAfterRms);
    q6RuntimeResidualEnd(i) = local_last_finite(M.q6ResidualRel);
    q9RuntimeResidualEnd(i) = local_last_finite(M.q9ResidualRel);
    q9TargetFilterRatioEnd(i) = local_last_finite(M.q9TargetFilterRatio);
    q9CorrectionVelocityRmsEnd(i) = local_last_finite(M.q9CorrectionVelocityRms);
    q9CorrectionVelocityMaxEnd(i) = local_last_finite(M.q9CorrectionVelocityMaxAbs);

    stdNTailMean(i) = local_getfield_default(r.tail, 'stdNTailMean', nan);
    kBTTailMean(i) = local_getfield_default(r.tail, 'kBTTailMean', nan);
    q9TargetFilterRatioTailMean(i) = local_getfield_default(r.tail, 'q9TargetFilterRatioTailMean', nan);
    q9CorrectionVelocityRmsTailMean(i) = local_getfield_default(r.tail, 'q9CorrectionVelocityRmsTailMean', nan);
end

summary = table(labels, nFrames, timeStart, timeEnd, amplitudeStart, amplitudeEnd, amplitudeRatio, ...
    correlationEnd, divRmsEnd, omegaRmsEnd, stdNEnd, stdNTailMean, kBTEnd, kBTTailMean, ...
    q6RuntimeDivAfterEnd, q6RuntimeResidualEnd, q9RuntimeResidualEnd, ...
    q9TargetFilterRatioEnd, q9TargetFilterRatioTailMean, q9CorrectionVelocityRmsEnd, ...
    q9CorrectionVelocityRmsTailMean, q9CorrectionVelocityMaxEnd, ...
    'VariableNames', {'run','nFrames','timeStart','timeEnd','amplitudeStart','amplitudeEnd', ...
    'amplitudeRatio','correlationEnd','divRmsEnd','omegaRmsEnd','stdNEnd','stdNTailMean', ...
    'kBTEnd','kBTTailMean','q6RuntimeDivAfterEnd','q6RuntimeResidualEnd', ...
    'q9RuntimeResidualEnd','q9TargetFilterRatioEnd','q9TargetFilterRatioTailMean', ...
    'q9CorrectionVelocityRmsEnd','q9CorrectionVelocityRmsTailMean','q9CorrectionVelocityMaxEnd'});
end

function tail = local_tail_stats(T, tailFraction)
tail = struct();
if isempty(T) || height(T) == 0
    return;
end
startIdx = max(1, floor((1 - tailFraction) * height(T)) + 1);
idx = startIdx:height(T);
tail.stdNTailMean = local_mean_column(T, 'stdN', idx);
tail.kBTTailMean = local_mean_column(T, 'kBTEstimate', idx);
tail.q9TargetFilterRatioTailMean = local_mean_column(T, 'q9TargetDivergenceFilterRatio', idx);
tail.q9CorrectionVelocityRmsTailMean = local_mean_column(T, 'q9CorrectionVelocityRms', idx);
end

function v = local_mean_column(T, name, idx)
if ismember(name, T.Properties.VariableNames)
    v = mean(T.(name)(idx), 'omitnan');
else
    v = nan;
end
end

function v = local_table_value(T, name, row)
if ismember(name, T.Properties.VariableNames)
    v = T.(name)(row);
else
    v = nan;
end
end

function v = local_last_finite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx)
    v = nan;
else
    v = x(idx);
end
end

function v = local_getfield_default(s, name, defaultValue)
if isfield(s, name)
    v = s.(name);
else
    v = defaultValue;
end
end

function local_plot_comparison(classic, q6, q9)
figure('Name', 'Taylor-Green classic vs Q6 vs filtered Q9');
tiledlayout(4, 2, 'TileSpacing', 'compact');

nexttile;
plot(classic.metrics.time, classic.metrics.amplitude, '-', ...
     q6.metrics.time, q6.metrics.amplitude, '-', ...
     q9.metrics.time, q9.metrics.amplitude, '-');
grid on; xlabel('time'); ylabel('TG amplitude');
legend('classic','q6','q9 filtered','Location','best'); title('Taylor-Green mode amplitude');

nexttile;
plot(classic.metrics.time, classic.metrics.correlation, '-', ...
     q6.metrics.time, q6.metrics.correlation, '-', ...
     q9.metrics.time, q9.metrics.correlation, '-');
grid on; xlabel('time'); ylabel('correlation');
legend('classic','q6','q9 filtered','Location','best'); title('pattern correlation');

nexttile;
semilogy(classic.metrics.time, max(classic.metrics.divRms, realmin), '-', ...
         q6.metrics.time, max(q6.metrics.divRms, realmin), '-', ...
         q9.metrics.time, max(q9.metrics.divRms, realmin), '-');
grid on; xlabel('time'); ylabel('RMS div, cell centered');
legend('classic','q6','q9 filtered','Location','best'); title('dumped-field divergence');

nexttile;
semilogy(q6.metrics.time, max(q6.metrics.q6DivAfterRms, realmin), '-', ...
         q9.metrics.time, max(q9.metrics.q6DivAfterRms, realmin), '-');
grid on; xlabel('time'); ylabel('runtime Q6 div after');
legend('q6','q9 filtered','Location','best'); title('runtime Q6 projection');

nexttile;
plot(classic.metrics.time, classic.metrics.stdNRuntime, '-', ...
     q6.metrics.time, q6.metrics.stdNRuntime, '-', ...
     q9.metrics.time, q9.metrics.stdNRuntime, '-');
grid on; xlabel('time'); ylabel('runtime std(N)');
legend('classic','q6','q9 filtered','Location','best'); title('population fluctuations');

nexttile;
plot(classic.metrics.time, classic.metrics.kBTEstimate, '-', ...
     q6.metrics.time, q6.metrics.kBTEstimate, '-', ...
     q9.metrics.time, q9.metrics.kBTEstimate, '-');
grid on; xlabel('time'); ylabel('kBT estimate');
legend('classic','q6','q9 filtered','Location','best'); title('thermal state');

nexttile;
plot(classic.metrics.time, classic.metrics.omegaRms, '-', ...
     q6.metrics.time, q6.metrics.omegaRms, '-', ...
     q9.metrics.time, q9.metrics.omegaRms, '-');
grid on; xlabel('time'); ylabel('RMS omega');
legend('classic','q6','q9 filtered','Location','best'); title('vorticity RMS');

nexttile;
yyaxis left;
semilogy(q9.metrics.time, max(q9.metrics.q9ResidualRel, realmin), '-');
ylabel('Q9 residual');
yyaxis right;
plot(q9.metrics.time, q9.metrics.q9CorrectionVelocityRms, '-');
ylabel('Q9 correction RMS');
grid on; xlabel('time'); title('filtered Q9 diagnostics');
end

function local_plot_final_fields(classic, q6, q9)
figure('Name', 'Final Taylor-Green speed fields');
tiledlayout(1, 3, 'TileSpacing', 'compact');
local_plot_speed(classic.lastFields, 'classic final speed');
local_plot_speed(q6.lastFields, 'q6 final speed');
local_plot_speed(q9.lastFields, 'q9 filtered final speed');
end

function local_plot_speed(fields, ttl)
speed = sqrt(fields.Ux.^2 + fields.Uy.^2);
imagesc(fields.xc, fields.yc, speed);
axis image;
set(gca, 'YDir', 'normal');
colorbar;
xlabel('x'); ylabel('y');
title(ttl, 'Interpreter', 'none');
end

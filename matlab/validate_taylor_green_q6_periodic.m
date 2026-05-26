function out = validate_taylor_green_q6_periodic(classicRunDir, q6RunDir, varargin)
%VALIDATE_TAYLOR_GREEN_Q6_PERIODIC Compare classic and Q6 periodic Taylor--Green runs.
%
%   out = validate_taylor_green_q6_periodic(classicRunDir, q6RunDir)
%
%   The validator analyzes dumped .smpcd states. It projects the cell velocity
%   field onto the analytic Taylor--Green basis and reports the modal amplitude,
%   pattern correlation, finite-difference divergence, vorticity RMS, kBT and
%   selected Q6 runtime diagnostics.
%
%   This is a validation/diagnostic helper, not a benchmark-grade estimator of
%   viscosity. It is intended to check that Q6 preserves a coherent periodic
%   incompressible structure while removing grid-level divergence.

p = inputParser;
p.FunctionName = 'validate_taylor_green_q6_periodic';
addRequired(p, 'classicRunDir', @(s) ischar(s) || isstring(s));
addRequired(p, 'q6RunDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'kxMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kyMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'plotFinalFields', true, @(x) islogical(x) || isnumeric(x));
parse(p, classicRunDir, q6RunDir, varargin{:});
opts = p.Results;

classicRunDir = char(opts.classicRunDir);
q6RunDir = char(opts.q6RunDir);

classic = local_analyze_run(classicRunDir, opts.kxMode, opts.kyMode);
q6 = local_analyze_run(q6RunDir, opts.kxMode, opts.kyMode);

summary = local_make_summary(classic, q6);

out = struct();
out.classic = classic;
out.q6 = q6;
out.summary = summary;

fprintf('\n=== Taylor-Green periodic Q6 validation ===\n');
disp(summary);
fprintf('Classic run : %s\n', classicRunDir);
fprintf('Q6 run     : %s\n', q6RunDir);
fprintf('===========================================\n\n');

if opts.makePlots
    local_plot_comparison(classic, q6);
end
if opts.plotFinalFields
    local_plot_final_fields(classic, q6);
end
end

function run = local_analyze_run(runDir, kxMode, kyMode)
paramsFile = fullfile(runDir, 'params_used.kv');
if ~isfile(paramsFile)
    error('validate_taylor_green_q6_periodic:missingParams', ...
        'Cannot find params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsFile);

for name = {'Lx','Ly','Nx','Ny'}
    if ~isfield(params, name{1})
        error('validate_taylor_green_q6_periodic:missingParam', ...
            'Missing %s in %s', name{1}, paramsFile);
    end
end

Lx = double(params.Lx);
Ly = double(params.Ly);
Nx = double(params.Nx);
Ny = double(params.Ny);

frames = list_smpcd_dumps(runDir);
if height(frames) == 0
    error('validate_taylor_green_q6_periodic:noFrames', ...
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
q6Applied = nan(n,1);
q6ResidualRel = nan(n,1);
q6DivBeforeRms = nan(n,1);
q6DivAfterRms = nan(n,1);

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
            if ismember('kBTEstimate', runtime.Properties.VariableNames)
                kBTEstimate(i) = runtime.kBTEstimate(j);
            end
            if ismember('q6Applied', runtime.Properties.VariableNames)
                q6Applied(i) = runtime.q6Applied(j);
            end
            if ismember('q6ResidualRel', runtime.Properties.VariableNames)
                q6ResidualRel(i) = runtime.q6ResidualRel(j);
            end
            if ismember('q6DivBeforeRms', runtime.Properties.VariableNames)
                q6DivBeforeRms(i) = runtime.q6DivBeforeRms(j);
            end
            if ismember('q6DivAfterProjectedFluxRms', runtime.Properties.VariableNames)
                q6DivAfterRms(i) = runtime.q6DivAfterProjectedFluxRms(j);
            end
        end
    end
end

metrics = table(step, time, amplitude, correlation, gridKinetic, divRms, divMaxAbs, omegaRms, ...
    kBTEstimate, q6Applied, q6ResidualRel, q6DivBeforeRms, q6DivAfterRms);

run = struct();
run.runDir = runDir;
run.params = params;
run.frames = frames;
run.runtime = runtime;
run.metrics = metrics;
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

function summary = local_make_summary(classic, q6)
summary = table();
summary.run = string({'classic'; 'q6'});
summary.nFrames = [height(classic.metrics); height(q6.metrics)];
summary.timeStart = [classic.metrics.time(1); q6.metrics.time(1)];
summary.timeEnd = [classic.metrics.time(end); q6.metrics.time(end)];
summary.amplitudeStart = [classic.metrics.amplitude(1); q6.metrics.amplitude(1)];
summary.amplitudeEnd = [classic.metrics.amplitude(end); q6.metrics.amplitude(end)];
summary.amplitudeRatio = summary.amplitudeEnd ./ summary.amplitudeStart;
summary.correlationEnd = [classic.metrics.correlation(end); q6.metrics.correlation(end)];
summary.divRmsEnd = [classic.metrics.divRms(end); q6.metrics.divRms(end)];
summary.omegaRmsEnd = [classic.metrics.omegaRms(end); q6.metrics.omegaRms(end)];
summary.kBTEnd = [local_last_finite(classic.metrics.kBTEstimate); local_last_finite(q6.metrics.kBTEstimate)];
summary.q6RuntimeDivAfterEnd = [nan; local_last_finite(q6.metrics.q6DivAfterRms)];
summary.q6RuntimeResidualEnd = [nan; local_last_finite(q6.metrics.q6ResidualRel)];
end

function v = local_last_finite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx)
    v = nan;
else
    v = x(idx);
end
end

function local_plot_comparison(classic, q6)
figure('Name', 'Taylor-Green classic vs Q6');
tiledlayout(3, 2, 'TileSpacing', 'compact');

nexttile;
plot(classic.metrics.time, classic.metrics.amplitude, '-', ...
     q6.metrics.time, q6.metrics.amplitude, '-');
grid on; xlabel('time'); ylabel('TG amplitude');
legend('classic','q6','Location','best'); title('Taylor-Green mode amplitude');

nexttile;
plot(classic.metrics.time, classic.metrics.correlation, '-', ...
     q6.metrics.time, q6.metrics.correlation, '-');
grid on; xlabel('time'); ylabel('correlation');
legend('classic','q6','Location','best'); title('pattern correlation');

nexttile;
semilogy(classic.metrics.time, max(classic.metrics.divRms, realmin), '-', ...
         q6.metrics.time, max(q6.metrics.divRms, realmin), '-');
grid on; xlabel('time'); ylabel('RMS div, cell centered');
legend('classic','q6','Location','best'); title('dumped-field divergence');

nexttile;
semilogy(q6.metrics.time, max(q6.metrics.q6DivBeforeRms, realmin), '-', ...
         q6.metrics.time, max(q6.metrics.q6DivAfterRms, realmin), '-');
grid on; xlabel('time'); ylabel('runtime Q6 RMS div');
legend('before','after','Location','best'); title('runtime Q6 divergence');

nexttile;
plot(classic.metrics.time, classic.metrics.kBTEstimate, '-', ...
     q6.metrics.time, q6.metrics.kBTEstimate, '-');
grid on; xlabel('time'); ylabel('kBT estimate');
legend('classic','q6','Location','best'); title('thermal state');

nexttile;
plot(classic.metrics.time, classic.metrics.omegaRms, '-', ...
     q6.metrics.time, q6.metrics.omegaRms, '-');
grid on; xlabel('time'); ylabel('RMS omega');
legend('classic','q6','Location','best'); title('vorticity RMS');
end

function local_plot_final_fields(classic, q6)
figure('Name', 'Taylor-Green final fields');
tiledlayout(2, 3, 'TileSpacing', 'compact');
local_show_field(classic.lastFields, classic.lastFields.Ux, 'classic final Ux');
local_show_field(q6.lastFields, q6.lastFields.Ux, 'q6 final Ux');
local_show_field(q6.lastFields, q6.lastFields.Ux - classic.lastFields.Ux, 'q6 - classic Ux');
local_show_field(classic.lastFields, classic.lastFields.omega, 'classic final omega');
local_show_field(q6.lastFields, q6.lastFields.omega, 'q6 final omega');
local_show_field(q6.lastFields, q6.lastFields.omega - classic.lastFields.omega, 'q6 - classic omega');
end

function local_show_field(fields, A, ttl)
imagesc(fields.xc, fields.yc, A);
set(gca, 'YDir', 'normal'); axis image; colorbar;
xlabel('x'); ylabel('y'); title(ttl, 'Interpreter', 'none');
end

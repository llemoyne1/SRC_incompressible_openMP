function out = validate_poiseuille_q9_channel_long(varargin)
%VALIDATE_POISEUILLE_Q9_CHANNEL_LONG Compare long classic, Q6 and filtered Q9 channel Poiseuille runs.
%
%   out = validate_poiseuille_q9_channel_long('makePlots', true)
%
%   Defaults assume this function is called from the matlab/ directory and
%   therefore use ../runs/... paths.

p = inputParser;
p.FunctionName = 'validate_poiseuille_q9_channel_long';
addParameter(p, 'classicRunDir', '../runs/poiseuille_y_classic_solid_thermal_long', @(s) ischar(s) || isstring(s));
addParameter(p, 'q6RunDir', '../runs/poiseuille_y_q6_solid_thermal_long', @(s) ischar(s) || isstring(s));
addParameter(p, 'q9RunDir', '../runs/poiseuille_y_q9_filtered_solid_thermal_long', @(s) ischar(s) || isstring(s));
addParameter(p, 'fitStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'excludeWallCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'densityTailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'densityLowKMaxIndex', 2, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'densityFilterPasses', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'densityFilterTolerance', 1.0e-10, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'densityFilterMaxIterations', 500, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

classic = local_analyze_run(char(string(opts.classicRunDir)), opts);
q6      = local_analyze_run(char(string(opts.q6RunDir)), opts);
q9      = local_analyze_run(char(string(opts.q9RunDir)), opts);

summary = local_make_summary(classic, q6, q9);

out = struct();
out.classic = classic;
out.q6 = q6;
out.q9 = q9;
out.summary = summary;

fprintf('\n=== Poiseuille filtered Q9 channel validation ===\n');
disp(summary);
fprintf('Classic run : %s\n', classic.runDir);
fprintf('Q6 run      : %s\n', q6.runDir);
fprintf('Q9 run      : %s\n', q9.runDir);
fprintf('Poiseuille fit uses fitStartFraction = %.3g and excludeWallCells = %.3g.\n', ...
    opts.fitStartFraction, opts.excludeWallCells);
fprintf('Density tail statistics use the last %.0f%% of dumped frames.\n', 100*opts.densityTailFraction);
fprintf('================================================\n\n');

if logical(opts.makePlots)
    local_plot_comparison(classic, q6, q9);
end
end

function run = local_analyze_run(runDir, opts)
profile = analyze_poiseuille_profile(runDir, ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', opts.fitStartFraction, ...
    'excludeWallCells', opts.excludeWallCells, ...
    'frameStride', opts.frameStride, ...
    'makePlots', false);

density = local_density_diagnostics(profile, opts);

run = profile;
run.densityDiagnostics = density;
end

function summary = local_make_summary(classic, q6, q9)
runs = {classic, q6, q9};
names = string({'classic'; 'q6'; 'q9_filtered'});
n = numel(runs);

nFrames = nan(n,1);
timeStart = nan(n,1);
timeEnd = nan(n,1);
uCenter = nan(n,1);
uMax = nan(n,1);
fitR2 = nan(n,1);
nuEff = nan(n,1);
kBTEnd = nan(n,1);
kBTTailMean = nan(n,1);
rawStdNEnd = nan(n,1);
rawStdNTailMean = nan(n,1);
filteredStdNEnd = nan(n,1);
filteredStdNTailMean = nan(n,1);
filteredStdNRelToQ6 = nan(n,1);
q6DivAfterEnd = nan(n,1);
q6ResidualEnd = nan(n,1);
q6IterationsEnd = nan(n,1);
q9ResidualEnd = nan(n,1);
q9TargetFilterRatioEnd = nan(n,1);
q9CorrectionVelocityRmsEnd = nan(n,1);
q9CorrectionVelocityMaxEnd = nan(n,1);
maxParticleAbsVyEnd = nan(n,1);
yWallReflectionMaxPerParticleEnd = nan(n,1);

for i = 1:n
    r = runs{i};
    nFrames(i) = height(r.frameTable);
    timeStart(i) = local_first_finite(r.frameTable.time);
    timeEnd(i) = local_last_finite(r.frameTable.time);
    uCenter(i) = r.uCenter;
    uMax(i) = r.uMax;
    fitR2(i) = r.fit.r2;
    nuEff(i) = r.fit.nuEff;
    kBTEnd(i) = local_tail_value(r.summaryTable, 'kBTEstimate');
    kBTTailMean(i) = local_tail_mean(r.summaryTable, 'kBTEstimate', 0.5);
    rawStdNEnd(i) = r.densityDiagnostics.rawStdNEnd;
    rawStdNTailMean(i) = r.densityDiagnostics.rawStdNTailMean;
    filteredStdNEnd(i) = r.densityDiagnostics.filteredStdNEnd;
    filteredStdNTailMean(i) = r.densityDiagnostics.filteredStdNTailMean;
    q6 = local_q6_tail(r.summaryTable);
    q6DivAfterEnd(i) = q6.divAfter;
    q6ResidualEnd(i) = q6.residual;
    q6IterationsEnd(i) = q6.iterations;
    q9 = local_q9_tail(r.summaryTable);
    q9ResidualEnd(i) = q9.residual;
    q9TargetFilterRatioEnd(i) = q9.filterRatio;
    q9CorrectionVelocityRmsEnd(i) = q9.corrRms;
    q9CorrectionVelocityMaxEnd(i) = q9.corrMax;
    maxParticleAbsVyEnd(i) = local_tail_value(r.summaryTable, 'maxParticleAbsVy');
    yWallReflectionMaxPerParticleEnd(i) = local_tail_value(r.summaryTable, 'maxYWallReflectionsPerParticle');
end

q6FilteredTail = filteredStdNTailMean(2);
if isfinite(q6FilteredTail) && q6FilteredTail > 0
    filteredStdNRelToQ6 = filteredStdNTailMean ./ q6FilteredTail;
end

summary = table(names, nFrames, timeStart, timeEnd, uCenter, uMax, fitR2, nuEff, ...
    kBTEnd, kBTTailMean, rawStdNEnd, rawStdNTailMean, filteredStdNEnd, ...
    filteredStdNTailMean, filteredStdNRelToQ6, q6DivAfterEnd, q6ResidualEnd, ...
    q6IterationsEnd, q9ResidualEnd, q9TargetFilterRatioEnd, ...
    q9CorrectionVelocityRmsEnd, q9CorrectionVelocityMaxEnd, ...
    maxParticleAbsVyEnd, yWallReflectionMaxPerParticleEnd, ...
    'VariableNames', {'run','nFrames','timeStart','timeEnd','uCenter','uMax','fitR2','nuEff', ...
    'kBTEnd','kBTTailMean','rawStdNEnd','rawStdNTailMean','filteredStdNEnd', ...
    'filteredStdNTailMean','filteredStdNRelToQ6','q6RuntimeDivAfterEnd','q6RuntimeResidualEnd', ...
    'q6IterationsEnd','q9RuntimeResidualEnd','q9TargetFilterRatioEnd', ...
    'q9CorrectionVelocityRmsEnd','q9CorrectionVelocityMaxEnd', ...
    'maxParticleAbsVyEnd','yWallReflectionMaxPerParticleEnd'});
end

function d = local_density_diagnostics(profile, opts)
params = profile.params;
grid = profile.grid;
frames = profile.frameTable;
if height(frames) == 0
    error('validate_poiseuille_q9_channel_long:noFrames', 'No dumped frames found for %s.', profile.runDir);
end

periodicX = local_is_periodic_x(params);
periodicY = local_is_periodic_y(params);

n = height(frames);
rawStd = nan(n,1);
filteredStd = nan(n,1);
for k = 1:n
    state = read_smpcd_state(char(frames.fullPath(k)));
    fields = bin_smpcd_state(state, ...
        'Lx', grid.Lx, 'Ly', grid.Ly, 'Nx', grid.Nx, 'Ny', grid.Ny, ...
        'periodicX', periodicX, 'periodicY', periodicY);
    N = double(fields.N);
    fluct = N - mean(N(:));
    rawStd(k) = local_std(fluct(:));
    filtered = local_elliptic_lowpass(fluct, fields.dx, fields.dy, periodicX, periodicY, ...
        opts.densityLowKMaxIndex, opts.densityFilterPasses, ...
        opts.densityFilterTolerance, opts.densityFilterMaxIterations);
    filteredStd(k) = local_std(filtered(:));
end

tailMask = local_tail_mask(n, opts.densityTailFraction);

d = struct();
d.time = frames.time;
d.step = frames.step;
d.rawStdN = rawStd;
d.filteredStdN = filteredStd;
d.tailMask = tailMask;
d.rawStdNEnd = rawStd(end);
d.rawStdNTailMean = mean(rawStd(tailMask), 'omitnan');
d.filteredStdNEnd = filteredStd(end);
d.filteredStdNTailMean = mean(filteredStd(tailMask), 'omitnan');
d.lowKMaxIndex = opts.densityLowKMaxIndex;
d.filterPasses = opts.densityFilterPasses;
end

function y = local_elliptic_lowpass(x, dx, dy, periodicX, periodicY, lowKMaxIndex, passes, tol, maxIt)
y = double(x);
y = y - mean(y(:));
passes = max(0, round(passes));
if passes == 0
    return;
end
[Ny, Nx] = size(y);
nApprox = sqrt(double(Nx * Ny));
denom = max(1.0, 2.0 * double(lowKMaxIndex) + 1.0);
lenCells = max(1.0, nApprox / denom);
ell = lenCells * 0.5 * (dx + dy);
for p = 1:passes
    rhs = y - mean(y(:));
    y = local_solve_helmholtz(rhs, dx, dy, ell, periodicX, periodicY, tol, maxIt);
    y = y - mean(y(:));
end
end

function x = local_solve_helmholtz(rhs, dx, dy, ell, periodicX, periodicY, tol, maxIt)
% Solve (I + ell^2 * A) x = rhs, A = -div(grad), by CG.
rhs = double(rhs);
[Ny, Nx] = size(rhs);
x = zeros(Ny, Nx);
r = rhs - local_apply_helmholtz(x, dx, dy, ell, periodicX, periodicY);
p = r;
rr = sum(r(:).*r(:));
rhsNorm = sqrt(sum(rhs(:).*rhs(:)));
if rhsNorm <= eps
    return;
end
absTol = tol * rhsNorm;
for it = 1:maxIt %#ok<NASGU>
    Ap = local_apply_helmholtz(p, dx, dy, ell, periodicX, periodicY);
    pAp = sum(p(:).*Ap(:));
    if ~(pAp > 0) || ~isfinite(pAp)
        break;
    end
    alpha = rr / pAp;
    x = x + alpha * p;
    r = r - alpha * Ap;
    rrNew = sum(r(:).*r(:));
    if sqrt(rrNew) <= absTol
        break;
    end
    beta = rrNew / rr;
    p = r + beta * p;
    rr = rrNew;
end
end

function y = local_apply_helmholtz(x, dx, dy, ell, periodicX, periodicY)
y = x + ell^2 * local_negative_laplacian(x, dx, dy, periodicX, periodicY);
end

function A = local_negative_laplacian(x, dx, dy, periodicX, periodicY)
[Ny, Nx] = size(x);
A = zeros(Ny, Nx);

% x-direction contribution.
if periodicX
    xp = x(:, [2:Nx, 1]);
    xm = x(:, [Nx, 1:Nx-1]);
    A = A + (2*x - xp - xm) / (dx*dx);
else
    if Nx > 1
        A(:, 1) = A(:, 1) + (x(:,1) - x(:,2)) / (dx*dx);
        A(:, Nx) = A(:, Nx) + (x(:,Nx) - x(:,Nx-1)) / (dx*dx);
        if Nx > 2
            A(:, 2:Nx-1) = A(:, 2:Nx-1) + (2*x(:,2:Nx-1) - x(:,3:Nx) - x(:,1:Nx-2)) / (dx*dx);
        end
    end
end

% y-direction contribution.
if periodicY
    yp = x([2:Ny, 1], :);
    ym = x([Ny, 1:Ny-1], :);
    A = A + (2*x - yp - ym) / (dy*dy);
else
    if Ny > 1
        A(1, :) = A(1, :) + (x(1,:) - x(2,:)) / (dy*dy);
        A(Ny, :) = A(Ny, :) + (x(Ny,:) - x(Ny-1,:)) / (dy*dy);
        if Ny > 2
            A(2:Ny-1, :) = A(2:Ny-1, :) + (2*x(2:Ny-1,:) - x(3:Ny,:) - x(1:Ny-2,:)) / (dy*dy);
        end
    end
end
end

function q = local_q6_tail(T)
q = struct('divAfter', NaN, 'residual', NaN, 'iterations', NaN);
if isempty(T) || ~istable(T) || ~ismember('q6Applied', T.Properties.VariableNames)
    return;
end
mask = T.q6Applied > 0;
if ~any(mask)
    return;
end
TT = T(mask, :);
q.divAfter = local_tail_value(TT, 'q6DivAfterProjectedFluxRms');
q.residual = local_tail_value(TT, 'q6ResidualRel');
q.iterations = local_tail_value(TT, 'q6Iterations');
end

function q = local_q9_tail(T)
q = struct('residual', NaN, 'filterRatio', NaN, 'corrRms', NaN, 'corrMax', NaN);
if isempty(T) || ~istable(T) || ~ismember('q9Applied', T.Properties.VariableNames)
    return;
end
mask = T.q9Applied > 0;
if ~any(mask)
    return;
end
TT = T(mask, :);
q.residual = local_tail_value(TT, 'q9ResidualRel');
q.filterRatio = local_tail_value(TT, 'q9TargetDivergenceFilterRatio');
q.corrRms = local_tail_value(TT, 'q9CorrectionVelocityRms');
q.corrMax = local_tail_value_any(TT, {'q9CorrectionVelocityMaxAbs', 'q9CorrectionVelocityMax'});
end

function value = local_tail_value(T, name)
value = NaN;
if isempty(T) || ~istable(T) || ~ismember(name, T.Properties.VariableNames) || height(T) < 1
    return;
end
v = T.(name);
idx = find(isfinite(v), 1, 'last');
if ~isempty(idx)
    value = v(idx);
end
end

function value = local_tail_value_any(T, names)
value = NaN;
for k = 1:numel(names)
    value = local_tail_value(T, names{k});
    if isfinite(value)
        return;
    end
end
end

function value = local_tail_mean(T, name, tailFraction)
value = NaN;
if isempty(T) || ~istable(T) || ~ismember(name, T.Properties.VariableNames) || height(T) < 1
    return;
end
v = T.(name);
mask = local_tail_mask(numel(v), tailFraction) & isfinite(v);
if any(mask)
    value = mean(v(mask));
end
end

function mask = local_tail_mask(n, fraction)
fraction = min(max(fraction, eps), 1);
startIdx = max(1, floor((1 - fraction) * n) + 1);
mask = false(n,1);
mask(startIdx:end) = true;
end

function v = local_first_finite(x)
v = NaN;
idx = find(isfinite(x), 1, 'first');
if ~isempty(idx)
    v = x(idx);
end
end

function v = local_last_finite(x)
v = NaN;
idx = find(isfinite(x), 1, 'last');
if ~isempty(idx)
    v = x(idx);
end
end

function s = local_std(x)
x = x(isfinite(x));
if isempty(x)
    s = NaN;
else
    s = std(x, 0);
end
end

function tf = local_is_periodic_x(params)
tf = local_is_periodic_value(local_get_param(params, 'bcX', local_get_param(params, 'bcLeft', 'periodic'))) && ...
     local_is_periodic_value(local_get_param(params, 'bcRight', local_get_param(params, 'bcX', 'periodic')));
end

function tf = local_is_periodic_y(params)
tf = local_is_periodic_value(local_get_param(params, 'bcY', local_get_param(params, 'bcBottom', 'periodic'))) && ...
     local_is_periodic_value(local_get_param(params, 'bcTop', local_get_param(params, 'bcY', 'periodic')));
end

function tf = local_is_periodic_value(v)
tf = strcmpi(strtrim(char(string(v))), 'periodic');
end

function value = local_get_param(params, name, defaultValue)
if isfield(params, name)
    value = params.(name);
else
    value = defaultValue;
end
end

function local_plot_comparison(classic, q6, q9)
figure('Name', 'Poiseuille classic vs Q6 vs filtered Q9');
tiledlayout(2,2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(classic.coord, classic.avgProfile, 'o-', 'DisplayName', 'classic');
hold on;
plot(q6.coord, q6.avgProfile, 's-', 'DisplayName', 'q6');
plot(q9.coord, q9.avgProfile, '^-', 'DisplayName', 'q9 filtered');
plot(classic.coord, classic.fit.fitProfile, '--', 'DisplayName', 'classic fit');
plot(q6.coord, q6.fit.fitProfile, '--', 'DisplayName', 'q6 fit');
plot(q9.coord, q9.fit.fitProfile, '--', 'DisplayName', 'q9 fit');
hold off;
grid on;
xlabel('y'); ylabel('Ux');
title('Mean Poiseuille profile');
legend('Location', 'best');

nexttile;
hold on;
local_plot_density_series(classic, 'rawStdN', 'classic raw');
local_plot_density_series(q6, 'rawStdN', 'q6 raw');
local_plot_density_series(q9, 'rawStdN', 'q9 raw');
hold off;
grid on;
xlabel('time'); ylabel('std(N)');
title('Raw occupancy fluctuations');
legend('Location', 'best');

nexttile;
hold on;
local_plot_density_series(classic, 'filteredStdN', 'classic filtered');
local_plot_density_series(q6, 'filteredStdN', 'q6 filtered');
local_plot_density_series(q9, 'filteredStdN', 'q9 filtered');
hold off;
grid on;
xlabel('time'); ylabel('low-pass std(N-meanN)');
title('Elliptic-lowpass occupancy fluctuations');
legend('Location', 'best');

nexttile;
T = q9.summaryTable;
if ~isempty(T) && istable(T) && ismember('q9Applied', T.Properties.VariableNames)
    T = T(T.q9Applied > 0, :);
    if ~isempty(T)
        yyaxis left;
        semilogy(T.time, T.q9ResidualRel, '-', 'DisplayName', 'Q9 residual');
        ylabel('Q9 residual');
        yyaxis right;
        plot(T.time, T.q9CorrectionVelocityRms, '-', 'DisplayName', 'Q9 corr RMS');
        hold on;
        if ismember('q9CorrectionVelocityMaxAbs', T.Properties.VariableNames)
            plot(T.time, T.q9CorrectionVelocityMaxAbs, '-', 'DisplayName', 'Q9 corr max abs');
        elseif ismember('q9CorrectionVelocityMax', T.Properties.VariableNames)
            plot(T.time, T.q9CorrectionVelocityMax, '-', 'DisplayName', 'Q9 corr max');
        end
        if ismember('maxParticleAbsVy', T.Properties.VariableNames)
            plot(T.time, T.maxParticleAbsVy, '-', 'DisplayName', 'max |vy| particle');
        end
        hold off;
        ylabel('velocity correction');
        grid on;
        xlabel('time');
        title('Filtered Q9 runtime diagnostics');
    end
else
    text(0.1, 0.5, 'No Q9 runtime diagnostics found');
    axis off;
end
end

function local_plot_density_series(run, fieldName, labelName)
d = run.densityDiagnostics;
if isfield(d, fieldName)
    t = d.time;
    if all(~isfinite(t))
        t = d.step;
    end
    plot(t, d.(fieldName), '-', 'DisplayName', labelName);
end
end

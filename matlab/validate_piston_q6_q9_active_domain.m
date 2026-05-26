function out = validate_piston_q6_q9_active_domain(varargin)
%VALIDATE_PISTON_Q6_Q9_ACTIVE_DOMAIN Compare classic/Q6/Q9 moving-domain piston runs.
%
% Intended to be launched from matlab/.
%
% out = validate_piston_q6_q9_active_domain('makePlots', true);

p = inputParser;
p.FunctionName = 'validate_piston_q6_q9_active_domain';
addParameter(p, 'runDirs', { ...
    '../runs/piston_y_solid_thermal_isothermal', ...
    '../runs/piston_y_q6_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_filtered_solid_thermal_isothermal'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'labels', {'classic','q6','q9_filtered'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'tailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
parse(p, varargin{:});

runDirs = cellstr(string(p.Results.runDirs));
labels = cellstr(string(p.Results.labels));
if numel(runDirs) ~= numel(labels)
    error('validate_piston_q6_q9_active_domain:labelMismatch', ...
        'runDirs and labels must have the same length.');
end

S = cell(numel(runDirs), 1);
rows = cell(numel(runDirs), 1);
for k = 1:numel(runDirs)
    f = fullfile(runDirs{k}, 'summary_runtime.csv');
    if ~isfile(f)
        error('validate_piston_q6_q9_active_domain:missingSummary', ...
            'Cannot find summary file: %s', f);
    end
    S{k} = readtable(f);
    rows{k} = local_metrics(S{k}, labels{k}, runDirs{k}, p.Results.tailFraction);
end

metrics = vertcat(rows{:});
fprintf('\n=== Moving active-domain piston Q6/Q9 validation ===\n');
disp(metrics);

if p.Results.makePlots
    local_plot(S, labels);
end

out = struct();
out.runDirs = runDirs;
out.labels = labels;
out.summaries = S;
out.metrics = metrics;
end

function row = local_metrics(T, label, runDir, tailFraction)
required = {'time','fluidYMax','fluidArea','meanPhysicalDensity','totalMass','kBTEstimate'};
for i = 1:numel(required)
    if ~ismember(required{i}, T.Properties.VariableNames)
        error('validate_piston_q6_q9_active_domain:missingColumn', ...
            'Run %s is missing required column %s.', runDir, required{i});
    end
end

t = T.time;
n = height(T);
i0 = max(1, floor((1 - tailFraction) * n) + 1);
tail = i0:n;

yTopStart = T.fluidYMax(1);
yTopEnd = T.fluidYMax(end);
areaStart = T.fluidArea(1);
areaEnd = T.fluidArea(end);
rhoStart = T.meanPhysicalDensity(1);
rhoEnd = T.meanPhysicalDensity(end);
expectedRhoRatio = areaStart / areaEnd;
rhoRatio = rhoEnd / rhoStart;
rhoAreaResidual = rhoRatio - expectedRhoRatio;

massRelDrift = rel_change(T.totalMass(1), T.totalMass(end));
kBTEnd = T.kBTEstimate(end);
kBTTailMean = mean(T.kBTEstimate(tail), 'omitnan');

pkinProxy = (T.Np ./ T.fluidArea) .* T.kBTEstimate;
pkinProxyEndRatio = pkinProxy(end) / pkinProxy(1);

q6DivAfterEnd = last_or_nan(T, 'q6DivAfterProjectedFluxRms');
q6ResidualEnd = last_or_nan(T, 'q6ResidualRel');
q6IterationsEnd = last_or_nan(T, 'q6Iterations');
q9ResidualEnd = last_or_nan(T, 'q9ResidualRel');
q9FilterRatioEnd = last_or_nan(T, 'q9TargetDivergenceFilterRatio');
q9CorrectionRmsEnd = last_or_nan(T, 'q9CorrectionVelocityRms');
q9CorrectionMaxEnd = last_or_nan(T, 'q9CorrectionVelocityMaxAbs');
q9DensityStdEnd = last_or_nan(T, 'q9DensityStdBefore');
maxParticleAbsVyEnd = last_or_nan(T, 'maxParticleAbsVy');
yWallReflectionMaxEnd = last_or_nan(T, 'maxYWallReflectionsPerParticle');

row = table(string(label), string(runDir), n, t(1), t(end), ...
    yTopStart, yTopEnd, areaStart, areaEnd, expectedRhoRatio, rhoRatio, rhoAreaResidual, ...
    massRelDrift, kBTEnd, kBTTailMean, pkinProxyEndRatio, ...
    q6DivAfterEnd, q6ResidualEnd, q6IterationsEnd, ...
    q9ResidualEnd, q9FilterRatioEnd, q9CorrectionRmsEnd, q9CorrectionMaxEnd, q9DensityStdEnd, ...
    maxParticleAbsVyEnd, yWallReflectionMaxEnd, ...
    'VariableNames', {'run','runDir','nRows','timeStart','timeEnd', ...
    'yTopStart','yTopEnd','areaStart','areaEnd','expectedRhoRatio','rhoRatio','rhoAreaResidual', ...
    'massRelDrift','kBTEnd','kBTTailMean','pkinProxyEndRatio', ...
    'q6DivAfterEnd','q6ResidualEnd','q6IterationsEnd', ...
    'q9ResidualEnd','q9TargetFilterRatioEnd','q9CorrectionVelocityRmsEnd','q9CorrectionVelocityMaxEnd','q9DensityStdEnd', ...
    'maxParticleAbsVyEnd','yWallReflectionMaxPerParticleEnd'});
end

function local_plot(S, labels)
figure('Name', 'Moving active-domain piston Q6/Q9');
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; hold on;
for k = 1:numel(S), plot(S{k}.time, S{k}.fluidYMax, 'DisplayName', labels{k}); end
hold off; grid on; xlabel('time'); ylabel('y_{top}'); title('Moving top wall'); legend('Interpreter','none');

nexttile; hold on;
for k = 1:numel(S), plot(S{k}.time, S{k}.meanPhysicalDensity./S{k}.meanPhysicalDensity(1), 'DisplayName', labels{k}); end
hold off; grid on; xlabel('time'); ylabel('\rho/\rho_0'); title('Mean density ratio');

nexttile; hold on;
for k = 1:numel(S), plot(S{k}.time, S{k}.kBTEstimate, 'DisplayName', labels{k}); end
hold off; grid on; xlabel('time'); ylabel('kBT'); title('Thermal response');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('q6DivAfterProjectedFluxRms', S{k}.Properties.VariableNames)
        semilogy(S{k}.time, max(S{k}.q6DivAfterProjectedFluxRms, eps), 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('Q6 div after'); title('Q6 projection');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('q9CorrectionVelocityRms', S{k}.Properties.VariableNames)
        semilogy(S{k}.time, max(S{k}.q9CorrectionVelocityRms, eps), 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('Q9 kick RMS'); title('Q9 correction');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('maxParticleAbsVy', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.maxParticleAbsVy, 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('max |v_y|'); title('Particle-wall safety');
end

function v = last_or_nan(T, name)
if ismember(name, T.Properties.VariableNames)
    v = T.(name)(end);
else
    v = NaN;
end
end

function r = rel_change(a, b)
if isfinite(a) && isfinite(b) && abs(a) > 0
    r = b / a - 1;
else
    r = NaN;
end
end

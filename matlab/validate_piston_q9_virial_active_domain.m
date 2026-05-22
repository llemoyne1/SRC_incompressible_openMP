function out = validate_piston_q9_virial_active_domain(varargin)
%VALIDATE_PISTON_Q9_VIRIAL_ACTIVE_DOMAIN Compare piston classic/Q6/Q9/Q9+virial.
%
% Intended to be launched from matlab/.
%
% out = validate_piston_q9_virial_active_domain('makePlots', true);

p = inputParser;
p.FunctionName = 'validate_piston_q9_virial_active_domain';
addParameter(p, 'runDirs', { ...
    '../runs/piston_y_solid_thermal_isothermal', ...
    '../runs/piston_y_q6_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_filtered_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_virial_solid_thermal_isothermal'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'labels', {'classic','q6','q9_filtered','q9_virial'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'tailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
parse(p, varargin{:});

runDirs = cellstr(string(p.Results.runDirs));
labels = cellstr(string(p.Results.labels));
if numel(runDirs) ~= numel(labels)
    error('validate_piston_q9_virial_active_domain:labelMismatch', ...
        'runDirs and labels must have the same length.');
end

S = cell(numel(runDirs), 1);
rows = cell(numel(runDirs), 1);
for k = 1:numel(runDirs)
    f = fullfile(runDirs{k}, 'summary_runtime.csv');
    if ~isfile(f)
        error('validate_piston_q9_virial_active_domain:missingSummary', ...
            'Cannot find summary file: %s', f);
    end
    S{k} = readtable(f);
    rows{k} = local_metrics(S{k}, labels{k}, runDirs{k}, p.Results.tailFraction);
end

metrics = vertcat(rows{:});
fprintf('\n=== Moving active-domain piston Q9/virial validation ===\n');
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
        error('validate_piston_q9_virial_active_domain:missingColumn', ...
            'Run %s is missing required column %s.', runDir, required{i});
    end
end

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

PkinMeanEnd = last_or_nan(T, 'PkinMean');
PvirMeanEnd = last_or_nan(T, 'PvirMean');
PtotMeanEnd = last_or_nan(T, 'PtotMean');
PdriveMeanEnd = last_or_nan(T, 'PdriveMean');
PtotMeanStart = first_or_nan(T, 'PtotMean');
PtotMeanRatio = safe_ratio(PtotMeanEnd, PtotMeanStart);

row = table(string(label), string(runDir), n, T.time(1), T.time(end), ...
    yTopStart, yTopEnd, expectedRhoRatio, rhoRatio, rhoAreaResidual, massRelDrift, ...
    kBTEnd, kBTTailMean, pkinProxyEndRatio, ...
    last_or_nan(T, 'q6DivAfterProjectedFluxRms'), last_or_nan(T, 'q6ResidualRel'), ...
    last_or_nan(T, 'q9ResidualRel'), last_or_nan(T, 'q9TargetDivergenceFilterRatio'), ...
    last_or_nan(T, 'q9CorrectionVelocityRms'), last_or_nan(T, 'q9CorrectionVelocityMaxAbs'), ...
    last_or_nan(T, 'virialEnabled'), last_or_nan(T, 'virialKickApplied'), ...
    last_or_nan(T, 'virialRhoMean'), last_or_nan(T, 'virialRhoEOSRef'), ...
    last_or_nan(T, 'virialRhoUniformNow'), last_or_nan(T, 'virialRhoDefectRelRms'), ...
    PkinMeanEnd, PvirMeanEnd, PtotMeanEnd, PdriveMeanEnd, PtotMeanRatio, ...
    last_or_nan(T, 'gradPdriveRms'), last_or_nan(T, 'virialDuAppliedRms'), ...
    last_or_nan(T, 'virialDuAppliedMaxAbs'), last_or_nan(T, 'virialDuOverThermalRms'), ...
    last_or_nan(T, 'virialMomentumResidualAfterCorrection'), ...
    last_or_nan(T, 'maxParticleAbsVy'), last_or_nan(T, 'maxYWallReflectionsPerParticle'), ...
    'VariableNames', {'run','runDir','nRows','timeStart','timeEnd', ...
    'yTopStart','yTopEnd','expectedRhoRatio','rhoRatio','rhoAreaResidual','massRelDrift', ...
    'kBTEnd','kBTTailMean','pkinProxyEndRatio', ...
    'q6DivAfterEnd','q6ResidualEnd', ...
    'q9ResidualEnd','q9TargetFilterRatioEnd','q9CorrectionVelocityRmsEnd','q9CorrectionVelocityMaxEnd', ...
    'virialEnabled','virialKickApplied','virialRhoMean','virialRhoEOSRef','virialRhoUniformNow','virialRhoDefectRelRms', ...
    'PkinMeanEnd','PvirMeanEnd','PtotMeanEnd','PdriveMeanEnd','PtotMeanRatio', ...
    'gradPdriveRmsEnd','virialDuAppliedRmsEnd','virialDuAppliedMaxEnd','virialDuOverThermalRmsEnd', ...
    'virialMomentumResidualAfterCorrectionEnd', ...
    'maxParticleAbsVyEnd','yWallReflectionMaxPerParticleEnd'});
end

function local_plot(S, labels)
figure('Name', 'Moving active-domain piston Q9 virial');
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; hold on;
for k = 1:numel(S), plot(S{k}.time, S{k}.meanPhysicalDensity./S{k}.meanPhysicalDensity(1), 'DisplayName', labels{k}); end
hold off; grid on; xlabel('time'); ylabel('\rho/\rho_0'); title('Mean density ratio'); legend('Interpreter','none');

nexttile; hold on;
for k = 1:numel(S), plot(S{k}.time, S{k}.kBTEstimate, 'DisplayName', labels{k}); end
hold off; grid on; xlabel('time'); ylabel('kBT'); title('Thermal response');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('PtotMean', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.PtotMean, 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('P_{tot} mean'); title('EOS total pressure');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('PvirMean', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.PvirMean, 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('P_{vir} mean'); title('Virial pressure');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('virialDuAppliedRms', S{k}.Properties.VariableNames)
        semilogy(S{k}.time, max(S{k}.virialDuAppliedRms, eps), 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('virial du RMS'); title('Virial velocity kick');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('maxParticleAbsVy', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.maxParticleAbsVy, 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('max |v_y|'); title('Particle-wall safety');
end

function v = first_or_nan(T, name)
if ismember(name, T.Properties.VariableNames)
    v = T.(name)(1);
else
    v = NaN;
end
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

function r = safe_ratio(a, b)
if isfinite(a) && isfinite(b) && abs(b) > 0
    r = a / b;
else
    r = NaN;
end
end

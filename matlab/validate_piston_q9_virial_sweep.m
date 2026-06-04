function out = validate_piston_q9_virial_sweep(varargin)
%VALIDATE_PISTON_Q9_VIRIAL_SWEEP Summarize a Kvirial/virialBeta piston sweep.
%
% Intended to be launched from matlab/.
%
% out = validate_piston_q9_virial_sweep('makePlots', true);

p = inputParser;
p.FunctionName = 'validate_piston_q9_virial_sweep';
addParameter(p, 'runDirs', { ...
    '../runs/piston_y_q9_filtered_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_virial_K0p005_beta0p02_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_virial_K0p010_beta0p02_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_virial_K0p020_beta0p02_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_virial_K0p050_beta0p02_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_virial_K0p100_beta0p02_solid_thermal_isothermal', ...
    '../runs/piston_y_q9_virial_K0p100_beta0p05_solid_thermal_isothermal'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'labels', { ...
    'q9_filtered', ...
    'K0p005_b0p02', ...
    'K0p010_b0p02', ...
    'K0p020_b0p02', ...
    'K0p050_b0p02', ...
    'K0p100_b0p02', ...
    'K0p100_b0p05'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'tailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
parse(p, varargin{:});

runDirs = cellstr(string(p.Results.runDirs));
labels = cellstr(string(p.Results.labels));
if numel(runDirs) ~= numel(labels)
    error('validate_piston_q9_virial_sweep:labelMismatch', ...
        'runDirs and labels must have the same length.');
end

S = cell(numel(runDirs), 1);
rows = cell(numel(runDirs), 1);
for k = 1:numel(runDirs)
    f = fullfile(runDirs{k}, 'summary_runtime.csv');
    if ~isfile(f)
        error('validate_piston_q9_virial_sweep:missingSummary', ...
            'Cannot find summary file: %s', f);
    end
    S{k} = readtable(f);
    rows{k} = local_metrics(S{k}, labels{k}, runDirs{k}, p.Results.tailFraction);
end

metrics = vertcat(rows{:});
fprintf('\n=== Moving active-domain piston Q9/virial sweep ===\n');
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
n = height(T);
i0 = max(1, floor((1 - tailFraction) * n) + 1);
tail = i0:n;

rhoStart = first_finite_or_nan(T, 'meanPhysicalDensity');
rhoEnd = last_finite_or_nan(T, 'meanPhysicalDensity');
areaStart = first_finite_or_nan(T, 'fluidArea');
areaEnd = last_finite_or_nan(T, 'fluidArea');
expectedRhoRatio = safe_ratio(areaStart, areaEnd);
rhoRatio = safe_ratio(rhoEnd, rhoStart);

PtotStart = first_finite_positive_or_nan(T, 'PtotMean');
PtotEnd = last_finite_or_nan(T, 'PtotMean');
PkinStart = first_finite_positive_or_nan(T, 'PkinMean');
PkinEnd = last_finite_or_nan(T, 'PkinMean');
PvirEnd = last_finite_or_nan(T, 'PvirMean');

KvirialEstimate = NaN;
rhoEOSRef = last_finite_or_nan(T, 'virialRhoEOSRef');
if isfinite(PvirEnd) && isfinite(rhoEnd) && isfinite(rhoEOSRef) && abs(rhoEnd-rhoEOSRef) > 0
    KvirialEstimate = PvirEnd / (rhoEnd - rhoEOSRef);
end

PtotExpectedEnd = NaN;
if isfinite(PkinEnd) && isfinite(KvirialEstimate) && isfinite(rhoEnd) && isfinite(rhoEOSRef)
    PtotExpectedEnd = PkinEnd + KvirialEstimate * (rhoEnd - rhoEOSRef);
end

row = table(string(label), string(runDir), n, first_finite_or_nan(T, 'time'), last_finite_or_nan(T, 'time'), ...
    expectedRhoRatio, rhoRatio, rhoRatio - expectedRhoRatio, ...
    rel_change(first_finite_or_nan(T, 'totalMass'), last_finite_or_nan(T, 'totalMass')), ...
    last_finite_or_nan(T, 'kBTEstimate'), mean_omitnan(T, 'kBTEstimate', tail), ...
    last_finite_or_nan(T, 'q6DivAfterProjectedFluxRms'), last_finite_or_nan(T, 'q6ResidualRel'), ...
    last_finite_or_nan(T, 'q9ResidualRel'), last_finite_or_nan(T, 'q9TargetDivergenceFilterRatio'), ...
    last_finite_or_nan(T, 'q9CorrectionVelocityRms'), last_finite_or_nan(T, 'q9CorrectionVelocityMaxAbs'), ...
    last_finite_or_nan(T, 'virialEnabled'), last_finite_or_nan(T, 'virialKickApplied'), ...
    last_finite_or_nan(T, 'virialRhoMean'), rhoEOSRef, last_finite_or_nan(T, 'virialRhoUniformNow'), ...
    last_finite_or_nan(T, 'virialRhoDefectRelRms'), ...
    PkinEnd, PvirEnd, PtotEnd, safe_ratio(PkinEnd, PkinStart), safe_ratio(PtotEnd, PtotStart), ...
    KvirialEstimate, PtotExpectedEnd, PtotEnd - PtotExpectedEnd, ...
    last_finite_or_nan(T, 'gradPdriveRms'), ...
    last_finite_or_nan(T, 'virialDuAppliedRms'), mean_omitnan(T, 'virialDuAppliedRms', tail), ...
    last_finite_or_nan(T, 'virialDuAppliedMaxAbs'), last_finite_or_nan(T, 'virialDuOverThermalRms'), ...
    last_finite_or_nan(T, 'virialMomentumResidualAfterCorrection'), ...
    last_finite_or_nan(T, 'maxParticleAbsVy'), last_finite_or_nan(T, 'maxYWallReflectionsPerParticle'), ...
    'VariableNames', {'run','runDir','nRows','timeStart','timeEnd', ...
    'expectedRhoRatio','rhoRatio','rhoAreaResidual','massRelDrift', ...
    'kBTEnd','kBTTailMean', ...
    'q6DivAfterEnd','q6ResidualEnd','q9ResidualEnd','q9TargetFilterRatioEnd', ...
    'q9CorrectionVelocityRmsEnd','q9CorrectionVelocityMaxEnd', ...
    'virialEnabled','virialKickApplied','virialRhoMean','virialRhoEOSRef','virialRhoUniformNow','virialRhoDefectRelRms', ...
    'PkinMeanEnd','PvirMeanEnd','PtotMeanEnd','PkinMeanRatio','PtotMeanRatio', ...
    'KvirialEstimate','PtotExpectedEnd','PtotExpectedResidual', ...
    'gradPdriveRmsEnd','virialDuAppliedRmsEnd','virialDuAppliedRmsTailMean', ...
    'virialDuAppliedMaxEnd','virialDuOverThermalRmsEnd','virialMomentumResidualAfterCorrectionEnd', ...
    'maxParticleAbsVyEnd','yWallReflectionMaxPerParticleEnd'});
end

function local_plot(S, labels)
figure('Name', 'Piston Q9 virial sweep');
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; hold on;
for k = 1:numel(S), plot(S{k}.time, S{k}.meanPhysicalDensity./S{k}.meanPhysicalDensity(1), 'DisplayName', labels{k}); end
hold off; grid on; xlabel('time'); ylabel('\rho/\rho_0'); title('Mean density ratio'); legend('Interpreter','none');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('PtotMean', S{k}.Properties.VariableNames)
        y = S{k}.PtotMean;
        i0 = find(isfinite(y) & y > 0, 1, 'first');
        if ~isempty(i0), plot(S{k}.time, y./y(i0), 'DisplayName', labels{k}); end
    end
end
hold off; grid on; xlabel('time'); ylabel('P_{tot}/P_{tot,0}'); title('EOS total pressure ratio');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('PvirMean', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.PvirMean, 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('P_{vir}'); title('Mean virial pressure');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('virialDuAppliedRms', S{k}.Properties.VariableNames)
        semilogy(S{k}.time, max(S{k}.virialDuAppliedRms, eps), 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('du RMS'); title('Virial kick RMS');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('virialDuAppliedMaxAbs', S{k}.Properties.VariableNames)
        semilogy(S{k}.time, max(S{k}.virialDuAppliedMaxAbs, eps), 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('du max'); title('Virial kick max');

nexttile; hold on;
for k = 1:numel(S)
    if ismember('maxParticleAbsVy', S{k}.Properties.VariableNames)
        plot(S{k}.time, S{k}.maxParticleAbsVy, 'DisplayName', labels{k});
    end
end
hold off; grid on; xlabel('time'); ylabel('max |v_y|'); title('Wall safety');
end

function v = first_finite_or_nan(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'first');
    if ~isempty(idx), v = x(idx); end
end
end


function v = first_finite_positive_or_nan(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x) & x > 0, 1, 'first');
    if ~isempty(idx), v = x(idx); end
end
end

function v = last_finite_or_nan(T, name)
v = NaN;
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
    idx = find(isfinite(x), 1, 'last');
    if ~isempty(idx), v = x(idx); end
end
end

function v = mean_omitnan(T, name, idx)
if ismember(name, T.Properties.VariableNames)
    v = mean(T.(name)(idx), 'omitnan');
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

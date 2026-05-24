function S = analyze_backward_step_hard_inlet_validation_0067(varargin)
%ANALYZE_BACKWARD_STEP_HARD_INLET_VALIDATION_0067 Summarize 0067 hard-inlet backward-step runs.
%
% Example:
%   cd matlab
%   S = analyze_backward_step_hard_inlet_validation_0067('root','..');

    p = inputParser;
    addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
    addParameter(p, 'runRoot', 'runs/backward_step_hard_inlet_validation_0067', @(s) ischar(s) || isstring(s));
    addParameter(p, 'lateFraction', 0.33, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
    addParameter(p, 'kBTTarget', 0.0025, @(x) isnumeric(x) && isscalar(x) && x > 0);
    parse(p, varargin{:});
    opt = p.Results;

    root = char(opt.root);
    runRoot = fullfile(root, char(opt.runRoot));
    D = dir(runRoot);
    isCase = [D.isdir] & ~ismember({D.name}, {'.','..','params'});
    labels = string({D(isCase).name});
    labels = sort(labels);

    rows = struct([]);
    for a = 1:numel(labels)
        label = labels(a);
        f = fullfile(runRoot, char(label), 'summary_runtime.csv');
        if ~isfile(f)
            warning('Missing summary_runtime.csv for %s', label);
            continue;
        end
        T = readtable(f);
        if isempty(T), continue; end
        i0 = max(1, floor((1 - opt.lateFraction) * height(T)) + 1);
        L = T(i0:end,:);
        r = struct();
        r.caseLabel = label;
        r.nRows = height(T);
        r.timeFinal = T.time(end);
        r.NpFirst = T.Np(1);
        r.NpFinal = T.Np(end);
        r.totalMassFirst = T.totalMass(1);
        r.totalMassFinal = T.totalMass(end);
        r.meanVxFirst = T.meanVx(1);
        r.meanVxFinal = T.meanVx(end);
        r.meanVyFinal = T.meanVy(end);
        r.kBTMeanLate = mean(L.kBTEstimate, 'omitnan');
        r.kBTMaxLate = max(L.kBTEstimate, [], 'omitnan');
        r.kBTOverTargetLate = r.kBTMeanLate / opt.kBTTarget;
        r.stdNFinal = T.stdN(end);
        r.stdNMeanLate = mean(L.stdN, 'omitnan');
        r.minNFinal = T.minN(end);
        r.maxNFinal = T.maxN(end);
        r.hitsLeftFinal = T.hitsLeft(end);
        r.hitsRightFinal = T.hitsRight(end);
        r.inletHardReservoirEnabledFinal = getlast(T, 'inletHardReservoirEnabled');
        r.inletReservoirCellsFinal = getlast(T, 'inletReservoirCells');
        r.inletReservoirTargetParticlesFinal = getlast(T, 'inletReservoirTargetParticles');
        r.inletReservoirDeletedMeanLate = getmean(L, 'inletReservoirDeleted');
        r.inletBackflowDeletedMeanLate = getmean(L, 'inletBackflowDeleted');
        r.outletParticlesDeletedMeanLate = getmean(L, 'outletParticlesDeleted');
        r.inletParticlesInsertedMeanLate = getmean(L, 'inletParticlesInserted');
        r.inletNetParticleDeltaMeanLate = getmean(L, 'inletNetParticleDelta');
        r.inletReservoirMeanNFinal = getlast(T, 'inletReservoirMeanN');
        r.inletReservoirStdNFinal = getlast(T, 'inletReservoirStdN');
        r.inletReservoirMinNFinal = getlast(T, 'inletReservoirMinN');
        r.inletReservoirMaxNFinal = getlast(T, 'inletReservoirMaxN');
        r.inletReservoirEmptyFractionFinal = getlast(T, 'inletReservoirEmptyFraction');
        r.inletMeanUxFinal = getlast(T, 'inletMeanUx');
        r.inletMeanUyFinal = getlast(T, 'inletMeanUy');
        r.inletKBTFinal = getlast(T, 'inletKBT');
        r.q6AppliedFinal = getlast(T, 'q6Applied');
        r.q6ConvergedFinal = getlast(T, 'q6Converged');
        r.q6DivBeforeFinal = getlast(T, 'q6DivBeforeRms');
        r.q6DivAfterFinal = getlast(T, 'q6DivAfterProjectedFluxRms');
        r.q6DivRatioFinal = safe_ratio(r.q6DivAfterFinal, r.q6DivBeforeFinal);
        r.q6ImmersedLeakCellClosedFinal = getlast(T, 'q6ImmersedSolidLeakCellClosedProjectedFluxRms');
        r.q9AppliedFinal = getlast(T, 'q9Applied');
        r.q9ConvergedFinal = getlast(T, 'q9Converged');
        r.q9MassDivBeforeFinal = getlast(T, 'q9MassFluxDivBeforeRms');
        r.q9MassDivAfterFinal = getlast(T, 'q9MassFluxDivAfterRms');
        r.q9MassDivRatioFinal = safe_ratio(r.q9MassDivAfterFinal, r.q9MassDivBeforeFinal);
        r.q9DensityMeanFinal = getlast(T, 'q9DensityMean');
        r.q9DensityStdBeforeFinal = getlast(T, 'q9DensityStdBefore');
        r.q9DensityStdRatioEstimateFinal = getlast(T, 'q9DensityStdRatioEstimate');
        r.q9CorrectionVelocityRmsFinal = getlast(T, 'q9CorrectionVelocityRms');
        r.q9CorrectionVelocityMaxAbsFinal = getlast(T, 'q9CorrectionVelocityMaxAbs');
        r.virialKickAppliedFinal = getlast(T, 'virialKickApplied');
        r.virialDuOverThermalRmsFinal = getlast(T, 'virialDuOverThermalRms');
        r.virialMomentumResidualAfterFinal = getlast(T, 'virialMomentumResidualAfterCorrection');
        r.passHardInletDensity = r.inletHardReservoirEnabledFinal == 1 && ...
            r.inletReservoirStdNFinal == 0 && r.inletReservoirMinNFinal == 20 && ...
            r.inletReservoirMaxNFinal == 20 && abs(r.inletMeanUxFinal - 0.05) < 1e-12;
        r.passThermalRelative = r.kBTOverTargetLate < 2.0;
        r.passNoCatastrophicQ9 = isnan(r.q9CorrectionVelocityMaxAbsFinal) || r.q9CorrectionVelocityMaxAbsFinal < 1.0;
        rows = [rows; r]; %#ok<AGROW>
    end

    if isempty(rows)
        S = table();
    else
        S = struct2table(rows);
    end
    out = fullfile(runRoot, 'summary_hard_inlet_validation_0067.csv');
    if ~isempty(S)
        writetable(S, out);
        disp(S);
        fprintf('[analyze 0067] wrote %s\n', out);
    end
end

function y = getlast(T, name)
    if ismember(name, T.Properties.VariableNames)
        y = T.(name)(end);
    else
        y = NaN;
    end
end

function y = getmean(T, name)
    if ismember(name, T.Properties.VariableNames)
        y = mean(T.(name), 'omitnan');
    else
        y = NaN;
    end
end

function r = safe_ratio(a, b)
    if isfinite(a) && isfinite(b) && abs(b) > 0
        r = a / b;
    else
        r = NaN;
    end
end

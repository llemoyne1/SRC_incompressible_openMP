function S = analyze_backward_step_q9_safety_smoke_0066(varargin)
%ANALYZE_BACKWARD_STEP_Q9_SAFETY_SMOKE_0066 Summarize guarded Q9 backstep smoke.
%
% 0066c separates three questions which were mixed in the first smoke:
%   1. Did the elliptic solvers report strict convergence?
%   2. Did the run remain physically bounded?
%   3. Is Q9 mostly acting smoothly, or is the limiter saving many cells?

    p = inputParser;
    addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
    addParameter(p, 'runRoot', 'runs/backward_step_q9_safety_smoke_0066', @(s) ischar(s) || isstring(s));
    addParameter(p, 'kBTTarget', 0.0025, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'lateFraction', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
    addParameter(p, 'maxKBTOverTarget', 1.5, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'maxQ9LimitedFraction', 0.12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'maxQ9KBTOverQ6', 1.15, @(x) isnumeric(x) && isscalar(x) && x > 0);
    parse(p, varargin{:});
    opt = p.Results;

    root = char(opt.root);
    runRoot = fullfile(root, char(opt.runRoot));
    d = dir(fullfile(runRoot, '*', 'summary_runtime.csv'));
    if isempty(d)
        error('No summary_runtime.csv files found under %s', runRoot);
    end

    rows = table();
    for i = 1:numel(d)
        caseDir = d(i).folder;
        [~, caseLabel] = fileparts(caseDir);
        T = readtable(fullfile(caseDir, d(i).name));
        n = height(T);
        i0 = max(1, floor((1 - opt.lateFraction) * n));
        L = T(i0:end, :);

        q9Active = get_last(T, 'q9SafetyActiveCells');
        q9Limited = get_last(T, 'q9VelocityLimitedCells');
        q9LimitedFrac = safe_ratio(q9Limited, q9Active);

        R = table();
        R.caseLabel = string(caseLabel);
        R.nRows = n;
        R.timeFinal = T.time(end);
        R.NpFirst = T.Np(1);
        R.NpFinal = T.Np(end);
        R.totalMassFirst = T.totalMass(1);
        R.totalMassFinal = T.totalMass(end);
        R.meanVxFinal = T.meanVx(end);
        R.meanVyFinal = T.meanVy(end);
        R.kBTMeanLate = mean(L.kBTEstimate, 'omitnan');
        R.kBTMinLate = min(L.kBTEstimate, [], 'omitnan');
        R.kBTMaxLate = max(L.kBTEstimate, [], 'omitnan');
        R.kBTOverTargetLate = R.kBTMeanLate / opt.kBTTarget;
        R.stdNMeanLate = mean(L.stdN, 'omitnan');
        R.stdNFinal = T.stdN(end);
        R.minNFinal = T.minN(end);
        R.maxNFinal = T.maxN(end);

        R.q6AppliedFinal = get_last(T, 'q6Applied');
        R.q6ConvergedFinal = get_last(T, 'q6Converged');
        R.q6DivBeforeFinal = get_last(T, 'q6DivBeforeRms');
        R.q6DivAfterFinal = get_last(T, 'q6DivAfterProjectedFluxRms');
        R.q6DivRatioFinal = safe_ratio(R.q6DivAfterFinal, R.q6DivBeforeFinal);
        R.q6CorrectionVelocityRmsFinal = get_last(T, 'q6CorrectionVelocityRms');
        R.q6CorrectionVelocityMaxAbsFinal = get_last(T, 'q6CorrectionVelocityMaxAbs');

        R.q9AppliedFinal = get_last(T, 'q9Applied');
        R.q9ConvergedFinal = get_last(T, 'q9Converged');
        R.q9MassDivBeforeFinal = get_last(T, 'q9MassFluxDivBeforeRms');
        R.q9MassDivAfterFinal = get_last(T, 'q9MassFluxDivAfterRms');
        R.q9MassDivRatioFinal = safe_ratio(R.q9MassDivAfterFinal, R.q9MassDivBeforeFinal);
        R.q9SafetyActiveCellsFinal = q9Active;
        R.q9SafetyExcludedCellsFinal = get_last(T, 'q9SafetyExcludedCells');
        R.q9OpenBoundaryExcludedCellsFinal = get_last(T, 'q9OpenBoundaryExcludedCells');
        R.q9ImmersedHaloExcludedCellsFinal = get_last(T, 'q9ImmersedHaloExcludedCells');
        R.q9LowMassSuppressedCellsFinal = get_last(T, 'q9LowMassSuppressedCells');
        R.q9VelocityLimitedCellsFinal = q9Limited;
        R.q9VelocityLimitedFractionFinal = q9LimitedFrac;
        R.q9CorrectionVelocityRawRmsFinal = get_last(T, 'q9CorrectionVelocityRawRms');
        R.q9CorrectionVelocityRawMaxAbsFinal = get_last(T, 'q9CorrectionVelocityRawMaxAbs');
        R.q9CorrectionVelocityRmsFinal = get_last(T, 'q9CorrectionVelocityRms');
        R.q9CorrectionVelocityMaxAbsFinal = get_last(T, 'q9CorrectionVelocityMaxAbs');
        R.q9CorrectionVelocityLimiterFinal = get_last(T, 'q9CorrectionVelocityLimiter');
        R.q9MinCellMassForCorrectionFinal = get_last(T, 'q9MinCellMassForCorrection');

        R.virialKickAppliedFinal = get_last(T, 'virialKickApplied');
        R.virialDuOverThermalRmsFinal = get_last(T, 'virialDuOverThermalRms');
        R.virialMomentumResidualAfterFinal = get_last(T, 'virialMomentumResidualAfterCorrection');

        massOk = R.NpFirst == R.NpFinal && abs(R.totalMassFinal - R.totalMassFirst) < 1e-9;
        thermalOk = R.kBTOverTargetLate <= opt.maxKBTOverTarget;
        q6Effective = isnan(R.q6DivRatioFinal) || R.q6DivRatioFinal < 0.75;
        q9LimiterOk = true;
        q9BoundedOk = true;
        q9UsefulOk = true;
        if R.q9AppliedFinal == 1
            q9LimiterOk = R.q9CorrectionVelocityMaxAbsFinal <= R.q9CorrectionVelocityLimiterFinal * (1 + 1e-9);
            q9BoundedOk = R.q9SafetyExcludedCellsFinal > 0 && q9LimiterOk;
            q9UsefulOk = R.q9MassDivRatioFinal < 1.02 && R.q9VelocityLimitedFractionFinal <= opt.maxQ9LimitedFraction;
        end
        virialOk = true;
        if R.virialKickAppliedFinal == 1
            virialOk = abs(R.virialMomentumResidualAfterFinal) < 1e-10 && R.virialDuOverThermalRmsFinal < 0.05;
        end

        R.passSolverConvergence = (R.q6AppliedFinal ~= 1 || R.q6ConvergedFinal == 1) && ...
            (R.q9AppliedFinal ~= 1 || R.q9ConvergedFinal == 1);
        R.passBoundedSafety = massOk && thermalOk && q6Effective && q9BoundedOk && virialOk;
        R.passTunedQ9Target = R.passBoundedSafety && q9UsefulOk;
        R.status = string(local_status(R));

        rows = [rows; R]; %#ok<AGROW>
    end

    % Add relative thermal diagnostics using the Q6 reference.  The backward-step
    % reference itself heats above the nominal target because keepMean forcing,
    % walls and the immersed rectangle inject/dissipate energy.  For Q9 tuning,
    % the incremental temperature relative to Q6 is more informative than the
    % absolute target ratio alone.
    q6Mask = rows.q9AppliedFinal ~= 1 & contains(rows.caseLabel, "q6");
    if any(q6Mask)
        q6KBTRef = rows.kBTMeanLate(find(q6Mask, 1, 'first'));
    else
        q6KBTRef = NaN;
    end
    rows.q6KBTReferenceLate = repmat(q6KBTRef, height(rows), 1);
    rows.q9KBTOverQ6Late = nan(height(rows), 1);
    rows.passRelativeThermal = false(height(rows), 1);
    for jj = 1:height(rows)
        if rows.q9AppliedFinal(jj) == 1 && isfinite(q6KBTRef) && q6KBTRef > 0
            rows.q9KBTOverQ6Late(jj) = rows.kBTMeanLate(jj) / q6KBTRef;
            rows.passRelativeThermal(jj) = rows.q9KBTOverQ6Late(jj) <= opt.maxQ9KBTOverQ6;
        else
            rows.passRelativeThermal(jj) = true;
        end
    end

    % Recompute the tuned target after the Q6-relative metric is available.
    for jj = 1:height(rows)
        if rows.q9AppliedFinal(jj) == 1
            q9Useful = rows.q9MassDivRatioFinal(jj) < 1.02 && ...
                rows.q9VelocityLimitedFractionFinal(jj) <= opt.maxQ9LimitedFraction && ...
                rows.passRelativeThermal(jj);
            rows.passTunedQ9Target(jj) = rows.passBoundedSafety(jj) && q9Useful;
            rows.status(jj) = string(local_status(rows(jj,:)));
        end
    end

    S = sortrows(rows, 'caseLabel');
    out = fullfile(runRoot, 'summary_q9_safety_smoke_0066.csv');
    writetable(S, out);
    disp(S);
    fprintf('[0066c] wrote %s\n', out);
end

function s = local_status(R)
    if R.passTunedQ9Target
        s = 'PASS_TUNED';
    elseif R.passBoundedSafety
        s = 'BOUNDED_NEEDS_TUNING';
    else
        s = 'FAIL_UNBOUNDED_OR_HOT';
    end
end

function x = get_last(T, name)
    if ismember(name, T.Properties.VariableNames)
        x = T.(name)(end);
    else
        x = NaN;
    end
end

function r = safe_ratio(a, b)
    if isfinite(a) && isfinite(b) && abs(b) > 0
        r = a / b;
    else
        r = NaN;
    end
end

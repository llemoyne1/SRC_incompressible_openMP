function suite = validate_backward_step_masked_structure_suite(varargin)
%VALIDATE_BACKWARD_STEP_MASKED_STRUCTURE_SUITE Compare classic, masked Q6 and masked Q9 step runs.
%
% The three cases remain periodic-x forced-channel tests with an immersed
% rectangular solid. They are meant to quantify the effect of masked Q6/Q9 on
% separated structures before adding true inlet/outlet boundary conditions.
%
% Example from repository root:
%   cd matlab
%   suite = validate_backward_step_masked_structure_suite();
%
% Example after running only Q6 and Q9:
%   suite = validate_backward_step_masked_structure_suite('runDirs', { ...
%       '../runs/backward_step_q6_mask_structure_96x48', ...
%       '../runs/backward_step_q9_mask_structure_96x48'});

    p = inputParser;
    addParameter(p, 'runDirs', local_default_run_dirs(), @(x) iscell(x) || isstring(x));
    addParameter(p, 'labels', {}, @(x) iscell(x) || isstring(x));
    addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'field', 'omega', @(s) ischar(s) || isstring(s));
    addParameter(p, 'averageLastFraction', 0.50, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
    addParameter(p, 'outputDir', '../runs/backward_step_masked_structure_suite_analysis', @(s) ischar(s) || isstring(s));
    parse(p, varargin{:});
    opt = p.Results;

    runDirs = cellstr(opt.runDirs);
    labels = cellstr(opt.labels);
    if isempty(labels)
        labels = local_default_labels(runDirs);
    end
    if numel(labels) ~= numel(runDirs)
        error('validate_backward_step_masked_structure_suite:labels', 'labels and runDirs must have the same length.');
    end

    outputDir = char(opt.outputDir);
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    cases = cell(numel(runDirs), 1);
    summaryRows = cell(numel(runDirs), 1);
    profileRows = cell(numel(runDirs), 1);

    for i = 1:numel(runDirs)
        if ~exist(runDirs{i}, 'dir')
            error('validate_backward_step_masked_structure_suite:missingRun', 'Missing run directory: %s', runDirs{i});
        end

        cases{i} = validate_backward_step_classic_long(runDirs{i}, ...
            'makePlots', false, ...
            'field', char(opt.field), ...
            'averageLastFraction', opt.averageLastFraction, ...
            'writeTables', true);

        base = cases{i}.table;
        diag = local_diagnostic_row(cases{i}, labels{i});
        summaryRows{i} = [diag base]; %#ok<AGROW>

        prof = cases{i}.lowerLayerProfile;
        prof.caseLabel = repmat(string(labels{i}), height(prof), 1);
        prof.runDir = repmat(string(runDirs{i}), height(prof), 1);
        profileRows{i} = prof; %#ok<AGROW>
    end

    suite = struct();
    suite.runDirs = runDirs;
    suite.labels = labels;
    suite.cases = cases;
    suite.summary = vertcat(summaryRows{:});
    suite.lowerLayerProfiles = vertcat(profileRows{:});

    writetable(suite.summary, fullfile(outputDir, 'backward_step_masked_structure_suite_summary.csv'));
    writetable(suite.lowerLayerProfiles, fullfile(outputDir, 'backward_step_masked_structure_suite_lower_profiles.csv'));

    disp(suite.summary);

    if opt.makePlots
        local_plot_suite(suite, char(opt.field), outputDir);
    end
end

function runDirs = local_default_run_dirs()
    runDirs = { ...
        '../runs/backward_step_classic_structure_96x48', ...
        '../runs/backward_step_q6_mask_structure_96x48', ...
        '../runs/backward_step_q9_mask_structure_96x48'};
end

function labels = local_default_labels(runDirs)
    labels = cell(size(runDirs));
    for i = 1:numel(runDirs)
        rd = char(runDirs{i});
        if contains(rd, 'q9')
            labels{i} = 'Q9-filtered masked';
        elseif contains(rd, 'q6')
            labels{i} = 'Q6 masked';
        elseif contains(rd, 'classic')
            labels{i} = 'classic';
        else
            [~, name] = fileparts(rd);
            labels{i} = name;
        end
    end
end

function row = local_diagnostic_row(out, label)
    params = out.params;
    method = local_param_string(params, 'method', 'classic');
    q9Enabled = local_param_bool(params, 'q9MassFluxProjectionEnable', false);
    maskEnabled = local_param_bool(params, 'projectionImmersedSolidMaskEnable', false);
    q6Strength = local_param_double(params, 'q6ProjectionStrength', local_param_double(params, 'projectionStrength', 1.0));
    q9Strength = local_param_double(params, 'q9MassFluxProjectionStrength', 0.0);
    q9Beta = local_param_double(params, 'q9DensityRelaxationBeta', 0.0);
    q9LowK = local_param_int(params, 'q9LowKMaxIndex', 0);
    q9LowPassPasses = local_param_int(params, 'q9EllipticLowPassPasses', 0);
    virialK = local_param_double(params, 'Kvirial', local_param_double(params, 'virialK', 0.0));
    virialBeta = local_param_double(params, 'virialBeta', 0.0);
    bodyAccelerationX = local_param_double(params, 'bodyAccelerationX', NaN);
    kBT = local_param_double(params, 'kBT', NaN);
    nSteps = local_param_int(params, 'nSteps', -1);

    late = out.lateSummary;

    q6StrengthRuntime = local_mean(late, 'q6ProjectionStrength');
    if isnan(q6StrengthRuntime)
        q6StrengthRuntime = q6Strength;
    end

    row = table(string(label), string(method), q9Enabled, maskEnabled, ...
        q6Strength, q6StrengthRuntime, q9Strength, q9Beta, q9LowK, q9LowPassPasses, virialK, virialBeta, bodyAccelerationX, kBT, nSteps, ...
        local_mean(late, 'q6Applied'), ...
        local_mean(late, 'q6Converged'), ...
        local_mean(late, 'q6Iterations'), ...
        local_mean(late, 'q6DivBeforeRms'), ...
        local_mean(late, 'q6DivAfterProjectedFluxRms'), ...
        local_mean(late, 'q6DivAfterCellVelocityRms'), ...
        local_mean(late, 'q6ImmersedSolidLeakProjectedFluxRms'), ...
        local_max(late, 'q6ImmersedSolidLeakProjectedFluxMaxAbs'), ...
        local_mean(late, 'q6CorrectionVelocityRms'), ...
        local_max(late, 'q6CorrectionVelocityMaxAbs'), ...
        local_mean(late, 'q9Applied'), ...
        local_mean(late, 'q9Converged'), ...
        local_mean(late, 'q9Iterations'), ...
        local_mean(late, 'q9MassFluxDivBeforeRms'), ...
        local_mean(late, 'q9MassFluxDivAfterRms'), ...
        local_mean(late, 'q9TargetDivergenceFilterRatio'), ...
        local_mean(late, 'q9DensityStdBefore'), ...
        local_mean(late, 'q9DensityStdAfterEstimate'), ...
        local_mean(late, 'q9DensityStdRatioEstimate'), ...
        local_mean(late, 'q9ImmersedSolidLeakMassFluxRms'), ...
        local_max(late, 'q9ImmersedSolidLeakMassFluxMaxAbs'), ...
        local_mean(late, 'q9CorrectionVelocityRms'), ...
        local_max(late, 'q9CorrectionVelocityMaxAbs'), ...
        local_mean(late, 'virialEnabled'), ...
        local_mean(late, 'virialKickApplied'), ...
        local_mean(late, 'virialRhoMean'), ...
        local_mean(late, 'virialRhoDefectRelRms'), ...
        local_mean(late, 'PtotMean'), ...
        local_mean(late, 'gradPdriveRms'), ...
        local_mean(late, 'virialDuAppliedRms'), ...
        local_max(late, 'virialDuAppliedMaxAbs'), ...
        local_mean(late, 'virialDuOverThermalRms'), ...
        'VariableNames', {'caseLabel','method','q9MassFluxProjectionEnable','projectionImmersedSolidMaskEnable', ...
        'q6ProjectionStrengthParam','q6ProjectionStrengthRuntimeLate', ...
        'q9MassFluxProjectionStrengthParam','q9DensityRelaxationBetaParam','q9LowKMaxIndexParam','q9EllipticLowPassPassesParam', ...
        'virialKParam','virialBetaParam', ...
        'bodyAccelerationXParam','kBTParam','nStepsParam', ...
        'q6AppliedLate','q6ConvergedFractionLate','q6IterationsMeanLate', ...
        'q6DivBeforeRmsLate','q6DivAfterProjectedFluxRmsLate','q6DivAfterCellVelocityRmsLate', ...
        'q6ImmersedSolidLeakProjectedFluxRmsLate','q6ImmersedSolidLeakProjectedFluxMaxAbsLate', ...
        'q6CorrectionVelocityRmsLate','q6CorrectionVelocityMaxAbsLate', ...
        'q9AppliedLate','q9ConvergedFractionLate','q9IterationsMeanLate', ...
        'q9MassFluxDivBeforeRmsLate','q9MassFluxDivAfterRmsLate','q9TargetDivergenceFilterRatioLate', ...
        'q9DensityStdBeforeLate','q9DensityStdAfterEstimateLate','q9DensityStdRatioEstimateLate', ...
        'q9ImmersedSolidLeakMassFluxRmsLate','q9ImmersedSolidLeakMassFluxMaxAbsLate', ...
        'q9CorrectionVelocityRmsLate','q9CorrectionVelocityMaxAbsLate', ...
        'virialEnabledLate','virialKickAppliedLate','virialRhoMeanLate','virialRhoDefectRelRmsLate', ...
        'PtotMeanLate','gradPdriveRmsLate','virialDuAppliedRmsLate','virialDuAppliedMaxAbsLate','virialDuOverThermalRmsLate'});
end

function value = local_mean(tbl, name)
    if ~istable(tbl) || ~ismember(name, tbl.Properties.VariableNames)
        value = NaN;
        return;
    end
    value = mean(tbl.(name), 'omitnan');
end

function value = local_max(tbl, name)
    if ~istable(tbl) || ~ismember(name, tbl.Properties.VariableNames)
        value = NaN;
        return;
    end
    value = max(tbl.(name), [], 'omitnan');
end

function value = local_param_string(params, key, defaultValue)
    value = defaultValue;
    if isstruct(params) && isfield(params, key)
        raw = params.(key);
        if isstring(raw) || ischar(raw)
            value = char(raw);
        end
    elseif isa(params, 'containers.Map') && isKey(params, key)
        raw = params(key);
        if isstring(raw) || ischar(raw)
            value = char(raw);
        end
    end
end

function value = local_param_bool(params, key, defaultValue)
    value = defaultValue;
    raw = [];
    found = false;
    if isstruct(params) && isfield(params, key)
        raw = params.(key); found = true;
    elseif isa(params, 'containers.Map') && isKey(params, key)
        raw = params(key); found = true;
    end
    if ~found
        return;
    end
    if islogical(raw) || isnumeric(raw)
        value = logical(raw);
    else
        s = lower(strtrim(char(raw)));
        value = any(strcmp(s, {'1','true','yes','on'}));
    end
end

function local_plot_suite(suite, fieldName, outputDir)
    n = numel(suite.cases);
    labels = suite.labels;

    fig1 = figure('Name', 'Backward step masked Q6/Q9 suite: mean fields');
    tiledlayout(n, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:n
        out = suite.cases{i};
        fields = out.meanFields;
        params = out.params;
        xMin = local_param_double(params, 'immersedSolidXMin', 0.25);
        xMax = local_param_double(params, 'immersedSolidXMax', 0.65);
        yMin = local_param_double(params, 'immersedSolidYMin', 0.0);
        yMax = local_param_double(params, 'immersedSolidYMax', 0.50);
        [Xc, Yc] = meshgrid(fields.xc, fields.yc);
        solidMask = Xc >= xMin & Xc <= xMax & Yc >= yMin & Yc <= yMax;

        nexttile;
        local_plot_field(fields, 'Ux', solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: mean Ux', labels{i}), 'Interpreter', 'none');
        hold on;
        contour(Xc, Yc, fields.Ux, [0 0], 'k-', 'LineWidth', 1.0);
        hold off;

        nexttile;
        local_plot_field(fields, fieldName, solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: %s', labels{i}, fieldName), 'Interpreter', 'none');

        nexttile;
        recirc = fields.Ux < 0 & ~solidMask & isfinite(fields.Ux);
        imagesc(fields.xc, fields.yc, double(recirc));
        axis xy equal tight;
        colorbar;
        hold on;
        rectangle('Position', [xMin, yMin, xMax-xMin, yMax-yMin], 'EdgeColor', 'k', 'LineWidth', 1.5);
        hold off;
        title(sprintf('%s: Ux < 0', labels{i}), 'Interpreter', 'none');
        xlabel('x'); ylabel('y');
    end
    saveas(fig1, fullfile(outputDir, 'backward_step_masked_structure_suite_fields.png'));

    fig2 = figure('Name', 'Backward step masked Q6/Q9 suite: lower-layer profiles');
    tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile; hold on;
    for i = 1:n
        prof = suite.cases{i}.lowerLayerProfile;
        plot(prof.x, prof.UxMeanLowerLayer, 'DisplayName', labels{i});
    end
    yline(0, 'k--'); grid on; legend('Location', 'best', 'Interpreter', 'none');
    xlabel('x'); ylabel('<Ux> lower layer'); title('Lower-layer mean streamwise velocity');

    nexttile; hold on;
    for i = 1:n
        prof = suite.cases{i}.lowerLayerProfile;
        plot(prof.x, prof.reversedFractionLowerLayer, 'DisplayName', labels{i});
    end
    grid on; legend('Location', 'best', 'Interpreter', 'none');
    xlabel('x'); ylabel('fraction Ux < 0'); title('Lower-layer reversed fraction');

    nexttile; hold on;
    for i = 1:n
        prof = suite.cases{i}.lowerLayerProfile;
        plot(prof.x, prof.omegaRmsLowerLayer, 'DisplayName', labels{i});
    end
    grid on; legend('Location', 'best', 'Interpreter', 'none');
    xlabel('x'); ylabel('omega RMS'); title('Lower-layer vorticity RMS');
    saveas(fig2, fullfile(outputDir, 'backward_step_masked_structure_suite_profiles.png'));

    local_plot_coherence_suite(suite, outputDir);
    local_plot_population_suite(suite, outputDir);
end

function local_plot_coherence_suite(suite, outputDir)
    n = numel(suite.cases);
    labels = suite.labels;
    fig = figure('Name', 'Backward step masked Q6/Q9 suite: coherence diagnostics');
    tiledlayout(n, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:n
        out = suite.cases{i};
        if ~isfield(out, 'coherenceFields')
            continue;
        end
        fields = out.meanFields;
        coh = out.coherenceFields;
        params = out.params;
        xMin = local_param_double(params, 'immersedSolidXMin', 0.25);
        xMax = local_param_double(params, 'immersedSolidXMax', 0.65);
        yMin = local_param_double(params, 'immersedSolidYMin', 0.0);
        yMax = local_param_double(params, 'immersedSolidYMax', 0.50);
        [Xc, Yc] = meshgrid(fields.xc, fields.yc);
        solidMask = Xc >= xMin & Xc <= xMax & Yc >= yMin & Yc <= yMax;

        nexttile;
        local_plot_field(fields, 'omega', solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: mean omega', labels{i}), 'Interpreter', 'none');

        nexttile;
        local_plot_coherence_field(fields, coh.omegaFluctRms, solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: omega fluct RMS', labels{i}), 'Interpreter', 'none');

        nexttile;
        local_plot_coherence_field(fields, coh.omegaCoherenceCellRatio, solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: |mean omega|/RMS', labels{i}), 'Interpreter', 'none');

        nexttile;
        local_plot_coherence_field(fields, coh.uxReverseProbability, solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: P(Ux<0)', labels{i}), 'Interpreter', 'none');
    end
    saveas(fig, fullfile(outputDir, 'backward_step_masked_structure_suite_coherence.png'));
end

function local_plot_population_suite(suite, outputDir)
    n = numel(suite.cases);
    labels = suite.labels;
    fig = figure('Name', 'Backward step masked Q6/Q9 suite: population diagnostics');
    tiledlayout(n, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:n
        out = suite.cases{i};
        if ~isfield(out, 'populationFields')
            continue;
        end
        fields = out.meanFields;
        pop = out.populationFields;
        params = out.params;
        xMin = local_param_double(params, 'immersedSolidXMin', 0.25);
        xMax = local_param_double(params, 'immersedSolidXMax', 0.65);
        yMin = local_param_double(params, 'immersedSolidYMin', 0.0);
        yMax = local_param_double(params, 'immersedSolidYMax', 0.50);
        [Xc, Yc] = meshgrid(fields.xc, fields.yc);
        solidMask = Xc >= xMin & Xc <= xMax & Yc >= yMin & Yc <= yMax;

        nexttile;
        local_plot_field(fields, 'N', solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: mean N', labels{i}), 'Interpreter', 'none');

        nexttile;
        nrel = fields.N ./ max(out.populationReferenceNFluid, eps);
        local_plot_data_field(fields, nrel, solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: N / <N>_fluid', labels{i}), 'Interpreter', 'none');

        nexttile;
        local_plot_data_field(fields, pop.NTemporalCv, solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: temporal CV(N)', labels{i}), 'Interpreter', 'none');

        nexttile;
        low = double(nrel < 0.5);
        low(~isfinite(nrel)) = NaN;
        local_plot_data_field(fields, low, solidMask, xMin, xMax, yMin, yMax);
        title(sprintf('%s: N < 0.5 ref', labels{i}), 'Interpreter', 'none');
    end
    saveas(fig, fullfile(outputDir, 'backward_step_masked_structure_suite_population.png'));
end

function local_plot_field(fields, name, solidMask, xMin, xMax, yMin, yMax)
    if ~isfield(fields, name)
        error('validate_backward_step_masked_structure_suite:badField', 'Unknown field: %s', name);
    end
    data = fields.(name);
    data(solidMask) = NaN;
    imagesc(fields.xc, fields.yc, data);
    axis xy equal tight;
    colorbar;
    hold on;
    rectangle('Position', [xMin, yMin, xMax-xMin, yMax-yMin], 'EdgeColor', 'k', 'LineWidth', 1.5);
    hold off;
    xlabel('x'); ylabel('y');
end


function local_plot_data_field(fields, data, solidMask, xMin, xMax, yMin, yMax)
    data(solidMask) = NaN;
    imagesc(fields.xc, fields.yc, data);
    axis xy equal tight;
    colorbar;
    hold on;
    rectangle('Position', [xMin, yMin, xMax-xMin, yMax-yMin], 'EdgeColor', 'k', 'LineWidth', 1.5);
    hold off;
    xlabel('x'); ylabel('y');
end

function local_plot_coherence_field(fields, data, solidMask, xMin, xMax, yMin, yMax)
    data(solidMask) = NaN;
    imagesc(fields.xc, fields.yc, data);
    axis xy equal tight;
    colorbar;
    hold on;
    rectangle('Position', [xMin, yMin, xMax-xMin, yMax-yMin], 'EdgeColor', 'k', 'LineWidth', 1.5);
    hold off;
    xlabel('x'); ylabel('y');
end

function value = local_param_int(params, key, defaultValue)
    value = defaultValue;
    raw = [];
    found = false;
    if isstruct(params) && isfield(params, key)
        raw = params.(key); found = true;
    elseif isa(params, 'containers.Map') && isKey(params, key)
        raw = params(key); found = true;
    end
    if ~found
        return;
    end
    if isnumeric(raw)
        value = round(double(raw));
    else
        parsed = str2double(char(raw));
        if isfinite(parsed)
            value = round(parsed);
        end
    end
end

function value = local_param_double(params, key, defaultValue)
    value = defaultValue;
    raw = [];
    found = false;
    if isstruct(params) && isfield(params, key)
        raw = params.(key); found = true;
    elseif isa(params, 'containers.Map') && isKey(params, key)
        raw = params(key); found = true;
    end
    if ~found
        return;
    end
    if isnumeric(raw)
        value = double(raw);
    else
        parsed = str2double(char(raw));
        if isfinite(parsed)
            value = parsed;
        end
    end
end

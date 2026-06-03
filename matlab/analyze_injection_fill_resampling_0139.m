function summary = analyze_injection_fill_resampling_0139(runRoot, varargin)
%ANALYZE_INJECTION_FILL_RESAMPLING_0139 Analyze inlet fill from inactive pool.
%
% Typical use from repository_root/matlab:
%   analyze_injection_fill_resampling_0139('../runs/injection_fill_resampling_0139');

    if nargin < 1 || isempty(runRoot)
        runRoot = '../runs/injection_fill_resampling_0139';
    end

    p = inputParser;
    addRequired(p, 'runRoot', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', 4.0, @isnumeric);
    addParameter(p, 'Ly', 1.0, @isnumeric);
    addParameter(p, 'Nx', 192, @isnumeric);
    addParameter(p, 'Ny', 48, @isnumeric);
    addParameter(p, 'gamma', 20, @isnumeric);
    addParameter(p, 'filledMassFraction', 0.25, @isnumeric);
    addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
    parse(p, runRoot, varargin{:});
    opt = p.Results;
    runRoot = char(opt.runRoot);

    cases = {'classic','q6','q6_resampling'};
    analysisDir = fullfile(runRoot, 'analysis');
    if ~exist(analysisDir, 'dir')
        mkdir(analysisDir);
    end

    rows = [];
    frameMetrics = struct();
    for ic = 1:numel(cases)
        c = cases{ic};
        caseDir = fullfile(runRoot, c);
        sumPath = fullfile(caseDir, 'summary_runtime.csv');
        if ~isfile(sumPath)
            warning('[0139] missing summary: %s', sumPath);
            continue;
        end
        T = readtable(sumPath);
        F = local_frame_metrics(caseDir, opt);
        frameMetrics.(c) = F;
        writetable(F, fullfile(analysisDir, sprintf('injection_fill_frame_metrics_0139_%s.csv', c)));

        last = height(T);
        finalF = local_last_frame(F);
        row = table();
        row.caseName = string(c);
        row.nSummaryRows = height(T);
        row.nFrames = height(F);
        row.finalTime = local_get_last(T, 'time', NaN);
        row.finalNFluid = local_get_last_any(T, {'nFluidParticles','fluidParticles','nFluid'}, NaN);
        row.finalNInactive = local_get_last_any(T, {'nInactiveParticles','inactiveParticles','nInactive'}, NaN);
        row.finalTotalMass = local_get_last_any(T, {'totalMass','resampTotalMass'}, NaN);
        row.finalMeanUx = local_get_last_any(T, {'meanUx','meanVelocityX','UxMean'}, NaN);
        row.finalStdN = local_get_last_any(T, {'stdN','resampStdN'}, NaN);
        row.finalResampMRelRms = local_get_last_any(T, {'resampMRelRms','MRelRms'}, NaN);
        row.maxResampMRelRms = local_get_max_any(T, {'resampMRelRms','MRelRms'}, NaN);
        row.finalQ6Div = local_get_last_any(T, {'q6DivAfterProjectedFluxRms','q6DivAfterCellVelocityRms'}, NaN);
        row.totalInletInserted = local_get_sum_any(T, {'inletParticlesInserted','inletNetParticleDelta'}, NaN);
        row.totalOutletDeleted = local_get_sum_any(T, {'outletParticlesDeleted'}, NaN);
        row.totalExtracted = local_get_sum_any(T, {'resampExtractionApplyOpsApplied','resampExtractionOps'}, 0);
        row.totalInserted = local_get_sum_any(T, {'resampInsertionApplyOpsApplied','resampInsertionOps'}, 0);
        row.totalLatentActivated = local_get_sum_any(T, {'resampLatentActivationApplied','resampLatentActivatedParticles'}, 0);
        row.totalRemapCells = local_get_sum_any(T, {'resampRemapCells','resampLocalRemapCells'}, 0);
        row.totalMassGuardAdjusted = local_get_sum_any(T, {'resampMassGuardParticlesAdjusted','resampMassGuardAdjustedParticles'}, 0);
        row.finalFilledCellFraction = finalF.filledCellFraction;
        row.finalWetCellFraction = finalF.wetCellFraction;
        row.finalFrontX = finalF.frontX;
        row.finalFrameMassRelRmsFilled = finalF.massRelRmsFilled;
        row.finalFrameMeanUxFilled = finalF.meanUxFilled;
        rows = [rows; row]; %#ok<AGROW>
    end

    summary = rows;
    if ~isempty(summary)
        writetable(summary, fullfile(analysisDir, 'injection_fill_summary_0139.csv'));
        disp('=== Injection/fill resampling 0139 summary ===');
        disp(summary);
    end

    if logical(opt.makePlots) && ~isempty(fieldnames(frameMetrics))
        local_plot_progress(frameMetrics, cases, analysisDir);
        local_plot_final_fields(frameMetrics, cases, analysisDir, opt);
    end
end

function F = local_frame_metrics(caseDir, opt)
    files = dir(fullfile(caseDir, 'state_step_*.smpcd'));
    if isempty(files)
        files = dir(fullfile(caseDir, '*.smpcd'));
    end
    if isempty(files)
        F = table();
        return;
    end
    [~, order] = sort({files.name});
    files = files(order);
    n = numel(files);
    F = table();
    targetM = double(opt.gamma);
    fillThreshold = double(opt.filledMassFraction) * targetM;
    for k = 1:n
        path = fullfile(files(k).folder, files(k).name);
        state = read_smpcd_state(path);
        B = bin_smpcd_state(state, 'Lx', opt.Lx, 'Ly', opt.Ly, 'Nx', opt.Nx, 'Ny', opt.Ny, ...
            'periodicX', false, 'periodicY', false, 'fluidOnly', true);
        filled = B.mass >= fillThreshold;
        wet = B.mass > 0;
        if any(wet(:))
            frontX = max(B.xc(any(wet, 1)));
            meanUxFilled = mean(B.Ux(wet), 'omitnan');
        else
            frontX = 0;
            meanUxFilled = NaN;
        end
        if any(filled(:))
            massRelRmsFilled = sqrt(mean(((B.mass(filled) - targetM) ./ targetM).^2));
        else
            massRelRmsFilled = NaN;
        end
        row = table();
        row.frameIndex = k;
        row.step = local_step_from_name(files(k).name);
        row.file = string(path);
        row.nFluid = sum(uint8(state.role(:)) == uint8(1));
        row.nInactive = sum(uint8(state.role(:)) == uint8(0));
        row.nLatent = sum(uint8(state.role(:)) == uint8(2));
        row.totalFluidMass = sum(double(state.mass(uint8(state.role(:)) == uint8(1))));
        row.wetCells = sum(wet(:));
        row.filledCells = sum(filled(:));
        row.wetCellFraction = row.wetCells / numel(B.mass);
        row.filledCellFraction = row.filledCells / numel(B.mass);
        row.frontX = frontX;
        row.massRelRmsFilled = massRelRmsFilled;
        row.meanUxFilled = meanUxFilled;
        row.maxMass = max(B.mass(:));
        row.minPositiveMass = min(B.mass(wet), [], 'omitnan');
        if isempty(row.minPositiveMass) || isinf(row.minPositiveMass)
            row.minPositiveMass = NaN;
        end
        F = [F; row]; %#ok<AGROW>
    end
end

function row = local_last_frame(F)
    if isempty(F)
        row = table();
        row.filledCellFraction = NaN;
        row.wetCellFraction = NaN;
        row.frontX = NaN;
        row.massRelRmsFilled = NaN;
        row.meanUxFilled = NaN;
    else
        row = F(end,:);
    end
end

function v = local_step_from_name(name)
    tok = regexp(name, 'state_step_(\d+)\.smpcd', 'tokens', 'once');
    if isempty(tok)
        v = NaN;
    else
        v = str2double(tok{1});
    end
end

function v = local_get_last(T, name, default)
    if ismember(name, T.Properties.VariableNames)
        x = T.(name);
        v = x(end);
    else
        v = default;
    end
end

function v = local_get_last_any(T, names, default)
    v = default;
    for i = 1:numel(names)
        if ismember(names{i}, T.Properties.VariableNames)
            x = T.(names{i});
            v = x(end);
            return;
        end
    end
end

function v = local_get_sum_any(T, names, default)
    v = default;
    for i = 1:numel(names)
        if ismember(names{i}, T.Properties.VariableNames)
            x = T.(names{i});
            if isempty(x)
                v = default;
            else
                v = sum(x, 'omitnan');
            end
            return;
        end
    end
end

function v = local_get_max_any(T, names, default)
    v = default;
    for i = 1:numel(names)
        if ismember(names{i}, T.Properties.VariableNames)
            x = T.(names{i});
            v = max(x, [], 'omitnan');
            return;
        end
    end
end

function local_plot_progress(frameMetrics, cases, analysisDir)
    fig = figure('Name', '0139 injection fill progress', 'Visible', 'on');
    tiledlayout(fig, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    nexttile; hold on; grid on;
    for i = 1:numel(cases)
        c = cases{i};
        if isfield(frameMetrics, c) && ~isempty(frameMetrics.(c))
            F = frameMetrics.(c);
            plot(F.step, F.wetCellFraction, 'DisplayName', c);
        end
    end
    ylabel('wet cell fraction'); legend('Interpreter','none','Location','best');

    nexttile; hold on; grid on;
    for i = 1:numel(cases)
        c = cases{i};
        if isfield(frameMetrics, c) && ~isempty(frameMetrics.(c))
            F = frameMetrics.(c);
            plot(F.step, F.frontX, 'DisplayName', c);
        end
    end
    ylabel('front x');

    nexttile; hold on; grid on;
    for i = 1:numel(cases)
        c = cases{i};
        if isfield(frameMetrics, c) && ~isempty(frameMetrics.(c))
            F = frameMetrics.(c);
            plot(F.step, F.nFluid, 'DisplayName', c);
        end
    end
    xlabel('step'); ylabel('active Fluid particles');
    exportgraphics(fig, fullfile(analysisDir, 'injection_fill_0139_progress.png'), 'Resolution', 160);
end

function local_plot_final_fields(frameMetrics, cases, analysisDir, opt)
    for i = 1:numel(cases)
        c = cases{i};
        if ~isfield(frameMetrics, c) || isempty(frameMetrics.(c))
            continue;
        end
        F = frameMetrics.(c);
        state = read_smpcd_state(char(F.file(end)));
        B = bin_smpcd_state(state, 'Lx', opt.Lx, 'Ly', opt.Ly, 'Nx', opt.Nx, 'Ny', opt.Ny, ...
            'periodicX', false, 'periodicY', false, 'fluidOnly', true);
        fig = figure('Name', sprintf('0139 injection fill final fields %s', c), 'Visible', 'on');
        tiledlayout(fig, 3, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
        local_image(B, B.speed, 'speed');
        local_image(B, B.Ux, 'Ux');
        local_image(B, B.Uy, 'Uy');
        local_image(B, B.omega, 'vorticity');
        local_image(B, B.mass, 'cell mass');
        local_image(B, B.N, 'cell population');
        exportgraphics(fig, fullfile(analysisDir, sprintf('injection_fill_0139_final_fields_%s.png', c)), 'Resolution', 160);
    end
end

function local_image(B, A, ttl)
    nexttile;
    imagesc(B.xc, B.yc, A);
    set(gca, 'YDir', 'normal');
    axis image tight;
    colorbar;
    title(ttl);
    xlabel('x'); ylabel('y');
end

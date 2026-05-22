function out = validate_immersed_circle_smoke(runDir, varargin)
%VALIDATE_IMMERSED_CIRCLE_SMOKE Basic checks for the analytic immersed circle.
%
% out = validate_immersed_circle_smoke('runs/immersed_circle_periodic_solid_thermal', ...
%     'circleCx',0.5,'circleCy',0.5,'circleR',0.12)
%
% This is a smoke validator, not a final wake diagnostic. It checks that
% particles are not left inside the analytic circle at dumped steps and that
% the runtime diagnostics report immersed-wall hits and virtual wall mass.

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'circleCx', [], @isnumeric);
    addParameter(p, 'circleCy', [], @isnumeric);
    addParameter(p, 'circleR', [], @isnumeric);
    addParameter(p, 'Lx', [], @isnumeric);
    addParameter(p, 'Ly', [], @isnumeric);
    addParameter(p, 'Nx', [], @isnumeric);
    addParameter(p, 'Ny', [], @isnumeric);
    addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'field', 'omega', @(s) ischar(s) || isstring(s));
    parse(p, runDir, varargin{:});
    opt = p.Results;
    runDir = char(opt.runDir);

    params = struct();
    paramsFile = fullfile(runDir, 'params_used.kv');
    if exist(paramsFile, 'file')
        params = parse_smpcd_kv(paramsFile);
    end

    Lx = local_get_param(opt.Lx, params, 'Lx', 1.0);
    Ly = local_get_param(opt.Ly, params, 'Ly', 1.0);
    Nx = local_get_param(opt.Nx, params, 'Nx', 32);
    Ny = local_get_param(opt.Ny, params, 'Ny', 32);
    cx = local_get_param(opt.circleCx, params, 'immersedCircleCx', 0.5);
    cy = local_get_param(opt.circleCy, params, 'immersedCircleCy', 0.5);
    R = local_get_param(opt.circleR, params, 'immersedCircleR', 0.12);

    summaryPath = fullfile(runDir, 'summary_runtime.csv');
    if ~exist(summaryPath, 'file')
        error('validate_immersed_circle_smoke:noSummary', 'Missing %s', summaryPath);
    end
    summary = readtable(summaryPath);

    frameTable = list_smpcd_dumps(runDir);
    if isempty(frameTable)
        error('validate_immersed_circle_smoke:noDumps', 'No .smpcd dumps found in %s', runDir);
    end

    nFrames = height(frameTable);
    maxInside = 0;
    finalFields = [];
    finalState = [];
    for k = 1:nFrames
        state = read_smpcd_state(frameTable.fullPath{k});
        r2 = (double(state.x(:)) - cx).^2 + (double(state.y(:)) - cy).^2;
        insideCount = nnz(r2 < (R * (1 - 1e-10))^2);
        maxInside = max(maxInside, insideCount);
        if k == nFrames
            finalState = state;
            finalFields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);
        end
    end

    totalImmersedHits = NaN;
    if ismember('hitsImmersed', summary.Properties.VariableNames)
        totalImmersedHits = sum(summary.hitsImmersed);
    end
    meanImmersedVirtualMass = NaN;
    if ismember('virtualMassImmersed', summary.Properties.VariableNames)
        meanImmersedVirtualMass = mean(summary.virtualMassImmersed, 'omitnan');
    end

    out = struct();
    out.runDir = runDir;
    out.summary = summary;
    out.frameTable = frameTable;
    out.nFrames = nFrames;
    out.maxParticlesInsideCircle = maxInside;
    out.totalImmersedHits = totalImmersedHits;
    out.meanImmersedVirtualMass = meanImmersedVirtualMass;
    out.kBTMean = mean(summary.kBTEstimate, 'omitnan');
    out.totalMassRelDrift = summary.totalMass(end) / summary.totalMass(1) - 1;

    out.table = table(string(runDir), nFrames, maxInside, totalImmersedHits, ...
        meanImmersedVirtualMass, out.kBTMean, out.totalMassRelDrift, ...
        'VariableNames', {'runDir','nFrames','maxParticlesInsideCircle', ...
        'totalImmersedHits','meanImmersedVirtualMass','kBTMean','totalMassRelDrift'});
    disp(out.table);

    if opt.makePlots
        figure('Name', 'Immersed circle smoke validation');
        tiledlayout(2,2);

        nexttile;
        plot(summary.time, summary.kBTEstimate, '-o');
        xlabel('time'); ylabel('kBT'); title('Thermal control'); grid on;

        nexttile;
        if ismember('hitsImmersed', summary.Properties.VariableNames)
            plot(summary.time, summary.hitsImmersed, '-o');
            ylabel('hitsImmersed');
        else
            plot(summary.time, zeros(height(summary),1));
            ylabel('hitsImmersed unavailable');
        end
        xlabel('time'); title('Immersed reflection hits'); grid on;

        nexttile;
        if ismember('virtualMassImmersed', summary.Properties.VariableNames)
            plot(summary.time, summary.virtualMassImmersed, '-o');
            ylabel('virtualMassImmersed');
        else
            plot(summary.time, zeros(height(summary),1));
            ylabel('virtualMassImmersed unavailable');
        end
        xlabel('time'); title('Immersed thermal coupling'); grid on;

        nexttile;
        plot_smpcd_frame(finalState, finalFields, 'field', opt.field, ...
            'showParticles', false, 'showVelocityVectors', false);
        hold on;
        th = linspace(0, 2*pi, 256);
        plot(cx + R*cos(th), cy + R*sin(th), 'k-', 'LineWidth', 1.5);
        title(sprintf('final %s with circle overlay', char(opt.field)), 'Interpreter', 'none');
        hold off;
    end
end

function v = local_get_param(userValue, params, key, defaultValue)
    if ~isempty(userValue)
        v = userValue;
        return;
    end
    if isstruct(params) && isfield(params, key)
        v = params.(key);
    else
        v = defaultValue;
    end
end

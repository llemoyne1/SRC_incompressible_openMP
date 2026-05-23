function out = validate_backward_step_smoke(runDir, varargin)
%VALIDATE_BACKWARD_STEP_SMOKE Basic diagnostics for the immersed rectangular step.
%
% This is a classic-compressible smoke validator. It checks that dumped real
% particles are not left inside the rectangular immersed solid and reports a
% simple downstream reversed-flow indicator.

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'field', 'omega', @(s) ischar(s) || isstring(s));
    parse(p, runDir, varargin{:});
    opt = p.Results;
    runDir = char(opt.runDir);

    paramsFile = fullfile(runDir, 'params_used.kv');
    if ~exist(paramsFile, 'file')
        error('validate_backward_step_smoke:noParams', 'Missing %s', paramsFile);
    end
    params = parse_smpcd_kv(paramsFile);

    Lx = local_get(params, 'Lx', 2.0);
    Ly = local_get(params, 'Ly', 1.0);
    Nx = local_get(params, 'Nx', 96);
    Ny = local_get(params, 'Ny', 48);
    xMin = local_get(params, 'immersedSolidXMin', 0.25);
    xMax = local_get(params, 'immersedSolidXMax', 0.65);
    yMin = local_get(params, 'immersedSolidYMin', 0.0);
    yMax = local_get(params, 'immersedSolidYMax', 0.50);
    vx = local_get(params, 'immersedSolidVx', 0.0);
    vy = local_get(params, 'immersedSolidVy', 0.0);

    summaryPath = fullfile(runDir, 'summary_runtime.csv');
    if ~exist(summaryPath, 'file')
        error('validate_backward_step_smoke:noSummary', 'Missing %s', summaryPath);
    end
    summary = readtable(summaryPath);

    frameTable = list_smpcd_dumps(runDir);
    if isempty(frameTable)
        error('validate_backward_step_smoke:noDumps', 'No .smpcd dumps found in %s', runDir);
    end

    maxInside = 0;
    finalState = [];
    finalFields = [];
    for k = 1:height(frameTable)
        state = read_smpcd_state(frameTable.fullPath{k});
        tk = frameTable.time(k);
        if isnan(tk), tk = 0.0; end
        xb0 = xMin + vx * tk; xb1 = xMax + vx * tk;
        yb0 = yMin + vy * tk; yb1 = yMax + vy * tk;
        inside = double(state.x(:)) >= xb0 & double(state.x(:)) <= xb1 & ...
                 double(state.y(:)) >= yb0 & double(state.y(:)) <= yb1;
        maxInside = max(maxInside, nnz(inside));
        if k == height(frameTable)
            finalState = state;
            finalFields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
                'periodicX', strcmp(local_get_string(params,'bcLeft','periodic'),'periodic') && strcmp(local_get_string(params,'bcRight','periodic'),'periodic'), ...
                'periodicY', strcmp(local_get_string(params,'bcBottom','periodic'),'periodic') && strcmp(local_get_string(params,'bcTop','periodic'),'periodic'));
        end
    end

    [Xc, Yc] = meshgrid(finalFields.xc, finalFields.yc);
    downstream = Xc > xMax & Xc < min(Lx, xMax + 0.75 * (xMax - xMin + Ly)) & Yc < min(Ly, yMax + 0.35 * Ly);
    uxDownstream = finalFields.Ux(downstream);
    reversed = uxDownstream < 0;

    out = struct();
    out.runDir = runDir;
    out.summary = summary;
    out.frameTable = frameTable;
    out.maxParticlesInsideRectangle = maxInside;
    out.totalImmersedHits = local_summary_sum(summary, 'hitsImmersed');
    out.meanImmersedVirtualMass = local_summary_mean(summary, 'virtualMassImmersed');
    out.kBTMean = mean(summary.kBTEstimate, 'omitnan');
    out.reversedUxMin = min(uxDownstream, [], 'omitnan');
    out.reversedUxFraction = mean(reversed, 'omitnan');
    out.table = table(string(runDir), height(frameTable), maxInside, out.totalImmersedHits, ...
        out.meanImmersedVirtualMass, out.kBTMean, out.reversedUxMin, out.reversedUxFraction, ...
        'VariableNames', {'runDir','nFrames','maxParticlesInsideRectangle', ...
        'totalImmersedHits','meanImmersedVirtualMass','kBTMean','minUxDownstream','reversedUxFraction'});
    disp(out.table);

    if opt.makePlots
        figure('Name', 'Backward-step immersed rectangle smoke');
        tiledlayout(2,2);

        nexttile;
        plot(summary.time, summary.kBTEstimate, '-o'); grid on;
        xlabel('time'); ylabel('kBT'); title('Thermal control');

        nexttile;
        if ismember('hitsImmersed', summary.Properties.VariableNames)
            plot(summary.time, summary.hitsImmersed, '-o'); ylabel('hitsImmersed');
        else
            plot(summary.time, zeros(height(summary),1)); ylabel('hitsImmersed unavailable');
        end
        grid on; xlabel('time'); title('Immersed wall hits');

        nexttile;
        plot_smpcd_frame(finalState, finalFields, 'field', opt.field, ...
            'showParticles', false, 'showVelocityVectors', false);
        hold on; local_draw_rectangle(xMin, xMax, yMin, yMax); hold off;
        title(sprintf('final %s', char(opt.field)), 'Interpreter', 'none');

        nexttile;
        plot_smpcd_frame(finalState, finalFields, 'field', 'Ux', ...
            'showParticles', false, 'showVelocityVectors', false);
        hold on; local_draw_rectangle(xMin, xMax, yMin, yMax); hold off;
        title('final Ux');
    end
end

function v = local_get(params, key, defaultValue)
    if isstruct(params) && isfield(params, key)
        v = params.(key);
    else
        v = defaultValue;
    end
end

function v = local_get_string(params, key, defaultValue)
    v = local_get(params, key, defaultValue);
    v = char(string(v));
end

function v = local_summary_sum(summary, name)
    if ismember(name, summary.Properties.VariableNames)
        v = sum(summary.(name), 'omitnan');
    else
        v = NaN;
    end
end

function v = local_summary_mean(summary, name)
    if ismember(name, summary.Properties.VariableNames)
        v = mean(summary.(name), 'omitnan');
    else
        v = NaN;
    end
end

function local_draw_rectangle(xMin, xMax, yMin, yMax)
    plot([xMin xMax xMax xMin xMin], [yMin yMin yMax yMax yMin], 'k-', 'LineWidth', 1.5);
end

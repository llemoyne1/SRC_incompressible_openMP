function out = validate_backward_step_classic_long(runDir, varargin)
%VALIDATE_BACKWARD_STEP_CLASSIC_LONG Time-averaged diagnostics for the rectangular step.
%
% This validator is for the classic-compressible periodic-x step case. It does
% not assume inlet/outlet boundary conditions and does not validate Q6/Q9. The
% aim is to quantify the immersed-solid treatment and the separated/reversed
% downstream region on averaged dumped fields.
%
% Example from repository root:
%   cd matlab
%   out = validate_backward_step_classic_long('../runs/backward_step_classic_long_96x48');

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'averageLastFraction', 0.50, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
    addParameter(p, 'field', 'omega', @(s) ischar(s) || isstring(s));
    addParameter(p, 'writeTables', true, @(x) islogical(x) || isnumeric(x));
    parse(p, runDir, varargin{:});
    opt = p.Results;
    runDir = char(opt.runDir);

    paramsFile = fullfile(runDir, 'params_used.kv');
    if ~exist(paramsFile, 'file')
        error('validate_backward_step_classic_long:noParams', 'Missing %s', paramsFile);
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
        error('validate_backward_step_classic_long:noSummary', 'Missing %s', summaryPath);
    end
    summary = readtable(summaryPath);

    frameTable = list_smpcd_dumps(runDir);
    if isempty(frameTable)
        error('validate_backward_step_classic_long:noDumps', 'No .smpcd dumps found in %s', runDir);
    end

    nFrames = height(frameTable);
    firstAverageFrame = max(1, floor((1.0 - opt.averageLastFraction) * nFrames) + 1);
    averageRows = firstAverageFrame:nFrames;

    periodicX = strcmp(local_get_string(params,'bcLeft','periodic'),'periodic') && ...
        strcmp(local_get_string(params,'bcRight','periodic'),'periodic');
    periodicY = strcmp(local_get_string(params,'bcBottom','periodic'),'periodic') && ...
        strcmp(local_get_string(params,'bcTop','periodic'),'periodic');

    maxInside = 0;
    meanFields = [];
    acc = local_empty_accumulator(Ny, Nx);
    templateFields = [];
    finalState = [];
    finalFields = [];

    for k = 1:nFrames
        state = read_smpcd_state(frameTable.fullPath{k});
        tk = frameTable.time(k);
        if isnan(tk), tk = 0.0; end
        xb0 = xMin + vx * tk; xb1 = xMax + vx * tk;
        yb0 = yMin + vy * tk; yb1 = yMax + vy * tk;
        inside = double(state.x(:)) >= xb0 & double(state.x(:)) <= xb1 & ...
                 double(state.y(:)) >= yb0 & double(state.y(:)) <= yb1;
        maxInside = max(maxInside, nnz(inside));

        if any(k == averageRows)
            fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
                'periodicX', periodicX, 'periodicY', periodicY);
            if isempty(templateFields)
                templateFields = fields;
            end
            acc = local_accumulate_fields(acc, fields);
        end

        if k == nFrames
            finalState = state;
            finalFields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
                'periodicX', periodicX, 'periodicY', periodicY);
        end
    end

    meanFields = local_finalize_mean_fields(templateFields, acc);

    [Xc, Yc] = meshgrid(meanFields.xc, meanFields.yc);
    insideSolid = Xc >= xMin & Xc <= xMax & Yc >= yMin & Yc <= yMax;
    fluidMask = ~insideSolid & isfinite(meanFields.Ux);
    downstreamMask = fluidMask & Xc > xMax & Xc < Lx & Yc > yMin & Yc < yMax;
    reversedMask = downstreamMask & meanFields.Ux < 0;

    lowerProfile = local_lower_layer_profile(meanFields, xMin, xMax, yMin, yMax, insideSolid);
    [reattachXProfile, reattachLengthProfile] = local_profile_reattachment(lowerProfile, xMax);

    if any(reversedMask(:))
        reattachXCell = max(Xc(reversedMask), [], 'omitnan');
        reattachLengthCell = reattachXCell - xMax;
    else
        reattachXCell = NaN;
        reattachLengthCell = NaN;
    end

    uxDownstream = meanFields.Ux(downstreamMask);
    omegaDownstream = meanFields.omega(downstreamMask);
    speedDownstream = meanFields.speed(downstreamMask);

    lateSummary = summary(summary.step >= frameTable.step(firstAverageFrame), :);
    if isempty(lateSummary)
        lateSummary = summary;
    end

    out = struct();
    out.runDir = runDir;
    out.params = params;
    out.summary = summary;
    out.lateSummary = lateSummary;
    out.frameTable = frameTable;
    out.averageRows = averageRows;
    out.meanFields = meanFields;
    out.finalState = finalState;
    out.finalFields = finalFields;
    out.lowerLayerProfile = lowerProfile;
    out.maxParticlesInsideRectangle = maxInside;
    out.totalImmersedHits = local_summary_sum(summary, 'hitsImmersed');
    out.meanImmersedVirtualMassLate = local_summary_mean(lateSummary, 'virtualMassImmersed');
    out.kBTMeanLate = local_summary_mean(lateSummary, 'kBTEstimate');
    out.kBTStdLate = local_summary_std(lateSummary, 'kBTEstimate');
    out.meanUxLate = local_summary_mean(lateSummary, 'meanVx');
    out.meanUyLate = local_summary_mean(lateSummary, 'meanVy');
    out.stdNLate = local_summary_mean(lateSummary, 'stdN');
    out.thermalVelocityLate = sqrt(max(out.kBTMeanLate, 0.0));
    out.meanUxOverThermalLate = out.meanUxLate / max(out.thermalVelocityLate, eps);
    out.minUxDownstream = min(uxDownstream, [], 'omitnan');
    out.meanUxDownstream = mean(uxDownstream, 'omitnan');
    out.meanUxDownstreamOverThermal = out.meanUxDownstream / max(out.thermalVelocityLate, eps);
    out.reversedUxFraction = mean(uxDownstream < 0, 'omitnan');
    out.omegaRmsDownstream = local_rms_omitnan(omegaDownstream);
    out.speedMeanDownstream = mean(speedDownstream, 'omitnan');
    out.reattachmentXCell = reattachXCell;
    out.reattachmentLengthCell = reattachLengthCell;
    out.reattachmentXProfile = reattachXProfile;
    out.reattachmentLengthProfile = reattachLengthProfile;

    out.table = table(string(runDir), nFrames, numel(averageRows), maxInside, ...
        out.totalImmersedHits, out.meanImmersedVirtualMassLate, out.kBTMeanLate, out.kBTStdLate, ...
        out.thermalVelocityLate, out.meanUxLate, out.meanUxOverThermalLate, out.meanUyLate, out.stdNLate, ...
        out.minUxDownstream, out.meanUxDownstream, out.meanUxDownstreamOverThermal, ...
        out.reversedUxFraction, out.omegaRmsDownstream, out.speedMeanDownstream, ...
        out.reattachmentXCell, out.reattachmentLengthCell, out.reattachmentXProfile, out.reattachmentLengthProfile, ...
        'VariableNames', {'runDir','nFrames','nAveragedFrames','maxParticlesInsideRectangle', ...
        'totalImmersedHits','meanImmersedVirtualMassLate','kBTMeanLate','kBTStdLate', ...
        'thermalVelocityLate','meanUxLate','meanUxOverThermalLate','meanUyLate','stdNLate', ...
        'minUxDownstream','meanUxDownstream','meanUxDownstreamOverThermal', ...
        'reversedUxFraction','omegaRmsDownstream','speedMeanDownstream', ...
        'reattachmentXCell','reattachmentLengthCell','reattachmentXProfile','reattachmentLengthProfile'});
    disp(out.table);

    if opt.writeTables
        writetable(out.table, fullfile(runDir, 'backward_step_classic_long_summary.csv'));
        writetable(lowerProfile, fullfile(runDir, 'backward_step_lower_layer_profile.csv'));
        fieldTable = smpcd_fields_to_table(meanFields, 'step', NaN, 'time', mean(frameTable.time(averageRows), 'omitnan'));
        writetable(fieldTable, fullfile(runDir, 'backward_step_mean_fields.csv'));
    end

    if opt.makePlots
        local_plot_validation(out, char(opt.field), xMin, xMax, yMin, yMax);
    end
end

function acc = local_empty_accumulator(Ny, Nx)
    z = zeros(Ny, Nx);
    acc.N = z; acc.mass = z; acc.rho = z;
    acc.Ux = z; acc.Uy = z; acc.speed = z; acc.omega = z;
    acc.kineticEnergy = z; acc.kBTcell = z;
    acc.countN = z; acc.countMass = z; acc.countRho = z;
    acc.countUx = z; acc.countUy = z; acc.countSpeed = z; acc.countOmega = z;
    acc.countKineticEnergy = z; acc.countKBTcell = z;
end

function acc = local_accumulate_fields(acc, fields)
    acc = local_accumulate_one(acc, fields, 'N');
    acc = local_accumulate_one(acc, fields, 'mass');
    acc = local_accumulate_one(acc, fields, 'rho');
    acc = local_accumulate_one(acc, fields, 'Ux');
    acc = local_accumulate_one(acc, fields, 'Uy');
    acc = local_accumulate_one(acc, fields, 'speed');
    acc = local_accumulate_one(acc, fields, 'omega');
    acc = local_accumulate_one(acc, fields, 'kineticEnergy');
    acc = local_accumulate_one(acc, fields, 'kBTcell');
end

function acc = local_accumulate_one(acc, fields, name)
    data = fields.(name);
    valid = isfinite(data);
    acc.(name)(valid) = acc.(name)(valid) + data(valid);
    countName = ['count' upper(name(1)) name(2:end)];
    acc.(countName)(valid) = acc.(countName)(valid) + 1;
end

function meanFields = local_finalize_mean_fields(templateFields, acc)
    if isempty(templateFields)
        error('validate_backward_step_classic_long:noAverageFields', 'No fields were accumulated.');
    end
    meanFields = templateFields;
    names = {'N','mass','rho','Ux','Uy','speed','omega','kineticEnergy','kBTcell'};
    for i = 1:numel(names)
        name = names{i};
        countName = ['count' upper(name(1)) name(2:end)];
        data = acc.(name) ./ max(acc.(countName), 1);
        data(acc.(countName) == 0) = NaN;
        meanFields.(name) = data;
    end
end

function profile = local_lower_layer_profile(fields, xMin, xMax, yMin, yMax, insideSolid)
    [Xc, Yc] = meshgrid(fields.xc, fields.yc);
    band = Yc > yMin & Yc < yMax & ~insideSolid & isfinite(fields.Ux);
    uxMean = nan(numel(fields.xc), 1);
    uyMean = nan(numel(fields.xc), 1);
    omegaRms = nan(numel(fields.xc), 1);
    reversedFraction = nan(numel(fields.xc), 1);
    nFluidCells = zeros(numel(fields.xc), 1);
    for ix = 1:numel(fields.xc)
        mask = band(:, ix);
        nFluidCells(ix) = nnz(mask);
        if any(mask)
            ux = fields.Ux(mask, ix);
            uy = fields.Uy(mask, ix);
            om = fields.omega(mask, ix);
            uxMean(ix) = mean(ux, 'omitnan');
            uyMean(ix) = mean(uy, 'omitnan');
            omegaRms(ix) = local_rms_omitnan(om);
            reversedFraction(ix) = mean(ux < 0, 'omitnan');
        end
    end
    downstream = fields.xc(:) > xMax;
    profile = table(fields.xc(:), uxMean, uyMean, omegaRms, reversedFraction, nFluidCells, downstream, ...
        'VariableNames', {'x','UxMeanLowerLayer','UyMeanLowerLayer','omegaRmsLowerLayer', ...
        'reversedFractionLowerLayer','nFluidCellsLowerLayer','isDownstreamOfStep'});
    profile.isInsideSolidStreamwise = fields.xc(:) >= xMin & fields.xc(:) <= xMax;
end

function [reattachX, reattachLength] = local_profile_reattachment(profile, xMax)
    reattachX = NaN;
    reattachLength = NaN;
    after = find(profile.x > xMax & isfinite(profile.UxMeanLowerLayer));
    if isempty(after)
        return;
    end
    neg = profile.UxMeanLowerLayer(after) < 0;
    firstNegLocal = find(neg, 1, 'first');
    if isempty(firstNegLocal)
        return;
    end
    tail = firstNegLocal:numel(after);
    firstPositiveAfterNeg = find(profile.UxMeanLowerLayer(after(tail)) >= 0, 1, 'first');
    if ~isempty(firstPositiveAfterNeg)
        idx = after(tail(firstPositiveAfterNeg));
        reattachX = profile.x(idx);
        reattachLength = reattachX - xMax;
    else
        idxNeg = after(find(neg, 1, 'last'));
        reattachX = profile.x(idxNeg);
        reattachLength = reattachX - xMax;
    end
end

function local_plot_validation(out, fieldName, xMin, xMax, yMin, yMax)
    figure('Name', 'Backward-step classic long validation');
    tiledlayout(2,2);

    ax = nexttile;
    plot(ax, out.summary.time, out.summary.kBTEstimate, '-'); grid(ax, 'on');
    xlabel(ax, 'time'); ylabel(ax, 'kBT'); title(ax, 'Thermal control');

    ax = nexttile;
    if ismember('hitsImmersed', out.summary.Properties.VariableNames)
        plot(ax, out.summary.time, out.summary.hitsImmersed, '-'); ylabel(ax, 'hitsImmersed');
    else
        plot(ax, out.summary.time, zeros(height(out.summary),1), '-'); ylabel(ax, 'hitsImmersed unavailable');
    end
    grid(ax, 'on'); xlabel(ax, 'time'); title(ax, 'Immersed wall hits');

    ax = nexttile;
    local_plot_binned_field(ax, out.meanFields, fieldName, xMin, xMax, yMin, yMax, true, true);
    title(ax, sprintf('mean %s + Ux=0/quiver', fieldName), 'Interpreter', 'none');

    ax = nexttile;
    plot(ax, out.lowerLayerProfile.x, out.lowerLayerProfile.UxMeanLowerLayer, '-');
    hold(ax, 'on');
    plot(ax, out.lowerLayerProfile.x, zeros(height(out.lowerLayerProfile),1), 'k--');
    xline(ax, xMax, 'k:');
    hold(ax, 'off');
    grid(ax, 'on'); xlabel(ax, 'x'); ylabel(ax, '<Ux> lower layer');
    title(ax, 'Lower-layer streamwise profile');

    figure('Name', 'Backward-step classic mean fields');
    tiledlayout(2,2);
    ax = nexttile; local_plot_binned_field(ax, out.meanFields, 'Ux', xMin, xMax, yMin, yMax, true, true); title(ax, 'mean Ux + Ux=0/quiver');
    ax = nexttile; local_plot_binned_field(ax, out.meanFields, 'Uy', xMin, xMax, yMin, yMax, true, false); title(ax, 'mean Uy + Ux=0');
    ax = nexttile; local_plot_binned_field(ax, out.meanFields, 'speed', xMin, xMax, yMin, yMax, true, true); title(ax, 'mean |U| + Ux=0/quiver');
    ax = nexttile; local_plot_recirculation_mask(ax, out.meanFields, xMin, xMax, yMin, yMax); title(ax, 'recirculation mask: Ux < 0');
end

function local_plot_binned_field(ax, fields, fieldName, xMin, xMax, yMin, yMax, overlayUxZero, overlayQuiver)
    if nargin < 8, overlayUxZero = false; end
    if nargin < 9, overlayQuiver = false; end

    data = local_extract_field(fields, fieldName);
    [Xc, Yc] = meshgrid(fields.xc, fields.yc);
    insideSolid = Xc >= xMin & Xc <= xMax & Yc >= yMin & Yc <= yMax;
    data(insideSolid) = NaN;

    imagesc(ax, fields.xc, fields.yc, data);
    set(ax, 'YDir', 'normal');
    axis(ax, 'equal');
    axis(ax, [0 fields.Lx 0 fields.Ly]);
    xlabel(ax, 'x');
    ylabel(ax, 'y');
    colorbar(ax);
    hold(ax, 'on');
    if overlayUxZero
        ux = fields.Ux;
        ux(insideSolid) = NaN;
        contour(ax, fields.xc, fields.yc, ux, [0 0], 'k', 'LineWidth', 1.2);
    end
    if overlayQuiver
        ux = fields.Ux; uy = fields.Uy;
        ux(insideSolid) = NaN; uy(insideSolid) = NaN;
        sx = max(1, round(numel(fields.xc) / 32));
        sy = max(1, round(numel(fields.yc) / 16));
        quiver(ax, Xc(1:sy:end,1:sx:end), Yc(1:sy:end,1:sx:end), ...
            ux(1:sy:end,1:sx:end), uy(1:sy:end,1:sx:end), 'k');
    end
    local_draw_rectangle(ax, xMin, xMax, yMin, yMax);
    hold(ax, 'off');
end

function local_plot_recirculation_mask(ax, fields, xMin, xMax, yMin, yMax)
    [Xc, Yc] = meshgrid(fields.xc, fields.yc);
    insideSolid = Xc >= xMin & Xc <= xMax & Yc >= yMin & Yc <= yMax;
    recirc = double(fields.Ux < 0);
    recirc(~isfinite(fields.Ux) | insideSolid) = NaN;
    imagesc(ax, fields.xc, fields.yc, recirc);
    set(ax, 'YDir', 'normal');
    axis(ax, 'equal');
    axis(ax, [0 fields.Lx 0 fields.Ly]);
    xlabel(ax, 'x');
    ylabel(ax, 'y');
    colorbar(ax);
    hold(ax, 'on');
    ux = fields.Ux; ux(insideSolid) = NaN;
    contour(ax, fields.xc, fields.yc, ux, [0 0], 'k', 'LineWidth', 1.2);
    local_draw_rectangle(ax, xMin, xMax, yMin, yMax);
    hold(ax, 'off');
end

function data = local_extract_field(fields, fieldName)
    switch lower(char(fieldName))
        case {'n','count','occupancy'}
            data = fields.N;
        case {'rho','density'}
            data = fields.rho;
        case {'ux'}
            data = fields.Ux;
        case {'uy'}
            data = fields.Uy;
        case {'speed','u'}
            data = fields.speed;
        case {'omega','vorticity'}
            data = fields.omega;
        case {'type','dominanttype'}
            data = fields.dominantType;
        otherwise
            error('validate_backward_step_classic_long:unknownField', 'Unknown field: %s', char(fieldName));
    end
end

function local_draw_rectangle(ax, xMin, xMax, yMin, yMax)
    patch(ax, [xMin xMax xMax xMin], [yMin yMin yMax yMax], [0.20 0.20 0.20], ...
        'EdgeColor', 'k', 'LineWidth', 1.0, 'FaceAlpha', 1.0);
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

function v = local_summary_std(summary, name)
    if ismember(name, summary.Properties.VariableNames)
        v = std(summary.(name), 'omitnan');
    else
        v = NaN;
    end
end

function v = local_rms_omitnan(x)
    x = x(isfinite(x));
    if isempty(x)
        v = NaN;
    else
        v = sqrt(mean(x.^2));
    end
end

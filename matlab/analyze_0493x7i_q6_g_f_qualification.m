function out = analyze_0493x7i_q6_g_f_qualification(rootDir, varargin)
%ANALYZE_0493X7I_Q6_G_F_QUALIFICATION Offline comparison of x7i run_ok dumps.
%
% out = analyze_0493x7i_q6_g_f_qualification( ...
%     'runs/0493x7i_q6_g_f_physical_qualification');
%
% The analysis is deliberately post-processing only.  It reuses the primitive
% .smpcd readers/binners and the existing Poiseuille profile analyzer.
%
% Cases / observables:
%   TG forced   : particle population at the four (1,1) vortex cores.
%   Poiseuille  : normalized velocity-profile shape and quadratic fit.
%   Bend pipe   : startup speed/coverage, including a far-field response.
%   Same-face IO: startup speed/coverage, including a far-field response.
%
% The expected mode directories are:
%   src, src-q6, src-q6-g-f
%
% Important: x7i bend-pipe defaults to a common filled Darcy state and starts
% from rest.  That is a controlled startup qualification variant of run_ok_bend_pipe.

p = inputParser;
p.FunctionName = 'analyze_0493x7i_q6_g_f_qualification';
addRequired(p, 'rootDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'modes', {'src','src-q6','src-q6-g-f'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'savePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'writeCsv', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'tgCoreRadiusCells', 2.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'tgTailFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'poiseuilleFitStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'poiseuilleExcludeWallCells', 2, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'startupTailFraction', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'startupFarXMinFraction', 0.75, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'startupSmoothRadiusCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'startupMovingThreshold10', 0.10, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'startupMovingThreshold25', 0.25, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'chiFluidThreshold', 0.5, @(x) isnumeric(x) && isscalar(x));
parse(p, rootDir, varargin{:});
opt = p.Results;

rootDir = char(rootDir);
if ~isfolder(rootDir)
    error('analyze_0493x7i:rootNotFound', 'Cannot find x7i root: %s', rootDir);
end
modes = cellstr(string(opt.modes));
analysisDir = fullfile(rootDir, 'analysis');
if ~isfolder(analysisDir)
    mkdir(analysisDir);
end

out = struct();
out.rootDir = rootDir;
out.modes = modes;
out.options = opt;

fprintf('\n=== 0493x7i Q6-g-f physical qualification ===\n');
fprintf('root: %s\n', rootDir);
fprintf('modes: %s\n\n', strjoin(modes, ', '));

tgRoot = fullfile(rootDir, 'tg');
poiseuilleRoot = fullfile(rootDir, 'poiseuille');
bendRoot = fullfile(rootDir, 'bend_pipe');
ioRoot = fullfile(rootDir, 'io_box');

if isfolder(tgRoot)
    out.tg = local_analyze_tg(tgRoot, modes, opt);
else
    out.tg = struct('metrics', table(), 'summary', table());
end

if isfolder(poiseuilleRoot)
    out.poiseuille = local_analyze_poiseuille(poiseuilleRoot, modes, opt);
else
    out.poiseuille = struct('summary', table(), 'profileComparison', table());
end

if isfolder(bendRoot)
    out.bendPipe = local_analyze_startup(bendRoot, modes, 'bend_pipe', opt);
else
    out.bendPipe = struct('metrics', table(), 'summary', table());
end

if isfolder(ioRoot)
    out.ioBox = local_analyze_startup(ioRoot, modes, 'io_box', opt);
else
    out.ioBox = struct('metrics', table(), 'summary', table());
end

if logical(opt.writeCsv)
    writetable(out.tg.metrics, fullfile(analysisDir, '0493x7i_tg_vortex_core_metrics.csv'));
    writetable(out.tg.summary, fullfile(analysisDir, '0493x7i_tg_vortex_core_summary.csv'));
    writetable(out.poiseuille.summary, fullfile(analysisDir, '0493x7i_poiseuille_summary.csv'));
    writetable(out.poiseuille.profileComparison, fullfile(analysisDir, '0493x7i_poiseuille_profiles.csv'));
    writetable(out.bendPipe.metrics, fullfile(analysisDir, '0493x7i_bend_pipe_startup_metrics.csv'));
    writetable(out.bendPipe.summary, fullfile(analysisDir, '0493x7i_bend_pipe_startup_summary.csv'));
    writetable(out.ioBox.metrics, fullfile(analysisDir, '0493x7i_io_box_startup_metrics.csv'));
    writetable(out.ioBox.summary, fullfile(analysisDir, '0493x7i_io_box_startup_summary.csv'));
end

if logical(opt.makePlots)
    figs = local_make_plots(out, analysisDir, logical(opt.savePlots));
    out.figures = figs;
else
    out.figures = gobjects(0);
end

fprintf('\n--- TG vortex-core population ---\n');
disp(out.tg.summary);
fprintf('\n--- Poiseuille profile ---\n');
disp(out.poiseuille.summary);
fprintf('\n--- Bend-pipe startup ---\n');
disp(out.bendPipe.summary);
fprintf('\n--- Same-face IO startup ---\n');
disp(out.ioBox.summary);
fprintf('===============================================\n\n');
end

function result = local_analyze_tg(caseRoot, modes, opt)
local_require_case_root(caseRoot, 'TG');
allMetrics = table();
summaryMode = strings(numel(modes),1);
summaryCore = nan(numel(modes),1);
summaryCoreStd = nan(numel(modes),1);
summaryCenter = nan(numel(modes),1);
summaryStdNRel = nan(numel(modes),1);
summaryAmp = nan(numel(modes),1);

for im = 1:numel(modes)
    mode = modes{im};
    runDir = local_output_dir(caseRoot, mode);
    params = local_load_params(runDir);
    tgEnable = local_get_bool(params, 'taylorGreenForcingEnable', false);
    tgAmp = local_get_num(params, 'taylorGreenForcingAmplitude', 0.0);
    if ~tgEnable || ~(tgAmp > 0)
        error('analyze_0493x7i:tgNotForced', ...
            'TG mode %s is not continuously forced (enable=%d amplitude=%g).', mode, tgEnable, tgAmp);
    end
    summaryAmp(im) = tgAmp;

    Lx = local_get_required_num(params, 'Lx');
    Ly = local_get_required_num(params, 'Ly');
    Nx = round(local_get_required_num(params, 'Nx'));
    Ny = round(local_get_required_num(params, 'Ny'));
    frames = list_smpcd_dumps(runDir);
    if height(frames) == 0
        error('analyze_0493x7i:noTGDumps', 'No TG dumps in %s', runDir);
    end

    n = height(frames);
    coreN = nan(n,4);
    centerCellN = nan(n,4);
    domainMeanN = nan(n,1);
    stdNRel = nan(n,1);
    coreRelDelta = nan(n,1);
    centerCellRelDelta = nan(n,1);
    coreAcrossStdRel = nan(n,1);

    centers = [0.25*Lx, 0.25*Ly; 0.75*Lx, 0.25*Ly; ...
               0.25*Lx, 0.75*Ly; 0.75*Lx, 0.75*Ly];

    for k = 1:n
        state = read_smpcd_state(char(frames.fullPath(k)));
        fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
            'periodicX', true, 'periodicY', true);
        N = double(fields.N);
        domainMeanN(k) = mean(N(:));
        stdNRel(k) = std(N(:), 0) / max(domainMeanN(k), eps);
        [X,Y] = meshgrid(fields.xc, fields.yc);
        radius = double(opt.tgCoreRadiusCells) * max(fields.dx, fields.dy);
        for c = 1:4
            dxp = abs(X - centers(c,1));
            dyp = abs(Y - centers(c,2));
            dxp = min(dxp, Lx - dxp);
            dyp = min(dyp, Ly - dyp);
            mask = hypot(dxp, dyp) <= radius;
            coreN(k,c) = mean(N(mask));
            [~,ix] = min(abs(fields.xc - centers(c,1)));
            [~,iy] = min(abs(fields.yc - centers(c,2)));
            centerCellN(k,c) = N(iy,ix);
        end
        coreMean = mean(coreN(k,:));
        centerMean = mean(centerCellN(k,:));
        coreRelDelta(k) = coreMean / max(domainMeanN(k), eps) - 1.0;
        centerCellRelDelta(k) = centerMean / max(domainMeanN(k), eps) - 1.0;
        coreAcrossStdRel(k) = std(coreN(k,:),0) / max(domainMeanN(k), eps);
    end

    modeCol = repmat(string(mode), n, 1);
    metric = table(modeCol, frames.step, frames.time, domainMeanN, ...
        coreN(:,1), coreN(:,2), coreN(:,3), coreN(:,4), ...
        mean(coreN,2), coreAcrossStdRel, coreRelDelta, ...
        mean(centerCellN,2), centerCellRelDelta, stdNRel, ...
        'VariableNames', {'mode','step','time','domainMeanN', ...
        'coreN1','coreN2','coreN3','coreN4','coreMeanN','coreAcrossStdRel', ...
        'coreRelDelta','centerCellMeanN','centerCellRelDelta','stdNRel'});
    if isempty(allMetrics)
        allMetrics = metric;
    else
        allMetrics = [allMetrics; metric]; %#ok<AGROW>
    end

    tail = local_tail_mask(n, opt.tgTailFraction);
    summaryMode(im) = string(mode);
    summaryCore(im) = mean(coreRelDelta(tail), 'omitnan');
    summaryCoreStd(im) = std(coreRelDelta(tail), 0, 'omitnan');
    summaryCenter(im) = mean(centerCellRelDelta(tail), 'omitnan');
    summaryStdNRel(im) = mean(stdNRel(tail), 'omitnan');
end

srcIndex = find(strcmp(modes, 'src'), 1, 'first');
q6Index = find(strcmp(modes, 'src-q6'), 1, 'first');
if isempty(srcIndex), srcIndex = 1; end
if isempty(q6Index), q6Index = srcIndex; end
coreDeltaMinusSrc = summaryCore - summaryCore(srcIndex);
coreDeltaMinusPreviousQ6 = summaryCore - summaryCore(q6Index);
summary = table(summaryMode, summaryAmp, summaryCore, summaryCoreStd, summaryCenter, summaryStdNRel, ...
    coreDeltaMinusSrc, coreDeltaMinusPreviousQ6, ...
    'VariableNames', {'mode','forcingAmplitude','coreRelDeltaTailMean','coreRelDeltaTailStd', ...
    'centerCellRelDeltaTailMean','stdNRelTailMean','coreRelDeltaMinusSrc','coreRelDeltaMinusPreviousQ6'});
result = struct('metrics', allMetrics, 'summary', summary);
end

function result = local_analyze_poiseuille(caseRoot, modes, opt)
local_require_case_root(caseRoot, 'Poiseuille');
nm = numel(modes);
runs = cell(nm,1);
modeCol = strings(nm,1);
fitR2 = nan(nm,1);
nuEff = nan(nm,1);
meanVelocity = nan(nm,1);
uMaxOverMean = nan(nm,1);
uCenterOverMean = nan(nm,1);
wallLowOverMean = nan(nm,1);
wallHighOverMean = nan(nm,1);
profileL2VsSrc = nan(nm,1);
profileLinfVsSrc = nan(nm,1);
profileL2VsPreviousQ6 = nan(nm,1);
profileLinfVsPreviousQ6 = nan(nm,1);

for im = 1:nm
    mode = modes{im};
    runDir = local_output_dir(caseRoot, mode);
    runs{im} = analyze_poiseuille_profile(runDir, ...
        'flowComponent', 'Ux', 'profileDirection', 'y', ...
        'fitStartFraction', opt.poiseuilleFitStartFraction, ...
        'excludeWallCells', opt.poiseuilleExcludeWallCells, ...
        'makePlots', false, 'plotConvergence', false, 'saveTables', false, 'saveMat', false);
    r = runs{im};
    modeCol(im) = string(mode);
    fitR2(im) = r.fit.r2;
    nuEff(im) = r.fit.nuEff;
    meanVelocity(im) = r.meanVelocity;
    uMaxOverMean(im) = r.uMax / local_nonzero(r.meanVelocity);
    uCenterOverMean(im) = r.uCenter / local_nonzero(r.meanVelocity);
    wallLowOverMean(im) = r.wallVelocityLow / local_nonzero(r.meanVelocity);
    wallHighOverMean(im) = r.wallVelocityHigh / local_nonzero(r.meanVelocity);
end

srcIndex = find(strcmp(modes, 'src'), 1, 'first');
q6Index = find(strcmp(modes, 'src-q6'), 1, 'first');
if isempty(srcIndex), srcIndex = 1; end
if isempty(q6Index), q6Index = srcIndex; end
ref = runs{srcIndex}.avgProfile / local_nonzero(runs{srcIndex}.meanVelocity);
refQ6 = runs{q6Index}.avgProfile / local_nonzero(runs{q6Index}.meanVelocity);
for im = 1:nm
    this = runs{im}.avgProfile / local_nonzero(runs{im}.meanVelocity);
    if numel(this) ~= numel(ref) || numel(this) ~= numel(refQ6)
        error('analyze_0493x7i:poiseuilleGridMismatch', 'Poiseuille profile grids differ across modes.');
    end
    d = this(:) - ref(:);
    dQ6 = this(:) - refQ6(:);
    profileL2VsSrc(im) = sqrt(mean(d.^2, 'omitnan')) / max(sqrt(mean(ref(:).^2, 'omitnan')), eps);
    profileLinfVsSrc(im) = max(abs(d), [], 'omitnan');
    profileL2VsPreviousQ6(im) = sqrt(mean(dQ6.^2, 'omitnan')) / max(sqrt(mean(refQ6(:).^2, 'omitnan')), eps);
    profileLinfVsPreviousQ6(im) = max(abs(dQ6), [], 'omitnan');
end

summary = table(modeCol, fitR2, nuEff, meanVelocity, uMaxOverMean, uCenterOverMean, ...
    wallLowOverMean, wallHighOverMean, profileL2VsSrc, profileLinfVsSrc, ...
    profileL2VsPreviousQ6, profileLinfVsPreviousQ6, ...
    'VariableNames', {'mode','fitR2','nuEff','meanVelocity','uMaxOverMean','uCenterOverMean', ...
    'wallLowOverMean','wallHighOverMean','normalizedProfileL2VsSrc','normalizedProfileLinfVsSrc', ...
    'normalizedProfileL2VsPreviousQ6','normalizedProfileLinfVsPreviousQ6'});

coord = runs{1}.coord(:);
profileComparison = table(coord, 'VariableNames', {'coord'});
for im = 1:nm
    name = matlab.lang.makeValidName(char(modeCol(im)));
    profileComparison.([name '_U']) = runs{im}.avgProfile(:);
    profileComparison.([name '_Unorm']) = runs{im}.avgProfile(:) / local_nonzero(runs{im}.meanVelocity);
    profileComparison.([name '_Ufit']) = runs{im}.fit.fitProfile(:);
end
result = struct('runs', {runs}, 'summary', summary, 'profileComparison', profileComparison);
end

function result = local_analyze_startup(caseRoot, modes, caseName, opt)
local_require_case_root(caseRoot, caseName);
allMetrics = table();
nm = numel(modes);
modeCol = strings(nm,1);
uRefSummary = nan(nm,1);
uCohTailOverRef = nan(nm,1);
uCohT50 = nan(nm,1);
uCohT90 = nan(nm,1);
farTailOverRef = nan(nm,1);
farT50 = nan(nm,1);
farT90 = nan(nm,1);
moving10Tail = nan(nm,1);
moving25Tail = nan(nm,1);
uCohT10Ref = nan(nm,1);
uCohT25Ref = nan(nm,1);
farT10Ref = nan(nm,1);
farT25Ref = nan(nm,1);

for im = 1:nm
    mode = modes{im};
    runDir = local_output_dir(caseRoot, mode);
    params = local_load_params(runDir);
    Lx = local_get_required_num(params, 'Lx');
    Ly = local_get_required_num(params, 'Ly');
    Nx = round(local_get_required_num(params, 'Nx'));
    Ny = round(local_get_required_num(params, 'Ny'));
    dt = local_get_required_num(params, 'dt');
    uRef = local_inlet_reference_speed(params);
    if ~(uRef > 0)
        error('analyze_0493x7i:noInletReference', 'Cannot infer a positive inlet speed in %s.', runDir);
    end

    geomMask = local_geometry_mask(params, runDir, Nx, Ny, opt.chiFluidThreshold);
    [paths, steps, times] = local_startup_frames(params, runDir, dt);
    n = numel(paths);
    uCohRms = nan(n,1);
    meanSpeed = nan(n,1);
    farMeanSpeed = nan(n,1);
    movingFraction10 = nan(n,1);
    movingFraction25 = nan(n,1);
    occupiedFraction = nan(n,1);

    for k = 1:n
        state = read_smpcd_state(char(paths(k)));
        fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...
            'periodicX', local_is_periodic_x(params), 'periodicY', local_is_periodic_y(params));
        Ux = double(fields.Ux); Uy = double(fields.Uy);
        Ux(~isfinite(Ux)) = 0; Uy(~isfinite(Uy)) = 0;
        [UxCoherent, UyCoherent, coherentMask] = local_smooth_velocity( ...
            Ux, Uy, geomMask, round(opt.startupSmoothRadiusCells));
        speed = hypot(UxCoherent, UyCoherent);
        [X,~] = meshgrid(fields.xc, fields.yc);
        farMask = coherentMask & X >= opt.startupFarXMinFraction * Lx;
        if ~any(coherentMask(:)) || ~any(farMask(:))
            error('analyze_0493x7i:emptyStartupMask', 'Empty geometric/far mask in %s.', runDir);
        end
        uCohRms(k) = sqrt(mean(UxCoherent(coherentMask).^2 + UyCoherent(coherentMask).^2));
        meanSpeed(k) = mean(speed(coherentMask));
        farMeanSpeed(k) = mean(speed(farMask));
        movingFraction10(k) = mean(speed(coherentMask) >= opt.startupMovingThreshold10 * uRef);
        movingFraction25(k) = mean(speed(coherentMask) >= opt.startupMovingThreshold25 * uRef);
        occupiedFraction(k) = mean(fields.N(geomMask) > 0);
    end

    [uResponse, t50, t90, uTail] = local_response(times, uCohRms, opt.startupTailFraction);
    [farResponse, ft50, ft90, fTail] = local_response(times, farMeanSpeed, opt.startupTailFraction);
    modeMetric = repmat(string(mode), n, 1);
    metric = table(modeMetric, steps, times, repmat(uRef,n,1), uCohRms, meanSpeed, farMeanSpeed, ...
        uCohRms/uRef, farMeanSpeed/uRef, movingFraction10, movingFraction25, occupiedFraction, ...
        uResponse, farResponse, ...
        'VariableNames', {'mode','step','time','uRef','uCohRms','meanSpeed','farMeanSpeed', ...
        'uCohOverRef','farMeanSpeedOverRef','movingFraction10','movingFraction25','occupiedFraction', ...
        'uCohResponse','farResponse'});
    if isempty(allMetrics)
        allMetrics = metric;
    else
        allMetrics = [allMetrics; metric]; %#ok<AGROW>
    end

    tail = local_tail_mask(n, opt.startupTailFraction);
    modeCol(im) = string(mode);
    uRefSummary(im) = uRef;
    uCohTailOverRef(im) = uTail / uRef;
    uCohT50(im) = t50;
    uCohT90(im) = t90;
    farTailOverRef(im) = fTail / uRef;
    farT50(im) = ft50;
    farT90(im) = ft90;
    moving10Tail(im) = mean(movingFraction10(tail), 'omitnan');
    moving25Tail(im) = mean(movingFraction25(tail), 'omitnan');
    uCohT10Ref(im) = local_first_signal_threshold(times, uCohRms/uRef, opt.startupMovingThreshold10);
    uCohT25Ref(im) = local_first_signal_threshold(times, uCohRms/uRef, opt.startupMovingThreshold25);
    farT10Ref(im) = local_first_signal_threshold(times, farMeanSpeed/uRef, opt.startupMovingThreshold10);
    farT25Ref(im) = local_first_signal_threshold(times, farMeanSpeed/uRef, opt.startupMovingThreshold25);
end

srcIndex = find(strcmp(modes, 'src'), 1, 'first');
q6Index = find(strcmp(modes, 'src-q6'), 1, 'first');
if isempty(srcIndex), srcIndex = 1; end
if isempty(q6Index), q6Index = srcIndex; end
uCohT50OverSrc = uCohT50 ./ local_nonzero(uCohT50(srcIndex));
farT50OverSrc = farT50 ./ local_nonzero(farT50(srcIndex));
uCohT50OverPreviousQ6 = uCohT50 ./ local_nonzero(uCohT50(q6Index));
farT50OverPreviousQ6 = farT50 ./ local_nonzero(farT50(q6Index));
summary = table(modeCol, uRefSummary, uCohTailOverRef, uCohT50, uCohT90, ...
    farTailOverRef, farT50, farT90, moving10Tail, moving25Tail, ...
    uCohT10Ref, uCohT25Ref, farT10Ref, farT25Ref, ...
    uCohT50OverSrc, farT50OverSrc, uCohT50OverPreviousQ6, farT50OverPreviousQ6, ...
    'VariableNames', {'mode','uRef','uCohTailOverRef','uCohT50','uCohT90', ...
    'farTailOverRef','farT50','farT90','movingFraction10Tail','movingFraction25Tail', ...
    'uCohT10Ref','uCohT25Ref','farT10Ref','farT25Ref', ...
    'uCohT50OverSrc','farT50OverSrc','uCohT50OverPreviousQ6','farT50OverPreviousQ6'});
result = struct('caseName', caseName, 'metrics', allMetrics, 'summary', summary);
end

function figs = local_make_plots(out, analysisDir, savePlots)
figs = gobjects(0);

f = figure('Name', '0493x7i TG vortex-core population'); hold on; grid on;
plotModes = unique(out.tg.metrics.mode, 'stable');
for km = 1:numel(plotModes)
    mode = plotModes(km);
    rows = out.tg.metrics.mode == mode;
    plot(out.tg.metrics.time(rows), out.tg.metrics.coreRelDelta(rows), '-o', 'DisplayName', char(mode));
end
xlabel('time'); ylabel('(N_{core}-<N>)/<N>'); title('Forced TG: vortex-core population'); legend('Location','best');
figs(end+1) = f; %#ok<AGROW>
if savePlots, saveas(f, fullfile(analysisDir, '0493x7i_tg_vortex_core_population.png')); end

f = figure('Name', '0493x7i Poiseuille normalized profiles'); hold on; grid on;
pc = out.poiseuille.profileComparison;
modeNames = out.poiseuille.summary.mode;
for k = 1:numel(modeNames)
    name = matlab.lang.makeValidName(char(modeNames(k)));
    plot(pc.coord, pc.([name '_Unorm']), 'DisplayName', char(modeNames(k)));
end
xlabel('y'); ylabel('U_x / <U_x>'); title('Poiseuille normalized mean profile'); legend('Location','best');
figs(end+1) = f; %#ok<AGROW>
if savePlots, saveas(f, fullfile(analysisDir, '0493x7i_poiseuille_normalized_profiles.png')); end

figs = [figs, local_plot_startup(out.bendPipe, analysisDir, savePlots), ...
              local_plot_startup(out.ioBox, analysisDir, savePlots)];
end

function figs = local_plot_startup(result, analysisDir, savePlots)
figs = gobjects(0);
caseName = result.caseName;

f = figure('Name', ['0493x7i ' caseName ' startup coherent speed']); hold on; grid on;
plotModes = unique(result.metrics.mode, 'stable');
for km = 1:numel(plotModes)
    mode = plotModes(km);
    rows = result.metrics.mode == mode;
    plot(result.metrics.time(rows), result.metrics.uCohOverRef(rows), '-o', 'DisplayName', char(mode));
end
xlabel('time'); ylabel('U_{coh,rms} / U_{inlet}'); title([strrep(caseName,'_',' ') ': global startup']); legend('Location','best');
figs(end+1) = f; %#ok<AGROW>
if savePlots, saveas(f, fullfile(analysisDir, ['0493x7i_' caseName '_startup_global.png'])); end

f = figure('Name', ['0493x7i ' caseName ' startup far field']); hold on; grid on;
plotModes = unique(result.metrics.mode, 'stable');
for km = 1:numel(plotModes)
    mode = plotModes(km);
    rows = result.metrics.mode == mode;
    plot(result.metrics.time(rows), result.metrics.farMeanSpeedOverRef(rows), '-o', 'DisplayName', char(mode));
end
xlabel('time'); ylabel('<|U|>_{far} / U_{inlet}'); title([strrep(caseName,'_',' ') ': far-field startup']); legend('Location','best');
figs(end+1) = f; %#ok<AGROW>
if savePlots, saveas(f, fullfile(analysisDir, ['0493x7i_' caseName '_startup_far.png'])); end
end


function [UxSmooth, UySmooth, validMask] = local_smooth_velocity(Ux, Uy, geomMask, radiusCells)
radiusCells = max(0, round(radiusCells));
if radiusCells == 0
    UxSmooth = Ux;
    UySmooth = Uy;
    validMask = geomMask;
    return;
end
width = 2*radiusCells + 1;
kernel = ones(width, width);
weight = conv2(double(geomMask), kernel, 'same');
UxSmooth = zeros(size(Ux));
UySmooth = zeros(size(Uy));
validMask = geomMask & weight > 0;
numX = conv2(Ux .* double(geomMask), kernel, 'same');
numY = conv2(Uy .* double(geomMask), kernel, 'same');
UxSmooth(validMask) = numX(validMask) ./ weight(validMask);
UySmooth(validMask) = numY(validMask) ./ weight(validMask);
end

function [paths, steps, times] = local_startup_frames(params, runDir, dt)
frames = list_smpcd_dumps(runDir);
paths = strings(0,1); steps = zeros(0,1); times = zeros(0,1);
if isfield(params, 'inputState')
    initPath = local_resolve_repo_path(char(string(params.inputState)), runDir);
    if isfile(initPath)
        paths(end+1,1) = string(initPath); %#ok<AGROW>
        steps(end+1,1) = 0; %#ok<AGROW>
        times(end+1,1) = 0; %#ok<AGROW>
    end
end
paths = [paths; frames.fullPath];
steps = [steps; frames.step];
times = [times; frames.time];
missing = ~isfinite(times);
times(missing) = steps(missing) * dt;
[steps, order] = sort(steps);
paths = paths(order); times = times(order);
[steps, ia] = unique(steps, 'stable');
paths = paths(ia); times = times(ia);
if isempty(paths)
    error('analyze_0493x7i:noStartupDumps', 'No initial state or dumps in %s.', runDir);
end
end

function mask = local_geometry_mask(params, runDir, Nx, Ny, threshold)
mask = true(Ny, Nx);
if ~local_get_bool(params, 'darcyBrinkmanEnable', false)
    return;
end
if ~isfield(params, 'darcyChiMode') || ~strcmpi(char(string(params.darcyChiMode)), 'file') || ~isfield(params, 'darcyChiFile')
    return;
end
chiPath = local_resolve_repo_path(char(string(params.darcyChiFile)), runDir);
if ~isfile(chiPath)
    warning('analyze_0493x7i:chiNotFound', 'Darcy chi file not found; using full grid: %s', chiPath);
    return;
end
fid = fopen(chiPath, 'rb', 'ieee-le');
if fid < 0, error('analyze_0493x7i:chiOpen', 'Cannot open chi file: %s', chiPath); end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
vals = fread(fid, Nx*Ny, 'single=>double');
if numel(vals) ~= Nx*Ny
    error('analyze_0493x7i:chiSize', 'Wrong chi size in %s.', chiPath);
end
chi = reshape(vals, [Nx, Ny]).';
mask = chi >= threshold;
end

function path = local_resolve_repo_path(rawPath, runDir)
if isfile(rawPath)
    path = rawPath;
    return;
end
repo = local_find_repo_root(runDir);
candidate = fullfile(repo, rawPath);
if isfile(candidate)
    path = candidate;
else
    path = rawPath;
end
end

function repo = local_find_repo_root(startDir)
repo = char(startDir);
for k = 1:12
    if isfolder(fullfile(repo, 'scripts'))
        return;
    end
    parent = fileparts(repo);
    if isempty(parent) || strcmp(parent, repo)
        break;
    end
    repo = parent;
end
repo = pwd;
end

function uRef = local_inlet_reference_speed(params)
uRef = 0.0;
fn = fieldnames(params);
for k = 1:numel(fn)
    if startsWith(fn{k}, 'openBoundarySegment') && ~strcmp(fn{k}, 'openBoundarySegmentCount') && ~strcmp(fn{k}, 'openBoundarySegmentsEnable')
        value = params.(fn{k});
        if ~(ischar(value) || isstring(value)), continue; end
        tok = strsplit(strtrim(char(string(value))));
        if numel(tok) >= 6 && strcmpi(tok{2}, 'inlet')
            ux = str2double(tok{5}); uy = str2double(tok{6});
            if isfinite(ux) && isfinite(uy)
                uRef = max(uRef, hypot(ux,uy));
            end
        end
    end
end
end

function [response, t50, t90, tailValue] = local_response(time, signal, tailFraction)
n = numel(signal);
tail = local_tail_mask(n, tailFraction);
tailValue = mean(signal(tail), 'omitnan');
baseline = signal(1);
den = tailValue - baseline;
response = nan(size(signal));
t50 = NaN; t90 = NaN;
if ~isfinite(den) || abs(den) <= 100*eps(max(1,abs(tailValue)))
    return;
end
response = (signal - baseline) / den;
t50 = local_first_crossing(time, response, 0.5);
t90 = local_first_crossing(time, response, 0.9);
end

function tCross = local_first_signal_threshold(time, signal, threshold)
tCross = NaN;
idx = find(isfinite(signal) & signal >= threshold, 1, 'first');
if isempty(idx), return; end
if idx == 1 || ~isfinite(signal(idx-1)) || signal(idx) == signal(idx-1)
    tCross = time(idx);
    return;
end
s0 = signal(idx-1); s1 = signal(idx);
t0 = time(idx-1); t1 = time(idx);
f = (threshold-s0)/(s1-s0);
f = min(1,max(0,f));
tCross = t0 + f*(t1-t0);
end

function tCross = local_first_crossing(time, response, threshold)
tCross = NaN;
idx = find(isfinite(response) & response >= threshold, 1, 'first');
if isempty(idx), return; end
if idx == 1 || ~isfinite(response(idx-1)) || response(idx) == response(idx-1)
    tCross = time(idx);
    return;
end
r0 = response(idx-1); r1 = response(idx);
t0 = time(idx-1); t1 = time(idx);
f = (threshold-r0)/(r1-r0);
f = min(1,max(0,f));
tCross = t0 + f*(t1-t0);
end

function tail = local_tail_mask(n, fraction)
count = max(1, ceil(n * double(fraction)));
tail = false(n,1);
tail(max(1,n-count+1):n) = true;
end

function runDir = local_output_dir(caseRoot, mode)
runDir = fullfile(caseRoot, mode, 'output');
if ~isfolder(runDir)
    error('analyze_0493x7i:runNotFound', 'Missing run output: %s', runDir);
end
end

function params = local_load_params(runDir)
paramsFile = fullfile(runDir, 'params_used.kv');
if ~isfile(paramsFile)
    error('analyze_0493x7i:paramsNotFound', 'Missing params_used.kv: %s', paramsFile);
end
params = parse_smpcd_kv(paramsFile);
end

function local_require_case_root(caseRoot, label)
if ~isfolder(caseRoot)
    error('analyze_0493x7i:caseNotFound', 'Missing %s case root: %s', label, caseRoot);
end
end

function value = local_get_required_num(params, name)
if ~isfield(params, name)
    error('analyze_0493x7i:missingParam', 'Missing required parameter %s.', name);
end
value = double(params.(name));
if ~isscalar(value) || ~isfinite(value)
    error('analyze_0493x7i:badParam', 'Parameter %s is not a finite scalar.', name);
end
end

function value = local_get_num(params, name, defaultValue)
if isfield(params, name) && isnumeric(params.(name)) && isscalar(params.(name)) && isfinite(params.(name))
    value = double(params.(name));
else
    value = defaultValue;
end
end

function value = local_get_bool(params, name, defaultValue)
if ~isfield(params, name)
    value = logical(defaultValue);
    return;
end
v = params.(name);
if islogical(v)
    value = v;
elseif isnumeric(v)
    value = v ~= 0;
else
    value = any(strcmpi(char(string(v)), {'true','yes','on','1'}));
end
end

function tf = local_is_periodic_x(params)
left = local_get_text(params, 'bcLeft', local_get_text(params, 'bcX', 'periodic'));
right = local_get_text(params, 'bcRight', local_get_text(params, 'bcX', 'periodic'));
tf = strcmpi(left,'periodic') && strcmpi(right,'periodic');
end

function tf = local_is_periodic_y(params)
bottom = local_get_text(params, 'bcBottom', local_get_text(params, 'bcY', 'periodic'));
top = local_get_text(params, 'bcTop', local_get_text(params, 'bcY', 'periodic'));
tf = strcmpi(bottom,'periodic') && strcmpi(top,'periodic');
end

function value = local_get_text(params, name, defaultValue)
if isfield(params, name)
    value = char(string(params.(name)));
else
    value = defaultValue;
end
end

function value = local_nonzero(value)
if ~isfinite(value) || abs(value) < eps
    value = NaN;
end
end

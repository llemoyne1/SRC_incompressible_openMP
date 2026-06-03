function R = analyze_open_channel_hard_inlet_budget_0071(varargin)
%ANALYZE_OPEN_CHANNEL_HARD_INLET_BUDGET_0071 Mass-budget diagnostics for the
%0071 straight-channel hard-inlet / passive-outlet test.
%
% The runtime part uses summary_runtime.csv. Boundary insertion/deletion
% counters are instantaneous at written summary rows, not cumulative unless
% summaryEvery=1. They are still useful for late-time sampled averages.
% The state part uses .smpcd dumps for spatial population/flux-proxy trends.

p = inputParser;
p.FunctionName = 'analyze_open_channel_hard_inlet_budget_0071';
addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
addParameter(p, 'runRoot', 'runs/open_channel_hard_inlet_budget_0071', @(s) ischar(s) || isstring(s));
addParameter(p, 'caseGlob', 'openchan_*', @(s) ischar(s) || isstring(s));
addParameter(p, 'lateFraction', 0.50, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

root = char(opts.root);
runRoot = char(opts.runRoot);
if ~exist(runRoot, 'dir')
    runRoot = fullfile(root, char(opts.runRoot));
end
if ~exist(runRoot, 'dir')
    error('Cannot find runRoot: %s', runRoot);
end

caseDirs = dir(fullfile(runRoot, char(opts.caseGlob)));
caseDirs = caseDirs([caseDirs.isdir]);
caseDirs = caseDirs(~startsWith({caseDirs.name}, '.'));
if isempty(caseDirs)
    error('No case directories matching %s in %s', char(opts.caseGlob), runRoot);
end

outDir = fullfile(runRoot, 'analysis_0071');
if ~exist(outDir, 'dir'); mkdir(outDir); end

runtimeAll = table();
stateAll = table();
summaryRows = table();
for c = 1:numel(caseDirs)
    caseLabel = caseDirs(c).name;
    caseDir = fullfile(caseDirs(c).folder, caseDirs(c).name);
    paramsPath = fullfile(caseDir, 'params_used.kv');
    runtimePath = fullfile(caseDir, 'summary_runtime.csv');
    if ~exist(paramsPath, 'file') || ~exist(runtimePath, 'file')
        warning('Skipping %s: missing params_used.kv or summary_runtime.csv', caseLabel);
        continue;
    end

    params = parse_smpcd_kv(paramsPath);
    runtime = readtable(runtimePath);
    if isempty(runtime)
        warning('Skipping %s: empty summary_runtime.csv', caseLabel);
        continue;
    end
    runtimeRows = local_runtime_rows(caseLabel, runtime, params);
    runtimeAll = [runtimeAll; runtimeRows]; %#ok<AGROW>

    frames = list_smpcd_dumps(caseDir);
    stateRows = table();
    if ~isempty(frames)
        idxList = 1:round(opts.frameStride):height(frames);
        if idxList(end) ~= height(frames)
            idxList = [idxList height(frames)]; %#ok<AGROW>
        end
        geom = local_geometry(params);
        for kk = 1:numel(idxList)
            idx = idxList(kk);
            state = read_smpcd_state(frames.fullPath{idx});
            fields = bin_smpcd_state(state, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', geom.Nx, 'Ny', geom.Ny);
            stateRows = [stateRows; local_state_budget_row(caseLabel, idx, frames.time(idx), fields, geom, params)]; %#ok<AGROW>
        end
        writetable(stateRows, fullfile(outDir, sprintf('state_budget_timeseries_%s.csv', caseLabel)));
        stateAll = [stateAll; stateRows]; %#ok<AGROW>
    else
        warning('No .smpcd dumps for %s; spatial state-budget diagnostics skipped.', caseLabel);
    end

    summaryRows = [summaryRows; local_summary_row(caseLabel, runtimeRows, stateRows, params, opts.lateFraction)]; %#ok<AGROW>
end

if ~isempty(runtimeAll)
    writetable(runtimeAll, fullfile(outDir, 'runtime_timeseries_all_cases.csv'));
end
if ~isempty(stateAll)
    writetable(stateAll, fullfile(outDir, 'state_budget_timeseries_all_cases.csv'));
end
if ~isempty(summaryRows)
    writetable(summaryRows, fullfile(outDir, 'open_channel_hard_inlet_budget_summary_0071.csv'));
    disp(summaryRows);
end
if opts.makePlots
    local_make_plots(runtimeAll, stateAll, outDir);
end

R = struct();
R.runRoot = runRoot;
R.outputDir = outDir;
R.runtimeTimeseries = runtimeAll;
R.stateTimeseries = stateAll;
R.summary = summaryRows;
end

function rows = local_runtime_rows(caseLabel, T, params)
dt = local_get_num(params, 'dt', NaN);
inserted = local_col(T, 'inletParticlesInserted');
reservoirDeleted = local_col(T, 'inletReservoirDeleted');
backflowDeleted = local_col(T, 'inletBackflowDeleted');
outletDeleted = local_col(T, 'outletParticlesDeleted');
source = inserted - reservoirDeleted - backflowDeleted;
net = source - outletDeleted;
ratio = local_safe_ratio(outletDeleted, source);

rows = table(repmat(string(caseLabel), height(T), 1), ...
    local_col(T,'step'), local_col(T,'time'), repmat(dt,height(T),1), ...
    local_col(T,'Np'), local_col(T,'totalMass'), local_col(T,'meanVx'), local_col(T,'meanVy'), ...
    local_col(T,'meanN'), local_col(T,'stdN'), local_col(T,'minN'), local_col(T,'maxN'), ...
    inserted, reservoirDeleted, backflowDeleted, outletDeleted, source, net, ratio, ...
    local_col(T,'q6Applied'), local_col(T,'q6DivAfterProjectedFluxRms'), local_col(T,'q6OpenBoundaryFluxBalance'), ...
    local_col(T,'q9Applied'), local_col(T,'q9DensityStdRatioEstimate'), local_col(T,'q9OpenBoundaryMassFluxBalance'), ...
    local_col(T,'q9LowMassSuppressedCells'), local_col(T,'q9LowMassRampedCells'), local_col(T,'q9MassFloorAppliedCells'), local_col(T,'q9VelocityLimitedCells'), ...
    local_col(T,'virialKickApplied'), local_col(T,'virialRhoDefectRelRms'), local_col(T,'PtotMean'), ...
    'VariableNames', {'caseLabel','step','time','dt','Np','totalMass','meanVx','meanVy', ...
    'meanN','stdN','minN','maxN','inletParticlesInserted','inletReservoirDeleted','inletBackflowDeleted','outletParticlesDeleted', ...
    'inletEffectiveSource','sampledBoundaryNet','sampledOutletOverSource', ...
    'q6Applied','q6DivAfterProjectedFluxRms','q6OpenBoundaryFluxBalance', ...
    'q9Applied','q9DensityStdRatioEstimate','q9OpenBoundaryMassFluxBalance', ...
    'q9LowMassSuppressedCells','q9LowMassRampedCells','q9MassFloorAppliedCells','q9VelocityLimitedCells', ...
    'virialKickApplied','virialRhoDefectRelRms','PtotMean'});
end

function row = local_state_budget_row(caseLabel, frameIndex, t, fields, geom, params)
N = local_field_or_zeros(fields, 'N', geom.Ny, geom.Nx);
Ux = local_field_or_zeros(fields, 'Ux', geom.Ny, geom.Nx);
Uy = local_field_or_zeros(fields, 'Uy', geom.Ny, geom.Nx);
fluid = true(geom.Ny, geom.Nx);
inletCells = max(1, round(local_get_num(params, 'inletReservoirCells', 3)));
outletCells = inletCells;
if isfield(params, 'outletDensityControlCells')
    outletCells = max(1, round(local_get_num(params, 'outletDensityControlCells', inletCells)));
end
inletBand = false(geom.Ny, geom.Nx); inletBand(:, 1:min(inletCells, geom.Nx)) = true;
outletBand = false(geom.Ny, geom.Nx); outletBand(:, max(1, geom.Nx-outletCells+1):geom.Nx) = true;
leftHalf = geom.X < 0.5 * geom.Lx;
rightHalf = ~leftHalf;
q9OpenCells = max(0, round(local_get_num(params, 'q9OpenBoundaryExclusionCells', 0)));
q9OpenExcluded = false(geom.Ny, geom.Nx);
if q9OpenCells > 0
    q9OpenExcluded(:, 1:min(q9OpenCells, geom.Nx)) = true;
    q9OpenExcluded(:, max(1, geom.Nx-q9OpenCells+1):geom.Nx) = true;
end
q9Active = fluid & ~q9OpenExcluded;

fluidN = N(fluid);
inletFluxProxy = sum(N(inletBand).*Ux(inletBand), 'omitnan');
outletFluxProxy = sum(N(outletBand).*Ux(outletBand), 'omitnan');
midFluxProxy = sum(N(:, max(1, round(0.5*geom.Nx))).*Ux(:, max(1, round(0.5*geom.Nx))), 'omitnan');

row = table(string(caseLabel), frameIndex, t, ...
    sum(fluidN,'omitnan'), mean(fluidN,'omitnan'), std(fluidN,0,'omitnan'), min(fluidN), max(fluidN), ...
    sum(N(inletBand),'omitnan'), mean(N(inletBand),'omitnan'), max([N(inletBand); 0]), ...
    sum(N(outletBand),'omitnan'), mean(N(outletBand),'omitnan'), max([N(outletBand); 0]), ...
    sum(N(leftHalf),'omitnan'), sum(N(rightHalf),'omitnan'), sum(N(q9Active),'omitnan'), ...
    inletFluxProxy, outletFluxProxy, midFluxProxy, local_scalar_ratio(outletFluxProxy, inletFluxProxy), ...
    mean(Ux(fluid),'omitnan'), mean(Uy(fluid),'omitnan'), sqrt(mean(Uy(fluid).^2,'omitnan')), ...
    'VariableNames', {'caseLabel','frameIndex','time','totalCellMass','meanCellN','stdCellN','minCellN','maxCellN', ...
    'inletBandMass','inletBandMeanN','inletBandMaxN','outletBandMass','outletBandMeanN','outletBandMaxN', ...
    'leftHalfMass','rightHalfMass','q9ActiveMass','inletFluxProxy','outletFluxProxy','midFluxProxy','outletOverInletFluxProxy', ...
    'meanUxCell','meanUyCell','uyRmsCell'});
end

function srow = local_summary_row(caseLabel, runtimeRows, stateRows, params, lateFraction)
lateRuntime = local_late(runtimeRows, lateFraction);
lateState = local_late(stateRows, lateFraction);
dt = local_get_num(params, 'dt', NaN);
Lx = local_get_num(params, 'Lx', NaN);
Uin = local_get_num(params, 'inletUxLeft', local_get_num(params, 'targetMeanUx', NaN));
Tadv = Lx / Uin;

timeFinal = runtimeRows.time(end);
NpFirst = runtimeRows.Np(1);
NpFinal = runtimeRows.Np(end);
NpSlopeAll = local_slope(runtimeRows.time, runtimeRows.Np);
NpSlopeLate = local_slope(lateRuntime.time, lateRuntime.Np);

stateFluxRatioLate = NaN;
stateMassSlopeLate = NaN;
stateStdNSlopeLate = NaN;
if ~isempty(lateState)
    stateFluxRatioLate = mean(lateState.outletOverInletFluxProxy, 'omitnan');
    stateMassSlopeLate = local_slope(lateState.time, lateState.totalCellMass);
    stateStdNSlopeLate = local_slope(lateState.time, lateState.stdCellN);
end

sourceLate = mean(lateRuntime.inletEffectiveSource, 'omitnan');
outletLate = mean(lateRuntime.outletParticlesDeleted, 'omitnan');
netLate = mean(lateRuntime.sampledBoundaryNet, 'omitnan');

srow = table(string(caseLabel), height(runtimeRows), timeFinal, timeFinal/Tadv, dt, ...
    NpFirst, NpFinal, NpFinal-NpFirst, NpSlopeAll, NpSlopeLate, NpSlopeLate*dt, ...
    mean(lateRuntime.meanVx,'omitnan'), mean(lateRuntime.stdN,'omitnan'), mean(lateRuntime.maxN,'omitnan'), ...
    sourceLate, outletLate, netLate, local_scalar_ratio(outletLate, sourceLate), ...
    mean(lateRuntime.q6DivAfterProjectedFluxRms,'omitnan'), mean(lateRuntime.q6OpenBoundaryFluxBalance,'omitnan'), ...
    mean(lateRuntime.q9DensityStdRatioEstimate,'omitnan'), mean(lateRuntime.q9OpenBoundaryMassFluxBalance,'omitnan'), ...
    mean(lateRuntime.q9LowMassRampedCells,'omitnan'), mean(lateRuntime.q9MassFloorAppliedCells,'omitnan'), mean(lateRuntime.q9VelocityLimitedCells,'omitnan'), ...
    stateFluxRatioLate, stateMassSlopeLate, stateStdNSlopeLate, ...
    'VariableNames', {'caseLabel','nRuntimeRows','timeFinal','advectiveTimesFinal','dt', ...
    'NpFirst','NpFinal','NpDelta','NpSlopeAll_perTime','NpSlopeLate_perTime','NpSlopeLate_perStep', ...
    'meanVxLate','stdNLate','maxNLate','inletEffectiveSourceMeanLate','outletDeletedMeanLate','sampledBoundaryNetMeanLate','outletOverSourceMeanLate', ...
    'q6DivAfterMeanLate','q6OpenFluxBalanceMeanLate','q9DensityStdRatioMeanLate','q9OpenMassFluxBalanceMeanLate', ...
    'q9LowMassRampedCellsMeanLate','q9MassFloorAppliedCellsMeanLate','q9VelocityLimitedCellsMeanLate', ...
    'stateOutletOverInletFluxProxyMeanLate','stateMassSlopeLate','stateStdNSlopeLate'});
end

function local_make_plots(runtimeAll, stateAll, outDir)
if ~isempty(runtimeAll)
    local_plot_by_case(runtimeAll, outDir, 'runtime_Np', 'Np');
    local_plot_by_case(runtimeAll, outDir, 'runtime_stdN', 'stdN');
    local_plot_by_case(runtimeAll, outDir, 'runtime_maxN', 'maxN');
    local_plot_by_case(runtimeAll, outDir, 'runtime_sampledBoundaryNet', 'sampledBoundaryNet');
    local_plot_by_case(runtimeAll, outDir, 'runtime_inletEffectiveSource', 'inletEffectiveSource');
    local_plot_by_case(runtimeAll, outDir, 'runtime_outletParticlesDeleted', 'outletParticlesDeleted');
    local_plot_by_case(runtimeAll, outDir, 'runtime_outletOverSource', 'sampledOutletOverSource');
end
if ~isempty(stateAll)
    local_plot_by_case(stateAll, outDir, 'state_totalCellMass', 'totalCellMass');
    local_plot_by_case(stateAll, outDir, 'state_stdCellN', 'stdCellN');
    local_plot_by_case(stateAll, outDir, 'state_maxCellN', 'maxCellN');
    local_plot_by_case(stateAll, outDir, 'state_fluxProxyRatio', 'outletOverInletFluxProxy');
    local_plot_by_case(stateAll, outDir, 'state_inletFluxProxy', 'inletFluxProxy');
    local_plot_by_case(stateAll, outDir, 'state_outletFluxProxy', 'outletFluxProxy');
end
end

function local_plot_by_case(T, outDir, baseName, fieldName)
if ~ismember(fieldName, T.Properties.VariableNames); return; end
labels = unique(T.caseLabel, 'stable');
fig = figure('Visible','on','Color','w'); hold on;
for i = 1:numel(labels)
    sel = T.caseLabel == labels(i);
    plot(T.time(sel), T.(fieldName)(sel), '-o', 'DisplayName', char(labels(i)));
end
grid on; xlabel('time'); ylabel(fieldName, 'Interpreter','none');
legend('Interpreter','none','Location','best');
title(sprintf('0071 open channel hard inlet: %s', fieldName), 'Interpreter','none');
saveas(fig, fullfile(outDir, sprintf('plot_%s.png', baseName)));
%close(fig);
end

function geom = local_geometry(params)
geom.Nx = local_get_num(params, 'Nx', NaN);
geom.Ny = local_get_num(params, 'Ny', NaN);
geom.Lx = local_get_num(params, 'Lx', NaN);
geom.Ly = local_get_num(params, 'Ly', NaN);
geom.dx = geom.Lx / geom.Nx;
geom.dy = geom.Ly / geom.Ny;
geom.x = ((0:geom.Nx-1) + 0.5) * geom.dx;
geom.y = ((0:geom.Ny-1) + 0.5) * geom.dy;
[geom.X, geom.Y] = meshgrid(geom.x, geom.y);
end

function Tlate = local_late(T, frac)
if isempty(T)
    Tlate = T;
    return;
end
t0 = T.time(1);
t1 = T.time(end);
cut = t1 - frac * (t1 - t0);
Tlate = T(T.time >= cut, :);
if isempty(Tlate); Tlate = T(end,:); end
end

function a = local_slope(t, y)
if numel(t) < 2 || all(~isfinite(y))
    a = NaN;
    return;
end
ok = isfinite(t) & isfinite(y);
if nnz(ok) < 2
    a = NaN;
else
    p = polyfit(t(ok), y(ok), 1);
    a = p(1);
end
end

function v = local_col(T, name)
if ismember(name, T.Properties.VariableNames)
    v = T.(name);
else
    v = NaN(height(T),1);
end
end

function r = local_safe_ratio(a, b)
r = NaN(size(a));
ok = isfinite(a) & isfinite(b) & abs(b) > 0;
r(ok) = a(ok) ./ b(ok);
end

function r = local_scalar_ratio(a, b)
if isfinite(a) && isfinite(b) && abs(b) > 0
    r = a / b;
else
    r = NaN;
end
end

function A = local_field_or_zeros(fields, name, ny, nx)
if isfield(fields, name)
    A = fields.(name);
elseif strcmp(name, 'N') && isfield(fields, 'mass')
    A = fields.mass;
else
    A = zeros(ny, nx);
end
end

function v = local_get_num(params, key, defaultVal)
v = defaultVal;
if isfield(params, key)
    tmp = str2double(string(params.(key)));
    if ~isnan(tmp); v = tmp; end
end
end

function R = analyze_backward_step_hard_inlet_budget_0072(varargin)
%ANALYZE_BACKWARD_STEP_HARD_INLET_BUDGET_0072 Zone mass-budget diagnostics for 48x24 hard-inlet backstep runs.
%
% The diagnostics are deliberately kinematic/discrete: flux proxies are sums of
% N*U over diagnostic bands/cuts. They are not a replacement for exact face-flux
% accounting in C++, but they are sufficient to identify where mass accumulates
% and whether the outlet removes enough particles relative to the hard inlet.

p = inputParser;
p.FunctionName = 'analyze_backward_step_hard_inlet_budget_0072';
addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
addParameter(p, 'runRoot', 'runs/backward_step_hard_inlet_budget_0072', @(s) ischar(s) || isstring(s));
addParameter(p, 'caseGlob', 'backstep_*', @(s) ischar(s) || isstring(s));
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'frontBandCells', 4, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'lateFraction', 0.50, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
parse(p, varargin{:});
opts = p.Results;

root = char(opts.root);
runRoot = fullfile(root, char(opts.runRoot));
if ~exist(runRoot, 'dir')
    error('Cannot find runRoot: %s', runRoot);
end

caseDirs = dir(fullfile(runRoot, char(opts.caseGlob)));
caseDirs = caseDirs([caseDirs.isdir]);
caseDirs = caseDirs(~startsWith({caseDirs.name}, '.'));
if isempty(caseDirs)
    error('No case directories matching %s in %s', char(opts.caseGlob), runRoot);
end

outDir = fullfile(runRoot, 'analysis_0072');
if ~exist(outDir, 'dir'); mkdir(outDir); end

allRows = table();
summaryRows = table();
for c = 1:numel(caseDirs)
    caseLabel = caseDirs(c).name;
    caseDir = fullfile(caseDirs(c).folder, caseDirs(c).name);
    paramsPath = fullfile(caseDir, 'params_used.kv');
    if ~exist(paramsPath, 'file')
        warning('Skipping %s: missing params_used.kv', caseLabel);
        continue;
    end
    params = parse_smpcd_kv(paramsPath);
    frames = list_smpcd_dumps(caseDir);
    if isempty(frames)
        warning('Skipping %s: no .smpcd dumps', caseLabel);
        continue;
    end
    idxList = 1:round(opts.frameStride):height(frames);
    if idxList(end) ~= height(frames)
        idxList = [idxList height(frames)]; %#ok<AGROW>
    end

    geom = local_geometry(params);
    rows = table();
    for kk = 1:numel(idxList)
        idx = idxList(kk);
        state = read_smpcd_state(frames.fullPath{idx});
        fields = bin_smpcd_state(state, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', geom.Nx, 'Ny', geom.Ny);
        masks = local_masks(fields, geom, params, opts.frontBandCells);
        row = local_budget_row(caseLabel, idx, frames.time(idx), fields, masks);
        rows = [rows; row]; %#ok<AGROW>
    end

    writetable(rows, fullfile(outDir, sprintf('mass_budget_timeseries_%s.csv', caseLabel)));
    allRows = [allRows; rows]; %#ok<AGROW>
    summaryRows = [summaryRows; local_summary_row(caseLabel, rows, opts.lateFraction)]; %#ok<AGROW>
end

if ~isempty(allRows)
    writetable(allRows, fullfile(outDir, 'mass_budget_timeseries_all_cases.csv'));
end
if ~isempty(summaryRows)
    writetable(summaryRows, fullfile(outDir, 'mass_budget_summary_0072.csv'));
end

if opts.makePlots && ~isempty(allRows)
    local_make_plots(allRows, outDir);
end

R = struct();
R.runRoot = runRoot;
R.outputDir = outDir;
R.timeseries = allRows;
R.summary = summaryRows;
end

function geom = local_geometry(params)
geom.Nx = local_get_num(params, 'Nx', NaN);
geom.Ny = local_get_num(params, 'Ny', NaN);
geom.Lx = local_get_num(params, 'Lx', NaN);
geom.Ly = local_get_num(params, 'Ly', NaN);
if any(isnan([geom.Nx geom.Ny geom.Lx geom.Ly]))
    error('Missing Nx/Ny/Lx/Ly in params_used.kv');
end
geom.dx = geom.Lx / geom.Nx;
geom.dy = geom.Ly / geom.Ny;
geom.x = ((0:geom.Nx-1) + 0.5) * geom.dx;
geom.y = ((0:geom.Ny-1) + 0.5) * geom.dy;
[geom.X, geom.Y] = meshgrid(geom.x, geom.y);
geom.inletCells = max(0, round(local_get_num(params, 'inletReservoirCells', 5)));
geom.outletCells = max(0, round(local_get_num(params, 'outletDensityControlCells', geom.inletCells)));
geom.sx0 = local_get_num(params, 'immersedSolidXMin', 0.25);
geom.sx1 = local_get_num(params, 'immersedSolidXMax', 0.65);
geom.sy0 = local_get_num(params, 'immersedSolidYMin', 0.0);
geom.sy1 = local_get_num(params, 'immersedSolidYMax', 0.50);
end

function masks = local_masks(fields, geom, params, frontBandCells)
N = local_field_or_zeros(fields, 'N', geom.Ny, geom.Nx);
solid = geom.X >= geom.sx0 & geom.X <= geom.sx1 & geom.Y >= geom.sy0 & geom.Y <= geom.sy1;
fluid = ~solid;
inletBand = geom.X <= geom.inletCells * geom.dx;
outletBand = geom.X >= geom.Lx - geom.outletCells * geom.dx;
frontBandWidth = max(1, round(frontBandCells)) * geom.dx;
frontBand = geom.X >= geom.sx0 - frontBandWidth & geom.X < geom.sx0 & geom.Y < geom.sy1 & fluid;
upstreamLower = geom.X < geom.sx0 & geom.Y < geom.sy1 & fluid;
upstreamUpper = geom.X < geom.sx0 & geom.Y >= geom.sy1 & fluid;
aboveObstacle = geom.X >= geom.sx0 & geom.X <= geom.sx1 & geom.Y >= geom.sy1 & fluid;
downstreamLower = geom.X > geom.sx1 & geom.Y < geom.sy1 & fluid;
downstreamUpper = geom.X > geom.sx1 & geom.Y >= geom.sy1 & fluid;

q9OpenCells = max(0, round(local_get_num(params, 'q9OpenBoundaryExclusionCells', 0)));
q9HaloCells = max(0, round(local_get_num(params, 'q9ImmersedSolidHaloCells', 0)));
q9OpenExcluded = false(size(solid));
if q9OpenCells > 0
    q9OpenExcluded(:, 1:min(q9OpenCells, geom.Nx)) = true;
    q9OpenExcluded(:, max(1, geom.Nx-q9OpenCells+1):geom.Nx) = true;
end
q9Halo = false(size(solid));
if q9HaloCells > 0
    K = ones(2*q9HaloCells + 1, 2*q9HaloCells + 1);
    q9Halo = conv2(double(solid), K, 'same') > 0 & ~solid;
end
r0 = local_get_num(params, 'q9LowMassRampStart', 1.0);
r1 = local_get_num(params, 'q9LowMassRampEnd', local_get_num(params, 'q9MinCellMassForCorrection', 8.0));
if r1 <= r0
    q9LowMassRamp = double(N >= r1);
else
    q9LowMassRamp = min(1, max(0, (N - r0) ./ (r1 - r0)));
end
q9GeoActive = fluid & ~q9OpenExcluded & ~q9Halo;

masks = struct();
masks.fluid = fluid;
masks.solid = solid;
masks.inletBand = inletBand & fluid;
masks.outletBand = outletBand & fluid;
masks.frontBand = frontBand;
masks.upstreamLower = upstreamLower;
masks.upstreamUpper = upstreamUpper;
masks.aboveObstacle = aboveObstacle;
masks.downstreamLower = downstreamLower;
masks.downstreamUpper = downstreamUpper;
masks.q9OpenExcluded = q9OpenExcluded & fluid;
masks.q9Halo = q9Halo;
masks.q9GeoActive = q9GeoActive;
masks.q9LowMassRamp = q9LowMassRamp;
end

function row = local_budget_row(caseLabel, frameIndex, t, fields, masks)
N = local_field_or_zeros(fields, 'N', size(masks.fluid,1), size(masks.fluid,2));
Ux = local_field_or_zeros(fields, 'Ux', size(N,1), size(N,2));
Uy = local_field_or_zeros(fields, 'Uy', size(N,1), size(N,2));
fluidN = N(masks.fluid);

names = {'inletBand','outletBand','frontBand','upstreamLower','upstreamUpper','aboveObstacle','downstreamLower','downstreamUpper','q9OpenExcluded','q9Halo','q9GeoActive'};
vals = struct();
for i = 1:numel(names)
    nm = names{i};
    vals.([nm 'Mass']) = sum(N(masks.(nm)), 'omitnan');
    vals.([nm 'MeanN']) = mean(N(masks.(nm)), 'omitnan');
    vals.([nm 'MaxN']) = max([N(masks.(nm)); 0]);
end

% Flux proxies. These are not exact finite-volume face fluxes; they are zone/cut trend diagnostics.
inletFluxProxy = sum(N(masks.inletBand) .* Ux(masks.inletBand), 'omitnan');
outletFluxProxy = sum(N(masks.outletBand) .* Ux(masks.outletBand), 'omitnan');
frontBandUpFluxProxy = sum(max(0, N(masks.frontBand) .* Uy(masks.frontBand)), 'omitnan');
frontBandDownFluxProxy = sum(min(0, N(masks.frontBand) .* Uy(masks.frontBand)), 'omitnan');

row = table(string(caseLabel), frameIndex, t, ...
    sum(fluidN,'omitnan'), mean(fluidN,'omitnan'), std(fluidN,0,'omitnan'), min(fluidN), max(fluidN), ...
    vals.inletBandMass, vals.outletBandMass, vals.frontBandMass, ...
    vals.upstreamLowerMass, vals.upstreamUpperMass, vals.aboveObstacleMass, vals.downstreamLowerMass, vals.downstreamUpperMass, ...
    vals.upstreamLowerMaxN, vals.downstreamLowerMaxN, vals.q9OpenExcludedMass, vals.q9HaloMass, vals.q9GeoActiveMass, ...
    inletFluxProxy, outletFluxProxy, frontBandUpFluxProxy, frontBandDownFluxProxy, ...
    'VariableNames', {'caseLabel','frameIndex','time','totalFluidMass','meanFluidN','stdFluidN','minFluidN','maxFluidN', ...
    'inletBandMass','outletBandMass','frontBandMass','upstreamLowerMass','upstreamUpperMass','aboveObstacleMass','downstreamLowerMass','downstreamUpperMass', ...
    'upstreamLowerMaxN','downstreamLowerMaxN','q9OpenExcludedMass','q9HaloMass','q9GeoActiveMass', ...
    'inletFluxProxy','outletFluxProxy','frontBandUpFluxProxy','frontBandDownFluxProxy'});
end

function srow = local_summary_row(caseLabel, rows, lateFraction)
last = rows(end,:);
if height(rows) >= 2
    t = rows.time;
    massSlope = polyfit(t, rows.totalFluidMass, 1); massSlope = massSlope(1);
    upSlope = polyfit(t, rows.upstreamLowerMass, 1); upSlope = upSlope(1);
    downSlope = polyfit(t, rows.downstreamLowerMass, 1); downSlope = downSlope(1);
    frontSlope = polyfit(t, rows.frontBandMass, 1); frontSlope = frontSlope(1);
else
    massSlope = NaN; upSlope = NaN; downSlope = NaN; frontSlope = NaN;
end
lateFraction = min(1, max(eps, lateFraction));
lateStart = rows.time(end) - lateFraction * (rows.time(end) - rows.time(1));
late = rows(rows.time >= lateStart, :);
if height(late) >= 2
    tl = late.time;
    massSlopeLate = polyfit(tl, late.totalFluidMass, 1); massSlopeLate = massSlopeLate(1);
    upSlopeLate = polyfit(tl, late.upstreamLowerMass, 1); upSlopeLate = upSlopeLate(1);
    downSlopeLate = polyfit(tl, late.downstreamLowerMass, 1); downSlopeLate = downSlopeLate(1);
    frontSlopeLate = polyfit(tl, late.frontBandMass, 1); frontSlopeLate = frontSlopeLate(1);
else
    massSlopeLate = NaN; upSlopeLate = NaN; downSlopeLate = NaN; frontSlopeLate = NaN;
end
inMeanLate = mean(late.inletFluxProxy, 'omitnan');
outMeanLate = mean(late.outletFluxProxy, 'omitnan');
if abs(inMeanLate) > eps
    outOverInLate = outMeanLate / inMeanLate;
else
    outOverInLate = NaN;
end
srow = table(string(caseLabel), height(rows), rows.time(1), rows.time(end), lateStart, ...
    last.totalFluidMass, massSlope, massSlopeLate, last.maxFluidN, mean(late.maxFluidN,'omitnan'), last.stdFluidN, mean(late.stdFluidN,'omitnan'), ...
    last.upstreamLowerMass, upSlope, upSlopeLate, last.upstreamLowerMaxN, ...
    last.downstreamLowerMass, downSlope, downSlopeLate, last.downstreamLowerMaxN, ...
    last.frontBandMass, frontSlope, frontSlopeLate, ...
    last.inletFluxProxy, last.outletFluxProxy, inMeanLate, outMeanLate, outOverInLate, mean(late.frontBandUpFluxProxy,'omitnan'), ...
    last.q9HaloMass, last.q9GeoActiveMass, ...
    'VariableNames', {'caseLabel','nFrames','timeFirst','timeFinal','lateStartTime', ...
    'totalFluidMassFinal','totalFluidMassSlope','totalFluidMassSlopeLate','maxFluidNFinal','maxFluidNMeanLate','stdFluidNFinal','stdFluidNMeanLate', ...
    'upstreamLowerMassFinal','upstreamLowerMassSlope','upstreamLowerMassSlopeLate','upstreamLowerMaxNFinal', ...
    'downstreamLowerMassFinal','downstreamLowerMassSlope','downstreamLowerMassSlopeLate','downstreamLowerMaxNFinal', ...
    'frontBandMassFinal','frontBandMassSlope','frontBandMassSlopeLate', ...
    'inletFluxProxyFinal','outletFluxProxyFinal','inletFluxProxyMeanLate','outletFluxProxyMeanLate','outletOverInletFluxProxyMeanLate','frontBandUpFluxProxyMeanLate', ...
    'q9HaloMassFinal','q9GeoActiveMassFinal'});
end

function local_make_plots(T, outDir)
labels = unique(T.caseLabel, 'stable');
fields = {'totalFluidMass','upstreamLowerMass','downstreamLowerMass','maxFluidN','stdFluidN','frontBandUpFluxProxy'};
for f = 1:numel(fields)
    fig = figure('Visible','on','Color','w'); hold on;
    for i = 1:numel(labels)
        sel = T.caseLabel == labels(i);
        plot(T.time(sel), T.(fields{f})(sel), '-o', 'DisplayName', char(labels(i)));
    end
    grid on; xlabel('time'); ylabel(fields{f}, 'Interpreter','none'); legend('Interpreter','none','Location','best');
    title(sprintf('0072 backward-step hard-inlet budget: %s', fields{f}), 'Interpreter','none');
    saveas(fig, fullfile(outDir, sprintf('plot_%s.png', fields{f})));
    %close(fig);
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

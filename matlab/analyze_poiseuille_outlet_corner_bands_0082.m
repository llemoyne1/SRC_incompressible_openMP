function R = analyze_poiseuille_outlet_corner_bands_0082(varargin)
%ANALYZE_POISEUILLE_OUTLET_CORNER_BANDS_0082 Outlet corner diagnostics for hard-inlet/free-outlet runs.
%
% This diagnostic is intentionally state-dump based.  It separates the right
% outlet and the upstream pre-outlet region into bottom-wall, core, and
% top-wall y-bands in order to identify corner recirculation/backflow and
% density accumulation near wall/outlet junctions.
%
% Typical use:
%   R = analyze_poiseuille_outlet_corner_bands_0082( ...
%       'root','..', ...
%       'runRoot','runs/poiseuille_ramped_softlimited_q9_0080_g30');

p = inputParser;
p.FunctionName = 'analyze_poiseuille_outlet_corner_bands_0082';
addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
addParameter(p, 'runRoot', 'runs/poiseuille_ramped_softlimited_q9_0080_g30', @(s) ischar(s) || isstring(s));
addParameter(p, 'caseGlob', 'poiseuille_*', @(s) ischar(s) || isstring(s));
addParameter(p, 'lateFraction', 0.50, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'outletBandCells', NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'preOutletBandCells', NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'wallBandCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'showFigures', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'closeFigures', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

root = char(opts.root);
runRoot = char(opts.runRoot);
if ~exist(runRoot, 'dir')
    runRoot = fullfile(root, runRoot);
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

outDir = fullfile(runRoot, 'analysis_0082_outlet_corner_bands');
if ~exist(outDir, 'dir'); mkdir(outDir); end

allBandRows = table();
allSummaryRows = table();

for c = 1:numel(caseDirs)
    caseLabel = caseDirs(c).name;
    caseDir = fullfile(caseDirs(c).folder, caseDirs(c).name);
    paramsPath = fullfile(caseDir, 'params_used.kv');
    runtimePath = fullfile(caseDir, 'summary_runtime.csv');
    if ~exist(paramsPath, 'file') || ~exist(runtimePath, 'file')
        warning('Skipping %s: missing params_used.kv or summary_runtime.csv.', caseLabel);
        continue;
    end

    params = parse_smpcd_kv(paramsPath);
    geom = local_geometry(params);
    frames = list_smpcd_dumps(caseDir, 'summaryFile', runtimePath);
    if isempty(frames)
        warning('No .smpcd dumps for %s; no outlet-band diagnostics produced.', caseLabel);
        continue;
    end

    idxList = 1:round(opts.frameStride):height(frames);
    if idxList(end) ~= height(frames)
        idxList = [idxList height(frames)]; %#ok<AGROW>
    end

    bandDef = local_band_definition(geom, params, opts);
    bandRows = table();
    for kk = 1:numel(idxList)
        idx = idxList(kk);
        state = read_smpcd_state(frames.fullPath{idx});
        fields = bin_smpcd_state(state, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', geom.Nx, 'Ny', geom.Ny, ...
            'periodicX', false, 'periodicY', false);
        bandRows = [bandRows; local_band_rows(caseLabel, idx, frames.time(idx), fields, geom, bandDef)]; %#ok<AGROW>
    end

    writetable(bandRows, fullfile(outDir, sprintf('outlet_corner_band_timeseries_%s.csv', caseLabel)));
    allBandRows = [allBandRows; bandRows]; %#ok<AGROW>

    summaryRows = local_summary_rows(caseLabel, bandRows, opts.lateFraction);
    writetable(summaryRows, fullfile(outDir, sprintf('outlet_corner_band_summary_%s.csv', caseLabel)));
    allSummaryRows = [allSummaryRows; summaryRows]; %#ok<AGROW>
end

if ~isempty(allBandRows)
    writetable(allBandRows, fullfile(outDir, 'outlet_corner_band_timeseries_all_cases.csv'));
end
if ~isempty(allSummaryRows)
    writetable(allSummaryRows, fullfile(outDir, 'outlet_corner_band_summary_all_cases.csv'));
    disp(allSummaryRows);
end

if opts.makePlots
    local_make_plots(allBandRows, outDir, logical(opts.showFigures), logical(opts.closeFigures));
end

R = struct();
R.runRoot = runRoot;
R.outputDir = outDir;
R.bandTimeseries = allBandRows;
R.summary = allSummaryRows;
end

function geom = local_geometry(params)
geom = struct();
geom.Lx = local_get_num(params, 'Lx', 1.0);
geom.Ly = local_get_num(params, 'Ly', 1.0);
geom.Nx = round(local_get_num(params, 'Nx', 32));
geom.Ny = round(local_get_num(params, 'Ny', 32));
geom.dx = geom.Lx / geom.Nx;
geom.dy = geom.Ly / geom.Ny;
geom.xc = ((0:geom.Nx-1) + 0.5) * geom.dx;
geom.yc = ((0:geom.Ny-1) + 0.5) * geom.dy;
end

function bandDef = local_band_definition(geom, params, opts)
defOutlet = local_get_num(params, 'q9OpenBoundaryExclusionCells', local_get_num(params, 'inletReservoirCells', 3));
if ~isfinite(defOutlet) || defOutlet <= 0
    defOutlet = local_get_num(params, 'inletReservoirCells', 3);
end
outletCells = round(opts.outletBandCells);
if ~isfinite(outletCells) || outletCells <= 0
    outletCells = round(defOutlet);
end
outletCells = max(1, min(geom.Nx, outletCells));

preCells = round(opts.preOutletBandCells);
if ~isfinite(preCells) || preCells <= 0
    preCells = 2*outletCells;
end
preCells = max(1, min(geom.Nx-outletCells, preCells));

wallCells = max(1, min(floor((geom.Ny-1)/2), round(opts.wallBandCells)));

ixOutlet = (geom.Nx-outletCells+1):geom.Nx;
ixPre = max(1, geom.Nx-outletCells-preCells+1):(geom.Nx-outletCells);
if isempty(ixPre)
    ixPre = ixOutlet;
end

iyBottom = 1:wallCells;
iyTop = (geom.Ny-wallCells+1):geom.Ny;
iyCore = (wallCells+1):(geom.Ny-wallCells);
if isempty(iyCore)
    iyCore = 1:geom.Ny;
end

bandDef = struct();
bandDef.outletCells = outletCells;
bandDef.preOutletCells = preCells;
bandDef.wallBandCells = wallCells;
bandDef.regions = struct( ...
    'name', {'outlet','preOutlet'}, ...
    'ix', {ixOutlet, ixPre});
bandDef.ybands = struct( ...
    'name', {'bottom','core','top','all'}, ...
    'iy', {iyBottom, iyCore, iyTop, 1:geom.Ny});
end

function rows = local_band_rows(caseLabel, frameIndex, t, fields, geom, bandDef)
N = local_field_or_zeros(fields, 'N', geom.Ny, geom.Nx);
Ux = local_field_or_zeros(fields, 'Ux', geom.Ny, geom.Nx);
Uy = local_field_or_zeros(fields, 'Uy', geom.Ny, geom.Nx);
Speed = sqrt(Ux.^2 + Uy.^2);

rows = table();
for r = 1:numel(bandDef.regions)
    ix = bandDef.regions(r).ix;
    for b = 1:numel(bandDef.ybands)
        iy = bandDef.ybands(b).iy;
        mask = false(geom.Ny, geom.Nx);
        mask(iy, ix) = true;
        rows = [rows; local_one_band_row(caseLabel, frameIndex, t, bandDef.regions(r).name, bandDef.ybands(b).name, mask, N, Ux, Uy, Speed)]; %#ok<AGROW>
    end
end
end

function row = local_one_band_row(caseLabel, frameIndex, t, regionName, yBandName, mask, N, Ux, Uy, Speed)
n = N(mask);
ux = Ux(mask);
uy = Uy(mask);
sp = Speed(mask);
flux = n .* ux;
backMask = ux < 0;
backMass = sum(n(backMask), 'omitnan');
totalMass = sum(n, 'omitnan');
positiveFlux = sum(max(flux, 0), 'omitnan');
negativeFlux = sum(min(flux, 0), 'omitnan');
netFlux = sum(flux, 'omitnan');
absFlux = sum(abs(flux), 'omitnan');

row = table(string(caseLabel), frameIndex, t, string(regionName), string(yBandName), nnz(mask), ...
    totalMass, mean(n,'omitnan'), std(n,0,'omitnan'), min(n), max(n), ...
    mean(ux,'omitnan'), mean(uy,'omitnan'), sqrt(mean(uy.^2,'omitnan')), mean(sp,'omitnan'), max(sp,[],'omitnan'), ...
    netFlux, positiveFlux, negativeFlux, absFlux, local_scalar_ratio(abs(negativeFlux), max(absFlux, eps)), ...
    backMass, local_scalar_ratio(backMass, totalMass), mean(ux(backMask),'omitnan'), ...
    'VariableNames', {'caseLabel','frameIndex','time','region','yBand','nCells', ...
    'mass','meanN','stdN','minN','maxN', ...
    'meanUx','meanUy','uyRms','meanSpeed','maxSpeed', ...
    'netFluxProxy','positiveFluxProxy','negativeFluxProxy','absFluxProxy','negativeFluxFraction', ...
    'backflowMass','backflowMassFraction','meanUxBackflow'});
end

function summary = local_summary_rows(caseLabel, bandRows, lateFraction)
if isempty(bandRows)
    summary = table();
    return;
end
lateRows = local_late(bandRows, lateFraction);
keys = unique(lateRows(:, {'region','yBand'}), 'rows', 'stable');
summary = table();
for i = 1:height(keys)
    idxLate = lateRows.region == keys.region(i) & lateRows.yBand == keys.yBand(i);
    idxAll = bandRows.region == keys.region(i) & bandRows.yBand == keys.yBand(i);
    L = lateRows(idxLate, :);
    A = bandRows(idxAll, :);
    srow = table(string(caseLabel), keys.region(i), keys.yBand(i), ...
        mean(L.mass,'omitnan'), local_slope(L.time, L.mass), mean(L.meanN,'omitnan'), mean(L.stdN,'omitnan'), max(A.maxN,[],'omitnan'), ...
        mean(L.netFluxProxy,'omitnan'), mean(L.positiveFluxProxy,'omitnan'), mean(L.negativeFluxProxy,'omitnan'), ...
        mean(L.negativeFluxFraction,'omitnan'), max(A.negativeFluxFraction,[],'omitnan'), ...
        mean(L.backflowMassFraction,'omitnan'), max(A.backflowMassFraction,[],'omitnan'), ...
        mean(L.uyRms,'omitnan'), max(A.maxSpeed,[],'omitnan'), ...
        'VariableNames', {'caseLabel','region','yBand', ...
        'massMeanLate','massSlopeLate','meanNMeanLate','stdNMeanLate','maxNAll', ...
        'netFluxMeanLate','positiveFluxMeanLate','negativeFluxMeanLate', ...
        'negativeFluxFractionMeanLate','negativeFluxFractionMaxAll', ...
        'backflowMassFractionMeanLate','backflowMassFractionMaxAll', ...
        'uyRmsMeanLate','maxSpeedAll'});
    summary = [summary; srow]; %#ok<AGROW>
end
end

function local_make_plots(T, outDir, showFigures, closeFigures)
if isempty(T); return; end
% Focus on outlet bands first: this is where the corner pathology is expected.
Tout = T(T.region == "outlet", :);
local_plot_bands(Tout, outDir, 'outlet_band_netFluxProxy', 'netFluxProxy', showFigures, closeFigures);
local_plot_bands(Tout, outDir, 'outlet_band_negativeFluxFraction', 'negativeFluxFraction', showFigures, closeFigures);
local_plot_bands(Tout, outDir, 'outlet_band_mass', 'mass', showFigures, closeFigures);
local_plot_bands(Tout, outDir, 'outlet_band_meanN', 'meanN', showFigures, closeFigures);
local_plot_bands(Tout, outDir, 'outlet_band_maxN', 'maxN', showFigures, closeFigures);
local_plot_bands(Tout, outDir, 'outlet_band_uyRms', 'uyRms', showFigures, closeFigures);

Tpre = T(T.region == "preOutlet", :);
local_plot_bands(Tpre, outDir, 'preoutlet_band_netFluxProxy', 'netFluxProxy', showFigures, closeFigures);
local_plot_bands(Tpre, outDir, 'preoutlet_band_negativeFluxFraction', 'negativeFluxFraction', showFigures, closeFigures);
local_plot_bands(Tpre, outDir, 'preoutlet_band_mass', 'mass', showFigures, closeFigures);
local_plot_bands(Tpre, outDir, 'preoutlet_band_uyRms', 'uyRms', showFigures, closeFigures);
end

function local_plot_bands(T, outDir, baseName, fieldName, showFigures, closeFigures)
if isempty(T) || ~ismember(fieldName, T.Properties.VariableNames); return; end
if showFigures
    fig = figure('Visible','on');
else
    fig = figure('Visible','off');
end
hold on; grid on;
labels = unique(T.yBand, 'stable');
for i = 1:numel(labels)
    idx = T.yBand == labels(i);
    plot(T.time(idx), T.(fieldName)(idx), '-o', 'DisplayName', char(labels(i)));
end
xlabel('time'); ylabel(fieldName); title(strrep(baseName, '_', '\_'));
legend('Location','best', 'Interpreter','none');
saveas(fig, fullfile(outDir, [baseName '.png']));
if closeFigures
    close(fig);
end
end

function A = local_field_or_zeros(fields, name, ny, nx)
if isfield(fields, name)
    A = fields.(name);
else
    A = zeros(ny, nx);
end
end

function out = local_late(T, lateFraction)
if isempty(T)
    out = T;
    return;
end
if ismember('time', T.Properties.VariableNames)
    t0 = T.time(1);
    t1 = T.time(end);
    tCut = t0 + (1-lateFraction) * (t1-t0);
    out = T(T.time >= tCut, :);
else
    n = height(T);
    i0 = max(1, floor((1-lateFraction)*n));
    out = T(i0:end, :);
end
end

function x = local_get_num(params, name, defaultValue)
if isfield(params, name) && isnumeric(params.(name)) && isscalar(params.(name))
    x = double(params.(name));
else
    x = defaultValue;
end
end

function r = local_scalar_ratio(a, b)
if ~isfinite(b) || abs(b) <= eps
    r = NaN;
else
    r = a / b;
end
end

function s = local_slope(x, y)
x = double(x(:)); y = double(y(:));
ok = isfinite(x) & isfinite(y);
if nnz(ok) < 2 || max(x(ok))-min(x(ok)) <= eps
    s = NaN;
    return;
end
p = polyfit(x(ok), y(ok), 1);
s = p(1);
end

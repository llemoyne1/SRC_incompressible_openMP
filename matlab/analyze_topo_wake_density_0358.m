function [T, S] = analyze_topo_wake_density_0358(runPath, varargin)
%ANALYZE_TOPO_WAKE_DENSITY_0358 Quantify density depletion upstream/wake from .smpcd dumps.
%
% [T,S] = analyze_topo_wake_density_0358(runPath, ...)
%
% runPath can be either a run root containing output/state_step_*.smpcd, or
% directly an output directory containing state_step_*.smpcd.
%
% The function bins each dump on the simulation grid and computes density,
% population, velocity and momentum-deficit proxies in three regions:
% upstream, near wake, far wake.  Regions are defined relative to an object box.
%
% Object detection:
%   1) use explicit 'ObjectBox',[xmin xmax ymin ymax]
%   2) otherwise infer a circle from immersedSolidCx/Cy/R or darcyCircleCx/Cy/R
%
% Example:
%   addpath(genpath('matlab'))
%   [T,S] = analyze_topo_wake_density_0358( ...
%       'runs/topo_vk_0356f_darcy5000_matched', ...
%       'OutputDir','runs/topo_vk_0356f_darcy5000_matched/analysis', ...
%       'MakePlots',true);
%
% For NACA/airfoil-like cases, pass ObjectBox explicitly, e.g.
%   'ObjectBox',[0.44 0.66 0.13 0.27]

p = inputParser;
p.FunctionName = 'analyze_topo_wake_density_0358';
addRequired(p, 'runPath', @(s)ischar(s) || isstring(s));
addParameter(p, 'ParamsFile', '', @(s)ischar(s) || isstring(s));
addParameter(p, 'OutputDir', '', @(s)ischar(s) || isstring(s));
addParameter(p, 'OutputCsv', '', @(s)ischar(s) || isstring(s));
addParameter(p, 'SummaryCsv', '', @(s)ischar(s) || isstring(s));
addParameter(p, 'Lx', [], @isnumeric);
addParameter(p, 'Ly', [], @isnumeric);
addParameter(p, 'Nx', [], @isnumeric);
addParameter(p, 'Ny', [], @isnumeric);
addParameter(p, 'ObjectBox', [], @isnumeric);
addParameter(p, 'BandHalfHeight', [], @isnumeric);
addParameter(p, 'BandPad', [], @isnumeric);
addParameter(p, 'GapX', [], @isnumeric);
addParameter(p, 'UpstreamLength', [], @isnumeric);
addParameter(p, 'NearWakeLength', [], @isnumeric);
addParameter(p, 'FarWakeLength', [], @isnumeric);
addParameter(p, 'Uref', [], @isnumeric);
addParameter(p, 'MaxDumps', Inf, @isnumeric);
addParameter(p, 'DumpStride', 1, @isnumeric);
addParameter(p, 'MakePlots', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'ShowFigures', true, @(x)islogical(x) || isnumeric(x));
parse(p, runPath, varargin{:});
opts = p.Results;

runPath = char(opts.runPath);
[runRoot, outputDir] = local_resolve_run_output(runPath);
paramsFile = local_resolve_params(runRoot, outputDir, char(opts.ParamsFile));
params = local_read_kv(paramsFile);

Lx = local_num(opts.Lx, params, 'Lx', NaN);
Ly = local_num(opts.Ly, params, 'Ly', NaN);
Nx = round(local_num(opts.Nx, params, 'Nx', NaN));
Ny = round(local_num(opts.Ny, params, 'Ny', NaN));
dt = local_num([], params, 'dt', NaN);
if any(~isfinite([Lx Ly Nx Ny]))
    error('analyze_topo_wake_density_0358:missingGrid', 'Cannot resolve Lx/Ly/Nx/Ny; pass ParamsFile or explicit values.');
end

objectBox = local_resolve_object_box(opts.ObjectBox, params);
if isempty(objectBox)
    error('analyze_topo_wake_density_0358:missingObject', ['Cannot infer object box. ', ...
        'Pass ObjectBox=[xmin xmax ymin ymax], or provide params with immersedSolid/darcy circle.']);
end
objectBox = double(objectBox(:).');
objectBox(1:2) = min(max(objectBox(1:2), 0), Lx);
objectBox(3:4) = min(max(objectBox(3:4), 0), Ly);

objXMin = objectBox(1); objXMax = objectBox(2);
objYMin = objectBox(3); objYMax = objectBox(4);
objYc = 0.5*(objYMin + objYMax);
objHalfH = max(1e-12, 0.5*(objYMax - objYMin));
if isempty(opts.BandHalfHeight)
    if isempty(opts.BandPad)
        bandHalfHeight = max(1.5*objHalfH, 0.08*Ly);
    else
        bandHalfHeight = objHalfH + double(opts.BandPad);
    end
else
    bandHalfHeight = double(opts.BandHalfHeight);
end
bandYMin = max(0, objYc - bandHalfHeight);
bandYMax = min(Ly, objYc + bandHalfHeight);

gapX = local_default(opts.GapX, 0.015*Lx);
upLen = local_default(opts.UpstreamLength, 0.20*Lx);
nearLen = local_default(opts.NearWakeLength, 0.25*Lx);
farLen = local_default(opts.FarWakeLength, 0.25*Lx);

regions = struct();
regions.upstream = [max(0, objXMin-gapX-upLen), max(0, objXMin-gapX), bandYMin, bandYMax];
regions.nearWake = [min(Lx, objXMax+gapX), min(Lx, objXMax+gapX+nearLen), bandYMin, bandYMax];
regions.farWake = [min(Lx, objXMax+gapX+nearLen), min(Lx, objXMax+gapX+nearLen+farLen), bandYMin, bandYMax];
regions.objectBox = objectBox;

dumps = dir(fullfile(outputDir, 'state_step_*.smpcd'));
if isempty(dumps)
    error('analyze_topo_wake_density_0358:noDumps', 'No state_step_*.smpcd dumps found in %s', outputDir);
end
[~, order] = sort({dumps.name}); dumps = dumps(order);
stride = max(1, round(opts.DumpStride));
dumps = dumps(1:stride:end);
if isfinite(opts.MaxDumps)
    dumps = dumps(1:min(numel(dumps), max(1, round(opts.MaxDumps))));
end

if isempty(opts.OutputDir)
    analysisDir = fullfile(runRoot, 'analysis');
else
    analysisDir = char(opts.OutputDir);
end
if ~exist(analysisDir, 'dir'), mkdir(analysisDir); end
outCsv = char(opts.OutputCsv);
if isempty(outCsv), outCsv = fullfile(analysisDir, 'wake_density_0358.csv'); end
sumCsv = char(opts.SummaryCsv);
if isempty(sumCsv), sumCsv = fullfile(analysisDir, 'wake_density_summary_0358.csv'); end

rows = cell(numel(dumps), 1);
for k = 1:numel(dumps)
    f = fullfile(dumps(k).folder, dumps(k).name);
    state = read_smpcd_state(f);
    fields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, 'periodicX', true, 'periodicY', false, 'fluidOnly', true);
    step = local_step_from_name(f);
    if isfinite(dt), time = step * dt; else, time = NaN; end
    Uref = local_default(opts.Uref, local_region_mean(fields.Ux, fields, regions.upstream));
    rows{k} = local_compute_row(f, step, time, state, fields, regions, Uref);
    fprintf('[0358-wake] %d/%d step=%g Nwake/up=%.6g Uxwake=%.6g deficit=%.6g\n', ...
        k, numel(dumps), step, rows{k}.nearWake_N_over_upstream, rows{k}.nearWake_Ux_mean, rows{k}.nearWake_momentumDeficit_mean);
end
T = struct2table(vertcat(rows{:}));
writetable(T, outCsv);

S = local_summary(T, runRoot, outputDir, paramsFile, objectBox, regions, Lx, Ly, Nx, Ny);
writetable(struct2table(S), sumCsv);

if logical(opts.MakePlots)
    local_make_plots(T, analysisDir, logical(opts.ShowFigures));
end

fprintf('[0358-wake] wrote %s\n', outCsv);
fprintf('[0358-wake] wrote %s\n', sumCsv);
end

function row = local_compute_row(file, step, time, state, fields, regions, Uref)
role = ones(numel(state.x),1,'uint8');
if isfield(state,'role') && ~isempty(state.role), role = uint8(state.role(:)); end
fluidCount = nnz(role == uint8(1));
allStats = local_stats_for_region(fields, [0 fields.Lx 0 fields.Ly], Uref);
up = local_stats_for_region(fields, regions.upstream, Uref);
nw = local_stats_for_region(fields, regions.nearWake, Uref);
fw = local_stats_for_region(fields, regions.farWake, Uref);
ob = local_stats_for_region(fields, regions.objectBox, Uref);
row = struct();
row.file = string(file);
row.step = step;
row.time = time;
row.rawParticles = numel(state.x);
row.rawFluidParticles = fluidCount;
row.Uref = Uref;
row.all_N_mean = allStats.N_mean;
row.upstream_N_mean = up.N_mean;
row.nearWake_N_mean = nw.N_mean;
row.farWake_N_mean = fw.N_mean;
row.object_N_mean = ob.N_mean;
row.nearWake_N_over_upstream = nw.N_mean / max(up.N_mean, eps);
row.farWake_N_over_upstream = fw.N_mean / max(up.N_mean, eps);
row.object_N_over_upstream = ob.N_mean / max(up.N_mean, eps);
row.upstream_rho_mean = up.rho_mean;
row.nearWake_rho_mean = nw.rho_mean;
row.farWake_rho_mean = fw.rho_mean;
row.nearWake_rho_over_upstream = nw.rho_mean / max(up.rho_mean, eps);
row.farWake_rho_over_upstream = fw.rho_mean / max(up.rho_mean, eps);
row.upstream_Ux_mean = up.Ux_mean;
row.nearWake_Ux_mean = nw.Ux_mean;
row.farWake_Ux_mean = fw.Ux_mean;
row.object_Ux_mean = ob.Ux_mean;
row.nearWake_Ux_over_upstream = nw.Ux_mean / max(abs(up.Ux_mean), eps);
row.farWake_Ux_over_upstream = fw.Ux_mean / max(abs(up.Ux_mean), eps);
row.nearWake_momentumDeficit_mean = nw.momentumDeficit_mean;
row.farWake_momentumDeficit_mean = fw.momentumDeficit_mean;
row.nearWake_massFluxProxy_mean = nw.massFluxProxy_mean;
row.farWake_massFluxProxy_mean = fw.massFluxProxy_mean;
row.upstream_cells = up.cellCount;
row.nearWake_cells = nw.cellCount;
row.farWake_cells = fw.cellCount;
end

function st = local_stats_for_region(fields, box, Uref)
[X, Y] = meshgrid(fields.xc, fields.yc);
mask = X >= box(1) & X <= box(2) & Y >= box(3) & Y <= box(4);
N = fields.N(mask); rho = fields.rho(mask); Ux = fields.Ux(mask); Uy = fields.Uy(mask);
validUx = isfinite(Ux);
Ux0 = Ux; Ux0(~validUx) = 0;
rho0 = rho; rho0(~isfinite(rho0)) = 0;
st = struct();
st.cellCount = nnz(mask);
st.N_mean = mean(N, 'omitnan');
st.N_min = min(N, [], 'omitnan');
st.N_std = std(N, 0, 'omitnan');
st.rho_mean = mean(rho, 'omitnan');
st.Ux_mean = mean(Ux, 'omitnan');
st.Uy_mean = mean(Uy, 'omitnan');
st.speed_mean = mean(hypot(Ux, Uy), 'omitnan');
st.massFluxProxy_mean = mean(rho0 .* Ux0, 'omitnan');
st.momentumDeficit_mean = mean(rho0 .* Ux0 .* (Uref - Ux0), 'omitnan');
end

function m = local_region_mean(A, fields, box)
[X, Y] = meshgrid(fields.xc, fields.yc);
mask = X >= box(1) & X <= box(2) & Y >= box(3) & Y <= box(4);
m = mean(A(mask), 'omitnan');
if ~isfinite(m), m = mean(A(:), 'omitnan'); end
if ~isfinite(m), m = 0; end
end

function S = local_summary(T, runRoot, outputDir, paramsFile, objectBox, regions, Lx, Ly, Nx, Ny)
S = struct();
S.runRoot = string(runRoot);
S.outputDir = string(outputDir);
S.paramsFile = string(paramsFile);
S.nDumps = height(T);
S.stepFirst = T.step(1);
S.stepLast = T.step(end);
S.timeFirst = T.time(1);
S.timeLast = T.time(end);
S.Lx = Lx; S.Ly = Ly; S.Nx = Nx; S.Ny = Ny;
S.objectXMin = objectBox(1); S.objectXMax = objectBox(2); S.objectYMin = objectBox(3); S.objectYMax = objectBox(4);
S.upstreamBox = string(sprintf('[%.9g %.9g %.9g %.9g]', regions.upstream));
S.nearWakeBox = string(sprintf('[%.9g %.9g %.9g %.9g]', regions.nearWake));
S.farWakeBox = string(sprintf('[%.9g %.9g %.9g %.9g]', regions.farWake));
S.nearWake_N_over_upstream_mean = mean(T.nearWake_N_over_upstream, 'omitnan');
S.nearWake_N_over_upstream_last = T.nearWake_N_over_upstream(end);
S.farWake_N_over_upstream_mean = mean(T.farWake_N_over_upstream, 'omitnan');
S.farWake_N_over_upstream_last = T.farWake_N_over_upstream(end);
S.nearWake_Ux_over_upstream_mean = mean(T.nearWake_Ux_over_upstream, 'omitnan');
S.nearWake_Ux_over_upstream_last = T.nearWake_Ux_over_upstream(end);
S.nearWake_momentumDeficit_mean = mean(T.nearWake_momentumDeficit_mean, 'omitnan');
S.nearWake_momentumDeficit_last = T.nearWake_momentumDeficit_mean(end);
end

function local_make_plots(T, outDir, showFigures)
vis = 'off'; if showFigures, vis = 'on'; end
plot_one(T.step, [T.nearWake_N_over_upstream T.farWake_N_over_upstream], {'near wake','far wake'}, 'step', 'N / N_{upstream}', 'Wake density ratio', fullfile(outDir, 'wake_density_ratio_0358'), vis);
plot_one(T.step, [T.nearWake_Ux_over_upstream T.farWake_Ux_over_upstream], {'near wake','far wake'}, 'step', 'Ux / Ux_{upstream}', 'Wake velocity ratio', fullfile(outDir, 'wake_velocity_ratio_0358'), vis);
plot_one(T.step, [T.nearWake_momentumDeficit_mean T.farWake_momentumDeficit_mean], {'near wake','far wake'}, 'step', 'rho ux (Uref-ux)', 'Momentum-deficit proxy', fullfile(outDir, 'wake_momentum_deficit_0358'), vis);
end

function plot_one(x, Y, labels, xl, yl, ttl, base, vis)
fig = figure('Visible', vis, 'Color', 'w');
plot(x, Y, '-o', 'LineWidth', 1.2);
grid on; xlabel(xl); ylabel(yl); title(ttl); legend(labels, 'Location', 'best');
saveas(fig, [base '.png']); saveas(fig, [base '.pdf']);
if strcmpi(vis, 'off'), close(fig); end
end

function [runRoot, outputDir] = local_resolve_run_output(runPath)
runPath = char(runPath);
if isfolder(fullfile(runPath, 'output'))
    runRoot = runPath; outputDir = fullfile(runPath, 'output'); return;
end
if isfolder(runPath) && ~isempty(dir(fullfile(runPath, 'state_step_*.smpcd')))
    outputDir = runPath; runRoot = fileparts(runPath); return;
end
error('analyze_topo_wake_density_0358:badRunPath', 'Cannot resolve run/output path: %s', runPath);
end

function paramsFile = local_resolve_params(runRoot, outputDir, requested)
if ~isempty(requested)
    paramsFile = char(requested); return;
end
cands = [dir(fullfile(runRoot, 'params', '*.kv')); dir(fullfile(runRoot, 'params_used.kv')); dir(fullfile(outputDir, 'params_used.kv'))];
if isempty(cands), paramsFile = ''; else, paramsFile = fullfile(cands(1).folder, cands(1).name); end
end

function params = local_read_kv(filename)
params = struct();
if isempty(filename) || ~isfile(filename), return; end
lines = regexp(fileread(filename), '\r?\n', 'split');
for i = 1:numel(lines)
    line = regexprep(lines{i}, '#.*$', '');
    tok = regexp(line, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$', 'tokens', 'once');
    if isempty(tok), continue; end
    params.(tok{1}) = tok{2};
end
end

function v = local_num(override, params, key, defaultValue)
if ~isempty(override), v = double(override); return; end
if isfield(params, key)
    v = str2double(params.(key)); if isfinite(v), return; end
end
v = defaultValue;
end

function val = local_default(x, def)
if isempty(x), val = def; else, val = double(x); end
end

function box = local_resolve_object_box(optBox, params)
if ~isempty(optBox)
    if numel(optBox) ~= 4, error('ObjectBox must have four entries.'); end
    box = double(optBox(:).'); return;
end
cx = local_num([], params, 'immersedSolidCx', NaN); cy = local_num([], params, 'immersedSolidCy', NaN); r = local_num([], params, 'immersedSolidR', NaN);
if ~isfinite(cx) || ~isfinite(cy) || ~isfinite(r) || r <= 0
    cx = local_num([], params, 'darcyCircleCx', NaN); cy = local_num([], params, 'darcyCircleCy', NaN); r = local_num([], params, 'darcyCircleR', NaN);
end
if isfinite(cx) && isfinite(cy) && isfinite(r) && r > 0
    box = [cx-r cx+r cy-r cy+r];
else
    box = [];
end
end

function step = local_step_from_name(filename)
[~, base] = fileparts(filename);
tok = regexp(base, 'state_step_(\d+)', 'tokens', 'once');
if isempty(tok), step = NaN; else, step = str2double(tok{1}); end
end

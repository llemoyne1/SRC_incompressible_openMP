function suite = analyze_periodic_darcy_step_0493x7w(varargin)
%ANALYZE_PERIODIC_DARCY_STEP_0493X7W Causal SRC/Q6/Q6-g-f Darcy-step comparison.
%
% Post-process the three existing 0493x7w periodic Darcy backward-step runs.
% No solver run is launched and no simulation file is modified.
%
% The analyzer is deliberately organized around the causal question for the
% weak Von-Karman structures observed with Q6/Q6-g-f:
%   (i)  do the three modes see the same Darcy/chi resistance and interface?
%   (ii) do they generate the same vorticity at the downstream step edge?
%   (iii) if generation is comparable, is vorticity transported/surviving
%         differently downstream?
%   (iv) where does divergence appear, especially when q6A is large?
%
% The three modes are always discovered below ONE run root and the dump-step
% sets must be identical by default.  This prevents accidental mixing of dumps
% belonging to different cases.
%
% Required repository helpers (already present in matlab/):
%   read_smpcd_state.m
%   bin_smpcd_state.m
%   parse_smpcd_kv.m
%
% Typical use FROM matlab/:
%
%   suite = analyze_periodic_darcy_step_0493x7w( ...
%       'RunRoot', '../runs/0493x7w_periodic_darcy_step_512x128_g6_u0.9');
%
% Main outputs:
%   x7w_step_timeseries_0493x7w.csv
%   x7w_step_summary_0493x7w.csv
%   x7w_step_tau_aligned_0493x7w.csv
%   x7w_step_pairwise_tau_aligned_0493x7w.csv
%   x7w_step_tau_window_scalars_0493x7w.csv
%   x7w_step_tau_window_fields_0493x7w.csv
%   x7w_step_tau_window_pairwise_0493x7w.csv
%   x7w_step_audit_0493x7w.csv
%   x7w_step_sensitivity_0493x7w.csv             (when enabled)
%   x7w_step_suite_0493x7w.mat
%   PNG/PDF comparison figures                   (when enabled)
%
% IMPORTANT: comparisons are aligned on monotone convective age
%   tau_H = integral(U_e dt)/H,
% not on instantaneous U_e. Coherent recirculation/vorticity metrics are
% recomputed from tau-window-averaged normalized velocity fields.
%
% Geometry is recovered from the actual darcyChiFile (chi<0.5 = penalized)
% and checked across all three modes.  Therefore x7w geometry overrides are
% supported without hard-coding 0.32/0.64/0.064.
%
% 0493x7w runner contract relevant to interpretation:
%   src        : B0=0, B1=0
%   src-q6     : B0=0, B1=0
%   src-q6-g-f : B0=0, B1=1
% The environment audit is read when available and takes precedence over these
% fallback values.

p = inputParser;
p.FunctionName = 'analyze_periodic_darcy_step_0493x7w';
addParameter(p, 'RunRoot', '../runs/0493x7w_periodic_darcy_step_512x128_g6_u0.9', @(x) ischar(x) || isstring(x));
addParameter(p, 'OutputDir', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'Modes', {'src','src-q6','src-q6-g-f'}, @(x) iscell(x) || isstring(x));
addParameter(p, 'StrictTriplet', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'DumpStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'MaxDumps', Inf, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'FluidRole', 1, @(x) isnumeric(x) && isscalar(x));

% Primary and sensitivity binning.  H/16 gives 256x64 for the default x7w
% geometry: ~24 particles per analysis bin at gamma=6 while retaining 16 bins/H.
addParameter(p, 'AnalysisBinsPerH', 16, @(x) isnumeric(x) && isscalar(x) && x >= 6);
addParameter(p, 'SensitivityCheck', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'SensitivityBinsPerH', 12, @(x) isnumeric(x) && isscalar(x) && x >= 6);

% Incident-flow region, measured immediately upstream of the DOWNSTREAM edge
% while staying above the Darcy plateau and away from the top wall.
addParameter(p, 'IncidentXRangeH', [-1.5 -0.5], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'IncidentYRangeH', [1.5 3.5], @(x) isnumeric(x) && numel(x) == 2);

% Flat chi interface, excluding both vertical corners of the Darcy block.
addParameter(p, 'InterfaceEdgeMarginH', 1.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'InterfaceBandH', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);

% Penalized bulk region, kept away from wall/interface/corners.
addParameter(p, 'DarcyBulkXMarginH', 1.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'DarcyBulkYRangeH', [0.25 0.75], @(x) isnumeric(x) && numel(x) == 2);

% Vorticity/divergence regions expressed with downstream periodic coordinate
% s = mod(x-xEdge,Lx), where xEdge is the downstream step edge.
addParameter(p, 'GeneratorXRangeH', [0.0 0.75], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'GeneratorYRangeH', [0.50 2.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'NearWakeXRangeH', [0.75 3.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'MidWakeXRangeH', [3.00 6.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'FarWakeXRangeH', [6.00 10.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'WakeYRangeH', [0.125 2.50], @(x) isnumeric(x) && numel(x) == 2);

% Recirculation is evaluated in the lower part of the expanded channel.
addParameter(p, 'RecirculationXMaxH', 10.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'RecirculationYRangeH', [0.125 1.25], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'ReattachProbeYRangeH', [0.125 0.375], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'ReattachSearchStartH', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'ReattachHoldBins', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'ReattachSmoothBins', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);

% Convective-age alignment. tau_H is monotone by construction and is used
% for all cross-mode scalar comparisons. Instantaneous-Ue matching is
% intentionally NOT used because Ue(t) is non-monotone in this transient.
addParameter(p, 'MatchedTauLevels', 17, @(x) isnumeric(x) && isscalar(x) && x >= 3);
addParameter(p, 'SummaryTauRangeH', [1 Inf], @(x) isnumeric(x) && numel(x) == 2 && x(2) > x(1));

% Coherent-field averaging windows. Each velocity snapshot is first
% normalized by its own incident Ue, then averaged with tau_H Voronoi weights.
% Curl/divergence and recirculation are computed AFTER averaging.
addParameter(p, 'TauWindowsH', [1 3; 4 6; 7 9], ...
    @(x) isnumeric(x) && size(x,2) == 2 && all(x(:,2) > x(:,1)));

% Optional viscosity overrides. Fields: src, src_q6, src_q6_g_f.
% When the default x7w/x7t calibrated signature is detected, x7t viscosities
% are used automatically; otherwise ReH is left NaN unless overridden.
addParameter(p, 'ModeViscosities', struct(), @isstruct);
addParameter(p, 'AutoUseX7TViscosities', true, @(x) islogical(x) || isnumeric(x));

addParameter(p, 'MakePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ShowFigures', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'WritePdf', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

runRoot = char(opt.RunRoot);
if ~isfolder(runRoot)
    error('analyze_periodic_darcy_step_0493x7w:missingRunRoot', ...
        'Run root not found: %s', runRoot);
end

if strlength(string(opt.OutputDir)) == 0
    outDir = [runRoot '_analysis_0493x7w'];
else
    outDir = char(opt.OutputDir);
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

modes = cellstr(string(opt.Modes));
cases = local_resolve_cases(runRoot, modes);
if logical(opt.StrictTriplet) && numel(cases) ~= 3
    error('analyze_periodic_darcy_step_0493x7w:tripletRequired', ...
        'StrictTriplet requires src, src-q6 and src-q6-g-f under %s.', runRoot);
end

fprintf('[0493x7w-analysis] runRoot=%s\n', runRoot);
for i = 1:numel(cases)
    fprintf('[0493x7w-analysis]   mode=%-12s run=%s\n', cases(i).mode, cases(i).runDir);
end

% Recover actual geometry from chi and make sure the triplet is the same case.
geom = local_geometry_from_case(cases(1));
for i = 2:numel(cases)
    gi = local_geometry_from_case(cases(i));
    local_assert_same_geometry(geom, gi, cases(1).mode, cases(i).mode);
end

fprintf('[0493x7w-analysis] geometry L=%.6gx%.6g native=%dx%d H=%.6g xBlock=[%.6g,%.6g] yBlock=[%.6g,%.6g]\n', ...
    geom.Lx, geom.Ly, geom.Nx, geom.Ny, geom.H, geom.xMin, geom.xMax, geom.yMin, geom.yMax);
fprintf('[0493x7w-analysis] downstream periodic clearance = %.6g H\n', geom.downstreamClearance / geom.H);

% Discover frame sets before reading particle payloads.  Strict mode requires
% exactly the same dump steps in all three modes.
allFrames = cell(numel(cases),1);
for i = 1:numel(cases)
    allFrames{i} = local_list_frames(cases(i).outputDir, cases(i).dt, opt.DumpStride, opt.MaxDumps);
end
commonSteps = local_common_steps(allFrames, cases, logical(opt.StrictTriplet));
if isempty(commonSteps)
    error('analyze_periodic_darcy_step_0493x7w:noCommonDumps', 'No common dump step exists across requested modes.');
end
fprintf('[0493x7w-analysis] common dumps=%d step=[%g..%g]\n', numel(commonSteps), commonSteps(1), commonSteps(end));

% Audit includes B0/B1, physical parameters, chi signature and dump coverage.
audit = local_build_audit(cases, geom, allFrames, commonSteps);
writetable(audit, fullfile(outDir, 'x7w_step_audit_0493x7w.csv'));

results = cell(numel(cases),1);
tables = cell(numel(cases),1);
sensTables = cell(numel(cases),1);
for i = 1:numel(cases)
    fprintf('\n[0493x7w-analysis] ===== %s =====\n', cases(i).mode);
    results{i} = local_analyze_case(cases(i), geom, allFrames{i}, commonSteps, opt);
    tables{i} = results{i}.timeseries;
    sensTables{i} = results{i}.sensitivity;
end

T = vertcat(tables{:});
writetable(T, fullfile(outDir, 'x7w_step_timeseries_0493x7w.csv'));

if logical(opt.SensitivityCheck)
    nonempty = ~cellfun(@isempty, sensTables);
    if any(nonempty)
        Q = vertcat(sensTables{nonempty});
        writetable(Q, fullfile(outDir, 'x7w_step_sensitivity_0493x7w.csv'));
    else
        Q = table();
    end
else
    Q = table();
end

% Remove legacy same-Ue products from the previous analyzer revision so a
% rerun cannot leave misleading files next to the tau-aligned results.
local_remove_legacy_outputs(outDir);

tauAligned = local_build_tau_aligned(T, modes, round(opt.MatchedTauLevels), opt.SummaryTauRangeH);
writetable(tauAligned, fullfile(outDir, 'x7w_step_tau_aligned_0493x7w.csv'));
tauPairwise = local_build_pairwise_tau_aligned(tauAligned, 'src');
writetable(tauPairwise, fullfile(outDir, 'x7w_step_pairwise_tau_aligned_0493x7w.csv'));

tauWindowScalars = local_build_tau_window_scalars(T, modes, double(opt.TauWindowsH));
writetable(tauWindowScalars, fullfile(outDir, 'x7w_step_tau_window_scalars_0493x7w.csv'));

[tauWindowFields, tauWindowFieldMetrics] = local_build_tau_window_fields(cases, results, geom, opt);
writetable(tauWindowFieldMetrics, fullfile(outDir, 'x7w_step_tau_window_fields_0493x7w.csv'));

tauWindowPairwise = local_build_tau_window_pairwise(tauWindowScalars, tauWindowFieldMetrics, 'src');
writetable(tauWindowPairwise, fullfile(outDir, 'x7w_step_tau_window_pairwise_0493x7w.csv'));

summary = local_build_summary(T, tauPairwise, cases, geom, opt);
writetable(summary, fullfile(outDir, 'x7w_step_summary_0493x7w.csv'));

suite = struct();
suite.runRoot = runRoot;
suite.outputDir = outDir;
suite.options = opt;
suite.geometry = geom;
suite.cases = cases;
suite.audit = audit;
suite.results = results;
suite.timeseries = T;
suite.sensitivity = Q;
suite.tauAligned = tauAligned;
suite.tauPairwise = tauPairwise;
suite.tauWindowScalars = tauWindowScalars;
suite.tauWindowFields = tauWindowFields;
suite.tauWindowFieldMetrics = tauWindowFieldMetrics;
suite.tauWindowPairwise = tauWindowPairwise;
suite.summary = summary;
save(fullfile(outDir, 'x7w_step_suite_0493x7w.mat'), 'suite', '-v7.3');

if logical(opt.MakePlots)
    local_plot_timeseries(T, modes, geom, opt, outDir);
    local_plot_solver_diagnostics(T, modes, opt, outDir);
    local_plot_tau_aligned(tauPairwise, modes, opt, outDir);
    local_plot_tau_window_metrics(tauWindowPairwise, modes, opt, outDir);
    local_plot_tau_window_fields(tauWindowFields, tauWindowFieldMetrics, cases, geom, opt, outDir);
end

local_print_summary(summary, tauPairwise, tauWindowFieldMetrics, tauWindowPairwise, geom, outDir);
end

% =========================================================================
% Per-mode analysis
% =========================================================================
function result = local_analyze_case(c, geom, frames, commonSteps, opt)
keep = ismember(frames.step, commonSteps);
frames = frames(keep,:);

H = geom.H;
analysisDx = H / double(opt.AnalysisBinsPerH);
NxA = max(16, round(geom.Lx / analysisDx));
NyA = max(8, round(geom.Ly / analysisDx));
if logical(opt.SensitivityCheck)
    sensDx = H / double(opt.SensitivityBinsPerH);
    NxS = max(16, round(geom.Lx / sensDx));
    NyS = max(8, round(geom.Ly / sensDx));
else
    NxS = NaN; NyS = NaN;
end

[nu, nuSource] = local_resolve_viscosity(c.mode, c.params, c.dt, opt);
logT = local_parse_solver_log(c.logFile);
darcyT = local_read_optional_csv(fullfile(c.outputDir,'darcy_cost_0343.csv'));

rows = repmat(local_empty_row(), height(frames), 1);
srows = repmat(local_empty_sensitivity_row(), height(frames), 1);
prevT = NaN; prevUe = NaN; tauH = 0.0; tauL = 0.0;

for k = 1:height(frames)
    st = read_smpcd_state(char(frames.fullPath(k)));
    fld = bin_smpcd_state(st, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', NxA, 'Ny', NyA, ...
        'periodicX', true, 'periodicY', false, 'fluidOnly', true);
    [fld.omega, fld.divergence] = local_curl_divergence(fld.Ux, fld.Uy, fld.dx, fld.dy, true, false);

    row = local_frame_metrics(st, fld, c, geom, frames.step(k), frames.time(k), nu, nuSource, opt);
    if k > 1 && isfinite(prevT) && isfinite(prevUe) && isfinite(row.Ue)
        dtt = max(0, row.time - prevT);
        distance = 0.5 * (max(prevUe,0) + max(row.Ue,0)) * dtt;
        tauH = tauH + distance / H;
        tauL = tauL + distance / geom.Lx;
    end
    row.tauH = tauH;
    row.tauL = tauL;
    row = local_attach_log_metrics(row, logT);
    row = local_attach_darcy_csv_metrics(row, darcyT);
    rows(k) = row;

    if logical(opt.SensitivityCheck)
        fs = bin_smpcd_state(st, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', NxS, 'Ny', NyS, ...
            'periodicX', true, 'periodicY', false, 'fluidOnly', true);
        [fs.omega, fs.divergence] = local_curl_divergence(fs.Ux, fs.Uy, fs.dx, fs.dy, true, false);
        srows(k) = local_sensitivity_metrics(fs, row, c, geom, opt, NxA, NyA, NxS, NyS);
    end

    fprintf('[0493x7w-analysis] %-12s %2d/%2d step=%4g Ue=% .5f ReH=%7s tauH=%5.2f ', ...
        c.mode, k, height(frames), row.step, row.Ue, local_num_string(row.ReH), row.tauH);
    fprintf('Darcy/Ue=% .4f slip=% .4f Ggen*=% .4g Gnear*=% .4g Sgn=% .4g divNear*=% .4g Lr/H=%s\n', ...
        row.darcyUxOverUe, row.interfaceSlipRatio, row.gammaAbsGeneratorStar, row.gammaAbsNearStar, ...
        row.survivalGeneratorToNear, row.divNearStar, local_num_string(row.reattachLengthH));

    prevT = row.time; prevUe = row.Ue;
end

T = struct2table(rows);
if logical(opt.SensitivityCheck)
    ST = struct2table(srows);
else
    ST = table();
end

result = struct();
result.case = c;
result.frames = frames;
result.timeseries = T;
result.sensitivity = ST;
result.nu = nu;
result.nuSource = nuSource;
result.analysisGrid = [NxA NyA];
result.sensitivityGrid = [NxS NyS];
end

function row = local_frame_metrics(st, fld, c, geom, step, time, nu, nuSource, opt)
H = geom.H;
[X,Y] = meshgrid(fld.xc, fld.yc);
S = mod(X - geom.xEdge, geom.Lx);

% Incident velocity: particle-space mass weighted mean for low thermal noise and
% independence from the post-processing bin size.
incidentBox = [ ...
    geom.xEdge + double(opt.IncidentXRangeH(1))*H, ...
    geom.xEdge + double(opt.IncidentXRangeH(2))*H, ...
    double(opt.IncidentYRangeH(1))*H, ...
    min(geom.Ly, double(opt.IncidentYRangeH(2))*H)];
[Ue,UeY,incidentMass,incidentParticles] = local_particle_region_velocity_periodic(st, incidentBox, geom.Lx, opt.FluidRole);
[UglobalX,UglobalY,totalMass] = local_global_velocity(st,opt.FluidRole);
if ~isfinite(Ue), Ue = UglobalX; end
if ~isfinite(UeY), UeY = UglobalY; end
scaleU = max(abs(Ue),1e-12);

% Actual chi sampled on the analysis grid by geometry.  x7w is a rectangular
% penalized block; the geometry itself was recovered from the chi file.
penalized = X >= geom.xMin & X <= geom.xMax & Y >= geom.yMin & Y <= geom.yMax;
free = ~penalized;

% Flat-interface response, far from both vertical corners.
xFlat0 = geom.xMin + double(opt.InterfaceEdgeMarginH)*H;
xFlat1 = geom.xMax - double(opt.InterfaceEdgeMarginH)*H;
flatX = X >= xFlat0 & X <= xFlat1;
above = flatX & Y >= geom.yMax & Y < geom.yMax + double(opt.InterfaceBandH)*H;
below = flatX & Y <= geom.yMax & Y > geom.yMax - double(opt.InterfaceBandH)*H;

UtAbove = local_mean_field(fld.Ux,above);
UtBelow = local_mean_field(fld.Ux,below);
UnAboveRms = local_rms_field(fld.Uy,above);
UnBelowRms = local_rms_field(fld.Uy,below);
if isfinite(UtAbove) && abs(UtAbove)>1e-12
    slipRatio = UtBelow/UtAbove;
else
    slipRatio = NaN;
end

% Penalized bulk response.
darcyBulk = X >= geom.xMin + double(opt.DarcyBulkXMarginH)*H & ...
            X <= geom.xMax - double(opt.DarcyBulkXMarginH)*H & ...
            Y >= double(opt.DarcyBulkYRangeH(1))*H & ...
            Y <= double(opt.DarcyBulkYRangeH(2))*H;
darcyUx = local_mean_field(fld.Ux,darcyBulk);
darcyUy = local_mean_field(fld.Uy,darcyBulk);
darcySpeed = local_mean_field(fld.speed,darcyBulk);
darcyUyRms = local_rms_field(fld.Uy,darcyBulk);

% Wake/generator masks.  Exclude the penalized block explicitly; downstream s
% is periodic and therefore remains valid across x=Lx -> 0.
gen = local_srange_mask(S,double(opt.GeneratorXRangeH)*H) & ...
      Y >= double(opt.GeneratorYRangeH(1))*H & Y <= double(opt.GeneratorYRangeH(2))*H & free;
near = local_srange_mask(S,double(opt.NearWakeXRangeH)*H) & ...
       Y >= double(opt.WakeYRangeH(1))*H & Y <= double(opt.WakeYRangeH(2))*H & free;
mid = local_srange_mask(S,double(opt.MidWakeXRangeH)*H) & ...
      Y >= double(opt.WakeYRangeH(1))*H & Y <= double(opt.WakeYRangeH(2))*H & free;
far = local_srange_mask(S,double(opt.FarWakeXRangeH)*H) & ...
      Y >= double(opt.WakeYRangeH(1))*H & Y <= double(opt.WakeYRangeH(2))*H & free;

cellArea = fld.dx*fld.dy;
wg = local_field_stats(fld.omega,gen,cellArea);
wn = local_field_stats(fld.omega,near,cellArea);
wm = local_field_stats(fld.omega,mid,cellArea);
wf = local_field_stats(fld.omega,far,cellArea);
dg = local_field_stats(fld.divergence,gen,cellArea);
dn = local_field_stats(fld.divergence,near,cellArea);
dm = local_field_stats(fld.divergence,mid,cellArea);
df = local_field_stats(fld.divergence,far,cellArea);

% Survival ratios are based on integrated |omega|.  They deliberately compare
% transport to generation rather than raw peak values.
SgenNear = local_safe_ratio(wn.absIntegral,wg.absIntegral);
SnearMid = local_safe_ratio(wm.absIntegral,wn.absIntegral);
SmidFar = local_safe_ratio(wf.absIntegral,wm.absIntegral);

% Cross-section transport index: mean over a narrow x-band of integral |omega|dy.
% Unlike area-content ratios, this is not inflated merely because the downstream
% region is longer.  Stations 0.5H, 1.5H and 3H are chosen to remain useful in
% this short unforced transient.
sec05 = local_cross_section_abs(fld.omega,S,Y,0.5*H,0.125*H,double(opt.WakeYRangeH)*H,fld.dy);
sec15 = local_cross_section_abs(fld.omega,S,Y,1.5*H,0.125*H,double(opt.WakeYRangeH)*H,fld.dy);
sec30 = local_cross_section_abs(fld.omega,S,Y,3.0*H,0.125*H,double(opt.WakeYRangeH)*H,fld.dy);
secSurv15 = local_safe_ratio(sec15,sec05);
secSurv30 = local_safe_ratio(sec30,sec05);

% Solenoidal-vs-compressive diagnostic using the same spatial masks.
rotGen = local_rotation_fraction(fld.omega,fld.divergence,gen);
rotNear = local_rotation_fraction(fld.omega,fld.divergence,near);
rotMid = local_rotation_fraction(fld.omega,fld.divergence,mid);
rotFar = local_rotation_fraction(fld.omega,fld.divergence,far);

% Transverse organized velocity after particle thermal noise has been binned.
uyGen = local_rms_field(fld.Uy,gen);
uyNear = local_rms_field(fld.Uy,near);
uyMid = local_rms_field(fld.Uy,mid);
uyFar = local_rms_field(fld.Uy,far);

% Recirculation bubble and reattachment near the lower wall.
recircMask = S >= 0 & S <= double(opt.RecirculationXMaxH)*H & ...
             Y >= double(opt.RecirculationYRangeH(1))*H & ...
             Y <= double(opt.RecirculationYRangeH(2))*H & free;
neg = recircMask & isfinite(fld.Ux) & fld.Ux < 0;
recircArea = nnz(neg)*cellArea;
vals = fld.Ux(recircMask); vals = vals(isfinite(vals));
if isempty(vals), uxMin = NaN; else, uxMin = min(vals); end
reattachH = local_reattachment_length(fld,S,Y,geom,opt);

if isfinite(nu) && nu>0, ReH=Ue*H/nu; else, ReH=NaN; end

row = local_empty_row();
row.mode = string(c.mode);
row.runDir = string(c.runDir);
row.step = step;
row.time = time;
row.tauH = NaN;
row.tauL = NaN;
row.nu = nu;
row.nuSource = string(nuSource);
row.B0 = c.B0;
row.B1 = c.B1;
row.UglobalX = UglobalX;
row.UglobalY = UglobalY;
row.totalFluidMass = totalMass;
row.Ue = Ue;
row.UeY = UeY;
row.incidentMass = incidentMass;
row.incidentParticles = incidentParticles;
row.ReH = ReH;
row.darcyUx = darcyUx;
row.darcyUy = darcyUy;
row.darcySpeed = darcySpeed;
row.darcyUyRms = darcyUyRms;
row.darcyUxOverUe = darcyUx/scaleU;
row.darcySpeedOverUe = darcySpeed/scaleU;
row.darcyUyRmsOverUe = darcyUyRms/scaleU;
row.interfaceUtAbove = UtAbove;
row.interfaceUtBelow = UtBelow;
row.interfaceSlipRatio = slipRatio;
row.interfaceUnAboveRms = UnAboveRms;
row.interfaceUnBelowRms = UnBelowRms;
row.interfaceUnAboveRmsOverUe = UnAboveRms/scaleU;
row.interfaceUnBelowRmsOverUe = UnBelowRms/scaleU;
row.omegaGeneratorRms = wg.rms;
row.omegaNearRms = wn.rms;
row.omegaMidRms = wm.rms;
row.omegaFarRms = wf.rms;
row.omegaGeneratorStar = wg.rms*H/scaleU;
row.omegaNearStar = wn.rms*H/scaleU;
row.omegaMidStar = wm.rms*H/scaleU;
row.omegaFarStar = wf.rms*H/scaleU;
row.gammaPosGenerator = wg.posIntegral;
row.gammaNegGenerator = wg.negIntegral;
row.gammaAbsGenerator = wg.absIntegral;
row.gammaAbsNear = wn.absIntegral;
row.gammaAbsMid = wm.absIntegral;
row.gammaAbsFar = wf.absIntegral;
row.gammaAbsGeneratorStar = wg.absIntegral/(scaleU*H);
row.gammaAbsNearStar = wn.absIntegral/(scaleU*H);
row.gammaAbsMidStar = wm.absIntegral/(scaleU*H);
row.gammaAbsFarStar = wf.absIntegral/(scaleU*H);
row.survivalGeneratorToNear = SgenNear;
row.survivalNearToMid = SnearMid;
row.survivalMidToFar = SmidFar;
row.vorticitySection0p5Star = sec05/scaleU;
row.vorticitySection1p5Star = sec15/scaleU;
row.vorticitySection3p0Star = sec30/scaleU;
row.sectionSurvival0p5To1p5 = secSurv15;
row.sectionSurvival0p5To3p0 = secSurv30;
row.divGeneratorRms = dg.rms;
row.divNearRms = dn.rms;
row.divMidRms = dm.rms;
row.divFarRms = df.rms;
row.divGeneratorStar = dg.rms*H/scaleU;
row.divNearStar = dn.rms*H/scaleU;
row.divMidStar = dm.rms*H/scaleU;
row.divFarStar = df.rms*H/scaleU;
row.rotationFractionGenerator = rotGen;
row.rotationFractionNear = rotNear;
row.rotationFractionMid = rotMid;
row.rotationFractionFar = rotFar;
row.uyGeneratorRmsOverUe = uyGen/scaleU;
row.uyNearRmsOverUe = uyNear/scaleU;
row.uyMidRmsOverUe = uyMid/scaleU;
row.uyFarRmsOverUe = uyFar/scaleU;
row.recirculationArea = recircArea;
row.recirculationAreaOverH2 = recircArea/(H*H);
row.recirculationUxMin = uxMin;
row.recirculationUxMinOverUe = uxMin/scaleU;
row.reattachLengthH = reattachH;
end

function row = local_empty_row()
row = struct( ...
    'mode',"",'runDir',"",'step',NaN,'time',NaN,'tauH',NaN,'tauL',NaN, ...
    'nu',NaN,'nuSource',"",'B0',NaN,'B1',NaN, ...
    'UglobalX',NaN,'UglobalY',NaN,'totalFluidMass',NaN, ...
    'Ue',NaN,'UeY',NaN,'incidentMass',NaN,'incidentParticles',NaN,'ReH',NaN, ...
    'darcyUx',NaN,'darcyUy',NaN,'darcySpeed',NaN,'darcyUyRms',NaN, ...
    'darcyUxOverUe',NaN,'darcySpeedOverUe',NaN,'darcyUyRmsOverUe',NaN, ...
    'interfaceUtAbove',NaN,'interfaceUtBelow',NaN,'interfaceSlipRatio',NaN, ...
    'interfaceUnAboveRms',NaN,'interfaceUnBelowRms',NaN, ...
    'interfaceUnAboveRmsOverUe',NaN,'interfaceUnBelowRmsOverUe',NaN, ...
    'omegaGeneratorRms',NaN,'omegaNearRms',NaN,'omegaMidRms',NaN,'omegaFarRms',NaN, ...
    'omegaGeneratorStar',NaN,'omegaNearStar',NaN,'omegaMidStar',NaN,'omegaFarStar',NaN, ...
    'gammaPosGenerator',NaN,'gammaNegGenerator',NaN, ...
    'gammaAbsGenerator',NaN,'gammaAbsNear',NaN,'gammaAbsMid',NaN,'gammaAbsFar',NaN, ...
    'gammaAbsGeneratorStar',NaN,'gammaAbsNearStar',NaN,'gammaAbsMidStar',NaN,'gammaAbsFarStar',NaN, ...
    'survivalGeneratorToNear',NaN,'survivalNearToMid',NaN,'survivalMidToFar',NaN, ...
    'vorticitySection0p5Star',NaN,'vorticitySection1p5Star',NaN,'vorticitySection3p0Star',NaN, ...
    'sectionSurvival0p5To1p5',NaN,'sectionSurvival0p5To3p0',NaN, ...
    'divGeneratorRms',NaN,'divNearRms',NaN,'divMidRms',NaN,'divFarRms',NaN, ...
    'divGeneratorStar',NaN,'divNearStar',NaN,'divMidStar',NaN,'divFarStar',NaN, ...
    'rotationFractionGenerator',NaN,'rotationFractionNear',NaN,'rotationFractionMid',NaN,'rotationFractionFar',NaN, ...
    'uyGeneratorRmsOverUe',NaN,'uyNearRmsOverUe',NaN,'uyMidRmsOverUe',NaN,'uyFarRmsOverUe',NaN, ...
    'recirculationArea',NaN,'recirculationAreaOverH2',NaN,'recirculationUxMin',NaN,'recirculationUxMinOverUe',NaN, ...
    'reattachLengthH',NaN, ...
    'kBTlog',NaN,'stdNlog',NaN,'resMlog',NaN,'q6Flog',NaN,'q6Alog',NaN, ...
    'darcyPowerCsv',NaN,'darcyPowerPerMassCsv',NaN,'solidLeakRmsCsv',NaN,'meanSpeedRmsCsv',NaN,'meanChiCsv',NaN,'meanAlphaCsv',NaN);
end

% =========================================================================
% Sensitivity binning
% =========================================================================
function s = local_sensitivity_metrics(fld, primary, c, geom, opt, NxA, NyA, NxS, NyS)
H=geom.H; [X,Y]=meshgrid(fld.xc,fld.yc); S=mod(X-geom.xEdge,geom.Lx);
penalized=X>=geom.xMin & X<=geom.xMax & Y>=geom.yMin & Y<=geom.yMax; free=~penalized;
gen=local_srange_mask(S,double(opt.GeneratorXRangeH)*H) & Y>=double(opt.GeneratorYRangeH(1))*H & Y<=double(opt.GeneratorYRangeH(2))*H & free;
near=local_srange_mask(S,double(opt.NearWakeXRangeH)*H) & Y>=double(opt.WakeYRangeH(1))*H & Y<=double(opt.WakeYRangeH(2))*H & free;
scaleU=max(abs(primary.Ue),1e-12); dA=fld.dx*fld.dy;
wg=local_field_stats(fld.omega,gen,dA); wn=local_field_stats(fld.omega,near,dA);
dg=local_field_stats(fld.divergence,gen,dA); dn=local_field_stats(fld.divergence,near,dA);
s=local_empty_sensitivity_row();
s.mode=string(c.mode); s.step=primary.step;
s.primaryNx=NxA; s.primaryNy=NyA; s.sensitivityNx=NxS; s.sensitivityNy=NyS;
s.gammaAbsGeneratorStarPrimary=primary.gammaAbsGeneratorStar;
s.gammaAbsGeneratorStarSensitivity=wg.absIntegral/(scaleU*H);
s.gammaAbsGeneratorStarRelDiff=local_rel_diff(s.gammaAbsGeneratorStarSensitivity,s.gammaAbsGeneratorStarPrimary);
s.gammaAbsNearStarPrimary=primary.gammaAbsNearStar;
s.gammaAbsNearStarSensitivity=wn.absIntegral/(scaleU*H);
s.gammaAbsNearStarRelDiff=local_rel_diff(s.gammaAbsNearStarSensitivity,s.gammaAbsNearStarPrimary);
s.omegaGeneratorStarPrimary=primary.omegaGeneratorStar;
s.omegaGeneratorStarSensitivity=wg.rms*H/scaleU;
s.omegaGeneratorStarRelDiff=local_rel_diff(s.omegaGeneratorStarSensitivity,s.omegaGeneratorStarPrimary);
s.omegaNearStarPrimary=primary.omegaNearStar;
s.omegaNearStarSensitivity=wn.rms*H/scaleU;
s.omegaNearStarRelDiff=local_rel_diff(s.omegaNearStarSensitivity,s.omegaNearStarPrimary);
s.divGeneratorStarPrimary=primary.divGeneratorStar;
s.divGeneratorStarSensitivity=dg.rms*H/scaleU;
s.divGeneratorStarRelDiff=local_rel_diff(s.divGeneratorStarSensitivity,s.divGeneratorStarPrimary);
s.divNearStarPrimary=primary.divNearStar;
s.divNearStarSensitivity=dn.rms*H/scaleU;
s.divNearStarRelDiff=local_rel_diff(s.divNearStarSensitivity,s.divNearStarPrimary);
end

function s=local_empty_sensitivity_row()
s=struct('mode',"",'step',NaN,'primaryNx',NaN,'primaryNy',NaN,'sensitivityNx',NaN,'sensitivityNy',NaN, ...
    'gammaAbsGeneratorStarPrimary',NaN,'gammaAbsGeneratorStarSensitivity',NaN,'gammaAbsGeneratorStarRelDiff',NaN, ...
    'gammaAbsNearStarPrimary',NaN,'gammaAbsNearStarSensitivity',NaN,'gammaAbsNearStarRelDiff',NaN, ...
    'omegaGeneratorStarPrimary',NaN,'omegaGeneratorStarSensitivity',NaN,'omegaGeneratorStarRelDiff',NaN, ...
    'omegaNearStarPrimary',NaN,'omegaNearStarSensitivity',NaN,'omegaNearStarRelDiff',NaN, ...
    'divGeneratorStarPrimary',NaN,'divGeneratorStarSensitivity',NaN,'divGeneratorStarRelDiff',NaN, ...
    'divNearStarPrimary',NaN,'divNearStarSensitivity',NaN,'divNearStarRelDiff',NaN);
end

% =========================================================================
% tau_H alignment, coherent tau-window fields and pairwise tables
% =========================================================================
function M = local_build_tau_aligned(T,modes,nLevels,summaryTauRange)
mins=nan(numel(modes),1); maxs=mins;
for i=1:numel(modes)
    v=T.tauH(T.mode==string(modes{i}) & isfinite(T.tauH));
    if ~isempty(v), mins(i)=min(v); maxs(i)=max(v); end
end
if any(~isfinite(mins)) || any(~isfinite(maxs))
    warning('0493x7w:tauAlignUnavailable','Cannot build tau_H aligned table: one mode has no finite tauH.');
    M=table(); return;
end
lo=max(mins); hi=min(maxs);
if numel(summaryTauRange)==2
    lo=max(lo,double(summaryTauRange(1)));
    if isfinite(summaryTauRange(2)), hi=min(hi,double(summaryTauRange(2))); end
end
if ~(isfinite(lo)&&isfinite(hi)&&hi>lo)
    warning('0493x7w:noTauOverlap','No common tau_H interval across modes.'); M=table(); return;
end
targets=linspace(lo,hi,nLevels);
rows={};
for j=1:numel(targets)
    target=targets(j);
    for i=1:numel(modes)
        A=T(T.mode==string(modes{i}) & isfinite(T.tauH),:);
        A=sortrows(A,'tauH');
        [~,ia]=unique(A.tauH,'stable'); A=A(ia,:);
        if isempty(A), continue; end
        [~,kn]=min(abs(A.tauH-target)); r=A(kn,:);
        vars=A.Properties.VariableNames;
        for iv=1:numel(vars)
            f=vars{iv}; col=A.(f);
            if isnumeric(col) && isvector(col)
                y=double(col); good=isfinite(A.tauH) & isfinite(y);
                if nnz(good)>=2
                    r.(f)=interp1(A.tauH(good),y(good),target,'linear',NaN);
                elseif nnz(good)==1
                    r.(f)=y(find(good,1,'first'));
                end
            end
        end
        r.matchLevel=j; %#ok<AGROW>
        r.targetTauH=target;
        r.sourceNearestStep=A.step(kn);
        r.sourceNearestTauH=A.tauH(kn);
        r.absNearestTauMismatch=abs(A.tauH(kn)-target);
        rows{end+1,1}=r; %#ok<AGROW>
    end
end
if isempty(rows), M=table(); return; end
M=vertcat(rows{:});
front={'matchLevel','targetTauH','mode','sourceNearestStep','sourceNearestTauH','absNearestTauMismatch','step','time','tauH','Ue','ReH'};
rest=setdiff(M.Properties.VariableNames,front,'stable');
M=M(:,[front rest]);
end

function P = local_build_pairwise_tau_aligned(M,referenceMode)
if isempty(M), P=table(); return; end
metrics={ ...
    'darcyUxOverUe','darcySpeedOverUe','darcyUyRmsOverUe', ...
    'interfaceSlipRatio','interfaceUnAboveRmsOverUe','interfaceUnBelowRmsOverUe', ...
    'gammaAbsGeneratorStar','gammaAbsNearStar','gammaAbsMidStar','gammaAbsFarStar', ...
    'survivalGeneratorToNear','survivalNearToMid','survivalMidToFar', ...
    'vorticitySection0p5Star','vorticitySection1p5Star','vorticitySection3p0Star', ...
    'sectionSurvival0p5To1p5','sectionSurvival0p5To3p0', ...
    'omegaGeneratorStar','omegaNearStar','omegaMidStar','omegaFarStar', ...
    'divGeneratorStar','divNearStar','divMidStar','divFarStar', ...
    'rotationFractionGenerator','rotationFractionNear','rotationFractionMid','rotationFractionFar', ...
    'uyGeneratorRmsOverUe','uyNearRmsOverUe','uyMidRmsOverUe','uyFarRmsOverUe', ...
    'darcyPowerPerMassCsv','solidLeakRmsCsv','meanSpeedRmsCsv','kBTlog'};
levels=unique(M.matchLevel);
comparisons=unique(M.mode,'stable'); comparisons=comparisons(comparisons~=string(referenceMode));
modeCol=strings(0,1); levelCol=[]; target=[]; metricCol=strings(0,1); refVal=[]; cmpVal=[]; ratio=[]; relDiff=[];
for il=1:numel(levels)
    ref=M(M.matchLevel==levels(il) & M.mode==string(referenceMode),:);
    if isempty(ref), continue; end
    for ic=1:numel(comparisons)
        cmp=M(M.matchLevel==levels(il) & M.mode==comparisons(ic),:);
        if isempty(cmp), continue; end
        for im=1:numel(metrics)
            f=metrics{im}; if ~ismember(f,M.Properties.VariableNames), continue; end
            a=ref.(f)(1); b=cmp.(f)(1);
            modeCol(end+1,1)=comparisons(ic); %#ok<AGROW>
            levelCol(end+1,1)=levels(il); target(end+1,1)=ref.targetTauH(1); %#ok<AGROW>
            metricCol(end+1,1)=string(f); refVal(end+1,1)=a; cmpVal(end+1,1)=b; %#ok<AGROW>
            ratio(end+1,1)=local_safe_ratio(b,a); relDiff(end+1,1)=local_rel_diff(b,a); %#ok<AGROW>
        end
    end
end
P=table(modeCol,levelCol,target,metricCol,refVal,cmpVal,ratio,relDiff, ...
    'VariableNames',{'mode','matchLevel','targetTauH','metric','srcValue','modeValue','ratioToSrc','relativeDifferenceToSrc'});
end

function W = local_build_tau_window_scalars(T,modes,windows)
% Use one canonical structure schema for every row.  MATLAB rejects indexed
% assignment between structs whose field sets/order differ, so do not build
% rows incrementally from struct() here.
prototype=local_empty_tau_window_scalar_row("",0,NaN,NaN);
nRows=size(windows,1)*numel(modes);
rows=repmat(prototype,nRows,1); n=0;
for iw=1:size(windows,1)
    a=windows(iw,1); b=windows(iw,2);
    for im=1:numel(modes)
        A=T(T.mode==string(modes{im}) & isfinite(T.tauH),:); A=sortrows(A,'tauH');
        [weights,coverage]=local_tau_voronoi_weights(A.tauH,a,b);
        use=weights>0; sw=sum(weights(use));
        n=n+1; r=local_empty_tau_window_scalar_row(modes{im},iw,a,b);
        r.coverageTauH=coverage; r.coverageFraction=coverage/max(b-a,eps); r.nFramesContributing=nnz(use);
        if sw>0
            wn=weights/sw; r.effectiveFrames=1/sum(wn(use).^2);
        else
            r.effectiveFrames=0;
        end
        r.meanUe=local_weighted_column(A.Ue,weights);
        r.meanReH=local_weighted_column(A.ReH,weights);
        r.meanDarcyPowerPerMassCsv=local_weighted_column(A.darcyPowerPerMassCsv,weights);
        r.meanSolidLeakRmsCsv=local_weighted_column(A.solidLeakRmsCsv,weights);
        r.meanDarcySpeedRmsCsv=local_weighted_column(A.meanSpeedRmsCsv,weights);
        r.meanDarcyUxOverUe=local_weighted_column(A.darcyUxOverUe,weights);
        r.meanInterfaceSlipRatio=local_weighted_column(A.interfaceSlipRatio,weights);
        r.meanInterfaceLeakAboveOverUe=local_weighted_column(A.interfaceUnAboveRmsOverUe,weights);
        r.meanInstantGammaGeneratorStar=local_weighted_column(A.gammaAbsGeneratorStar,weights);
        r.meanInstantGammaNearStar=local_weighted_column(A.gammaAbsNearStar,weights);
        r.meanInstantSectionSurvival0p5To1p5=local_weighted_column(A.sectionSurvival0p5To1p5,weights);
        r.meanInstantDivNearStar=local_weighted_column(A.divNearStar,weights);
        r.meanInstantUyNearRmsOverUe=local_weighted_column(A.uyNearRmsOverUe,weights);
        rows(n)=r;
    end
end
if n==0
    W=table();
else
    rows=rows(1:n);
    W=struct2table(rows);
end
end

function r = local_empty_tau_window_scalar_row(mode,iw,a,b)
r=struct('mode',string(mode),'windowId',iw,'tauStart',a,'tauEnd',b, ...
    'coverageTauH',0,'coverageFraction',0,'nFramesContributing',0,'effectiveFrames',0, ...
    'meanUe',NaN,'meanReH',NaN,'meanDarcyPowerPerMassCsv',NaN,'meanSolidLeakRmsCsv',NaN, ...
    'meanDarcySpeedRmsCsv',NaN,'meanDarcyUxOverUe',NaN,'meanInterfaceSlipRatio',NaN, ...
    'meanInterfaceLeakAboveOverUe',NaN,'meanInstantGammaGeneratorStar',NaN,'meanInstantGammaNearStar',NaN, ...
    'meanInstantSectionSurvival0p5To1p5',NaN,'meanInstantDivNearStar',NaN,'meanInstantUyNearRmsOverUe',NaN);
end

function [F,W] = local_build_tau_window_fields(cases,results,geom,opt)
windows=double(opt.TauWindowsH);
nTotal=size(windows,1)*numel(cases);
F=cell(nTotal,1);
rowPrototype=local_empty_window_field_row("",0,NaN,NaN);
rows=repmat(rowPrototype,nTotal,1);
n=0;
dxTarget=geom.H/double(opt.AnalysisBinsPerH); nx=max(16,round(geom.Lx/dxTarget)); ny=max(8,round(geom.Ly/dxTarget));
for iw=1:size(windows,1)
    a=windows(iw,1); b=windows(iw,2);
    for im=1:numel(cases)
        A=results{im}.timeseries; A=sortrows(A,'tauH');
        [weights,coverage]=local_tau_voronoi_weights(A.tauH,a,b);
        use=find(weights>0 & isfinite(A.Ue) & abs(A.Ue)>1e-12);
        n=n+1;
        entry=struct('mode',string(cases(im).mode),'windowId',iw,'tauStart',a,'tauEnd',b, ...
            'coverageTauH',coverage,'coverageFraction',coverage/max(b-a,eps),'nFramesContributing',numel(use), ...
            'effectiveFrames',0,'field',[]);
        if isempty(use)
            warning('0493x7w:emptyTauWindow','No frames contribute to %s tau_H=[%.3g,%.3g].',cases(im).mode,a,b);
            F{n}=entry;
            rows(n)=local_empty_window_field_row(cases(im).mode,iw,a,b);
            continue;
        end
        ww=weights(use); ww=ww/sum(ww); entry.effectiveFrames=1/sum(ww.^2);
        sumUx=[]; sumUy=[]; sumWx=[]; sumWy=[]; template=[];
        for jj=1:numel(use)
            k=use(jj); dumpPath=local_find_dump_by_step(cases(im).outputDir,A.step(k));
            if isempty(dumpPath), error('0493x7w:missingWindowDump','Missing dump for %s step=%g.',cases(im).mode,A.step(k)); end
            st=read_smpcd_state(dumpPath);
            fld=bin_smpcd_state(st,'Lx',geom.Lx,'Ly',geom.Ly,'Nx',nx,'Ny',ny,'periodicX',true,'periodicY',false,'fluidOnly',true);
            ux=double(fld.Ux)/A.Ue(k); uy=double(fld.Uy)/A.Ue(k);
            if isempty(sumUx)
                sumUx=zeros(size(ux)); sumUy=zeros(size(uy)); sumWx=zeros(size(ux)); sumWy=zeros(size(uy)); template=fld;
            end
            okx=isfinite(ux); oky=isfinite(uy);
            sumUx(okx)=sumUx(okx)+ww(jj)*ux(okx); sumWx(okx)=sumWx(okx)+ww(jj);
            sumUy(oky)=sumUy(oky)+ww(jj)*uy(oky); sumWy(oky)=sumWy(oky)+ww(jj);
        end
        UxMean=nan(size(sumUx)); UyMean=nan(size(sumUy));
        okx=sumWx>0; oky=sumWy>0; UxMean(okx)=sumUx(okx)./sumWx(okx); UyMean(oky)=sumUy(oky)./sumWy(oky);
        mf=template; mf.UxStar=UxMean; mf.UyStar=UyMean; mf.Ux=UxMean; mf.Uy=UyMean;
        [omegaNorm,divNorm]=local_curl_divergence(UxMean,UyMean,mf.dx,mf.dy,true,false);
        mf.omegaStar=omegaNorm*geom.H; mf.divStar=divNorm*geom.H;
        entry.field=mf;
        F{n}=entry;
        rows(n)=local_coherent_field_metrics(mf,cases(im),geom,opt,iw,a,b,coverage,entry.effectiveFrames,numel(use));
        r=rows(n);
        fprintf('[0493x7w-analysis] tau-window %-12s [%.1f,%.1f] frames=%d eff=%.2f cov=%.3f ', ...
            cases(im).mode,a,b,numel(use),entry.effectiveFrames,entry.coverageFraction);
        fprintf('Ggen*=%.4g Gnear*=%.4g Ssec=%.4g divNear*=%.4g recirc/H2=%.4g Lr/H=%s\n', ...
            r.coherentGammaGeneratorStar,r.coherentGammaNearStar,r.coherentSectionSurvival0p5To1p5, ...
            r.coherentDivNearStar,r.coherentRecirculationAreaOverH2,local_num_string(r.coherentReattachLengthH));
    end
end
if isempty(rows), W=table(); else, W=struct2table(rows); end
end

function r = local_empty_window_field_row(mode,iw,a,b)
r=struct('mode',string(mode),'windowId',iw,'tauStart',a,'tauEnd',b,'coverageTauH',0,'coverageFraction',0, ...
    'nFramesContributing',0,'effectiveFrames',0,'coherentDarcyUxOverUe',NaN,'coherentInterfaceSlipRatio',NaN, ...
    'coherentInterfaceLeakAboveRmsOverUe',NaN,'coherentGammaPosGeneratorStar',NaN,'coherentGammaNegGeneratorStar',NaN, ...
    'coherentGammaGeneratorStar',NaN,'coherentGammaNearStar',NaN,'coherentGammaMidStar',NaN,'coherentGammaFarStar',NaN, ...
    'coherentOmegaGeneratorRmsStar',NaN,'coherentOmegaNearRmsStar',NaN,'coherentDivGeneratorStar',NaN,'coherentDivNearStar',NaN, ...
    'coherentRotationFractionNear',NaN,'coherentUyNearRmsOverUe',NaN,'coherentVorticitySection0p5Star',NaN, ...
    'coherentVorticitySection1p5Star',NaN,'coherentVorticitySection3p0Star',NaN,'coherentSectionSurvival0p5To1p5',NaN, ...
    'coherentSectionSurvival0p5To3p0',NaN,'coherentRecirculationAreaOverH2',NaN,'coherentRecirculationUxMinOverUe',NaN, ...
    'coherentReattachLengthH',NaN);
end

function r = local_coherent_field_metrics(fld,c,geom,opt,iw,a,b,coverage,effectiveFrames,nFrames)
H=geom.H; [X,Y]=meshgrid(fld.xc,fld.yc); S=mod(X-geom.xEdge,geom.Lx);
penalized=X>=geom.xMin & X<=geom.xMax & Y>=geom.yMin & Y<=geom.yMax; free=~penalized;
xFlat0=geom.xMin+double(opt.InterfaceEdgeMarginH)*H; xFlat1=geom.xMax-double(opt.InterfaceEdgeMarginH)*H;
flatX=X>=xFlat0 & X<=xFlat1;
above=flatX & Y>=geom.yMax & Y<geom.yMax+double(opt.InterfaceBandH)*H;
below=flatX & Y<=geom.yMax & Y>geom.yMax-double(opt.InterfaceBandH)*H;
UtAbove=local_mean_field(fld.UxStar,above); UtBelow=local_mean_field(fld.UxStar,below);
slip=local_safe_ratio(UtBelow,UtAbove); leak=local_rms_field(fld.UyStar,above);
darcyBulk=X>=geom.xMin+double(opt.DarcyBulkXMarginH)*H & X<=geom.xMax-double(opt.DarcyBulkXMarginH)*H & ...
    Y>=double(opt.DarcyBulkYRangeH(1))*H & Y<=double(opt.DarcyBulkYRangeH(2))*H;
darcyUx=local_mean_field(fld.UxStar,darcyBulk);
gen=local_srange_mask(S,double(opt.GeneratorXRangeH)*H) & Y>=double(opt.GeneratorYRangeH(1))*H & Y<=double(opt.GeneratorYRangeH(2))*H & free;
near=local_srange_mask(S,double(opt.NearWakeXRangeH)*H) & Y>=double(opt.WakeYRangeH(1))*H & Y<=double(opt.WakeYRangeH(2))*H & free;
mid=local_srange_mask(S,double(opt.MidWakeXRangeH)*H) & Y>=double(opt.WakeYRangeH(1))*H & Y<=double(opt.WakeYRangeH(2))*H & free;
far=local_srange_mask(S,double(opt.FarWakeXRangeH)*H) & Y>=double(opt.WakeYRangeH(1))*H & Y<=double(opt.WakeYRangeH(2))*H & free;
dAstar=fld.dx*fld.dy/(H*H);
wg=local_field_stats(fld.omegaStar,gen,dAstar); wn=local_field_stats(fld.omegaStar,near,dAstar);
wm=local_field_stats(fld.omegaStar,mid,dAstar); wf=local_field_stats(fld.omegaStar,far,dAstar);
dg=local_field_stats(fld.divStar,gen,1); dn=local_field_stats(fld.divStar,near,1);
sec05=local_cross_section_abs(fld.omegaStar,S,Y,0.5*H,0.125*H,double(opt.WakeYRangeH)*H,fld.dy)/H;
sec15=local_cross_section_abs(fld.omegaStar,S,Y,1.5*H,0.125*H,double(opt.WakeYRangeH)*H,fld.dy)/H;
sec30=local_cross_section_abs(fld.omegaStar,S,Y,3.0*H,0.125*H,double(opt.WakeYRangeH)*H,fld.dy)/H;
rotNear=local_rotation_fraction(fld.omegaStar,fld.divStar,near); uyNear=local_rms_field(fld.UyStar,near);
recircMask=S>=0 & S<=double(opt.RecirculationXMaxH)*H & Y>=double(opt.RecirculationYRangeH(1))*H & ...
    Y<=double(opt.RecirculationYRangeH(2))*H & free;
neg=recircMask & isfinite(fld.UxStar) & fld.UxStar<0; recircArea=nnz(neg)*fld.dx*fld.dy/(H*H);
v=fld.UxStar(recircMask); v=v(isfinite(v)); if isempty(v), uxMin=NaN; else, uxMin=min(v); end
reattach=local_reattachment_length(fld,S,Y,geom,opt);
r=local_empty_window_field_row(c.mode,iw,a,b); r.coverageTauH=coverage; r.coverageFraction=coverage/max(b-a,eps);
r.nFramesContributing=nFrames; r.effectiveFrames=effectiveFrames; r.coherentDarcyUxOverUe=darcyUx;
r.coherentInterfaceSlipRatio=slip; r.coherentInterfaceLeakAboveRmsOverUe=leak;
r.coherentGammaPosGeneratorStar=wg.posIntegral; r.coherentGammaNegGeneratorStar=wg.negIntegral;
r.coherentGammaGeneratorStar=wg.absIntegral; r.coherentGammaNearStar=wn.absIntegral; r.coherentGammaMidStar=wm.absIntegral; r.coherentGammaFarStar=wf.absIntegral;
r.coherentOmegaGeneratorRmsStar=wg.rms; r.coherentOmegaNearRmsStar=wn.rms;
r.coherentDivGeneratorStar=dg.rms; r.coherentDivNearStar=dn.rms; r.coherentRotationFractionNear=rotNear; r.coherentUyNearRmsOverUe=uyNear;
r.coherentVorticitySection0p5Star=sec05; r.coherentVorticitySection1p5Star=sec15; r.coherentVorticitySection3p0Star=sec30;
r.coherentSectionSurvival0p5To1p5=local_safe_ratio(sec15,sec05); r.coherentSectionSurvival0p5To3p0=local_safe_ratio(sec30,sec05);
r.coherentRecirculationAreaOverH2=recircArea; r.coherentRecirculationUxMinOverUe=uxMin; r.coherentReattachLengthH=reattach;
end

function P = local_build_tau_window_pairwise(Ws,Wf,referenceMode)
modeCol=strings(0,1); windowCol=[]; aCol=[]; bCol=[]; sourceCol=strings(0,1); metricCol=strings(0,1);
refVal=[]; cmpVal=[]; ratio=[]; relDiff=[];
if ~isempty(Ws)
    scalarMetrics=setdiff(Ws.Properties.VariableNames,{'mode','windowId','tauStart','tauEnd','coverageTauH','coverageFraction','nFramesContributing','effectiveFrames'},'stable');
    [modeCol,windowCol,aCol,bCol,sourceCol,metricCol,refVal,cmpVal,ratio,relDiff]= ...
        local_append_window_pairs(Ws,scalarMetrics,'scalar',referenceMode,modeCol,windowCol,aCol,bCol,sourceCol,metricCol,refVal,cmpVal,ratio,relDiff);
end
if ~isempty(Wf)
    fieldMetrics=setdiff(Wf.Properties.VariableNames,{'mode','windowId','tauStart','tauEnd','coverageTauH','coverageFraction','nFramesContributing','effectiveFrames'},'stable');
    [modeCol,windowCol,aCol,bCol,sourceCol,metricCol,refVal,cmpVal,ratio,relDiff]= ...
        local_append_window_pairs(Wf,fieldMetrics,'coherent_field',referenceMode,modeCol,windowCol,aCol,bCol,sourceCol,metricCol,refVal,cmpVal,ratio,relDiff);
end
P=table(modeCol,windowCol,aCol,bCol,sourceCol,metricCol,refVal,cmpVal,ratio,relDiff, ...
    'VariableNames',{'mode','windowId','tauStart','tauEnd','source','metric','srcValue','modeValue','ratioToSrc','relativeDifferenceToSrc'});
end

function [modeCol,windowCol,aCol,bCol,sourceCol,metricCol,refVal,cmpVal,ratio,relDiff] = local_append_window_pairs(W,metrics,source,referenceMode,modeCol,windowCol,aCol,bCol,sourceCol,metricCol,refVal,cmpVal,ratio,relDiff)
windows=unique(W.windowId); comparisons=unique(W.mode,'stable'); comparisons=comparisons(comparisons~=string(referenceMode));
for iw=1:numel(windows)
    ref=W(W.windowId==windows(iw) & W.mode==string(referenceMode),:); if isempty(ref), continue; end
    for ic=1:numel(comparisons)
        cmp=W(W.windowId==windows(iw) & W.mode==comparisons(ic),:); if isempty(cmp), continue; end
        for im=1:numel(metrics)
            f=metrics{im}; a=ref.(f)(1); b=cmp.(f)(1);
            if ~(isnumeric(a)&&isnumeric(b)), continue; end
            modeCol(end+1,1)=comparisons(ic); windowCol(end+1,1)=windows(iw); %#ok<AGROW>
            aCol(end+1,1)=ref.tauStart(1); bCol(end+1,1)=ref.tauEnd(1); sourceCol(end+1,1)=string(source); metricCol(end+1,1)=string(f); %#ok<AGROW>
            refVal(end+1,1)=a; cmpVal(end+1,1)=b; ratio(end+1,1)=local_safe_ratio(b,a); relDiff(end+1,1)=local_rel_diff(b,a); %#ok<AGROW>
        end
    end
end
end

function S = local_build_summary(T,P,cases,geom,opt)
modeNames={cases.mode}; mins=nan(numel(cases),1); maxs=mins;
for i=1:numel(cases)
    v=T.tauH(T.mode==string(modeNames{i}) & isfinite(T.tauH)); if ~isempty(v), mins(i)=min(v); maxs(i)=max(v); end
end
lo=max(mins); hi=min(maxs); lo=max(lo,double(opt.SummaryTauRangeH(1))); if isfinite(opt.SummaryTauRangeH(2)), hi=min(hi,double(opt.SummaryTauRangeH(2))); end
rows=repmat(struct('mode',"",'B0',NaN,'B1',NaN,'nu',NaN,'nuSource',"", ...
    'firstStep',NaN,'lastStep',NaN,'firstUe',NaN,'lastUe',NaN,'finalTauH',NaN,'summaryTauStart',lo,'summaryTauEnd',hi, ...
    'finalKBT',NaN,'finalStdN',NaN,'finalQ6F',NaN,'finalQ6A',NaN, ...
    'tauMeanDarcyPowerPerMassCsv',NaN,'tauMeanSolidLeakRmsCsv',NaN,'tauMeanDarcySpeedRmsCsv',NaN, ...
    'tauMeanDarcyUxOverUe',NaN,'tauMeanInterfaceSlipRatio',NaN,'tauMeanInterfaceLeakAboveOverUe',NaN, ...
    'tauMeanGammaGeneratorStar',NaN,'tauMeanGammaNearStar',NaN,'tauMeanSectionSurvival0p5To1p5',NaN, ...
    'tauMeanDivNearStar',NaN,'tauMeanUyNearRmsOverUe',NaN, ...
    'tauRatioDarcyPowerToSrc',NaN,'tauRatioSolidLeakToSrc',NaN,'tauRatioDarcyUxToSrc',NaN,'tauRatioSlipToSrc',NaN, ...
    'tauRatioGammaGeneratorToSrc',NaN,'tauRatioGammaNearToSrc',NaN,'tauRatioSectionSurvivalToSrc',NaN, ...
    'tauRatioDivNearToSrc',NaN,'tauRatioUyNearToSrc',NaN),numel(cases),1);
for i=1:numel(cases)
    m=string(cases(i).mode); A=T(T.mode==m,:); A=sortrows(A,'tauH'); r=rows(i); r.mode=m; r.B0=cases(i).B0; r.B1=cases(i).B1;
    if ~isempty(A)
        r.nu=A.nu(1); r.nuSource=A.nuSource(1); r.firstStep=A.step(1); r.lastStep=A.step(end); r.firstUe=A.Ue(1); r.lastUe=A.Ue(end); r.finalTauH=A.tauH(end);
        r.finalKBT=A.kBTlog(end); r.finalStdN=A.stdNlog(end); r.finalQ6F=A.q6Flog(end); r.finalQ6A=A.q6Alog(end);
        [w,~]=local_tau_voronoi_weights(A.tauH,lo,hi);
        r.tauMeanDarcyPowerPerMassCsv=local_weighted_column(A.darcyPowerPerMassCsv,w); r.tauMeanSolidLeakRmsCsv=local_weighted_column(A.solidLeakRmsCsv,w);
        r.tauMeanDarcySpeedRmsCsv=local_weighted_column(A.meanSpeedRmsCsv,w); r.tauMeanDarcyUxOverUe=local_weighted_column(A.darcyUxOverUe,w);
        r.tauMeanInterfaceSlipRatio=local_weighted_column(A.interfaceSlipRatio,w); r.tauMeanInterfaceLeakAboveOverUe=local_weighted_column(A.interfaceUnAboveRmsOverUe,w);
        r.tauMeanGammaGeneratorStar=local_weighted_column(A.gammaAbsGeneratorStar,w); r.tauMeanGammaNearStar=local_weighted_column(A.gammaAbsNearStar,w);
        r.tauMeanSectionSurvival0p5To1p5=local_weighted_column(A.sectionSurvival0p5To1p5,w); r.tauMeanDivNearStar=local_weighted_column(A.divNearStar,w);
        r.tauMeanUyNearRmsOverUe=local_weighted_column(A.uyNearRmsOverUe,w);
    end
    if m=="src"
        r.tauRatioDarcyPowerToSrc=1; r.tauRatioSolidLeakToSrc=1; r.tauRatioDarcyUxToSrc=1; r.tauRatioSlipToSrc=1; r.tauRatioGammaGeneratorToSrc=1;
        r.tauRatioGammaNearToSrc=1; r.tauRatioSectionSurvivalToSrc=1; r.tauRatioDivNearToSrc=1; r.tauRatioUyNearToSrc=1;
    elseif ~isempty(P)
        r.tauRatioDarcyPowerToSrc=local_pair_mean(P,m,'darcyPowerPerMassCsv'); r.tauRatioSolidLeakToSrc=local_pair_mean(P,m,'solidLeakRmsCsv');
        r.tauRatioDarcyUxToSrc=local_pair_mean(P,m,'darcyUxOverUe'); r.tauRatioSlipToSrc=local_pair_mean(P,m,'interfaceSlipRatio');
        r.tauRatioGammaGeneratorToSrc=local_pair_mean(P,m,'gammaAbsGeneratorStar'); r.tauRatioGammaNearToSrc=local_pair_mean(P,m,'gammaAbsNearStar');
        r.tauRatioSectionSurvivalToSrc=local_pair_mean(P,m,'sectionSurvival0p5To1p5'); r.tauRatioDivNearToSrc=local_pair_mean(P,m,'divNearStar');
        r.tauRatioUyNearToSrc=local_pair_mean(P,m,'uyNearRmsOverUe');
    end
    rows(i)=r;
end
S=struct2table(rows); S.H=repmat(geom.H,height(S),1); S.downstreamClearanceH=repmat(geom.downstreamClearance/geom.H,height(S),1);
end

function v=local_pair_mean(P,mode,metric)
idx=P.mode==mode & P.metric==string(metric) & isfinite(P.ratioToSrc); if any(idx), v=mean(P.ratioToSrc(idx),'omitnan'); else, v=NaN; end
end

function [w,coverage]=local_tau_voronoi_weights(tau,a,b)
tau=double(tau(:)); n=numel(tau); w=zeros(n,1); coverage=0;
if n==0 || ~(isfinite(a)&&isfinite(b)&&b>a), return; end
if any(diff(tau)<0), [tau,ord]=sort(tau); else, ord=(1:n)'; end
if n==1
    if tau(1)>=a && tau(1)<=b, w(1)=b-a; coverage=b-a; end
else
    edges=zeros(n+1,1); edges(2:n)=0.5*(tau(1:end-1)+tau(2:end)); edges(1)=tau(1); edges(end)=tau(end);
    ws=max(0,min(edges(2:end),b)-max(edges(1:end-1),a)); coverage=sum(ws); w(ord)=ws;
end
end

function v=local_weighted_column(x,w)
x=double(x(:)); w=double(w(:)); ok=isfinite(x)&isfinite(w)&w>0; if ~any(ok), v=NaN; else, v=sum(x(ok).*w(ok))/sum(w(ok)); end
end

function local_remove_legacy_outputs(outDir)
patterns={ ...
    'x7w_step_matched_ue_0493x7w.csv','x7w_step_pairwise_matched_0493x7w.csv', ...
    'x7w_step_matched_ue_ratios_0493x7w.png','x7w_step_matched_ue_ratios_0493x7w.pdf', ...
    'x7w_step_fields_matched_ue*_0493x7w.png','x7w_step_fields_matched_ue*_0493x7w.pdf', ...
    'x7w_step_fields_final_common_step_0493x7w.png','x7w_step_fields_final_common_step_0493x7w.pdf'};
for ip=1:numel(patterns)
    d=dir(fullfile(outDir,patterns{ip})); for j=1:numel(d), if ~d(j).isdir, delete(fullfile(d(j).folder,d(j).name)); end, end
end
end


% =========================================================================
% Run discovery, audit, geometry and logs
% =========================================================================
function cases=local_resolve_cases(runRoot,modes)
cases=struct('mode',{},'runDir',{},'outputDir',{},'paramsFile',{},'envFile',{},'logFile',{},'params',{},'env',{},'dt',{},'B0',{},'B1',{});
for i=1:numel(modes)
    mode=char(modes{i}); runDir=fullfile(runRoot,mode);
    if ~isfolder(runDir)
        error('0493x7w:missingMode','Missing mode directory: %s',runDir);
    end
    out=fullfile(runDir,'output');
    if ~isfolder(out) || isempty(dir(fullfile(out,'state_step_*.smpcd')))
        error('0493x7w:missingDumps','No state_step_*.smpcd dumps in %s',out);
    end
    paramsFile=local_resolve_params(runDir,out); params=parse_smpcd_kv(paramsFile);
    envFile=fullfile(runDir,'logs','environment_0434.env');
    if isfile(envFile), env=local_parse_env(envFile); else, env=struct(); end
    logs=dir(fullfile(runDir,'logs','*.log'));
    if isempty(logs), logFile=''; else, [~,j]=max([logs.datenum]); logFile=fullfile(logs(j).folder,logs(j).name); end
    dt=local_param_num(params,{'dt'},NaN);
    if ~isfinite(dt), error('0493x7w:missingDt','Missing dt in %s',paramsFile); end
    [b0,b1]=local_b_flags(mode,env);
    c=struct('mode',mode,'runDir',runDir,'outputDir',out,'paramsFile',paramsFile,'envFile',envFile,'logFile',logFile, ...
        'params',params,'env',env,'dt',dt,'B0',b0,'B1',b1);
    cases(end+1)=c; %#ok<AGROW>
end
end

function A=local_build_audit(cases,geom,frames,commonSteps)
mode=strings(numel(cases),1); paramsFile=mode; envFile=mode; chiFile=mode; nDumps=zeros(numel(cases),1);
firstStep=nan(numel(cases),1); lastStep=firstStep; dt=firstStep; gamma=firstStep; kBT=firstStep; angle=firstStep;
alpha=firstStep; darcyQ=firstStep; B0=firstStep; B1=firstStep; q6gf=zeros(numel(cases),1); commonFilled=nan(numel(cases),1);
for i=1:numel(cases)
    c=cases(i); mode(i)=string(c.mode); paramsFile(i)=string(c.paramsFile); envFile(i)=string(c.envFile);
    chiFile(i)=string(geom.chiFile); nDumps(i)=height(frames{i});
    if ~isempty(frames{i}), firstStep(i)=frames{i}.step(1); lastStep(i)=frames{i}.step(end); end
    dt(i)=c.dt; gamma(i)=local_param_num(c.params,{'gamma','resamplingTargetCellMass'},NaN);
    kBT(i)=local_param_num(c.params,{'kBT'},NaN); angle(i)=local_param_num(c.params,{'rotationAngle'},NaN);
    alpha(i)=local_param_num(c.params,{'darcyAlphaMax'},NaN); darcyQ(i)=local_param_num(c.params,{'darcyQ'},NaN);
    B0(i)=c.B0; B1(i)=c.B1; q6gf(i)=double(contains(c.mode,'q6-g-f'));
    commonFilled(i)=local_struct_num(c.env,'RUN_OK_DARCY_COMMON_FILLED_STATE',NaN);
end
commonDumpCount=repmat(numel(commonSteps),numel(cases),1);
Lx=repmat(geom.Lx,numel(cases),1); Ly=repmat(geom.Ly,numel(cases),1); H=repmat(geom.H,numel(cases),1);
xMin=repmat(geom.xMin,numel(cases),1); xMax=repmat(geom.xMax,numel(cases),1);
A=table(mode,paramsFile,envFile,chiFile,nDumps,commonDumpCount,firstStep,lastStep,dt,gamma,kBT,angle,alpha,darcyQ,B0,B1,q6gf,commonFilled,Lx,Ly,H,xMin,xMax);
end

function geom=local_geometry_from_case(c)
p=c.params; Lx=local_param_num(p,{'Lx'},NaN); Ly=local_param_num(p,{'Ly'},NaN);
Nx=round(local_param_num(p,{'Nx'},NaN)); Ny=round(local_param_num(p,{'Ny'},NaN));
if ~(all(isfinite([Lx Ly Nx Ny]))&&Lx>0&&Ly>0&&Nx>0&&Ny>0), error('0493x7w:badGeometryParams','Bad grid/domain in %s',c.paramsFile); end
chiText=local_param_text(p,{'darcyChiFile'},'');
chiPath=local_resolve_referenced_file(chiText,c.runDir,c.paramsFile);
if isempty(chiPath), error('0493x7w:missingChi','Cannot resolve darcyChiFile=%s from %s',chiText,c.paramsFile); end
chi=local_read_chi(chiPath,Nx,Ny); solid=chi<0.5;
if ~any(solid(:)), error('0493x7w:noPenalizedChi','No chi<0.5 cell in %s',chiPath); end
dx=Lx/Nx; dy=Ly/Ny; xc=((0:Nx-1)+0.5)*dx; yc=((0:Ny-1)+0.5)*dy;
[ix,iy]=meshgrid(1:Nx,1:Ny); %#ok<ASGLU>
cols=find(any(solid,1)); rows=find(any(solid,2));
xMin=xc(cols(1))-0.5*dx; xMax=xc(cols(end))+0.5*dx; yMin=yc(rows(1))-0.5*dy; yMax=yc(rows(end))+0.5*dy;
H=yMax-yMin; xEdge=xMax;
clearance=mod(xMin-xEdge,Lx);
geom=struct('Lx',Lx,'Ly',Ly,'Nx',Nx,'Ny',Ny,'dx',dx,'dy',dy,'chiFile',chiPath,'chi',chi, ...
    'xMin',xMin,'xMax',xMax,'yMin',yMin,'yMax',yMax,'H',H,'xEdge',xEdge,'downstreamClearance',clearance);
end

function local_assert_same_geometry(a,b,modeA,modeB)
nums={'Lx','Ly','Nx','Ny','xMin','xMax','yMin','yMax','H'};
for i=1:numel(nums)
    f=nums{i}; av=double(a.(f)); bv=double(b.(f)); tol=1e-10*max(1,max(abs([av bv])));
    if abs(av-bv)>tol, error('0493x7w:geometryMismatch','Geometry mismatch %s: %s=%g %s=%g',f,modeA,av,modeB,bv); end
end
if ~isequal(size(a.chi),size(b.chi)) || max(abs(a.chi(:)-b.chi(:)))>1e-7
    error('0493x7w:chiMismatch','Chi fields differ between %s and %s.',modeA,modeB);
end
end

function chi=local_read_chi(filename,Nx,Ny)
fid=fopen(filename,'r','ieee-le'); if fid<0, error('0493x7w:chiOpen','Cannot open %s',filename); end
cl=onCleanup(@() fclose(fid)); %#ok<NASGU>
v=fread(fid,Nx*Ny,'single=>double');
if numel(v)~=Nx*Ny, error('0493x7w:chiSize','Expected %d float32 values in %s, found %d.',Nx*Ny,filename,numel(v)); end
chi=reshape(v,[Nx Ny]).';
end

function env=local_parse_env(filename)
env=struct(); fid=fopen(filename,'r'); if fid<0, return; end
cl=onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    line=fgetl(fid); if ~ischar(line), break; end
    line=strtrim(line); if isempty(line)||startsWith(line,'#'), continue; end
    eq=strfind(line,'='); if isempty(eq), continue; end
    key=matlab.lang.makeValidName(strtrim(line(1:eq(1)-1))); txt=strtrim(line(eq(1)+1:end));
    num=str2double(txt); if isfinite(num), env.(key)=num;
    elseif any(strcmpi(txt,{'true','yes','on'})), env.(key)=true;
    elseif any(strcmpi(txt,{'false','no','off'})), env.(key)=false;
    else, env.(key)=txt; end
end
end

function [b0,b1]=local_b_flags(mode,env)
b0=local_struct_num(env,'MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0',NaN);
b1=local_struct_num(env,'MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1',NaN);
if ~isfinite(b0), b0=0; end
if ~isfinite(b1), b1=double(strcmp(mode,'src-q6-g-f')); end
end

function L=local_parse_solver_log(filename)
L=table(); if isempty(filename)||~isfile(filename), return; end
fid=fopen(filename,'r'); if fid<0, return; end
cl=onCleanup(@() fclose(fid)); %#ok<NASGU>
step=[]; time=[]; kBT=[]; stdN=[]; resM=[]; q6F=[]; q6A=[];
pat='\[src_mpcd_base\]\s+step=(\d+)/(\d+)\s+t=([+\-0-9.eE]+)\s+kBT=([+\-0-9.eE]+)\s+stdN=([+\-0-9.eE]+)\s+resM=([+\-0-9.eE]+)\s+q6F=([+\-0-9.eE]+)\s+q6A=([+\-0-9.eE]+)';
while true
    line=fgetl(fid); if ~ischar(line), break; end
    tok=regexp(line,pat,'tokens','once'); if isempty(tok), continue; end
    step(end+1,1)=str2double(tok{1}); %#ok<AGROW>
    time(end+1,1)=str2double(tok{3}); kBT(end+1,1)=str2double(tok{4}); stdN(end+1,1)=str2double(tok{5}); %#ok<AGROW>
    resM(end+1,1)=str2double(tok{6}); q6F(end+1,1)=str2double(tok{7}); q6A(end+1,1)=str2double(tok{8}); %#ok<AGROW>
end
if ~isempty(step), L=table(step,time,kBT,stdN,resM,q6F,q6A); [~,ia]=unique(L.step,'last'); L=sortrows(L(ia,:),'step'); end
end

function row=local_attach_log_metrics(row,L)
if isempty(L), return; end
j=find(L.step==row.step,1,'last'); if isempty(j), return; end
row.kBTlog=L.kBT(j); row.stdNlog=L.stdN(j); row.resMlog=L.resM(j); row.q6Flog=L.q6F(j); row.q6Alog=L.q6A(j);
end

function T=local_read_optional_csv(filename)
T=table();
if ~isfile(filename), return; end
try
    T=readtable(filename);
catch ME
    warning('0493x7w:csvRead','Cannot read %s: %s',filename,ME.message);
    T=table();
end
end

function row=local_attach_darcy_csv_metrics(row,T)
if isempty(T) || ~ismember('step',T.Properties.VariableNames), return; end
j=find(double(T.step)==row.step,1,'last');
if isempty(j), return; end
row.darcyPowerCsv=local_table_value(T,j,{'darcyPower'});
row.darcyPowerPerMassCsv=local_table_value(T,j,{'darcyPowerPerMass'});
row.solidLeakRmsCsv=local_table_value(T,j,{'solidLeakRms'});
row.meanSpeedRmsCsv=local_table_value(T,j,{'meanSpeedRms'});
row.meanChiCsv=local_table_value(T,j,{'meanChi'});
row.meanAlphaCsv=local_table_value(T,j,{'meanAlpha'});
end

function v=local_table_value(T,j,names)
v=NaN;
for ii=1:numel(names)
    f=matlab.lang.makeValidName(names{ii});
    if ismember(f,T.Properties.VariableNames)
        x=T.(f)(j);
        if iscell(x), x=x{1}; end
        if isnumeric(x)||islogical(x), x=double(x); else, x=str2double(char(string(x))); end
        if isfinite(x), v=x; return; end
    end
end
end

function paramsFile=local_resolve_params(runDir,outputDir)
cands=[dir(fullfile(runDir,'params','*.kv')); dir(fullfile(runDir,'params_used.kv')); dir(fullfile(outputDir,'params_used.kv'))];
if isempty(cands), error('0493x7w:missingParams','No .kv parameter file found under %s',runDir); end
[~,ord]=sort([cands.datenum],'descend'); cands=cands(ord); paramsFile=fullfile(cands(1).folder,cands(1).name);
end

function frames=local_list_frames(outputDir,dt,stride,maxDumps)
f=dir(fullfile(outputDir,'state_step_*.smpcd')); if isempty(f), frames=table(); return; end
step=nan(numel(f),1); fullPath=strings(numel(f),1); file=strings(numel(f),1);
for i=1:numel(f)
    file(i)=string(f(i).name); fullPath(i)=string(fullfile(f(i).folder,f(i).name));
    tok=regexp(f(i).name,'state_step_(\d+)\.smpcd$','tokens','once'); if ~isempty(tok), step(i)=str2double(tok{1}); end
end
ok=isfinite(step); step=step(ok); fullPath=fullPath(ok); file=file(ok); [step,ord]=sort(step); fullPath=fullPath(ord); file=file(ord);
time=step*dt; frames=table(file,fullPath,step,time); stride=max(1,round(stride)); frames=frames(1:stride:end,:);
if isfinite(maxDumps), frames=frames(1:min(height(frames),round(maxDumps)),:); end
end

function common=local_common_steps(frames,cases,strict)
common=frames{1}.step;
for i=2:numel(frames), common=intersect(common,frames{i}.step,'stable'); end
if strict
    for i=1:numel(frames)
        if numel(frames{i}.step)~=numel(common) || any(frames{i}.step~=common)
            missing=setdiff(common,frames{i}.step); extra=setdiff(frames{i}.step,common);
            error('0493x7w:dumpMismatch','Dump-step mismatch for %s (missing common=%s extra=%s).',cases(i).mode,mat2str(missing.'),mat2str(extra.'));
        end
    end
end
end

function path=local_resolve_referenced_file(txt,runDir,paramsFile)
path=''; if isempty(txt), return; end
txt=char(txt); cands={txt,fullfile(runDir,txt),fullfile(fileparts(paramsFile),txt),fullfile('..',txt)};
% If runDir contains a /runs/ component, prepend its prefix to paths beginning runs/.
r=strrep(runDir,'\','/'); pos=strfind(r,'/runs/');
if ~isempty(pos), prefix=r(1:pos(1)-1); cands{end+1}=fullfile(prefix,txt); end %#ok<AGROW>
for i=1:numel(cands), if isfile(cands{i}), path=cands{i}; return; end, end
end

function path=local_find_dump_by_step(outputDir,step)
path='';
f=dir(fullfile(outputDir,'state_step_*.smpcd'));
for ii=1:numel(f)
    tok=regexp(f(ii).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(tok) && str2double(tok{1})==step
        path=fullfile(f(ii).folder,f(ii).name);
        return;
    end
end
end

% =========================================================================
% Numerical field helpers
% =========================================================================
function [omega,div]=local_curl_divergence(Ux,Uy,dx,dy,periodicX,periodicY)
Ux=local_fill_empty_velocity(Ux); Uy=local_fill_empty_velocity(Uy);
if periodicX
    dUx_dx=(circshift(Ux,[0,-1])-circshift(Ux,[0,1]))/(2*dx);
    dUy_dx=(circshift(Uy,[0,-1])-circshift(Uy,[0,1]))/(2*dx);
else
    dUx_dx=local_derivative_x(Ux,dx); dUy_dx=local_derivative_x(Uy,dx);
end
if periodicY
    dUx_dy=(circshift(Ux,[-1,0])-circshift(Ux,[1,0]))/(2*dy);
    dUy_dy=(circshift(Uy,[-1,0])-circshift(Uy,[1,0]))/(2*dy);
else
    dUx_dy=local_derivative_y(Ux,dy); dUy_dy=local_derivative_y(Uy,dy);
end
omega=dUy_dx-dUx_dy; div=dUx_dx+dUy_dy;
end

function A=local_fill_empty_velocity(A)
if all(isfinite(A(:))), return; end
for pass=1:6
    bad=~isfinite(A); if ~any(bad(:)), break; end
    vals=zeros(size(A)); cnt=zeros(size(A));
    shifts={[0 1],[0 -1],[1 0],[-1 0]};
    for j=1:numel(shifts)
        B=circshift(A,shifts{j}); ok=isfinite(B); vals(ok)=vals(ok)+B(ok); cnt(ok)=cnt(ok)+1;
    end
    fill=bad & cnt>0; A(fill)=vals(fill)./cnt(fill);
end
A(~isfinite(A))=0;
end

function d=local_derivative_x(A,dx)
d=zeros(size(A)); d(:,2:end-1)=(A(:,3:end)-A(:,1:end-2))/(2*dx); d(:,1)=(A(:,2)-A(:,1))/dx; d(:,end)=(A(:,end)-A(:,end-1))/dx;
end
function d=local_derivative_y(A,dy)
d=zeros(size(A)); d(2:end-1,:)=(A(3:end,:)-A(1:end-2,:))/(2*dy); d(1,:)=(A(2,:)-A(1,:))/dy; d(end,:)=(A(end,:)-A(end-1,:))/dy;
end

function mask=local_srange_mask(S,range)
mask=S>=range(1) & S<=range(2);
end

function st=local_field_stats(A,mask,dA)
v=A(mask); v=v(isfinite(v));
if isempty(v), st=struct('rms',NaN,'posIntegral',NaN,'negIntegral',NaN,'absIntegral',NaN); return; end
st=struct('rms',sqrt(mean(v.^2)),'posIntegral',sum(v(v>0))*dA,'negIntegral',sum(v(v<0))*dA,'absIntegral',sum(abs(v))*dA);
end

function r=local_rotation_fraction(omega,div,mask)
w=omega(mask); d=div(mask); ok=isfinite(w)&isfinite(d); w=w(ok); d=d(ok);
if isempty(w), r=NaN; return; end
w2=mean(w.^2); d2=mean(d.^2); r=w2/max(w2+d2,eps);
end

function v=local_mean_field(A,mask)
x=A(mask); x=x(isfinite(x)); if isempty(x), v=NaN; else, v=mean(x); end
end
function v=local_rms_field(A,mask)
x=A(mask); x=x(isfinite(x)); if isempty(x), v=NaN; else, v=sqrt(mean(x.^2)); end
end

function c=local_cross_section_abs(A,S,Y,s0,hx,yrange,dy)
sCols=S(1,:); cols=find(abs(sCols-s0)<=hx);
if isempty(cols), c=NaN; return; end
vals=nan(numel(cols),1);
for jj=1:numel(cols)
    col=cols(jj); rows=Y(:,col)>=yrange(1) & Y(:,col)<=yrange(2);
    v=A(rows,col); v=v(isfinite(v));
    if ~isempty(v), vals(jj)=sum(abs(v))*dy; end
end
vals=vals(isfinite(vals)); if isempty(vals), c=NaN; else, c=mean(vals); end
end

function LrH=local_reattachment_length(fld,S,Y,geom,opt)
H=geom.H; y0=double(opt.ReattachProbeYRangeH(1))*H; y1=double(opt.ReattachProbeYRangeH(2))*H;
cols=1:numel(fld.xc); sCols=mod(fld.xc-geom.xEdge,geom.Lx); valid=sCols>=double(opt.ReattachSearchStartH)*H & sCols<=double(opt.RecirculationXMaxH)*H;
[ss,ord]=sort(sCols(valid)); cc=cols(valid); cc=cc(ord); u=nan(numel(cc),1);
for j=1:numel(cc)
    m=Y(:,cc(j))>=y0 & Y(:,cc(j))<=y1; vals=fld.Ux(m,cc(j)); vals=vals(isfinite(vals)); if ~isempty(vals), u(j)=mean(vals); end
end
if isempty(u)||~any(u<0), LrH=NaN; return; end
u=local_smooth_nan(u,max(1,round(opt.ReattachSmoothBins))); holdN=max(1,round(opt.ReattachHoldBins));
start=max(2,find(u<0,1,'first')+1); idx=NaN;
for j=start:numel(u)-holdN+1
    if all(isfinite(u(j:j+holdN-1))) && all(u(j:j+holdN-1)>=0), idx=j; break; end
end
if isnan(idx), LrH=NaN; return; end
% Linear interpolation of the last sign change when possible.
j=idx; if j>1 && isfinite(u(j-1)) && u(j)~=u(j-1)
    sc=ss(j-1)+(0-u(j-1))*(ss(j)-ss(j-1))/(u(j)-u(j-1));
else, sc=ss(j); end
LrH=sc/H;
end

function y=local_smooth_nan(x,n)
y=x; if n<=1, return; end
h=floor(n/2);
for i=1:numel(x), j0=max(1,i-h); j1=min(numel(x),i+h); v=x(j0:j1); v=v(isfinite(v)); if ~isempty(v), y(i)=mean(v); end, end
end

function [Ux,Uy,M,N]=local_particle_region_velocity_periodic(st,box,Lx,fluidRole)
role=ones(numel(st.x),1,'uint8'); if isfield(st,'role'), role=uint8(st.role(:)); end
x=mod(double(st.x(:)),Lx); y=double(st.y(:)); x0=mod(box(1),Lx); x1=mod(box(2),Lx);
if box(2)-box(1)>=Lx, inx=true(size(x)); elseif x0<=x1, inx=x>=x0 & x<=x1; else, inx=x>=x0 | x<=x1; end
keep=role==uint8(fluidRole) & inx & y>=box(3) & y<=box(4); m=double(st.mass(keep)); M=sum(m); N=nnz(keep);
if M>0, Ux=sum(m.*double(st.vx(keep)))/M; Uy=sum(m.*double(st.vy(keep)))/M; else, Ux=NaN; Uy=NaN; end
end

function [Ux,Uy,M]=local_global_velocity(st,fluidRole)
role=ones(numel(st.x),1,'uint8'); if isfield(st,'role'), role=uint8(st.role(:)); end
keep=role==uint8(fluidRole); m=double(st.mass(keep)); M=sum(m);
if M>0, Ux=sum(m.*double(st.vx(keep)))/M; Uy=sum(m.*double(st.vy(keep)))/M; else, Ux=NaN; Uy=NaN; end
end

% =========================================================================
% Viscosity
% =========================================================================
function [nu,source]=local_resolve_viscosity(mode,params,dt,opt)
key=local_mode_key(mode); nu=NaN; source="unavailable";
if isfield(opt.ModeViscosities,key)
    v=double(opt.ModeViscosities.(key)); if isfinite(v)&&v>0, nu=v; source="user_mode_override"; return; end
end
if ~logical(opt.AutoUseX7TViscosities), return; end
Lx=local_param_num(params,{'Lx'},NaN); Ly=local_param_num(params,{'Ly'},NaN); Nx=local_param_num(params,{'Nx'},NaN); Ny=local_param_num(params,{'Ny'},NaN);
gamma=local_param_num(params,{'gamma','resamplingTargetCellMass'},NaN); kBT=local_param_num(params,{'kBT'},NaN); angle=local_param_num(params,{'rotationAngle'},NaN);
ax=Lx/Nx; ay=Ly/Ny;
match=all(isfinite([ax ay gamma dt kBT angle])) && abs(ax-0.002)<=2e-6 && abs(ay-0.002)<=2e-6 && ...
    abs(gamma-6)<=1e-9 && abs(dt-5e-4)<=1e-10 && abs(kBT-5)<=1e-8 && abs(angle-1.3962634015954636)<=2e-6;
if ~match, return; end
switch key
    case 'src', nu=0.00118720273;
    case 'src_q6', nu=0.000759568145;
    case 'src_q6_g_f', nu=0.00124451358;
end
if isfinite(nu), source="0493x7t_transverse_shear_a002_alpha80"; end
end

function key=local_mode_key(mode)
s=strrep(lower(char(mode)),'-','_');
if contains(s,'q6_g_f')||contains(s,'q6gf'), key='src_q6_g_f'; elseif contains(s,'q6'), key='src_q6'; else, key='src'; end
end

% =========================================================================
% Plots
% =========================================================================
function local_plot_timeseries(T,modes,geom,opt,outDir)
vis='off'; if logical(opt.ShowFigures), vis='on'; end
fig=figure('Visible',vis,'Color','w','Name','0493x7w Darcy-step timeseries','Position',[100 100 1450 900]);
tiledlayout(3,3,'Padding','compact','TileSpacing','compact');

nexttile; hold on; local_plot_modes(T,modes,'tauH','Ue'); xlabel('\tau_H=\int U_e dt/H'); ylabel('U_e'); title('Incident velocity'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','kBTlog'); xlabel('\tau_H'); ylabel('kBT'); title('Thermal history from solver log'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','darcyUxOverUe'); xlabel('\tau_H'); ylabel('<u_x>_{Darcy}/U_e'); title('Penalized bulk response'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','interfaceSlipRatio'); xlabel('\tau_H'); ylabel('u_t^-/u_t^+'); title('Flat chi-interface transmission'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','gammaAbsGeneratorStar'); local_plot_modes(T,modes,'tauH','gammaAbsNearStar','--'); xlabel('\tau_H'); ylabel('\Gamma_{abs}/(U_e H)'); title('Vorticity generation (solid) / near wake (dashed)'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','sectionSurvival0p5To1p5'); xlabel('\tau_H'); ylabel('C_{|\omega|}(1.5H)/C_{|\omega|}(0.5H)'); title('Cross-section vorticity transport'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','divNearStar'); xlabel('\tau_H'); ylabel('H RMS(div u)/U_e'); title('Near-wake divergence'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','uyNearRmsOverUe'); xlabel('\tau_H'); ylabel('RMS(u_y)/U_e'); title('Near-wake transverse velocity'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'tauH','rotationFractionNear'); xlabel('\tau_H'); ylabel('<\omega^2>/(<\omega^2>+<div^2>)'); title('Near-wake rotation fraction'); grid on;
legend(modes,'Interpreter','none','Location','bestoutside');
sgtitle(sprintf('0493x7w periodic Darcy step | H=%.4g | clearance=%.2fH',geom.H,geom.downstreamClearance/geom.H));
local_save_figure(fig,outDir,'x7w_step_timeseries_0493x7w',opt);
end

function local_plot_solver_diagnostics(T,modes,opt,outDir)
vis='off'; if logical(opt.ShowFigures), vis='on'; end
fig=figure('Visible',vis,'Color','w','Name','0493x7w solver/Darcy diagnostics','Position',[130 130 1300 720]);
tiledlayout(2,3,'Padding','compact','TileSpacing','compact');
nexttile; hold on; local_plot_modes(T,modes,'time','kBTlog'); xlabel('t'); ylabel('kBT'); title('Solver kBT'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'time','stdNlog'); xlabel('t'); ylabel('stdN'); title('Population stdN'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'time','q6Flog'); xlabel('t'); ylabel('q6F'); title('q6F'); grid on; set(gca,'YScale','log');
nexttile; hold on; local_plot_modes(T,modes,'time','q6Alog'); xlabel('t'); ylabel('q6A'); title('q6A'); grid on; set(gca,'YScale','log');
nexttile; hold on; local_plot_modes(T,modes,'time','darcyPowerPerMassCsv'); xlabel('t'); ylabel('Darcy power / mass'); title('darcy\_cost direct power'); grid on;
nexttile; hold on; local_plot_modes(T,modes,'time','solidLeakRmsCsv'); xlabel('t'); ylabel('solidLeakRms'); title('darcy\_cost direct leak'); grid on;
legend(modes,'Interpreter','none','Location','bestoutside'); sgtitle('0493x7w direct solver and Darcy CSV diagnostics');
local_save_figure(fig,outDir,'x7w_step_solver_darcy_diagnostics_0493x7w',opt);
end

function local_plot_tau_aligned(P,modes,opt,outDir)
if isempty(P), return; end
vis='off'; if logical(opt.ShowFigures), vis='on'; end
fig=figure('Visible',vis,'Color','w','Name','0493x7w tau_H-aligned ratios','Position',[120 120 1500 900]);
tiledlayout(3,3,'Padding','compact','TileSpacing','compact');
metrics={'darcyPowerPerMassCsv','solidLeakRmsCsv','darcyUxOverUe','interfaceSlipRatio','gammaAbsGeneratorStar','gammaAbsNearStar','sectionSurvival0p5To1p5','divNearStar','uyNearRmsOverUe'};
titles={'Darcy power / mass','Darcy solid leak','Darcy u_x/U_e','Interface slip','Vorticity generation','Near-wake vorticity','Vorticity survival','Near-wake divergence','Near-wake u_y RMS'};
cmp=modes(~strcmp(modes,'src'));
for j=1:numel(metrics)
    nexttile; hold on;
    for i=1:numel(cmp)
        A=P(P.mode==string(cmp{i}) & P.metric==string(metrics{j}),:); A=sortrows(A,'targetTauH');
        plot(A.targetTauH,A.ratioToSrc,'-o','LineWidth',1.2,'DisplayName',cmp{i});
    end
    yline(1,':'); xlabel('\tau_H'); ylabel('mode / SRC'); title(titles{j}); grid on;
end
legend(cmp,'Interpreter','none','Location','bestoutside');
sgtitle('0493x7w ratios aligned on monotone convective age \tau_H');
local_save_figure(fig,outDir,'x7w_step_tau_aligned_ratios_0493x7w',opt);
end

function local_plot_tau_window_metrics(P,modes,opt,outDir)
if isempty(P), return; end
vis='off'; if logical(opt.ShowFigures), vis='on'; end
fig=figure('Visible',vis,'Color','w','Name','0493x7w tau-window ratios','Position',[90 90 1600 820]);
tiledlayout(2,5,'Padding','compact','TileSpacing','compact');
metrics={'meanDarcyPowerPerMassCsv','meanSolidLeakRmsCsv','coherentDarcyUxOverUe','coherentInterfaceSlipRatio', ...
    'coherentGammaGeneratorStar','coherentGammaNearStar','coherentSectionSurvival0p5To1p5','coherentDivNearStar', ...
    'coherentRecirculationAreaOverH2','coherentReattachLengthH'};
titles={'Darcy power / mass','Darcy solid leak','Coherent Darcy u_x/U_e','Coherent interface slip', ...
    'Coherent vorticity generation','Coherent near-wake vorticity','Coherent vorticity survival','Coherent near-wake divergence', ...
    'Coherent recirculation area','Coherent L_r/H'};
cmp=modes(~strcmp(modes,'src'));
for j=1:numel(metrics)
    nexttile; hold on;
    for i=1:numel(cmp)
        A=P(P.mode==string(cmp{i}) & P.metric==string(metrics{j}),:); A=sortrows(A,'windowId');
        if isempty(A), continue; end
        xc=0.5*(A.tauStart+A.tauEnd);
        plot(xc,A.ratioToSrc,'-o','LineWidth',1.2,'DisplayName',cmp{i});
    end
    yline(1,':'); xlabel('window center \tau_H'); ylabel('mode / SRC'); title(titles{j}); grid on;
end
legend(cmp,'Interpreter','none','Location','bestoutside');
sgtitle('0493x7w tau-window ratios; coherent quantities are computed after velocity averaging');
local_save_figure(fig,outDir,'x7w_step_tau_window_ratios_0493x7w',opt);
end

function local_plot_tau_window_fields(F,W,cases,geom,opt,outDir)
if isempty(F)||isempty(W), return; end
vis='off'; if logical(opt.ShowFigures), vis='on'; end
windows=unique(W.windowId); nModes=numel(cases);
for iw=1:numel(windows)
    wid=windows(iw);
    keep=cellfun(@(e) ~isempty(e) && isfield(e,'windowId') && e.windowId==wid,F);
    entries=F(keep);
    if isempty(entries), continue; end
    fields=cell(nModes,1); subtitles=strings(nModes,1); metricsRows=cell(nModes,1);
    valid=true;
    for im=1:nModes
        idx=find(cellfun(@(e) ~isempty(e) && string(e.mode)==string(cases(im).mode),entries),1);
        if isempty(idx) || isempty(entries{idx}.field), valid=false; break; end
        fields{im}=entries{idx}.field;
        rr=W(W.windowId==wid & W.mode==string(cases(im).mode),:); metricsRows{im}=rr;
        subtitles(im)=sprintf('%s | frames=%d | N_eff=%.2f',cases(im).mode,entries{idx}.nFramesContributing,entries{idx}.effectiveFrames);
    end
    if ~valid, continue; end
    wlim=local_common_abs_limit(fields,'omegaStar',99.0); dlim=local_common_abs_limit(fields,'divStar',99.0);
    uxmin=Inf; uxmax=-Inf;
    for im=1:nModes
        v=fields{im}.UxStar(:); v=v(isfinite(v)); if ~isempty(v), uxmin=min(uxmin,min(v)); uxmax=max(uxmax,max(v)); end
    end
    a=entries{1}.tauStart; b=entries{1}.tauEnd;
    fig=figure('Visible',vis,'Color','w','Name',sprintf('0493x7w mean fields tau %.1f-%.1f',a,b),'Position',[60 60 1550 300*nModes]);
    tiledlayout(nModes,3,'Padding','compact','TileSpacing','compact');
    for im=1:nModes
        fld=fields{im}; rr=metricsRows{im};
        nexttile; imagesc(fld.xc,fld.yc,fld.UxStar); axis xy equal tight; caxis([uxmin uxmax]); colorbar;
        title(subtitles(im),'Interpreter','none'); ylabel('y'); if im==nModes,xlabel('x');end
        hold on; local_overlay_step(geom); contour(fld.xc,fld.yc,fld.UxStar,[0 0],'k--','LineWidth',1.0); hold off;
        if ~isempty(rr)
            text(0.01,0.03,sprintf('A_{rec}/H^2=%.3g  L_r/H=%s',rr.coherentRecirculationAreaOverH2(1),local_num_string(rr.coherentReattachLengthH(1))), ...
                'Units','normalized','BackgroundColor','w','Margin',2,'Interpreter','tex');
        end
        nexttile; imagesc(fld.xc,fld.yc,fld.omegaStar); axis xy equal tight; caxis([-wlim wlim]); colorbar; title('curl(<u/U_e>) H');
        if im==nModes,xlabel('x');end; hold on; local_overlay_step(geom); hold off;
        nexttile; imagesc(fld.xc,fld.yc,fld.divStar); axis xy equal tight; caxis([-dlim dlim]); colorbar; title('div(<u/U_e>) H');
        if im==nModes,xlabel('x');end; hold on; local_overlay_step(geom); hold off;
    end
    sgtitle(sprintf('0493x7w coherent mean fields | \tau_H in [%.1f, %.1f]',a,b));
    tag=sprintf('tau_%g_%g',a,b); tag=strrep(tag,'.','p');
    local_save_figure(fig,outDir,['x7w_step_tau_window_fields_' tag '_0493x7w'],opt);
end
end


function local_plot_modes(T,modes,xfield,yfield,varargin)
style='-'; if ~isempty(varargin), style=varargin{1}; end
for i=1:numel(modes)
    A=T(T.mode==string(modes{i}),:); A=sortrows(A,xfield); plot(A.(xfield),A.(yfield),style,'LineWidth',1.2,'DisplayName',modes{i});
end
end
function local_overlay_step(g)
plot([g.xMin g.xMax g.xMax g.xMin g.xMin],[g.yMin g.yMin g.yMax g.yMax g.yMin],'k-','LineWidth',1.0);
end
function lim=local_common_abs_limit(F,field,pct)
v=[];
for i=1:numel(F)
    raw=F{i}.(field);
    a=abs(raw(:));
    a=a(isfinite(a));
    v=[v;a]; %#ok<AGROW>
end
if isempty(v), lim=1; else, lim=local_percentile(v,pct); if ~(isfinite(lim)&&lim>0), lim=max(v); end, end
end
function local_save_figure(fig,outDir,name,opt)
png=fullfile(outDir,[name '.png']);
exportgraphics(fig,png,'Resolution',180);
if logical(opt.WritePdf)
    try
        exportgraphics(fig,fullfile(outDir,[name '.pdf']),'ContentType','vector');
    catch ME
        warning('0493x7w:pdfExport','PDF export failed for %s: %s',name,ME.message);
    end
end
end

% =========================================================================
% Summary printing
% =========================================================================
function local_print_summary(S,P,Wf,Wp,geom,outDir)
fprintf('\n===== 0493x7w PERIODIC DARCY STEP ANALYSIS -- TAU-ALIGNED =====\n');
fprintf('H=%.8g downstreamClearance/H=%.4g\n',geom.H,geom.downstreamClearance/geom.H);
if ~isempty(S), fprintf('scalar comparison range: tau_H=[%.3f, %.3f]\n',S.summaryTauStart(1),S.summaryTauEnd(1)); end
for i=1:height(S)
    fprintf('%-12s B0=%g B1=%g nu=%s Ue:% .5f -> % .5f tauH=%.3f kBTf=%s q6Ff=%s q6Af=%s\n', ...
        char(S.mode(i)),S.B0(i),S.B1(i),local_num_string(S.nu(i)),S.firstUe(i),S.lastUe(i),S.finalTauH(i), ...
        local_num_string(S.finalKBT(i)),local_num_string(S.finalQ6F(i)),local_num_string(S.finalQ6A(i)));
    fprintf('             tau-mean Darcy/Ue=% .4g slip=% .4g Ggen*=% .4g Gnear*=% .4g Ssec=% .4g divNear*=% .4g uyNear/Ue=% .4g\n', ...
        S.tauMeanDarcyUxOverUe(i),S.tauMeanInterfaceSlipRatio(i),S.tauMeanGammaGeneratorStar(i),S.tauMeanGammaNearStar(i), ...
        S.tauMeanSectionSurvival0p5To1p5(i),S.tauMeanDivNearStar(i),S.tauMeanUyNearRmsOverUe(i));
    fprintf('             tau-mean darcy_cost: power/M=%s solidLeakRms=%s meanSpeedRms=%s\n', ...
        local_num_string(S.tauMeanDarcyPowerPerMassCsv(i)),local_num_string(S.tauMeanSolidLeakRmsCsv(i)),local_num_string(S.tauMeanDarcySpeedRmsCsv(i)));
    if S.mode(i)~="src"
        fprintf('             tau-aligned ratios to SRC: power=%.4g leak=%.4g Darcy=%.4g slip=%.4g Ggen=%.4g Gnear=%.4g Ssec=%.4g divNear=%.4g uyNear=%.4g\n', ...
            S.tauRatioDarcyPowerToSrc(i),S.tauRatioSolidLeakToSrc(i),S.tauRatioDarcyUxToSrc(i),S.tauRatioSlipToSrc(i), ...
            S.tauRatioGammaGeneratorToSrc(i),S.tauRatioGammaNearToSrc(i),S.tauRatioSectionSurvivalToSrc(i), ...
            S.tauRatioDivNearToSrc(i),S.tauRatioUyNearToSrc(i));
    end
end

if ~isempty(Wf)
    fprintf('\n--- coherent fields: metrics computed AFTER <u/Ue> tau-window averaging ---\n');
    wins=unique(Wf.windowId);
    for iw=1:numel(wins)
        A=Wf(Wf.windowId==wins(iw),:); if isempty(A), continue; end
        fprintf('tau_H=[%.1f, %.1f]\n',A.tauStart(1),A.tauEnd(1));
        for ir=1:height(A)
            fprintf('  %-12s cov=%.3f Neff=%.2f Darcy=% .4g slip=% .4g Ggen*=%.4g Gnear*=%.4g Ssec=%.4g divNear*=%.4g recirc/H2=%.4g Lr/H=%s\n', ...
                char(A.mode(ir)),A.coverageFraction(ir),A.effectiveFrames(ir),A.coherentDarcyUxOverUe(ir),A.coherentInterfaceSlipRatio(ir), ...
                A.coherentGammaGeneratorStar(ir),A.coherentGammaNearStar(ir),A.coherentSectionSurvival0p5To1p5(ir), ...
                A.coherentDivNearStar(ir),A.coherentRecirculationAreaOverH2(ir),local_num_string(A.coherentReattachLengthH(ir)));
            if A.mode(ir)~="src" && ~isempty(Wp)
                fprintf('               ratios/SRC: Darcy=%.4g slip=%.4g Ggen=%.4g Gnear=%.4g Ssec=%.4g divNear=%.4g recirc=%.4g Lr=%.4g\n', ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentDarcyUxOverUe'), ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentInterfaceSlipRatio'), ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentGammaGeneratorStar'), ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentGammaNearStar'), ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentSectionSurvival0p5To1p5'), ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentDivNearStar'), ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentRecirculationAreaOverH2'), ...
                    local_window_pair_value(Wp,A.mode(ir),wins(iw),'coherentReattachLengthH'));
            end
        end
    end
end

if ~isempty(P)
    fprintf('\nInterpretation guard:\n');
    fprintf('  Cross-mode scalar ratios are interpolated at common monotone tau_H; same-Ue matching is not used.\n');
    fprintf('  Recirculation/Lr and coherent vorticity/divergence come from tau-window-averaged normalized velocity fields.\n');
    fprintf('  Q6 ~= Q6GF != SRC at interface/edge => common Q6 mechanism; B1 alone cannot explain it.\n');
    fprintf('  SRC ~= Q6 but Q6GF differs => GF/B1-specific path remains plausible.\n');
    fprintf('  Same coherent edge generation and transport as SRC => generic Darcy/chi damping is strongly disfavoured.\n');
end
fprintf('outputDir=%s\nstatus=COMPLETE\n',outDir);
end

function v=local_window_pair_value(P,mode,windowId,metric)
idx=P.mode==string(mode) & P.windowId==windowId & P.metric==string(metric) & isfinite(P.ratioToSrc);
if any(idx), v=P.ratioToSrc(find(idx,1,'first')); else, v=NaN; end
end


% =========================================================================
% Generic helpers
% =========================================================================
function v=local_param_num(s,names,default)
v=default;
for i=1:numel(names)
    f=matlab.lang.makeValidName(names{i});
    if ~isfield(s,f), continue; end
    x=s.(f);
    if isnumeric(x)||islogical(x)
        x=double(x);
    else
        x=str2double(char(string(x)));
    end
    if isfinite(x)
        v=x;
        return;
    end
end
end

function t=local_param_text(s,names,default)
t=default;
for i=1:numel(names)
    f=matlab.lang.makeValidName(names{i});
    if isfield(s,f)
        t=char(string(s.(f)));
        return;
    end
end
end

function v=local_struct_num(s,name,default)
v=default;
f=matlab.lang.makeValidName(name);
if ~isfield(s,f), return; end
x=s.(f);
if isnumeric(x)||islogical(x)
    x=double(x);
else
    x=str2double(char(string(x)));
end
if isfinite(x), v=x; end
end

function r=local_safe_ratio(a,b)
if isfinite(a)&&isfinite(b)&&abs(b)>1e-14
    r=a/b;
else
    r=NaN;
end
end

function r=local_rel_diff(a,b)
if isfinite(a)&&isfinite(b)
    r=abs(a-b)/max(abs(b),1e-14);
else
    r=NaN;
end
end

function p=local_percentile(v,q)
v=sort(v(isfinite(v)));
if isempty(v), p=NaN; return; end
q=max(0,min(100,q));
pos=1+(numel(v)-1)*q/100;
lo=floor(pos); hi=ceil(pos);
if lo==hi
    p=v(lo);
else
    p=v(lo)+(pos-lo)*(v(hi)-v(lo));
end
end

function s=local_num_string(x)
if isfinite(x)
    s=sprintf('%.6g',x);
else
    s='NaN';
end
end

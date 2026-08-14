function suite = analyze_vk_vorticity_transport_0493x7u(varargin)
%ANALYZE_VK_VORTICITY_TRANSPORT_0493X7U Quantify VK wake transport from existing dumps.
%
% This analysis is designed for execution from the repository matlab/ directory.
% Its default discovery root is therefore '../runs/*'.  It does not rerun the
% solver and does not require filtered-field recordings: it reads the existing
% state_step_*.smpcd particle dumps, deposits them on one common physical grid,
% and compares the evolution of mean flow and vorticity across available modes.
%
% Main objectives:
%   1) measure the actual upstream velocity and Reynolds-number history;
%   2) separate vorticity generation at the cylinder from downstream survival;
%   3) quantify organized alternating shedding independently of visual filtering;
%   4) detect periodic-domain wrap-around before interpreting late-time data.
%
% Typical usage from matlab/:
%
%   suite = analyze_vk_vorticity_transport_0493x7u( ...
%       'RunPatterns', {'../runs/0434_vk_darcy_chi_periodic_*'}, ...
%       'MakePlots', true, 'ShowFigures', true);
%
% To discover all VK-like runs below ../runs/:
%
%   suite = analyze_vk_vorticity_transport_0493x7u('RunPatterns', {'../runs/*'});
%
% The current x7t transverse-shear viscosities are applied automatically ONLY
% when the run matches the calibrated signature a=0.002, gamma=6, dt=5e-4,
% kBT=5, rotationAngle=80 deg.  Otherwise Re is left unavailable unless a
% viscosity override is supplied.
%
% Viscosity override examples:
%
%   nu = struct('src',1.18720273e-3, ...
%               'src_q6',7.59568145e-4, ...
%               'src_q6_g_f',1.24451358e-3);
%   suite = analyze_vk_vorticity_transport_0493x7u( ...
%       'RunPatterns', {'../runs/my_vk_case'}, 'ModeViscosities', nu);
%
% Outputs under ../runs/vk_vorticity_transport_0493x7u_analysis by default:
%   vk_vorticity_timeseries_0493x7u.csv
%   vk_vorticity_summary_0493x7u.csv
%   vk_vorticity_regions_0493x7u.csv
%   vk_vorticity_sensitivity_0493x7u.csv          (when enabled)
%   vk_vorticity_fields_<case>.csv
%   vk_vorticity_suite_0493x7u.mat
%   diagnostic PNG/PDF figures
%
% Existing repository helpers used:
%   read_smpcd_state.m, bin_smpcd_state.m, parse_smpcd_kv.m
%
% 0493x7u is post-processing only; it does not modify simulation physics.

p = inputParser;
p.FunctionName = 'analyze_vk_vorticity_transport_0493x7u';
addParameter(p, 'RunPatterns', {'../runs/*'}, @(x) ischar(x) || isstring(x) || iscell(x));
addParameter(p, 'OutputDir', '../runs/vk_vorticity_transport_0493x7u_analysis', @(x) ischar(x) || isstring(x));
addParameter(p, 'AnalysisCellsPerDiameter', 20, @(x) isnumeric(x) && isscalar(x) && x >= 8);
addParameter(p, 'SensitivityCheck', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'SensitivityCellsPerDiameter', 16, @(x) isnumeric(x) && isscalar(x) && x >= 8);
addParameter(p, 'DumpStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'MaxDumps', Inf, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'FluidRole', 1, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'FirstPassStartDiameters', 4.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'WrapLimitDomainTransits', 0.80, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'UpstreamXRangeD', [-1.75 -1.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'UpstreamWallMarginD', 0.50, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'GeneratorThicknessD', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'WakeHalfHeightD', 1.50, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'NearWakeXRangeD', [0.75 3.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'MidWakeXRangeD', [3.00 7.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'FarWakeXRangeD', [7.00 12.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'ProbeXD', [2.0 4.0], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'ProbeHalfWidthD', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'ProbeHalfHeightD', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'DeficitXD', [2.0 4.0 8.0], @(x) isnumeric(x) && numel(x) >= 1);
addParameter(p, 'DeficitHalfWidthD', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'LowKMaxIndex', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'ModeViscosities', struct(), @isstruct);
addParameter(p, 'AutoUseX7TViscosities', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'MakePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ShowFigures', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'WriteFieldCsv', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

outDir = char(opt.OutputDir);
if ~exist(outDir, 'dir'), mkdir(outDir); end

patterns = local_cellstr(opt.RunPatterns);
cases = local_discover_cases(patterns);
if isempty(cases)
    error('analyze_vk_vorticity_transport_0493x7u:noCases', ...
        'No VK-like run with state_step_*.smpcd dumps was found under the requested ../runs patterns.');
end

fprintf('[0493x7u] discovered %d VK mode run(s)\n', numel(cases));
for i = 1:numel(cases)
    fprintf('[0493x7u]   %2d  mode=%-12s  run=%s\n', i, cases(i).mode, cases(i).runDir);
end

caseResults = cell(numel(cases), 1);
allRows = cell(numel(cases), 1);
summaryRows = cell(numel(cases), 1);
regionRows = cell(numel(cases), 1);
sensitivityRows = {};

for i = 1:numel(cases)
    fprintf('\n[0493x7u] ===== case %d/%d: %s =====\n', i, numel(cases), cases(i).label);
    result = local_analyze_case(cases(i), opt, outDir);
    caseResults{i} = result;
    allRows{i} = result.timeseries;
    summaryRows{i} = result.summary;
    regionRows{i} = result.regionTable;
    if ~isempty(result.sensitivity)
        sensitivityRows{end+1,1} = result.sensitivity; %#ok<AGROW>
    end
end

T = vertcat(allRows{:});
S = vertcat(summaryRows{:});
R = vertcat(regionRows{:});

writetable(T, fullfile(outDir, 'vk_vorticity_timeseries_0493x7u.csv'));
writetable(S, fullfile(outDir, 'vk_vorticity_summary_0493x7u.csv'));
writetable(R, fullfile(outDir, 'vk_vorticity_regions_0493x7u.csv'));

if ~isempty(sensitivityRows)
    Q = vertcat(sensitivityRows{:});
    writetable(Q, fullfile(outDir, 'vk_vorticity_sensitivity_0493x7u.csv'));
else
    Q = table();
end

suite = struct();
suite.cases = cases;
suite.results = caseResults;
suite.timeseries = T;
suite.summary = S;
suite.regions = R;
suite.sensitivity = Q;
suite.options = opt;
suite.outputDir = outDir;
save(fullfile(outDir, 'vk_vorticity_suite_0493x7u.mat'), 'suite', '-v7.3');

if logical(opt.MakePlots)
    local_make_comparison_plots(caseResults, S, opt, outDir);
end

fprintf('\n===== 0493x7u VK VORTICITY TRANSPORT =====\n');
for i = 1:height(S)
    fprintf('%s | mode=%s | Uinf=%.6g | Re=%.6g | omegaGen*=%.6g | omegaNear*=%.6g | SgenNear=%.6g | St=%s | peak=%.4g | corr=%.4g\n', ...
        char(S.caseLabel(i)), char(S.mode(i)), S.UinfMeanFirstPass(i), S.ReMeanFirstPass(i), ...
        S.omegaGeneratorStarMeanFirstPass(i), S.omegaNearStarMeanFirstPass(i), ...
        S.vorticitySurvivalGeneratorToNear(i), local_num_string(S.Strouhal(i)), ...
        S.spectralPeakFraction(i), S.probe2D4DCorrelation(i));
end
fprintf('timeseries=%s\n', fullfile(outDir, 'vk_vorticity_timeseries_0493x7u.csv'));
fprintf('summary=%s\n', fullfile(outDir, 'vk_vorticity_summary_0493x7u.csv'));
fprintf('regions=%s\n', fullfile(outDir, 'vk_vorticity_regions_0493x7u.csv'));
if ~isempty(sensitivityRows)
    fprintf('sensitivity=%s\n', fullfile(outDir, 'vk_vorticity_sensitivity_0493x7u.csv'));
end
fprintf('status=COMPLETE\n');
end

% -------------------------------------------------------------------------
function result = local_analyze_case(c, opt, outDir)
params = parse_smpcd_kv(c.paramsFile);
[Lx, Ly, NxNative, NyNative, dt, gamma, kBT, rotationAngle] = local_basic_params(params);
periodicX = local_axis_periodic(params, 'x');
periodicY = local_axis_periodic(params, 'y');
[cx, cy, R] = local_cylinder(params);
D = 2 * R;
if ~(all(isfinite([Lx Ly NxNative NyNative dt cx cy R])) && Lx > 0 && Ly > 0 && NxNative > 0 && NyNative > 0 && dt > 0 && R > 0)
    error('analyze_vk_vorticity_transport_0493x7u:badParams', ...
        'Incomplete geometry/grid parameters for %s (%s).', c.label, c.paramsFile);
end

analysisDxTarget = D / double(opt.AnalysisCellsPerDiameter);
NxA = max(8, round(Lx / analysisDxTarget));
NyA = max(8, round(Ly / analysisDxTarget));

if logical(opt.SensitivityCheck)
    sensDxTarget = D / double(opt.SensitivityCellsPerDiameter);
    NxS = max(8, round(Lx / sensDxTarget));
    NyS = max(8, round(Ly / sensDxTarget));
else
    NxS = NaN; NyS = NaN;
end

frames = local_list_frames(c.outputDir, dt, opt.DumpStride, opt.MaxDumps);
if isempty(frames)
    error('analyze_vk_vorticity_transport_0493x7u:noFrames', 'No dumps in %s', c.outputDir);
end

[nu, nuSource] = local_resolve_viscosity(c.mode, params, Lx, Ly, NxNative, NyNative, dt, gamma, kBT, rotationAngle, opt);
regions = local_regions(Lx, Ly, cx, cy, R, opt);

rows = repmat(local_empty_row(), height(frames), 1);
if logical(opt.SensitivityCheck)
    sensRaw = repmat(local_empty_sensitivity_row(), height(frames), 1);
else
    sensRaw = repmat(local_empty_sensitivity_row(), 0, 1);
end

sumOmega = zeros(NyA, NxA);
sumOmegaSq = zeros(NyA, NxA);
sumUx = zeros(NyA, NxA);
sumUy = zeros(NyA, NxA);
sumN = zeros(NyA, NxA);
fieldSelected = false(height(frames), 1);
tauDcum = 0.0;
tauLcum = 0.0;
prevTime = NaN;
prevUup = NaN;

for k = 1:height(frames)
    st = read_smpcd_state(char(frames.fullPath(k)));
    fld = bin_smpcd_state(st, 'Lx', Lx, 'Ly', Ly, 'Nx', NxA, 'Ny', NyA, ...
        'periodicX', periodicX, 'periodicY', periodicY, 'fluidOnly', true);
    fld.omega = local_vorticity(fld.Ux, fld.Uy, fld.dx, fld.dy, periodicX, periodicY);
    row = local_frame_metrics(st, fld, frames.step(k), frames.time(k), c, nu, nuSource, ...
        Lx, Ly, cx, cy, R, regions, opt);

    % Build the convective clocks online so the first-pass mean fields can be
    % accumulated during this same particle read. This avoids a second pass over
    % large VK dump files.
    if k > 1 && isfinite(prevTime) && isfinite(row.time) && row.time >= prevTime && ...
            isfinite(prevUup) && isfinite(row.Uupstream)
        dtk = row.time - prevTime;
        distance = 0.5 * (max(0,prevUup) + max(0,row.Uupstream)) * dtk;
        tauDcum = tauDcum + distance / D;
        tauLcum = tauLcum + distance / Lx;
    end
    row.tauD = tauDcum;
    row.tauL = tauLcum;
    row.window = local_window_label(row.tauD, row.tauL, opt);
    rows(k) = row;

    if logical(opt.SensitivityCheck)
        fs = bin_smpcd_state(st, 'Lx', Lx, 'Ly', Ly, 'Nx', NxS, 'Ny', NyS, ...
            'periodicX', periodicX, 'periodicY', periodicY, 'fluidOnly', true);
        fs.omega = local_vorticity(fs.Ux, fs.Uy, fs.dx, fs.dy, periodicX, periodicY);
        sensRaw(k) = local_sensitivity_metrics(fs, row, cx, cy, R, regions, opt);
    end

    if strcmp(row.window, "first_pass")
        sumOmega = sumOmega + local_nan_to_zero(fld.omega);
        sumOmegaSq = sumOmegaSq + local_nan_to_zero(fld.omega).^2;
        sumUx = sumUx + local_nan_to_zero(fld.Ux);
        sumUy = sumUy + local_nan_to_zero(fld.Uy);
        sumN = sumN + fld.N;
        fieldSelected(k) = true;
    end

    fprintf('[0493x7u] %s %3d/%3d step=%g Uinf=%.6g Re=%s tauD=%.3g tauL=%.3g omegaGen*=%.4g omegaNear*=%.4g Aomega*=%.4g\n', ...
        c.mode, k, height(frames), frames.step(k), row.Uupstream, local_num_string(row.ReD), ...
        row.tauD, row.tauL, row.omegaGeneratorStar, row.omegaNearStar, row.antisymmetricOmegaStar);
    prevTime = row.time;
    prevUup = row.Uupstream;
end

tauD = [rows.tauD].';
tauL = [rows.tauL].';
firstPass = strcmp(string({rows.window}.'), "first_pass");
if nnz(firstPass) < 4
    warning('0493x7u:firstPassSparse', ...
        '%s has only %d first-pass frames (tauD>=%.3g, tauL<%.3g). Summary shedding metrics may be unavailable.', ...
        c.label, nnz(firstPass), opt.FirstPassStartDiameters, opt.WrapLimitDomainTransits);
end

% If no first-pass frame exists, retain a diagnostic all-frame field average
% rather than returning empty fields. This fallback is explicitly marked in the
% summary and does not silently qualify shedding.
if nnz(fieldSelected) == 0
    for k = 1:height(frames)
        st = read_smpcd_state(char(frames.fullPath(k)));
        fld = bin_smpcd_state(st, 'Lx', Lx, 'Ly', Ly, 'Nx', NxA, 'Ny', NyA, ...
            'periodicX', true, 'periodicY', false, 'fluidOnly', true);
        fld.omega = local_vorticity(fld.Ux, fld.Uy, fld.dx, fld.dy, true, false);
        sumOmega = sumOmega + local_nan_to_zero(fld.omega);
        sumOmegaSq = sumOmegaSq + local_nan_to_zero(fld.omega).^2;
        sumUx = sumUx + local_nan_to_zero(fld.Ux);
        sumUy = sumUy + local_nan_to_zero(fld.Uy);
        sumN = sumN + fld.N;
        fieldSelected(k) = true;
    end
end
nField = max(1, nnz(fieldSelected));
meanFields = struct();
meanFields.omegaMean = sumOmega / nField;
meanFields.omegaRms = sqrt(max(sumOmegaSq / nField, 0));
meanFields.UxMean = sumUx / nField;
meanFields.UyMean = sumUy / nField;
meanFields.NMean = sumN / nField;
meanFields.xc = ((0:NxA-1)+0.5) * Lx / NxA;
meanFields.yc = ((0:NyA-1)+0.5) * Ly / NyA;
meanFields.Nx = NxA; meanFields.Ny = NyA;
meanFields.dx = Lx/NxA; meanFields.dy = Ly/NyA;
meanFields.firstPassMask = firstPass;

T = struct2table(rows);
T.caseLabel(:) = string(c.label);
T.parentRun(:) = string(c.parentRun);
T.runDir(:) = string(c.runDir);
T.mode(:) = string(c.mode);
T.paramsFile(:) = string(c.paramsFile);
T.nuSource(:) = string(nuSource);

shed = local_shedding_metrics(T, firstPass, D);
recirc = local_recirculation_length(meanFields, cx, cy, R, D);
summary = local_summary_row(T, c, nu, nuSource, firstPass, shed, recirc, ...
    Lx, Ly, NxNative, NyNative, NxA, NyA, cx, cy, R, gamma, kBT, rotationAngle, periodicX, periodicY, opt);
regionTable = local_region_table(c, regions, D);

if logical(opt.SensitivityCheck)
    sensitivity = local_sensitivity_summary(c, T, sensRaw, firstPass, NxA, NyA, NxS, NyS);
else
    sensitivity = table();
end

prefix = local_safe_name(c.label);
if logical(opt.WriteFieldCsv)
    local_write_field_csv(meanFields, cx, cy, R, regions, ...
        fullfile(outDir, ['vk_vorticity_fields_', prefix, '.csv']));
end
if logical(opt.MakePlots)
    local_make_case_plots(T, meanFields, c, regions, cx, cy, R, opt, outDir);
end

result = struct();
result.case = c;
result.params = params;
result.frames = frames;
result.timeseries = T;
result.summary = summary;
result.regionTable = regionTable;
result.sensitivity = sensitivity;
result.meanFields = meanFields;
result.shedding = shed;
result.regions = regions;
end

% -------------------------------------------------------------------------
function row = local_frame_metrics(st, fld, step, time, c, nu, nuSource, Lx, Ly, cx, cy, R, regions, opt)
D = 2*R;
[X,Y] = meshgrid(fld.xc, fld.yc);
solid = (X-cx).^2 + (Y-cy).^2 <= R^2;
maskGenerator = local_generator_mask(X,Y,cx,cy,R,double(opt.GeneratorThicknessD)*D);
maskNear = local_box_mask(X,Y,regions.nearWake) & ~solid;
maskMid = local_box_mask(X,Y,regions.midWake) & ~solid;
maskFar = local_box_mask(X,Y,regions.farWake) & ~solid;
maskShedding = local_box_mask(X,Y,regions.sheddingWake) & ~solid;
maskUpper = maskShedding & Y > cy;
maskLower = maskShedding & Y < cy;

[UglobalX,UglobalY,totalMass] = local_global_velocity(st, opt.FluidRole);
[Uup, UupY, upMass, upParticles] = local_particle_region_velocity(st, regions.upstream, opt.FluidRole);
if ~isfinite(Uup), Uup = UglobalX; end
if ~isfinite(UupY), UupY = UglobalY; end

scaleU = max(abs(Uup), 1e-12);
cellArea = fld.dx*fld.dy;

[omegaGen, gammaPosGen, gammaNegGen, gammaAbsGen] = local_vorticity_stats(fld.omega, maskGenerator, cellArea);
[omegaNear, gammaPosNear, gammaNegNear, gammaAbsNear] = local_vorticity_stats(fld.omega, maskNear, cellArea);
[omegaMid, gammaPosMid, gammaNegMid, gammaAbsMid] = local_vorticity_stats(fld.omega, maskMid, cellArea);
[omegaFar, gammaPosFar, gammaNegFar, gammaAbsFar] = local_vorticity_stats(fld.omega, maskFar, cellArea);

upperGamma = sum(fld.omega(maskUpper), 'omitnan') * cellArea;
lowerGamma = sum(fld.omega(maskLower), 'omitnan') * cellArea;
netWakeGamma = sum(fld.omega(maskShedding), 'omitnan') * cellArea;
antisymGamma = upperGamma - lowerGamma;

probe2 = local_probe_velocity(fld, cx + double(opt.ProbeXD(1))*D, cy, ...
    double(opt.ProbeHalfWidthD)*D, double(opt.ProbeHalfHeightD)*D);
probe4 = local_probe_velocity(fld, cx + double(opt.ProbeXD(2))*D, cy, ...
    double(opt.ProbeHalfWidthD)*D, double(opt.ProbeHalfHeightD)*D);

defX = double(opt.DeficitXD(:).');
def = nan(1, numel(defX));
for j = 1:numel(defX)
    def(j) = local_wake_deficit(fld, cx + defX(j)*D, cy, Uup, ...
        double(opt.DeficitHalfWidthD)*D, double(opt.WakeHalfHeightD)*D, D);
end

wakeN = fld.N(maskShedding);
Nref = mean(fld.N(~solid), 'omitnan');
p05 = local_percentile(wakeN, 5);
low5 = mean(wakeN < 5, 'omitnan');
lowHalf = mean(wakeN < 0.5*Nref, 'omitnan');
lowK = local_lowk_fraction(fld.omega, maskShedding, round(opt.LowKMaxIndex));

if isfinite(nu) && nu > 0
    ReD = Uup*D/nu;
else
    ReD = NaN;
end

row = local_empty_row();
row.caseLabel = string(c.label);
row.parentRun = string(c.parentRun);
row.runDir = string(c.runDir);
row.mode = string(c.mode);
row.paramsFile = string(c.paramsFile);
row.step = step;
row.time = time;
row.tauD = NaN;
row.tauL = NaN;
row.window = "unclassified";
row.nu = nu;
row.nuSource = string(nuSource);
row.UglobalX = UglobalX;
row.UglobalY = UglobalY;
row.Uupstream = Uup;
row.UupstreamY = UupY;
row.totalFluidMass = totalMass;
row.upstreamMass = upMass;
row.upstreamParticles = upParticles;
row.ReD = ReD;
row.omegaGeneratorRms = omegaGen;
row.omegaNearRms = omegaNear;
row.omegaMidRms = omegaMid;
row.omegaFarRms = omegaFar;
row.omegaGeneratorStar = omegaGen*D/scaleU;
row.omegaNearStar = omegaNear*D/scaleU;
row.omegaMidStar = omegaMid*D/scaleU;
row.omegaFarStar = omegaFar*D/scaleU;
row.gammaPosGenerator = gammaPosGen;
row.gammaNegGenerator = gammaNegGen;
row.gammaAbsGenerator = gammaAbsGen;
row.gammaPosNear = gammaPosNear;
row.gammaNegNear = gammaNegNear;
row.gammaAbsNear = gammaAbsNear;
row.gammaPosMid = gammaPosMid;
row.gammaNegMid = gammaNegMid;
row.gammaAbsMid = gammaAbsMid;
row.gammaPosFar = gammaPosFar;
row.gammaNegFar = gammaNegFar;
row.gammaAbsFar = gammaAbsFar;
row.gammaAbsGeneratorStar = gammaAbsGen/(scaleU*D);
row.gammaAbsNearStar = gammaAbsNear/(scaleU*D);
row.gammaAbsMidStar = gammaAbsMid/(scaleU*D);
row.gammaAbsFarStar = gammaAbsFar/(scaleU*D);
row.netWakeCirculation = netWakeGamma;
row.netWakeCirculationStar = netWakeGamma/(scaleU*D);
row.antisymmetricOmega = antisymGamma;
row.antisymmetricOmegaStar = antisymGamma/(scaleU*D);
row.probeUy2D = probe2.Uy;
row.probeUy4D = probe4.Uy;
row.probeUx2D = probe2.Ux;
row.probeUx4D = probe4.Ux;
row.probeUy2DStar = probe2.Uy/scaleU;
row.probeUy4DStar = probe4.Uy/scaleU;
row.wakeDeficit2D = local_pick(def, defX, 2.0);
row.wakeDeficit4D = local_pick(def, defX, 4.0);
row.wakeDeficit8D = local_pick(def, defX, 8.0);
row.populationReferenceN = Nref;
row.populationP05Wake = p05;
row.populationP05WakeOverReference = p05/max(Nref,eps);
row.populationBelow5FractionWake = low5;
row.populationBelowHalfReferenceFractionWake = lowHalf;
row.omegaLowKFractionWake = lowK;
end

function row = local_empty_row()
row = struct( ...
    'caseLabel',"",'parentRun',"",'runDir',"",'mode',"",'paramsFile',"", ...
    'step',NaN,'time',NaN,'tauD',NaN,'tauL',NaN,'window',"", ...
    'nu',NaN,'nuSource',"", ...
    'UglobalX',NaN,'UglobalY',NaN,'Uupstream',NaN,'UupstreamY',NaN, ...
    'totalFluidMass',NaN,'upstreamMass',NaN,'upstreamParticles',NaN,'ReD',NaN, ...
    'omegaGeneratorRms',NaN,'omegaNearRms',NaN,'omegaMidRms',NaN,'omegaFarRms',NaN, ...
    'omegaGeneratorStar',NaN,'omegaNearStar',NaN,'omegaMidStar',NaN,'omegaFarStar',NaN, ...
    'gammaPosGenerator',NaN,'gammaNegGenerator',NaN,'gammaAbsGenerator',NaN, ...
    'gammaPosNear',NaN,'gammaNegNear',NaN,'gammaAbsNear',NaN, ...
    'gammaPosMid',NaN,'gammaNegMid',NaN,'gammaAbsMid',NaN, ...
    'gammaPosFar',NaN,'gammaNegFar',NaN,'gammaAbsFar',NaN, ...
    'gammaAbsGeneratorStar',NaN,'gammaAbsNearStar',NaN,'gammaAbsMidStar',NaN,'gammaAbsFarStar',NaN, ...
    'netWakeCirculation',NaN,'netWakeCirculationStar',NaN, ...
    'antisymmetricOmega',NaN,'antisymmetricOmegaStar',NaN, ...
    'probeUy2D',NaN,'probeUy4D',NaN,'probeUx2D',NaN,'probeUx4D',NaN, ...
    'probeUy2DStar',NaN,'probeUy4DStar',NaN, ...
    'wakeDeficit2D',NaN,'wakeDeficit4D',NaN,'wakeDeficit8D',NaN, ...
    'populationReferenceN',NaN,'populationP05Wake',NaN,'populationP05WakeOverReference',NaN, ...
    'populationBelow5FractionWake',NaN,'populationBelowHalfReferenceFractionWake',NaN, ...
    'omegaLowKFractionWake',NaN);
end

% -------------------------------------------------------------------------
function s = local_empty_sensitivity_row()
s = struct('step',NaN,'omegaGeneratorStar',NaN,'omegaNearStar',NaN,'omegaMidStar',NaN, ...
    'omegaFarStar',NaN,'antisymmetricOmegaStar',NaN,'omegaLowKFractionWake',NaN);
end

function s = local_sensitivity_metrics(fld, primaryRow, cx, cy, R, regions, opt)
D = 2*R;
[X,Y] = meshgrid(fld.xc, fld.yc);
solid = (X-cx).^2 + (Y-cy).^2 <= R^2;
maskGen = local_generator_mask(X,Y,cx,cy,R,double(opt.GeneratorThicknessD)*D);
maskNear = local_box_mask(X,Y,regions.nearWake) & ~solid;
maskMid = local_box_mask(X,Y,regions.midWake) & ~solid;
maskFar = local_box_mask(X,Y,regions.farWake) & ~solid;
maskShedding = local_box_mask(X,Y,regions.sheddingWake) & ~solid;
maskUpper = maskShedding & Y > cy;
maskLower = maskShedding & Y < cy;
cellArea = fld.dx*fld.dy;
scaleU = max(abs(primaryRow.Uupstream),1e-12);
s = local_empty_sensitivity_row();
s.step = primaryRow.step;
s.omegaGeneratorStar = local_rms(fld.omega(maskGen))*D/scaleU;
s.omegaNearStar = local_rms(fld.omega(maskNear))*D/scaleU;
s.omegaMidStar = local_rms(fld.omega(maskMid))*D/scaleU;
s.omegaFarStar = local_rms(fld.omega(maskFar))*D/scaleU;
s.antisymmetricOmegaStar = (sum(fld.omega(maskUpper),'omitnan') - sum(fld.omega(maskLower),'omitnan'))*cellArea/(scaleU*D);
s.omegaLowKFractionWake = local_lowk_fraction(fld.omega,maskShedding,round(opt.LowKMaxIndex));
end

function Q = local_sensitivity_summary(c, T, sensRaw, firstPass, NxA, NyA, NxS, NyS)
if isempty(sensRaw)
    Q = table(); return;
end
idx = find(firstPass);
if isempty(idx), idx = 1:height(T); end
fields = {'omegaGeneratorStar','omegaNearStar','omegaMidStar','omegaFarStar','antisymmetricOmegaStar','omegaLowKFractionWake'};
caseCol = strings(numel(fields),1);
modeCol = strings(numel(fields),1);
metric = strings(numel(fields),1);
primary = nan(numel(fields),1);
sens = nan(numel(fields),1);
rel = nan(numel(fields),1);
for j = 1:numel(fields)
    f = fields{j};
    caseCol(j) = string(c.label); modeCol(j) = string(c.mode); metric(j) = string(f);
    col = T.(f);
    primary(j) = mean(col(idx), 'omitnan');
    v = nan(numel(idx),1);
    for kk = 1:numel(idx), v(kk) = sensRaw(idx(kk)).(f); end
    sens(j) = mean(v,'omitnan');
    rel(j) = abs(primary(j)-sens(j))/max(abs(primary(j)),eps);
end
Q = table(caseCol,modeCol,metric,repmat(NxA,numel(fields),1),repmat(NyA,numel(fields),1), ...
    repmat(NxS,numel(fields),1),repmat(NyS,numel(fields),1),primary,sens,rel, ...
    'VariableNames',{'caseLabel','mode','metric','primaryNx','primaryNy','sensitivityNx','sensitivityNy','primaryMean','sensitivityMean','relativeDifference'});
end

% -------------------------------------------------------------------------
function shed = local_shedding_metrics(T, firstPass, D)
idx = find(firstPass & isfinite(T.time));
shed = struct('frequency',NaN,'Strouhal',NaN,'status',"INSUFFICIENT_DATA", ...
    'spectralPeakFraction',NaN,'probeFrequency2D',NaN,'probeFrequency4D',NaN, ...
    'antisymFrequency',NaN,'probe2D4DCorrelation',NaN,'probeLag',NaN, ...
    'convectionVelocity',NaN,'cyclesObserved',NaN,'windowDuration',NaN);
if numel(idx) < 8
    return;
end

t = T.time(idx);
u = T.Uupstream(idx);
y2 = T.probeUy2DStar(idx);
y4 = T.probeUy4DStar(idx);
ya = T.antisymmetricOmegaStar(idx);

[f2,p2,~] = local_dominant_frequency(t,y2);
[f4,p4,~] = local_dominant_frequency(t,y4);
[fa,pa,~] = local_dominant_frequency(t,ya);
[cc,lag] = local_best_lag_correlation(t,y2,y4);

candidates = [f2 f4 fa];
valid = isfinite(candidates) & candidates > 0;
if any(valid)
    f = median(candidates(valid));
else
    f = NaN;
end
peakFraction = mean([p2 p4 pa], 'omitnan');
duration = max(t)-min(t);
cycles = f*duration;
Umean = mean(u,'omitnan');
if isfinite(f) && isfinite(Umean) && abs(Umean)>eps
    St = f*D/abs(Umean);
else
    St = NaN;
end

freqAgreement = true;
if isfinite(f2) && isfinite(f4) && f2>0 && f4>0
    freqAgreement = abs(f2-f4)/max(0.5*(f2+f4),eps) <= 0.20;
end
if ~(isfinite(f) && cycles >= 3)
    status = "INSUFFICIENT_CYCLES";
elseif ~freqAgreement
    status = "PROBE_FREQUENCY_MISMATCH";
elseif ~(isfinite(peakFraction) && peakFraction >= 0.20)
    status = "NO_COHERENT_PEAK";
else
    status = "VALID";
end

if isfinite(lag) && abs(lag)>eps
    Uconv = (2*D)/abs(lag);
else
    Uconv = NaN;
end

shed.frequency = f;
shed.Strouhal = St;
shed.status = status;
shed.spectralPeakFraction = peakFraction;
shed.probeFrequency2D = f2;
shed.probeFrequency4D = f4;
shed.antisymFrequency = fa;
shed.probe2D4DCorrelation = cc;
shed.probeLag = lag;
shed.convectionVelocity = Uconv;
shed.cyclesObserved = cycles;
shed.windowDuration = duration;
end

function [fdom, peakFraction, spectrum] = local_dominant_frequency(t, y)
spectrum = struct('f',[],'power',[]);
fdom = NaN; peakFraction = NaN;
ok = isfinite(t) & isfinite(y);
t = t(ok); y = y(ok);
if numel(t)<8, return; end
[tu,ia] = unique(t,'stable'); y = y(ia); t = tu;
if numel(t)<8, return; end
dt = median(diff(t));
if ~(isfinite(dt) && dt>0), return; end
% Require nearly uniform dump spacing; interpolate tiny irregularities only.
tUniform = (t(1):dt:t(end)).';
if numel(tUniform) >= 8 && numel(tUniform) ~= numel(t)
    y = interp1(t,y,tUniform,'linear','extrap'); t=tUniform;
end
y = y - mean(y,'omitnan');
% Linear detrend without relying on Signal Processing Toolbox.
x = t - mean(t);
coef = [ones(numel(x),1) x] \ y;
y = y - [ones(numel(x),1) x]*coef;
n = numel(y);
if local_rms(y) <= 1e-14, return; end
Y = fft(y);
pow = abs(Y).^2;
f = (0:n-1).'/(n*dt);
pos = (1:floor(n/2)+1).';
f = f(pos); pow = pow(pos);
if numel(f)<=1, return; end
f = f(2:end); pow = pow(2:end); % remove DC
if isempty(pow) || sum(pow)<=0, return; end
[pk,im] = max(pow);
fdom = f(im);
peakFraction = pk/sum(pow);
spectrum.f = f;
spectrum.power = pow;
end

function [bestCorr,bestLag] = local_best_lag_correlation(t,a,b)
bestCorr=NaN; bestLag=NaN;
ok=isfinite(t)&isfinite(a)&isfinite(b);
t=t(ok); a=a(ok); b=b(ok);
if numel(t)<8, return; end
dt=median(diff(t));
a=a-mean(a); b=b-mean(b);
sa=std(a); sb=std(b);
if ~(sa>0 && sb>0), return; end
maxLagSamples=min(floor(numel(a)/3), max(1,round(0.5/max(dt,eps))));
best=-Inf; lagBest=0;
for lag=-maxLagSamples:maxLagSamples
    if lag>=0
        aa=a(1:end-lag); bb=b(1+lag:end);
    else
        l=-lag; aa=a(1+l:end); bb=b(1:end-l);
    end
    if numel(aa)<5, continue; end
    den=sqrt(sum(aa.^2)*sum(bb.^2));
    if den<=0, continue; end
    r=sum(aa.*bb)/den;
    if abs(r)>best
        best=abs(r); bestCorr=r; lagBest=lag;
    end
end
if isfinite(bestCorr), bestLag=lagBest*dt; end
end

% -------------------------------------------------------------------------
function S = local_summary_row(T,c,nu,nuSource,firstPass,shed,recirc,Lx,Ly,Nx,Ny,NxA,NyA,cx,cy,R,gamma,kBT,rotationAngle,periodicX,periodicY,opt)
idx=find(firstPass);
if isempty(idx), idx=(1:height(T)).'; windowSource="all_frames_fallback"; else, windowSource="first_pass"; end
m=@(name) local_table_mean(T,name,idx);
mn=@(name) local_table_min(T,name,idx);
rmsf=@(name) local_table_rms(T,name,idx);

S=table(string(c.label),string(c.parentRun),string(c.runDir),string(c.mode),string(c.paramsFile), ...
    height(T),numel(idx),windowSource,Lx,Ly,Nx,Ny,NxA,NyA,cx,cy,R,2*R,gamma,kBT,rotationAngle, ...
    logical(periodicX),logical(periodicY),nu,string(nuSource),m('Uupstream'),mn('Uupstream'),m('UglobalX'),m('ReD'),mn('ReD'), ...
    m('tauD'),max(T.tauD),max(T.tauL), ...
    m('omegaGeneratorStar'),m('omegaNearStar'),m('omegaMidStar'),m('omegaFarStar'), ...
    m('omegaNearStar')/max(m('omegaGeneratorStar'),eps), ...
    m('omegaMidStar')/max(m('omegaNearStar'),eps), ...
    m('omegaFarStar')/max(m('omegaMidStar'),eps), ...
    m('gammaAbsGeneratorStar'),m('gammaAbsNearStar'),m('gammaAbsMidStar'),m('gammaAbsFarStar'), ...
    rmsf('antisymmetricOmegaStar'),rmsf('probeUy2DStar'),rmsf('probeUy4DStar'), ...
    m('wakeDeficit2D'),m('wakeDeficit4D'),m('wakeDeficit8D'), ...
    m('populationP05WakeOverReference'),m('populationBelow5FractionWake'), ...
    m('populationBelowHalfReferenceFractionWake'),m('omegaLowKFractionWake'), ...
    shed.frequency,shed.Strouhal,string(shed.status),shed.spectralPeakFraction, ...
    shed.probeFrequency2D,shed.probeFrequency4D,shed.antisymFrequency, ...
    shed.probe2D4DCorrelation,shed.probeLag,shed.convectionVelocity,shed.cyclesObserved, ...
    recirc,double(opt.FirstPassStartDiameters),double(opt.WrapLimitDomainTransits), ...
    'VariableNames',{ ...
    'caseLabel','parentRun','runDir','mode','paramsFile','nFrames','nFirstPassFrames','summaryWindow', ...
    'Lx','Ly','NxNative','NyNative','analysisNx','analysisNy','cylinderCx','cylinderCy','cylinderR','cylinderD','gamma','kBT','rotationAngle', ...
    'periodicX','periodicY','nu','nuSource','UinfMeanFirstPass','UinfMinFirstPass','UglobalMeanFirstPass','ReMeanFirstPass','ReMinFirstPass', ...
    'tauDMeanFirstPass','tauDMax','tauLMax', ...
    'omegaGeneratorStarMeanFirstPass','omegaNearStarMeanFirstPass','omegaMidStarMeanFirstPass','omegaFarStarMeanFirstPass', ...
    'vorticitySurvivalGeneratorToNear','vorticitySurvivalNearToMid','vorticitySurvivalMidToFar', ...
    'gammaAbsGeneratorStarMeanFirstPass','gammaAbsNearStarMeanFirstPass','gammaAbsMidStarMeanFirstPass','gammaAbsFarStarMeanFirstPass', ...
    'antisymmetricOmegaStarRms','probeUy2DStarRms','probeUy4DStarRms', ...
    'wakeDeficit2DMean','wakeDeficit4DMean','wakeDeficit8DMean', ...
    'populationP05WakeOverReference','populationBelow5FractionWake','populationBelowHalfReferenceFractionWake','omegaLowKFractionWake', ...
    'dominantFrequency','Strouhal','StrouhalStatus','spectralPeakFraction', ...
    'probeFrequency2D','probeFrequency4D','antisymmetricOmegaFrequency', ...
    'probe2D4DCorrelation','probe2D4DLag','vortexConvectionVelocity','cyclesObserved', ...
    'recirculationLengthOverD','firstPassStartDiameters','wrapLimitDomainTransits'});
end

% -------------------------------------------------------------------------
function recirc = local_recirculation_length(fields,cx,cy,R,D)
[X,Y]=meshgrid(fields.xc,fields.yc);
yBand=abs(Y-cy)<=0.15*D;
xSearch=fields.xc>cx+R & fields.xc<min(fields.xc(end),cx+5*D);
prof=nan(1,numel(fields.xc));
for ix=find(xSearch)
    vals=fields.UxMean(:,ix); mask=yBand(:,ix);
    prof(ix)=mean(vals(mask),'omitnan');
end
idx=find(xSearch & isfinite(prof) & prof<0);
if isempty(idx)
    recirc=0;
else
    recirc=max(0,(fields.xc(max(idx))-(cx+R))/D);
end
end

% -------------------------------------------------------------------------
function local_make_case_plots(T,F,c,regions,cx,cy,R,opt,outDir)
vis='off'; if logical(opt.ShowFigures), vis='on'; end
prefix=local_safe_name(c.label);
D=2*R;

fig=figure('Visible',vis,'Color','w','Name',['0493x7u ',c.label]);
tl=tiledlayout(2,2,'Padding','compact','TileSpacing','compact'); %#ok<NASGU>
nexttile;
yyaxis left; plot(T.time,T.Uupstream,'-o','LineWidth',1.1,'MarkerSize',3); ylabel('U_\infty');
yyaxis right; plot(T.time,T.ReD,'-s','LineWidth',1.0,'MarkerSize',3); ylabel('Re_D');
xlabel('time'); title('Upstream velocity / Reynolds'); grid on;
nexttile;
plot(T.tauD,[T.omegaGeneratorStar T.omegaNearStar T.omegaMidStar T.omegaFarStar],'-','LineWidth',1.1);
xlabel('\tau_D'); ylabel('\omega_{rms} D/U_\infty'); title('Vorticity generation and survival');
legend({'generator','near','mid','far'},'Location','best'); grid on;
nexttile;
plot(T.time,[T.antisymmetricOmegaStar T.probeUy2DStar T.probeUy4DStar],'-','LineWidth',1.0);
xlabel('time'); ylabel('normalized signal'); title('Organized shedding signals');
legend({'A_\omega^*','u_y(2D)/U_\infty','u_y(4D)/U_\infty'},'Location','best'); grid on;
nexttile;
plot(T.time,[T.populationP05WakeOverReference T.omegaLowKFractionWake],'-','LineWidth',1.0);
xlabel('time'); ylabel('fraction'); title('Support / large-scale content');
legend({'wake N P05/Nref','wake low-k vorticity'},'Location','best'); grid on;
local_export_figure(fig,fullfile(outDir,['vk_vorticity_timeseries_',prefix]));

fig2=figure('Visible',vis,'Color','w','Name',['0493x7u fields ',c.label]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile;
imagesc(F.xc,F.yc,F.omegaMean); axis xy equal tight; colorbar; title('First-pass mean \omega'); xlabel('x'); ylabel('y'); hold on;
local_circle(cx,cy,R); local_region_rectangles(regions);
nexttile;
imagesc(F.xc,F.yc,F.omegaRms); axis xy equal tight; colorbar; title('First-pass RMS \omega'); xlabel('x'); ylabel('y'); hold on;
local_circle(cx,cy,R);
local_export_figure(fig2,fullfile(outDir,['vk_vorticity_fields_',prefix]));
end

function local_make_comparison_plots(results,S,opt,outDir)
if isempty(results), return; end
vis='off'; if logical(opt.ShowFigures), vis='on'; end

fig=figure('Visible',vis,'Color','w','Name','0493x7u VK comparison');
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
nexttile; hold on;
for i=1:numel(results), plot(results{i}.timeseries.time,results{i}.timeseries.Uupstream,'LineWidth',1.1,'DisplayName',results{i}.case.label); end
xlabel('time'); ylabel('U_\infty'); title('Actual upstream velocity'); grid on; legend('Location','best','Interpreter','none');
nexttile; hold on;
for i=1:numel(results), plot(results{i}.timeseries.time,results{i}.timeseries.ReD,'LineWidth',1.1,'DisplayName',results{i}.case.label); end
xlabel('time'); ylabel('Re_D'); title('Mode-specific Reynolds number'); grid on; legend('Location','best','Interpreter','none');
nexttile;
%bar(categorical(S.caseLabel),[S.omegaGeneratorStarMeanFirstPass S.omegaNearStarMeanFirstPass S.omegaMidStarMeanFirstPass S.omegaFarStarMeanFirstPass],'grouped');
ylabel('\omega_{rms}D/U_\infty'); title('Vorticity downstream transport'); legend({'generator','near','mid','far'},'Location','best'); grid on;
nexttile;
%bar(categorical(S.caseLabel),[S.vorticitySurvivalGeneratorToNear S.vorticitySurvivalNearToMid S.omegaLowKFractionWake],'grouped');
ylabel('ratio / fraction'); title('Survival and large-scale organization'); legend({'generator->near','near->mid','low-k'},'Location','best'); grid on;
local_export_figure(fig,fullfile(outDir,'vk_vorticity_comparison_0493x7u'));
end

% -------------------------------------------------------------------------
function local_write_field_csv(F,cx,cy,R,regions,filename)
[X,Y]=meshgrid(F.xc,F.yc);
solid=(X-cx).^2+(Y-cy).^2<=R^2;
gen=local_generator_mask(X,Y,cx,cy,R,0.25*(2*R));
near=local_box_mask(X,Y,regions.nearWake)&~solid;
mid=local_box_mask(X,Y,regions.midWake)&~solid;
far=local_box_mask(X,Y,regions.farWake)&~solid;
T=table(X(:),Y(:),F.UxMean(:),F.UyMean(:),F.omegaMean(:),F.omegaRms(:),F.NMean(:), ...
    solid(:),gen(:),near(:),mid(:),far(:), ...
    'VariableNames',{'x','y','UxMean','UyMean','omegaMean','omegaRms','NMean','solidMask','generatorMask','nearWakeMask','midWakeMask','farWakeMask'});
writetable(T,filename);
end

% -------------------------------------------------------------------------
function regions=local_regions(Lx,Ly,cx,cy,R,opt)
D=2*R;
wallMargin=double(opt.UpstreamWallMarginD)*D;
ymin=max(0,wallMargin); ymax=min(Ly,Ly-wallMargin);
if ymin>=ymax, ymin=0; ymax=Ly; end
ux=sort(double(opt.UpstreamXRangeD(:).'));
near=sort(double(opt.NearWakeXRangeD(:).'));
mid=sort(double(opt.MidWakeXRangeD(:).'));
far=sort(double(opt.FarWakeXRangeD(:).'));
h=double(opt.WakeHalfHeightD)*D;
wy0=max(0,cy-h); wy1=min(Ly,cy+h);
regions=struct();
regions.upstream=[max(0,cx+ux(1)*D), min(Lx,cx+ux(2)*D), ymin,ymax];
regions.nearWake=[max(0,cx+near(1)*D), min(Lx,cx+near(2)*D), wy0,wy1];
regions.midWake=[max(0,cx+mid(1)*D), min(Lx,cx+mid(2)*D), wy0,wy1];
regions.farWake=[max(0,cx+far(1)*D), min(Lx,cx+far(2)*D), wy0,wy1];
regions.sheddingWake=[regions.nearWake(1),regions.midWake(2),wy0,wy1];
regions.object=[cx-R,cx+R,cy-R,cy+R];
end

function T=local_region_table(c,r,D)
names={"upstream";"generator_annulus";"nearWake";"midWake";"farWake";"sheddingWake"};
xmin=[r.upstream(1);NaN;r.nearWake(1);r.midWake(1);r.farWake(1);r.sheddingWake(1)];
xmax=[r.upstream(2);NaN;r.nearWake(2);r.midWake(2);r.farWake(2);r.sheddingWake(2)];
ymin=[r.upstream(3);NaN;r.nearWake(3);r.midWake(3);r.farWake(3);r.sheddingWake(3)];
ymax=[r.upstream(4);NaN;r.nearWake(4);r.midWake(4);r.farWake(4);r.sheddingWake(4)];
notes={"direct particle mass-weighted Uinf";sprintf('R < r < R+%.6g',0.25*D);"vorticity transport";"vorticity transport";"vorticity transport";"antisymmetric shedding / low-k"};
T=table(repmat(string(c.label),numel(names),1),repmat(string(c.mode),numel(names),1),names,xmin,xmax,ymin,ymax,notes, ...
    'VariableNames',{'caseLabel','mode','region','xmin','xmax','ymin','ymax','notes'});
end

% -------------------------------------------------------------------------
function tf=local_axis_periodic(params,axisName)
tf=false;
if strcmpi(axisName,'x')
    if isfield(params,'bcX'), tf=strcmpi(char(string(params.bcX)),'periodic'); return; end
    if isfield(params,'bcLeft') && isfield(params,'bcRight')
        tf=strcmpi(char(string(params.bcLeft)),'periodic') && strcmpi(char(string(params.bcRight)),'periodic');
    end
else
    if isfield(params,'bcY'), tf=strcmpi(char(string(params.bcY)),'periodic'); return; end
    if isfield(params,'bcBottom') && isfield(params,'bcTop')
        tf=strcmpi(char(string(params.bcBottom)),'periodic') && strcmpi(char(string(params.bcTop)),'periodic');
    end
end
end

function [Lx,Ly,Nx,Ny,dt,gamma,kBT,angle]=local_basic_params(params)
Lx=local_param_num(params,{'Lx'},NaN); Ly=local_param_num(params,{'Ly'},NaN);
Nx=round(local_param_num(params,{'Nx','NX'},NaN)); Ny=round(local_param_num(params,{'Ny','NY'},NaN));
dt=local_param_num(params,{'dt','DT'},NaN);
gamma=local_param_num(params,{'gamma','Gamma','GAMMA','wallVpGamma','resamplingTargetCellMass'},NaN);
kBT=local_param_num(params,{'kBT','KBT'},NaN);
angle=local_param_num(params,{'rotationAngle','alpha','rotationAngleRad'},NaN);
end

function [cx,cy,R]=local_cylinder(params)
cx=local_param_num(params,{'darcyCircleCx','immersedSolidCx','immersedCircleCx'},NaN);
cy=local_param_num(params,{'darcyCircleCy','immersedSolidCy','immersedCircleCy'},NaN);
R=local_param_num(params,{'darcyCircleR','immersedSolidR','immersedCircleR'},NaN);
if isfinite(cx) && isfinite(cy) && isfinite(R) && R>0, return; end

% run_ok_vk uses a precomputed chi file and does not duplicate circle geometry
% as darcyCircleCx/Cy/R parameters. Recover the traceable generator geometry
% from filenames such as
%   ...circle_xc0.2_yc0.205_r0.04_750x200.f32
% and the older p-decimal convention
%   ...circle_xc0p2_yc0p205_rc0p04_1200x640_f32.f32
if isfield(params,'darcyChiFile')
    chi=char(string(params.darcyChiFile));
    tok=regexp(chi,'circle_xc([^_/\\]+)_yc([^_/\\]+)_(?:rc|r)([^_/\\]+)_','tokens','once');
    if ~isempty(tok)
        tx=local_filename_number(tok{1}); ty=local_filename_number(tok{2}); tr=local_filename_number(tok{3});
        if isfinite(tx)&&isfinite(ty)&&isfinite(tr)&&tr>0, cx=tx; cy=ty; R=tr; return; end
    end
end
end

function v=local_filename_number(s)
s=char(s);
v=str2double(s);
if isfinite(v), return; end
% Historical filenames encode decimal points with p. A leading m is accepted
% as a minus sign for completeness.
s=strrep(s,'p','.');
if startsWith(s,'m'), s=['-',s(2:end)]; end
v=str2double(s);
end

function [nu,source]=local_resolve_viscosity(mode,params,Lx,Ly,Nx,Ny,dt,gamma,kBT,angle,opt)
key=local_mode_key(mode);
nu=NaN; source="unavailable";
if isfield(opt.ModeViscosities,key)
    v=double(opt.ModeViscosities.(key));
    if isfinite(v)&&v>0, nu=v; source="user_mode_override"; return; end
end
if ~logical(opt.AutoUseX7TViscosities), return; end
ax=Lx/Nx; ay=Ly/Ny;
match = abs(ax-0.002)<=2e-6 && abs(ay-0.002)<=2e-6 && ...
    isfinite(gamma)&&abs(gamma-6)<=1e-9 && isfinite(dt)&&abs(dt-5e-4)<=1e-9 && ...
    isfinite(kBT)&&abs(kBT-5)<=1e-8 && isfinite(angle)&&abs(angle-1.3962634015954636)<=2e-6;
if ~match, return; end
switch key
    case 'src', nu=0.00118720273;
    case 'src_q6', nu=0.000759568145;
    case 'src_q6_g_f', nu=0.00124451358;
end
if isfinite(nu), source="0493x7t_transverse_shear_a002_alpha80"; end
end

function key=local_mode_key(mode)
s=lower(char(mode));
s=strrep(s,'-','_'); s=strrep(s,'+','_');
if contains(s,'q6_g_f') || contains(s,'q6gf'), key='src_q6_g_f';
elseif contains(s,'q6'), key='src_q6';
else, key='src'; end
end

% -------------------------------------------------------------------------
function cases=local_discover_cases(patterns)
cases=struct('label',{},'parentRun',{},'runDir',{},'outputDir',{},'paramsFile',{},'mode',{});
seen={};
for ip=1:numel(patterns)
    pat=char(patterns{ip});
    hasWildcard = contains(pat,'*') || contains(pat,'?');
    if ~hasWildcard && isfolder(pat)
        entries = struct('name',local_basename(pat),'folder',fileparts(pat),'date','','bytes',0,'isdir',true,'datenum',NaN);
    else
        entries=dir(pat);
    end
    for ie=1:numel(entries)
        if ~entries(ie).isdir || any(strcmp(entries(ie).name,{'.','..'})), continue; end
        root=fullfile(entries(ie).folder,entries(ie).name);
        [cases,seen]=local_try_add_root(cases,seen,root,root);
        modeNames={'src','src-q6','src-q6-g-f'};
        for im=1:numel(modeNames)
            sub=fullfile(root,modeNames{im});
            if isfolder(sub), [cases,seen]=local_try_add_root(cases,seen,sub,root); end
        end
    end
end
if ~isempty(cases)
    labels={cases.label}; [~,ord]=sort(labels); cases=cases(ord);
end
end

function [cases,seen]=local_try_add_root(cases,seen,runDir,parentRun)
outputDir='';
if isfolder(fullfile(runDir,'output')) && ~isempty(dir(fullfile(runDir,'output','state_step_*.smpcd')))
    outputDir=fullfile(runDir,'output');
elseif isfolder(runDir) && ~isempty(dir(fullfile(runDir,'state_step_*.smpcd')))
    outputDir=runDir; runDir=fileparts(runDir);
end
if isempty(outputDir), return; end
paramsFile=local_resolve_params(runDir,outputDir);
if isempty(paramsFile), return; end
try
    params=parse_smpcd_kv(paramsFile); [cx,cy,R]=local_cylinder(params); %#ok<ASGLU>
catch
    return;
end
if ~(isfinite(cx)&&isfinite(cy)&&isfinite(R)&&R>0), return; end
canon=strrep(char(runDir),'\\','/');
if any(strcmp(seen,canon)), return; end
seen{end+1}=canon; %#ok<AGROW>
base=local_basename(runDir);
if any(strcmp(base,{'src','src-q6','src-q6-g-f'})), mode=base; else, mode=local_infer_mode(params,base); end
parentBase=local_basename(parentRun);
if strcmp(parentBase,base), label=base; else, label=[parentBase,'/',mode]; end
c=struct('label',label,'parentRun',parentRun,'runDir',runDir,'outputDir',outputDir,'paramsFile',paramsFile,'mode',mode);
cases(end+1)=c; %#ok<AGROW>
end

function mode=local_infer_mode(params,fallback)
mode=fallback;
if isfield(params,'speciesQ6Mode') && contains(lower(char(string(params.speciesQ6Mode))),'free_surface')
    mode='src-q6-g-f'; return;
end
pe=local_param_bool(params,{'projectionEnable'},false);
if pe, mode='src-q6';
elseif isfield(params,'method') && strcmpi(char(string(params.method)),'classic'), mode='src';
end
end

function paramsFile=local_resolve_params(runDir,outputDir)
cands=[dir(fullfile(runDir,'params','*.kv'));dir(fullfile(runDir,'params_used.kv'));dir(fullfile(outputDir,'params_used.kv'))];
if isempty(cands), paramsFile=''; return; end
% Prefer a non-empty .kv in params/, then params_used.kv.
[~,ord]=sort([cands.datenum],'descend'); cands=cands(ord);
paramsFile=fullfile(cands(1).folder,cands(1).name);
end

function frames=local_list_frames(outputDir,dt,stride,maxDumps)
files=dir(fullfile(outputDir,'state_step_*.smpcd'));
if isempty(files), frames=table(); return; end
step=nan(numel(files),1); fullPath=strings(numel(files),1); name=strings(numel(files),1);
for k=1:numel(files)
    name(k)=string(files(k).name); fullPath(k)=string(fullfile(files(k).folder,files(k).name));
    tok=regexp(files(k).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(tok), step(k)=str2double(tok{1}); end
end
[step,ord]=sort(step); name=name(ord); fullPath=fullPath(ord);
time=step*dt;
frames=table(name,fullPath,step,time,'VariableNames',{'file','fullPath','step','time'});
stride=max(1,round(stride)); frames=frames(1:stride:end,:);
if isfinite(maxDumps), frames=frames(1:min(height(frames),round(maxDumps)),:); end
end

% -------------------------------------------------------------------------
function omega=local_vorticity(Ux,Uy,dx,dy,periodicX,periodicY)
Ux=local_fill_empty_velocity(Ux); Uy=local_fill_empty_velocity(Uy);
if periodicX
    dUy_dx=(circshift(Uy,[0,-1])-circshift(Uy,[0,1]))/(2*dx);
else
    dUy_dx=local_derivative_x(Uy,dx);
end
if periodicY
    dUx_dy=(circshift(Ux,[-1,0])-circshift(Ux,[1,0]))/(2*dy);
else
    dUx_dy=local_derivative_y(Ux,dy);
end
omega=dUy_dx-dUx_dy;
end

function A=local_fill_empty_velocity(A)
% Analysis bins are deliberately coarse (D/20 by default), so empty cells are
% rare. Fill any residual holes by nearest finite row/column neighbors rather
% than inserting zero, which would create artificial curl spikes.
if all(isfinite(A(:))), return; end
for pass=1:4
    bad=~isfinite(A); if ~any(bad(:)), break; end
    vals=zeros(size(A)); cnt=zeros(size(A));
    shifts={[0 1],[0 -1],[1 0],[-1 0]};
    for j=1:numel(shifts)
        B=circshift(A,shifts{j}); ok=isfinite(B); vals(ok)=vals(ok)+B(ok); cnt(ok)=cnt(ok)+1; end
    fill=bad & cnt>0; A(fill)=vals(fill)./cnt(fill);
end
A(~isfinite(A))=0;
end

function d=local_derivative_x(A,dx)
d=zeros(size(A)); d(:,2:end-1)=(A(:,3:end)-A(:,1:end-2))/(2*dx);
d(:,1)=(A(:,2)-A(:,1))/dx; d(:,end)=(A(:,end)-A(:,end-1))/dx;
end
function d=local_derivative_y(A,dy)
d=zeros(size(A)); d(2:end-1,:)=(A(3:end,:)-A(1:end-2,:))/(2*dy);
d(1,:)=(A(2,:)-A(1,:))/dy; d(end,:)=(A(end,:)-A(end-1,:))/dy;
end

% -------------------------------------------------------------------------
function [Ux,Uy,M,N]=local_particle_region_velocity(st,box,fluidRole)
role=ones(numel(st.x),1,'uint8'); if isfield(st,'role'), role=uint8(st.role(:)); end
keep=role==uint8(fluidRole) & double(st.x(:))>=box(1) & double(st.x(:))<=box(2) & double(st.y(:))>=box(3) & double(st.y(:))<=box(4);
m=double(st.mass(keep)); M=sum(m); N=nnz(keep);
if M>0
    Ux=sum(m.*double(st.vx(keep)))/M; Uy=sum(m.*double(st.vy(keep)))/M;
else
    Ux=NaN; Uy=NaN;
end
end

function [Ux,Uy,M]=local_global_velocity(st,fluidRole)
role=ones(numel(st.x),1,'uint8'); if isfield(st,'role'), role=uint8(st.role(:)); end
keep=role==uint8(fluidRole); m=double(st.mass(keep)); M=sum(m);
if M>0, Ux=sum(m.*double(st.vx(keep)))/M; Uy=sum(m.*double(st.vy(keep)))/M; else, Ux=NaN; Uy=NaN; end
end

function [rmsw,gp,gn,ga]=local_vorticity_stats(omega,mask,dA)
v=omega(mask); v=v(isfinite(v));
if isempty(v), rmsw=NaN; gp=NaN; gn=NaN; ga=NaN; return; end
rmsw=sqrt(mean(v.^2)); gp=sum(v(v>0))*dA; gn=sum(v(v<0))*dA; ga=sum(abs(v))*dA;
end

function p=local_probe_velocity(fld,x0,y0,hx,hy)
[X,Y]=meshgrid(fld.xc,fld.yc); mask=abs(X-x0)<=hx & abs(Y-y0)<=hy;
p=struct('Ux',mean(fld.Ux(mask),'omitnan'),'Uy',mean(fld.Uy(mask),'omitnan'));
end

function d=local_wake_deficit(fld,x0,yc,Uinf,hx,hy,D)
if ~(isfinite(Uinf)&&abs(Uinf)>eps), d=NaN; return; end
[X,Y]=meshgrid(fld.xc,fld.yc); band=abs(X-x0)<=hx & abs(Y-yc)<=hy;
rows=find(any(band,2)); if isempty(rows), d=NaN; return; end
prof=nan(numel(rows),1);
for j=1:numel(rows)
    vals=fld.Ux(rows(j),band(rows(j),:)); prof(j)=mean(vals,'omitnan');
end
integrand=max(0,1-prof/Uinf); d=sum(integrand,'omitnan')*fld.dy/D;
end

function mask=local_generator_mask(X,Y,cx,cy,R,thickness)
r=sqrt((X-cx).^2+(Y-cy).^2); mask=r>R & r<=R+thickness;
end
function mask=local_box_mask(X,Y,box)
mask=X>=box(1)&X<=box(2)&Y>=box(3)&Y<=box(4);
end

function f=local_lowk_fraction(A,mask,kmax)
B=A; B(~isfinite(B))=0; B(~mask)=0; F=fft2(B); [ny,nx]=size(B);
[kx,ky]=meshgrid(0:nx-1,0:ny-1); kx=min(kx,nx-kx); ky=min(ky,ny-ky);
low=(kx.^2+ky.^2)<=kmax^2; E=abs(F).^2; Et=sum(E(:));
if Et<=0, f=NaN; else, f=sum(E(low),'all')/Et; end
end

% -------------------------------------------------------------------------
function tau=local_cumtrapz_positive(t,u)
tau=zeros(size(t));
for k=2:numel(t)
    dt=t(k)-t(k-1); ua=max(0,u(k-1)); ub=max(0,u(k));
    if ~(isfinite(dt)&&dt>=0&&isfinite(ua)&&isfinite(ub)), tau(k)=tau(k-1); else, tau(k)=tau(k-1)+0.5*(ua+ub)*dt; end
end
end

function s=local_window_label(tauD,tauL,opt)
if tauD<double(opt.FirstPassStartDiameters), s="startup";
elseif tauL<double(opt.WrapLimitDomainTransits), s="first_pass";
else, s="wrap_around"; end
end

% -------------------------------------------------------------------------

function v=local_table_mean(T,name,idx)
x=T.(name); v=mean(x(idx),'omitnan');
end
function v=local_table_min(T,name,idx)
x=T.(name); v=min(x(idx),[],'omitnan');
end
function v=local_table_rms(T,name,idx)
x=T.(name); v=local_rms(x(idx));
end

function v=local_param_num(params,keys,defaultValue)
v=defaultValue;
for i=1:numel(keys)
    k=matlab.lang.makeValidName(keys{i});
    if isfield(params,k)
        x=params.(k); if isnumeric(x)||islogical(x), q=double(x); else, q=str2double(string(x)); end
        if isfinite(q), v=q; return; end
    end
end
end
function v=local_param_bool(params,keys,defaultValue)
v=defaultValue;
for i=1:numel(keys)
    k=matlab.lang.makeValidName(keys{i});
    if isfield(params,k)
        x=params.(k); if islogical(x), v=x; return; end
        if isnumeric(x), v=(x~=0); return; end
        s=lower(strtrim(char(string(x)))); v=any(strcmp(s,{'1','true','yes','on'})); return;
    end
end
end

function c=local_cellstr(x)
if ischar(x), c={x}; elseif isstring(x), c=cellstr(x(:)); else, c=cellfun(@char,x,'UniformOutput',false); end
end
function b=local_basename(path)
[~,b,ext]=fileparts(path); b=[b ext];
end
function s=local_safe_name(x)
s=regexprep(char(x),'[^A-Za-z0-9_-]+','_'); if isempty(s), s='case'; end
end
function A=local_nan_to_zero(A), A(~isfinite(A))=0; end
function r=local_rms(x), x=x(isfinite(x)); if isempty(x),r=NaN;else,r=sqrt(mean(x.^2));end, end
function x=local_pick(values,coords,target)
[dist,idx]=min(abs(coords-target)); if isempty(idx)||dist>0.25, x=NaN; else, x=values(idx); end
end
function q=local_percentile(x,pct)
x=sort(x(isfinite(x))); if isempty(x),q=NaN;return;end
r=1+(pct/100)*(numel(x)-1); lo=floor(r); hi=ceil(r); if lo==hi,q=x(lo);else,q=x(lo)+(r-lo)*(x(hi)-x(lo));end
end
function s=local_num_string(x)
if isfinite(x), s=sprintf('%.6g',x); else, s='NA'; end
end

function local_circle(cx,cy,R)
th=linspace(0,2*pi,200); plot(cx+R*cos(th),cy+R*sin(th),'k-','LineWidth',1.0);
end
function local_region_rectangles(r)
boxes={r.upstream,r.nearWake,r.midWake,r.farWake};
for i=1:numel(boxes), b=boxes{i}; rectangle('Position',[b(1),b(3),b(2)-b(1),b(4)-b(3)],'LineStyle','--'); end
end
function local_export_figure(fig,base)
try, exportgraphics(fig,[base,'.png'],'Resolution',160); catch, saveas(fig,[base,'.png']); end
try, exportgraphics(fig,[base,'.pdf'],'ContentType','vector'); catch, try, saveas(fig,[base,'.pdf']); catch, end, end
if strcmpi(get(fig,'Visible'),'off'), close(fig); end
end

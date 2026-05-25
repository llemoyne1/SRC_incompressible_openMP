function R = analyze_poiseuille_hard_inlet_free_outlet_0077(varargin)
%ANALYZE_POISEUILLE_HARD_INLET_FREE_OUTLET_0077 Analyze 0077 hard-inlet/free-outlet channel runs.
%
% This analysis combines runtime diagnostics and dumped state fields.  The
% runtime boundary counters are sampled at summary rows; the state flux proxies
% are computed from binned particle fields in inlet/outlet bands and are better
% suited for late-time throughput comparison when summaryEvery > 1.

p = inputParser;
p.FunctionName = 'analyze_poiseuille_hard_inlet_free_outlet_0077';
addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
addParameter(p, 'runRoot', 'runs/poiseuille_hard_inlet_free_outlet_validated_q9_0077', @(s) ischar(s) || isstring(s));
addParameter(p, 'caseGlob', 'poiseuille_*', @(s) ischar(s) || isstring(s));
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

outDir = fullfile(runRoot, 'analysis_0077');
if ~exist(outDir, 'dir'); mkdir(outDir); end

runtimeAll = table();
stateAll = table();
profileAll = table();
summaryRows = table();

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
    T = readtable(runtimePath);
    runtimeRows = local_runtime_rows(caseLabel, T, params);
    writetable(runtimeRows, fullfile(outDir, sprintf('runtime_timeseries_%s.csv', caseLabel)));
    runtimeAll = [runtimeAll; runtimeRows]; %#ok<AGROW>

    frames = list_smpcd_dumps(caseDir, 'summaryFile', runtimePath);
    stateRows = table();
    profileRows = table();
    if ~isempty(frames)
        idxList = 1:round(opts.frameStride):height(frames);
        if idxList(end) ~= height(frames)
            idxList = [idxList height(frames)]; %#ok<AGROW>
        end
        geom = local_geometry(params);
        for kk = 1:numel(idxList)
            idx = idxList(kk);
            state = read_smpcd_state(frames.fullPath{idx});
            fields = bin_smpcd_state(state, 'Lx', geom.Lx, 'Ly', geom.Ly, 'Nx', geom.Nx, 'Ny', geom.Ny, ...
                'periodicX', false, 'periodicY', false);
            stateRows = [stateRows; local_state_budget_row(caseLabel, idx, frames.time(idx), fields, geom, params)]; %#ok<AGROW>
            profileRows = [profileRows; local_profile_row(caseLabel, idx, frames.time(idx), fields, geom, params)]; %#ok<AGROW>
        end
        writetable(stateRows, fullfile(outDir, sprintf('state_budget_timeseries_%s.csv', caseLabel)));
        writetable(profileRows, fullfile(outDir, sprintf('profile_timeseries_%s.csv', caseLabel)));
        stateAll = [stateAll; stateRows]; %#ok<AGROW>
        profileAll = [profileAll; profileRows]; %#ok<AGROW>
    else
        warning('No .smpcd dumps for %s; state/profile diagnostics skipped.', caseLabel);
    end

    summaryRows = [summaryRows; local_summary_row(caseLabel, runtimeRows, stateRows, profileRows, params, opts.lateFraction)]; %#ok<AGROW>
end

if ~isempty(runtimeAll)
    writetable(runtimeAll, fullfile(outDir, 'runtime_timeseries_all_cases.csv'));
end
if ~isempty(stateAll)
    writetable(stateAll, fullfile(outDir, 'state_budget_timeseries_all_cases.csv'));
end
if ~isempty(profileAll)
    writetable(profileAll, fullfile(outDir, 'profile_timeseries_all_cases.csv'));
end
if ~isempty(summaryRows)
    writetable(summaryRows, fullfile(outDir, 'poiseuille_hard_inlet_free_outlet_summary_0077.csv'));
    disp(summaryRows);
end

if opts.makePlots
    local_make_plots(runtimeAll, stateAll, profileAll, outDir);
end

R = struct();
R.runRoot = runRoot;
R.outputDir = outDir;
R.runtimeTimeseries = runtimeAll;
R.stateTimeseries = stateAll;
R.profileTimeseries = profileAll;
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
    local_col(T,'kBTEstimate'), local_col(T,'maxParticleSpeed'), ...
    inserted, reservoirDeleted, backflowDeleted, outletDeleted, source, net, ratio, ...
    local_col(T,'q6Applied'), local_col(T,'q6Converged'), local_col(T,'q6ResidualRel'), local_col(T,'q6DivAfterProjectedFluxRms'), local_col(T,'q6OpenBoundaryFluxBalance'), ...
    local_col(T,'q9Applied'), local_col(T,'q9Converged'), local_col(T,'q9ResidualRel'), local_col(T,'q9DensityStdRatioEstimate'), local_col(T,'q9OpenBoundaryMassFluxBalance'), ...
    local_col(T,'q9CorrectionVelocityRms'), local_col(T,'q9CorrectionVelocityMaxAbs'), local_col(T,'q9CorrectionVelocityRawRms'), local_col(T,'q9CorrectionVelocityRawMaxAbs'), ...
    local_col(T,'q9LowMassSuppressedCells'), local_col(T,'q9LowMassRampedCells'), local_col(T,'q9MassFloorAppliedCells'), local_col(T,'q9VelocityLimitedCells'), ...
    local_col(T,'virialKickApplied'), local_col(T,'virialRhoDefectRelRms'), local_col(T,'PtotMean'), local_col(T,'virialDuAppliedRms'), local_col(T,'virialDuAppliedMaxAbs'), ...
    'VariableNames', {'caseLabel','step','time','dt','Np','totalMass','meanVx','meanVy', ...
    'meanN','stdN','minN','maxN','kBTEstimate','maxParticleSpeed', ...
    'inletParticlesInserted','inletReservoirDeleted','inletBackflowDeleted','outletParticlesDeleted', ...
    'inletEffectiveSource','sampledBoundaryNet','sampledOutletOverSource', ...
    'q6Applied','q6Converged','q6ResidualRel','q6DivAfterProjectedFluxRms','q6OpenBoundaryFluxBalance', ...
    'q9Applied','q9Converged','q9ResidualRel','q9DensityStdRatioEstimate','q9OpenBoundaryMassFluxBalance', ...
    'q9CorrectionVelocityRms','q9CorrectionVelocityMaxAbs','q9CorrectionVelocityRawRms','q9CorrectionVelocityRawMaxAbs', ...
    'q9LowMassSuppressedCells','q9LowMassRampedCells','q9MassFloorAppliedCells','q9VelocityLimitedCells', ...
    'virialKickApplied','virialRhoDefectRelRms','PtotMean','virialDuAppliedRms','virialDuAppliedMaxAbs'});
end

function row = local_state_budget_row(caseLabel, frameIndex, t, fields, geom, params)
N = local_field_or_zeros(fields, 'N', geom.Ny, geom.Nx);
Ux = local_field_or_zeros(fields, 'Ux', geom.Ny, geom.Nx);
Uy = local_field_or_zeros(fields, 'Uy', geom.Ny, geom.Nx);
fluid = true(geom.Ny, geom.Nx);

inletCells = max(1, round(local_get_num(params, 'inletReservoirCells', 3)));
outletCells = inletCells;
inletBand = false(geom.Ny, geom.Nx); inletBand(:, 1:min(inletCells, geom.Nx)) = true;
outletBand = false(geom.Ny, geom.Nx); outletBand(:, max(1, geom.Nx-outletCells+1):geom.Nx) = true;
midCol = max(1, min(geom.Nx, round(0.5 * geom.Nx)));

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
midFluxProxy = sum(N(:, midCol).*Ux(:, midCol), 'omitnan');

row = table(string(caseLabel), frameIndex, t, ...
    sum(fluidN,'omitnan'), mean(fluidN,'omitnan'), std(fluidN,0,'omitnan'), min(fluidN), max(fluidN), ...
    sum(N(inletBand),'omitnan'), mean(N(inletBand),'omitnan'), max([N(inletBand); 0]), ...
    sum(N(outletBand),'omitnan'), mean(N(outletBand),'omitnan'), max([N(outletBand); 0]), ...
    sum(N(q9Active),'omitnan'), inletFluxProxy, outletFluxProxy, midFluxProxy, local_scalar_ratio(outletFluxProxy, inletFluxProxy), ...
    mean(Ux(fluid),'omitnan'), mean(Uy(fluid),'omitnan'), sqrt(mean(Uy(fluid).^2,'omitnan')), ...
    'VariableNames', {'caseLabel','frameIndex','time','totalCellMass','meanCellN','stdCellN','minCellN','maxCellN', ...
    'inletBandMass','inletBandMeanN','inletBandMaxN','outletBandMass','outletBandMeanN','outletBandMaxN', ...
    'q9ActiveMass','inletFluxProxy','outletFluxProxy','midFluxProxy','outletOverInletFluxProxy', ...
    'meanUxCell','meanUyCell','uyRmsCell'});
end

function row = local_profile_row(caseLabel, frameIndex, t, fields, geom, params)
N = local_field_or_zeros(fields, 'N', geom.Ny, geom.Nx);
Ux = local_field_or_zeros(fields, 'Ux', geom.Ny, geom.Nx);
openCells = max(0, round(local_get_num(params, 'q9OpenBoundaryExclusionCells', local_get_num(params, 'inletReservoirCells', 3))));
i0 = min(geom.Nx, max(1, openCells + 1));
i1 = max(i0, geom.Nx - openCells);
cols = i0:i1;
profile = mean(Ux(:, cols), 2, 'omitnan');
profileN = mean(N(:, cols), 2, 'omitnan');
y = geom.yc(:);
valid = isfinite(profile);

if nnz(valid) >= 3
    coeff = polyfit(y(valid), profile(valid), 2);
    fitv = polyval(coeff, y(valid));
    ssRes = sum((profile(valid) - fitv).^2);
    ssTot = sum((profile(valid) - mean(profile(valid))).^2);
    r2 = 1 - ssRes / max(ssTot, eps);
    curvature = coeff(1);
else
    r2 = NaN;
    curvature = NaN;
end

nEdge = max(1, round(0.10 * geom.Ny));
wallUx = mean([profile(1:nEdge); profile(end-nEdge+1:end)], 'omitnan');
centerIdx = max(1, min(geom.Ny, round(0.5 * geom.Ny)));
centerUx = profile(centerIdx);
meanUx = mean(profile, 'omitnan');
meanN = mean(profileN, 'omitnan');
stdN = std(profileN, 0, 'omitnan');

row = table(string(caseLabel), frameIndex, t, i0, i1, ...
    meanUx, centerUx, wallUx, centerUx - wallUx, r2, curvature, meanN, stdN, ...
    'VariableNames', {'caseLabel','frameIndex','time','profileColStart','profileColEnd', ...
    'profileMeanUx','profileCenterUx','profileWallUx','profileCenterMinusWallUx','profileQuadraticR2','profileQuadraticCurvature', ...
    'profileMeanN','profileStdN'});
end

function srow = local_summary_row(caseLabel, runtimeRows, stateRows, profileRows, params, lateFraction)
lateRuntime = local_late(runtimeRows, lateFraction);
lateState = local_late(stateRows, lateFraction);
lateProfile = local_late(profileRows, lateFraction);
dt = local_get_num(params, 'dt', NaN);
Lx = local_get_num(params, 'Lx', NaN);
Uin = local_get_num(params, 'inletUxLeft', local_get_num(params, 'targetMeanUx', NaN));
Tadv = Lx / max(abs(Uin), eps);

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

profileR2Late = NaN;
profileCenterMinusWallLate = NaN;
profileMeanUxLate = NaN;
if ~isempty(lateProfile)
    profileR2Late = mean(lateProfile.profileQuadraticR2, 'omitnan');
    profileCenterMinusWallLate = mean(lateProfile.profileCenterMinusWallUx, 'omitnan');
    profileMeanUxLate = mean(lateProfile.profileMeanUx, 'omitnan');
end

sourceLate = mean(lateRuntime.inletEffectiveSource, 'omitnan');
outletLate = mean(lateRuntime.outletParticlesDeleted, 'omitnan');
netLate = mean(lateRuntime.sampledBoundaryNet, 'omitnan');

srow = table(string(caseLabel), height(runtimeRows), timeFinal, timeFinal/Tadv, dt, ...
    NpFirst, NpFinal, NpFinal-NpFirst, NpSlopeAll, NpSlopeLate, NpSlopeLate*dt, ...
    mean(lateRuntime.meanVx,'omitnan'), mean(lateRuntime.kBTEstimate,'omitnan'), max(lateRuntime.kBTEstimate, [], 'omitnan'), ...
    mean(lateRuntime.stdN,'omitnan'), mean(lateRuntime.maxN,'omitnan'), max(runtimeRows.maxN, [], 'omitnan'), ...
    sourceLate, outletLate, netLate, local_scalar_ratio(outletLate, sourceLate), ...
    mean(lateRuntime.q6DivAfterProjectedFluxRms,'omitnan'), mean(lateRuntime.q6OpenBoundaryFluxBalance,'omitnan'), ...
    mean(lateRuntime.q9DensityStdRatioEstimate,'omitnan'), mean(lateRuntime.q9OpenBoundaryMassFluxBalance,'omitnan'), ...
    mean(lateRuntime.q9CorrectionVelocityRms,'omitnan'), max(lateRuntime.q9CorrectionVelocityMaxAbs, [], 'omitnan'), ...
    mean(lateRuntime.q9LowMassSuppressedCells,'omitnan'), mean(lateRuntime.q9LowMassRampedCells,'omitnan'), mean(lateRuntime.q9MassFloorAppliedCells,'omitnan'), mean(lateRuntime.q9VelocityLimitedCells,'omitnan'), ...
    mean(lateRuntime.virialRhoDefectRelRms,'omitnan'), mean(lateRuntime.virialDuAppliedRms,'omitnan'), max(lateRuntime.virialDuAppliedMaxAbs, [], 'omitnan'), ...
    stateFluxRatioLate, stateMassSlopeLate, stateStdNSlopeLate, profileMeanUxLate, profileCenterMinusWallLate, profileR2Late, ...
    'VariableNames', {'caseLabel','nRuntimeRows','timeFinal','advectiveTimesFinal','dt', ...
    'NpFirst','NpFinal','NpDelta','NpSlopeAll_perTime','NpSlopeLate_perTime','NpSlopeLate_perStep', ...
    'meanVxLate','kBTMeanLate','kBTMaxAll','stdNLate','maxNLate','maxNAll', ...
    'inletEffectiveSourceMeanLate','outletDeletedMeanLate','sampledBoundaryNetMeanLate','outletOverSourceMeanLate', ...
    'q6DivAfterMeanLate','q6OpenFluxBalanceMeanLate','q9DensityStdRatioMeanLate','q9OpenMassFluxBalanceMeanLate', ...
    'q9CorrectionVelocityRmsMeanLate','q9CorrectionVelocityMaxAbsLateMax', ...
    'q9LowMassSuppressedCellsMeanLate','q9LowMassRampedCellsMeanLate','q9MassFloorAppliedCellsMeanLate','q9VelocityLimitedCellsMeanLate', ...
    'virialRhoDefectRelRmsMeanLate','virialDuAppliedRmsMeanLate','virialDuAppliedMaxAbsLateMax', ...
    'stateOutletOverInletFluxProxyMeanLate','stateMassSlopeLate','stateStdNSlopeLate', ...
    'profileMeanUxLate','profileCenterMinusWallUxLate','profileQuadraticR2Late'});
end

function local_make_plots(runtimeAll, stateAll, profileAll, outDir)
if ~isempty(runtimeAll)
    local_plot_by_case(runtimeAll, outDir, 'runtime_Np', 'Np');
    local_plot_by_case(runtimeAll, outDir, 'runtime_kBT', 'kBTEstimate');
    local_plot_by_case(runtimeAll, outDir, 'runtime_stdN', 'stdN');
    local_plot_by_case(runtimeAll, outDir, 'runtime_maxN', 'maxN');
    local_plot_by_case(runtimeAll, outDir, 'runtime_q9CorrectionVelocityMaxAbs', 'q9CorrectionVelocityMaxAbs');
    local_plot_by_case(runtimeAll, outDir, 'runtime_sampledOutletOverSource', 'sampledOutletOverSource');
end
if ~isempty(stateAll)
    local_plot_by_case(stateAll, outDir, 'state_totalCellMass', 'totalCellMass');
    local_plot_by_case(stateAll, outDir, 'state_fluxProxyRatio', 'outletOverInletFluxProxy');
    local_plot_by_case(stateAll, outDir, 'state_inletFluxProxy', 'inletFluxProxy');
    local_plot_by_case(stateAll, outDir, 'state_outletFluxProxy', 'outletFluxProxy');
end
if ~isempty(profileAll)
    local_plot_by_case(profileAll, outDir, 'profile_centerMinusWallUx', 'profileCenterMinusWallUx');
    local_plot_by_case(profileAll, outDir, 'profile_quadraticR2', 'profileQuadraticR2');
end
end

function local_plot_by_case(T, outDir, baseName, fieldName)
if isempty(T) || ~ismember(fieldName, T.Properties.VariableNames); return; end
labels = unique(T.caseLabel, 'stable');
fig = figure('Visible','on'); hold on; grid on;
for i = 1:numel(labels)
    idx = T.caseLabel == labels(i);
    plot(T.time(idx), T.(fieldName)(idx), 'DisplayName', char(labels(i)));
end
xlabel('time'); ylabel(fieldName); title(strrep(baseName, '_', '\_'));
legend('Location','best', 'Interpreter','none');
saveas(fig, fullfile(outDir, [baseName '.png']));
%close(fig);
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

function v = local_col(T, name)
if ismember(name, T.Properties.VariableNames)
    v = T.(name);
else
    v = nan(height(T), 1);
end
end

function x = local_get_num(params, name, defaultValue)
if isfield(params, name) && isnumeric(params.(name)) && isscalar(params.(name))
    x = double(params.(name));
else
    x = defaultValue;
end
end

function r = local_safe_ratio(a, b)
r = nan(size(a));
ok = abs(b) > eps;
r(ok) = a(ok) ./ b(ok);
end

function r = local_scalar_ratio(a, b)
if abs(b) <= eps
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

function summary = analyze_backward_step_resampling_0136(runRoot, varargin)
%ANALYZE_BACKWARD_STEP_RESAMPLING_0136 Post-process open-channel backward-step validation.
%
% Usage from repository matlab/ directory:
%   analyze_backward_step_resampling_0136('../runs/backward_step_resampling_0136');

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','backward_step_resampling_0136');
end
runRoot = char(strrep(string(runRoot), '\\', filesep));

p = inputParser;
p.FunctionName = 'analyze_backward_step_resampling_0136';
addParameter(p, 'Lx', 4.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 192, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ny', 48, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'stepXMin', 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'stepXMax', 0.8, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'stepHeight', 0.5, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

cases = {'classic','q6','q6_resampling'};
caseLabels = cases;
analysisDir = fullfile(runRoot, 'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end

rows = struct([]);
for c = 1:numel(cases)
    caseName = cases{c};
    caseDir = fullfile(runRoot, caseName);
    summaryCsv = fullfile(caseDir, 'summary_runtime.csv');
    if ~isfile(summaryCsv)
        warning('[0136] skipping missing summary: %s', summaryCsv);
        continue;
    end
    S = readtable(summaryCsv);
    dumpFiles = local_find_state_files(caseDir);
    nFrames = numel(dumpFiles);
    if nFrames == 0
        warning('[0136] skipping %s: no state_step_*.smpcd files.', caseName);
        continue;
    end

    lastFile = dumpFiles{end};
    state = read_smpcd_state(lastFile);
    B = bin_smpcd_state(state, ...
        'Lx', opt.Lx, 'Ly', opt.Ly, 'Nx', opt.Nx, 'Ny', opt.Ny, ...
        'periodicX', false, 'periodicY', false, ...
        'fluidOnly', true);
    geom = local_geometry(opt.Lx, opt.Ly, opt.Nx, opt.Ny, opt.stepXMin, opt.stepXMax, opt.stepHeight);
    B = local_mask_solid_fields(B, geom);
    D = local_backward_step_diagnostics(B, geom, S);

    rows(c).caseName = string(caseName); %#ok<AGROW>
    rows(c).nFrames = nFrames;
    rows(c).finalMeanUx = D.meanUx;
    rows(c).finalRecircMeanUx = D.recircMeanUx;
    rows(c).finalRecircMinUx = D.recircMinUx;
    rows(c).finalRecircBackflowFraction = D.recircBackflowFraction;
    rows(c).finalShearOmegaRms = D.shearOmegaRms;
    rows(c).finalWakeOmegaRms = D.wakeOmegaRms;
    rows(c).finalSolidLeakMass = D.solidLeakMass;
    rows(c).maxSolidLeakMass = local_colmax(S, 'solidLeakMass', D.solidLeakMass);
    rows(c).finalStdN = local_last(S, 'stdN', std(B.N(:), 0, 'omitnan'));
    rows(c).finalResampMRelRms = local_last(S, 'resampMRelRms', NaN);
    rows(c).maxResampMRelRms = local_colmax(S, 'resampMRelRms', NaN);
    rows(c).finalQ6Div = local_last(S, 'q6DivAfterProjectedFluxRms', NaN);
    rows(c).totalExtracted = local_colsum(S, 'resampExtractionApplyOpsApplied');
    rows(c).totalInserted = local_colsum(S, 'resampInsertionApplyOpsApplied');
    rows(c).totalRemapCells = local_colsum(S, 'resampRemapCells');
    rows(c).totalMassGuardAdjusted = local_colsum(S, 'resampMassGuardParticlesAdjusted');

    writetable(local_profile_table(B, geom), fullfile(analysisDir, sprintf('backstep_profile_%s.csv', caseName)));
    if logical(opt.makePlots)
        local_plot_fields(B, geom, caseName, fullfile(analysisDir, sprintf('backstep_0136_final_fields_%s.png', caseName)));
    end
end

if isempty(rows)
    summary = table();
    warning('[0136] no cases were analyzed.');
    return;
end

summary = struct2table(rows);
writetable(summary, fullfile(analysisDir, 'backward_step_summary_0136.csv'));
disp('=== Backward-step resampling 0136 summary ===');
disp(summary);

if logical(opt.makePlots)
    local_plot_profiles(runRoot, analysisDir, caseLabels, opt);
    local_plot_timeseries(runRoot, analysisDir, caseLabels);
end
end

function files = local_find_state_files(caseDir)
d = dir(fullfile(caseDir, 'state_step_*.smpcd'));
[~, order] = sort({d.name});
d = d(order);
files = arrayfun(@(q) fullfile(q.folder, q.name), d, 'UniformOutput', false);
end

function geom = local_geometry(Lx, Ly, Nx, Ny, stepXMin, stepXMax, stepHeight)
dx = Lx / Nx; dy = Ly / Ny;
[xc, yc] = meshgrid(((0:Nx-1)+0.5)*dx, ((0:Ny-1)+0.5)*dy);
solid = xc >= stepXMin & xc <= stepXMax & yc <= stepHeight;
geom = struct('Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, 'dx', dx, 'dy', dy, ...
    'xc', xc, 'yc', yc, 'solid', solid, 'fluid', ~solid, ...
    'stepXMin', stepXMin, 'stepXMax', stepXMax, 'stepHeight', stepHeight);
end

function B = local_mask_solid_fields(B, geom)
mask = geom.solid;
fields = {'mass','N','Ux','Uy','speed','omega'};
for k = 1:numel(fields)
    f = fields{k};
    if isfield(B, f)
        A = B.(f);
        A(mask) = NaN;
        B.(f) = A;
    end
end
end

function D = local_backward_step_diagnostics(B, geom, S)
recirc = geom.xc > geom.stepXMax & geom.xc < min(geom.stepXMax + 1.5, geom.Lx) & geom.yc < geom.stepHeight;
wake = geom.xc > geom.stepXMax & geom.xc < min(geom.stepXMax + 2.0, geom.Lx) & geom.yc > 0.15 & geom.yc < 0.85;
shear = geom.xc > geom.stepXMax & geom.xc < min(geom.stepXMax + 1.5, geom.Lx) & abs(geom.yc - geom.stepHeight) < 0.12;
uxRecirc = B.Ux(recirc & ~isnan(B.Ux));
D.meanUx = mean(B.Ux(~isnan(B.Ux)), 'omitnan');
D.recircMeanUx = mean(uxRecirc, 'omitnan');
D.recircMinUx = min(uxRecirc, [], 'omitnan');
D.recircBackflowFraction = mean(uxRecirc < 0, 'omitnan');
D.shearOmegaRms = sqrt(mean(B.omega(shear & ~isnan(B.omega)).^2, 'omitnan'));
D.wakeOmegaRms = sqrt(mean(B.omega(wake & ~isnan(B.omega)).^2, 'omitnan'));
if ismember('solidLeakMass', S.Properties.VariableNames)
    D.solidLeakMass = S.solidLeakMass(end);
else
    D.solidLeakMass = sum(B.mass(geom.solid), 'omitnan');
end
end

function T = local_profile_table(B, geom)
T = table();
T.y = geom.yc(:,1);
T.meanUx = mean(B.Ux, 2, 'omitnan');
T.meanMass = mean(B.mass, 2, 'omitnan');
T.meanN = mean(B.N, 2, 'omitnan');
T.omegaRms = sqrt(mean(B.omega.^2, 2, 'omitnan'));
end

function local_plot_fields(B, geom, caseName, outPng)
fig = figure('Name', ['0136 backward step fields ' caseName], 'Visible', 'on');
tiledlayout(3,2, 'Padding', 'compact', 'TileSpacing', 'compact');
local_field_tile(geom, B.speed, 'speed');
local_field_tile(geom, B.Ux, 'Ux');
local_field_tile(geom, B.Uy, 'Uy');
local_field_tile(geom, B.omega, 'vorticity');
local_field_tile(geom, B.mass, 'cell mass');
local_field_tile(geom, B.N, 'cell population');
for ax = findall(fig, 'Type', 'axes').'
    axes(ax); %#ok<LAXES>
    hold on; local_draw_step(geom, 'k-', 1.5); hold off;
end
saveas(fig, outPng);
end

function local_field_tile(geom, A, ttl)
nexttile;
imagesc(geom.xc(1,:), geom.yc(:,1), A);
set(gca, 'YDir', 'normal'); axis equal tight; colorbar;
title(ttl); xlabel('x'); ylabel('y');
end

function local_plot_profiles(runRoot, analysisDir, caseLabels, opt)
fig = figure('Name', '0136 backward step profiles', 'Visible', 'on');
tiledlayout(1,3, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile; hold on; title('streamwise profile'); xlabel('mean Ux'); ylabel('y'); grid on;
for c = 1:numel(caseLabels)
    f = fullfile(analysisDir, sprintf('backstep_profile_%s.csv', caseLabels{c}));
    if isfile(f)
        T = readtable(f); plot(T.meanUx, T.y, 'DisplayName', caseLabels{c});
    end
end
legend('Interpreter', 'none', 'Location', 'best');
nexttile; hold on; title('mass profile'); xlabel('mean cell mass'); ylabel('y'); grid on;
for c = 1:numel(caseLabels)
    f = fullfile(analysisDir, sprintf('backstep_profile_%s.csv', caseLabels{c}));
    if isfile(f)
        T = readtable(f); plot(T.meanMass, T.y, 'DisplayName', caseLabels{c});
    end
end
legend('Interpreter', 'none', 'Location', 'best');
nexttile; hold on; title('omega RMS profile'); xlabel('RMS omega'); ylabel('y'); grid on;
for c = 1:numel(caseLabels)
    f = fullfile(analysisDir, sprintf('backstep_profile_%s.csv', caseLabels{c}));
    if isfile(f)
        T = readtable(f); plot(T.omegaRms, T.y, 'DisplayName', caseLabels{c});
    end
end
legend('Interpreter', 'none', 'Location', 'best');
saveas(fig, fullfile(analysisDir, 'backstep_0136_profiles.png'));
end

function local_plot_timeseries(runRoot, analysisDir, caseLabels)
fig = figure('Name', '0136 backward step timeseries', 'Visible', 'on');
tiledlayout(5,1, 'Padding', 'compact', 'TileSpacing', 'compact');
vars = {'meanUx','q6DivAfterProjectedFluxRms','resampMRelRms','stdN','solidLeakMass'};
ylabels = {'mean Ux','q6 div RMS','resamp MRelRMS','std(N)','solid leak mass'};
for v = 1:numel(vars)
    nexttile; hold on; grid on; ylabel(ylabels{v});
    for c = 1:numel(caseLabels)
        f = fullfile(runRoot, caseLabels{c}, 'summary_runtime.csv');
        if ~isfile(f), continue; end
        S = readtable(f);
        if ~ismember(vars{v}, S.Properties.VariableNames), continue; end
        t = local_time_vector(S);
        plot(t, S.(vars{v}), 'DisplayName', caseLabels{c});
    end
    if v == numel(vars), xlabel('time'); end
    legend('Interpreter', 'none', 'Location', 'best');
end
saveas(fig, fullfile(analysisDir, 'backstep_0136_timeseries.png'));
end

function t = local_time_vector(S)
if ismember('time', S.Properties.VariableNames)
    t = S.time;
elseif ismember('t', S.Properties.VariableNames)
    t = S.t;
elseif ismember('step', S.Properties.VariableNames)
    t = S.step;
else
    t = (0:height(S)-1).';
end
end

function v = local_last(S, name, defaultValue)
if ismember(name, S.Properties.VariableNames) && ~isempty(S.(name))
    v = S.(name)(end);
else
    v = defaultValue;
end
end

function v = local_colmax(S, name, defaultValue)
if ismember(name, S.Properties.VariableNames) && ~isempty(S.(name))
    v = max(S.(name), [], 'omitnan');
else
    v = defaultValue;
end
end

function v = local_colsum(S, name)
if ismember(name, S.Properties.VariableNames) && ~isempty(S.(name))
    v = sum(S.(name), 'omitnan');
else
    v = 0;
end
end

function local_draw_step(geom, style, lw)
plot([geom.stepXMin geom.stepXMax geom.stepXMax geom.stepXMin geom.stepXMin], ...
     [0 0 geom.stepHeight geom.stepHeight 0], style, 'LineWidth', lw);
end

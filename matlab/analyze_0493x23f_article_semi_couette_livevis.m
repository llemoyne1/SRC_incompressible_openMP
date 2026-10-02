function out = analyze_0493x23f_article_semi_couette_livevis(runRoot, primaryStartStep, primaryEndStep)
%ANALYZE_0493X23F_ARTICLE_SEMI_COUETTE_LIVEVIS
%
% Analyse conservative du benchmark article 0493x23f :
%
%       S | L | G | S
%
% y = 0       : paroi solide immobile, ux = 0
% 0<y<hL      : liquide
% y = hL      : interface liquide/gaz
% hL<y<Ly     : gaz
% y = Ly      : paroi solide mobile, ux = +Uw
%
% Aucun repliement, aucune hypothese de symetrie.
%
% Observable principale :
%
%       R_tau = (mu_L a_L)/(mu_G a_G)
%             = (a_L/a_G)/(mu_G/mu_L)
%
% avec
%
%       mu_G/mu_L = (rho_G nu_G)/(rho_L nu_L)
%
% et les viscosites cinematiques independamment calibrees :
%
%       nu_L = 6.15880e-4
%       nu_G = 7.29393e-4
%
% Le profil continuum bicouche no-slip utilise le rapport de viscosites
% MESURE sur la fenetre analysee :
%
%       r = mu_G/mu_L
%       a_G^th = Uw/(hG + r hL)
%       a_L^th = r a_G^th
%       U_Gamma^th = a_L^th hL
%
% Metrologie :
%   - lecture rho, ux, uy LiveVis ;
%   - moyenne conservative : ux = sum(rho*ux)/sum(rho) ;
%   - moyenne horizontale en x puis temporelle ;
%   - fits lineaires fixes en excluant 4 cellules pres des parois/interface.
%
% Usage :
%
%   out = analyze_0493x23f_article_semi_couette_livevis;
%
% Fenetre principale explicite :
%
%   out = analyze_0493x23f_article_semi_couette_livevis( ...
%       '../runs/0493x23f_article_semi_couette_64x64_Uw0075_seed593171', ...
%       4000, 8000);
%
% Si primaryStartStep / primaryEndStep sont omis :
%   - end = fin nominale deduite de la derniere frame ;
%   - start = max(0,end-4000).
%
% Sorties :
%
% <runRoot>/analysis_0493x23f_semi_couette/
%   semi_couette_summary_0493x23f.txt
%   semi_couette_profile_0493x23f.png
%   semi_couette_rolling_0493x23f.png
%   semi_couette_terminal_0493x23f.png
%   semi_couette_rolling_0493x23f.csv
%   semi_couette_terminal_0493x23f.csv
%   semi_couette_0493x23f.mat

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs', ...
        '0493x23f_article_semi_couette_64x64_Uw0075_seed593171');
end
runRoot = char(runRoot);

cfg = struct();

% References independently calibrated at the same local transport point.
cfg.nuL = 6.15880e-4;
cfg.nuG = 7.29393e-4;

% Defaults, overwritten from params/environment when available.
cfg.Lx = 0.25;
cfg.Ly = 0.25;
cfg.nx = 64;   % recorder/live grid Nx (updated from manifest)
cfg.ny = 64;   % recorder/live grid Ny (updated from manifest)
cfg.solverNx = 64;
cfg.solverNy = 64;
cfg.liquidCells = 32;
cfg.UwBottom = 0.0;
cfg.UwTop = 0.075;
cfg.sigma = NaN;

cfg.excludeWallCells = 4;
cfg.excludeInterfaceCells = 4;

%% ========================================================================
% Locate recording + metadata
% =========================================================================
[recDir, manifestFile] = local_find_recording_dir(runRoot);
manifestText = fileread(manifestFile);

% IMPORTANT: recorder/live grid and solver grid are distinct quantities.
% The .f32 payload size follows liveGridNx/liveGridNy. Geometry and the
% LIQUID_CELLS count refer to the solver grid.
cfg.nx = round(local_kv_num(manifestText, {'liveGridNx','recordGridNx'}, cfg.nx));
cfg.ny = round(local_kv_num(manifestText, {'liveGridNy','recordGridNy'}, cfg.ny));
cfg.solverNx = round(local_kv_num(manifestText, {'solverNx','Nx'}, cfg.solverNx));
cfg.solverNy = round(local_kv_num(manifestText, {'solverNy','Ny'}, cfg.solverNy));
cfg.Lx = local_kv_num(manifestText, {'Lx','domainLx'}, cfg.Lx);
cfg.Ly = local_kv_num(manifestText, {'Ly','domainLy'}, cfg.Ly);
cfg.recordEvery = local_kv_num(manifestText, {'recordEvery'}, NaN);

% Params file is authoritative for walls and surface tension.
paramsFile = local_first_file(fullfile(runRoot,'params','*.kv'));
if ~isempty(paramsFile)
    paramsText = fileread(paramsFile);
    cfg.Lx = local_kv_num(paramsText, {'Lx'}, cfg.Lx);
    cfg.Ly = local_kv_num(paramsText, {'Ly'}, cfg.Ly);
    cfg.solverNx = round(local_kv_num(paramsText, {'Nx'}, cfg.solverNx));
    cfg.solverNy = round(local_kv_num(paramsText, {'Ny'}, cfg.solverNy));
    cfg.UwBottom = local_kv_num(paramsText, {'wallUxBottom'}, cfg.UwBottom);
    cfg.UwTop = local_kv_num(paramsText, {'wallUxTop'}, cfg.UwTop);
    cfg.sigma = local_kv_num(paramsText, ...
        {'surfaceTensionSigma','q6GfSurfaceTensionSigma'}, cfg.sigma);
end

% Environment snapshot contains LIQUID_CELLS in the supplied runner.
envFile = local_first_file(fullfile(runRoot,'logs','environment_0493x23f.env'));
if isempty(envFile)
    envFile = local_first_file(fullfile(runRoot,'logs','environment*.env'));
end
if ~isempty(envFile)
    envText = fileread(envFile);
    cfg.liquidCells = round(local_kv_num(envText, ...
        {'LIQUID_CELLS'}, cfg.liquidCells));
end

if cfg.ny <= 0 || cfg.nx <= 0
    error('Invalid recorder grid %dx%d.',cfg.nx,cfg.ny);
end
if cfg.solverNy <= 0 || cfg.solverNx <= 0
    error('Invalid solver grid %dx%d.',cfg.solverNx,cfg.solverNy);
end
if cfg.liquidCells <= 0 || cfg.liquidCells >= cfg.solverNy
    error('LIQUID_CELLS=%d incompatible with solver Ny=%d.', ...
        cfg.liquidCells,cfg.solverNy);
end

% Solver spacing controls physical geometry and fit exclusion distances.
cfg.hx = cfg.Lx/cfg.solverNx;
cfg.hy = cfg.Ly/cfg.solverNy;
if abs(cfg.hx-cfg.hy) > 1e-10*max(cfg.hx,cfg.hy)
    warning('Solver cells are not square: hx=%.12g hy=%.12g.',cfg.hx,cfg.hy);
end
cfg.h = cfg.hy;

% Recorder spacing controls the physical position of recorded rows.
cfg.recHx = cfg.Lx/cfg.nx;
cfg.recHy = cfg.Ly/cfg.ny;

cfg.yGamma = cfg.liquidCells*cfg.h;
cfg.hL = cfg.yGamma;
cfg.hG = cfg.Ly-cfg.yGamma;
cfg.Uw = cfg.UwTop-cfg.UwBottom;

% rho is accumulated particle mass per recorder bin. Its absolute value
% depends on recorder resolution; the phase ratio is resolution-independent.
cfg.rhoScale = 1.0;

%% ========================================================================
% Inventory complete LiveVis frames
% =========================================================================
rhoFiles = dir(fullfile(recDir,'step_*_field_rho.f32'));
if isempty(rhoFiles)
    error('No rho LiveVis frames under %s',recDir);
end

steps = [];
rhoNames = {};
uxNames = {};
uyNames = {};

for i = 1:numel(rhoFiles)
    tok = regexp(rhoFiles(i).name, ...
        '^step_(\d+)_field_rho\.f32$','tokens','once');
    if isempty(tok), continue; end

    s = str2double(tok{1});
    uxName = regexprep(rhoFiles(i).name, ...
        '_field_rho\.f32$','_field_ux.f32');
    uyName = regexprep(rhoFiles(i).name, ...
        '_field_rho\.f32$','_field_uy.f32');

    if isfile(fullfile(recDir,uxName)) && ...
       isfile(fullfile(recDir,uyName))
        steps(end+1,1) = s; %#ok<AGROW>
        rhoNames{end+1,1} = rhoFiles(i).name; %#ok<AGROW>
        uxNames{end+1,1} = uxName; %#ok<AGROW>
        uyNames{end+1,1} = uyName; %#ok<AGROW>
    end
end

[steps,ord] = sort(steps);
rhoNames = rhoNames(ord);
uxNames = uxNames(ord);
uyNames = uyNames(ord);

if isempty(steps)
    error('No complete rho/ux/uy LiveVis frames in %s',recDir);
end

if ~isfinite(cfg.recordEvery) || cfg.recordEvery <= 0
    if numel(steps) >= 2
        cfg.recordEvery = median(diff(steps));
    else
        cfg.recordEvery = 1;
    end
end

% Frames in this code family are usually 1,21,...,N-19.
% Recover the nominal requested end step for clean terminal windows.
lastRecordedStep = steps(end);
nominalEndStep = ceil(lastRecordedStep/cfg.recordEvery)*cfg.recordEvery;

if nargin < 3 || isempty(primaryEndStep)
    primaryEndStep = nominalEndStep;
end
if nargin < 2 || isempty(primaryStartStep)
    primaryStartStep = max(0,primaryEndStep-min(4000,primaryEndStep));
end

if primaryStartStep >= primaryEndStep
    error('primaryStartStep must be < primaryEndStep.');
end

fprintf('[0493x23f-analysis] run=%s\n',runRoot);
fprintf('[0493x23f-analysis] recording=%s\n',recDir);
fprintf(['[0493x23f-analysis] frames=%d recorded=%d..%d ', ...
         'nominalEnd=%d recordEvery=%g\n'], ...
    numel(steps),steps(1),steps(end),nominalEndStep,cfg.recordEvery);
fprintf(['[0493x23f-analysis] solverGrid=%dx%d recorderGrid=%dx%d ', ...
         'L=%.6g x %.6g hSolver=%.9g interface y/h=%d sigma=%.9g\n'], ...
    cfg.solverNx,cfg.solverNy,cfg.nx,cfg.ny,cfg.Lx,cfg.Ly,cfg.h, ...
    cfg.liquidCells,cfg.sigma);

%% ========================================================================
% Read once: horizontal conservative row sums for every frame
% =========================================================================
nF = numel(steps);
rhoRows = zeros(nF,cfg.ny);
pxRows  = zeros(nF,cfg.ny);
pyRows  = zeros(nF,cfg.ny);

% Additional homogeneity diagnostic: horizontal rho variance.
rho2Rows = zeros(nF,cfg.ny);

for i = 1:nF
    rho = local_read_f32(fullfile(recDir,rhoNames{i}),cfg.nx,cfg.ny) ...
        * cfg.rhoScale;
    ux  = local_read_f32(fullfile(recDir,uxNames{i}),cfg.nx,cfg.ny);
    uy  = local_read_f32(fullfile(recDir,uyNames{i}),cfg.nx,cfg.ny);

    if any(~isfinite(rho(:))) || any(~isfinite(ux(:))) || ...
       any(~isfinite(uy(:)))
        error('NaN/Inf in frame step=%d.',steps(i));
    end

    rhoRows(i,:)  = sum(rho,2).';
    rho2Rows(i,:) = sum(rho.^2,2).';
    pxRows(i,:)   = sum(rho.*ux,2).';
    pyRows(i,:)   = sum(rho.*uy,2).';

    if mod(i,100)==0 || i==nF
        fprintf('[0493x23f-analysis] read %d/%d frames step=%d\n', ...
            i,nF,steps(i));
    end
end

data = struct();
data.steps = steps;
data.rhoRows = rhoRows;
data.rho2Rows = rho2Rows;
data.pxRows = pxRows;
data.pyRows = pyRows;

%% ========================================================================
% Main estimates
% =========================================================================
[ePrimary,pPrimary] = local_estimate(data,primaryStartStep, ...
    primaryEndStep,cfg,true);

[eFull,~] = local_estimate(data,0,primaryEndStep,cfg,false);

lateHalfStart = max(0,primaryEndStep/2);
lateHalfMask = data.steps > lateHalfStart & data.steps <= primaryEndStep;
if nnz(lateHalfMask) >= 2
    [eLateHalf,~] = local_estimate(data,lateHalfStart, ...
        primaryEndStep,cfg,false);
else
    eLateHalf = local_empty_estimate();
    eLateHalf.startStep = lateHalfStart;
    eLateHalf.endStep = primaryEndStep;
    eLateHalf.nFrames = nnz(lateHalfMask);
    warning('0493x23f:LateHalfUnavailable', ...
        ['Late-half window (%g,%g] contains only %d frame(s); ', ...
         'late-half estimate skipped for this short smoke run.'], ...
        lateHalfStart,primaryEndStep,eLateHalf.nFrames);
end

% Dynamic rolling window:
% 400 steps for a 1000-step smoke; up to 2000 steps for long runs.
duration = max(primaryEndStep,1);
rollingWindow = min(2000,max(400, ...
    100*round((0.25*duration)/100)));
rollingWindow = min(rollingWindow,primaryEndStep);
rollingStride = max(100,100*round((rollingWindow/10)/100));

rollEnds = rollingWindow:rollingStride:primaryEndStep;
if isempty(rollEnds) || rollEnds(end) ~= primaryEndStep
    rollEnds = unique([rollEnds primaryEndStep]);
end

rolling = repmat(local_empty_estimate(),numel(rollEnds),1);
keepRoll = false(numel(rollEnds),1);
for k = 1:numel(rollEnds)
    s0 = max(0,rollEnds(k)-rollingWindow);
    try
        rolling(k) = local_estimate(data,s0,rollEnds(k),cfg,false);
        keepRoll(k) = true;
    catch
        keepRoll(k) = false;
    end
end
rolling = rolling(keepRoll);
Troll = struct2table(rolling);

% Terminal windows.
termCandidates = [400 800 1000 2000 4000 6000];
termCandidates = unique(termCandidates(termCandidates <= primaryEndStep));
if isempty(termCandidates)
    termCandidates = primaryEndStep;
end

terminal = repmat(local_empty_estimate(),numel(termCandidates),1);
keepTerm = false(numel(termCandidates),1);
for k = 1:numel(termCandidates)
    try
        terminal(k) = local_estimate(data, ...
            primaryEndStep-termCandidates(k),primaryEndStep,cfg,false);
        keepTerm(k) = true;
    catch
        keepTerm(k) = false;
    end
end
terminal = terminal(keepTerm);
Tterm = struct2table(terminal);
Tterm.windowSteps = termCandidates(keepTerm).';

%% ========================================================================
% Output
% =========================================================================
outDir = fullfile(runRoot,'analysis_0493x23f_semi_couette');
if ~isfolder(outDir), mkdir(outDir); end

writetable(Troll,fullfile(outDir,'semi_couette_rolling_0493x23f.csv'));
writetable(Tterm,fullfile(outDir,'semi_couette_terminal_0493x23f.csv'));

local_plot_profile(pPrimary,ePrimary,cfg, ...
    fullfile(outDir,'semi_couette_profile_0493x23f.png'));
local_plot_rolling(Troll,cfg,rollingWindow, ...
    fullfile(outDir,'semi_couette_rolling_0493x23f.png'));
local_plot_terminal(Tterm,cfg, ...
    fullfile(outDir,'semi_couette_terminal_0493x23f.png'));

summaryFile = fullfile(outDir,'semi_couette_summary_0493x23f.txt');
fid = fopen(summaryFile,'w');
if fid < 0, error('Cannot write %s',summaryFile); end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid,'===== 0493x23f ARTICLE SEMI-COUETTE S|L|G|S =====\n');
fprintf(fid,'runRoot = %s\n',runRoot);
fprintf(fid,'recording = %s\n',recDir);
fprintf(fid,'frames available = %d ; recorded steps = [%d,%d]\n', ...
    nF,steps(1),steps(end));
fprintf(fid,'nominal end step = %d ; recordEvery = %.12g\n', ...
    nominalEndStep,cfg.recordEvery);
fprintf(fid,'solver grid = %dx%d ; recorder grid = %dx%d\n', ...
    cfg.solverNx,cfg.solverNy,cfg.nx,cfg.ny);
fprintf(fid,'Lx=%.12g ; Ly=%.12g ; hSolver=%.12g ; hRecorderY=%.12g\n', ...
    cfg.Lx,cfg.Ly,cfg.h,cfg.recHy);
fprintf(fid,'geometry = S | L(%d solver cells) | G(%d solver cells) | S\n', ...
    cfg.liquidCells,cfg.solverNy-cfg.liquidCells);
fprintf(fid,'yGamma = %.12g = %d h\n',cfg.yGamma,cfg.liquidCells);
fprintf(fid,'wallUxBottom = %.12g ; wallUxTop = %.12g ; DeltaUw = %.12g\n', ...
    cfg.UwBottom,cfg.UwTop,cfg.Uw);
fprintf(fid,'surfaceTensionSigma = %.12g\n',cfg.sigma);
fprintf(fid,'nuL = %.12g ; nuG = %.12g ; nuG/nuL = %.12g\n', ...
    cfg.nuL,cfg.nuG,cfg.nuG/cfg.nuL);
fprintf(fid,'fit liquid = [bottom+%dh, interface-%dh]\n', ...
    cfg.excludeWallCells,cfg.excludeInterfaceCells);
fprintf(fid,'fit gas = [interface+%dh, top-%dh]\n\n', ...
    cfg.excludeInterfaceCells,cfg.excludeWallCells);

fprintf(fid,'PRIMARY WINDOW (%g,%g]\n',primaryStartStep,primaryEndStep);
local_print_estimate(fid,ePrimary);

fprintf(fid,'\nFULL WINDOW (0,%g]\n',primaryEndStep);
local_print_estimate(fid,eFull);

fprintf(fid,'\nLATE HALF (%g,%g]\n',lateHalfStart,primaryEndStep);
if eLateHalf.nFrames >= 2
    local_print_estimate(fid,eLateHalf);
else
    fprintf(fid,'SKIPPED: only %d frame(s) available in this window.\n', ...
        eLateHalf.nFrames);
end

if height(Tterm) >= 2
    fprintf(fid,'\nTERMINAL WINDOW SENSITIVITY\n');
    fprintf(fid,['window   aL          aG          aL/aG      muG/muL     ', ...
        'Rtau        R2L       R2G       slipGamma/Uw\n']);
    for k = 1:height(Tterm)
        fprintf(fid,'%6g  %11.5g %11.5g %11.5g %11.5g %11.5g %9.5f %9.5f %+12.5g\n', ...
            Tterm.windowSteps(k),Tterm.aL(k),Tterm.aG(k), ...
            Tterm.slopeRatio(k),Tterm.muRatio(k),Tterm.Rtau(k), ...
            Tterm.R2L(k),Tterm.R2G(k),Tterm.interfaceSlipOverUw(k));
    end
end

fprintf(fid,'\nINTERPRETATION TARGETS\n');
fprintf(fid,'steady two-layer stress continuity : Rtau -> 1\n');
fprintf(fid,'interface velocity continuity      : interfaceSlip/Uw -> 0\n');
fprintf(fid,'bottom no-slip                     : bottomSlip/Uw -> 0\n');
fprintf(fid,'top no-slip                        : topSlip/Uw -> 0\n');
fprintf(fid,'piecewise linearity                : R2L,R2G -> 1\n');
fprintf(fid,['analytic reference uses measured rhoG/rhoL and independently ', ...
    'calibrated nuL,nuG.\n']);

clear cleanup

out = struct();
out.cfg = cfg;
out.runRoot = runRoot;
out.recDir = recDir;
out.primary = ePrimary;
out.full = eFull;
out.lateHalf = eLateHalf;
out.profile = pPrimary;
out.rolling = Troll;
out.terminal = Tterm;
out.outputDir = outDir;
out.summaryFile = summaryFile;

save(fullfile(outDir,'semi_couette_0493x23f.mat'),'out');

fprintf('\n[0493x23f-analysis] PRIMARY (%g,%g]\n', ...
    primaryStartStep,primaryEndStep);
local_console_estimate(ePrimary);
fprintf('[0493x23f-analysis] summary=%s\n',summaryFile);

end

% =========================================================================
% Window estimate
% =========================================================================
function [e,p] = local_estimate(data,startStep,endStep,cfg,wantProfile)

idx = data.steps > startStep & data.steps <= endStep;
nFrames = nnz(idx);
if nFrames < 2
    error('Window (%g,%g] has only %d frame(s); need at least 2 for the short diagnostic.', ...
        startStep,endStep,nFrames);
elseif nFrames < 5
    warning('0493x23f:LowFrameCount', ...
        'Window (%g,%g] has only %d frames: usable for a smoke/profile diagnostic, not for final statistics.', ...
        startStep,endStep,nFrames);
end

R = sum(data.rhoRows(idx,:),1).';
R2sum = sum(data.rho2Rows(idx,:),1).';
Px = sum(data.pxRows(idx,:),1).';
Py = sum(data.pyRows(idx,:),1).';

% Recorded rows live on the recorder grid, not on the solver grid.
y = ((1:cfg.ny).'-0.5)*cfg.recHy;

rho = R/(nFrames*cfg.nx);
ux = Px./R;
uy = Py./R;

% Horizontal density standard deviation, averaged consistently in time.
meanRho2 = R2sum/(nFrames*cfg.nx);
rhoXStd = sqrt(max(meanRho2-rho.^2,0));

maskL = y >= cfg.excludeWallCells*cfg.h & ...
        y <= cfg.yGamma-cfg.excludeInterfaceCells*cfg.h;

maskG = y >= cfg.yGamma+cfg.excludeInterfaceCells*cfg.h & ...
        y <= cfg.Ly-cfg.excludeWallCells*cfg.h;

if nnz(maskL) < 4 || nnz(maskG) < 4
    error('Fit windows too small: nL=%d nG=%d.',nnz(maskL),nnz(maskG));
end

[aL,bL,R2L] = local_line_fit(y(maskL),ux(maskL));
[aG,bG,R2G] = local_line_fit(y(maskG),ux(maskG));

rhoL = mean(rho(maskL));
rhoG = mean(rho(maskG));

muRatio = (rhoG*cfg.nuG)/(rhoL*cfg.nuL);
slopeRatio = aL/aG;
Rtau = slopeRatio/muRatio;

% Extrapolated values at interface and walls.
uLI = aL*cfg.yGamma+bL;
uGI = aG*cfg.yGamma+bG;
uLBottom = bL;
uGTop = aG*cfg.Ly+bG;

interfaceSlip = uGI-uLI;
bottomSlip = uLBottom-cfg.UwBottom;
topSlip = cfg.UwTop-uGTop;

% Analytical no-slip two-layer Couette reference based on measured mu ratio.
aGth = cfg.Uw/(cfg.hG+muRatio*cfg.hL);
aLth = muRatio*aGth;
uIth = cfg.UwBottom+aLth*cfg.hL;

uTheory = nan(size(y));
uTheory(y <= cfg.yGamma) = ...
    cfg.UwBottom+aLth*y(y <= cfg.yGamma);
uTheory(y > cfg.yGamma) = ...
    uIth+aGth*(y(y > cfg.yGamma)-cfg.yGamma);

uFit = nan(size(y));
uFit(y <= cfg.yGamma) = aL*y(y <= cfg.yGamma)+bL;
uFit(y > cfg.yGamma) = aG*y(y > cfg.yGamma)+bG;

profileMask = maskL | maskG;
fitRmsOverUw = sqrt(mean((ux(profileMask)-uFit(profileMask)).^2)) ...
    / max(abs(cfg.Uw),eps);
theoryRmsOverUw = sqrt(mean((ux(profileMask)-uTheory(profileMask)).^2)) ...
    / max(abs(cfg.Uw),eps);

uyRmsOverUw = sqrt(mean(uy(profileMask).^2)) ...
    / max(abs(cfg.Uw),eps);

rhoLCVy = std(rho(maskL),0)/max(abs(rhoL),eps);
rhoGCVy = std(rho(maskG),0)/max(abs(rhoG),eps);

rhoLHorizontalCV = mean(rhoXStd(maskL)./max(rho(maskL),eps));
rhoGHorizontalCV = mean(rhoXStd(maskG)./max(rho(maskG),eps));

e = local_empty_estimate();
e.startStep = startStep;
e.endStep = endStep;
e.nFrames = nFrames;

e.aL = aL;
e.aG = aG;
e.bL = bL;
e.bG = bG;
e.R2L = R2L;
e.R2G = R2G;
e.slopeRatio = slopeRatio;

e.rhoL = rhoL;
e.rhoG = rhoG;
e.rhoRatio = rhoG/rhoL;
e.muRatio = muRatio;
e.Rtau = Rtau;

e.uInterfaceL = uLI;
e.uInterfaceG = uGI;
e.uInterfaceTheory = uIth;
e.interfaceSlipOverUw = interfaceSlip/max(abs(cfg.Uw),eps);

e.uBottomFit = uLBottom;
e.uTopFit = uGTop;
e.bottomSlipOverUw = bottomSlip/max(abs(cfg.Uw),eps);
e.topSlipOverUw = topSlip/max(abs(cfg.Uw),eps);

e.aLTheory = aLth;
e.aGTheory = aGth;
e.aLOverTheory = aL/aLth;
e.aGOverTheory = aG/aGth;

e.fitRmsOverUw = fitRmsOverUw;
e.theoryRmsOverUw = theoryRmsOverUw;
e.uyRmsOverUw = uyRmsOverUw;

e.rhoLCVy = rhoLCVy;
e.rhoGCVy = rhoGCVy;
e.rhoLHorizontalCV = rhoLHorizontalCV;
e.rhoGHorizontalCV = rhoGHorizontalCV;

if wantProfile
    p = struct();
    p.y = y;
    p.yOverH = y/cfg.h;
    p.rho = rho;
    p.rhoXStd = rhoXStd;
    p.ux = ux;
    p.uy = uy;
    p.uFit = uFit;
    p.uTheory = uTheory;
    p.maskL = maskL;
    p.maskG = maskG;
else
    p = struct();
end

end

function e = local_empty_estimate()
e = struct( ...
    'startStep',NaN,'endStep',NaN,'nFrames',NaN, ...
    'aL',NaN,'aG',NaN,'bL',NaN,'bG',NaN, ...
    'R2L',NaN,'R2G',NaN,'slopeRatio',NaN, ...
    'rhoL',NaN,'rhoG',NaN,'rhoRatio',NaN, ...
    'muRatio',NaN,'Rtau',NaN, ...
    'uInterfaceL',NaN,'uInterfaceG',NaN,'uInterfaceTheory',NaN, ...
    'interfaceSlipOverUw',NaN, ...
    'uBottomFit',NaN,'uTopFit',NaN, ...
    'bottomSlipOverUw',NaN,'topSlipOverUw',NaN, ...
    'aLTheory',NaN,'aGTheory',NaN, ...
    'aLOverTheory',NaN,'aGOverTheory',NaN, ...
    'fitRmsOverUw',NaN,'theoryRmsOverUw',NaN,'uyRmsOverUw',NaN, ...
    'rhoLCVy',NaN,'rhoGCVy',NaN, ...
    'rhoLHorizontalCV',NaN,'rhoGHorizontalCV',NaN);
end

% =========================================================================
% Figures
% =========================================================================
function local_plot_profile(p,e,cfg,fileName)

f = figure('Color','w','Position',[100 80 1450 850]);
tl = tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('0493x23f semi-Couette S|L|G|S, window (%g,%g]', ...
    e.startStep,e.endStep));

nexttile;
plot(p.ux/cfg.Uw,p.yOverH,'o','MarkerSize',4); hold on;
plot(p.uFit/cfg.Uw,p.yOverH,'-','LineWidth',1.5);
plot(p.uTheory/cfg.Uw,p.yOverH,'--','LineWidth',1.5);
yline(cfg.yGamma/cfg.h,':','interface');
xline(cfg.UwBottom/cfg.Uw,':');
xline(cfg.UwTop/cfg.Uw,':');
grid on;
xlabel('u_x / \Delta U_w');
ylabel('y/h');
legend('conservative mean','piecewise fits','two-layer theory', ...
    'Location','best');
title(sprintf('R_\\tau=%.4g, slip_\\Gamma/U_w=%+.3g', ...
    e.Rtau,e.interfaceSlipOverUw));

nexttile;
plot(p.rho,p.yOverH,'-','LineWidth',1.2); hold on;
yline(cfg.yGamma/cfg.h,':','interface');
grid on;
xlabel('\rho');
ylabel('y/h');
title(sprintf('\\rho_L=%.4g, \\rho_G=%.4g',e.rhoL,e.rhoG));

nexttile;
plot(p.uy/cfg.Uw,p.yOverH,'-','LineWidth',1.2); hold on;
xline(0,':');
yline(cfg.yGamma/cfg.h,':','interface');
grid on;
xlabel('u_y / \Delta U_w');
ylabel('y/h');
title(sprintf('u_y RMS/U_w = %.3g',e.uyRmsOverUw));

local_save_figure(f,fileName);
end

function local_plot_rolling(T,cfg,windowSteps,fileName)

if isempty(T), return; end

f = figure('Color','w','Position',[100 80 1350 900]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('0493x23f rolling diagnostics, window=%g steps',windowSteps));

nexttile;
plot(T.endStep,T.aL,'-o','MarkerSize',3); hold on;
plot(T.endStep,T.aLTheory,'--','LineWidth',1.2);
grid on; xlabel('step'); ylabel('a_L');
legend('measured','two-layer theory','Location','best');
title('Liquid slope');

nexttile;
plot(T.endStep,T.aG,'-o','MarkerSize',3); hold on;
plot(T.endStep,T.aGTheory,'--','LineWidth',1.2);
grid on; xlabel('step'); ylabel('a_G');
legend('measured','two-layer theory','Location','best');
title('Gas slope');

nexttile;
plot(T.endStep,T.Rtau,'-o','MarkerSize',3); hold on;
yline(1,':');
grid on; xlabel('step'); ylabel('R_\tau');
title('\mu_L a_L / (\mu_G a_G)');

nexttile;
plot(T.endStep,T.interfaceSlipOverUw,'-o','MarkerSize',3); hold on;
plot(T.endStep,T.bottomSlipOverUw,'--','LineWidth',1.1);
plot(T.endStep,T.topSlipOverUw,'-.','LineWidth',1.1);
yline(0,':');
grid on; xlabel('step'); ylabel('slip / \Delta U_w');
legend('interface','bottom wall','top wall','Location','best');
title('Velocity continuity / wall no-slip');

local_save_figure(f,fileName);
end

function local_plot_terminal(T,cfg,fileName) %#ok<INUSD>

if isempty(T), return; end

f = figure('Color','w','Position',[100 80 1350 800]);
tl = tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
title(tl,'0493x23f terminal-window sensitivity');

nexttile;
plot(T.windowSteps,T.aL,'-o'); hold on;
plot(T.windowSteps,T.aLTheory,'--');
grid on; xlabel('terminal window [steps]'); ylabel('a_L');
title('Liquid slope');

nexttile;
plot(T.windowSteps,T.aG,'-o'); hold on;
plot(T.windowSteps,T.aGTheory,'--');
grid on; xlabel('terminal window [steps]'); ylabel('a_G');
title('Gas slope');

nexttile;
plot(T.windowSteps,T.Rtau,'-o'); hold on;
yline(1,':');
grid on; xlabel('terminal window [steps]'); ylabel('R_\tau');
title('Stress continuity');

local_save_figure(f,fileName);
end

function local_save_figure(f,fileName)
try
    exportgraphics(f,fileName,'Resolution',180);
catch
    saveas(f,fileName);
end
%close(f);
end

% =========================================================================
% Reporting
% =========================================================================
function local_print_estimate(fid,e)

fprintf(fid,'frames = %d\n',e.nFrames);
fprintf(fid,'aL = %.12g ; R2L = %.10g\n',e.aL,e.R2L);
fprintf(fid,'aG = %.12g ; R2G = %.10g\n',e.aG,e.R2G);
fprintf(fid,'aL/aG = %.12g\n',e.slopeRatio);

fprintf(fid,'rhoL = %.12g ; rhoG = %.12g ; rhoG/rhoL = %.12g\n', ...
    e.rhoL,e.rhoG,e.rhoRatio);
fprintf(fid,'muG/muL = %.12g\n',e.muRatio);
fprintf(fid,'Rtau = muL*aL/(muG*aG) = %.12g\n',e.Rtau);

fprintf(fid,'theory aL = %.12g ; measured/theory = %.12g\n', ...
    e.aLTheory,e.aLOverTheory);
fprintf(fid,'theory aG = %.12g ; measured/theory = %.12g\n', ...
    e.aGTheory,e.aGOverTheory);

fprintf(fid,'uGamma liquid fit = %.12g\n',e.uInterfaceL);
fprintf(fid,'uGamma gas fit    = %.12g\n',e.uInterfaceG);
fprintf(fid,'uGamma theory     = %.12g\n',e.uInterfaceTheory);
fprintf(fid,'interface slip/Uw = %+.12g\n',e.interfaceSlipOverUw);

fprintf(fid,'bottom fit velocity = %.12g ; bottom slip/Uw = %+.12g\n', ...
    e.uBottomFit,e.bottomSlipOverUw);
fprintf(fid,'top fit velocity = %.12g ; top slip/Uw = %+.12g\n', ...
    e.uTopFit,e.topSlipOverUw);

fprintf(fid,'piecewise-fit RMS/Uw = %.12g\n',e.fitRmsOverUw);
fprintf(fid,'continuum-theory RMS/Uw = %.12g\n',e.theoryRmsOverUw);
fprintf(fid,'uy RMS/Uw = %.12g\n',e.uyRmsOverUw);

fprintf(fid,'rhoL vertical CV = %.12g ; rhoG vertical CV = %.12g\n', ...
    e.rhoLCVy,e.rhoGCVy);
fprintf(fid,'rhoL mean horizontal CV = %.12g ; rhoG mean horizontal CV = %.12g\n', ...
    e.rhoLHorizontalCV,e.rhoGHorizontalCV);
end

function local_console_estimate(e)
fprintf('  aL=%.8g  R2L=%.5f  theory=%.8g  gain=%.4f\n', ...
    e.aL,e.R2L,e.aLTheory,e.aLOverTheory);
fprintf('  aG=%.8g  R2G=%.5f  theory=%.8g  gain=%.4f\n', ...
    e.aG,e.R2G,e.aGTheory,e.aGOverTheory);
fprintf('  rhoG/rhoL=%.8g  muG/muL=%.8g\n', ...
    e.rhoRatio,e.muRatio);
fprintf('  aL/aG=%.8g  Rtau=%.8g\n',e.slopeRatio,e.Rtau);
fprintf('  slip interface=%+.3f%% bottom=%+.3f%% top=%+.3f%%\n', ...
    100*e.interfaceSlipOverUw,100*e.bottomSlipOverUw, ...
    100*e.topSlipOverUw);
fprintf('  theory RMS/Uw=%.4g  uy RMS/Uw=%.4g\n', ...
    e.theoryRmsOverUw,e.uyRmsOverUw);
end

% =========================================================================
% Utilities
% =========================================================================
function [a,b,R2] = local_line_fit(x,y)
x=x(:); y=y(:);
ok=isfinite(x)&isfinite(y);
x=x(ok); y=y(ok);

X=[x,ones(size(x))];
beta=X\y;
a=beta(1);
b=beta(2);

yh=X*beta;
ssRes=sum((y-yh).^2);
ssTot=sum((y-mean(y)).^2);
if ssTot>0
    R2=1-ssRes/ssTot;
else
    R2=NaN;
end
end

function A = local_read_f32(fileName,nx,ny)
fid=fopen(fileName,'r','ieee-le');
if fid<0, error('Cannot open %s',fileName); end
c=onCleanup(@() fclose(fid));
v=fread(fid,nx*ny,'single=>double');
if numel(v)~=nx*ny
    error('%s : got %d values, expected %d.', ...
        fileName,numel(v),nx*ny);
end
% Recorder is row-major: x varies fastest.
A=reshape(v,[nx,ny]).';
end

function val = local_kv_num(txt,keys,defaultVal)
val=defaultVal;
for i=1:numel(keys)
    key=regexptranslate('escape',keys{i});
    tok=regexp(txt,['(?m)^\s*' key '\s*=\s*([^\r\n#]+)'], ...
        'tokens','once');
    if ~isempty(tok)
        x=str2double(strtrim(tok{1}));
        if isfinite(x)
            val=x;
            return;
        end
    end
end
end

function f = local_first_file(pattern)
d=dir(pattern);
if isempty(d)
    f='';
else
    f=fullfile(d(1).folder,d(1).name);
end
end

function [recDir,manifestFile] = local_find_recording_dir(runRoot)

base=fullfile(runRoot,'output','recordings');
if ~isfolder(base)
    error('Recording base directory missing: %s',base);
end

% First look for directories with both manifest and rho frames.
d=dir(base);
for i=1:numel(d)
    if ~d(i).isdir || any(strcmp(d(i).name,{'.','..'})), continue; end
    candidate=fullfile(base,d(i).name);
    mf=fullfile(candidate,'manifest.kv');
    rr=dir(fullfile(candidate,'step_*_field_rho.f32'));
    if isfile(mf) && ~isempty(rr)
        recDir=candidate;
        manifestFile=mf;
        return;
    end
end

% Some recorder layouts place files directly in output/recordings.
mf=fullfile(base,'manifest.kv');
rr=dir(fullfile(base,'step_*_field_rho.f32'));
if isfile(mf) && ~isempty(rr)
    recDir=base;
    manifestFile=mf;
    return;
end

error('No LiveVis recording with manifest + rho frames under %s',base);
end

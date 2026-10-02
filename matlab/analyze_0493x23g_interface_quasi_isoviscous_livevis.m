function out = analyze_0493x23g_interface_quasi_isoviscous_livevis(runRoot, primaryStartStep, primaryEndStep)
%ANALYZE_0493X23G_INTERFACE_QUASI_ISOVISCOUS_LIVEVIS
%
% Analyse CENTREE INTERFACE du benchmark 0493x23g :
%
%       S | L(Q6-g-f) | G(SRC) | S
%
% Le but n'est PAS de reconstruire une solution de Couette a partir des
% conditions no-slip aux parois. Les parois servent seulement a produire un
% cisaillement mesurable. La qualification porte localement sur l'interface.
%
% Observables principales, dans des bandes one-sided a distance de Gamma :
%
%   1) continuite de vitesse tangentielle
%          Delta u_Gamma = u_G(Gamma+) - u_L(Gamma-) -> 0
%
%   2) continuite de contrainte tangentielle
%          mu_L a_L = mu_G a_G
%      avec
%          a_L = du_x/dy cote liquide
%          a_G = du_x/dy cote gaz
%          mu_G/mu_L = (rho_G nu_G)/(rho_L nu_L)
%
%   3) rapport local
%          R_tau,local = (rho_L nu_L a_L)/(rho_G nu_G a_G) -> 1
%
% Les densites rho_L et rho_G sont mesurees DANS LES MEMES bandes locales que
% les gradients. Les viscosites cinematiques viennent de la cartographie de
% transport article L036_G08_A120 et sont lues dans l'environnement du run si
% elles y sont presentes.
%
% IMPORTANT :
%   - aucune hypothese no-slip aux murs n'entre dans R_tau,local ;
%   - l'interface est localisee frame par frame via rho1/(rho1+rho2)=0.5 ;
%   - les profils sont realignes sur cette interface avant moyennage ;
%   - les points de fit doivent etre quasi-purs en composition (YL >= 0.90
%     cote liquide, YL <= 0.10 cote gaz par defaut) ;
%   - plusieurs bandes [dmin,dmax]/h sont testees pour verifier que la
%     conclusion ne depend pas d'une seule fenetre arbitraire.
%
% La tension superficielle n'est PAS supposee nulle par l'analyseur. La valeur
% effectivement utilisee par le run est lue dans les params / l'environnement
% et reportee. Un run relance avec sigma=2560 est donc analyse tel quel.
%
% Usage depuis matlab/ :
%
%   out = analyze_0493x23g_interface_quasi_isoviscous_livevis( ...
%       '../runs/0493x23g_interface_quasi_isoviscous_128x128_Uw0.04_seed593172');
%
% Fenetre explicite :
%
%   out = analyze_0493x23g_interface_quasi_isoviscous_livevis( ...
%       '../runs/...', 4000, 8000);
%
% Si la fenetre n'est pas donnee, les 4000 derniers steps nominaux sont pris.
%
% Sorties :
%   <runRoot>/analysis_0493x23g_interface/
%     interface_summary_0493x23g.txt
%     interface_profile_0493x23g.csv
%     interface_fit_bands_0493x23g.csv
%     interface_rolling_0493x23g.csv
%     interface_profile_0493x23g.png
%     interface_fit_sensitivity_0493x23g.png
%     interface_rolling_0493x23g.png
%     interface_0493x23g.mat

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs', ...
        '0493x23g_interface_quasi_isoviscous_128x128_Uw0.04_seed593172');
end
runRoot = char(runRoot);

%% ========================================================================
% Configuration defaults (overwritten from run metadata whenever possible)
% =========================================================================
cfg = struct();
cfg.transportCase = 'L036_G08_A120';
cfg.nuL = 0.00071853512255;
cfg.nuG = 0.0006774787066662;
cfg.nuLStd = 0.00007148437368744265;
cfg.nuGStd = 0.0000665780874244649;

cfg.Lx = 0.5;
cfg.Ly = 0.5;
cfg.solverNx = 128;
cfg.solverNy = 128;
cfg.recNx = 128;
cfg.recNy = 128;
cfg.liquidCells = 64;
cfg.UwBottom = -0.04;
cfg.UwTop = +0.04;
cfg.sigma = NaN;

% Composition threshold used to keep the local fits out of the mixed band.
cfg.pureThreshold = 0.90;

% Primary local fit band, in solver-cell units from the instantaneous Gamma.
cfg.defaultBandH = [4 12];

% Sensitivity sweep. A band may be skipped automatically if too few pure rows
% remain after applying the composition threshold.
cfg.fitBandsH = [ ...
     2  6; ...
     3  8; ...
     4 10; ...
     4 12; ...
     5 12; ...
     6 16; ...
     8 20; ...
    10 24];
cfg.minFitPoints = 4;
cfg.zoomH = 24;

%% ========================================================================
% Locate recording + metadata
% =========================================================================
[recDir, manifestFile] = local_find_recording_dir(runRoot);
manifestText = fileread(manifestFile);

% Recorder dimensions come ONLY from the recorder manifest. Solver dimensions
% remain separate to avoid the old x23f 64/250-grid metrology error.
cfg.recNx = round(local_kv_num(manifestText, ...
    {'liveGridNx','recordGridNx'}, cfg.recNx));
cfg.recNy = round(local_kv_num(manifestText, ...
    {'liveGridNy','recordGridNy'}, cfg.recNy));
cfg.solverNx = round(local_kv_num(manifestText, ...
    {'solverNx','Nx'}, cfg.solverNx));
cfg.solverNy = round(local_kv_num(manifestText, ...
    {'solverNy','Ny'}, cfg.solverNy));
cfg.Lx = local_kv_num(manifestText, {'Lx','domainLx'}, cfg.Lx);
cfg.Ly = local_kv_num(manifestText, {'Ly','domainLy'}, cfg.Ly);
cfg.recordEvery = local_kv_num(manifestText, {'recordEvery'}, NaN);

% Solver params are authoritative for geometry, walls and sigma. They must NOT
% overwrite recNx/recNy.
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

% Environment snapshot: article transport references + liquid geometry + sigma
% override used by the actual run.
envFile = local_first_file(fullfile(runRoot,'logs','environment_0493x23g.env'));
if isempty(envFile)
    envFile = local_first_file(fullfile(runRoot,'logs','environment*.env'));
end
if ~isempty(envFile)
    envText = fileread(envFile);
    cfg.liquidCells = round(local_kv_num(envText, {'LIQUID_CELLS'}, cfg.liquidCells));
    cfg.nuL = local_kv_num(envText, {'ARTICLE_NU_L'}, cfg.nuL);
    cfg.nuG = local_kv_num(envText, {'ARTICLE_NU_G'}, cfg.nuG);
    cfg.nuLStd = local_kv_num(envText, {'ARTICLE_NU_L_STD'}, cfg.nuLStd);
    cfg.nuGStd = local_kv_num(envText, {'ARTICLE_NU_G_STD'}, cfg.nuGStd);
    cfg.sigma = local_kv_num(envText, {'SURFACE_TENSION_SIGMA'}, cfg.sigma);
    cfg.transportCase = local_kv_str(envText, {'ARTICLE_TRANSPORT_CASE'}, cfg.transportCase);
end

if cfg.solverNx <= 0 || cfg.solverNy <= 0 || cfg.recNx <= 0 || cfg.recNy <= 0
    error('Invalid solver/recorder grids: solver=%dx%d recorder=%dx%d.', ...
        cfg.solverNx,cfg.solverNy,cfg.recNx,cfg.recNy);
end
if cfg.liquidCells <= 0 || cfg.liquidCells >= cfg.solverNy
    error('LIQUID_CELLS=%d incompatible with solver Ny=%d.', ...
        cfg.liquidCells,cfg.solverNy);
end

cfg.hx = cfg.Lx/cfg.solverNx;
cfg.hy = cfg.Ly/cfg.solverNy;
if abs(cfg.hx-cfg.hy) > 1e-10*max(cfg.hx,cfg.hy)
    warning('0493x23g:NonSquareSolverCells', ...
        'Solver cells are not square: hx=%.12g hy=%.12g.',cfg.hx,cfg.hy);
end
cfg.h = cfg.hy;
cfg.recHx = cfg.Lx/cfg.recNx;
cfg.recHy = cfg.Ly/cfg.recNy;
cfg.yGammaNominal = cfg.liquidCells*cfg.h;
cfg.deltaUw = cfg.UwTop-cfg.UwBottom;

% Convert recorder-bin masses to solver-cell-equivalent densities. This scale
% cancels from phase ratios, but keeps rho values interpretable if recorder and
% solver grids ever differ.
cfg.rhoScale = (cfg.solverNx/cfg.recNx)*(cfg.solverNy/cfg.recNy);

cfg.nuRatio = cfg.nuG/cfg.nuL;
if isfinite(cfg.nuLStd) && isfinite(cfg.nuGStd) && ...
        cfg.nuL > 0 && cfg.nuG > 0
    cfg.nuRatioStdIndependent = cfg.nuRatio * sqrt( ...
        (cfg.nuGStd/cfg.nuG)^2 + (cfg.nuLStd/cfg.nuL)^2);
else
    cfg.nuRatioStdIndependent = NaN;
end

%% ========================================================================
% Inventory complete recorder frames
% =========================================================================
requiredFields = {'rho','rho1','rho2','ux','uy'};
[steps,names] = local_inventory_frames(recDir,requiredFields);

if isempty(steps)
    error(['No complete rho/rho1/rho2/ux/uy recorder frames under %s. ', ...
           'The x23g interface analyzer requires composition recording.'],recDir);
end

if ~isfinite(cfg.recordEvery) || cfg.recordEvery <= 0
    if numel(steps) >= 2
        cfg.recordEvery = median(diff(steps));
    else
        cfg.recordEvery = 1;
    end
end

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

fprintf('[0493x23g-analysis] run=%s\n',runRoot);
fprintf('[0493x23g-analysis] recording=%s\n',recDir);
fprintf(['[0493x23g-analysis] frames=%d recorded=%d..%d nominalEnd=%d ', ...
         'recordEvery=%g\n'],numel(steps),steps(1),steps(end), ...
         nominalEndStep,cfg.recordEvery);
fprintf(['[0493x23g-analysis] solver=%dx%d recorder=%dx%d h=%.9g ', ...
         'sigma=%.9g\n'],cfg.solverNx,cfg.solverNy,cfg.recNx,cfg.recNy, ...
         cfg.h,cfg.sigma);
fprintf(['[0493x23g-analysis] transport=%s nuL=%.9g nuG=%.9g ', ...
         'nuG/nuL=%.7g\n'],cfg.transportCase,cfg.nuL,cfg.nuG,cfg.nuRatio);

%% ========================================================================
% Read once: conservative row sums + per-frame interface position
% =========================================================================
nF = numel(steps);
yRec = ((1:cfg.recNy).'-0.5)*cfg.recHy;

data = struct();
data.steps = steps;
data.yRec = yRec;
data.rhoRows  = zeros(nF,cfg.recNy);
data.rho1Rows = zeros(nF,cfg.recNy);
data.rho2Rows = zeros(nF,cfg.recNy);
data.pxRows   = zeros(nF,cfg.recNy);
data.pyRows   = zeros(nF,cfg.recNy);
data.yGamma = nan(nF,1);
data.width1090 = nan(nF,1);
data.compositionClosureRel = nan(nF,1);

for i = 1:nF
    rho  = local_read_f32(fullfile(recDir,names.rho{i}), cfg.recNx,cfg.recNy) * cfg.rhoScale;
    rho1 = local_read_f32(fullfile(recDir,names.rho1{i}),cfg.recNx,cfg.recNy) * cfg.rhoScale;
    rho2 = local_read_f32(fullfile(recDir,names.rho2{i}),cfg.recNx,cfg.recNy) * cfg.rhoScale;
    ux   = local_read_f32(fullfile(recDir,names.ux{i}),  cfg.recNx,cfg.recNy);
    uy   = local_read_f32(fullfile(recDir,names.uy{i}),  cfg.recNx,cfg.recNy);

    if any(~isfinite(rho(:))) || any(~isfinite(rho1(:))) || ...
       any(~isfinite(rho2(:))) || any(~isfinite(ux(:))) || ...
       any(~isfinite(uy(:)))
        error('NaN/Inf in recorder frame step=%d.',steps(i));
    end

    R  = sum(rho,2);
    R1 = sum(rho1,2);
    R2 = sum(rho2,2);

    data.rhoRows(i,:)  = R.';
    data.rho1Rows(i,:) = R1.';
    data.rho2Rows(i,:) = R2.';
    data.pxRows(i,:)   = sum(rho.*ux,2).';
    data.pyRows(i,:)   = sum(rho.*uy,2).';

    den = R1+R2;
    YL = nan(size(den));
    ok = den > 0;
    YL(ok) = R1(ok)./den(ok);

    data.yGamma(i) = local_crossing_near(yRec,YL,0.5,cfg.yGammaNominal);
    y90 = local_crossing_near(yRec,YL,0.9,data.yGamma(i));
    y10 = local_crossing_near(yRec,YL,0.1,data.yGamma(i));
    if isfinite(y90) && isfinite(y10)
        data.width1090(i) = abs(y10-y90);
    end

    data.compositionClosureRel(i) = sum(abs(rho(:)-rho1(:)-rho2(:))) / ...
        max(sum(abs(rho(:))),eps);

    if mod(i,100)==0 || i==nF
        fprintf('[0493x23g-analysis] read %d/%d frames step=%d yGamma/h=%.5f\n', ...
            i,nF,steps(i),data.yGamma(i)/cfg.h);
    end
end

badGamma = ~isfinite(data.yGamma);
if any(badGamma)
    warning('0493x23g:InterfaceCrossingMissing', ...
        '%d/%d frames have no robust YL=0.5 crossing; nominal Gamma used there.', ...
        nnz(badGamma),nF);
    data.yGamma(badGamma) = cfg.yGammaNominal;
end

%% ========================================================================
% Primary estimate + local fit-band sensitivity
% =========================================================================
[ePrimary,pPrimary,Tbands] = local_window_estimate( ...
    data,primaryStartStep,primaryEndStep,cfg,true);

% Rolling stationarity of the INTERFACE observables only.
duration = max(primaryEndStep,1);
rollingWindow = min(2000,max(800,100*round((0.25*duration)/100)));
rollingWindow = min(rollingWindow,primaryEndStep);
rollingStride = max(200,100*round((rollingWindow/5)/100));
rollEnds = rollingWindow:rollingStride:primaryEndStep;
if isempty(rollEnds) || rollEnds(end) ~= primaryEndStep
    rollEnds = unique([rollEnds primaryEndStep]);
end

rolling = repmat(local_empty_estimate(),numel(rollEnds),1);
keepRoll = false(numel(rollEnds),1);
for k = 1:numel(rollEnds)
    s0 = max(0,rollEnds(k)-rollingWindow);
    try
        [rolling(k),~,~] = local_window_estimate(data,s0,rollEnds(k),cfg,false);
        keepRoll(k) = true;
    catch ME
        warning('0493x23g:RollingSkip','rolling (%g,%g] skipped: %s', ...
            s0,rollEnds(k),ME.message);
    end
end
rolling = rolling(keepRoll);
if isempty(rolling)
    Troll = table();
else
    Troll = struct2table(rolling);
end

%% ========================================================================
% Output
% =========================================================================
outDir = fullfile(runRoot,'analysis_0493x23g_interface');
if ~isfolder(outDir), mkdir(outDir); end

% Row-by-row interface-centered averaged profile.
Tprofile = table(pPrimary.zOverH,pPrimary.s,pPrimary.ux,pPrimary.uy, ...
    pPrimary.rho,pPrimary.rhoL,pPrimary.rhoG,pPrimary.YL,pPrimary.gradUx, ...
    'VariableNames',{'zOverH','distanceFromInterface','ux','uy', ...
    'rho','rhoLiquid','rhoGas','YLiquid','dux_dy'});
writetable(Tprofile,fullfile(outDir,'interface_profile_0493x23g.csv'));
writetable(Tbands,fullfile(outDir,'interface_fit_bands_0493x23g.csv'));
if ~isempty(Troll)
    writetable(Troll,fullfile(outDir,'interface_rolling_0493x23g.csv'));
end

local_plot_profile(pPrimary,ePrimary,cfg, ...
    fullfile(outDir,'interface_profile_0493x23g.png'));
local_plot_band_sensitivity(Tbands,cfg, ...
    fullfile(outDir,'interface_fit_sensitivity_0493x23g.png'));
if ~isempty(Troll)
    local_plot_rolling(Troll,cfg,rollingWindow, ...
        fullfile(outDir,'interface_rolling_0493x23g.png'));
end

summaryFile = fullfile(outDir,'interface_summary_0493x23g.txt');
fid = fopen(summaryFile,'w');
if fid < 0, error('Cannot write %s',summaryFile); end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid,'===== 0493x23g INTERFACE-CENTERED QUASI-ISOVISCOUS L/G =====\n');
fprintf(fid,'runRoot = %s\n',runRoot);
fprintf(fid,'recording = %s\n',recDir);
fprintf(fid,'frames available = %d ; recorded steps = [%d,%d]\n', ...
    nF,steps(1),steps(end));
fprintf(fid,'nominal end step = %d ; recordEvery = %.12g\n', ...
    nominalEndStep,cfg.recordEvery);
fprintf(fid,'solver grid = %dx%d ; recorder grid = %dx%d\n', ...
    cfg.solverNx,cfg.solverNy,cfg.recNx,cfg.recNy);
fprintf(fid,'Lx=%.12g ; Ly=%.12g ; h=%.12g ; nominal yGamma=%.12g\n', ...
    cfg.Lx,cfg.Ly,cfg.h,cfg.yGammaNominal);
fprintf(fid,'walls = [%.12g, %.12g] ; DeltaUw = %.12g\n', ...
    cfg.UwBottom,cfg.UwTop,cfg.deltaUw);
fprintf(fid,'surfaceTensionSigma = %.12g\n',cfg.sigma);
fprintf(fid,'transport case = %s\n',cfg.transportCase);
fprintf(fid,'nuL = %.12g +/- %.12g\n',cfg.nuL,cfg.nuLStd);
fprintf(fid,'nuG = %.12g +/- %.12g\n',cfg.nuG,cfg.nuGStd);
fprintf(fid,'nuG/nuL = %.12g ; independent propagated std = %.12g\n', ...
    cfg.nuRatio,cfg.nuRatioStdIndependent);
fprintf(fid,'pure composition threshold = %.6g\n',cfg.pureThreshold);
fprintf(fid,'default local fit band = [%.6g, %.6g] h from Gamma\n\n', ...
    cfg.defaultBandH(1),cfg.defaultBandH(2));

fprintf(fid,'PRIMARY WINDOW (%g,%g]\n',primaryStartStep,primaryEndStep);
local_print_estimate(fid,ePrimary,cfg);

fprintf(fid,'\nLOCAL FIT-BAND SENSITIVITY\n');
fprintf(fid,['band[h]      nL nG    aL           aG           aL/aG       ', ...
    'muG/muL      Rtau        R2L      R2G      slipG/L/DU\n']);
for k = 1:height(Tbands)
    fprintf(fid,'[%4.1f,%4.1f] %3d %3d %12.5g %12.5g %12.5g %12.5g %12.5g %8.5f %8.5f %+12.5g\n', ...
        Tbands.dMinH(k),Tbands.dMaxH(k),Tbands.nL(k),Tbands.nG(k), ...
        Tbands.aL(k),Tbands.aG(k),Tbands.slopeRatio(k), ...
        Tbands.muGOverMuL(k),Tbands.RtauLocal(k), ...
        Tbands.R2L(k),Tbands.R2G(k),Tbands.interfaceSlipOverDeltaU(k));
end

if ~isempty(Troll)
    fprintf(fid,'\nROLLING LOCAL STATIONARITY (window=%g steps)\n',rollingWindow);
    fprintf(fid,['endStep   yG/h       w10-90/h   aL/aG      muG/muL    ', ...
        'Rtau       slip/DU      R2L     R2G\n']);
    for k = 1:height(Troll)
        fprintf(fid,'%7g %10.5f %11.5f %11.5g %11.5g %11.5g %+12.5g %8.5f %8.5f\n', ...
            Troll.endStep(k),Troll.yGammaMeanOverH(k), ...
            Troll.interfaceWidth1090OverH(k),Troll.slopeRatio(k), ...
            Troll.muGOverMuL(k),Troll.RtauLocal(k), ...
            Troll.interfaceSlipOverDeltaU(k),Troll.R2L(k),Troll.R2G(k));
    end
end

fprintf(fid,'\nINTERPRETATION / ACCEPTANCE LOGIC\n');
fprintf(fid,'PRIMARY OBJECT: local L/G interaction, not remote wall no-slip.\n');
fprintf(fid,'velocity continuity: interfaceSlip/DeltaUw -> 0.\n');
fprintf(fid,'tangential stress continuity: RtauLocal -> 1.\n');
fprintf(fid,['expected local slope ratio is muG/muL=(rhoG*nuG)/(rhoL*nuL), ', ...
    'evaluated in each fit band.\n']);
fprintf(fid,['band sensitivity should be weak once the fit starts outside the ', ...
    'mixed 10-90%% composition layer.\n']);
fprintf(fid,'wall velocities are reported only as forcing metadata, not as an acceptance criterion.\n');

clear cleanup

out = struct();
out.cfg = cfg;
out.runRoot = runRoot;
out.recDir = recDir;
out.primary = ePrimary;
out.profile = pPrimary;
out.fitBands = Tbands;
out.rolling = Troll;
out.outputDir = outDir;
out.summaryFile = summaryFile;

save(fullfile(outDir,'interface_0493x23g.mat'),'out');

fprintf('\n[0493x23g-analysis] PRIMARY (%g,%g]\n',primaryStartStep,primaryEndStep);
local_console_estimate(ePrimary,cfg);
fprintf('[0493x23g-analysis] summary=%s\n',summaryFile);

end

% =========================================================================
% Window estimate: align each frame on its own YL=0.5 crossing, then average
% conservative numerators/denominators before any velocity fit.
% =========================================================================
function [e,p,Tbands] = local_window_estimate(data,startStep,endStep,cfg,wantProfile)

idx = find(data.steps > startStep & data.steps <= endStep);
nFrames = numel(idx);
if nFrames < 2
    error('Window (%g,%g] has only %d frame(s).',startStep,endStep,nFrames);
elseif nFrames < 5
    warning('0493x23g:LowFrameCount', ...
        'Window (%g,%g] has only %d frames: smoke diagnostic only.', ...
        startStep,endStep,nFrames);
end

% Common relative coordinate. With matching grids this is the familiar
% -63.5,...,+63.5 cell-center coordinate; it also remains valid if a different
% recorder grid is used.
zCommon = (((1:cfg.recNy).'-0.5)*cfg.recHy - cfg.yGammaNominal)/cfg.h;
sCommon = zCommon*cfg.h;

sumR  = zeros(cfg.recNy,1); nR  = zeros(cfg.recNy,1);
sumR1 = zeros(cfg.recNy,1); nR1 = zeros(cfg.recNy,1);
sumR2 = zeros(cfg.recNy,1); nR2 = zeros(cfg.recNy,1);
sumPx = zeros(cfg.recNy,1); nPx = zeros(cfg.recNy,1);
sumPy = zeros(cfg.recNy,1); nPy = zeros(cfg.recNy,1);

for jj = 1:nFrames
    i = idx(jj);
    zFrame = (data.yRec-data.yGamma(i))/cfg.h;

    [sumR,nR]   = local_accum_interp(sumR,nR,zFrame,data.rhoRows(i,:).',zCommon);
    [sumR1,nR1] = local_accum_interp(sumR1,nR1,zFrame,data.rho1Rows(i,:).',zCommon);
    [sumR2,nR2] = local_accum_interp(sumR2,nR2,zFrame,data.rho2Rows(i,:).',zCommon);
    [sumPx,nPx] = local_accum_interp(sumPx,nPx,zFrame,data.pxRows(i,:).',zCommon);
    [sumPy,nPy] = local_accum_interp(sumPy,nPy,zFrame,data.pyRows(i,:).',zCommon);
end

% For velocity use summed conservative momentum over summed mass. For density,
% divide the accumulated row mass by the number of contributing frames and by
% the horizontal recorder-bin count.
rho  = sumR ./max(nR,1)  / cfg.recNx;
rhoL = sumR1./max(nR1,1) / cfg.recNx;
rhoG = sumR2./max(nR2,1) / cfg.recNx;
ux = sumPx./sumR;
uy = sumPy./sumR;

rho(sumR<=0) = NaN;
rhoL(nR1<=0) = NaN;
rhoG(nR2<=0) = NaN;
ux(sumR<=0) = NaN;
uy(sumR<=0) = NaN;

phaseDen = rhoL+rhoG;
YL = rhoL./phaseDen;
YL(phaseDen<=0) = NaN;

gradUx = local_finite_gradient(sCommon,ux);

% Interface geometry in the raw frames and in the aligned mean profile.
yGammaVals = data.yGamma(idx);
widthVals = data.width1090(idx);
e = local_empty_estimate();
e.startStep = startStep;
e.endStep = endStep;
e.nFrames = nFrames;
e.yGammaMean = mean(yGammaVals,'omitnan');
e.yGammaStd = std(yGammaVals,0,'omitnan');
e.yGammaMeanOverH = e.yGammaMean/cfg.h;
e.yGammaStdOverH = e.yGammaStd/cfg.h;
e.interfaceWidth1090 = mean(widthVals,'omitnan');
e.interfaceWidth1090Std = std(widthVals,0,'omitnan');
e.interfaceWidth1090OverH = e.interfaceWidth1090/cfg.h;
e.compositionClosureRelMean = mean(data.compositionClosureRel(idx),'omitnan');

% Mean-profile 10/50/90 positions should be close to z=0 after alignment.
e.z50MeanProfile = local_crossing_near(zCommon,YL,0.5,0.0);
z90 = local_crossing_near(zCommon,YL,0.9,e.z50MeanProfile);
z10 = local_crossing_near(zCommon,YL,0.1,e.z50MeanProfile);
if isfinite(z90) && isfinite(z10)
    e.meanProfileWidth1090OverH = abs(z10-z90);
else
    e.meanProfileWidth1090OverH = NaN;
end

p = struct();
p.zOverH = zCommon;
p.s = sCommon;
p.rho = rho;
p.rhoL = rhoL;
p.rhoG = rhoG;
p.YL = YL;
p.ux = ux;
p.uy = uy;
p.gradUx = gradUx;

% Sensitivity table over one-sided local bands.
bands = repmat(local_empty_band(),size(cfg.fitBandsH,1),1);
for k = 1:size(cfg.fitBandsH,1)
    bands(k) = local_fit_band(p,cfg.fitBandsH(k,1),cfg.fitBandsH(k,2),cfg);
end
Tbands = struct2table(bands);

% Default primary band.
b = local_fit_band(p,cfg.defaultBandH(1),cfg.defaultBandH(2),cfg);
e.dMinH = b.dMinH;
e.dMaxH = b.dMaxH;
e.nL = b.nL;
e.nG = b.nG;
e.aL = b.aL;
e.aG = b.aG;
e.bL = b.bL;
e.bG = b.bG;
e.R2L = b.R2L;
e.R2G = b.R2G;
e.slopeRatio = b.slopeRatio;
e.rhoL = b.rhoL;
e.rhoG = b.rhoG;
e.rhoRatio = b.rhoRatio;
e.muGOverMuL = b.muGOverMuL;
e.muRatioViscStd = b.muRatioViscStd;
e.RtauLocal = b.RtauLocal;
e.interfaceSlip = b.interfaceSlip;
e.interfaceSlipOverDeltaU = b.interfaceSlipOverDeltaU;
e.uGammaL = b.uGammaL;
e.uGammaG = b.uGammaG;
e.fitRmsOverDeltaU = b.fitRmsOverDeltaU;

if ~wantProfile
    p = struct();
    Tbands = table();
end
end

% =========================================================================
% Fit one local band on each side of the aligned interface.
% =========================================================================
function b = local_fit_band(p,dMinH,dMaxH,cfg)

b = local_empty_band();
b.dMinH = dMinH;
b.dMaxH = dMaxH;

if ~(dMinH >= 0 && dMaxH > dMinH)
    return;
end

z = p.zOverH;
maskL = z >= -dMaxH & z <= -dMinH & ...
        p.YL >= cfg.pureThreshold & isfinite(p.ux);
maskG = z >=  dMinH & z <=  dMaxH & ...
        p.YL <= (1-cfg.pureThreshold) & isfinite(p.ux);

b.nL = nnz(maskL);
b.nG = nnz(maskG);
if b.nL < cfg.minFitPoints || b.nG < cfg.minFitPoints
    return;
end

[b.aL,b.bL,b.R2L] = local_line_fit(p.s(maskL),p.ux(maskL));
[b.aG,b.bG,b.R2G] = local_line_fit(p.s(maskG),p.ux(maskG));

b.uGammaL = b.bL;
b.uGammaG = b.bG;
b.interfaceSlip = b.uGammaG-b.uGammaL;
b.interfaceSlipOverDeltaU = b.interfaceSlip/max(abs(cfg.deltaUw),eps);

% Local phase densities are evaluated in exactly the same bands as gradients.
b.rhoL = mean(p.rhoL(maskL),'omitnan');
b.rhoG = mean(p.rhoG(maskG),'omitnan');
b.rhoRatio = b.rhoG/b.rhoL;
b.muGOverMuL = (b.rhoG*cfg.nuG)/(b.rhoL*cfg.nuL);

% Propagate ONLY the independent viscosity-reference uncertainties here.
% Density sampling uncertainty is not folded into this documentary envelope.
if isfinite(cfg.nuRatioStdIndependent)
    b.muRatioViscStd = b.muGOverMuL * ...
        (cfg.nuRatioStdIndependent/cfg.nuRatio);
else
    b.muRatioViscStd = NaN;
end

b.slopeRatio = b.aL/b.aG;
b.RtauLocal = b.slopeRatio/b.muGOverMuL;

uFitL = b.aL*p.s+b.bL;
uFitG = b.aG*p.s+b.bG;
res = [p.ux(maskL)-uFitL(maskL); p.ux(maskG)-uFitG(maskG)];
b.fitRmsOverDeltaU = sqrt(mean(res.^2,'omitnan'))/max(abs(cfg.deltaUw),eps);
end

function b = local_empty_band()
b = struct( ...
    'dMinH',NaN,'dMaxH',NaN,'nL',0,'nG',0, ...
    'aL',NaN,'aG',NaN,'bL',NaN,'bG',NaN, ...
    'R2L',NaN,'R2G',NaN,'slopeRatio',NaN, ...
    'rhoL',NaN,'rhoG',NaN,'rhoRatio',NaN, ...
    'muGOverMuL',NaN,'muRatioViscStd',NaN,'RtauLocal',NaN, ...
    'uGammaL',NaN,'uGammaG',NaN,'interfaceSlip',NaN, ...
    'interfaceSlipOverDeltaU',NaN,'fitRmsOverDeltaU',NaN);
end

function e = local_empty_estimate()
e = struct( ...
    'startStep',NaN,'endStep',NaN,'nFrames',NaN, ...
    'yGammaMean',NaN,'yGammaStd',NaN,'yGammaMeanOverH',NaN, ...
    'yGammaStdOverH',NaN,'interfaceWidth1090',NaN, ...
    'interfaceWidth1090Std',NaN,'interfaceWidth1090OverH',NaN, ...
    'meanProfileWidth1090OverH',NaN,'z50MeanProfile',NaN, ...
    'compositionClosureRelMean',NaN, ...
    'dMinH',NaN,'dMaxH',NaN,'nL',0,'nG',0, ...
    'aL',NaN,'aG',NaN,'bL',NaN,'bG',NaN, ...
    'R2L',NaN,'R2G',NaN,'slopeRatio',NaN, ...
    'rhoL',NaN,'rhoG',NaN,'rhoRatio',NaN, ...
    'muGOverMuL',NaN,'muRatioViscStd',NaN,'RtauLocal',NaN, ...
    'uGammaL',NaN,'uGammaG',NaN,'interfaceSlip',NaN, ...
    'interfaceSlipOverDeltaU',NaN,'fitRmsOverDeltaU',NaN);
end

% =========================================================================
% Figures
% =========================================================================
function local_plot_profile(p,e,cfg,fileName)

f = figure('Color','w','Position',[80 60 1450 980]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf(['0493x23g interface-centered L/G, window (%g,%g], ', ...
    '\\sigma=%.4g'],e.startStep,e.endStep,cfg.sigma));

% Full velocity profile: walls shown only as forcing metadata.
nexttile;
plot(p.zOverH,p.ux/cfg.deltaUw,'-o','MarkerSize',3); hold on;
xline(0,':','Gamma');
yline(cfg.UwBottom/cfg.deltaUw,':','wall bottom');
yline(cfg.UwTop/cfg.deltaUw,':','wall top');
grid on;
xlabel('(y-y_\Gamma)/h'); ylabel('u_x / \Delta U_w');
title('Full profile (walls are not acceptance criteria)');

% Interface zoom + one-sided default fits.
nexttile;
zoom = abs(p.zOverH) <= cfg.zoomH;
plot(p.zOverH(zoom),p.ux(zoom)/cfg.deltaUw,'o','MarkerSize',4); hold on;
zfitL = linspace(-cfg.defaultBandH(2),0,80).';
zfitG = linspace(0,cfg.defaultBandH(2),80).';
plot(zfitL,(e.aL*(zfitL*cfg.h)+e.bL)/cfg.deltaUw,'-','LineWidth',1.5);
plot(zfitG,(e.aG*(zfitG*cfg.h)+e.bG)/cfg.deltaUw,'-','LineWidth',1.5);
xline(0,':','Gamma');
grid on;
xlabel('(y-y_\Gamma)/h'); ylabel('u_x / \Delta U_w');
title(sprintf(['local [%g,%g]h: a_L/a_G=%.4g, target=%.4g, ', ...
    'R_\\tau=%.4g'],e.dMinH,e.dMaxH,e.slopeRatio,e.muGOverMuL,e.RtauLocal));
legend('mean profile','liquid fit','gas fit','Location','best');

% Composition.
nexttile;
plot(p.zOverH,p.YL,'-','LineWidth',1.5); hold on;
plot(p.zOverH,1-p.YL,'--','LineWidth',1.2);
xline(0,':','Gamma');
yline(0.1,':'); yline(0.5,':'); yline(0.9,':');
xlim([-cfg.zoomH cfg.zoomH]); ylim([-0.03 1.03]);
grid on;
xlabel('(y-y_\Gamma)/h'); ylabel('mass fraction');
legend('Y_L','Y_G','Location','best');
title(sprintf('composition width 10-90 = %.3g h',e.interfaceWidth1090OverH));

% Local velocity derivative.
nexttile;
plot(p.zOverH,p.gradUx,'-','LineWidth',1.2); hold on;
yline(e.aL,'--','a_L fit');
yline(e.aG,'-.','a_G fit');
xline(0,':','Gamma');
xlim([-cfg.zoomH cfg.zoomH]);
grid on;
xlabel('(y-y_\Gamma)/h'); ylabel('d u_x / d y');
title(sprintf('slip_\Gamma/\Delta U = %+.3g',e.interfaceSlipOverDeltaU));

local_save_figure(f,fileName);
end

function local_plot_band_sensitivity(T,cfg,fileName)
if isempty(T), return; end

n = height(T);
x = 1:n;
labels = arrayfun(@(i) sprintf('%g-%g',T.dMinH(i),T.dMaxH(i)), ...
    (1:n).','UniformOutput',false);

f = figure('Color','w','Position',[80 60 1450 900]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl,'0493x23g local interface fit-band sensitivity');

nexttile;
plot(x,T.slopeRatio,'-o','LineWidth',1.2); hold on;
plot(x,T.muGOverMuL,'--s','LineWidth',1.2);
grid on; xticks(x); xticklabels(labels); xtickangle(35);
ylabel('ratio'); xlabel('[d_{min},d_{max}]/h');
legend('a_L/a_G','local \mu_G/\mu_L','Location','best');
title('Gradient ratio vs local constitutive target');

nexttile;
plot(x,T.RtauLocal,'-o','LineWidth',1.2); hold on;
yline(1,':');
grid on; xticks(x); xticklabels(labels); xtickangle(35);
ylabel('R_{\tau,local}'); xlabel('[d_{min},d_{max}]/h');
title('(\rho_L\nu_L a_L)/(\rho_G\nu_G a_G)');

nexttile;
plot(x,T.interfaceSlipOverDeltaU,'-o','LineWidth',1.2); hold on;
yline(0,':');
grid on; xticks(x); xticklabels(labels); xtickangle(35);
ylabel('\Delta u_\Gamma / \Delta U_w'); xlabel('[d_{min},d_{max}]/h');
title('Extrapolated tangential velocity continuity');

nexttile;
plot(x,T.R2L,'-o','LineWidth',1.1); hold on;
plot(x,T.R2G,'-s','LineWidth',1.1);
yline(0.99,':');
grid on; xticks(x); xticklabels(labels); xtickangle(35);
ylabel('R^2'); xlabel('[d_{min},d_{max}]/h');
legend('liquid','gas','Location','best');
title(sprintf('one-sided linearity, pure threshold=%.2f',cfg.pureThreshold));

local_save_figure(f,fileName);
end

function local_plot_rolling(T,cfg,windowSteps,fileName)
if isempty(T), return; end

f = figure('Color','w','Position',[80 60 1450 900]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('0493x23g rolling interface diagnostics, window=%g steps',windowSteps));

nexttile;
plot(T.endStep,T.yGammaMeanOverH,'-o','MarkerSize',3); hold on;
yline(cfg.yGammaNominal/cfg.h,':');
grid on; xlabel('step'); ylabel('y_\Gamma/h');
title('Interface position');

nexttile;
plot(T.endStep,T.slopeRatio,'-o','MarkerSize',3); hold on;
plot(T.endStep,T.muGOverMuL,'--','LineWidth',1.2);
grid on; xlabel('step'); ylabel('ratio');
legend('a_L/a_G','local \mu_G/\mu_L','Location','best');
title('Local slope-ratio stationarity');

nexttile;
plot(T.endStep,T.RtauLocal,'-o','MarkerSize',3); hold on;
yline(1,':');
grid on; xlabel('step'); ylabel('R_{\tau,local}');
title('Local stress-continuity diagnostic');

nexttile;
plot(T.endStep,T.interfaceSlipOverDeltaU,'-o','MarkerSize',3); hold on;
yline(0,':');
grid on; xlabel('step'); ylabel('\Delta u_\Gamma/\Delta U_w');
title('Local tangential velocity continuity');

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
function local_print_estimate(fid,e,cfg)
fprintf(fid,'frames = %d\n',e.nFrames);
fprintf(fid,'interface yGamma/h = %.12g +/- %.12g\n', ...
    e.yGammaMeanOverH,e.yGammaStdOverH);
fprintf(fid,'interface width 10-90 = %.12g h\n',e.interfaceWidth1090OverH);
fprintf(fid,'aligned mean-profile width 10-90 = %.12g h\n',e.meanProfileWidth1090OverH);
fprintf(fid,'rho-rho1-rho2 relative closure mean = %.12g\n',e.compositionClosureRelMean);
fprintf(fid,'fit band = [%.6g, %.6g] h ; nL=%d nG=%d\n', ...
    e.dMinH,e.dMaxH,e.nL,e.nG);
fprintf(fid,'aL = %.12g ; R2L = %.10g\n',e.aL,e.R2L);
fprintf(fid,'aG = %.12g ; R2G = %.10g\n',e.aG,e.R2G);
fprintf(fid,'aL/aG = %.12g\n',e.slopeRatio);
fprintf(fid,'rhoL(local) = %.12g ; rhoG(local) = %.12g ; rhoG/rhoL = %.12g\n', ...
    e.rhoL,e.rhoG,e.rhoRatio);
fprintf(fid,'muG/muL(local) = %.12g\n',e.muGOverMuL);
fprintf(fid,'viscosity-reference-only std on mu ratio = %.12g\n',e.muRatioViscStd);
fprintf(fid,'RtauLocal = %.12g\n',e.RtauLocal);
fprintf(fid,'uGammaL = %.12g ; uGammaG = %.12g\n',e.uGammaL,e.uGammaG);
fprintf(fid,'interface slip/DeltaUw = %+.12g\n',e.interfaceSlipOverDeltaU);
fprintf(fid,'local fit RMS/DeltaUw = %.12g\n',e.fitRmsOverDeltaU);
fprintf(fid,'documentary nominal nuG/nuL = %.12g +/- %.12g (independent propagation)\n', ...
    cfg.nuRatio,cfg.nuRatioStdIndependent);
end

function local_console_estimate(e,cfg)
fprintf('  Gamma/h=%.6f +/- %.4g ; width10-90=%.4g h ; sigma=%.6g\n', ...
    e.yGammaMeanOverH,e.yGammaStdOverH,e.interfaceWidth1090OverH,cfg.sigma);
fprintf('  local band=[%.1f,%.1f]h  nL=%d nG=%d\n', ...
    e.dMinH,e.dMaxH,e.nL,e.nG);
fprintf('  aL=%.8g R2L=%.5f ; aG=%.8g R2G=%.5f\n', ...
    e.aL,e.R2L,e.aG,e.R2G);
fprintf('  aL/aG=%.8g ; local muG/muL=%.8g ; RtauLocal=%.8g\n', ...
    e.slopeRatio,e.muGOverMuL,e.RtauLocal);
fprintf('  interface slip/DeltaUw=%+.5g ; rhoG/rhoL=%.8g\n', ...
    e.interfaceSlipOverDeltaU,e.rhoRatio);
end

% =========================================================================
% Utilities
% =========================================================================
function [sumOut,nOut] = local_accum_interp(sumIn,nIn,x,y,xq)
yq = interp1(x,y,xq,'linear',NaN);
ok = isfinite(yq);
sumOut = sumIn;
nOut = nIn;
sumOut(ok) = sumOut(ok)+yq(ok);
nOut(ok) = nOut(ok)+1;
end

function yc = local_crossing_near(y,f,level,yNear)
y = y(:); f = f(:);
ok = isfinite(y) & isfinite(f);
y = y(ok); f = f(ok);
yc = NaN;
if numel(y) < 2, return; end

g = f-level;
ids = find(g(1:end-1).*g(2:end) <= 0 & ...
           ~(g(1:end-1)==0 & g(2:end)==0));
if isempty(ids)
    [~,ii] = min(abs(g));
    if abs(g(ii)) < 0.05
        yc = y(ii);
    end
    return;
end

cand = nan(numel(ids),1);
for k = 1:numel(ids)
    i = ids(k);
    y0=y(i); y1=y(i+1); f0=f(i); f1=f(i+1);
    if f1 == f0
        cand(k)=0.5*(y0+y1);
    else
        cand(k)=y0+(level-f0)*(y1-y0)/(f1-f0);
    end
end
[~,kbest] = min(abs(cand-yNear));
yc = cand(kbest);
end

function g = local_finite_gradient(x,y)
x=x(:); y=y(:);
g=nan(size(y));
ok=isfinite(x)&isfinite(y);
ids=find(ok);
if numel(ids)<2, return; end
% Work only on contiguous valid sections.
breaks=[0; find(diff(ids)>1); numel(ids)];
for b=1:numel(breaks)-1
    seg=ids(breaks(b)+1:breaks(b+1));
    if numel(seg)>=2
        g(seg)=gradient(y(seg),x(seg));
    end
end
end

function [a,b,R2] = local_line_fit(x,y)
x=x(:); y=y(:);
ok=isfinite(x)&isfinite(y);
x=x(ok); y=y(ok);
if numel(x)<2
    a=NaN; b=NaN; R2=NaN; return;
end
X=[x,ones(size(x))];
beta=X\y;
a=beta(1); b=beta(2);
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
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
v=fread(fid,nx*ny,'single=>double');
if numel(v)~=nx*ny
    error('%s : got %d values, expected %d.',fileName,numel(v),nx*ny);
end
% Recorder storage is row-major: x varies fastest.
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

function val = local_kv_str(txt,keys,defaultVal)
val=defaultVal;
for i=1:numel(keys)
    key=regexptranslate('escape',keys{i});
    tok=regexp(txt,['(?m)^\s*' key '\s*=\s*([^\r\n#]+)'], ...
        'tokens','once');
    if ~isempty(tok)
        s=strtrim(tok{1});
        s=regexprep(s,'^["'']|["'']$','');
        if ~isempty(s)
            val=s;
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

function [steps,names] = local_inventory_frames(recDir,fields)
rhoFiles = dir(fullfile(recDir,'step_*_field_rho.f32'));
steps=[];
for k=1:numel(fields)
    names.(fields{k})={};
end
for i=1:numel(rhoFiles)
    tok=regexp(rhoFiles(i).name,'^step_(\d+)_field_rho\.f32$','tokens','once');
    if isempty(tok), continue; end
    s=str2double(tok{1});
    this=struct();
    complete=true;
    for k=1:numel(fields)
        fld=fields{k};
        fn=sprintf('step_%010d_field_%s.f32',s,fld);
        % Preserve wider step formatting if recorder used more than 10 digits.
        if strcmp(fld,'rho')
            fn=rhoFiles(i).name;
        else
            fn=regexprep(rhoFiles(i).name,'_field_rho\.f32$', ...
                ['_field_' fld '.f32']);
        end
        if ~isfile(fullfile(recDir,fn))
            complete=false;
            break;
        end
        this.(fld)=fn;
    end
    if complete
        steps(end+1,1)=s; %#ok<AGROW>
        for k=1:numel(fields)
            fld=fields{k};
            names.(fld){end+1,1}=this.(fld); %#ok<AGROW>
        end
    end
end
[steps,ord]=sort(steps);
for k=1:numel(fields)
    fld=fields{k};
    names.(fld)=names.(fld)(ord);
end
end

function [recDir,manifestFile] = local_find_recording_dir(runRoot)
base=fullfile(runRoot,'output','recordings');
if ~isfolder(base)
    error('Recording base directory missing: %s',base);
end

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

mf=fullfile(base,'manifest.kv');
rr=dir(fullfile(base,'step_*_field_rho.f32'));
if isfile(mf) && ~isempty(rr)
    recDir=base;
    manifestFile=mf;
    return;
end
error('No recorder session with manifest + rho frames under %s',base);
end

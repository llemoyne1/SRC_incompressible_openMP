function out = analyze_0493x23e_halves_livevis(runRoot)
%ANALYZE_0493X23E_HALVES_LIVEVIS
% Analyse SEPAREE des moities z>0 et z<0 du Couette biphasique 0493x23e.
%
% But :
%   verifier si l'evolution de aL/aG observee jusqu'a 18000 steps est
%   coherente sur les DEUX interfaces liquide-gaz, ou si le repliement
%   antisymetrique masque une asymetrie haut/bas.
%
% IMPORTANT :
%   - cet analyseur ne remplace PAS analyze_0493x23e_stability_livevis.m ;
%   - il n'effectue aucun repliement pour les grandeurs "pos" et "neg" ;
%   - la moitie basse est ajustee avec sa vraie coordonnee signee z<0.
%     Ainsi, pour un Couette antisymetrique ideal, les pentes hautes et
%     basses ont le MEME signe :
%           aL_pos ~= aL_neg,  aG_pos ~= aG_neg.
%
% Metrologie conservative dans chaque moitie :
%   P_x(y) = sum_x rho(x,y) u_x(x,y)
%   M(y)   = sum_x rho(x,y)
%   u_x(y) = P_x(y)/M(y)
%
% Geometrie nominale :
%   G | L | G
%   z in [-H,H], H=0.25
%   interfaces z = +/- zGamma, zGamma=32 h = 0.125
%   parois z = +/- H, avec u_wall = +/- Uw, Uw=0.075.
%
% Fits fixes, identiques en distance a l'interface/paroi :
%   liquide : |z| <= zGamma - 4 h
%   gaz     : |z| >= zGamma + 4 h et |z| <= H - 4 h
%
% Analyse temporelle :
%   - tout l'historique disponible 0 -> 18000 ;
%   - fenetres glissantes de 2000 steps, stride 200 ;
%   - micro-blocs non recouvrants de 400 steps ;
%   - fenetres terminales de 1000 a 12000 steps ;
%   - comparaison explicite haut/bas ;
%   - controle de coherence : le repliement reconstruit sur (6000,18000]
%     doit reproduire l'analyseur article precedent.
%
% Usage depuis le dossier matlab :
%   out = analyze_0493x23e_halves_livevis;
%
% ou :
%   out = analyze_0493x23e_halves_livevis( ...
%       '../runs/0493x23e_article_couette_livevis_Uw0075_seed593170');
%
% Sorties :
%   <runRoot>/analysis_0493x23e_halves/
%       rolling_halves_2000_0493x23e.csv
%       microblocks_halves_0400_0493x23e.csv
%       terminal_windows_halves_0493x23e.csv
%       halves_summary_0493x23e.txt
%       halves_rolling_0493x23e.png
%       halves_asymmetry_0493x23e.png
%       halves_late_profiles_0493x23e.png
%       halves_terminal_windows_0493x23e.png
%       halves_0493x23e.mat

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs', ...
        '0493x23e_article_couette_livevis_Uw0075_seed593170');
end
runRoot = char(runRoot);

%% ========================================================================
% Configuration
% =========================================================================
cfg = struct();

cfg.analysisStartStep = 0;
cfg.analysisEndStep   = 18000;

cfg.rollingWindowSteps = 2000;
cfg.rollingStrideSteps = 200;
cfg.microBlockSteps    = 400;
cfg.lateStartStep      = 6000;
cfg.tailTrendSteps     = 6000;
cfg.terminalWindows    = [1000 2000 4000 6000 8000 12000];

cfg.Lx = 0.5;
cfg.Ly = 0.5;
cfg.Uw = 0.075;

cfg.interfaceCells = 32;
cfg.excludeInterfaceCells = 4;
cfg.excludeWallCells = 4;

% Viscosites cinematiques TG path-aware deja utilisees dans l'analyse x23e.
cfg.nuL = 6.15880e-4;
cfg.nuG = 7.29393e-4;

%% ========================================================================
% Recording / manifest
% =========================================================================
recDir = fullfile(runRoot,'output','recordings','couette_x23e');
if ~isfolder(recDir)
    recDir = local_find_recording_dir(runRoot);
end

manifestFile = fullfile(recDir,'manifest.kv');
if ~isfile(manifestFile)
    error('Manifest introuvable : %s',manifestFile);
end
manifestText = fileread(manifestFile);

nx = local_kv_num(manifestText, {'liveGridNx','Nx','solverNx'}, 128);
ny = local_kv_num(manifestText, {'liveGridNy','Ny','solverNy'}, 128);
solverNx = local_kv_num(manifestText, {'solverNx'}, nx);
solverNy = local_kv_num(manifestText, {'solverNy'}, ny);
cfg.Lx = local_kv_num(manifestText, {'Lx','domainLx'}, cfg.Lx);
cfg.Ly = local_kv_num(manifestText, {'Ly','domainLy'}, cfg.Ly);
cfg.recordEvery = local_kv_num(manifestText, {'recordEvery'}, NaN);

if mod(ny,2) ~= 0
    error('Ny=%d doit etre pair.',ny);
end

cfg.nx = nx;
cfg.ny = ny;
cfg.solverNx = solverNx;
cfg.solverNy = solverNy;
cfg.h = cfg.Ly/ny;
cfg.H = cfg.Ly/2;
cfg.zGamma = cfg.interfaceCells*cfg.h;
cfg.rhoScale = (solverNx/nx)*(solverNy/ny);

%% ========================================================================
% Inventaire des frames completes
% =========================================================================
rhoFiles = dir(fullfile(recDir,'step_*_field_rho.f32'));
if isempty(rhoFiles)
    error('Aucune frame rho dans %s',recDir);
end

steps = zeros(numel(rhoFiles),1);
rhoNames = cell(numel(rhoFiles),1);
uxNames  = cell(numel(rhoFiles),1);
uyNames  = cell(numel(rhoFiles),1);
keep = false(numel(rhoFiles),1);

for i = 1:numel(rhoFiles)
    tok = regexp(rhoFiles(i).name,'^step_(\d+)_field_rho\.f32$', ...
        'tokens','once');
    if isempty(tok), continue; end

    s = str2double(tok{1});
    uxName = regexprep(rhoFiles(i).name,'_field_rho\.f32$','_field_ux.f32');
    uyName = regexprep(rhoFiles(i).name,'_field_rho\.f32$','_field_uy.f32');

    if isfile(fullfile(recDir,uxName)) && isfile(fullfile(recDir,uyName))
        steps(i) = s;
        rhoNames{i} = rhoFiles(i).name;
        uxNames{i} = uxName;
        uyNames{i} = uyName;
        keep(i) = true;
    end
end

steps = steps(keep);
rhoNames = rhoNames(keep);
uxNames = uxNames(keep);
uyNames = uyNames(keep);

[steps,ord] = sort(steps);
rhoNames = rhoNames(ord);
uxNames = uxNames(ord);
uyNames = uyNames(ord);

use = steps > cfg.analysisStartStep & steps <= cfg.analysisEndStep;
steps = steps(use);
rhoNames = rhoNames(use);
uxNames = uxNames(use);
uyNames = uyNames(use);

if isempty(steps)
    error('Aucune frame dans ]%d,%d].', ...
        cfg.analysisStartStep,cfg.analysisEndStep);
end

lastRecordedStep = steps(end);

fprintf('[0493x23e-halves] recDir=%s\n',recDir);
fprintf('[0493x23e-halves] grid=%dx%d h=%.10g frames=%d recorded=%d..%d nominalEnd=%d\n', ...
    nx,ny,cfg.h,numel(steps),steps(1),steps(end),cfg.analysisEndStep);

%% ========================================================================
% Lecture unique : sommes horizontales conservatives par ligne y
% =========================================================================
nF = numel(steps);
rhoRows = zeros(nF,ny);
pxRows  = zeros(nF,ny);
pyRows  = zeros(nF,ny);

for i = 1:nF
    rho = local_read_f32(fullfile(recDir,rhoNames{i}),nx,ny)*cfg.rhoScale;
    ux  = local_read_f32(fullfile(recDir,uxNames{i}), nx,ny);
    uy  = local_read_f32(fullfile(recDir,uyNames{i}), nx,ny);

    if any(~isfinite(rho(:))) || any(~isfinite(ux(:))) || any(~isfinite(uy(:)))
        error('NaN/Inf dans la frame step=%d.',steps(i));
    end

    rhoRows(i,:) = sum(rho,2).';
    pxRows(i,:)  = sum(rho.*ux,2).';
    pyRows(i,:)  = sum(rho.*uy,2).';

    if mod(i,100)==0 || i==nF
        fprintf('[0493x23e-halves] read %d/%d frames (step=%d)\n', ...
            i,nF,steps(i));
    end
end

data = struct();
data.steps = steps;
data.rhoRows = rhoRows;
data.pxRows = pxRows;
data.pyRows = pyRows;

%% ========================================================================
% Auto-controle du repliement precedent sur (6000,18000]
% =========================================================================
folded = local_estimate_folded(data,cfg.lateStartStep,cfg.analysisEndStep,cfg);

ref = struct();
ref.aL = 0.1118677907;
ref.aG = 0.5076760565;
ref.ratio = 0.2203527018;

selfErr = [ ...
    abs(folded.aL-ref.aL)/abs(ref.aL), ...
    abs(folded.aG-ref.aG)/abs(ref.aG), ...
    abs(folded.ratio-ref.ratio)/abs(ref.ratio)];

metrologySelfCheck = max(selfErr) <= 5e-3;

fprintf('[0493x23e-halves] folded self-check (6000,18000]: ');
fprintf('aL=%.9g aG=%.9g ratio=%.9g maxRelErr=%.3g -> %s\n', ...
    folded.aL,folded.aG,folded.ratio,max(selfErr), ...
    local_tf(metrologySelfCheck));

if ~metrologySelfCheck
    warning(['Le repliement de controle ne reproduit pas l''analyse x23e ', ...
        'precedente a 0.5%%. Ne pas interpreter les moities avant verification.']);
end

%% ========================================================================
% Estimations globales utiles
% =========================================================================
full = local_estimate_halves(data,0,cfg.analysisEndStep,cfg);
late = local_estimate_halves(data,cfg.lateStartStep,cfg.analysisEndStep,cfg);
previous2000 = local_estimate_halves(data,14000,16000,cfg);
last2000     = local_estimate_halves(data,16000,18000,cfg);

%% ========================================================================
% Serie glissante 2000 steps, de 0 -> 18000
% =========================================================================
rollEnd = cfg.rollingWindowSteps:cfg.rollingStrideSteps:cfg.analysisEndStep;
rolling = repmat(local_empty_halves(),numel(rollEnd),1);

for k = 1:numel(rollEnd)
    rolling(k) = local_estimate_halves(data, ...
        rollEnd(k)-cfg.rollingWindowSteps,rollEnd(k),cfg);
end
Troll = struct2table(local_strip_profiles(rolling));

%% ========================================================================
% Micro-blocs non recouvrants de 400 steps sur tout 0 -> 18000
% =========================================================================
blockStarts = 0:cfg.microBlockSteps:(cfg.analysisEndStep-cfg.microBlockSteps);
micro = repmat(local_empty_halves(),numel(blockStarts),1);

for k = 1:numel(blockStarts)
    micro(k) = local_estimate_halves(data,blockStarts(k), ...
        blockStarts(k)+cfg.microBlockSteps,cfg);
end
Tmicro = struct2table(local_strip_profiles(micro));
Tmicro.midStep = 0.5*(Tmicro.startStep+Tmicro.endStep);

%% ========================================================================
% Fenetres terminales finissant toutes a 18000
% =========================================================================
wins = cfg.terminalWindows(:);
term = repmat(local_empty_halves(),numel(wins),1);

for k = 1:numel(wins)
    term(k) = local_estimate_halves(data, ...
        cfg.analysisEndStep-wins(k),cfg.analysisEndStep,cfg);
end
Tterm = struct2table(local_strip_profiles(term));
Tterm.windowSteps = wins;

%% ========================================================================
% Tendances sur les 6000 derniers steps, separement haut/bas
% =========================================================================
tail = Tmicro.midStep > (cfg.analysisEndStep-cfg.tailTrendSteps);

trendNames = { ...
    'aL_pos','aL_neg','aG_pos','aG_neg', ...
    'ratio_pos','ratio_neg','Rtau_pos','Rtau_neg', ...
    'rhoRatio_pos','rhoRatio_neg', ...
    'asym_aL','asym_aG','asym_ratio','asym_Rtau'};

trendRows = repmat(struct('name','','mean',NaN,'SD',NaN,'CV',NaN, ...
    'slopePerStep',NaN,'driftOver6000Frac',NaN,'lag1',NaN,'Neff',NaN), ...
    numel(trendNames),1);

for k = 1:numel(trendNames)
    nm = trendNames{k};
    y = Tmicro.(nm)(tail);
    x = Tmicro.midStep(tail);

    [sl,se] = local_trend(x,y); %#ok<ASGLU>
    mu = mean(y,'omitnan');
    sd = std(y,0,'omitnan');

    trendRows(k).name = nm;
    trendRows(k).mean = mu;
    trendRows(k).SD = sd;
    trendRows(k).CV = sd/max(abs(mu),eps);
    trendRows(k).slopePerStep = sl;
    trendRows(k).driftOver6000Frac = ...
        abs(sl)*cfg.tailTrendSteps/max(abs(mu),eps);

    [rho1,~,neff] = local_corr_diag(y);
    trendRows(k).lag1 = rho1;
    trendRows(k).Neff = neff;
end
Ttrend = struct2table(trendRows);

%% ========================================================================
% Sorties
% =========================================================================
outDir = fullfile(runRoot,'analysis_0493x23e_halves');
if ~isfolder(outDir), mkdir(outDir); end

writetable(Troll, fullfile(outDir,'rolling_halves_2000_0493x23e.csv'));
writetable(Tmicro,fullfile(outDir,'microblocks_halves_0400_0493x23e.csv'));
writetable(Tterm, fullfile(outDir,'terminal_windows_halves_0493x23e.csv'));
writetable(Ttrend,fullfile(outDir,'tail_trends_halves_0493x23e.csv'));

local_plot_rolling(Troll,cfg, ...
    fullfile(outDir,'halves_rolling_0493x23e.png'));
local_plot_asymmetry(Troll,cfg, ...
    fullfile(outDir,'halves_asymmetry_0493x23e.png'));
local_plot_profiles(late,cfg, ...
    fullfile(outDir,'halves_late_profiles_0493x23e.png'));
local_plot_terminal(Tterm,cfg, ...
    fullfile(outDir,'halves_terminal_windows_0493x23e.png'));

summaryFile = fullfile(outDir,'halves_summary_0493x23e.txt');
fid = fopen(summaryFile,'w');
if fid < 0, error('Impossible d''ecrire %s',summaryFile); end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid,'0493x23e Couette LiveVis separate-half analysis\n');
fprintf(fid,'runRoot = %s\n',runRoot);
fprintf(fid,'recording = %s\n',recDir);
fprintf(fid,'frames available = %d, recorded step range = [%d,%d]\n', ...
    nF,steps(1),lastRecordedStep);
fprintf(fid,'nominal analysis range = (0,%d]\n',cfg.analysisEndStep);
fprintf(fid,'window convention = (startStep,endStep]\n');
fprintf(fid,'grid = %dx%d, Lx=%.12g, Ly=%.12g, h=%.12g\n', ...
    nx,ny,cfg.Lx,cfg.Ly,cfg.h);
fprintf(fid,'zGamma/h = %.6g, H/h = %.6g\n', ...
    cfg.zGamma/cfg.h,cfg.H/cfg.h);
fprintf(fid,'wall velocities = bottom %.12g, top %.12g\n',-cfg.Uw,+cfg.Uw);
fprintf(fid,'nuL = %.12g, nuG = %.12g, nuG/nuL = %.12g\n\n', ...
    cfg.nuL,cfg.nuG,cfg.nuG/cfg.nuL);

fprintf(fid,'FOLDED METROLOGY SELF-CHECK ON (6000,18000]\n');
fprintf(fid,'expected aL = %.12g, folded = %.12g\n',ref.aL,folded.aL);
fprintf(fid,'expected aG = %.12g, folded = %.12g\n',ref.aG,folded.aG);
fprintf(fid,'expected ratio = %.12g, folded = %.12g\n',ref.ratio,folded.ratio);
fprintf(fid,'max relative error = %.12g\n',max(selfErr));
fprintf(fid,'metrologySelfCheck = %d\n\n',metrologySelfCheck);

fprintf(fid,'FULL HISTORY (0,18000]\n');
local_print_halves(fid,full);

fprintf(fid,'\nLATE HISTORY (6000,18000]\n');
local_print_halves(fid,late);

fprintf(fid,'\nPREVIOUS 2000 (14000,16000]\n');
local_print_halves(fid,previous2000);

fprintf(fid,'\nLAST 2000 (16000,18000]\n');
local_print_halves(fid,last2000);

fprintf(fid,'\nTAIL TRENDS OVER LAST %d STEPS\n',cfg.tailTrendSteps);
fprintf(fid,'name                 mean          SD            CV        drift6000       lag1        Neff\n');
for k = 1:height(Ttrend)
    fprintf(fid,'%-16s %12.6g  %12.6g  %12.6g  %12.6g  %10.5g  %10.5g\n', ...
        Ttrend.name{k},Ttrend.mean(k),Ttrend.SD(k),Ttrend.CV(k), ...
        Ttrend.driftOver6000Frac(k),Ttrend.lag1(k),Ttrend.Neff(k));
end

fprintf(fid,'\nASYMMETRY DEFINITION\n');
fprintf(fid,['asym_X = 2*(X_pos-X_neg)/(abs(X_pos)+abs(X_neg)); ', ...
    '0 means perfect top/bottom agreement.\n']);
fprintf(fid,['For interface and wall slips, bottom values are orientation-corrected ', ...
    'so that a symmetric Couette gives the same sign as the top half.\n']);

clear cleanup

out = struct();
out.cfg = cfg;
out.runRoot = runRoot;
out.recDir = recDir;
out.foldedSelfCheck = folded;
out.metrologySelfCheck = metrologySelfCheck;
out.full = full;
out.late = late;
out.previous2000 = previous2000;
out.last2000 = last2000;
out.rolling = Troll;
out.microblocks = Tmicro;
out.terminalWindows = Tterm;
out.tailTrends = Ttrend;
out.outputDir = outDir;

save(fullfile(outDir,'halves_0493x23e.mat'),'out');

fprintf('\n[0493x23e-halves] LATE (6000,18000]\n');
local_console_halves(late);
fprintf('\n[0493x23e-halves] LAST 2000 (16000,18000]\n');
local_console_halves(last2000);
fprintf('[0493x23e-halves] summary=%s\n',summaryFile);

end

% =========================================================================
% Estimation SEPAREE des deux moities
% =========================================================================
function e = local_estimate_halves(data,startStep,endStep,cfg)

idx = data.steps > startStep & data.steps <= endStep;
n = nnz(idx);
if n < 2
    error('Fenetre (%d,%d] : seulement %d frames.',startStep,endStep,n);
end

R  = sum(data.rhoRows(idx,:),1).';
Px = sum(data.pxRows(idx,:), 1).';
Py = sum(data.pyRows(idx,:), 1).';

half = cfg.ny/2;

% ordre depuis le centre vers la paroi dans les deux moities
iPos = (half+1):cfg.ny;
iNeg = half:-1:1;

zAbs = ((1:half).'-0.5)*cfg.h;
zPos = +zAbs;
zNeg = -zAbs;

Rpos = R(iPos);
Rneg = R(iNeg);
Pxpos = Px(iPos);
Pxneg = Px(iNeg);
Pypos = Py(iPos);
Pyneg = Py(iNeg);

uPos = Pxpos./Rpos;
uNeg = Pxneg./Rneg;
vPos = Pypos./Rpos;
vNeg = Pyneg./Rneg;

rhoPos = Rpos/(n*cfg.nx);
rhoNeg = Rneg/(n*cfg.nx);

maskL = zAbs <= (cfg.zGamma-cfg.excludeInterfaceCells*cfg.h);
maskG = zAbs >= (cfg.zGamma+cfg.excludeInterfaceCells*cfg.h) & ...
        zAbs <= (cfg.H-cfg.excludeWallCells*cfg.h);

[aLp,bLp,R2Lp] = local_line_fit(zPos(maskL),uPos(maskL));
[aGp,bGp,R2Gp] = local_line_fit(zPos(maskG),uPos(maskG));

[aLn,bLn,R2Ln] = local_line_fit(zNeg(maskL),uNeg(maskL));
[aGn,bGn,R2Gn] = local_line_fit(zNeg(maskG),uNeg(maskG));

rhoLp = mean(rhoPos(maskL));
rhoGp = mean(rhoPos(maskG));
rhoLn = mean(rhoNeg(maskL));
rhoGn = mean(rhoNeg(maskG));

rhoRatioP = rhoGp/rhoLp;
rhoRatioN = rhoGn/rhoLn;

muRatioP = (rhoGp*cfg.nuG)/(rhoLp*cfg.nuL);
muRatioN = (rhoGn*cfg.nuG)/(rhoLn*cfg.nuL);

ratioP = aLp/aGp;
ratioN = aLn/aGn;

RtauP = ratioP/muRatioP;
RtauN = ratioN/muRatioN;

% Extrapolations aux deux interfaces.
uLiP = aLp*(+cfg.zGamma)+bLp;
uGiP = aGp*(+cfg.zGamma)+bGp;
uLiN = aLn*(-cfg.zGamma)+bLn;
uGiN = aGn*(-cfg.zGamma)+bGn;

% Convention orientee : un Couette antisymetrique parfait donne le meme
% signe en haut et en bas.
slipP = (uGiP-uLiP)/cfg.Uw;
slipN = -(uGiN-uLiN)/cfg.Uw;

uGwP = aGp*(+cfg.H)+bGp;
uGwN = aGn*(-cfg.H)+bGn;

wallSlipP = (+cfg.Uw-uGwP)/cfg.Uw;
wallSlipN = (uGwN-(-cfg.Uw))/cfg.Uw;

% RMS transverse par moitie, normalise par Uw.
uyRmsP = sqrt(mean(vPos.^2))/cfg.Uw;
uyRmsN = sqrt(mean(vNeg.^2))/cfg.Uw;

e = local_empty_halves();
e.startStep = startStep;
e.endStep = endStep;
e.nFrames = n;

e.aL_pos = aLp;
e.aL_neg = aLn;
e.aG_pos = aGp;
e.aG_neg = aGn;
e.ratio_pos = ratioP;
e.ratio_neg = ratioN;

e.R2L_pos = R2Lp;
e.R2L_neg = R2Ln;
e.R2G_pos = R2Gp;
e.R2G_neg = R2Gn;

e.rhoL_pos = rhoLp;
e.rhoL_neg = rhoLn;
e.rhoG_pos = rhoGp;
e.rhoG_neg = rhoGn;
e.rhoRatio_pos = rhoRatioP;
e.rhoRatio_neg = rhoRatioN;
e.muRatio_pos = muRatioP;
e.muRatio_neg = muRatioN;
e.Rtau_pos = RtauP;
e.Rtau_neg = RtauN;

e.interfaceSlip_pos = slipP;
e.interfaceSlip_neg = slipN;
e.wallSlip_pos = wallSlipP;
e.wallSlip_neg = wallSlipN;
e.uyRms_pos = uyRmsP;
e.uyRms_neg = uyRmsN;

% Mesures d'asymetrie haut/bas.
e.asym_aL = local_rel_asym(aLp,aLn);
e.asym_aG = local_rel_asym(aGp,aGn);
e.asym_ratio = local_rel_asym(ratioP,ratioN);
e.asym_rhoRatio = local_rel_asym(rhoRatioP,rhoRatioN);
e.asym_muRatio = local_rel_asym(muRatioP,muRatioN);
e.asym_Rtau = local_rel_asym(RtauP,RtauN);

% Moyennes simples des deux estimations independantes, uniquement comme
% indicateurs de comparaison (ce n'est PAS le repliement conservatif).
e.mean_aL = 0.5*(aLp+aLn);
e.mean_aG = 0.5*(aGp+aGn);
e.mean_ratio = 0.5*(ratioP+ratioN);
e.mean_Rtau = 0.5*(RtauP+RtauN);

% Profils conservatifs conserves pour la figure de la fenetre demandee.
e.zPos = zPos;
e.zNeg = zNeg;
e.uPos = uPos;
e.uNeg = uNeg;
e.rhoPos = rhoPos;
e.rhoNeg = rhoNeg;
e.maskL = maskL;
e.maskG = maskG;
e.bL_pos = bLp;
e.bL_neg = bLn;
e.bG_pos = bGp;
e.bG_neg = bGn;
end

function e = local_empty_halves()
% Les champs vecteurs sont presents pour les estimations individuelles mais
% doivent rester des cellules vides lors de la conversion des series en table.
e = struct( ...
    'startStep',NaN,'endStep',NaN,'nFrames',NaN, ...
    'aL_pos',NaN,'aL_neg',NaN,'aG_pos',NaN,'aG_neg',NaN, ...
    'ratio_pos',NaN,'ratio_neg',NaN, ...
    'R2L_pos',NaN,'R2L_neg',NaN,'R2G_pos',NaN,'R2G_neg',NaN, ...
    'rhoL_pos',NaN,'rhoL_neg',NaN,'rhoG_pos',NaN,'rhoG_neg',NaN, ...
    'rhoRatio_pos',NaN,'rhoRatio_neg',NaN, ...
    'muRatio_pos',NaN,'muRatio_neg',NaN, ...
    'Rtau_pos',NaN,'Rtau_neg',NaN, ...
    'interfaceSlip_pos',NaN,'interfaceSlip_neg',NaN, ...
    'wallSlip_pos',NaN,'wallSlip_neg',NaN, ...
    'uyRms_pos',NaN,'uyRms_neg',NaN, ...
    'asym_aL',NaN,'asym_aG',NaN,'asym_ratio',NaN, ...
    'asym_rhoRatio',NaN,'asym_muRatio',NaN,'asym_Rtau',NaN, ...
    'mean_aL',NaN,'mean_aG',NaN,'mean_ratio',NaN,'mean_Rtau',NaN, ...
    'zPos',[],'zNeg',[],'uPos',[],'uNeg',[], ...
    'rhoPos',[],'rhoNeg',[],'maskL',[],'maskG',[], ...
    'bL_pos',NaN,'bL_neg',NaN,'bG_pos',NaN,'bG_neg',NaN);
end

function s = local_strip_profiles(s)
% Supprime les champs vectoriels avant struct2table pour les series
% temporelles. Les profils restent disponibles dans full/late/last2000.
fields = {'zPos','zNeg','uPos','uNeg','rhoPos','rhoNeg','maskL','maskG'};
s = rmfield(s,fields);
end

% =========================================================================
% Repliement identique a l'analyseur precedent, uniquement pour self-check
% =========================================================================
function f = local_estimate_folded(data,startStep,endStep,cfg)

idx = data.steps > startStep & data.steps <= endStep;
n = nnz(idx);
if n < 2
    error('Fenetre folded (%d,%d] : %d frames.',startStep,endStep,n);
end

R  = sum(data.rhoRows(idx,:),1).';
Px = sum(data.pxRows(idx,:),1).';

half = cfg.ny/2;
top = (half+1):cfg.ny;
bot = half:-1:1;

den = R(top)+R(bot);
uOdd = (Px(top)-Px(bot))./den;
z = ((1:half).'-0.5)*cfg.h;

maskL = z <= (cfg.zGamma-cfg.excludeInterfaceCells*cfg.h);
maskG = z >= (cfg.zGamma+cfg.excludeInterfaceCells*cfg.h) & ...
        z <= (cfg.H-cfg.excludeWallCells*cfg.h);

[aL,~,R2L] = local_line_fit(z(maskL),uOdd(maskL));
[aG,~,R2G] = local_line_fit(z(maskG),uOdd(maskG));

f = struct('aL',aL,'aG',aG,'ratio',aL/aG,'R2L',R2L,'R2G',R2G);
end

% =========================================================================
% Figures
% =========================================================================
function local_plot_rolling(T,cfg,fileName)
f = figure('Color','w','Position',[100 100 1300 900]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('0493x23e - separate halves, rolling %d steps', ...
    cfg.rollingWindowSteps));

nexttile;
plot(T.endStep,T.aL_pos,'-','LineWidth',1.2); hold on;
plot(T.endStep,T.aL_neg,'--','LineWidth',1.2);
grid on; xlabel('step fin'); ylabel('a_L');
legend('z>0','z<0','Location','best'); title('Pente liquide');

nexttile;
plot(T.endStep,T.aG_pos,'-','LineWidth',1.2); hold on;
plot(T.endStep,T.aG_neg,'--','LineWidth',1.2);
grid on; xlabel('step fin'); ylabel('a_G');
legend('z>0','z<0','Location','best'); title('Pente gaz');

nexttile;
plot(T.endStep,T.ratio_pos,'-','LineWidth',1.2); hold on;
plot(T.endStep,T.ratio_neg,'--','LineWidth',1.2);
grid on; xlabel('step fin'); ylabel('a_L/a_G');
legend('z>0','z<0','Location','best'); title('Partage des pentes');

nexttile;
plot(T.endStep,T.Rtau_pos,'-','LineWidth',1.2); hold on;
plot(T.endStep,T.Rtau_neg,'--','LineWidth',1.2);
yline(1,':');
grid on; xlabel('step fin'); ylabel('R_\tau');
legend('z>0','z<0','Location','best'); title('Continuite de contrainte');

local_save_figure(f,fileName);
end

function local_plot_asymmetry(T,cfg,fileName)
f = figure('Color','w','Position',[100 100 1300 900]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf(['0493x23e - top/bottom asymmetry, rolling %d steps; ', ...
    '0 = perfect agreement'],cfg.rollingWindowSteps));

nexttile;
plot(T.endStep,100*T.asym_aL,'LineWidth',1.2); yline(0,':');
grid on; xlabel('step fin'); ylabel('asym a_L [%]'); title('Liquide');

nexttile;
plot(T.endStep,100*T.asym_aG,'LineWidth',1.2); yline(0,':');
grid on; xlabel('step fin'); ylabel('asym a_G [%]'); title('Gaz');

nexttile;
plot(T.endStep,100*T.asym_ratio,'LineWidth',1.2); yline(0,':');
grid on; xlabel('step fin'); ylabel('asym (a_L/a_G) [%]');
title('Ratio des pentes');

nexttile;
plot(T.endStep,100*T.asym_Rtau,'LineWidth',1.2); hold on;
plot(T.endStep,100*T.asym_rhoRatio,'--','LineWidth',1.2);
yline(0,':'); grid on; xlabel('step fin'); ylabel('asym [%]');
legend('R_\tau','\rho_G/\rho_L','Location','best');
title('Contrainte vs densite');

local_save_figure(f,fileName);
end

function local_plot_profiles(e,cfg,fileName)
f = figure('Color','w','Position',[100 100 1250 850]);
tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('0493x23e - independent late profiles (%d,%d]', ...
    e.startStep,e.endStep));

nexttile;
plot(e.uNeg,e.zNeg,'o','MarkerSize',3); hold on;
plot(e.uPos,e.zPos,'o','MarkerSize',3);

zLp = e.zPos(e.maskL);
zGp = e.zPos(e.maskG);
zLn = e.zNeg(e.maskL);
zGn = e.zNeg(e.maskG);

plot(e.aL_pos*zLp+e.bL_pos,zLp,'-','LineWidth',1.5);
plot(e.aG_pos*zGp+e.bG_pos,zGp,'-','LineWidth',1.5);
plot(e.aL_neg*zLn+e.bL_neg,zLn,'--','LineWidth',1.5);
plot(e.aG_neg*zGn+e.bG_neg,zGn,'--','LineWidth',1.5);

xline(0,':'); yline(+cfg.zGamma,':'); yline(-cfg.zGamma,':');
grid on; xlabel('u_x'); ylabel('z');
title('Profils u_x(z) sans repliement');

nexttile;
plot(e.rhoNeg,e.zNeg,'-','LineWidth',1.2); hold on;
plot(e.rhoPos,e.zPos,'-','LineWidth',1.2);
yline(+cfg.zGamma,':'); yline(-cfg.zGamma,':');
grid on; xlabel('\rho'); ylabel('z');
title('Densite moyenne par moitie');

local_save_figure(f,fileName);
end

function local_plot_terminal(T,cfg,fileName)
f = figure('Color','w','Position',[100 100 1300 900]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('0493x23e - terminal estimates ending at %d', ...
    cfg.analysisEndStep));

nexttile;
plot(T.windowSteps,T.aL_pos,'-o'); hold on;
plot(T.windowSteps,T.aL_neg,'--o');
grid on; xlabel('longueur fenetre [steps]'); ylabel('a_L');
legend('z>0','z<0','Location','best'); title('a_L terminal');

nexttile;
plot(T.windowSteps,T.aG_pos,'-o'); hold on;
plot(T.windowSteps,T.aG_neg,'--o');
grid on; xlabel('longueur fenetre [steps]'); ylabel('a_G');
legend('z>0','z<0','Location','best'); title('a_G terminal');

nexttile;
plot(T.windowSteps,T.ratio_pos,'-o'); hold on;
plot(T.windowSteps,T.ratio_neg,'--o');
grid on; xlabel('longueur fenetre [steps]'); ylabel('a_L/a_G');
legend('z>0','z<0','Location','best'); title('Ratio terminal');

nexttile;
plot(T.windowSteps,100*T.asym_ratio,'-o'); hold on;
plot(T.windowSteps,100*T.asym_Rtau,'--o'); yline(0,':');
grid on; xlabel('longueur fenetre [steps]'); ylabel('asymetrie [%]');
legend('a_L/a_G','R_\tau','Location','best');
title('Sensibilite de l''asymetrie');

local_save_figure(f,fileName);
end

function local_save_figure(f,fileName)
try
    exportgraphics(f,fileName,'Resolution',170);
catch
    saveas(f,fileName);
end
%close(f);
end

% =========================================================================
% Outils statistiques
% =========================================================================
function [a,b,R2] = local_line_fit(x,y)
x = x(:); y = y(:);
ok = isfinite(x) & isfinite(y);
x = x(ok); y = y(ok);

X = [x,ones(size(x))];
beta = X\y;
a = beta(1);
b = beta(2);

yh = X*beta;
ssRes = sum((y-yh).^2);
ssTot = sum((y-mean(y)).^2);
if ssTot > 0
    R2 = 1-ssRes/ssTot;
else
    R2 = NaN;
end
end

function r = local_rel_asym(a,b)
den = abs(a)+abs(b);
if den <= eps
    r = NaN;
else
    r = 2*(a-b)/den;
end
end

function [slope,slopeSE] = local_trend(x,y)
x = x(:); y = y(:);
ok = isfinite(x) & isfinite(y);
x = x(ok); y = y(ok);

xc = x-mean(x);
X = [xc,ones(size(xc))];
beta = X\y;
slope = beta(1);

res = y-X*beta;
n = numel(y);
dof = max(n-2,1);
s2 = sum(res.^2)/dof;
C = s2*inv(X.'*X); %#ok<MINV>
slopeSE = sqrt(max(C(1,1),0));
end

function [rho1,tauInt,Neff] = local_corr_diag(y)
y = y(:);
y = y(isfinite(y));
n = numel(y);

if n < 3
    rho1 = NaN; tauInt = NaN; Neff = NaN; return;
end

yc = y-mean(y);
den = sum(yc.^2);

if den <= 0
    rho1 = 0; tauInt = 1; Neff = n; return;
end

maxLag = min(n-1,floor(n/2));
rho = zeros(maxLag,1);

for k = 1:maxLag
    rho(k) = sum(yc(1:n-k).*yc(1+k:n))/den;
end

rho1 = rho(1);
s = 0;
for k = 1:maxLag
    if rho(k) <= 0, break; end
    s = s+rho(k);
end

tauInt = max(1,1+2*s);
Neff = max(1,n/tauInt);
end

% =========================================================================
% I/O / texte
% =========================================================================
function A = local_read_f32(fileName,nx,ny)
fid = fopen(fileName,'r','ieee-le');
if fid < 0, error('Impossible d''ouvrir %s',fileName); end
c = onCleanup(@() fclose(fid));
v = fread(fid,nx*ny,'single=>double');

if numel(v) ~= nx*ny
    error('%s : %d valeurs, attendu %d.',fileName,numel(v),nx*ny);
end

% Enregistreur row-major : x varie le plus vite.
A = reshape(v,[nx,ny]).';
end

function val = local_kv_num(txt,keys,defaultVal)
val = defaultVal;
for i = 1:numel(keys)
    key = regexptranslate('escape',keys{i});
    tok = regexp(txt,['(?m)^\s*' key '\s*=\s*([^\r\n#]+)'], ...
        'tokens','once');
    if ~isempty(tok)
        x = str2double(strtrim(tok{1}));
        if isfinite(x)
            val = x;
            return;
        end
    end
end
end

function recDir = local_find_recording_dir(runRoot)
base = fullfile(runRoot,'output','recordings');
d = dir(fullfile(base,'*','manifest.kv'));

if isempty(d)
    error('Aucun manifest.kv sous %s',base);
end

chosen = 1;
for i = 1:numel(d)
    if contains(lower(d(i).folder),'couette')
        chosen = i;
        break;
    end
end
recDir = d(chosen).folder;
end

function s = local_tf(v)
if v, s='PASS'; else, s='FAIL'; end
end

function local_print_halves(fid,e)
fprintf(fid,'frames = %d\n',e.nFrames);

fprintf(fid,'z>0: aL = %.12g, R2L = %.10g; aG = %.12g, R2G = %.10g\n', ...
    e.aL_pos,e.R2L_pos,e.aG_pos,e.R2G_pos);
fprintf(fid,'z<0: aL = %.12g, R2L = %.10g; aG = %.12g, R2G = %.10g\n', ...
    e.aL_neg,e.R2L_neg,e.aG_neg,e.R2G_neg);

fprintf(fid,'z>0: aL/aG = %.12g; rhoG/rhoL = %.12g; muG/muL = %.12g; Rtau = %.12g\n', ...
    e.ratio_pos,e.rhoRatio_pos,e.muRatio_pos,e.Rtau_pos);
fprintf(fid,'z<0: aL/aG = %.12g; rhoG/rhoL = %.12g; muG/muL = %.12g; Rtau = %.12g\n', ...
    e.ratio_neg,e.rhoRatio_neg,e.muRatio_neg,e.Rtau_neg);

fprintf(fid,'oriented interface slip/Uw: z>0 = %+.12g; z<0 = %+.12g\n', ...
    e.interfaceSlip_pos,e.interfaceSlip_neg);
fprintf(fid,'oriented wall slip/Uw:      z>0 = %+.12g; z<0 = %+.12g\n', ...
    e.wallSlip_pos,e.wallSlip_neg);

fprintf(fid,'uy RMS/Uw: z>0 = %.12g; z<0 = %.12g\n', ...
    e.uyRms_pos,e.uyRms_neg);

fprintf(fid,'asym aL = %+.12g; asym aG = %+.12g; asym ratio = %+.12g\n', ...
    e.asym_aL,e.asym_aG,e.asym_ratio);
fprintf(fid,'asym rhoRatio = %+.12g; asym Rtau = %+.12g\n', ...
    e.asym_rhoRatio,e.asym_Rtau);
end

function local_console_halves(e)
fprintf('  z>0: aL=%.8g aG=%.8g ratio=%.8g Rtau=%.8g\n', ...
    e.aL_pos,e.aG_pos,e.ratio_pos,e.Rtau_pos);
fprintf('  z<0: aL=%.8g aG=%.8g ratio=%.8g Rtau=%.8g\n', ...
    e.aL_neg,e.aG_neg,e.ratio_neg,e.Rtau_neg);
fprintf('  asym: aL=%+.3f%% aG=%+.3f%% ratio=%+.3f%% Rtau=%+.3f%%\n', ...
    100*e.asym_aL,100*e.asym_aG,100*e.asym_ratio,100*e.asym_Rtau);
end

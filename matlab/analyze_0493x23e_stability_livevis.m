function out = analyze_0493x23e_stability_livevis(runRoot)
%ANALYZE_0493X23E_STABILITY_LIVEVIS
% Analyse de stabilite temporelle du Couette biphasique 0493x23e a 18000 steps.
%
% L'analyse reprend STRICTEMENT la metrologie conservative du traitement
% article :
%   px = rho .* ux
%   py = rho .* uy
%   moyenne en x et dans le temps sur les quantites conservatives
%   repliement antisymetrique G|L|G :
%       u_odd(z)  = [Pxtop(z)-Pxbottom(z)]/[Mtop(z)+Mbottom(z)]
%       u_even(z) = [Pxtop(z)+Pxbottom(z)]/[Mtop(z)+Mbottom(z)]
%
% Geometrie nominale x23e :
%   Nx=Ny=128, Lx=Ly=0.5, h=1/256
%   centre du liquide z=0
%   interface zGamma=32 h
%   paroi z=64 h
%
% Fenetres de fit fixes (pas d'optimisation a posteriori) :
%   liquide : z <= zGamma - 4 h
%   gaz     : z >= zGamma + 4 h et z <= H - 4 h
%
% L'objectif n'est PAS seulement d'estimer aL/aG sur [6000,18000], mais de
% verifier si l'etat terminal est stabilise :
%   1) series glissantes sur 2000 steps ;
%   2) micro-blocs non recouvrants de 400 steps ;
%   3) sensibilite de l'estimation terminale a la longueur de fenetre ;
%   4) derive lineaire sur les 6000 derniers steps ;
%   5) comparaison [14000,16000] vs [16000,18000] ;
%   6) stabilite de rhoG/rhoL et donc de muG/muL ;
%   7) R_tau = (aL/aG)/(muG/muL).
%
% Usage depuis le dossier matlab :
%   out = analyze_0493x23e_stability_livevis;
%
% ou :
%   out = analyze_0493x23e_stability_livevis( ...
%       '../runs/0493x23e_article_couette_livevis_Uw0075_seed593170');
%
% Sorties :
%   <runRoot>/analysis_0493x23e_stability/
%       rolling_2000_0493x23e.csv
%       microblocks_0400_0493x23e.csv
%       terminal_windows_0493x23e.csv
%       stability_metrics_0493x23e.csv
%       stability_summary_0493x23e.txt
%       stability_rolling_0493x23e.png
%       stability_microblocks_0493x23e.png
%       stability_terminal_windows_0493x23e.png
%       stability_0493x23e.mat
%
% Remarque :
% Les seuils STABLE-like sont des seuils DIAGNOSTIQUES, pas une loi physique.
% Ils sont regroupes dans cfg.tol* ci-dessous et peuvent etre modifies.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..', 'runs', ...
        '0493x23e_article_couette_livevis_Uw0075_seed593170');
end
runRoot = char(runRoot);

%% ------------------------------------------------------------------------
% Configuration
% -------------------------------------------------------------------------
cfg = struct();

cfg.analysisStartStep = 6000;
cfg.analysisEndStep   = 18000;

% Metrologie temporelle
cfg.rollingWindowSteps = 2000;
cfg.rollingStrideSteps = 200;
cfg.microBlockSteps    = 400;
cfg.tailTrendSteps     = 6000;
cfg.terminalWindows    = [1000 2000 4000 6000 8000 12000];

% Geometrie / physique
cfg.Lx = 0.5;
cfg.Ly = 0.5;
cfg.Uw = 0.075;
cfg.interfaceCells = 32;
cfg.excludeInterfaceCells = 4;
cfg.excludeWallCells = 4;

% Viscosites cinematiques TG mesurees au meme dt=0.002
cfg.nuL = 6.15880e-4;
cfg.nuG = 7.29393e-4;

% Seuils de DIAGNOSTIC pour qualifier "STABLE-like".
% Trois tests sont appliques : saut terminal, derive de queue, sensibilite
% a la longueur de fenetre.
cfg.tolSlopeFraction = 0.05;      % 5 % pour aL et aG
cfg.tolRatioFraction = 0.05;      % 5 % pour aL/aG
cfg.tolDensityFraction = 0.02;    % 2 % pour rhoG/rhoL

% R2 minimal uniquement comme garde de qualite spatiale du fit terminal.
cfg.minTerminalR2 = 0.99;

%% ------------------------------------------------------------------------
% Localisation de l'enregistrement LiveVis
% -------------------------------------------------------------------------
recDir = fullfile(runRoot, 'output', 'recordings', 'couette_x23e');
if ~isfolder(recDir)
    recDir = local_find_recording_dir(runRoot);
end

manifestFile = fullfile(recDir, 'manifest.kv');
if ~isfile(manifestFile)
    error('Manifest introuvable : %s', manifestFile);
end
manifestText = fileread(manifestFile);

nx = local_kv_num(manifestText, {'liveGridNx','Nx','solverNx'}, 128);
ny = local_kv_num(manifestText, {'liveGridNy','Ny','solverNy'}, 128);
solverNx = local_kv_num(manifestText, {'solverNx'}, nx);
solverNy = local_kv_num(manifestText, {'solverNy'}, ny);
cfg.Lx = local_kv_num(manifestText, {'Lx','domainLx'}, cfg.Lx);
cfg.Ly = local_kv_num(manifestText, {'Ly','domainLy'}, cfg.Ly);
recordEvery = local_kv_num(manifestText, {'recordEvery'}, NaN);

if mod(ny,2) ~= 0
    error('Ny=%d doit etre pair pour le repliement G|L|G.', ny);
end

cfg.nx = nx;
cfg.ny = ny;
cfg.solverNx = solverNx;
cfg.solverNy = solverNy;
cfg.recordEvery = recordEvery;
cfg.h = cfg.Ly / ny;
cfg.H = cfg.Ly / 2;
cfg.zGamma = cfg.interfaceCells * cfg.h;

% Correction native-equivalente si grille LiveVis != grille solveur.
rhoScale = (solverNx/nx) * (solverNy/ny);
cfg.rhoScale = rhoScale;

%% ------------------------------------------------------------------------
% Inventaire des frames completes rho/ux/uy
% -------------------------------------------------------------------------
rhoFiles = dir(fullfile(recDir, 'step_*_field_rho.f32'));
if isempty(rhoFiles)
    error('Aucune frame rho trouvee dans %s', recDir);
end

steps = zeros(numel(rhoFiles),1);
rhoNames = cell(numel(rhoFiles),1);
uxNames  = cell(numel(rhoFiles),1);
uyNames  = cell(numel(rhoFiles),1);
keep = false(numel(rhoFiles),1);

for i = 1:numel(rhoFiles)
    tok = regexp(rhoFiles(i).name, '^step_(\d+)_field_rho\.f32$', ...
        'tokens', 'once');
    if isempty(tok)
        continue;
    end
    s = str2double(tok{1});
    uxName = regexprep(rhoFiles(i).name, '_field_rho\.f32$', '_field_ux.f32');
    uyName = regexprep(rhoFiles(i).name, '_field_rho\.f32$', '_field_uy.f32');

    if isfile(fullfile(recDir, uxName)) && isfile(fullfile(recDir, uyName))
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

[steps, ord] = sort(steps);
rhoNames = rhoNames(ord);
uxNames  = uxNames(ord);
uyNames  = uyNames(ord);

maskEnd = steps <= cfg.analysisEndStep;
steps = steps(maskEnd);
rhoNames = rhoNames(maskEnd);
uxNames = uxNames(maskEnd);
uyNames = uyNames(maskEnd);

if isempty(steps)
    error('Aucune frame complete <= step %d.', cfg.analysisEndStep);
end
if steps(end) < cfg.analysisEndStep
    warning('Derniere frame = %d, inferieure a la cible %d.', ...
        steps(end), cfg.analysisEndStep);
    cfg.analysisEndStep = steps(end);
end

fprintf('[0493x23e-stability] recDir=%s\n', recDir);
fprintf('[0493x23e-stability] grid=%dx%d h=%.10g frames=%d steps=%d..%d\n', ...
    nx, ny, cfg.h, numel(steps), steps(1), steps(end));

%% ------------------------------------------------------------------------
% Lecture unique des champs : on ne conserve que les sommes horizontales
% rho, rho*ux, rho*uy pour chaque y et chaque frame.
% -------------------------------------------------------------------------
nF = numel(steps);
rhoRows = zeros(nF, ny);
pxRows  = zeros(nF, ny);
pyRows  = zeros(nF, ny);

for i = 1:nF
    rho = local_read_f32(fullfile(recDir, rhoNames{i}), nx, ny) * rhoScale;
    ux  = local_read_f32(fullfile(recDir, uxNames{i}),  nx, ny);
    uy  = local_read_f32(fullfile(recDir, uyNames{i}),  nx, ny);

    if any(~isfinite(rho(:))) || any(~isfinite(ux(:))) || any(~isfinite(uy(:)))
        error('NaN/Inf dans la frame step=%d.', steps(i));
    end

    rhoRows(i,:) = sum(rho, 2).';
    pxRows(i,:)  = sum(rho .* ux, 2).';
    pyRows(i,:)  = sum(rho .* uy, 2).';

    if mod(i,100)==0 || i==nF
        fprintf('[0493x23e-stability] read %d/%d frames (step=%d)\n', ...
            i, nF, steps(i));
    end
end

data = struct();
data.steps = steps;
data.rhoRows = rhoRows;
data.pxRows = pxRows;
data.pyRows = pyRows;

%% ------------------------------------------------------------------------
% 0) Auto-controle : reproduction de la metrologie deja validee sur
%    (6000,18000].
% -------------------------------------------------------------------------
fullWindow = local_estimate(data, cfg.analysisStartStep, ...
    cfg.analysisEndStep, cfg);

ref = struct();
ref.aL = 0.1118677907;
ref.aG = 0.5076760565;
ref.ratio = 0.2203527018;

selfErr = [ ...
    abs(fullWindow.aL-ref.aL)/abs(ref.aL), ...
    abs(fullWindow.aG-ref.aG)/abs(ref.aG), ...
    abs(fullWindow.ratio-ref.ratio)/abs(ref.ratio) ...
    ];
metrologySelfCheck = max(selfErr) <= 5e-3;

fprintf('[0493x23e-stability] self-check (6000,18000]: ');
fprintf('aL=%.9g aG=%.9g ratio=%.9g maxRelErr=%.3g -> %s\n', ...
    fullWindow.aL, fullWindow.aG, fullWindow.ratio, max(selfErr), ...
    local_tf(metrologySelfCheck));

if ~metrologySelfCheck
    warning(['La metrologie (6000,18000] ne reproduit pas a 0.5%% les valeurs ', ...
        'de l''analyse article precedente. Verifier orientation/folding avant ', ...
        'd''interpreter la stabilite.']);
end

%% ------------------------------------------------------------------------
% 1) Serie glissante : fenetre de 2000 steps, stride 200
% -------------------------------------------------------------------------
rollEnd = (cfg.analysisStartStep + cfg.rollingWindowSteps): ...
          cfg.rollingStrideSteps:cfg.analysisEndStep;
rolling = repmat(local_empty_estimate(), numel(rollEnd), 1);

for k = 1:numel(rollEnd)
    rolling(k) = local_estimate(data, rollEnd(k)-cfg.rollingWindowSteps, ...
        rollEnd(k), cfg);
end
Troll = struct2table(rolling);

%% ------------------------------------------------------------------------
% 2) Micro-blocs non recouvrants de 400 steps sur [6000,18000]
% Convention : (startStep, endStep], donc 600 frames exactement sur
% (6000,18000] si recordEvery=20.
% -------------------------------------------------------------------------
blockStarts = cfg.analysisStartStep:cfg.microBlockSteps: ...
              (cfg.analysisEndStep-cfg.microBlockSteps);
micro = repmat(local_empty_estimate(), numel(blockStarts), 1);

for k = 1:numel(blockStarts)
    micro(k) = local_estimate(data, blockStarts(k), ...
        blockStarts(k)+cfg.microBlockSteps, cfg);
end
Tmicro = struct2table(micro);
Tmicro.midStep = 0.5*(Tmicro.startStep + Tmicro.endStep);

%% ------------------------------------------------------------------------
% 3) Sensibilite de l'etat TERMINAL a la longueur de fenetre
% -------------------------------------------------------------------------
wins = cfg.terminalWindows(:);
term = repmat(local_empty_estimate(), numel(wins), 1);
for k = 1:numel(wins)
    term(k) = local_estimate(data, cfg.analysisEndStep-wins(k), ...
        cfg.analysisEndStep, cfg);
end
Tterm = struct2table(term);
Tterm.windowSteps = wins;

%% ------------------------------------------------------------------------
% 4) Comparaison dernier bloc 2000 vs bloc precedent
% -------------------------------------------------------------------------
prev2000 = local_estimate(data, ...
    cfg.analysisEndStep-2*cfg.rollingWindowSteps, ...
    cfg.analysisEndStep-cfg.rollingWindowSteps, cfg);

last2000 = local_estimate(data, ...
    cfg.analysisEndStep-cfg.rollingWindowSteps, ...
    cfg.analysisEndStep, cfg);

%% ------------------------------------------------------------------------
% 5) Metriques de stabilite
% -------------------------------------------------------------------------
tailMask = Tmicro.midStep > (cfg.analysisEndStep-cfg.tailTrendSteps);

metrics = [
    local_metric('aL',       Tmicro.aL,       Tmicro.midStep, tailMask, ...
                 Tterm, prev2000.aL,       last2000.aL,       cfg.tolSlopeFraction, cfg)
    local_metric('aG',       Tmicro.aG,       Tmicro.midStep, tailMask, ...
                 Tterm, prev2000.aG,       last2000.aG,       cfg.tolSlopeFraction, cfg)
    local_metric('ratio',    Tmicro.ratio,    Tmicro.midStep, tailMask, ...
                 Tterm, prev2000.ratio,    last2000.ratio,    cfg.tolRatioFraction, cfg)
    local_metric('rhoRatio', Tmicro.rhoRatio, Tmicro.midStep, tailMask, ...
                 Tterm, prev2000.rhoRatio, last2000.rhoRatio, cfg.tolDensityFraction, cfg)
    local_metric('muRatio',  Tmicro.muRatio,  Tmicro.midStep, tailMask, ...
                 Tterm, prev2000.muRatio,  last2000.muRatio,  cfg.tolDensityFraction, cfg)
    local_metric('Rtau',     Tmicro.Rtau,     Tmicro.midStep, tailMask, ...
                 Tterm, prev2000.Rtau,     last2000.Rtau,     cfg.tolRatioFraction, cfg)
    ];
Tmetrics = struct2table(metrics);

% Garde spatiale sur le dernier etat 2000 steps.
fitQualityOK = last2000.R2L >= cfg.minTerminalR2 && ...
               last2000.R2G >= cfg.minTerminalR2;

% Le statut global exige la stabilite des deux pentes, de leur ratio et du
% rapport de densites. Rtau n'est pas ajoute comme contrainte independante
% car il est derive de ratio et rhoRatio.
mainNames = {'aL','aG','ratio','rhoRatio'};
mainOK = true;
for k = 1:numel(mainNames)
    j = find(strcmp(Tmetrics.name, mainNames{k}), 1);
    mainOK = mainOK && Tmetrics.stableLike(j);
end

if mainOK && fitQualityOK
    diagnosticStatus = "STABLE-like";
else
    diagnosticStatus = "NOT-STABLE-like";
end

%% ------------------------------------------------------------------------
% 6) Sorties
% -------------------------------------------------------------------------
outDir = fullfile(runRoot, 'analysis_0493x23e_stability');
if ~isfolder(outDir)
    mkdir(outDir);
end

writetable(Troll, fullfile(outDir, 'rolling_2000_0493x23e.csv'));
writetable(Tmicro, fullfile(outDir, 'microblocks_0400_0493x23e.csv'));
writetable(Tterm, fullfile(outDir, 'terminal_windows_0493x23e.csv'));
writetable(Tmetrics, fullfile(outDir, 'stability_metrics_0493x23e.csv'));

local_plot_rolling(Troll, cfg, ...
    fullfile(outDir, 'stability_rolling_0493x23e.png'));
local_plot_micro(Tmicro, tailMask, cfg, ...
    fullfile(outDir, 'stability_microblocks_0493x23e.png'));
local_plot_terminal(Tterm, cfg, ...
    fullfile(outDir, 'stability_terminal_windows_0493x23e.png'));

summaryFile = fullfile(outDir, 'stability_summary_0493x23e.txt');
fid = fopen(summaryFile, 'w');
if fid < 0
    error('Impossible d''ecrire %s', summaryFile);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '0493x23e Couette LiveVis terminal stability analysis\n');
fprintf(fid, 'runRoot = %s\n', runRoot);
fprintf(fid, 'recording = %s\n', recDir);
fprintf(fid, 'frames available = %d, step range = [%d,%d]\n', ...
    nF, steps(1), steps(end));
fprintf(fid, 'analysis convention = (startStep,endStep]\n');
fprintf(fid, 'grid = %dx%d, Lx=%.12g, Ly=%.12g, h=%.12g\n', ...
    nx, ny, cfg.Lx, cfg.Ly, cfg.h);
fprintf(fid, 'zGamma/h = %.6g, H/h = %.6g\n', ...
    cfg.zGamma/cfg.h, cfg.H/cfg.h);
fprintf(fid, 'fit liquid = z <= zGamma-4h; fit gas = z >= zGamma+4h and z <= H-4h\n');
fprintf(fid, 'nuL = %.12g, nuG = %.12g, nuG/nuL = %.12g\n', ...
    cfg.nuL, cfg.nuG, cfg.nuG/cfg.nuL);
fprintf(fid, '\n');
fprintf(fid, 'METROLOGY SELF-CHECK ON (6000,18000]\n');
fprintf(fid, 'expected aL = %.12g, measured = %.12g\n', ref.aL, fullWindow.aL);
fprintf(fid, 'expected aG = %.12g, measured = %.12g\n', ref.aG, fullWindow.aG);
fprintf(fid, 'expected ratio = %.12g, measured = %.12g\n', ref.ratio, fullWindow.ratio);
fprintf(fid, 'max relative error = %.12g\n', max(selfErr));
fprintf(fid, 'metrologySelfCheck = %d\n\n', metrologySelfCheck);

fprintf(fid, 'LAST 2000 STEPS (%d,%d]\n', ...
    last2000.startStep, last2000.endStep);
local_print_estimate(fid, last2000);

fprintf(fid, '\nPREVIOUS 2000 STEPS (%d,%d]\n', ...
    prev2000.startStep, prev2000.endStep);
local_print_estimate(fid, prev2000);

fprintf(fid, '\nSTABILITY METRICS\n');
fprintf(fid, ['name          endJump       tailDrift     windowSpread  tailCV        ', ...
              'lag1          Neff          tol       stableLike\n']);
for k = 1:height(Tmetrics)
    fprintf(fid, '%-12s  %11.5g  %11.5g  %11.5g  %11.5g  %11.5g  %11.5g  %8.4g  %d\n', ...
        Tmetrics.name{k}, Tmetrics.endJumpFrac(k), ...
        Tmetrics.tailDriftFrac(k), Tmetrics.terminalWindowSpreadFrac(k), ...
        Tmetrics.tailCV(k), Tmetrics.lag1(k), Tmetrics.Neff(k), ...
        Tmetrics.tolerance(k), Tmetrics.stableLike(k));
end

fprintf(fid, '\nDiagnostic thresholds:\n');
fprintf(fid, '  slopes aL/aG      : %.3f\n', cfg.tolSlopeFraction);
fprintf(fid, '  ratio aL/aG       : %.3f\n', cfg.tolRatioFraction);
fprintf(fid, '  rhoG/rhoL         : %.3f\n', cfg.tolDensityFraction);
fprintf(fid, '  terminal fit R2   : >= %.4f\n', cfg.minTerminalR2);
fprintf(fid, '\nfitQualityOK = %d\n', fitQualityOK);
fprintf(fid, 'metrologySelfCheck = %d\n', metrologySelfCheck);
fprintf(fid, 'diagnosticStatus = %s\n', char(diagnosticStatus));
fprintf(fid, ['\nIMPORTANT: STABLE-like / NOT-STABLE-like est un diagnostic numerique ', ...
              'base sur les seuils ci-dessus, pas une preuve de stationnarite.\n']);

clear cleanup

out = struct();
out.cfg = cfg;
out.runRoot = runRoot;
out.recDir = recDir;
out.rolling = Troll;
out.microblocks = Tmicro;
out.terminalWindows = Tterm;
out.metrics = Tmetrics;
out.fullWindow = fullWindow;
out.reference = ref;
out.metrologySelfCheck = metrologySelfCheck;
out.previous2000 = prev2000;
out.last2000 = last2000;
out.fitQualityOK = fitQualityOK;
out.diagnosticStatus = diagnosticStatus;
out.outputDir = outDir;

save(fullfile(outDir, 'stability_0493x23e.mat'), 'out');

fprintf('\n[0493x23e-stability] LAST 2000 (%d,%d]\n', ...
    last2000.startStep, last2000.endStep);
fprintf('  aL=%.9g  aG=%.9g  aL/aG=%.9g\n', ...
    last2000.aL, last2000.aG, last2000.ratio);
fprintf('  rhoL=%.9g rhoG=%.9g rhoG/rhoL=%.9g\n', ...
    last2000.rhoL, last2000.rhoG, last2000.rhoRatio);
fprintf('  muG/muL=%.9g  Rtau=%.9g\n', ...
    last2000.muRatio, last2000.Rtau);
fprintf('  R2L=%.7f R2G=%.7f slip/Uw=%+.6g evenRMS/Uw=%.6g\n', ...
    last2000.R2L, last2000.R2G, last2000.slipOverUw, ...
    last2000.evenRmsOverUw);

fprintf('\n[0493x23e-stability] METRICS\n');
disp(Tmetrics(:, {'name','endJumpFrac','tailDriftFrac', ...
    'terminalWindowSpreadFrac','tailCV','lag1','Neff','tolerance','stableLike'}));

fprintf('[0493x23e-stability] metrologySelfCheck=%s\n', local_tf(metrologySelfCheck));
fprintf('[0493x23e-stability] diagnosticStatus=%s\n', char(diagnosticStatus));
fprintf('[0493x23e-stability] summary=%s\n', summaryFile);

end

% =========================================================================
% Estimation conservative sur une fenetre (startStep,endStep]
% =========================================================================
function e = local_estimate(data, startStep, endStep, cfg)

idx = data.steps > startStep & data.steps <= endStep;
n = nnz(idx);
if n < 2
    error('Fenetre (%d,%d] : seulement %d frames.', startStep, endStep, n);
end

R  = sum(data.rhoRows(idx,:), 1).';
Px = sum(data.pxRows(idx,:),  1).';
Py = sum(data.pyRows(idx,:),  1).';

ny = cfg.ny;
half = ny/2;
top = (half+1):ny;
bot = half:-1:1;

Rt = R(top);
Rb = R(bot);
Pxt = Px(top);
Pxb = Px(bot);
Pyt = Py(top);
Pyb = Py(bot);

den = Rt + Rb;
if any(den <= 0)
    error('Masse repliee non positive dans (%d,%d].', startStep, endStep);
end

% Metrologie conservative.
uOdd  = (Pxt - Pxb) ./ den;
uEven = (Pxt + Pxb) ./ den;
uyMean = (Pyt + Pyb) ./ den;

z = ((1:half).' - 0.5) * cfg.h;

maskL = z <= (cfg.zGamma - cfg.excludeInterfaceCells*cfg.h);
maskG = z >= (cfg.zGamma + cfg.excludeInterfaceCells*cfg.h) & ...
        z <= (cfg.H - cfg.excludeWallCells*cfg.h);

[aL,bL,R2L] = local_line_fit(z(maskL), uOdd(maskL));
[aG,bG,R2G] = local_line_fit(z(maskG), uOdd(maskG));

% Densite moyenne volumique repliee dans les memes zones bulk.
rhoFold = den / (2*n*cfg.nx);
rhoL = mean(rhoFold(maskL));
rhoG = mean(rhoFold(maskG));
rhoRatio = rhoG/rhoL;

muRatio = (rhoG*cfg.nuG)/(rhoL*cfg.nuL);
ratio = aL/aG;
Rtau = ratio/muRatio;

uLi = aL*cfg.zGamma + bL;
uGi = aG*cfg.zGamma + bG;
slip = uGi-uLi;

uGw = aG*cfg.H+bG;
wallSlip = cfg.Uw-uGw;

e = local_empty_estimate();
e.startStep = startStep;
e.endStep = endStep;
e.nFrames = n;
e.aL = aL;
e.aG = aG;
e.ratio = ratio;
e.R2L = R2L;
e.R2G = R2G;
e.rhoL = rhoL;
e.rhoG = rhoG;
e.rhoRatio = rhoRatio;
e.muRatio = muRatio;
e.Rtau = Rtau;
e.slipOverUw = slip/cfg.Uw;
e.wallSlipOverUw = wallSlip/cfg.Uw;
e.evenRmsOverUw = sqrt(mean(uEven.^2))/cfg.Uw;
e.uyRmsOverUw = sqrt(mean(uyMean.^2))/cfg.Uw;
end

function e = local_empty_estimate()
e = struct( ...
    'startStep', NaN, ...
    'endStep', NaN, ...
    'nFrames', NaN, ...
    'aL', NaN, ...
    'aG', NaN, ...
    'ratio', NaN, ...
    'R2L', NaN, ...
    'R2G', NaN, ...
    'rhoL', NaN, ...
    'rhoG', NaN, ...
    'rhoRatio', NaN, ...
    'muRatio', NaN, ...
    'Rtau', NaN, ...
    'slipOverUw', NaN, ...
    'wallSlipOverUw', NaN, ...
    'evenRmsOverUw', NaN, ...
    'uyRmsOverUw', NaN);
end

% =========================================================================
% Metrique de stabilite
% =========================================================================
function m = local_metric(name, yMicro, xMicro, tailMask, Tterm, ...
                          prevVal, lastVal, tolerance, cfg)

yt = yMicro(tailMask);
xt = xMicro(tailMask);

ok = isfinite(yt) & isfinite(xt);
yt = yt(ok);
xt = xt(ok);

if numel(yt) < 4
    error('Pas assez de micro-blocs pour la tendance de %s.', name);
end

[slope, slopeSE] = local_trend(xt, yt);
ybar = mean(yt);
scale = max(abs(ybar), eps);

tailDriftFrac = abs(slope) * cfg.tailTrendSteps / scale;
tailDrift2SEFrac = 2*slopeSE*cfg.tailTrendSteps/scale;
tailCV = std(yt,0)/scale;

[rho1,tauInt,Neff] = local_corr_diag(yt);

endJumpFrac = abs(lastVal-prevVal) / max(abs(0.5*(lastVal+prevVal)), eps);

% Sensibilite a la longueur de fenetre terminale : 2000,4000,6000.
want = [2000 4000 6000];
vals = nan(size(want));
for j = 1:numel(want)
    ii = find(Tterm.windowSteps == want(j), 1);
    if ~isempty(ii)
        vals(j) = Tterm.(name)(ii);
    end
end
vals = vals(isfinite(vals));
if numel(vals) >= 2
    terminalWindowSpreadFrac = (max(vals)-min(vals)) / ...
        max(abs(mean(vals)), eps);
else
    terminalWindowSpreadFrac = NaN;
end

stableLike = endJumpFrac <= tolerance && ...
             tailDriftFrac <= tolerance && ...
             terminalWindowSpreadFrac <= tolerance;

m = struct();
m.name = name;
m.endJumpFrac = endJumpFrac;
m.tailSlopePerStep = slope;
m.tailSlopeSEPerStep = slopeSE;
m.tailDriftFrac = tailDriftFrac;
m.tailDrift2SEFrac = tailDrift2SEFrac;
m.terminalWindowSpreadFrac = terminalWindowSpreadFrac;
m.tailMean = ybar;
m.tailSD = std(yt,0);
m.tailCV = tailCV;
m.lag1 = rho1;
m.tauIntBlocks = tauInt;
m.Neff = Neff;
m.tolerance = tolerance;
m.stableLike = stableLike;
end

% =========================================================================
% Fits / statistiques sans toolbox
% =========================================================================
function [a,b,R2] = local_line_fit(x,y)
x = x(:);
y = y(:);
ok = isfinite(x) & isfinite(y);
x = x(ok);
y = y(ok);

X = [x, ones(size(x))];
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

function [slope,slopeSE] = local_trend(x,y)
x = x(:);
y = y(:);
xc = x-mean(x);
X = [xc, ones(size(xc))];
beta = X\y;
slope = beta(1);

r = y-X*beta;
n = numel(y);
dof = max(n-2,1);
s2 = sum(r.^2)/dof;
C = s2 * inv(X.'*X); %#ok<MINV>
slopeSE = sqrt(max(C(1,1),0));
end

function [rho1,tauInt,Neff] = local_corr_diag(y)
y = y(:);
y = y(isfinite(y));
n = numel(y);
if n < 3
    rho1 = NaN;
    tauInt = NaN;
    Neff = NaN;
    return;
end

yc = y-mean(y);
den = sum(yc.^2);
if den <= 0
    rho1 = 0;
    tauInt = 1;
    Neff = n;
    return;
end

maxLag = min(n-1, floor(n/2));
rho = zeros(maxLag,1);
for k = 1:maxLag
    rho(k) = sum(yc(1:n-k).*yc(1+k:n))/den;
end
rho1 = rho(1);

% Initial positive sequence simple.
s = 0;
for k = 1:maxLag
    if rho(k) <= 0
        break;
    end
    s = s + rho(k);
end
tauInt = max(1, 1+2*s);
Neff = max(1, n/tauInt);
end

% =========================================================================
% Figures
% =========================================================================
function local_plot_rolling(T, cfg, fileName)
f = figure('Color','w','Position',[100 100 1250 850]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('0493x23e - rolling window %d steps', cfg.rollingWindowSteps));

nexttile;
plot(T.endStep,T.aL,'-o','MarkerSize',3);
grid on; xlabel('step fin'); ylabel('a_L'); title('Pente liquide');

nexttile;
plot(T.endStep,T.aG,'-o','MarkerSize',3);
grid on; xlabel('step fin'); ylabel('a_G'); title('Pente gaz');

nexttile;
plot(T.endStep,T.ratio,'-o','MarkerSize',3); hold on;
plot(T.endStep,T.muRatio,'--','LineWidth',1.2);
grid on; xlabel('step fin'); ylabel('rapport');
legend('a_L/a_G','\mu_G/\mu_L','Location','best');
title('Partage des pentes vs reference visqueuse');

nexttile;
plot(T.endStep,T.Rtau,'-o','MarkerSize',3); hold on;
yline(1,'--');
grid on; xlabel('step fin'); ylabel('R_\tau');
title('R_\tau=(a_L/a_G)/(\mu_G/\mu_L)');

local_save_figure(f,fileName);
end

function local_plot_micro(T, tailMask, cfg, fileName)
f = figure('Color','w','Position',[100 100 1250 850]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('0493x23e - non-overlapping blocks of %d steps', ...
    cfg.microBlockSteps));

local_plot_with_tail_trend(T.midStep,T.ratio,tailMask,'a_L/a_G');
title('Ratio des pentes'); grid on; xlabel('step milieu');

local_plot_with_tail_trend(T.midStep,T.aL,tailMask,'a_L');
title('Pente liquide'); grid on; xlabel('step milieu');

local_plot_with_tail_trend(T.midStep,T.aG,tailMask,'a_G');
title('Pente gaz'); grid on; xlabel('step milieu');

local_plot_with_tail_trend(T.midStep,T.rhoRatio,tailMask,'\rho_G/\rho_L');
title('Rapport de densites bulk'); grid on; xlabel('step milieu');

local_save_figure(f,fileName);
end

function local_plot_with_tail_trend(x,y,tailMask,ylab)
nexttile;
plot(x,y,'o-','MarkerSize',3); hold on;
xt = x(tailMask);
yt = y(tailMask);
[slope,~] = local_trend(xt,yt);
b = mean(yt)-slope*mean(xt);
plot(xt,slope*xt+b,'--','LineWidth',1.4);
xline(min(xt),':');
ylabel(ylab);
end

function local_plot_terminal(T, cfg, fileName)
f = figure('Color','w','Position',[100 100 1250 850]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl, sprintf('0493x23e - estimates ending at step %d', ...
    cfg.analysisEndStep));

nexttile;
plot(T.windowSteps,T.aL,'-o');
grid on; xlabel('longueur fenetre [steps]'); ylabel('a_L');
title('Sensibilite de a_L');

nexttile;
plot(T.windowSteps,T.aG,'-o');
grid on; xlabel('longueur fenetre [steps]'); ylabel('a_G');
title('Sensibilite de a_G');

nexttile;
plot(T.windowSteps,T.ratio,'-o'); hold on;
plot(T.windowSteps,T.muRatio,'--o');
grid on; xlabel('longueur fenetre [steps]'); ylabel('rapport');
legend('a_L/a_G','\mu_G/\mu_L','Location','best');
title('Ratio terminal');

nexttile;
plot(T.windowSteps,T.Rtau,'-o'); hold on;
yline(1,'--');
grid on; xlabel('longueur fenetre [steps]'); ylabel('R_\tau');
title('R_\tau terminal');

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
% I/O
% =========================================================================
function A = local_read_f32(fileName,nx,ny)
fid = fopen(fileName,'r','ieee-le');
if fid < 0
    error('Impossible d''ouvrir %s',fileName);
end
c = onCleanup(@() fclose(fid));
v = fread(fid,nx*ny,'single=>double');
if numel(v) ~= nx*ny
    error('%s : %d valeurs, attendu %d.',fileName,numel(v),nx*ny);
end
% Enregistreur row-major, x varie le plus vite.
A = reshape(v,[nx,ny]).';
end

function val = local_kv_num(txt, keys, defaultVal)
val = defaultVal;
for i = 1:numel(keys)
    key = regexptranslate('escape',keys{i});
    tok = regexp(txt, ['(?m)^\s*' key '\s*=\s*([^\r\n#]+)'], ...
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

% Priorite a un dossier contenant "couette".
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
if v
    s = 'PASS';
else
    s = 'FAIL';
end
end

function local_print_estimate(fid,e)
fprintf(fid,'frames = %d\n',e.nFrames);
fprintf(fid,'aL = %.12g, R2L = %.10g\n',e.aL,e.R2L);
fprintf(fid,'aG = %.12g, R2G = %.10g\n',e.aG,e.R2G);
fprintf(fid,'aL/aG = %.12g\n',e.ratio);
fprintf(fid,'rhoL = %.12g, rhoG = %.12g, rhoG/rhoL = %.12g\n', ...
    e.rhoL,e.rhoG,e.rhoRatio);
fprintf(fid,'muG/muL = %.12g\n',e.muRatio);
fprintf(fid,'Rtau = %.12g\n',e.Rtau);
fprintf(fid,'interface slip/Uw = %+.12g\n',e.slipOverUw);
fprintf(fid,'gas wall slip/Uw = %+.12g\n',e.wallSlipOverUw);
fprintf(fid,'common-mode RMS/Uw = %.12g\n',e.evenRmsOverUw);
fprintf(fid,'uy mean-profile RMS/Uw = %.12g\n',e.uyRmsOverUw);
end

function analyze_0493x14ai_n2_article(runRoot)
%ANALYZE_0493X14AI_N2_ARTICLE
% Article-only post-processing of the historical x14ai-fix1 two-phase n=2
% oscillating-drop reproduction.
%
% This file does NOT redefine or refit the qualified frequency.  The values
% omega, beta, R2 and Gomega are read from the output of the historical
% analyzer analyze_0493x14x_oscillating_drop_n2.py.
%
% It produces:
%   1) article_n2_mode.pdf/png:
%      the x9f signed second-moment deformation, with the historical damped
%      fit frequency/beta imposed (only amplitude/phase/offset are projected
%      for visualization).
%   2) article_n2_total_momentum.pdf/png:
%      total two-phase momentum drift reconstructed from species_runtime.
%   3) article_n2_summary.csv and article_n2_report.txt.
%
% Historical reference reproduced by the original x14ai-fix1 run:
%   grid 400x400, R/h=40, eps=0.04, sigma=2560
%   mL=1, mG=0.1, kBTL=0.02, kBTG=0.08, dt=0.002
%   seed=493180, 0<t<=4 (2000 steps)
%   omega=1.6375276, Gomega=0.9798833
%   beta=0.1694319, R2=0.997111
%   max total-momentum drift=5.08e-11
%
% Run from repository matlab/:
%   analyze_0493x14ai_n2_article('../runs/0493x14ai_n2_article_reproduction_seed493180')
%
% IMPORTANT METROLOGY NOTE
% The quantitative values reported in the paper must come from the historical
% analyzer output.  The signed shape observable below is only used to draw the
% trace.  It is the x-oriented component of the x9f second-moment ellipticity:
%       q2_display = ellipticity * cos(2*principalAngle).
% This follows the historical x9f definition (ellipticity + principal angle).
% The plotting script does not optimize omega or beta.

if nargin < 1 || strlength(string(runRoot)) == 0
    runRoot = '../runs/0493x14ai_n2_article_reproduction_seed493180';
end
runRoot = char(runRoot);
assert(isfolder(runRoot), 'Run root not found: %s', runRoot);

outDir = fullfile(runRoot, 'article_figures');
if ~isfolder(outDir), mkdir(outDir); end

reportPath = localOneRecursive(runRoot, 'oscillating_drop_n2_report*.txt', true);
shapePath  = localOneRecursive(runRoot, 'cuda_ellipse_shape_0493x9f.csv', true);
speciesPath = localOneRecursive(runRoot, 'species_runtime*.csv', true);
provPath = localOneRecursive(runRoot, 'article_reproduction_provenance.txt', false);

reportText = fileread(reportPath);

omega0 = localRx(reportText, ...
    'theory2D\.twoFluid[^\n]*omega0=([0-9eE+\-.]+)', 'omega0');
period0 = localRx(reportText, ...
    'theory2D\.twoFluid[^\n]*period0=([0-9eE+\-.]+)', 'period0');
omega = localRx(reportText, ...
    'fit[^\n]*omega=([0-9eE+\-.]+)', 'omega');
beta = localRx(reportText, ...
    'fit[^\n]*betaMeasured=([0-9eE+\-.]+)', 'betaMeasured');
R2 = localRx(reportText, ...
    'fit[^\n]*R2=([0-9eE+\-.]+)', 'R2');
Gomega = localRx(reportText, ...
    'gain[^\n]*Gomega=([0-9eE+\-.]+)', 'Gomega');

kBTL = localRxOptional(reportText, ...
    'liquid[^\n]*kBTmean=([0-9eE+\-.]+)');
kBTG = localRxOptional(reportText, ...
    'gas[^\n]*kBTmean=([0-9eE+\-.]+)');
clipMax = localRxOptional(reportText, ...
    'limiter[^\n]*maxClipFraction=([0-9eE+\-.]+)');

% -------------------------------------------------------------------------
% Figure 1: signed n=2 deformation and historical qualified fit.
% -------------------------------------------------------------------------
S = readtable(shapePath, 'VariableNamingRule', 'preserve');
[t,~] = localColumn(S, {'time'});
[ell,ellName] = localColumn(S, {'ellipticity','momentEllipticity'});
[theta,thetaName] = localColumn(S, ...
    {'principalAngle','principalAngleRadians','principalAngleRad', ...
     'momentPrincipalAngle','momentAngle','momentAngleRadians','momentAngleDegrees', ...
     'principalAngleDegrees','principalAngleDeg','angle','angleRadians','angleDegrees','angleDeg'});

t = double(t(:));
ell = double(ell(:));
theta = double(theta(:));

% Preserve the CSV's convention whenever its name gives the unit.  If the
% header is unit-less, infer degrees only if values cannot reasonably be rad.
lname = lower(thetaName);
if contains(lname,'deg') || max(abs(theta),[],'omitnan') > 2*pi + 0.25
    theta = theta*pi/180;
end

q2 = ell .* cos(2*theta);

valid = isfinite(t) & isfinite(q2);
t = t(valid); q2 = q2(valid);
[t,ord] = sort(t); q2 = q2(ord);

% Historical report fits 0<t<=4.  Do not extend the article trace beyond it.
mask = t > 0 & t <= 4 + 1e-12;
tf = t(mask); qf = q2(mask);
assert(numel(tf) >= 12, 'Not enough x9f samples in 0<t<=4.');

% Project only C,D,offset at the historical omega and beta.  omega and beta
% themselves are NOT refitted.
tau = tf - tf(1);
E = exp(-beta*tau);
X = [E.*cos(omega*tau), E.*sin(omega*tau), ones(size(tau))];
coef = X \ qf;
qfit = X*coef;

f1 = figure('Visible','off','Color','w','Name','x14ai n2 mode');
plot(tf/period0, qf, 'o-', 'DisplayName','SRC-MPCD');
hold on;
plot(tf/period0, qfit, '-', 'LineWidth',1.5, ...
    'DisplayName',sprintf('damped fit: \\omega/\\omega_{th}=%.4f',Gomega));
xline(1.0,'--','DisplayName','T_{th}');
hold off;
xlabel('t/T_{2,th}');
ylabel('signed n=2 second-moment deformation');
grid on;
legend('Location','best');
title(sprintf('Two-phase oscillating drop n=2: G_\\omega=%.4f, R^2=%.4f', ...
    Gomega,R2));
localExport(f1, outDir, 'article_n2_mode');
close(f1);

% Save the plotted trace so every point in the figure is auditable.
traceTable = table(tf, tf/period0, qf, qfit, ...
    'VariableNames',{'time','timeOverTheoryPeriod','q2Display','historicalFitDisplay'});
writetable(traceTable, fullfile(outDir,'article_n2_mode_trace.csv'));

% -------------------------------------------------------------------------
% Figure 2: total momentum conservation from species_runtime.
% -------------------------------------------------------------------------
P = readtable(speciesPath, 'VariableNamingRule', 'preserve');
[pt,~] = localColumn(P, {'time'});
[px,py] = localMomentumColumns(P);

pt = double(pt(:));
px = double(px(:)); py = double(py(:));
valid = isfinite(pt) & isfinite(px) & isfinite(py);
pt = pt(valid); px = px(valid); py = py(valid);

[ut,~,g] = unique(pt,'sorted');
sumPx = accumarray(g,px,[],@sum);
sumPy = accumarray(g,py,[],@sum);
dPx = sumPx - sumPx(1);
dPy = sumPy - sumPy(1);
dP = hypot(dPx,dPy);
maxDrift = max(dP);

f2 = figure('Visible','off','Color','w','Name','x14ai n2 momentum');
plot(ut/period0, dPx, '-', 'DisplayName','\Delta P_x');
hold on;
plot(ut/period0, dPy, '-', 'DisplayName','\Delta P_y');
plot(ut/period0, dP,  '-', 'DisplayName','|\Delta P|');
hold off;
xlabel('t/T_{2,th}');
ylabel('total momentum drift');
grid on;
legend('Location','best');
title(sprintf('Two-phase total-momentum conservation: max |\\Delta P|=%.3e',maxDrift));
localExport(f2, outDir, 'article_n2_total_momentum');
close(f2);

momentumTable = table(ut,ut/period0,sumPx,sumPy,dPx,dPy,dP, ...
    'VariableNames',{'time','timeOverTheoryPeriod','PxTotal','PyTotal', ...
                     'deltaPx','deltaPy','deltaPNorm'});
writetable(momentumTable, fullfile(outDir,'article_n2_total_momentum_trace.csv'));

% -------------------------------------------------------------------------
% Article summary: current reproduction vs immutable historical reference.
% -------------------------------------------------------------------------
historicalOmega = 1.6375276;
historicalGomega = 0.9798833;
historicalBeta = 0.1694319;
historicalR2 = 0.997111;
historicalMaxMomentumDrift = 5.08e-11;

summary = table(omega0,period0,omega,Gomega,beta,R2,kBTL,kBTG,clipMax,maxDrift, ...
    historicalOmega,historicalGomega,historicalBeta,historicalR2, ...
    historicalMaxMomentumDrift, ...
    omega-historicalOmega,Gomega-historicalGomega,beta-historicalBeta,R2-historicalR2, ...
    'VariableNames',{ ...
    'omegaTheoryTwoFluid','periodTheoryTwoFluid','omegaMeasured','GomegaMeasured', ...
    'betaMeasured','R2','kBTLiquidMean','kBTGasMean','maxClipFraction', ...
    'maxTotalMomentumDrift','historicalOmega','historicalGomega','historicalBeta', ...
    'historicalR2','historicalMaxTotalMomentumDrift','deltaOmegaVsHistorical', ...
    'deltaGomegaVsHistorical','deltaBetaVsHistorical','deltaR2VsHistorical'});
writetable(summary, fullfile(outDir,'article_n2_summary.csv'));

fid = fopen(fullfile(outDir,'article_n2_report.txt'),'w');
assert(fid>=0,'Cannot create article report.');
fprintf(fid,'===== 0493x14ai-fix1 TWO-PHASE n=2 — ARTICLE REPRODUCTION =====\n');
fprintf(fid,'runRoot=%s\n',runRoot);
fprintf(fid,'historicalAnalyzerReport=%s\n',reportPath);
fprintf(fid,'shapeCSV=%s\n',shapePath);
fprintf(fid,'speciesRuntimeCSV=%s\n',speciesPath);
if ~isempty(provPath), fprintf(fid,'provenance=%s\n',provPath); end
fprintf(fid,'displayObservable=%s*cos(2*%s)\n',ellName,thetaName);
fprintf(fid,'theory omega=%.12g period=%.12g\n',omega0,period0);
fprintf(fid,'reproduction omega=%.12g Gomega=%.12g beta=%.12g R2=%.12g\n', ...
    omega,Gomega,beta,R2);
fprintf(fid,'reproduction kBTL=%.12g kBTG=%.12g maxClipFraction=%.12g\n', ...
    kBTL,kBTG,clipMax);
fprintf(fid,'reproduction maxTotalMomentumDrift=%.12g\n',maxDrift);
fprintf(fid,'historicalReference omega=1.6375276 Gomega=0.9798833 beta=0.1694319 R2=0.997111 maxTotalMomentumDrift=5.08e-11\n');
fprintf(fid,'deltaVsHistorical dOmega=%+.6e dGomega=%+.6e dBeta=%+.6e dR2=%+.6e\n', ...
    omega-historicalOmega,Gomega-historicalGomega,beta-historicalBeta,R2-historicalR2);
fprintf(fid,'IMPORTANT: omega/beta/R2/Gomega are read from the historical analyzer output; this MATLAB file does not refit them.\n');
fclose(fid);

% Direct LaTeX-ready row, deliberately descriptive rather than a new PASS gate.
fid = fopen(fullfile(outDir,'article_n2_table_row.tex'),'w');
if fid>=0
    fprintf(fid,'$n=2$ & %.4f & %.4f & %.4f & %.4f & %.2e \\\\\n', ...
        Gomega,beta,R2,omega,maxDrift);
    fclose(fid);
end

fprintf('\n===== 0493x14ai-fix1 n=2 ARTICLE OUTPUT =====\n');
fprintf('historical reference: Gomega=0.9798833, beta=0.1694319, R2=0.997111\n');
fprintf('reproduction:         Gomega=%.8f, beta=%.8f, R2=%.8f\n',Gomega,beta,R2);
fprintf('max |delta P_total| = %.6e\n',maxDrift);
fprintf('figures: %s\n',outDir);
fprintf('summary: %s\n',fullfile(outDir,'article_n2_summary.csv'));
end

% =========================================================================
% Local helpers
% =========================================================================
function path = localOneRecursive(root,pattern,required)
d = dir(fullfile(root,'**',pattern));
d = d(~[d.isdir]);
if isempty(d)
    if required
        error('Required file not found under %s: %s',root,pattern);
    else
        path = '';
        return
    end
end
if numel(d) > 1
    % A reproduction must not silently mix runs.
    names = string(fullfile({d.folder},{d.name}));
    error('Expected one %s under %s, found %d:\n%s',pattern,root,numel(d),join(names,newline));
end
path = fullfile(d(1).folder,d(1).name);
end

function value = localRx(txt,pattern,label)
tok = regexp(txt,pattern,'tokens','once');
assert(~isempty(tok),'Could not parse %s from historical analyzer report.',label);
value = str2double(tok{1});
assert(isfinite(value),'Non-finite %s parsed from historical analyzer report.',label);
end

function value = localRxOptional(txt,pattern)
tok = regexp(txt,pattern,'tokens','once');
if isempty(tok)
    value = NaN;
else
    value = str2double(tok{1});
end
end

function [v,name] = localColumn(T,candidates)
vars = string(T.Properties.VariableNames);
normVars = lower(regexprep(vars,'[^a-zA-Z0-9]',''));
for k=1:numel(candidates)
    target = lower(regexprep(string(candidates{k}),'[^a-zA-Z0-9]',''));
    j = find(normVars==target,1);
    if ~isempty(j)
        name = char(vars(j));
        v = T.(name);
        return
    end
end
error('Missing required column. Candidates: %s. Available: %s', ...
      strjoin(candidates,', '), strjoin(cellstr(vars),', '));
end

function [px,py] = localMomentumColumns(T)
% Prefer explicit momentum columns.  Fall back to totalMass*meanV, which is
% the historical species_runtime reconstruction used for this validation.
try
    [px,~] = localColumn(T,{'totalMomentumX','momentumX','Px','totalPx'});
    [py,~] = localColumn(T,{'totalMomentumY','momentumY','Py','totalPy'});
    return
catch
end
[mass,~] = localColumn(T,{'totalMass','massTotal','speciesMass'});
[vx,~] = localColumn(T,{'meanVx','meanVelocityX','uxMean'});
[vy,~] = localColumn(T,{'meanVy','meanVelocityY','uyMean'});
px = double(mass).*double(vx);
py = double(mass).*double(vy);
end

function localExport(fig,outDir,stem)
pngPath = fullfile(outDir,[stem '.png']);
pdfPath = fullfile(outDir,[stem '.pdf']);
set(fig,'PaperPositionMode','auto');
print(fig,pngPath,'-dpng','-r300');
print(fig,pdfPath,'-dpdf','-painters');
end

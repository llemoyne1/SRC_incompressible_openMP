function out = analyze_vk_nondim_0493x8j(varargin)
%ANALYZE_VK_NONDIM_0493X8J Nondimensionalize the established confined VK wake.
%
% Run from the repository ./matlab directory.
%
% Default inputs are the outputs of analyze_vk_established_0493x8i:
%   ../runs/0493x8i_vk_established_analysis/vk_established_fields_0493x8i.mat
%   ../runs/0493x8i_vk_established_analysis/vk_established_summary_0493x8i.csv
%
% The goal is to define the upstream velocity scale explicitly before a
% literature comparison.  At several sections upstream of the cylinder this
% analyzer measures:
%   Ub    bulk/section-mean streamwise velocity
%   Uc    velocity interpolated at the channel centreline y=H/2
%   Umax  maximum of the time-mean section profile
%   UcFit amplitude of a least-squares plane-Poiseuille profile
%
% It then reports Re and St using Ub, Uc and Umax, together with the measured
% wavelength and vortex convection speed from x8i.  The profile fit is a
% diagnostic only: a poor Poiseuille fit does not stop the analysis.
%
% Typical use:
%   out = analyze_vk_nondim_0493x8j;
%
% Useful overrides:
%   out = analyze_vk_nondim_0493x8j( ...
%       'SectionXD',[-2.0 -1.5 -1.0], ...
%       'ReferenceSectionXD',-1.5, ...
%       'ShowFigures',true);

p = inputParser;
p.FunctionName = 'analyze_vk_nondim_0493x8j';
addParameter(p,'FieldsFile','../runs/0493x8i_vk_established_analysis2/vk_established_fields_0493x8i.mat');
addParameter(p,'SummaryFile','../runs/0493x8i_vk_established_analysis2/vk_established_summary_0493x8i.csv');
addParameter(p,'OutputDir','../runs/0493x8j_vk_nondim_analysis2');
addParameter(p,'CylinderCx',0.9375);
addParameter(p,'CylinderD',0.3125);
addParameter(p,'SectionXD',[-2.0 -1.5 -1.0]);
addParameter(p,'ReferenceSectionXD',-1.5);
addParameter(p,'SectionHalfWidthD',0.05);
addParameter(p,'MakePlots',true);
addParameter(p,'ShowFigures',true);
addParameter(p,'MinLocalStep',-inf);
addParameter(p,'MaxLocalStep',inf);
parse(p,varargin{:});
opt = p.Results;

fieldsFile = char(opt.FieldsFile);
summaryFile = char(opt.SummaryFile);
outDir = char(opt.OutputDir);
if ~isfile(fieldsFile)
    error('0493x8j:missingFields','x8i fields file not found: %s',fieldsFile);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

S = load(fieldsFile,'x','y','meanUx','meanUy','summary');
if ~isfield(S,'x') || ~isfield(S,'y') || ~isfield(S,'meanUx')
    error('0493x8j:missingCoreFields','x8i MAT file does not contain x, y and meanUx.');
end

x = double(S.x(:).');
y = double(S.y(:));
meanUx = double(S.meanUx);
if size(meanUx,1) ~= numel(y) || size(meanUx,2) ~= numel(x)
    if size(meanUx,1) == numel(x) && size(meanUx,2) == numel(y)
        meanUx = meanUx.';
        warning('0493x8j:transposeMeanUx','meanUx was transposed to match y-by-x layout.');
    else
        error('0493x8j:fieldShape','meanUx dimensions do not match x and y.');
    end
end

T = table();
if isfield(S,'summary') && istable(S.summary) && ~isempty(S.summary)
    T = S.summary;
elseif isfile(summaryFile)
    try
        T = readtable(summaryFile);
    catch
        warning('0493x8j:summaryRead','Could not read x8i summary CSV; using supplied/default scales where possible.');
    end
else
    warning('0493x8j:noSummary','x8i summary is unavailable; some wake quantities will be NaN.');
end

D = double(opt.CylinderD);
xc = double(opt.CylinderCx);
Ly = local_table_scalar_0493x8j(T,'Ly',max(y)-min(y));
if ~isfinite(Ly) || Ly <= 0
    if numel(y) > 1
        Ly = max(y)-min(y)+median(diff(y));
    else
        Ly = 1;
    end
end
H = Ly;
yc = 0.5*H;
nu = local_table_scalar_0493x8j(T,'nuRef',6.7432658123431854e-4);
fPod = local_table_scalar_0493x8j(T,'fPod',NaN);
fProbe = local_table_scalar_0493x8j(T,'fProbe',NaN);
lambdaOverD = local_table_scalar_0493x8j(T,'lambdaOverD',NaN);
cVortex = local_table_scalar_0493x8j(T,'vortexConvectionSpeed',NaN);
UrefX8i = local_table_scalar_0493x8j(T,'Uref',0.18);
UupX8i = local_table_scalar_0493x8j(T,'UupMean',NaN);

freqs = [fPod fProbe];
freqs = freqs(isfinite(freqs) & freqs > 0);
if isempty(freqs)
    fPrimary = NaN;
elseif numel(freqs) == 1
    fPrimary = freqs(1);
else
    fPrimary = mean(freqs);
end

sectionXD = double(opt.SectionXD(:));
nSec = numel(sectionXD);
sectionXTarget = xc + sectionXD*D;
sectionXActual = nan(nSec,1);
sectionCols = cell(nSec,1);
profiles = nan(numel(y),nSec);
Ub = nan(nSec,1);
Uc = nan(nSec,1);
Umax = nan(nSec,1);
UcFit = nan(nSec,1);
poiseuilleR2 = nan(nSec,1);
poiseuilleNRMSE = nan(nSec,1);
UcOverUb = nan(nSec,1);
UmaxOverUb = nan(nSec,1);

halfWidth = max(0,double(opt.SectionHalfWidthD))*D;
phiP = 1-(2*y/H-1).^2;
phiP = max(phiP,0);

for i = 1:nSec
    cols = find(abs(x-sectionXTarget(i)) <= halfWidth);
    if isempty(cols)
        [~,ix0] = min(abs(x-sectionXTarget(i)));
        cols = ix0;
    end
    sectionCols{i} = cols;
    sectionXActual(i) = mean(x(cols));
    u = mean(meanUx(:,cols),2,'omitnan');
    profiles(:,i) = u;

    good = isfinite(u);
    if nnz(good) < 4
        warning('0493x8j:sparseProfile','Section %.3gD has too few finite profile values.',sectionXD(i));
        continue;
    end

    % Cell-centre rectangle rule: for a uniform y grid this is the natural
    % section bulk velocity associated with the recorded finite-volume field.
    Ub(i) = mean(u(good));

    % Interpolate the measured profile to the exact channel centreline.
    try
        Uc(i) = interp1(y(good),u(good),yc,'linear','extrap');
    catch
        [~,iy0] = min(abs(y-yc));
        Uc(i) = u(iy0);
    end
    Umax(i) = max(u(good));

    % One-parameter plane-Poiseuille fit u = UcFit*[1-(2y/H-1)^2].
    pg = phiP(good);
    ug = u(good);
    den = pg.'*pg;
    if den > 0
        UcFit(i) = (pg.'*ug)/den;
        ufit = UcFit(i)*pg;
        poiseuilleR2(i) = local_r2_0493x8j(ug,ufit);
        poiseuilleNRMSE(i) = sqrt(mean((ug-ufit).^2))/max(abs(Ub(i)),eps);
    end

    if isfinite(Ub(i)) && abs(Ub(i)) > eps
        UcOverUb(i) = Uc(i)/Ub(i);
        UmaxOverUb(i) = Umax(i)/Ub(i);
    end
end

ReB = Ub*D/nu;
ReC = Uc*D/nu;
ReMax = Umax*D/nu;
StB = fPrimary*D./Ub;
StC = fPrimary*D./Uc;
StMax = fPrimary*D./Umax;
cVOverUb = cVortex./Ub;
cVOverUc = cVortex./Uc;
cVOverUmax = cVortex./Umax;

% Reference section is the measured section closest to the requested x/D.
refXDRequested = double(opt.ReferenceSectionXD);
[~,iRef] = min(abs(sectionXD-refXDRequested));
refXD = sectionXD(iRef);

% Aggregate across the measured sections.  This is useful for checking whether
% the nondimensionalization depends strongly on where the upstream profile is
% sampled; it is not used to hide section-to-section variation.
UbMean = local_meanfinite_0493x8j(Ub);
UcMean = local_meanfinite_0493x8j(Uc);
UmaxMean = local_meanfinite_0493x8j(Umax);
UbRelSpread = local_relspread_0493x8j(Ub);
UcRelSpread = local_relspread_0493x8j(Uc);
UmaxRelSpread = local_relspread_0493x8j(Umax);
UcOverUbMean = local_meanfinite_0493x8j(UcOverUb);
poiseuilleR2Mean = local_meanfinite_0493x8j(poiseuilleR2);
poiseuilleNRMSEMean = local_meanfinite_0493x8j(poiseuilleNRMSE);

% A direct profile average across the selected upstream sections.
meanIncidentProfile = mean(profiles,2,'omitnan');
UbProfileMean = local_meanfinite_0493x8j(meanIncidentProfile);
try
    UcProfileMean = interp1(y(isfinite(meanIncidentProfile)),meanIncidentProfile(isfinite(meanIncidentProfile)),yc,'linear','extrap');
catch
    UcProfileMean = UcMean;
end
UmaxProfileMean = max(meanIncidentProfile(isfinite(meanIncidentProfile)));
if isempty(UmaxProfileMean)
    UmaxProfileMean = NaN;
end

ReBMean = UbMean*D/nu;
ReCMean = UcMean*D/nu;
StBMean = fPrimary*D/UbMean;
StCMean = fPrimary*D/UcMean;
cVOverUbMean = cVortex/UbMean;
cVOverUcMean = cVortex/UcMean;

sectionTable = table(sectionXD,sectionXTarget,sectionXActual,Ub,Uc,Umax,UcFit, ...
    UcOverUb,UmaxOverUb,poiseuilleR2,poiseuilleNRMSE, ...
    ReB,ReC,ReMax,StB,StC,StMax,cVOverUb,cVOverUc,cVOverUmax, ...
    'VariableNames',{'sectionXD','xTarget','xActual','Ub','Uc','Umax','UcPoiseuilleFit', ...
    'UcOverUb','UmaxOverUb','poiseuilleR2','poiseuilleNRMSE', ...
    'ReB','ReC','ReMax','StB','StC','StMax','cVOverUb','cVOverUc','cVOverUmax'});

profileTable = table(y,y/H,'VariableNames',{'y','yOverH'});
for i = 1:nSec
    tag = local_xd_tag_0493x8j(sectionXD(i));
    profileTable.(['ux_' tag]) = profiles(:,i);
    if isfinite(Ub(i)) && abs(Ub(i)) > eps
        profileTable.(['uxOverUb_' tag]) = profiles(:,i)/Ub(i);
    else
        profileTable.(['uxOverUb_' tag]) = nan(size(y));
    end
    if isfinite(Uc(i)) && abs(Uc(i)) > eps
        profileTable.(['uxOverUc_' tag]) = profiles(:,i)/Uc(i);
    else
        profileTable.(['uxOverUc_' tag]) = nan(size(y));
    end
end
profileTable.uxMeanSections = meanIncidentProfile;
profileTable.poiseuilleShape = phiP;

summary = table( ...
    D,H,D/H,xc,nu,UrefX8i,UupX8i,fPod,fProbe,fPrimary,lambdaOverD,cVortex, ...
    refXD,Ub(iRef),Uc(iRef),Umax(iRef),UcFit(iRef),UcOverUb(iRef), ...
    poiseuilleR2(iRef),poiseuilleNRMSE(iRef), ...
    ReB(iRef),ReC(iRef),ReMax(iRef),StB(iRef),StC(iRef),StMax(iRef), ...
    cVOverUb(iRef),cVOverUc(iRef),cVOverUmax(iRef), ...
    UbMean,UcMean,UmaxMean,UbRelSpread,UcRelSpread,UmaxRelSpread,UcOverUbMean, ...
    poiseuilleR2Mean,poiseuilleNRMSEMean,ReBMean,ReCMean,StBMean,StCMean, ...
    cVOverUbMean,cVOverUcMean,UbProfileMean,UcProfileMean,UmaxProfileMean, ...
    'VariableNames',{ ...
    'D','H','blockageDoverH','cylinderCx','nu','UrefX8i','UupX8i','fPod','fProbe','fPrimary','lambdaOverD','vortexConvectionSpeed', ...
    'referenceSectionXD','UbRef','UcRef','UmaxRef','UcPoiseuilleFitRef','UcOverUbRef', ...
    'poiseuilleR2Ref','poiseuilleNRMSERef', ...
    'ReBRef','ReCRef','ReMaxRef','StBRef','StCRef','StMaxRef', ...
    'cVOverUbRef','cVOverUcRef','cVOverUmaxRef', ...
    'UbMeanSections','UcMeanSections','UmaxMeanSections','UbRelativeSpread','UcRelativeSpread','UmaxRelativeSpread','UcOverUbMeanSections', ...
    'poiseuilleR2MeanSections','poiseuilleNRMSEMeanSections','ReBMeanSections','ReCMeanSections','StBMeanSections','StCMeanSections', ...
    'cVOverUbMeanSections','cVOverUcMeanSections','UbMeanProfile','UcMeanProfile','UmaxMeanProfile'});

writetable(sectionTable,fullfile(outDir,'vk_nondim_sections_0493x8j.csv'));
writetable(profileTable,fullfile(outDir,'vk_nondim_profiles_0493x8j.csv'));
writetable(summary,fullfile(outDir,'vk_nondim_summary_0493x8j.csv'));

plotFiles = strings(0,1);
if logical(opt.MakePlots)
    vis = 'off';
    if logical(opt.ShowFigures)
        vis = 'on';
    end

    % 1) Upstream profiles in the literature-friendly channel coordinates.
    f1 = figure('Visible',vis,'Color','w','Name','0493x8j upstream profiles');
    tiledlayout(f1,1,2,'Padding','compact','TileSpacing','compact');
    nexttile; hold on; grid on;
    for i = 1:nSec
        plot(profiles(:,i)/Ub(i),y/H,'LineWidth',1.2,'DisplayName',sprintf('x-x_c=%.1fD',sectionXD(i)));
    end
    plot(1.5*phiP,y/H,'k--','LineWidth',1.3,'DisplayName','Poiseuille: u/U_b=1.5\phi');
    xlabel('u/U_b'); ylabel('y/H');
    title('Upstream profile: bulk scaling');
    legend('Location','best');

    nexttile; hold on; grid on;
    for i = 1:nSec
        plot(profiles(:,i)/Uc(i),y/H,'LineWidth',1.2,'DisplayName',sprintf('x-x_c=%.1fD',sectionXD(i)));
    end
    plot(phiP,y/H,'k--','LineWidth',1.3,'DisplayName','Poiseuille');
    xlabel('u/U_c'); ylabel('y/H');
    title('Upstream profile: centreline scaling');
    legend('Location','best');
    sgtitle(sprintf('Confined VK upstream profile | D/H=%.3f',D/H));
    plotFiles(end+1,1) = string(local_export_figure_0493x8j(f1,fullfile(outDir,'vk_nondim_upstream_profiles_0493x8j'))); %#ok<AGROW>

    % 2) Section dependence of the velocity scales and shape diagnostics.
    f2 = figure('Visible',vis,'Color','w','Name','0493x8j section sensitivity');
    tiledlayout(f2,2,2,'Padding','compact','TileSpacing','compact');
    nexttile; hold on; grid on;
    plot(sectionXD,Ub,'o-','LineWidth',1.2,'DisplayName','U_b');
    plot(sectionXD,Uc,'o-','LineWidth',1.2,'DisplayName','U_c');
    plot(sectionXD,Umax,'o-','LineWidth',1.2,'DisplayName','U_{max}');
    xlabel('(x-x_c)/D'); ylabel('velocity'); legend('Location','best'); title('Velocity scales');

    nexttile; hold on; grid on;
    plot(sectionXD,UcOverUb,'o-','LineWidth',1.2,'DisplayName','U_c/U_b');
    yline(1.5,'--','DisplayName','Poiseuille 3/2');
    xlabel('(x-x_c)/D'); ylabel('ratio'); legend('Location','best'); title('Profile shape ratio');

    nexttile; hold on; grid on;
    plot(sectionXD,poiseuilleR2,'o-','LineWidth',1.2,'DisplayName','R^2');
    plot(sectionXD,poiseuilleNRMSE,'o-','LineWidth',1.2,'DisplayName','NRMSE');
    xlabel('(x-x_c)/D'); ylabel('fit metric'); legend('Location','best'); title('Poiseuille fit');

    nexttile; hold on; grid on;
    plot(ReB,StB,'o-','LineWidth',1.2,'DisplayName','bulk scale');
    plot(ReC,StC,'s-','LineWidth',1.2,'DisplayName','centreline scale');
    xlabel('Re'); ylabel('St'); legend('Location','best'); title('Same wake under velocity conventions');
    sgtitle('Upstream-section sensitivity');
    plotFiles(end+1,1) = string(local_export_figure_0493x8j(f2,fullfile(outDir,'vk_nondim_section_sensitivity_0493x8j'))); %#ok<AGROW>
end

out = struct();
out.summary = summary;
out.sections = sectionTable;
out.profiles = profileTable;
out.outputDir = string(outDir);
out.plotFiles = plotFiles;

fprintf('\n===== 0493x8j VK NONDIMENSIONALIZATION =====\n');
fprintf('D/H=%.8g | D=%.8g H=%.8g | nu=%.9g\n',D/H,D,H,nu);
fprintf('frequency fPrimary=%.9g (POD=%.9g probe=%.9g) | lambda/D=%.6g\n', ...
    fPrimary,fPod,fProbe,lambdaOverD);
fprintf('reference section requested=%.3gD used=%.3gD x=%.8g\n',refXDRequested,refXD,sectionXActual(iRef));
fprintf('  Ub=%.8g Uc=%.8g Umax=%.8g Uc/Ub=%.6g\n',Ub(iRef),Uc(iRef),Umax(iRef),UcOverUb(iRef));
fprintf('  Poiseuille fit: UcFit=%.8g R2=%.6g NRMSE=%.6g\n',UcFit(iRef),poiseuilleR2(iRef),poiseuilleNRMSE(iRef));
fprintf('  bulk:       Re_b=%.6g St_b=%.6g c_v/Ub=%.6g\n',ReB(iRef),StB(iRef),cVOverUb(iRef));
fprintf('  centreline: Re_c=%.6g St_c=%.6g c_v/Uc=%.6g\n',ReC(iRef),StC(iRef),cVOverUc(iRef));
fprintf('section means: Ub=%.8g Uc=%.8g Uc/Ub=%.6g\n',UbMean,UcMean,UcOverUbMean);
fprintf('section relative spread: Ub=%.4g Uc=%.4g Umax=%.4g\n',UbRelSpread,UcRelSpread,UmaxRelSpread);
fprintf('mean nondim: Re_b=%.6g St_b=%.6g | Re_c=%.6g St_c=%.6g\n',ReBMean,StBMean,ReCMean,StCMean);
fprintf('summary=%s\n',fullfile(outDir,'vk_nondim_summary_0493x8j.csv'));
fprintf('sections=%s\n',fullfile(outDir,'vk_nondim_sections_0493x8j.csv'));
fprintf('profiles=%s\n',fullfile(outDir,'vk_nondim_profiles_0493x8j.csv'));
fprintf('status=COMPLETE\n');
end

% =========================================================================
function v = local_table_scalar_0493x8j(T,name,defaultValue)
v = defaultValue;
if ~istable(T) || isempty(T) || ~ismember(name,T.Properties.VariableNames)
    return;
end
x = T.(name);
if isnumeric(x) || islogical(x)
    x = double(x(1));
elseif iscell(x)
    x = str2double(string(x{1}));
else
    x = str2double(string(x(1)));
end
if isfinite(x)
    v = x;
end
end

function r2 = local_r2_0493x8j(y,yfit)
y = double(y(:));
yfit = double(yfit(:));
good = isfinite(y) & isfinite(yfit);
y = y(good); yfit = yfit(good);
if numel(y) < 3
    r2 = NaN;
    return;
end
ssr = sum((y-yfit).^2);
sst = sum((y-mean(y)).^2);
if sst <= eps
    r2 = NaN;
else
    r2 = 1-ssr/sst;
end
end

function m = local_meanfinite_0493x8j(v)
v = double(v(:));
v = v(isfinite(v));
if isempty(v)
    m = NaN;
else
    m = mean(v);
end
end

function s = local_relspread_0493x8j(v)
v = double(v(:));
v = v(isfinite(v));
if numel(v) < 2
    s = NaN;
    return;
end
m = mean(v);
if abs(m) <= eps
    s = NaN;
else
    s = (max(v)-min(v))/abs(m);
end
end

function tag = local_xd_tag_0493x8j(xd)
s = sprintf('%.3f',xd);
s = strrep(s,'-','m');
s = strrep(s,'.','p');
s = regexprep(s,'0+$','');
s = regexprep(s,'p$','');
tag = ['xD_' s];
tag = matlab.lang.makeValidName(tag);
end

function pathOut = local_export_figure_0493x8j(fig,basePath)
pngPath = [basePath '.png'];
try
    exportgraphics(fig,pngPath,'Resolution',180);
catch
    saveas(fig,pngPath);
end
pathOut = pngPath;
end

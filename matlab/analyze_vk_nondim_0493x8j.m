function out = analyze_vk_nondim_0493x8j(varargin)
%ANALYZE_VK_NONDIM_0493X8J Definitive VK nondimensionalization/literature comparison.
%
% Purpose
% -------
% Establish the Q6-G-F confined-cylinder comparison using the velocity and
% nondimensionalization conventions of the two reference papers used for the
% 0493x8m benchmark:
%
% Zovatto & Pedrizzetti, J. Fluid Mech. 440 (2001), 1-25:
%   Re_Z  = Ub*H/nu
%   T*_Z  = T*Ub/H = Ub/(f*H)
%   blockage D/H = 0.2; centred cylinder gamma=2
%   tabulated reference at Re_Z=280: T*_Z=0.83
%
% Sahin & Owens, Phys. Fluids 16 (2004), 1305-1320:
%   Re_SO = Umax,inlet*D/nu
%   St_SO = f*D/Umax,inlet
%   blockage beta=D/H=0.2
%   critical Hopf point (finest M3): Re_crit=69.34, St_crit=0.1567
%
% IMPORTANT: the Sahin-Owens critical point is an onset reference, not a
% same-Re direct benchmark for the present Re_SO=84 flow.  The direct
% frequency comparison at the present operating point is primarily against
% Zovatto-Pedrizzetti.  x8j also converts the Zovatto T* result into the
% Sahin-Owens convention to make the velocity-scale change explicit.
%
% x8j consumes the established wake products from x8i and, when available,
% the rho/flux diagnostic from x8n.  The x8n bulk velocity at -3D is preferred
% as the measured channel bulk scale because it is one diameter from the
% inlet and lies in the post-inlet region where x8n checks flux conservation.
% If x8n files are absent, x8j falls back to the time-mean x8i velocity field.
%
% No physical state is modified.  No hard PASS/FAIL threshold is imposed;
% the script reports signed relative differences and the domain caveat.
%
% Typical use from ./matlab:
%   out = analyze_vk_nondim_0493x8j;
%
% Useful overrides:
%   out = analyze_vk_nondim_0493x8j( ...
%       'TargetUb',0.12083932335718987, ...
%       'ReferenceSectionXD',-3.0, ...
%       'ShowFigures',true);

p = inputParser;
p.FunctionName = 'analyze_vk_nondim_0493x8j';

runRoot = 'E:\SRC_MPCD_dev\SRC_GPU-SURF\runs\0493x8u_zovatto_re280_q6-g-f_smoke5000';
recordDir = fullfile(runRoot,'segment_001','src-q6-g-f','output','recordings', ...
    '0493x8m_zovatto_re280_seg001_src-q6-g-f');
x8iDir = fullfile(runRoot,'vk_analysis_v1');

addParameter(p,'FieldsFile',fullfile(x8iDir,'vk_established_fields_0493x8i.mat'));
addParameter(p,'SummaryFile',fullfile(x8iDir,'vk_established_summary_0493x8i.csv'));
addParameter(p,'FluxSectionsFile',fullfile(recordDir,'vk_flux_rho_sections_0493x8n.csv'));
addParameter(p,'FluxSummaryFile',fullfile(recordDir,'vk_flux_rho_summary_0493x8n.csv'));
addParameter(p,'OutputDir',fullfile(runRoot,'vk_analysis_v1','comparison_x8j'));

addParameter(p,'CylinderCx',1.25);
addParameter(p,'CylinderD',0.3125);
addParameter(p,'TargetUb',0.12083932335718987);
addParameter(p,'TargetUmaxFactor',1.5);
addParameter(p,'SectionXD',[-3.8 -3.5 -3.0 -2.5 -2.0 -1.5 -1.0]);
addParameter(p,'ReferenceSectionXD',-3.0);
addParameter(p,'SectionHalfWidthD',0.05);

% Literature constants for the exact comparison point.
addParameter(p,'ZovattoReH',280.0);
addParameter(p,'ZovattoTstar',0.83);
addParameter(p,'ZovattoBlockage',0.20);
addParameter(p,'ZovattoGamma',2.0);
addParameter(p,'ZovattoUpstreamD',15.0);
addParameter(p,'ZovattoDownstreamD',40.0);
addParameter(p,'SahinBeta',0.20);
addParameter(p,'SahinReCrit',69.34);
addParameter(p,'SahinStCrit',0.1567);
addParameter(p,'SahinUpstreamD',40.0);
addParameter(p,'SahinDownstreamD',40.0);
addParameter(p,'PresentUpstreamD',4.0);
addParameter(p,'PresentDownstreamD',11.0);

addParameter(p,'MakePlots',true);
addParameter(p,'ShowFigures',true);
parse(p,varargin{:});
opt = p.Results;

fieldsFile = char(opt.FieldsFile);
summaryFile = char(opt.SummaryFile);
fluxSectionsFile = char(opt.FluxSectionsFile);
fluxSummaryFile = char(opt.FluxSummaryFile);
outDir = char(opt.OutputDir);
if ~isfile(fieldsFile)
    error('0493x8j:missingFields','x8i fields file not found: %s',fieldsFile);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

% -------------------------------------------------------------------------
% x8i established wake products.
% -------------------------------------------------------------------------
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
    catch ME
        warning('0493x8j:summaryRead','Could not read x8i summary CSV (%s).',ME.message);
    end
else
    warning('0493x8j:noSummary','x8i summary is unavailable; some wake quantities will be NaN.');
end

D = double(opt.CylinderD);
xc = double(opt.CylinderCx);
H = local_table_scalar_0493x8j(T,'Ly',max(y)-min(y));
if ~isfinite(H) || H <= 0
    if numel(y) > 1
        H = max(y)-min(y)+median(diff(y));
    else
        H = 1;
    end
end
yc = 0.5*H;
nu = local_table_scalar_0493x8j(T,'nuRef',6.7432658123431854e-4);
fPod = local_table_scalar_0493x8j(T,'fPod',NaN);
fProbe = local_table_scalar_0493x8j(T,'fProbe',NaN);
freqAgreement = local_table_scalar_0493x8j(T,'frequencyAgreementRel',NaN);
podPhaseR2 = local_table_scalar_0493x8j(T,'podPhaseR2',NaN);
podCycles = local_table_scalar_0493x8j(T,'podCycles',NaN);
probeR2Mean = local_table_scalar_0493x8j(T,'probeR2Mean',NaN);
lambdaOverD = local_table_scalar_0493x8j(T,'lambdaOverD',NaN);
cVortex = local_table_scalar_0493x8j(T,'vortexConvectionSpeed',NaN);
UrefX8i = local_table_scalar_0493x8j(T,'Uref',NaN);
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

% -------------------------------------------------------------------------
% Time-mean upstream profiles from x8i fields.  These are diagnostic only;
% the literature comparison does not use local centreline velocity as Re.
% -------------------------------------------------------------------------
sectionXD = double(opt.SectionXD(:));
nSec = numel(sectionXD);
sectionXTarget = xc + sectionXD*D;
sectionXActual = nan(nSec,1);
profiles = nan(numel(y),nSec);
Ub = nan(nSec,1);
Uc = nan(nSec,1);
UmaxLocal = nan(nSec,1);
UcFit = nan(nSec,1);
poiseuilleR2 = nan(nSec,1);
poiseuilleNRMSE = nan(nSec,1);
UcOverUb = nan(nSec,1);
UmaxOverUb = nan(nSec,1);

halfWidth = max(0,double(opt.SectionHalfWidthD))*D;
phiP = max(1-(2*y/H-1).^2,0);

for i = 1:nSec
    cols = find(abs(x-sectionXTarget(i)) <= halfWidth);
    if isempty(cols)
        [~,ix0] = min(abs(x-sectionXTarget(i)));
        cols = ix0;
    end
    sectionXActual(i) = mean(x(cols));
    u = mean(meanUx(:,cols),2,'omitnan');
    profiles(:,i) = u;

    good = isfinite(u);
    if nnz(good) < 4
        warning('0493x8j:sparseProfile','Section %.3gD has too few finite profile values.',sectionXD(i));
        continue;
    end

    Ub(i) = mean(u(good));
    try
        Uc(i) = interp1(y(good),u(good),yc,'linear','extrap');
    catch
        [~,iy0] = min(abs(y-yc));
        Uc(i) = u(iy0);
    end
    UmaxLocal(i) = max(u(good));

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
        UmaxOverUb(i) = UmaxLocal(i)/Ub(i);
    end
end

refXDRequested = double(opt.ReferenceSectionXD);
[~,iRef] = min(abs(sectionXD-refXDRequested));
refXDField = sectionXD(iRef);
UbFieldRef = Ub(iRef);

% -------------------------------------------------------------------------
% x8n flux/rho diagnostic.  Prefer its -3D bulk value when available.
% -------------------------------------------------------------------------
fluxAvailable = false;
fluxSummaryAvailable = false;
fluxSectionXD = nan(0,1);
fluxXFromInletD = nan(0,1);
fluxUb = nan(0,1);
fluxQvOverRef = nan(0,1);
fluxRhoOverRef = nan(0,1);
fluxJrhoOverRef = nan(0,1);
UbFluxRef = NaN;
refXDFlux = NaN;
QvSpreadPost = NaN;
rhoSpreadPost = NaN;
JrhoSpreadPost = NaN;

if isfile(fluxSectionsFile)
    try
        TF = readtable(fluxSectionsFile);
        required = {'sectionXD','Ub'};
        if all(ismember(required,TF.Properties.VariableNames)) && ~isempty(TF)
            fluxSectionXD = double(TF.sectionXD(:));
            fluxUb = double(TF.Ub(:));
            if ismember('xFromInletD',TF.Properties.VariableNames)
                fluxXFromInletD = double(TF.xFromInletD(:));
            else
                fluxXFromInletD = nan(size(fluxSectionXD));
            end
            if ismember('QvOverRef',TF.Properties.VariableNames)
                fluxQvOverRef = double(TF.QvOverRef(:));
            end
            if ismember('rhoOverRef',TF.Properties.VariableNames)
                fluxRhoOverRef = double(TF.rhoOverRef(:));
            end
            if ismember('JrhoOverRef',TF.Properties.VariableNames)
                fluxJrhoOverRef = double(TF.JrhoOverRef(:));
            end
            [~,iFluxRef] = min(abs(fluxSectionXD-refXDRequested));
            UbFluxRef = fluxUb(iFluxRef);
            refXDFlux = fluxSectionXD(iFluxRef);
            fluxAvailable = isfinite(UbFluxRef);
        end
    catch ME
        warning('0493x8j:fluxSectionsRead','Could not read x8n sections CSV (%s).',ME.message);
    end
end

if isfile(fluxSummaryFile)
    try
        TS = readtable(fluxSummaryFile);
        if ~isempty(TS)
            QvSpreadPost = local_table_scalar_0493x8j(TS,'QvRelativeSpreadPostInlet',NaN);
            rhoSpreadPost = local_table_scalar_0493x8j(TS,'rhoRelativeSpreadPostInlet',NaN);
            JrhoSpreadPost = local_table_scalar_0493x8j(TS,'JrhoRelativeSpreadPostInlet',NaN);
            fluxSummaryAvailable = true;
        end
    catch ME
        warning('0493x8j:fluxSummaryRead','Could not read x8n summary CSV (%s).',ME.message);
    end
end

if fluxAvailable
    UbMeasured = UbFluxRef;
    measuredUbSource = sprintf('x8n flux section %.3gD',refXDFlux);
else
    UbMeasured = UbFieldRef;
    measuredUbSource = sprintf('x8i mean field section %.3gD',refXDField);
end

% -------------------------------------------------------------------------
% Definitive literature conventions.
% -------------------------------------------------------------------------
TargetUb = double(opt.TargetUb);
UmaxInlet = double(opt.TargetUmaxFactor)*TargetUb;
beta = D/H;

% Zovatto-Pedrizzetti: channel scale H, bulk U.
ReZTarget = TargetUb*H/nu;
ReZMeasured = UbMeasured*H/nu;
TstarZTarget = TargetUb/(fPrimary*H);
TstarZMeasured = UbMeasured/(fPrimary*H);
TstarZPodTarget = TargetUb/(fPod*H);
TstarZProbeTarget = TargetUb/(fProbe*H);
errReZTargetPct = 100*(ReZTarget/double(opt.ZovattoReH)-1);
errReZMeasuredPct = 100*(ReZMeasured/double(opt.ZovattoReH)-1);
errTstarZTargetPct = 100*(TstarZTarget/double(opt.ZovattoTstar)-1);
errTstarZMeasuredPct = 100*(TstarZMeasured/double(opt.ZovattoTstar)-1);
errTstarZPodPct = 100*(TstarZPodTarget/double(opt.ZovattoTstar)-1);
errTstarZProbePct = 100*(TstarZProbeTarget/double(opt.ZovattoTstar)-1);

% Sahin-Owens: inlet maximum scale, cylinder diameter D.
ReSO = UmaxInlet*D/nu;
StSO = fPrimary*D/UmaxInlet;
StSOPod = fPod*D/UmaxInlet;
StSOProbe = fProbe*D/UmaxInlet;
ReSOOverCrit = ReSO/double(opt.SahinReCrit);
StSOOverCrit = StSO/double(opt.SahinStCrit);

% Convert the Zovatto point to the Sahin-Owens convention.  This is a direct
% change of nondimensionalization of the SAME Zovatto reference point:
% Umax/Ub=1.5 for plane Poiseuille and beta=D/H.
ReSOFromZovatto = double(opt.TargetUmaxFactor)*double(opt.ZovattoBlockage)*double(opt.ZovattoReH);
StSOFromZovatto = double(opt.ZovattoBlockage)/(double(opt.TargetUmaxFactor)*double(opt.ZovattoTstar));
errStSOVsZovattoPct = 100*(StSO/StSOFromZovatto-1);

period = 1/fPrimary;
cvOverTargetUb = cVortex/TargetUb;
cvOverMeasuredUb = cVortex/UbMeasured;

% Legacy local scales retained as diagnostics and explicitly labelled local.
ReDLocalBulk = Ub*D/nu;
ReDLocalCentre = Uc*D/nu;
StDLocalBulk = fPrimary*D./Ub;
StDLocalCentre = fPrimary*D./Uc;

% Aggregate profile diagnostics.
UbMean = local_meanfinite_0493x8j(Ub);
UcMean = local_meanfinite_0493x8j(Uc);
UmaxMean = local_meanfinite_0493x8j(UmaxLocal);
UbRelSpread = local_relspread_0493x8j(Ub);
UcRelSpread = local_relspread_0493x8j(Uc);
UmaxRelSpread = local_relspread_0493x8j(UmaxLocal);
poiseuilleR2Mean = local_meanfinite_0493x8j(poiseuilleR2);
poiseuilleNRMSEMean = local_meanfinite_0493x8j(poiseuilleNRMSE);

% -------------------------------------------------------------------------
% Output tables.
% -------------------------------------------------------------------------
sectionTable = table(sectionXD,sectionXTarget,sectionXActual,Ub,Uc,UmaxLocal,UcFit, ...
    UcOverUb,UmaxOverUb,poiseuilleR2,poiseuilleNRMSE, ...
    ReDLocalBulk,ReDLocalCentre,StDLocalBulk,StDLocalCentre, ...
    'VariableNames',{'sectionXD','xTarget','xActual','Ub','Uc','UmaxLocal','UcPoiseuilleFit', ...
    'UcOverUb','UmaxOverUb','poiseuilleR2','poiseuilleNRMSE', ...
    'ReDLocalBulkDiagnostic','ReDLocalCentreDiagnostic','StDLocalBulkDiagnostic','StDLocalCentreDiagnostic'});

profileTable = table(y,y/H,'VariableNames',{'y','yOverH'});
for i = 1:nSec
    tag = local_xd_tag_0493x8j(sectionXD(i));
    profileTable.(['ux_' tag]) = profiles(:,i);
    if isfinite(Ub(i)) && abs(Ub(i)) > eps
        profileTable.(['uxOverUb_' tag]) = profiles(:,i)/Ub(i);
    else
        profileTable.(['uxOverUb_' tag]) = nan(size(y));
    end
end
profileTable.poiseuilleShape = phiP;

summary = table( ...
    D,H,beta,xc,nu,TargetUb,UmaxInlet,UbMeasured,string(measuredUbSource), ...
    UrefX8i,UupX8i,fPod,fProbe,fPrimary,freqAgreement,podPhaseR2,podCycles,probeR2Mean, ...
    lambdaOverD,cVortex,cvOverTargetUb,cvOverMeasuredUb,period, ...
    ReZTarget,ReZMeasured,TstarZTarget,TstarZMeasured,TstarZPodTarget,TstarZProbeTarget, ...
    double(opt.ZovattoReH),double(opt.ZovattoTstar),errReZTargetPct,errReZMeasuredPct, ...
    errTstarZTargetPct,errTstarZMeasuredPct,errTstarZPodPct,errTstarZProbePct, ...
    ReSO,StSO,StSOPod,StSOProbe,double(opt.SahinReCrit),double(opt.SahinStCrit), ...
    ReSOOverCrit,StSOOverCrit,ReSOFromZovatto,StSOFromZovatto,errStSOVsZovattoPct, ...
    QvSpreadPost,rhoSpreadPost,JrhoSpreadPost, ...
    double(opt.PresentUpstreamD),double(opt.PresentDownstreamD), ...
    double(opt.ZovattoUpstreamD),double(opt.ZovattoDownstreamD), ...
    double(opt.SahinUpstreamD),double(opt.SahinDownstreamD), ...
    UbMean,UcMean,UmaxMean,UbRelSpread,UcRelSpread,UmaxRelSpread, ...
    poiseuilleR2Mean,poiseuilleNRMSEMean, ...
    'VariableNames',{ ...
    'D','H','blockageDoverH','cylinderCx','nu','targetUb','targetUmaxInlet','measuredUb','measuredUbSource', ...
    'UrefX8i','UupCentralBandX8i','fPod','fProbe','fPrimary','frequencyAgreementRel','podPhaseR2','podCycles','probeR2Mean', ...
    'lambdaOverD','vortexConvectionSpeed','cVOverTargetUb','cVOverMeasuredUb','period', ...
    'ReZovattoTargetBulk','ReZovattoMeasuredBulk','TstarZovattoTargetBulk','TstarZovattoMeasuredBulk','TstarZovattoPodTargetBulk','TstarZovattoProbeTargetBulk', ...
    'ZovattoReReference','ZovattoTstarReference','ReZovattoTargetErrorPct','ReZovattoMeasuredErrorPct', ...
    'TstarZovattoTargetErrorPct','TstarZovattoMeasuredErrorPct','TstarZovattoPodErrorPct','TstarZovattoProbeErrorPct', ...
    'ReSahinOwens','StSahinOwens','StSahinOwensPod','StSahinOwensProbe','SahinOwensReCrit','SahinOwensStCrit', ...
    'ReSahinOwensOverCrit','StSahinOwensOverCrit','ReSahinOwensEquivalentZovatto','StSahinOwensEquivalentZovatto','StSahinOwensVsEquivalentZovattoErrorPct', ...
    'QvRelativeSpreadPostInlet','rhoRelativeSpreadPostInlet','JrhoRelativeSpreadPostInlet', ...
    'presentUpstreamD','presentDownstreamD','ZovattoUpstreamD','ZovattoDownstreamD','SahinOwensUpstreamD','SahinOwensDownstreamD', ...
    'UbMeanFieldSections','UcMeanFieldSections','UmaxMeanFieldSections','UbRelativeSpreadFieldSections','UcRelativeSpreadFieldSections','UmaxRelativeSpreadFieldSections', ...
    'poiseuilleR2MeanFieldSections','poiseuilleNRMSEMeanFieldSections'});

comparison = table( ...
    ["Zovatto-Pedrizzetti direct"; "Zovatto-Pedrizzetti measured-Ub"; "Zovatto point in Sahin-Owens convention"; "Sahin-Owens critical context"], ...
    ["Re=Ub H/nu, T*=T Ub/H"; "Re=Ub H/nu, T*=T Ub/H"; "Re=Umax D/nu, St=fD/Umax"; "Hopf onset at beta=0.2"], ...
    [ReZTarget; ReZMeasured; ReSO; double(opt.SahinReCrit)], ...
    [TstarZTarget; TstarZMeasured; StSO; double(opt.SahinStCrit)], ...
    [double(opt.ZovattoReH); double(opt.ZovattoReH); ReSOFromZovatto; double(opt.SahinReCrit)], ...
    [double(opt.ZovattoTstar); double(opt.ZovattoTstar); StSOFromZovatto; double(opt.SahinStCrit)], ...
    [errReZTargetPct; errReZMeasuredPct; 100*(ReSO/ReSOFromZovatto-1); 100*(ReSO/double(opt.SahinReCrit)-1)], ...
    [errTstarZTargetPct; errTstarZMeasuredPct; errStSOVsZovattoPct; 100*(StSO/double(opt.SahinStCrit)-1)], ...
    'VariableNames',{'comparison','definition','Q6GF_Re','Q6GF_periodOrSt','reference_Re','reference_periodOrSt','ReDifferencePct','frequencyMetricDifferencePct'});

literature = table( ...
    ["Zovatto & Pedrizzetti (2001)"; "Sahin & Owens (2004)"], ...
    ["J. Fluid Mech. 440, 1-25"; "Phys. Fluids 16, 1305-1320"], ...
    ["10.1017/S0022112001004608"; "10.1063/1.1668285"], ...
    ["Re=Ub H/nu; T*=T Ub/H"; "Re=Umax D/nu; St=fD/Umax"], ...
    [double(opt.ZovattoBlockage); double(opt.SahinBeta)], ...
    [double(opt.ZovattoReH); double(opt.SahinReCrit)], ...
    [double(opt.ZovattoTstar); double(opt.SahinStCrit)], ...
    'VariableNames',{'reference','journal','doi','definition','blockageDoverH','referenceRe','referencePeriodOrSt'});

writetable(sectionTable,fullfile(outDir,'vk_nondim_sections_0493x8j.csv'));
writetable(profileTable,fullfile(outDir,'vk_nondim_profiles_0493x8j.csv'));
writetable(summary,fullfile(outDir,'vk_nondim_summary_0493x8j.csv'));
writetable(comparison,fullfile(outDir,'vk_literature_comparison_0493x8j.csv'));
writetable(literature,fullfile(outDir,'vk_literature_definitions_0493x8j.csv'));

% -------------------------------------------------------------------------
% Figures.
% -------------------------------------------------------------------------
plotFiles = strings(0,1);
if logical(opt.MakePlots)
    vis = 'off';
    if logical(opt.ShowFigures)
        vis = 'on';
    end

    % 1) Upstream profile and bulk-section stability.
    f1 = figure('Visible',vis,'Color','w','Name','0493x8j upstream conditioning');
    tiledlayout(f1,1,2,'Padding','compact','TileSpacing','compact');

    nexttile; hold on; grid on;
    for i = 1:nSec
        plot(profiles(:,i)/Ub(i),y/H,'LineWidth',1.1, ...
            'DisplayName',sprintf('x-x_c=%.1fD',sectionXD(i)));
    end
    plot(1.5*phiP,y/H,'k--','LineWidth',1.3,'DisplayName','Poiseuille');
    xlabel('u/U_b'); ylabel('y/H');
    title('Established upstream profiles');
    legend('Location','best');

    nexttile; hold on; grid on;
    plot(sectionXD,Ub/TargetUb,'o-','LineWidth',1.3,'DisplayName','x8i U_b/target');
    yline(1,'k--','HandleVisibility','off');
    if fluxAvailable
        plot(fluxSectionXD,fluxUb/TargetUb,'s-','LineWidth',1.2,'DisplayName','x8n U_b/target');
    end
    xlabel('(x-x_c)/D'); ylabel('U_b/U_{b,target}');
    title('Bulk-flow conditioning');
    legend('Location','best');
    sgtitle(sprintf('Q6-G-F upstream conditioning | D/H=%.3f',beta));
    plotFiles(end+1,1) = string(local_export_figure_0493x8j(f1, ...
        fullfile(outDir,'vk_upstream_conditioning_0493x8j'))); %#ok<AGROW>

    % 2) Literature comparison in each paper's own convention.
    f2 = figure('Visible',vis,'Color','w','Name','0493x8j literature comparison');
    tiledlayout(f2,1,2,'Padding','compact','TileSpacing','compact');

    nexttile; hold on; grid on;
    plot(double(opt.ZovattoReH),double(opt.ZovattoTstar),'ks','MarkerSize',8,'LineWidth',1.4, ...
        'DisplayName','Zovatto-Pedrizzetti');
    plot(ReZTarget,TstarZTarget,'o','MarkerSize',8,'LineWidth',1.4, ...
        'DisplayName','Q6-G-F (target U_b)');
    plot(ReZMeasured,TstarZMeasured,'^','MarkerSize',8,'LineWidth',1.4, ...
        'DisplayName','Q6-G-F (measured U_b)');
    xlabel('Re_H = U_b H/\nu'); ylabel('T^* = T U_b/H');
    title(sprintf('Zovatto convention | \DeltaT^* = %+.2f%%',errTstarZTargetPct));
    legend('Location','best');

    nexttile; hold on; grid on;
    plot(double(opt.SahinReCrit),double(opt.SahinStCrit),'ks','MarkerSize',8,'LineWidth',1.4, ...
        'DisplayName','Sahin-Owens critical');
    plot(ReSOFromZovatto,StSOFromZovatto,'d','MarkerSize',8,'LineWidth',1.4, ...
        'DisplayName','Zovatto point, S-O scaling');
    plot(ReSO,StSO,'o','MarkerSize',8,'LineWidth',1.4, ...
        'DisplayName','Q6-G-F');
    xlabel('Re_D = U_{max}D/\nu'); ylabel('St = fD/U_{max}');
    title(sprintf('Sahin-Owens convention | \DeltaSt vs ZP = %+.2f%%',errStSOVsZovattoPct));
    legend('Location','best');
    sgtitle('Confined-cylinder VK literature comparison');
    plotFiles(end+1,1) = string(local_export_figure_0493x8j(f2, ...
        fullfile(outDir,'vk_literature_comparison_0493x8j'))); %#ok<AGROW>

    % 3) x8n post-inlet flux conservation, when available.
    if fluxAvailable && any(isfinite(fluxQvOverRef))
        f3 = figure('Visible',vis,'Color','w','Name','0493x8j flux conservation');
        hold on; grid on;
        plot(fluxXFromInletD,fluxQvOverRef,'o-','LineWidth',1.2,'DisplayName','Q_v/Q_{v,ref}');
        if any(isfinite(fluxJrhoOverRef))
            plot(fluxXFromInletD,fluxJrhoOverRef,'s-','LineWidth',1.2,'DisplayName','J_\rho/J_{\rho,ref}');
        end
        if any(isfinite(fluxRhoOverRef))
            plot(fluxXFromInletD,fluxRhoOverRef,'^-','LineWidth',1.2,'DisplayName','\rho/\rho_{ref}');
        end
        yline(1,'k--','HandleVisibility','off');
        xlabel('x/D from inlet'); ylabel('normalized quantity');
        title('x8n established post-inlet conservation');
        legend('Location','best');
        plotFiles(end+1,1) = string(local_export_figure_0493x8j(f3, ...
            fullfile(outDir,'vk_flux_conservation_0493x8j'))); %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
% Console report: definitions are printed next to values to prevent scale
% confusion between the two papers.
% -------------------------------------------------------------------------
fprintf('\n===== 0493x8j DEFINITIVE VK LITERATURE COMPARISON =====\n');
fprintf('geometry: D/H=%.8g D=%.8g H=%.8g | nu=%.9g\n',beta,D,H,nu);
fprintf('wake: fPrimary=%.9g (POD=%.9g, probe=%.9g) | |df|/fmean=%.4g\n', ...
    fPrimary,fPod,fProbe,freqAgreement);
fprintf('      POD phase R2=%.6g cycles=%.4g | probe mean R2=%.6g\n', ...
    podPhaseR2,podCycles,probeR2Mean);
fprintf('      lambda/D=%.6g | c_v/Ub_target=%.6g | c_v/Ub_measured=%.6g\n', ...
    lambdaOverD,cvOverTargetUb,cvOverMeasuredUb);

fprintf('\n--- upstream / flux conditioning ---\n');
fprintf('target Ub=%.9g | measured Ub=%.9g (%s) | delta=%+.4f %%\n', ...
    TargetUb,UbMeasured,measuredUbSource,100*(UbMeasured/TargetUb-1));
if fluxSummaryAvailable
    fprintf('x8n post-inlet relative spread: Qv=%.6g rho=%.6g Jrho=%.6g\n', ...
        QvSpreadPost,rhoSpreadPost,JrhoSpreadPost);
end

fprintf('\n--- Zovatto & Pedrizzetti 2001 convention ---\n');
fprintf('definition: Re=Ub*H/nu ; T*=T*Ub/H ; reference D/H=0.2 gamma=2\n');
fprintf('reference:  Re=%.6g T*=%.6g\n',double(opt.ZovattoReH),double(opt.ZovattoTstar));
fprintf('Q6GF target-Ub:   Re=%.6g (%+.4f %%) T*=%.8g (%+.4f %%)\n', ...
    ReZTarget,errReZTargetPct,TstarZTarget,errTstarZTargetPct);
fprintf('Q6GF measured-Ub: Re=%.6g (%+.4f %%) T*=%.8g (%+.4f %%)\n', ...
    ReZMeasured,errReZMeasuredPct,TstarZMeasured,errTstarZMeasuredPct);
fprintf('frequency estimators at target Ub: T*_POD=%.8g (%+.4f %%) T*_probe=%.8g (%+.4f %%)\n', ...
    TstarZPodTarget,errTstarZPodPct,TstarZProbeTarget,errTstarZProbePct);

fprintf('\n--- Sahin & Owens 2004 convention ---\n');
fprintf('definition: Re=Umax,inlet*D/nu ; St=f*D/Umax,inlet ; beta=D/H=0.2\n');
fprintf('Q6GF: Umax,inlet=%.9g Re=%.6g St=%.8g\n',UmaxInlet,ReSO,StSO);
fprintf('Zovatto Re=280,T*=0.83 converted to same convention: Re=%.6g St=%.8g\n', ...
    ReSOFromZovatto,StSOFromZovatto);
fprintf('Q6GF vs converted Zovatto: delta St=%+.4f %%\n',errStSOVsZovattoPct);
fprintf('Sahin-Owens Hopf onset context only: Recrit=%.6g Stcrit=%.6g | Re/Recrit=%.6g\n', ...
    double(opt.SahinReCrit),double(opt.SahinStCrit),ReSOOverCrit);

fprintf('\n--- domain caveat ---\n');
fprintf('present domain: upstream=%.3gD downstream=%.3gD\n', ...
    double(opt.PresentUpstreamD),double(opt.PresentDownstreamD));
fprintf('Zovatto-Pedrizzetti: upstream=%.3gD downstream=%.3gD\n', ...
    double(opt.ZovattoUpstreamD),double(opt.ZovattoDownstreamD));
fprintf('Sahin-Owens: upstream=%.3gD downstream=%.3gD\n', ...
    double(opt.SahinUpstreamD),double(opt.SahinDownstreamD));

fprintf('\noutputs:\n');
fprintf('  summary=%s\n',fullfile(outDir,'vk_nondim_summary_0493x8j.csv'));
fprintf('  comparison=%s\n',fullfile(outDir,'vk_literature_comparison_0493x8j.csv'));
fprintf('  definitions=%s\n',fullfile(outDir,'vk_literature_definitions_0493x8j.csv'));
fprintf('  sections=%s\n',fullfile(outDir,'vk_nondim_sections_0493x8j.csv'));
fprintf('  profiles=%s\n',fullfile(outDir,'vk_nondim_profiles_0493x8j.csv'));
fprintf('status=COMPLETE\n');

out = struct();
out.summary = summary;
out.comparison = comparison;
out.literature = literature;
out.sections = sectionTable;
out.profiles = profileTable;
out.outputDir = string(outDir);
out.plotFiles = plotFiles;
out.fluxAvailable = fluxAvailable;
out.fluxSummaryAvailable = fluxSummaryAvailable;
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

function r2 = local_r2_0493x8j(a,b)
a = double(a(:));
b = double(b(:));
good = isfinite(a) & isfinite(b);
a = a(good);
b = b(good);
if numel(a) < 3
    r2 = NaN;
    return;
end
ssr = sum((a-b).^2);
sst = sum((a-mean(a)).^2);
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

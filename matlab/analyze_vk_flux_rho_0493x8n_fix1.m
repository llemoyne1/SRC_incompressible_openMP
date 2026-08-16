function out = analyze_vk_flux_rho_0493x8n(varargin)
%ANALYZE_VK_FLUX_RHO_0493X8N Diagnose upstream volume and density-weighted flux.
%
% Purpose
% -------
% Use the established part of a filtered-field recording (rho, ux) to
% determine whether the observed increase of bulk velocity close to the inlet
% is accompanied by a density decrease or by an increase of density-weighted
% flux.
%
% For each requested x-section the analyzer computes, frame by frame,
%
%   Ub(x,t)       = (1/H) integral ux dy
%   Qv(x,t)       =       integral ux dy = H*Ub
%   rhoBar(x,t)   = (1/H) integral rho dy
%   Mrho(x,t)     =       integral rho dy
%   Jrho(x,t)     =       integral rho*ux dy
%   Urho(x,t)     = Jrho/Mrho
%
% Jrho is the physical mass flux if the recorded rho field is a physical mass
% density.  Even if rho is stored in recorder-density units, Jrho ratios between
% x-sections remain the useful conservation diagnostic because the same density
% normalization is used everywhere.
%
% The script streams frames from disk and does not keep the full 3-D rho/ux
% time series in memory.  It uses only base MATLAB functions.
%
% Typical use for 0493x8m Zovatto reduced-domain production:
%
%   recDir = ['E:/SRC_MPCD_dev/SRC_GPU-SURF/runs/' ...
%       '0493x8m_zovatto_re280_prod60k/segment_000/src-q6-g-f/output/' ...
%       'recordings/0493x8m_zovatto_re280_seg000_src-q6-g-f_step_0000001088'];
%
%   out = analyze_vk_flux_rho_0493x8n( ...
%       'RecordingDir',recDir, ...
%       'OutputDir',['E:/SRC_MPCD_dev/SRC_GPU-SURF/runs/' ...
%                    '0493x8m_zovatto_re280_prod60k/analysis_x8n_flux_rho'], ...
%       'MinLocalStep',12000, ...
%       'RestartStepOffset',12000, ...
%       'CylinderCx',1.25, ...
%       'CylinderD',0.3125, ...
%       'TargetUb',0.12083932335718987, ...
%       'ShowFigures',true);
%
% 0493x8n: diagnostic only; no physical state is modified.

p = inputParser;
p.FunctionName = 'analyze_vk_flux_rho_0493x8n';
addParameter(p,'RecordingDir','../runs/0493x8m_zovatto_re280_prod60k/segment_000/src-q6-g-f/output/recordings');
addParameter(p,'OutputDir','../runs/0493x8n_flux_rho_analysis');
addParameter(p,'RestartStepOffset',12000);
addParameter(p,'Dt',0.002);
addParameter(p,'MinLocalStep',12000);
addParameter(p,'MaxLocalStep',inf);
addParameter(p,'CylinderD',0.3125);
addParameter(p,'CylinderCx',1.25);
addParameter(p,'TargetUb',0.12083932335718987);
% Dense inlet scan plus the already-inspected upstream sections.
addParameter(p,'SectionXD',[-3.95 -3.90 -3.80 -3.70 -3.50 -3.25 -3.00 -2.50 -2.00 -1.50 -1.00]);
addParameter(p,'SectionHalfWidthD',0.025);
% -3D is outside the immediate inlet layer and still well upstream of the
% strongest cylinder-induced profile deformation in the current reduced box.
addParameter(p,'ReferenceSectionXD',-3.0);
addParameter(p,'MakePlots',true);
addParameter(p,'ShowFigures',true);
parse(p,varargin{:});
opt = p.Results;

recordDir = char(opt.RecordingDir);
outDir = char(opt.OutputDir);
if ~isfolder(recordDir)
    error('0493x8n:missingRecording','Recording directory not found: %s',recordDir);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

% -------------------------------------------------------------------------
% Recorder geometry / cadence.
% -------------------------------------------------------------------------
manifestPath = fullfile(recordDir,'manifest.kv');
manifest = struct();
if isfile(manifestPath)
    manifest = local_read_kv_0493x8n(manifestPath);
else
    warning('0493x8n:noManifest','manifest.kv not found; using supplied/default geometry where possible.');
end

nx = round(local_kv_number_0493x8n(manifest,'liveGridNx',600));
ny = round(local_kv_number_0493x8n(manifest,'liveGridNy',200));
Lx = local_kv_number_0493x8n(manifest,'Lx',4.6875);
Ly = local_kv_number_0493x8n(manifest,'Ly',1.5625);
dt = double(opt.Dt);
if isfield(manifest,'dt')
    dt = local_kv_number_0493x8n(manifest,'dt',dt);
end

D = double(opt.CylinderD);
xc = double(opt.CylinderCx);
H = Ly;
dx = Lx/nx;
dy = Ly/ny;
x = ((0:nx-1)+0.5)*dx;
y = (((0:ny-1)+0.5)*dy).';

% -------------------------------------------------------------------------
% Common complete rho/ux frames in the requested established window.
% -------------------------------------------------------------------------
stepsUx = local_list_steps_0493x8n(recordDir,'ux');
stepsRho = local_list_steps_0493x8n(recordDir,'rho');
steps = intersect(stepsUx,stepsRho,'stable');
if isempty(steps)
    error('0493x8n:noFrames','No matching rho/ux .f32 frame pairs found in %s',recordDir);
end
if numel(steps) ~= numel(stepsUx) || numel(steps) ~= numel(stepsRho)
    warning('0493x8n:pairMismatch','Using %d common rho/ux frames (%d ux, %d rho).', ...
        numel(steps),numel(stepsUx),numel(stepsRho));
end

steps = local_keep_complete_frames_0493x8n(recordDir,steps,nx,ny);
minStep = double(opt.MinLocalStep);
maxStep = double(opt.MaxLocalStep);
steps = steps(double(steps) >= minStep & double(steps) <= maxStep);
if numel(steps) < 10
    error('0493x8n:tooFewFrames','Only %d complete rho/ux frame pairs remain after step filtering.',numel(steps));
elseif numel(steps) < 40
    warning('0493x8n:fewFrames','Only %d complete frames; section averages may be noisy.',numel(steps));
end

nFrames = numel(steps);
localTime = double(steps(:))*dt;
globalStep = double(opt.RestartStepOffset) + double(steps(:));
globalTime = globalStep*dt;

% -------------------------------------------------------------------------
% Section locations.  A small x-window is averaged before y integration.
% -------------------------------------------------------------------------
sectionXD = double(opt.SectionXD(:));
nSec = numel(sectionXD);
sectionXTarget = xc + sectionXD*D;
sectionXActual = nan(nSec,1);
sectionCols = cell(nSec,1);
halfWidth = max(0,double(opt.SectionHalfWidthD))*D;
for i = 1:nSec
    cols = find(abs(x-sectionXTarget(i)) <= halfWidth);
    if isempty(cols)
        [~,ix0] = min(abs(x-sectionXTarget(i)));
        cols = ix0;
    end
    sectionCols{i} = cols;
    sectionXActual(i) = mean(x(cols));
end
xFromInletD = sectionXActual/D;

% Reference section is used only for ratios, not to alter raw quantities.
refXDRequested = double(opt.ReferenceSectionXD);
[~,iRef] = min(abs(sectionXD-refXDRequested));
refXD = sectionXD(iRef);

% -------------------------------------------------------------------------
% Streaming accumulation.
% -------------------------------------------------------------------------
UbFrame = nan(nFrames,nSec);
QvFrame = nan(nFrames,nSec);
rhoBarFrame = nan(nFrames,nSec);
MrhoFrame = nan(nFrames,nSec);
JrhoFrame = nan(nFrames,nSec);
UrhoFrame = nan(nFrames,nSec);
rhoUFactorFrame = nan(nFrames,nSec);

sumUxProfile = zeros(ny,nSec);
sumRhoProfile = zeros(ny,nSec);
sumRhoUProfile = zeros(ny,nSec);
profileCount = zeros(ny,nSec);
nonFiniteFrames = 0;

for k = 1:nFrames
    sx = fullfile(recordDir,sprintf('step_%010d_field_ux.f32',steps(k)));
    sr = fullfile(recordDir,sprintf('step_%010d_field_rho.f32',steps(k)));
    ux = double(local_read_f32_field_0493x8n(sx,nx,ny));
    rho = double(local_read_f32_field_0493x8n(sr,nx,ny));

    bad = ~isfinite(ux) | ~isfinite(rho);
    if any(bad(:))
        nonFiniteFrames = nonFiniteFrames + 1;
        ux(bad) = NaN;
        rho(bad) = NaN;
    end

    for i = 1:nSec
        cols = sectionCols{i};
        uY = mean(ux(:,cols),2,'omitnan');
        rY = mean(rho(:,cols),2,'omitnan');
        ruY = mean(rho(:,cols).*ux(:,cols),2,'omitnan');

        goodU = isfinite(uY);
        goodR = isfinite(rY);
        goodRU = isfinite(ruY);
        if nnz(goodU) < 4 || nnz(goodR) < 4 || nnz(goodRU) < 4
            continue;
        end

        UbFrame(k,i) = mean(uY(goodU));
        QvFrame(k,i) = sum(uY(goodU))*dy;
        rhoBarFrame(k,i) = mean(rY(goodR));
        MrhoFrame(k,i) = sum(rY(goodR))*dy;
        JrhoFrame(k,i) = sum(ruY(goodRU))*dy;
        if isfinite(MrhoFrame(k,i)) && abs(MrhoFrame(k,i)) > eps
            UrhoFrame(k,i) = JrhoFrame(k,i)/MrhoFrame(k,i);
        end
        denom = rhoBarFrame(k,i)*QvFrame(k,i);
        if isfinite(denom) && abs(denom) > eps
            % Equals one for a spatially uniform rho field (up to x-window
            % averaging); departures quantify rho-u covariance across y.
            rhoUFactorFrame(k,i) = JrhoFrame(k,i)/denom;
        end

        gp = isfinite(uY) & isfinite(rY) & isfinite(ruY);
        sumUxProfile(gp,i) = sumUxProfile(gp,i) + uY(gp);
        sumRhoProfile(gp,i) = sumRhoProfile(gp,i) + rY(gp);
        sumRhoUProfile(gp,i) = sumRhoUProfile(gp,i) + ruY(gp);
        profileCount(gp,i) = profileCount(gp,i) + 1;
    end
end

if nonFiniteFrames > 0
    warning('0493x8n:nonfinite','Non-finite rho/ux values occurred in %d frames; affected samples were omitted.',nonFiniteFrames);
end

profileDen = profileCount;
profileDen(profileDen < 1) = 1;
meanUxProfile = sumUxProfile./profileDen;
meanRhoProfile = sumRhoProfile./profileDen;
meanRhoUProfile = sumRhoUProfile./profileDen;
meanUxProfile(profileCount==0) = NaN;
meanRhoProfile(profileCount==0) = NaN;
meanRhoUProfile(profileCount==0) = NaN;

% -------------------------------------------------------------------------
% Time statistics by x-section.
% -------------------------------------------------------------------------
Ub = local_colmean_0493x8n(UbFrame);
Qv = local_colmean_0493x8n(QvFrame);
rhoBar = local_colmean_0493x8n(rhoBarFrame);
Mrho = local_colmean_0493x8n(MrhoFrame);
Jrho = local_colmean_0493x8n(JrhoFrame);
Urho = local_colmean_0493x8n(UrhoFrame);
rhoUFactor = local_colmean_0493x8n(rhoUFactorFrame);

UbCV = local_colcv_0493x8n(UbFrame);
QvCV = local_colcv_0493x8n(QvFrame);
rhoBarCV = local_colcv_0493x8n(rhoBarFrame);
JrhoCV = local_colcv_0493x8n(JrhoFrame);

QvRef = Qv(iRef);
rhoRef = rhoBar(iRef);
JrhoRef = Jrho(iRef);
UbRef = Ub(iRef);
QvOverRef = Qv/max(abs(QvRef),eps);
rhoOverRef = rhoBar/max(abs(rhoRef),eps);
JrhoOverRef = Jrho/max(abs(JrhoRef),eps);
UbOverRef = Ub/max(abs(UbRef),eps);

TargetUb = double(opt.TargetUb);
if isfinite(TargetUb) && abs(TargetUb) > eps
    UbOverTarget = Ub/TargetUb;
    QvTarget = H*TargetUb;
    QvOverTarget = Qv/QvTarget;
else
    UbOverTarget = nan(nSec,1);
    QvOverTarget = nan(nSec,1);
    QvTarget = NaN;
end

sectionTable = table(sectionXD,sectionXTarget,sectionXActual,xFromInletD, ...
    Ub,Qv,rhoBar,Mrho,Jrho,Urho,rhoUFactor, ...
    UbCV,QvCV,rhoBarCV,JrhoCV, ...
    UbOverRef,QvOverRef,rhoOverRef,JrhoOverRef,UbOverTarget,QvOverTarget, ...
    'VariableNames',{ ...
    'sectionXD','xTarget','xActual','xFromInletD', ...
    'Ub','Qv','rhoBar','Mrho','Jrho','Urho','rhoUFactor', ...
    'UbCV','QvCV','rhoBarCV','JrhoCV', ...
    'UbOverRef','QvOverRef','rhoOverRef','JrhoOverRef','UbOverTarget','QvOverTarget'});

% Long time-series table: convenient for later plotting/checks without reread.
N = nFrames*nSec;
localStepLong = repmat(double(steps(:)),nSec,1);
globalStepLong = repmat(globalStep,nSec,1);
localTimeLong = repmat(localTime,nSec,1);
globalTimeLong = repmat(globalTime,nSec,1);
sectionXDLong = repelem(sectionXD,nFrames);
xActualLong = repelem(sectionXActual,nFrames);
UbLong = reshape(UbFrame,[],1);
QvLong = reshape(QvFrame,[],1);
rhoBarLong = reshape(rhoBarFrame,[],1);
JrhoLong = reshape(JrhoFrame,[],1);
UrhoLong = reshape(UrhoFrame,[],1);
if numel(localStepLong) ~= N
    error('0493x8n:internalShape','Unexpected long-table shape.');
end
timeseriesTable = table(localStepLong,globalStepLong,localTimeLong,globalTimeLong, ...
    sectionXDLong,xActualLong,UbLong,QvLong,rhoBarLong,JrhoLong,UrhoLong, ...
    'VariableNames',{'localStep','globalStep','localTime','globalTime', ...
    'sectionXD','xActual','Ub','Qv','rhoBar','Jrho','Urho'});

profileTable = table(y,y/H,'VariableNames',{'y','yOverH'});
for i = 1:nSec
    tag = local_xd_tag_0493x8n(sectionXD(i));
    profileTable.(['ux_' tag]) = meanUxProfile(:,i);
    profileTable.(['rho_' tag]) = meanRhoProfile(:,i);
    profileTable.(['rhoUx_' tag]) = meanRhoUProfile(:,i);
end

% Overall conservation/spread diagnostics over all requested sections and over
% a post-inlet subset x/D_from_inlet >= 1 (if available).
QvRelSpreadAll = local_relspread_0493x8n(Qv);
rhoRelSpreadAll = local_relspread_0493x8n(rhoBar);
JrhoRelSpreadAll = local_relspread_0493x8n(Jrho);
postMask = xFromInletD >= 1.0;
if nnz(postMask) < 2
    postMask = true(size(xFromInletD));
end
QvRelSpreadPost = local_relspread_0493x8n(Qv(postMask));
rhoRelSpreadPost = local_relspread_0493x8n(rhoBar(postMask));
JrhoRelSpreadPost = local_relspread_0493x8n(Jrho(postMask));

% First section -> reference section changes localize what happens in the inlet
% layer.  They are reported without a hard PASS/FAIL classification.
iFirst = 1;
QvRatioFirstToRef = QvRef/max(abs(Qv(iFirst)),eps);
rhoRatioFirstToRef = rhoRef/max(abs(rhoBar(iFirst)),eps);
JrhoRatioFirstToRef = JrhoRef/max(abs(Jrho(iFirst)),eps);

summary = table(nFrames,double(steps(1)),double(steps(end)),localTime(1),localTime(end), ...
    double(opt.RestartStepOffset),D,xc,H,Lx,nx,ny,dx,dy,TargetUb,QvTarget, ...
    refXD,sectionXActual(iRef),UbRef,QvRef,rhoRef,JrhoRef, ...
    QvRelSpreadAll,rhoRelSpreadAll,JrhoRelSpreadAll, ...
    QvRelSpreadPost,rhoRelSpreadPost,JrhoRelSpreadPost, ...
    sectionXD(iFirst),sectionXActual(iFirst),QvRatioFirstToRef,rhoRatioFirstToRef,JrhoRatioFirstToRef, ...
    'VariableNames',{ ...
    'frames','localStepFirst','localStepLast','localTimeFirst','localTimeLast', ...
    'restartStepOffset','D','cylinderCx','H','Lx','Nx','Ny','dx','dy','targetUb','targetQv', ...
    'referenceSectionXD','referenceXActual','UbRef','QvRef','rhoRef','JrhoRef', ...
    'QvRelativeSpreadAll','rhoRelativeSpreadAll','JrhoRelativeSpreadAll', ...
    'QvRelativeSpreadPostInlet','rhoRelativeSpreadPostInlet','JrhoRelativeSpreadPostInlet', ...
    'firstSectionXD','firstXActual','QvRefOverFirst','rhoRefOverFirst','JrhoRefOverFirst'});

writetable(sectionTable,fullfile(outDir,'vk_flux_rho_sections_0493x8n.csv'));
writetable(timeseriesTable,fullfile(outDir,'vk_flux_rho_timeseries_0493x8n.csv'));
writetable(profileTable,fullfile(outDir,'vk_flux_rho_profiles_0493x8n.csv'));
writetable(summary,fullfile(outDir,'vk_flux_rho_summary_0493x8n.csv'));
save(fullfile(outDir,'vk_flux_rho_0493x8n.mat'), ...
    'x','y','steps','localTime','globalStep','globalTime', ...
    'sectionTable','timeseriesTable','profileTable','summary', ...
    'UbFrame','QvFrame','rhoBarFrame','MrhoFrame','JrhoFrame','UrhoFrame','rhoUFactorFrame', ...
    'meanUxProfile','meanRhoProfile','meanRhoUProfile','-v7.3');

% -------------------------------------------------------------------------
% Figures.
% -------------------------------------------------------------------------
plotFiles = strings(0,1);
if logical(opt.MakePlots)
    vis = 'off';
    if logical(opt.ShowFigures)
        vis = 'on';
    end

    % Main conservation diagnostic.
    f1 = figure('Visible',vis,'Color','w','Name','0493x8n inlet flux/rho diagnostic');
    tiledlayout(f1,2,2,'Padding','compact','TileSpacing','compact');

    nexttile; hold on; grid on;
    plot(xFromInletD,Ub,'o-','LineWidth',1.3,'DisplayName','U_b');
    if isfinite(TargetUb)
        yline(TargetUb,'--','LineWidth',1.1,'DisplayName','target U_b');
    end
    xlabel('x/D from inlet'); ylabel('U_b'); title('Bulk velocity');
    legend('Location','best');

    nexttile; hold on; grid on;
    plot(xFromInletD,rhoBar,'o-','LineWidth',1.3,'DisplayName','\rho bar');
    xlabel('x/D from inlet'); ylabel('\rho bar'); title('Mean recorded density');
    legend('Location','best');

    nexttile; hold on; grid on;
    plot(xFromInletD,QvOverRef,'o-','LineWidth',1.3,'DisplayName','Q_v / Q_{v,ref}');
    plot(xFromInletD,JrhoOverRef,'s-','LineWidth',1.3,'DisplayName','J_\rho / J_{\rho,ref}');
    yline(1,'--','HandleVisibility','off');
    xlabel('x/D from inlet'); ylabel('normalized flux'); title(sprintf('Flux conservation | ref %.2fD',refXD));
    legend('Location','best');

    nexttile; hold on; grid on;
    plot(xFromInletD,rhoOverRef,'o-','LineWidth',1.3,'DisplayName','\rho bar / \rho_{ref}');
    plot(xFromInletD,Urho./Urho(iRef),'s-','LineWidth',1.3,'DisplayName','U_\rho / U_{\rho,ref}');
    plot(xFromInletD,rhoUFactor,'^-','LineWidth',1.3,'DisplayName','J_\rho/(\rho bar Q_v)');
    yline(1,'--','HandleVisibility','off');
    xlabel('x/D from inlet'); ylabel('ratio'); title('Density/velocity decomposition');
    legend('Location','best');

    sgtitle(sprintf('0493x8n established inlet diagnostic | local steps %d..%d',steps(1),steps(end)));
    plotFiles(end+1,1) = string(local_export_figure_0493x8n(f1,fullfile(outDir,'vk_flux_rho_conservation_0493x8n'))); %#ok<AGROW>

    % Time stationarity at the first, reference and last sections.
    idxPlot = unique([1 iRef nSec]);
    f2 = figure('Visible',vis,'Color','w','Name','0493x8n flux stationarity');
    tiledlayout(f2,3,1,'Padding','compact','TileSpacing','compact');
    nexttile; hold on; grid on;
    for ii = idxPlot
        plot(localTime,UbFrame(:,ii),'LineWidth',0.9,'DisplayName',sprintf('%.2fD',sectionXD(ii)));
    end
    ylabel('U_b'); title('Bulk velocity vs time'); legend('Location','best');
    nexttile; hold on; grid on;
    for ii = idxPlot
        plot(localTime,rhoBarFrame(:,ii),'LineWidth',0.9,'DisplayName',sprintf('%.2fD',sectionXD(ii)));
    end
    ylabel('\rho bar'); title('Mean density vs time'); legend('Location','best');
    nexttile; hold on; grid on;
    for ii = idxPlot
        plot(localTime,JrhoFrame(:,ii)./Jrho(ii),'LineWidth',0.9,'DisplayName',sprintf('%.2fD',sectionXD(ii)));
    end
    xlabel('local time'); ylabel('J_\rho / <J_\rho>_t'); title('Density-weighted flux stationarity');
    legend('Location','best');
    plotFiles(end+1,1) = string(local_export_figure_0493x8n(f2,fullfile(outDir,'vk_flux_rho_stationarity_0493x8n'))); %#ok<AGROW>

    % Mean rho profiles to see whether any compensation is wall-localized.
    f3 = figure('Visible',vis,'Color','w','Name','0493x8n rho profiles');
    hold on; grid on;
    for i = 1:nSec
        plot(meanRhoProfile(:,i),y/H,'LineWidth',1.0,'DisplayName',sprintf('x-x_c=%.2fD',sectionXD(i)));
    end
    xlabel('\rho'); ylabel('y/H'); title('Established mean density profiles');
    legend('Location','bestoutside');
    plotFiles(end+1,1) = string(local_export_figure_0493x8n(f3,fullfile(outDir,'vk_flux_rho_profiles_0493x8n'))); %#ok<AGROW>
end

% -------------------------------------------------------------------------
% Console summary focused on the decision we need to make.
% -------------------------------------------------------------------------
fprintf('\n===== 0493x8n RHO / FLUX DIAGNOSTIC =====\n');
fprintf('recording=%s\n',recordDir);
fprintf('grid=%dx%d L=(%.9g,%.9g) H/D=%.8g | frames=%d localStep=%d..%d\n', ...
    nx,ny,Lx,Ly,H/D,nFrames,steps(1),steps(end));
fprintf('section reference: requested %.3gD used %.3gD x=%.9g (x/D from inlet=%.5g)\n', ...
    refXDRequested,refXD,sectionXActual(iRef),xFromInletD(iRef));
if isfinite(TargetUb)
    fprintf('target Ub=%.9g QvTarget=%.9g\n',TargetUb,QvTarget);
end
fprintf('\n  sectionXD  x/Din       Ub        Ub/target    rhoBar      Qv/Qref    Jrho/Jref   Jrho/(rhoQv)\n');
for i = 1:nSec
    fprintf('  %8.3f  %6.3f  %10.7f  %10.5f  %10.6g  %10.5f  %10.5f  %12.6f\n', ...
        sectionXD(i),xFromInletD(i),Ub(i),UbOverTarget(i),rhoBar(i),QvOverRef(i),JrhoOverRef(i),rhoUFactor(i));
end
fprintf('\nrelative section spread (all):       Qv=%.5g rho=%.5g Jrho=%.5g\n', ...
    QvRelSpreadAll,rhoRelSpreadAll,JrhoRelSpreadAll);
fprintf('relative section spread (x/D>=1):    Qv=%.5g rho=%.5g Jrho=%.5g\n', ...
    QvRelSpreadPost,rhoRelSpreadPost,JrhoRelSpreadPost);
fprintf('first %.3gD -> ref %.3gD ratios: Qv=%.6g rho=%.6g Jrho=%.6g\n', ...
    sectionXD(iFirst),refXD,QvRatioFirstToRef,rhoRatioFirstToRef,JrhoRatioFirstToRef);
fprintf('interpretation guide:\n');
fprintf('  Jrho ~ constant while Qv changes => density compensation / compressibility-like expansion.\n');
fprintf('  Jrho changes with Qv while rho stays ~constant => net density-weighted flux increase in inlet treatment.\n');
fprintf('  Both Jrho and rho change => mixed mechanism; inspect section/time tables and rho profiles.\n');
fprintf('NOTE: Jrho = integral rho*ux dy; relative x-conservation is the primary diagnostic.\n');
fprintf('sections=%s\n',fullfile(outDir,'vk_flux_rho_sections_0493x8n.csv'));
fprintf('timeseries=%s\n',fullfile(outDir,'vk_flux_rho_timeseries_0493x8n.csv'));
fprintf('profiles=%s\n',fullfile(outDir,'vk_flux_rho_profiles_0493x8n.csv'));
fprintf('summary=%s\n',fullfile(outDir,'vk_flux_rho_summary_0493x8n.csv'));
fprintf('status=COMPLETE\n');

out = struct();
out.summary = summary;
out.sections = sectionTable;
out.timeseries = timeseriesTable;
out.profiles = profileTable;
out.outputDir = string(outDir);
out.plotFiles = plotFiles;
out.recordingDir = string(recordDir);
end

% =========================================================================
function kv = local_read_kv_0493x8n(path)
kv = struct();
fid = fopen(path,'r');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    line = strtrim(line);
    if isempty(line) || startsWith(line,'#')
        continue;
    end
    eq = strfind(line,'=');
    if isempty(eq)
        continue;
    end
    key = strtrim(line(1:eq(1)-1));
    val = strtrim(line(eq(1)+1:end));
    key = matlab.lang.makeValidName(key);
    kv.(key) = val;
end
end

function v = local_kv_number_0493x8n(kv,key,defaultValue)
v = defaultValue;
if ~isstruct(kv) || ~isfield(kv,key)
    return;
end
x = str2double(kv.(key));
if isfinite(x)
    v = x;
end
end

function steps = local_list_steps_0493x8n(recordDir,fieldName)
D = dir(fullfile(recordDir,sprintf('step_*_field_%s.f32',fieldName)));
steps = zeros(numel(D),1);
n = 0;
for i = 1:numel(D)
    tok = regexp(D(i).name,'^step_(\d+)_field_','tokens','once');
    if isempty(tok)
        continue;
    end
    n = n+1;
    steps(n) = str2double(tok{1});
end
steps = steps(1:n);
steps = unique(sort(steps));
end

function steps = local_keep_complete_frames_0493x8n(recordDir,steps,nx,ny)
expectedBytes = nx*ny*4;
keep = true(size(steps));
for i = 1:numel(steps)
    fu = fullfile(recordDir,sprintf('step_%010d_field_ux.f32',steps(i)));
    fr = fullfile(recordDir,sprintf('step_%010d_field_rho.f32',steps(i)));
    du = dir(fu);
    dr = dir(fr);
    if isempty(du) || isempty(dr) || du.bytes ~= expectedBytes || dr.bytes ~= expectedBytes
        keep(i) = false;
    end
end
nBad = nnz(~keep);
if nBad > 0
    warning('0493x8n:incompleteFrames','Ignoring %d incomplete rho/ux frame pairs.',nBad);
end
steps = steps(keep);
end

function F = local_read_f32_field_0493x8n(path,nx,ny)
fid = fopen(path,'rb');
if fid < 0
    error('0493x8n:openField','Cannot open %s',path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
v = fread(fid,nx*ny,'single=>single');
if numel(v) ~= nx*ny
    error('0493x8n:shortField','Unexpected field size in %s',path);
end
% Same recorder convention as x8i: row_major, x varying fastest.
F = reshape(v,[nx ny]).';
end

function m = local_colmean_0493x8n(A)
nc = size(A,2);
m = nan(nc,1);
for j = 1:nc
    v = A(:,j);
    v = v(isfinite(v));
    if ~isempty(v)
        m(j) = mean(v);
    end
end
end

function cv = local_colcv_0493x8n(A)
nc = size(A,2);
cv = nan(nc,1);
for j = 1:nc
    v = A(:,j);
    v = v(isfinite(v));
    if numel(v) >= 2
        mm = mean(v);
        if abs(mm) > eps
            cv(j) = std(v)/abs(mm);
        end
    end
end
end

function s = local_relspread_0493x8n(v)
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

function tag = local_xd_tag_0493x8n(xd)
s = sprintf('%.3f',xd);
s = strrep(s,'-','m');
s = strrep(s,'.','p');
s = regexprep(s,'0+$','');
s = regexprep(s,'p$','');
tag = ['xD_' s];
tag = matlab.lang.makeValidName(tag);
end

function pathOut = local_export_figure_0493x8n(fig,basePath)
pngPath = [basePath '.png'];
try
    exportgraphics(fig,pngPath,'Resolution',180);
catch
    saveas(fig,pngPath);
end
pathOut = pngPath;
end

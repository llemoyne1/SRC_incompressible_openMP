function out = analyze_0493x23g_phase_resolved_dumps_robust(runRoot,varargin)
%ANALYZE_0493X23G_PHASE_RESOLVED_DUMPS_ROBUST
% Robust phase-resolved L/G tangential-velocity analysis from particle dumps.
%
% This version replaces the original 0.25h "one-bin = one estimate" analysis
% by:
%   1) per-dump interface recentering;
%   2) 1h sliding physical windows sampled every 0.25h;
%   3) equal weighting of dumps in the mean profile;
%   4) dump-level bootstrap 95% confidence intervals;
%   5) a direct interfacial slab diagnostic using a finite physical slab;
%   6) phase-resolved fit-band sensitivity with slopes in PHYSICAL units du/dy.
%
% It does NOT use the LiveVis barycentric ux field and it does NOT use
% viscosity in the primary phase-velocity diagnostic.
%
% Example:
% out = analyze_0493x23g_phase_resolved_dumps_robust( ...
%   '../runs/0493x23g_interface_quasi_isoviscous_restart_8000_to_40000_seed593172', ...
%   'StepRange',[10000 15000]);
%
% Main outputs:
%   <runRoot>/analysis_phase_resolved_0493x23g_robust/
%       phase_resolved_robust_profile_0493x23g.png
%       phase_resolved_robust_stationarity_0493x23g.png
%       phase_resolved_robust_fit_sensitivity_0493x23g.png
%       phase_resolved_robust_profile_0493x23g.csv
%       phase_resolved_robust_fit_bands_0493x23g.csv
%       phase_resolved_robust_dump_diagnostics_0493x23g.csv
%       phase_resolved_robust_summary_0493x23g.txt
%
% IMPORTANT:
% - Sliding windows are fixed physical Eulerian slabs after recentering on
%   yGamma. They are not the randomly shifted SRC collision cells.
% - Confidence intervals are obtained by resampling DUMPS, not particles.
%   This avoids treating all particles inside one stochastic realization as
%   independent samples.
% - Fit slopes are returned as du/dy, not du/d[(y-yGamma)/h].

p = inputParser;
p.FunctionName = mfilename;
addRequired(p,'runRoot',@(s)ischar(s)||isstring(s));
addParameter(p,'StepRange',[NaN NaN],@(x)isnumeric(x)&&numel(x)==2);
addParameter(p,'Lx',0.5,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'Ly',0.5,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'Nx',128,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
addParameter(p,'Ny',128,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
addParameter(p,'LiquidType',1,@(x)isnumeric(x)&&isscalar(x));
addParameter(p,'GasType',2,@(x)isnumeric(x)&&isscalar(x));
addParameter(p,'DeltaUw',0.08,@(x)isnumeric(x)&&isscalar(x)&&x>0);

% Spatial statistics.
addParameter(p,'BaseBinWidthH',0.25,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'WindowWidthH',1.0,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'EvalSpacingH',0.25,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'HalfWidthH',28,@(x)isnumeric(x)&&isscalar(x)&&x>2);
addParameter(p,'MinWindowParticles',40,@(x)isnumeric(x)&&isscalar(x)&&x>=1);

% Direct interfacial slab: same physical slab for both phases.
addParameter(p,'DirectSlabHalfWidthH',0.75,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'DirectSlabSensitivityH',[0.5 0.75 1.0 1.5], ...
    @(x)isnumeric(x)&&isvector(x)&&all(x>0));

% Bootstrap.
addParameter(p,'BootstrapReplicates',2000,@(x)isnumeric(x)&&isscalar(x)&&x>=100);
addParameter(p,'BootstrapSeed',493231,@(x)isnumeric(x)&&isscalar(x));

% Figures.
addParameter(p,'MakeFigures',true,@(x)islogical(x)||isnumeric(x));
addParameter(p,'SaveFigures',true,@(x)islogical(x)||isnumeric(x));
parse(p,runRoot,varargin{:});
o = p.Results;

runRoot = char(runRoot);
Lx = double(o.Lx); Ly = double(o.Ly);
Nx = double(o.Nx); Ny = double(o.Ny);
dx = Lx/Nx; h = Ly/Ny;
if abs(dx-h) > 1e-12*max([1,abs(dx),abs(h)])
    warning('0493x23g:nonSquareCells','dx != dy; y distances are normalized by dy.');
end
dUw = double(o.DeltaUw);
liq = uint32(o.LiquidType);
gas = uint32(o.GasType);

% -------------------------------------------------------------------------
% Locate dumps.
% -------------------------------------------------------------------------
candDirs = {fullfile(runRoot,'output'),runRoot};
dumpDir = '';
for kk=1:numel(candDirs)
    if isfolder(candDirs{kk}) && ~isempty(dir(fullfile(candDirs{kk},'state_step_*.smpcd')))
        dumpDir = candDirs{kk};
        break;
    end
end
if isempty(dumpDir)
    error('0493x23g:noDumps','No state_step_*.smpcd dumps found under %s.',runRoot);
end

D = dir(fullfile(dumpDir,'state_step_*.smpcd'));
steps = nan(numel(D),1);
for k=1:numel(D)
    tok = regexp(D(k).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(tok), steps(k)=str2double(tok{1}); end
end
q = isfinite(steps);
D = D(q); steps = steps(q);
[steps,ord] = sort(steps); D = D(ord);

sr = double(o.StepRange(:).');
keep = true(size(steps));
if isfinite(sr(1)), keep = keep & steps>=sr(1); end
if isfinite(sr(2)), keep = keep & steps<=sr(2); end
D = D(keep); steps = steps(keep);
if isempty(D)
    error('0493x23g:noDumpsInRange','No dumps in requested StepRange.');
end
nDump = numel(D);

fprintf('[x23g-phase-robust] dumps=%d range=[%d,%d]\n',nDump,steps(1),steps(end));

% -------------------------------------------------------------------------
% Fine histogram grid and sliding-window evaluation grid.
% -------------------------------------------------------------------------
baseBW = double(o.BaseBinWidthH);
W = double(o.HalfWidthH);
fineEdges = (-W-baseBW:baseBW:W+baseBW).';
fineCenters = 0.5*(fineEdges(1:end-1)+fineEdges(2:end));
nf = numel(fineCenters);

evalSpacing = double(o.EvalSpacingH);
evalS = (-W:evalSpacing:W).';
ne = numel(evalS);
windowHalf = 0.5*double(o.WindowWidthH);
minNp = double(o.MinWindowParticles);

% Per-dump resolved profiles.
UL = nan(ne,nDump);
UG = nan(ne,nDump);
UM = nan(ne,nDump);
YLwin = nan(ne,nDump);
NLwin = zeros(ne,nDump);
NGwin = zeros(ne,nDump);

% Per-dump geometry and direct slab.
yGammaH = nan(nDump,1);
directSlip = nan(nDump,1);
directUL = nan(nDump,1);
directUG = nan(nDump,1);
directNL = zeros(nDump,1);
directNG = zeros(nDump,1);
directMeanSL = nan(nDump,1);
directMeanSG = nan(nDump,1);

slabHalfList = double(o.DirectSlabSensitivityH(:).');
nSlab = numel(slabHalfList);
directSlipSens = nan(nDump,nSlab);
directCountLSens = zeros(nDump,nSlab);
directCountGSens = zeros(nDump,nSlab);

% Keep per-dump outer-fit diagnostics for stationarity plots.
bands = [2 6;3 8;4 10;4 12;5 12;6 16;8 20;10 24];
nBand = size(bands,1);
fitPerDumpL = nan(nDump,nBand);
fitPerDumpG = nan(nDump,nBand);
r2PerDumpL = nan(nDump,nBand);
r2PerDumpG = nan(nDump,nBand);

for kd=1:nDump
    file = fullfile(D(kd).folder,D(kd).name);
    s = local_read_state(file);

    typ = uint32(s.type(:));
    y = double(s.y(:));
    vx = double(s.vx(:));
    m = double(s.mass(:));

    fluid = true(s.Np,1);
    if isfield(s,'role') && ~isempty(s.role)
        rr = double(s.role(:));
        if any(rr==1), fluid = (rr==1); end
    end

    isL = fluid & typ==liq;
    isG = fluid & typ==gas;
    if ~any(isL) || ~any(isG)
        error('0493x23g:missingPhase','Dump %s lacks one requested phase.',D(kd).name);
    end

    % ---------------------------------------------------------------------
    % Interface from x-averaged native-grid particle composition.
    % ---------------------------------------------------------------------
    iy = floor(y/h)+1;
    iy = min(max(iy,1),Ny);
    MLrow = accumarray(iy(isL),m(isL),[Ny 1],@sum,0);
    MGrow = accumarray(iy(isG),m(isG),[Ny 1],@sum,0);
    den = MLrow+MGrow;
    YLrow = nan(Ny,1);
    qq = den>0;
    YLrow(qq)=MLrow(qq)./den(qq);
    yc = ((0:Ny-1)'+0.5)*h;
    yg = local_crossing(yc,YLrow);
    yGammaH(kd)=yg/h;

    sh = (y-yg)/h;

    % ---------------------------------------------------------------------
    % Fine phase histograms after recentering.
    % ---------------------------------------------------------------------
    ib = discretize(sh,fineEdges);
    qL = isL & isfinite(ib);
    qG = isG & isfinite(ib);

    ML = accumarray(ib(qL),m(qL),[nf 1],@sum,0);
    MG = accumarray(ib(qG),m(qG),[nf 1],@sum,0);
    PxL = accumarray(ib(qL),m(qL).*vx(qL),[nf 1],@sum,0);
    PxG = accumarray(ib(qG),m(qG).*vx(qG),[nf 1],@sum,0);
    NL = accumarray(ib(qL),1,[nf 1],@sum,0);
    NG = accumarray(ib(qG),1,[nf 1],@sum,0);

    % ---------------------------------------------------------------------
    % Sliding 1h physical windows.  We sum particle moments first and only
    % then divide, so the estimator is conservative inside each phase.
    % ---------------------------------------------------------------------
    for ie=1:ne
        sel = fineCenters >= evalS(ie)-windowHalf & fineCenters <= evalS(ie)+windowHalf;
        ml = sum(ML(sel)); mg = sum(MG(sel));
        pxl = sum(PxL(sel)); pxg = sum(PxG(sel));
        nl = sum(NL(sel)); ng = sum(NG(sel));

        NLwin(ie,kd)=nl; NGwin(ie,kd)=ng;

        if nl>=minNp && ml>0
            UL(ie,kd)=pxl/ml;
        end
        if ng>=minNp && mg>0
            UG(ie,kd)=pxg/mg;
        end
        if (nl+ng)>=minNp && (ml+mg)>0
            UM(ie,kd)=(pxl+pxg)/(ml+mg);
            YLwin(ie,kd)=ml/(ml+mg);
        end
    end

    % ---------------------------------------------------------------------
    % Direct same-physical-slab phase difference at Gamma.
    % This does NOT rely on extrapolated one-sided fits.
    % ---------------------------------------------------------------------
    hs = double(o.DirectSlabHalfWidthH);
    qLs = isL & abs(sh)<=hs;
    qGs = isG & abs(sh)<=hs;
    directNL(kd)=sum(qLs); directNG(kd)=sum(qGs);
    if directNL(kd)>=minNp && directNG(kd)>=minNp
        mL = sum(m(qLs)); mG = sum(m(qGs));
        directUL(kd)=sum(m(qLs).*vx(qLs))/mL;
        directUG(kd)=sum(m(qGs).*vx(qGs))/mG;
        directSlip(kd)=directUG(kd)-directUL(kd);
        directMeanSL(kd)=sum(m(qLs).*sh(qLs))/mL;
        directMeanSG(kd)=sum(m(qGs).*sh(qGs))/mG;
    end

    for js=1:nSlab
        hs2 = slabHalfList(js);
        qLs2 = isL & abs(sh)<=hs2;
        qGs2 = isG & abs(sh)<=hs2;
        directCountLSens(kd,js)=sum(qLs2);
        directCountGSens(kd,js)=sum(qGs2);
        if directCountLSens(kd,js)>=minNp && directCountGSens(kd,js)>=minNp
            mL2=sum(m(qLs2)); mG2=sum(m(qGs2));
            uL2=sum(m(qLs2).*vx(qLs2))/mL2;
            uG2=sum(m(qGs2).*vx(qGs2))/mG2;
            directSlipSens(kd,js)=uG2-uL2;
        end
    end

    % Per-dump phase-resolved fit diagnostics on the robust window profile.
    for jb=1:nBand
        d1=bands(jb,1); d2=bands(jb,2);
        [aL,~,rL]=local_fit_physical(evalS,UL(:,kd),-d2,-d1,h);
        [aG,~,rG]=local_fit_physical(evalS,UG(:,kd), d1, d2,h);
        fitPerDumpL(kd,jb)=aL; fitPerDumpG(kd,jb)=aG;
        r2PerDumpL(kd,jb)=rL; r2PerDumpG(kd,jb)=rG;
    end

    fprintf('[x23g-phase-robust] step=%6d yG/h=%8.4f slab N=(%d,%d) dUslab/DU=% .4g\n', ...
        steps(kd),yGammaH(kd),directNL(kd),directNG(kd),directSlip(kd)/dUw);
end

% -------------------------------------------------------------------------
% Equal-dump mean profiles.
% -------------------------------------------------------------------------
uLmean = mean(UL,2,'omitnan');
uGmean = mean(UG,2,'omitnan');
uMmean = mean(UM,2,'omitnan');
YLmean = mean(YLwin,2,'omitnan');

nValidL = sum(isfinite(UL),2);
nValidG = sum(isfinite(UG),2);
nValidBoth = sum(isfinite(UL)&isfinite(UG),2);
duMean = uGmean-uLmean;

% -------------------------------------------------------------------------
% Dump-level bootstrap.
% -------------------------------------------------------------------------
B = round(double(o.BootstrapReplicates));
rng(double(o.BootstrapSeed),'twister');

bootUL = nan(ne,B);
bootUG = nan(ne,B);
bootUM = nan(ne,B);
bootDU = nan(ne,B);
bootDirect = nan(B,1);

fitBoot = nan(nBand,6,B); % aL,aG,R2L,R2G,uGammaL,uGammaG

for b=1:B
    jj = randi(nDump,[nDump 1]);
    uLb = mean(UL(:,jj),2,'omitnan');
    uGb = mean(UG(:,jj),2,'omitnan');
    uMb = mean(UM(:,jj),2,'omitnan');

    bootUL(:,b)=uLb;
    bootUG(:,b)=uGb;
    bootUM(:,b)=uMb;
    bootDU(:,b)=uGb-uLb;

    ds = directSlip(jj);
    ds = ds(isfinite(ds));
    if ~isempty(ds), bootDirect(b)=mean(ds); end

    for jb=1:nBand
        d1=bands(jb,1); d2=bands(jb,2);
        [aL,bL,rL]=local_fit_physical(evalS,uLb,-d2,-d1,h);
        [aG,bG,rG]=local_fit_physical(evalS,uGb, d1, d2,h);
        fitBoot(jb,:,b)=[aL aG rL rG bL bG];
    end
end

[uLlo,uLhi]=local_ci(bootUL,2.5,97.5);
[uGlo,uGhi]=local_ci(bootUG,2.5,97.5);
[uMlo,uMhi]=local_ci(bootUM,2.5,97.5);
[duLo,duHi]=local_ci(bootDU,2.5,97.5);

directMean = mean(directSlip,'omitnan');
directStd = std(directSlip,'omitnan');
directBoot = bootDirect(isfinite(bootDirect));
if isempty(directBoot)
    directCI=[NaN NaN];
else
    directCI=[local_percentile(directBoot,2.5) local_percentile(directBoot,97.5)];
end

% Direct slab sensitivity across widths.
slabStats = nan(nSlab,6);
for js=1:nSlab
    z=directSlipSens(:,js)/dUw;
    qz=isfinite(z);
    if any(qz)
        zz=z(qz);
        % bootstrap dumps for this width
        bz=nan(B,1);
        for b=1:B
            jj=randi(numel(zz),[numel(zz) 1]);
            bz(b)=mean(zz(jj));
        end
        slabStats(js,:)=[slabHalfList(js),sum(qz),mean(zz),std(zz), ...
            local_percentile(bz,2.5),local_percentile(bz,97.5)];
    else
        slabStats(js,:)=[slabHalfList(js),0,NaN,NaN,NaN,NaN];
    end
end

% -------------------------------------------------------------------------
% Mean fit-band sensitivity + bootstrap CI, with slopes in physical du/dy.
% -------------------------------------------------------------------------
fitMean = nan(nBand,13);
for jb=1:nBand
    d1=bands(jb,1); d2=bands(jb,2);
    [aL,bL,rL]=local_fit_physical(evalS,uLmean,-d2,-d1,h);
    [aG,bG,rG]=local_fit_physical(evalS,uGmean, d1, d2,h);

    tmpAL=squeeze(fitBoot(jb,1,:));
    tmpAG=squeeze(fitBoot(jb,2,:));
    tmpBL=squeeze(fitBoot(jb,5,:));
    tmpBG=squeeze(fitBoot(jb,6,:));
    slipBoot=(tmpBG-tmpBL)/dUw;

    fitMean(jb,:)=[d1 d2 aL aG rL rG bL bG (bG-bL)/dUw, ...
        local_percentile(tmpAL(isfinite(tmpAL)),2.5), ...
        local_percentile(tmpAL(isfinite(tmpAL)),97.5), ...
        local_percentile(tmpAG(isfinite(tmpAG)),2.5), ...
        local_percentile(tmpAG(isfinite(tmpAG)),97.5)];
end

% Separate bootstrap CI for extrapolated offset.
slipFitCI = nan(nBand,2);
for jb=1:nBand
    tmpBL=squeeze(fitBoot(jb,5,:));
    tmpBG=squeeze(fitBoot(jb,6,:));
    zz=(tmpBG-tmpBL)/dUw;
    zz=zz(isfinite(zz));
    if ~isempty(zz)
        slipFitCI(jb,:)=[local_percentile(zz,2.5) local_percentile(zz,97.5)];
    end
end

% -------------------------------------------------------------------------
% Output files.
% -------------------------------------------------------------------------
outDir=fullfile(runRoot,'analysis_phase_resolved_0493x23g_robust');
if ~isfolder(outDir), mkdir(outDir); end

T=table(evalS,nValidL,nValidG,nValidBoth,YLmean, ...
    uLmean,uLlo,uLhi,uGmean,uGlo,uGhi,uMmean,uMlo,uMhi,duMean,duLo,duHi, ...
    'VariableNames',{'sOverH','validDumpsL','validDumpsG','validDumpsBoth','YL', ...
    'uL','uL_ciLow','uL_ciHigh','uG','uG_ciLow','uG_ciHigh', ...
    'uMix','uMix_ciLow','uMix_ciHigh','uGminusUL','du_ciLow','du_ciHigh'});
writetable(T,fullfile(outDir,'phase_resolved_robust_profile_0493x23g.csv'));

Tf=array2table([fitMean slipFitCI], ...
    'VariableNames',{'dMinH','dMaxH','aL','aG','R2L','R2G','uGammaL','uGammaG', ...
    'slipOverDeltaUw','aL_ciLow','aL_ciHigh','aG_ciLow','aG_ciHigh', ...
    'slip_ciLow','slip_ciHigh'});
writetable(Tf,fullfile(outDir,'phase_resolved_robust_fit_bands_0493x23g.csv'));

Td=table(steps,yGammaH,directNL,directNG,directMeanSL,directMeanSG, ...
    directUL,directUG,directSlip,directSlip/dUw, ...
    'VariableNames',{'step','yGammaOverH','directNL','directNG', ...
    'directMeanSL','directMeanSG','directUL','directUG', ...
    'directSlip','directSlipOverDeltaUw'});
writetable(Td,fullfile(outDir,'phase_resolved_robust_dump_diagnostics_0493x23g.csv'));

Ts=array2table(slabStats, ...
    'VariableNames',{'halfWidthH','validDumps','meanSlipOverDeltaUw','stdSlipOverDeltaUw', ...
    'ciLow','ciHigh'});
writetable(Ts,fullfile(outDir,'phase_resolved_robust_slab_sensitivity_0493x23g.csv'));

% -------------------------------------------------------------------------
% Figures.
% -------------------------------------------------------------------------
if logical(o.MakeFigures)
    % Profile + uncertainty.
    f1=figure('Name','0493x23g robust phase-resolved profile','Color','w');
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

    nexttile;
    local_band_plot(evalS,uLmean/dUw,uLlo/dUw,uLhi/dUw,'liquid'); hold on;
    local_band_plot(evalS,uGmean/dUw,uGlo/dUw,uGhi/dUw,'gas');
    local_band_plot(evalS,uMmean/dUw,uMlo/dUw,uMhi/dUw,'mixture');
    xline(0,':','\Gamma');
    xlim([-W W]); grid on;
    xlabel('(y-y_\Gamma)/h'); ylabel('u_x/\Delta U_w');
    title(sprintf('Robust phase profiles: %.2fh windows, dump bootstrap',o.WindowWidthH));
    legend('Location','best');

    nexttile;
    local_band_plot(evalS,uLmean/dUw,uLlo/dUw,uLhi/dUw,'liquid'); hold on;
    local_band_plot(evalS,uGmean/dUw,uGlo/dUw,uGhi/dUw,'gas');
    local_band_plot(evalS,uMmean/dUw,uMlo/dUw,uMhi/dUw,'mixture');
    xline(0,':','\Gamma');
    xlim([-6 6]); grid on;
    xlabel('(y-y_\Gamma)/h'); ylabel('u_x/\Delta U_w');
    title('Zoom on the kinetic interface region');
    legend('Location','best');

    nexttile;
    plot(evalS,YLmean,'-','DisplayName','Y_L'); hold on;
    plot(evalS,1-YLmean,'--','DisplayName','Y_G');
    yline(0.5,':'); xline(0,':','\Gamma');
    xlim([-6 6]); ylim([-0.05 1.05]); grid on;
    xlabel('(y-y_\Gamma)/h'); ylabel('window mass fraction');
    title('Composition in the same sliding windows');
    legend('Location','best');

    nexttile;
    local_band_plot(evalS,duMean/dUw,duLo/dUw,duHi/dUw,'u_G-u_L'); hold on;
    yline(0,':'); xline(0,':','\Gamma');
    xlim([-6 6]); grid on;
    xlabel('(y-y_\Gamma)/h'); ylabel('(u_G-u_L)/\Delta U_w');
    title('Phase difference with 95% dump-bootstrap CI');
    legend('Location','best');

    sgtitle(sprintf('0493x23g robust particle-dump analysis, local steps %d--%d',steps(1),steps(end)));

    % Stationarity and direct slab.
    f2=figure('Name','0493x23g robust phase-resolved stationarity','Color','w');
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

    nexttile;
    plot(steps,yGammaH,'o-'); grid on;
    xlabel('local restart step'); ylabel('y_\Gamma/h');
    title('Particle interface position');

    nexttile;
    plot(steps,directSlip/dUw,'o-'); hold on;
    yline(0,':'); grid on;
    xlabel('local restart step'); ylabel('\Delta u_{G-L}^{slab}/\Delta U_w');
    title(sprintf('Direct same slab, |s| \\le %.2fh',o.DirectSlabHalfWidthH));

    nexttile;
    errorbar(slabHalfList,slabStats(:,3), ...
        slabStats(:,3)-slabStats(:,5),slabStats(:,6)-slabStats(:,3),'o-');
    yline(0,':'); grid on;
    xlabel('interfacial slab half-width / h'); ylabel('mean slip / \Delta U_w');
    title('Direct-slab width sensitivity (95% bootstrap CI)');

    nexttile;
    plot(steps,directMeanSL,'o-','DisplayName','mean s_L/h'); hold on;
    plot(steps,directMeanSG,'s-','DisplayName','mean s_G/h');
    yline(0,':'); grid on;
    xlabel('local restart step'); ylabel('mass-weighted position in slab');
    title('Where the two phase samples lie inside the slab');
    legend('Location','best');

    sgtitle('0493x23g robust direct interfacial phase diagnostic');

    % Fit sensitivity.
    f3=figure('Name','0493x23g robust fit sensitivity','Color','w');
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

    xband=1:nBand;
    labels=compose('%g-%g',bands(:,1),bands(:,2));

    nexttile;
    errorbar(xband,fitMean(:,3),fitMean(:,3)-fitMean(:,10),fitMean(:,11)-fitMean(:,3),'o-','DisplayName','a_L'); hold on;
    errorbar(xband,fitMean(:,4),fitMean(:,4)-fitMean(:,12),fitMean(:,13)-fitMean(:,4),'s-','DisplayName','a_G');
    xticks(xband); xticklabels(labels); xtickangle(35); grid on;
    xlabel('[d_{min},d_{max}]/h'); ylabel('du/dy');
    title('Physical phase slopes with bootstrap CI');
    legend('Location','best');

    nexttile;
    plot(xband,fitMean(:,5),'o-','DisplayName','R^2_L'); hold on;
    plot(xband,fitMean(:,6),'s-','DisplayName','R^2_G');
    yline(0.9,':'); ylim([0 1.02]); grid on;
    xticks(xband); xticklabels(labels); xtickangle(35);
    xlabel('[d_{min},d_{max}]/h'); ylabel('R^2');
    title('Mean-profile linearity');
    legend('Location','best');

    nexttile;
    errorbar(xband,fitMean(:,9),fitMean(:,9)-slipFitCI(:,1),slipFitCI(:,2)-fitMean(:,9),'o-');
    yline(0,':'); grid on;
    xticks(xband); xticklabels(labels); xtickangle(35);
    xlabel('[d_{min},d_{max}]/h'); ylabel('(u_G^\Gamma-u_L^\Gamma)/\Delta U_w');
    title('Extrapolated phase offset with bootstrap CI');

    nexttile;
    plot(xband,fitMean(:,3)./fitMean(:,4),'o-'); grid on;
    xticks(xband); xticklabels(labels); xtickangle(35);
    xlabel('[d_{min},d_{max}]/h'); ylabel('a_L/a_G');
    title('Phase-resolved slope ratio (descriptive only)');

    sgtitle('0493x23g robust phase-resolved fit sensitivity');

    if logical(o.SaveFigures)
        exportgraphics(f1,fullfile(outDir,'phase_resolved_robust_profile_0493x23g.png'),'Resolution',180);
        exportgraphics(f2,fullfile(outDir,'phase_resolved_robust_stationarity_0493x23g.png'),'Resolution',180);
        exportgraphics(f3,fullfile(outDir,'phase_resolved_robust_fit_sensitivity_0493x23g.png'),'Resolution',180);
    end
end

% -------------------------------------------------------------------------
% Text summary.
% -------------------------------------------------------------------------
fid=fopen(fullfile(outDir,'phase_resolved_robust_summary_0493x23g.txt'),'w');
fprintf(fid,'===== 0493x23g ROBUST PHASE-RESOLVED PARTICLE-DUMP ANALYSIS =====\n');
fprintf(fid,'runRoot = %s\n',runRoot);
fprintf(fid,'dumpDir = %s\n',dumpDir);
fprintf(fid,'dumps = %d ; local steps = [%d,%d]\n',nDump,steps(1),steps(end));
fprintf(fid,'grid = %dx%d ; Lx=%.17g ; Ly=%.17g ; h=%.17g\n',Nx,Ny,Lx,Ly,h);
fprintf(fid,'types: liquid=%d gas=%d ; DeltaUw=%.17g\n',double(liq),double(gas),dUw);
fprintf(fid,'base bin width = %.6g h ; sliding window width = %.6g h ; eval spacing = %.6g h\n', ...
    baseBW,double(o.WindowWidthH),evalSpacing);
fprintf(fid,'min particles per phase/window = %d\n',round(minNp));
fprintf(fid,'bootstrap = %d resamples of dumps ; seed=%d\n',B,round(double(o.BootstrapSeed)));
fprintf(fid,'yGamma/h mean +/- std = %.12g +/- %.12g\n',mean(yGammaH,'omitnan'),std(yGammaH,'omitnan'));

qd=isfinite(directSlip);
fprintf(fid,'\nDIRECT INTERFACIAL SAME-SLAB DIAGNOSTIC\n');
fprintf(fid,'slab = |(y-yGamma)/h| <= %.6g\n',double(o.DirectSlabHalfWidthH));
if any(qd)
    fprintf(fid,'valid dumps = %d/%d\n',sum(qd),nDump);
    fprintf(fid,'mean slip/DeltaUw = %.12g\n',directMean/dUw);
    fprintf(fid,'dump std slip/DeltaUw = %.12g\n',directStd/dUw);
    fprintf(fid,'bootstrap 95%% CI slip/DeltaUw = [%.12g, %.12g]\n',directCI(1)/dUw,directCI(2)/dUw);
    fprintf(fid,'mean liquid sample position s/h = %.12g\n',mean(directMeanSL(qd),'omitnan'));
    fprintf(fid,'mean gas sample position s/h = %.12g\n',mean(directMeanSG(qd),'omitnan'));
else
    fprintf(fid,'No dump had enough particles of both phases in the direct slab.\n');
end

fprintf(fid,'\nDIRECT SLAB-WIDTH SENSITIVITY\n');
fprintf(fid,'halfWidth[h] validDumps meanSlip/DU stdSlip/DU ciLow ciHigh\n');
for js=1:nSlab
    fprintf(fid,'%12.6g %10d %12.6g %12.6g %12.6g %12.6g\n', ...
        slabStats(js,1),round(slabStats(js,2)),slabStats(js,3),slabStats(js,4),slabStats(js,5),slabStats(js,6));
end

fprintf(fid,'\nROBUST PHASE-RESOLVED FIT SENSITIVITY\n');
fprintf(fid,'IMPORTANT: aL and aG below are PHYSICAL slopes du/dy.\n');
fprintf(fid,'band[h]      aL          aG         R2L      R2G      uGammaL     uGammaG    slip/DU      aL95%%             aG95%%            slip95%%\n');
for jb=1:nBand
    fprintf(fid,'[%4.1f,%4.1f] %11.6g %11.6g %8.4f %8.4f %11.6g %11.6g %11.6g  [% .5g,% .5g]  [% .5g,% .5g]  [% .5g,% .5g]\n', ...
        fitMean(jb,1),fitMean(jb,2),fitMean(jb,3),fitMean(jb,4),fitMean(jb,5),fitMean(jb,6), ...
        fitMean(jb,7),fitMean(jb,8),fitMean(jb,9),fitMean(jb,10),fitMean(jb,11), ...
        fitMean(jb,12),fitMean(jb,13),slipFitCI(jb,1),slipFitCI(jb,2));
end

fprintf(fid,'\nINTERPRETATION RULES\n');
fprintf(fid,'1. Primary question: are uL and uG themselves smooth near Gamma after statistically robust averaging?\n');
fprintf(fid,'2. If only uMix bends while uL/uG remain smooth within their CI, the LiveVis dip is predominantly barycentric.\n');
fprintf(fid,'3. If uL or uG bends outside its bootstrap CI, the kinetic layer is phase-resolved.\n');
fprintf(fid,'4. The direct slab diagnostic compares phase means in the SAME finite physical slab; sample-position offsets are reported explicitly.\n');
fprintf(fid,'5. Fits are secondary diagnostics; no viscosity enters this analyzer.\n');
fclose(fid);

out=struct();
out.runRoot=runRoot;
out.outDir=outDir;
out.steps=steps;
out.yGammaOverH=yGammaH;
out.sOverH=evalS;
out.uL=uLmean; out.uL_ci=[uLlo uLhi];
out.uG=uGmean; out.uG_ci=[uGlo uGhi];
out.uMix=uMmean; out.uMix_ci=[uMlo uMhi];
out.uGminusUL=duMean; out.du_ci=[duLo duHi];
out.directSlipPerDump=directSlip;
out.directSlipMean=directMean;
out.directSlipBootstrapCI=directCI;
out.fitBands=Tf;
out.dumpDiagnostics=Td;
out.slabSensitivity=Ts;

fprintf('\n[x23g-phase-robust] DONE -> %s\n',outDir);
if any(qd)
    fprintf('[x23g-phase-robust] direct slab slip/DeltaUw = %.6g ; 95%% CI [%.6g, %.6g]\n', ...
        directMean/dUw,directCI(1)/dUw,directCI(2)/dUw);
end

end

% =========================================================================
function yg=local_crossing(yc,YL)
q=isfinite(YL);
i=find(q(1:end-1)&q(2:end)&YL(1:end-1)>=0.5&YL(2:end)<0.5,1,'first');
if isempty(i)
    iq=find(q);
    if isempty(iq), error('Cannot locate interface: composition is undefined.'); end
    [~,j]=min(abs(YL(iq)-0.5));
    yg=yc(iq(j));
    return;
end
f0=YL(i)-0.5; f1=YL(i+1)-0.5;
if abs(f1-f0)<eps
    yg=0.5*(yc(i)+yc(i+1));
else
    yg=yc(i)-f0*(yc(i+1)-yc(i))/(f1-f0);
end
end

function [a,b,r2]=local_fit_physical(sOverH,u,smin,smax,h)
q=isfinite(sOverH)&isfinite(u)&sOverH>=smin&sOverH<=smax;
if sum(q)<3
    a=NaN; b=NaN; r2=NaN; return;
end
x=sOverH(q)*h;
yy=u(q);
pp=polyfit(x,yy,1);
a=pp(1); b=pp(2);
yh=polyval(pp,x);
sst=sum((yy-mean(yy)).^2);
ssr=sum((yy-yh).^2);
if sst>0, r2=1-ssr/sst; else, r2=NaN; end
end

function [lo,hi]=local_ci(A,pLo,pHi)
% Row-wise percentile CI, ignoring NaN.
n=size(A,1);
lo=nan(n,1); hi=nan(n,1);
for i=1:n
    z=A(i,:);
    z=z(isfinite(z));
    if ~isempty(z)
        lo(i)=local_percentile(z,pLo);
        hi(i)=local_percentile(z,pHi);
    end
end
end

function q=local_percentile(x,p)
% Toolbox-free linear percentile, p in [0,100].
x=sort(x(:));
n=numel(x);
if n==0, q=NaN; return; end
if n==1, q=x; return; end
p=max(0,min(100,double(p)));
r=1+(n-1)*p/100;
i=floor(r); j=ceil(r);
if i==j
    q=x(i);
else
    q=x(i)+(r-i)*(x(j)-x(i));
end
end

function local_band_plot(x,mu,lo,hi,label)
% Draw CI band + mean without requiring a graphics toolbox.
x=x(:); mu=mu(:); lo=lo(:); hi=hi(:);
q=isfinite(x)&isfinite(mu)&isfinite(lo)&isfinite(hi);
if any(q)
    xx=x(q); ll=lo(q); hh=hi(q);
    patch([xx;flipud(xx)],[ll;flipud(hh)],[0.75 0.75 0.75], ...
        'FaceAlpha',0.18,'EdgeColor','none','HandleVisibility','off');
    hold on;
    plot(xx,mu(q),'-','LineWidth',1.25,'DisplayName',label);
else
    plot(nan,nan,'-','DisplayName',label);
end
end

function s=local_read_state(filename)
if exist('read_smpcd_state','file')==2
    s=read_smpcd_state(filename);
    return;
end

fid=fopen(filename,'r','ieee-le');
if fid<0, error('Cannot open %s',filename); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>

magic=fread(fid,16,'uint8=>uint8');
ex=uint8(zeros(16,1)); tag=uint8('SRCMPCD_STATE'); ex(1:numel(tag))=tag;
if numel(magic)~=16 || any(magic~=ex), error('Bad smpcd magic: %s',filename); end

ver=fread(fid,1,'uint32=>uint32');
endian=fread(fid,1,'uint32=>uint32');
dim=fread(fid,1,'uint32=>uint32');
layout=fread(fid,1,'uint32=>uint32');
Np=fread(fid,1,'uint64=>uint64');
hasType=fread(fid,1,'uint32=>uint32');
hasMass=fread(fid,1,'uint32=>uint32');
realSize=fread(fid,1,'uint32=>uint32');
typeSize=fread(fid,1,'uint32=>uint32');
reserved=fread(fid,8,'uint64=>uint64');

if ~(ver==1||ver==2) || endian~=hex2dec('01020304') || ...
        dim~=2 || layout~=1 || hasType~=1 || hasMass~=1 || realSize~=8 || typeSize~=4
    error('Unsupported smpcd format: %s',filename);
end

n=double(Np);
s=struct();
s.Np=n;
s.x=fread(fid,n,'double=>double');
s.y=fread(fid,n,'double=>double');
s.vx=fread(fid,n,'double=>double');
s.vy=fread(fid,n,'double=>double');
s.type=fread(fid,n,'uint32=>uint32');
s.mass=fread(fid,n,'double=>double');

if ver==2
    if isempty(reserved) || reserved(1)~=uint64(1)
        error('Unsupported V2 role flag in %s',filename);
    end
    s.role=fread(fid,n,'uint8=>uint8');
else
    s.role=ones(n,1,'uint8');
end

if numel(s.x)~=n || numel(s.y)~=n || numel(s.vx)~=n || numel(s.vy)~=n || ...
        numel(s.type)~=n || numel(s.mass)~=n || numel(s.role)~=n
    error('Truncated smpcd payload: %s',filename);
end
end

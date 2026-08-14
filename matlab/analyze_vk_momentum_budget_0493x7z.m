function out = analyze_vk_momentum_budget_0493x7z(varargin)
%ANALYZE_VK_MOMENTUM_BUDGET_0493X7Z Offline VK momentum-loss decomposition.
%
% Purpose
% -------
% Use ONLY files already written by the existing VK runs.  No solver rerun and
% no physics change.  For every run contained in an x7u timeseries:
%
%   observed dPx/dt = body-force input + Darcy/Brinkman force + remainder
%
% The remainder is deliberately named "nonDarcyResidual": with the currently
% available outputs it contains wall/SRC-collision/thermostat momentum exchange,
% any non-neutral projection contribution, and cadence/discretization error.
% It is NOT silently identified with Q6 or wall friction.
%
% The analyzer also reports the existing Q6 k=0 diagnostics at summary cadence
% and the optional 0493w5 species-Q6 signed momentum audit when present.
%
% Typical call:
%   out = analyze_vk_momentum_budget_0493x7z( ...
%       'X7UTimeseries', '../runs/.../vk_vorticity_timeseries_0493x7u.csv');
%
% Outputs:
%   vk_momentum_budget_summary_0493x7z.csv
%   vk_momentum_budget_timeseries_0493x7z.csv
%   vk_momentum_budget_q6_samples_0493x7z.csv   (when available)
%   vk_momentum_budget_0493x7z.png/.pdf          (optional)
%
% 0493x7z is diagnostic-only.

p = inputParser;
addParameter(p,'X7UTimeseries','../runs/vk_vorticity_transport_0493x7u_analysis/vk_vorticity_timeseries_0493x7u.csv', ...
    @(x)ischar(x)||isstring(x));
addParameter(p,'OutputDir','../runs/vk_momentum_budget_0493x7z', ...
    @(x)ischar(x)||isstring(x));
addParameter(p,'MakePlots',true,@(x)islogical(x)||isnumeric(x));
addParameter(p,'ShowFigures',true,@(x)islogical(x)||isnumeric(x));
addParameter(p,'IncludeSmokesInPlots',false,@(x)islogical(x)||isnumeric(x));
addParameter(p,'LongRunMinTime',1.0,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(p,'Verbose',true,@(x)islogical(x)||isnumeric(x));
parse(p,varargin{:});
opt=p.Results;

x7uFile=char(string(opt.X7UTimeseries));
assert(isfile(x7uFile),'0493x7z:missingX7U','Missing x7u timeseries: %s',x7uFile);
outDir=char(string(opt.OutputDir));
if ~exist(outDir,'dir'), mkdir(outDir); end

X=readtable(x7uFile,'VariableNamingRule','preserve');
required={'runDir','mode','step','time','UglobalX','Uupstream','totalFluidMass'};
local_require_vars(X,required,'x7u timeseries');
X.runDir=string(X.runDir);
X.mode=string(X.mode);
if ismember('caseLabel',X.Properties.VariableNames), X.caseLabel=string(X.caseLabel); end
if ismember('paramsFile',X.Properties.VariableNames), X.paramsFile=string(X.paramsFile); end

runKeys=unique(X.runDir,'stable');
summaryRows=cell(0,1);
budgetTables=cell(0,1);
q6Tables=cell(0,1);

fprintf('\n===== 0493x7z VK MOMENTUM BUDGET =====\n');
fprintf('x7u=%s\n',x7uFile);
fprintf('runs=%d\n',numel(runKeys));

for ir=1:numel(runKeys)
    runKey=runKeys(ir);
    TX=X(X.runDir==runKey,:);
    [~,ord]=sort(double(TX.time));
    TX=TX(ord,:);
    mode=string(TX.mode(1));
    runDir=local_resolve_run_dir(runKey);
    label=local_case_label(runKey,mode);

    fprintf('\n[0493x7z] %2d/%2d %s\n',ir,numel(runKeys),label);

    if strlength(runDir)==0
        warning('0493x7z:missingRun','Cannot resolve runDir=%s',runKey);
        continue;
    end

    outputDir=fullfile(char(runDir),'output');
    summaryPath=fullfile(outputDir,'summary_runtime.csv');
    if ~isfile(summaryPath)
        warning('0493x7z:missingSummary','Missing %s',summaryPath);
        continue;
    end

    paramsPath=local_resolve_params(TX,runDir);
    params=local_parse_kv(paramsPath);
    ax=local_get_num(params,'bodyAccelerationX',0.0);
    dtParam=local_get_num(params,'dt',NaN);
    rot=local_get_num(params,'rotationAngle',NaN);
    nx=local_get_num(params,'Nx',NaN);
    ny=local_get_num(params,'Ny',NaN);

    S=readtable(summaryPath,'VariableNamingRule','preserve');
    local_require_vars(S,{'step','time','totalMass','Px'},'summary_runtime');
    [~,ord]=sort(double(S.time)); S=S(ord,:);
    [~,iu]=unique(double(S.time),'stable'); S=S(iu,:);

    st=double(S.step);
    ts=double(S.time);
    mass=double(S.totalMass);
    px=double(S.Px);
    ug=px./mass;
    if ismember('meanVx',S.Properties.VariableNames)
        ugReported=double(S.meanVx);
        ugMismatch=max(abs(ug-ugReported),[],'omitnan');
    else
        ugMismatch=NaN;
    end

    validS=isfinite(ts)&isfinite(mass)&mass>0&isfinite(px);
    ts=ts(validS); st=st(validS); mass=mass(validS); px=px(validS); ug=ug(validS);
    %assert(numel(ts)>=2,'0493x7z:shortSummary','Need >=2 summary rows: %s',summaryPath);

    tStart=ts(1); tEnd=ts(end);
    pxStart=px(1); pxEnd=px(end);
    uStart=ug(1); uEnd=ug(end);
    pScale=max(abs(pxStart),eps);
    globalDeltaPx=pxEnd-pxStart;
    globalDeltaFrac=globalDeltaPx/pScale;
    globalUFrac=(uEnd-uStart)/max(abs(uStart),eps);

    % x7u upstream values for the same run.
    xuTime=double(TX.time);
    xuUp=double(TX.Uupstream);
    xuGlobal=double(TX.UglobalX);
    uUpStart=local_first_finite(xuUp);
    uUpEnd=local_last_finite(xuUp);
    uUpFrac=(uUpEnd-uUpStart)/max(abs(uUpStart),eps);

    % Locate topo force CSV.  The current VK runner defaults to this exact name,
    % but honor a params override when present.
    topoName=local_get_str(params,'topoBenchmarkFilename','topo_benchmark_0348.csv');
    topoPath=fullfile(outputDir,topoName);
    if ~isfile(topoPath)
        cand=dir(fullfile(outputDir,'topo_benchmark*.csv'));
        if numel(cand)==1
            topoPath=fullfile(cand(1).folder,cand(1).name);
        end
    end

    hasTopo=isfile(topoPath);
    darcyConvention="unavailable";
    darcyOpposeFrac=NaN;
    darcyPowerMean=NaN;
    tBudgetStart=NaN; tBudgetEnd=NaN;
    deltaPxBudget=NaN; obsDeltaFracBudget=NaN;
    bodyImpulse=NaN; darcyImpulse=NaN; otherImpulse=NaN;
    bodyFrac=NaN; darcySinkFrac=NaN; otherSinkFrac=NaN;
    darcySinkShare=NaN; axHold=NaN;
    B=table();

    if hasTopo
        D=readtable(topoPath,'VariableNamingRule','preserve');
        if all(ismember({'time','darcyForceX'},D.Properties.VariableNames))
            td=double(D.time);
            fdRaw=double(D.darcyForceX);
            if ismember('mass',D.Properties.VariableNames)
                md=double(D.mass);
            else
                md=interp1(ts,mass,td,'linear',NaN);
            end
            good=isfinite(td)&isfinite(fdRaw)&isfinite(md)&md>0;
            td=td(good); fdRaw=fdRaw(good); md=md(good);
            [td,ord]=sort(td); fdRaw=fdRaw(ord); md=md(ord);
            [td,iu]=unique(td,'stable'); fdRaw=fdRaw(iu); md=md(iu);

            if numel(td)>=2
                uAtDarcy=interp1(ts,ug,td,'linear',NaN);
                [fDarcyFluid,darcyConvention,darcyOpposeFrac]= ...
                    local_select_darcy_fluid_sign(fdRaw,uAtDarcy,td);

                if ismember('darcyPower',D.Properties.VariableNames)
                    pwr=double(D.darcyPower);
                    pwr=pwr(good); pwr=pwr(ord); pwr=pwr(iu);
                    darcyPowerMean=mean(pwr,'omitnan');
                end

                tBudgetStart=max(ts(1),td(1));
                tBudgetEnd=min(ts(end),td(end));
                useD=td>=tBudgetStart & td<=tBudgetEnd;
                tdB=td(useD); fdB=fDarcyFluid(useD); mdB=md(useD);

                if numel(tdB)>=2 && tBudgetEnd>tBudgetStart
                    p0=interp1(ts,px,tBudgetStart,'linear');
                    p1=interp1(ts,px,tBudgetEnd,'linear');
                    deltaPxBudget=p1-p0;
                    pScaleBudget=max(abs(p0),eps);

                    bodyForce=ax*mdB;
                    bodyImpulse=trapz(tdB,bodyForce);
                    darcyImpulse=trapz(tdB,fdB);
                    otherImpulse=deltaPxBudget-bodyImpulse-darcyImpulse;

                    obsDeltaFracBudget=deltaPxBudget/pScaleBudget;
                    bodyFrac=bodyImpulse/pScaleBudget;
                    darcySinkFrac=-darcyImpulse/pScaleBudget;
                    otherSinkFrac=-otherImpulse/pScaleBudget;
                    sinkD=max(0,-darcyImpulse);
                    sinkO=max(0,-otherImpulse);
                    if sinkD+sinkO>0
                        darcySinkShare=sinkD/(sinkD+sinkO);
                    end
                    massTime=trapz(tdB,mdB);
                    if massTime>0
                        % Body acceleration that would balance the sinks measured
                        % along THIS decelerating trajectory.  Diagnostic only.
                        axHold=ax-deltaPxBudget/massTime;
                    end

                    % Interval force budget on summary midpoints, only where a
                    % Darcy force interpolation is supported by measured topo data.
                    dts=diff(ts);
                    midT=0.5*(ts(1:end-1)+ts(2:end));
                    midStep=0.5*(st(1:end-1)+st(2:end));
                    midM=0.5*(mass(1:end-1)+mass(2:end));
                    fNet=diff(px)./dts;
                    fBody=ax*midM;
                    fDarcy=interp1(td, fDarcyFluid, midT, 'linear', NaN);
                    supported=midT>=td(1)&midT<=td(end)&isfinite(fDarcy)&dts>0;
                    fOther=fNet-fBody-fDarcy;

                    B=table( ...
                        repmat(string(label),nnz(supported),1), ...
                        repmat(runKey,nnz(supported),1), ...
                        repmat(mode,nnz(supported),1), ...
                        midStep(supported),midT(supported),midM(supported), ...
                        fNet(supported),fBody(supported),fDarcy(supported),fOther(supported), ...
                        fNet(supported)./midM(supported), ...
                        fBody(supported)./midM(supported), ...
                        fDarcy(supported)./midM(supported), ...
                        fOther(supported)./midM(supported), ...
                        'VariableNames',{'caseName','runDir','mode','stepMid','timeMid','massMid', ...
                        'FnetX','FbodyX','FdarcyFluidX','FnonDarcyResidualX', ...
                        'anetX','abodyX','adarcyX','anonDarcyResidualX'});
                end
            end
        end
    end

    % Q6 summary diagnostics: sampled values only.  Do not turn them into a
    % cumulative impulse because x7k intentionally writes them only at summary
    % cadence whereas Q6 acts every step.
    q6CorrMean=NaN; q6CorrRms=NaN; q6CorrMax=NaN;
    q6ResidualMean=NaN; q6ResidualMax=NaN; q6AppliedFraction=NaN;
    if ismember('q6MomentumCorrectionVx',S.Properties.VariableNames)
        qv=double(S.q6MomentumCorrectionVx);
        q6CorrMean=mean(qv,'omitnan');
        q6CorrRms=sqrt(mean(qv.^2,'omitnan'));
        q6CorrMax=max(abs(qv),[],'omitnan');
    end
    if ismember('q6MomentumResidualBeforeCorrection',S.Properties.VariableNames)
        qr=double(S.q6MomentumResidualBeforeCorrection);
        q6ResidualMean=mean(qr,'omitnan');
        q6ResidualMax=max(qr,[],'omitnan');
    end
    if ismember('q6Applied',S.Properties.VariableNames)
        q6AppliedFraction=mean(double(S.q6Applied)>0,'omitnan');
    end

    % Optional signed species-Q6 audit.  It is useful to compare the raw Q6
    % momentum sampled before/around the closure, but remains a cadence-limited
    % diagnostic and is never integrated here.
    q6AuditPath=fullfile(outputDir,'cuda_species_q6_independent_masked_0493w5.csv');
    q6AuditPxPerMassMean=NaN; q6AuditPxPerMassRms=NaN; q6AuditPxPerMassMax=NaN;
    if isfile(q6AuditPath)
        A=readtable(q6AuditPath,'VariableNamingRule','preserve');
        if ismember('momentumX',A.Properties.VariableNames)
            apx=double(A.momentumX);
            if ismember('step',A.Properties.VariableNames)
                at=double(A.step);
                am=interp1(st,mass,at,'nearest',NaN);
            else
                at=(1:height(A)).';
                am=repmat(median(mass,'omitnan'),height(A),1);
            end
            adv=apx./am;
            q6AuditPxPerMassMean=mean(adv,'omitnan');
            q6AuditPxPerMassRms=sqrt(mean(adv.^2,'omitnan'));
            q6AuditPxPerMassMax=max(abs(adv),[],'omitnan');
            q6Tables{end+1,1}=table( ...
                repmat(string(label),height(A),1),repmat(runKey,height(A),1), ...
                repmat(mode,height(A),1),at,apx,am,adv, ...
                'VariableNames',{'caseName','runDir','mode','step','q6AuditMomentumX', ...
                'fluidMassNearest','q6AuditMomentumXPerMass'}); %#ok<AGROW>
        end
    end

    virtualPxMean=local_mean_var(S,'virtualMomentumX');
    wallHitsMean=NaN;
    if all(ismember({'hitsBottom','hitsTop'},S.Properties.VariableNames))
        wallHitsMean=mean(double(S.hitsBottom)+double(S.hitsTop),'omitnan');
    end

    runClass=local_run_class(runKey);
    res=local_resolution_label(runKey,nx,ny);
    isSmoke=contains(lower(runKey),'smoke');

    R=table( ...
        string(label),runKey,mode,runClass,res,double(isSmoke), ...
        nx,ny,rot,ax,dtParam,tStart,tEnd,uStart,uEnd,globalUFrac, ...
        uUpStart,uUpEnd,uUpFrac,pxStart,pxEnd,globalDeltaPx,globalDeltaFrac, ...
        double(hasTopo),string(darcyConvention),darcyOpposeFrac,darcyPowerMean, ...
        tBudgetStart,tBudgetEnd,deltaPxBudget,obsDeltaFracBudget, ...
        bodyImpulse,darcyImpulse,otherImpulse,bodyFrac,darcySinkFrac,otherSinkFrac, ...
        darcySinkShare,axHold, ...
        q6AppliedFraction,q6CorrMean,q6CorrRms,q6CorrMax,q6ResidualMean,q6ResidualMax, ...
        q6AuditPxPerMassMean,q6AuditPxPerMassRms,q6AuditPxPerMassMax, ...
        virtualPxMean,wallHitsMean,ugMismatch, ...
        string(summaryPath),string(topoPath),string(paramsPath), ...
        'VariableNames',{ ...
        'caseName','runDir','mode','runClass','resolution','isSmoke', ...
        'Nx','Ny','rotationAngle','bodyAccelerationX','dt', ...
        'timeStart','timeEnd','UglobalStart','UglobalEnd','UglobalDeltaFraction', ...
        'UupstreamStart','UupstreamEnd','UupstreamDeltaFraction', ...
        'PxStart','PxEnd','deltaPxGlobal','deltaPxGlobalFraction', ...
        'hasTopoForce','darcyForceConvention','darcyOpposesFlowFraction','darcyPowerMean', ...
        'budgetTimeStart','budgetTimeEnd','deltaPxBudget','deltaPxBudgetFraction', ...
        'bodyImpulseX','darcyFluidImpulseX','nonDarcyResidualImpulseX', ...
        'bodyImpulseOverP0','darcyMomentumSinkOverP0','nonDarcyMomentumSinkOverP0', ...
        'darcyShareOfResolvedSinks','bodyAccelerationToHoldCurrentTrajectory', ...
        'q6AppliedFraction','q6MomentumCorrectionVxMean','q6MomentumCorrectionVxRms', ...
        'q6MomentumCorrectionVxAbsMax','q6MomentumResidualBeforeCorrectionMean', ...
        'q6MomentumResidualBeforeCorrectionMax', ...
        'q6AuditMomentumXPerMassMean','q6AuditMomentumXPerMassRms','q6AuditMomentumXPerMassAbsMax', ...
        'virtualMomentumXMean','wallHitsBottomTopMean','summaryPxVsMeanVxMismatchMax', ...
        'summaryPath','topoPath','paramsPath'});

    summaryRows{end+1,1}=R; %#ok<AGROW>
    if ~isempty(B), budgetTables{end+1,1}=B; end %#ok<AGROW>

    if logical(opt.Verbose)
        fprintf('  Uglobal %.6g -> %.6g (%+.1f%%), Uup %.6g -> %.6g (%+.1f%%)\n', ...
            uStart,uEnd,100*globalUFrac,uUpStart,uUpEnd,100*uUpFrac);
        if hasTopo && isfinite(darcySinkFrac)
            fprintf('  budget dP/P0=%+.4f body=%+.4f DarcySink=%+.4f otherSink=%+.4f DarcyShare=%.3f\n', ...
                obsDeltaFracBudget,bodyFrac,darcySinkFrac,otherSinkFrac,darcySinkShare);
            fprintf('  Darcy sign=%s opposeFlow=%.3f  Ax=%.3e Ax_hold~%.3e\n', ...
                darcyConvention,darcyOpposeFrac,ax,axHold);
        else
            fprintf('  topo force unavailable/incomplete -> no Darcy split\n');
        end
        if isfinite(q6CorrRms)
            fprintf('  Q6 sampled k0 correction Vx: mean=%+.3e rms=%.3e max=%.3e\n', ...
                q6CorrMean,q6CorrRms,q6CorrMax);
        end
    end
end

assert(~isempty(summaryRows),'0493x7z:noUsableRuns','No run with a readable summary_runtime.csv was found.');
Sall=vertcat(summaryRows{:});

% Sort for readable output: resolution, class, mode, name.
try
    Sall=sortrows(Sall,{'resolution','runClass','mode','caseName'});
catch
end

summaryCsv=fullfile(outDir,'vk_momentum_budget_summary_0493x7z.csv');
writetable(Sall,summaryCsv);

if isempty(budgetTables)
    Ball=table();
else
    Ball=vertcat(budgetTables{:});
end
timeseriesCsv=fullfile(outDir,'vk_momentum_budget_timeseries_0493x7z.csv');
if ~isempty(Ball), writetable(Ball,timeseriesCsv); end

if isempty(q6Tables)
    Qall=table();
else
    Qall=vertcat(q6Tables{:});
end
q6Csv=fullfile(outDir,'vk_momentum_budget_q6_samples_0493x7z.csv');
if ~isempty(Qall), writetable(Qall,q6Csv); end

fprintf('\n===== 0493x7z SUMMARY: LONG RUNS, WORST Ux LOSS FIRST =====\n');
longMask=Sall.timeEnd-Sall.timeStart>=double(opt.LongRunMinTime) & Sall.isSmoke==0;
L=Sall(longMask,:);
if ~isempty(L)
    L=sortrows(L,'UglobalDeltaFraction','ascend');
    disp(L(:,{'caseName','mode','resolution','UglobalStart','UglobalEnd', ...
        'UupstreamEnd','deltaPxBudgetFraction','bodyImpulseOverP0', ...
        'darcyMomentumSinkOverP0','nonDarcyMomentumSinkOverP0', ...
        'darcyShareOfResolvedSinks','bodyAccelerationX', ...
        'bodyAccelerationToHoldCurrentTrajectory','q6MomentumCorrectionVxRms'}));
else
    fprintf('(no long runs according to LongRunMinTime)\n');
end

fprintf('\nInterpretation contract:\n');
fprintf('  Darcy sink = directly resolved from topo_benchmark force.\n');
fprintf('  nonDarcyResidual = observed dPx - body input - Darcy force.\n');
fprintf('  nonDarcyResidual is NOT automatically Q6: it also contains wall/collision/thermostat\n');
fprintf('  momentum exchange and cadence/discretization error.\n');
fprintf('  Q6 k0 columns are sampled diagnostics only and are NOT cumulatively integrated.\n');

plotPng=""; plotPdf="";
if logical(opt.MakePlots)
    [plotPng,plotPdf]=local_make_plots(Sall,Ball,X,outDir,opt);
end

out=struct();
out.summary=Sall;
out.timeseries=Ball;
out.q6Samples=Qall;
out.summaryCsv=string(summaryCsv);
out.timeseriesCsv=string(timeseriesCsv);
out.q6Csv=string(q6Csv);
out.plotPng=string(plotPng);
out.plotPdf=string(plotPdf);
out.x7uTimeseries=string(x7uFile);

fprintf('\n===== 0493x7z OUTPUTS =====\n');
fprintf('summary=%s\n',summaryCsv);
if ~isempty(Ball), fprintf('timeseries=%s\n',timeseriesCsv); end
if ~isempty(Qall), fprintf('q6Samples=%s\n',q6Csv); end
if strlength(string(plotPng))>0, fprintf('plot=%s\n',plotPng); end
fprintf('status=COMPLETE\n');
end

% =========================================================================
function [pngPath,pdfPath]=local_make_plots(S,B,X,outDir,opt)
pngPath=""; pdfPath="";
if logical(opt.ShowFigures)
    vis='on';
else
    vis='off';
end
f=figure('Name','0493x7z VK momentum budget','Visible',vis,'Color','w');
tl=tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');

plotMask=true(height(S),1);
if ~logical(opt.IncludeSmokesInPlots)
    plotMask=plotMask & S.isSmoke==0;
end
plotMask=plotMask & (S.timeEnd-S.timeStart>=double(opt.LongRunMinTime));
Sp=S(plotMask,:);

% Panel 1: normalized global momentum, using interval budget table.
ax1=nexttile(tl,1); hold(ax1,'on'); grid(ax1,'on');
if ~isempty(B)
    names=unique(B.caseName,'stable');
    for i=1:numel(names)
        name=names(i);
        if ~any(Sp.caseName==name), continue; end
        run=Sp(Sp.caseName==name,:);
        if isempty(run), continue; end
        % Reconstruct normalized P trend approximately by integrating Fnet from
        % interval table, anchored at 1 at the first plotted midpoint.
        Tb=B(B.caseName==name,:);
        if height(Tb)<2, continue; end
        tt=double(Tb.timeMid);
        fp=double(Tb.FnetX);
        mm=double(Tb.massMid);
        % Since Fnet=dP/dt and P~M*U, cumulative impulse is the exact interval
        % diagnostic represented by B. Normalize by the run's PxStart.
        imp=cumtrapz(tt,fp);
        pp=1+imp/max(abs(double(run.PxStart(1))),eps);
        plot(ax1,tt,pp,'DisplayName',char(local_plot_label(run(1,:))));
    end
end
xlabel(ax1,'time'); ylabel(ax1,'P_x/P_{x,0} (budget window)');
title(ax1,'Global streamwise momentum');

% Panel 2: x7u upstream velocity.
ax2=nexttile(tl,2); hold(ax2,'on'); grid(ax2,'on');
for i=1:height(Sp)
    key=Sp.runDir(i);
    TX=X(X.runDir==key,:);
    [tt,ord]=sort(double(TX.time));
    uu=double(TX.Uupstream(ord));
    plot(ax2,tt,uu,'DisplayName',char(local_plot_label(Sp(i,:))));
end
xlabel(ax2,'time'); ylabel(ax2,'U_{\infty}');
title(ax2,'Actual upstream velocity');

% Panel 3: integrated sink decomposition. Avoid categorical/bar to keep labels
% robust even when case labels collide.
ax3=nexttile(tl,3); hold(ax3,'on'); grid(ax3,'on');
n=height(Sp); yy=(1:n).';
if n>0
    plot(ax3,Sp.darcyMomentumSinkOverP0,yy,'o','DisplayName','Darcy sink / P_0');
    plot(ax3,Sp.nonDarcyMomentumSinkOverP0,yy,'x','DisplayName','non-Darcy residual sink / P_0');
    plot(ax3,-Sp.bodyImpulseOverP0,yy,'+','DisplayName','- body input / P_0');
    ytick=cell(n,1);
    for ii=1:n, ytick{ii}=char(local_plot_label(Sp(ii,:))); end
    set(ax3,'YTick',yy,'YTickLabel',ytick,'TickLabelInterpreter','none','YDir','reverse');
    legend(ax3,'Location','best');
end
xlabel(ax3,'positive = momentum sink');
title(ax3,'Integrated momentum budget');

% Panel 4: required Ax along current trajectory + Q6 closure sample magnitude.
ax4=nexttile(tl,4); hold(ax4,'on'); grid(ax4,'on');
if n>0
    plot(ax4,Sp.bodyAccelerationToHoldCurrentTrajectory,yy,'o','DisplayName','A_x needed to hold');
    plot(ax4,Sp.bodyAccelerationX,yy,'+','DisplayName','A_x used');
    set(ax4,'YTick',yy,'YTickLabel',repmat({''},n,1),'YDir','reverse');
    legend(ax4,'Location','best');
end
xlabel(ax4,'acceleration');
title(ax4,'Forcing deficit');

lg=legend(ax2,'Location','eastoutside','Interpreter','none');
try, lg.FontSize=7; catch, end

pngPath=fullfile(outDir,'vk_momentum_budget_0493x7z.png');
pdfPath=fullfile(outDir,'vk_momentum_budget_0493x7z.pdf');
exportgraphics(f,pngPath,'Resolution',180);
exportgraphics(f,pdfPath,'ContentType','vector');
end

% =========================================================================
function [fFluid,convention,opposeFrac]=local_select_darcy_fluid_sign(fRaw,u,t)
good=isfinite(fRaw)&isfinite(u)&abs(u)>1e-10&isfinite(t);
if nnz(good)<2
    fFluid=nan(size(fRaw)); convention="ambiguous"; opposeFrac=NaN; return;
end
w=fRaw(good).*u(good);
posFrac=mean(w>0);
negFrac=mean(w<0);
if posFrac>=0.60
    % Raw force follows the flow -> reaction/drag on obstacle. Fluid gets -raw.
    fFluid=-fRaw;
    convention="raw_reaction_on_obstacle__fluid_minus_raw";
elseif negFrac>=0.60
    fFluid=fRaw;
    convention="raw_force_on_fluid";
else
    % Darcy is dissipative. Choose the sign giving non-positive integrated
    % streamwise work proxy over the measured trajectory.
    workRaw=trapz(t(good),w);
    if workRaw<=0
        fFluid=fRaw;
        convention="auto_work__raw_force_on_fluid";
    else
        fFluid=-fRaw;
        convention="auto_work__fluid_minus_raw";
    end
end
prod=fFluid(good).*u(good);
opposeFrac=mean(prod<=0);
end

function pth=local_resolve_params(TX,runDir)
pth="";
if ismember('paramsFile',TX.Properties.VariableNames)
    p=string(TX.paramsFile(1));
    if strlength(p)>0
        pth=local_resolve_file(p);
        if strlength(pth)>0, return; end
    end
end
cands=[ ...
    string(fullfile(char(runDir),'output','params_used.kv')); ...
    string(fullfile(char(runDir),'params','vk_darcy_chi_periodic.kv')); ...
    string(fullfile(char(runDir),'params','params.kv'))];
for k=1:numel(cands)
    if isfile(cands(k)), pth=cands(k); return; end
end
d=dir(fullfile(char(runDir),'params','*.kv'));
if numel(d)==1, pth=string(fullfile(d(1).folder,d(1).name)); end
end

function pth=local_resolve_file(p)
pth="";
p=string(p);
if isfile(p), pth=p; return; end
q=string(fullfile('..',char(p)));
if isfile(q), pth=q; return; end
end

function runDir=local_resolve_run_dir(runKey)
runDir="";
r=string(runKey);
cands=[r; string(fullfile('..',char(r)))];
for k=1:numel(cands)
    if isfolder(cands(k)), runDir=cands(k); return; end
end
end

function s=local_parse_kv(path)
s=struct();
if strlength(string(path))==0 || ~isfile(path), return; end
txt=splitlines(string(fileread(path)));
for i=1:numel(txt)
    line=strtrim(txt(i));
    if strlength(line)==0 || startsWith(line,"#"), continue; end
    h=strfind(line,"#"); if ~isempty(h), line=strtrim(extractBefore(line,h(1))); end
    k=strfind(line,"="); if isempty(k), continue; end
    key=strtrim(extractBefore(line,k(1)));
    val=strtrim(extractAfter(line,k(1)));
    if strlength(key)==0, continue; end
    key=matlab.lang.makeValidName(char(key));
    s.(key)=char(val);
end
end

function v=local_get_num(s,key,default)
v=default;
key=matlab.lang.makeValidName(key);
if isfield(s,key)
    x=str2double(string(s.(key)));
    if isfinite(x), v=x; end
end
end

function v=local_get_str(s,key,default)
v=char(default);
key=matlab.lang.makeValidName(key);
if isfield(s,key)
    x=strtrim(string(s.(key)));
    if strlength(x)>0, v=char(x); end
end
end

function local_require_vars(T,names,who)
missing=names(~ismember(names,T.Properties.VariableNames));
if ~isempty(missing)
    error('0493x7z:missingColumns','%s missing columns: %s',who,strjoin(missing,', '));
end
end

function x=local_first_finite(v)
i=find(isfinite(v),1,'first'); if isempty(i), x=NaN; else, x=v(i); end
end
function x=local_last_finite(v)
i=find(isfinite(v),1,'last'); if isempty(i), x=NaN; else, x=v(i); end
end

function x=local_mean_var(T,name)
if ismember(name,T.Properties.VariableNames)
    x=mean(double(T.(name)),'omitnan');
else
    x=NaN;
end
end

function c=local_case_label(runKey,mode)
r=replace(string(runKey),"\","/");
parts=split(r,"/");
parts(parts=="")=[];
if numel(parts)>=2
    c=parts(end-1)+"/"+parts(end);
else
    c=r+" / "+mode;
end
end

function c=local_run_class(runKey)
r=lower(replace(string(runKey),"\","/"));
if contains(r,'x7qoff') || contains(r,'x7y')
    c="x7q_ablation";
elseif contains(r,'div0_b1off') || contains(r,'b1off')
    c="div0_b1off";
elseif contains(r,'div0_b1on')
    c="div0_b1on";
elseif contains(r,'0434_vk_darcy_chi_periodic')
    c="baseline";
elseif contains(r,'smoke')
    c="smoke";
else
    c="other";
end
end

function c=local_resolution_label(runKey,nx,ny)
r=replace(string(runKey),"\","/");
tok=regexp(char(r),'(\d+)x(\d+)','tokens','once');
if ~isempty(tok)
    c=string(tok{1})+"x"+string(tok{2});
elseif isfinite(nx)&&isfinite(ny)
    c=string(round(nx))+"x"+string(round(ny));
else
    c="unknown";
end
end

function s=local_plot_label(row)
s=row.resolution+" | "+row.runClass+" | "+row.mode;
end

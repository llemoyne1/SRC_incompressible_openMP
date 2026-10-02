function analyze_0493x24bc_sato_jet_profiles()
% ANALYZE_0493X24BC_SATO_JET_PROFILES
% Offline x24b/x24c comparison using the fields ACTUALLY recorded in the runs:
%   rho, ux, uy
% The authoritative manifest shows that rho1/rho2 were not recorded.
%
% x24b was recorded with smoothPasses=3 and x24c with smoothPasses=0.
% To make the comparison observationally homogeneous, this script applies
% the recorder's exact 3x3 box smoother offline to x24c until both datasets
% have the same effective smoothPasses (= max of both manifests).
%
% Since species-resolved rho2 is absent, the momentum-flux quantity is a
% gas-region proxy
%       Jdown = rho_total * max(-uy,0)^2 / cellArea
% masked using the independently reconstructed incident gas density stored in
% sato_stageA_recording_history.csv. Cells whose total recorded mass exceeds
% 3 times the expected gas-cell mass are excluded as liquid-contaminated.
%
% This remains an OFFLINE diagnostic. It does not modify simulation data.

close all;
root = fileparts(mfilename('fullpath'));
runsRoot = fullfile(root,'..','runs');

cases = struct([]);
cases(1).tag='x24b_H0p8';
cases(1).runDir=fullfile(runsRoot,'0493x24b_sato_anchor_H0p8_Fr0p90_seed493205');
cases(1).HoverD=0.8;
cases(2).tag='x24c_H1p7';
cases(2).runDir=fullfile(runsRoot,'0493x24c_sato_corrected_H1p7_Fr0p90_seed493205');
cases(2).HoverD=1.7;

stepMin=3000; stepMax=4000;
zOverDList=[0.25 0.50 1.00];
bandThicknessOverD=0.20;
D=20*0.00390625;
jetCenterX=0.5*1.5625;
liquidRejectFactor=3.0;
metricWindowOverD=4.0;

% First read manifests and establish common observational smoothing.
for ic=1:numel(cases)
    recRoots=findRecordingRoots(fullfile(cases(ic).runDir,'output','recordings'));
    assert(~isempty(recRoots),'No recording timeline under %s',cases(ic).runDir);
    man=readManifest(fullfile(recRoots{1},'manifest.kv'));
    cases(ic).smoothPasses=str2double(getfielddef(man,'smoothPasses','0')); %#ok<GFLD>
    cases(ic).recordFields=getfielddef(man,'recordFields',''); %#ok<GFLD>
    fprintf('%s manifest: recordFields=%s smoothPasses=%g\n',cases(ic).tag,cases(ic).recordFields,cases(ic).smoothPasses);
end
targetSmooth=max([cases.smoothPasses]);
fprintf('Common effective smoothing for comparison: %g pass(es)\n',targetSmooth);

allSummary=table();
profileStore=cell(numel(cases),numel(zOverDList));

for ic=1:numel(cases)
    C=cases(ic);
    fprintf('\n===== %s =====\n',C.tag);
    assert(isfolder(C.runDir),'Missing run directory: %s',C.runDir);

    histPath=fullfile(C.runDir,'analysis','sato_stageA_recording_history.csv');
    assert(isfile(histPath),'Missing interface history: %s',histPath);
    H=readtable(histPath,'VariableNamingRule','preserve');
    assert(any(strcmp(H.Properties.VariableNames,'etaFar')),'etaFar missing in %s',histPath);
    assert(any(strcmp(H.Properties.VariableNames,'incidentGasMassDensity')), ...
        'incidentGasMassDensity missing in %s',histPath);

    recRoots=findRecordingRoots(fullfile(C.runDir,'output','recordings'));
    frames=collectFrames(recRoots,stepMin,stepMax);
    assert(~isempty(frames),'No rho+uy recording frames in [%d,%d] for %s',stepMin,stepMax,C.tag);
    [~,ia]=unique([frames.step],'stable'); frames=frames(ia);
    fprintf('frames in window: %d (steps %d ... %d)\n',numel(frames),frames(1).step,frames(end).step);

    extraSmooth=max(0,targetSmooth-C.smoothPasses);
    fprintf('offline extra smoothing: %g pass(es)\n',extraSmooth);

    for iz=1:numel(zOverDList)
        zD=zOverDList(iz);
        metrics=struct('integratedJ',{},'peakJ',{},'FWHM',{},'sigmaJ',{},'centroidX',{}, ...
            'step',{},'time',{},'etaFar',{},'yProbe',{},'expectedGasCellMass',{},'acceptedFraction',{});
        Jstack=[]; MaskStack=[]; Ustack=[]; xRef=[];

        for k=1:numel(frames)
            F=frames(k);
            ih=nearestHistoryRow(H,F.step);
            etaFar=H.etaFar(ih);
            rhoG=H.incidentGasMassDensity(ih);
            if ~isfinite(etaFar) || ~isfinite(rhoG) || rhoG<=0, continue; end

            rho=readF32(F.rho,F.nx,F.ny);
            uy =readF32(F.uy, F.nx,F.ny);
            if extraSmooth>0
                rho=smoothScalarRecorder(rho,extraSmooth);
                uy =smoothScalarRecorder(uy, extraSmooth);
            end

            dx=F.Lx/F.nx; dy=F.Ly/F.ny; cellArea=dx*dy;
            x=((1:F.nx)-0.5)*dx;
            y=((1:F.ny)-0.5)*dy;
            yProbe=etaFar+zD*D;
            halfBand=0.5*bandThicknessOverD*D;
            iy=find(abs(y-yProbe)<=halfBand);
            if isempty(iy), [~,i0]=min(abs(y-yProbe)); iy=i0; end

            rr=mean(rho(iy,:),1,'omitnan');
            vv=mean(uy(iy,:),1,'omitnan');

            expectedGasCellMass=rhoG*cellArea;
            gasMask=isfinite(rr) & rr>0 & rr<=liquidRejectFactor*expectedGasCellMass;
            J=(rr/cellArea).*max(-vv,0).^2;
            J(~gasMask)=NaN;

            if isempty(xRef), xRef=x; end
            Jstack(end+1,:)=J; %#ok<AGROW>
            MaskStack(end+1,:)=double(gasMask); %#ok<AGROW>
            Ustack(end+1,:)=vv; %#ok<AGROW>

            M=profileMetrics(x,J,jetCenterX,metricWindowOverD*D);
            M.step=F.step; M.time=F.time; M.etaFar=etaFar; M.yProbe=yProbe;
            M.expectedGasCellMass=expectedGasCellMass;
            M.acceptedFraction=mean(gasMask);
            metrics(end+1)=M; %#ok<AGROW>
        end

        assert(~isempty(metrics),'No usable profiles for %s z/D=%g',C.tag,zD);
        Jmean=mean(Jstack,1,'omitnan');
        maskMean=mean(MaskStack,1,'omitnan');
        uyMean=mean(Ustack,1,'omitnan');
        profileStore{ic,iz}=struct('x',xRef,'J',Jmean,'accepted',maskMean,'uy',uyMean);

        Tm=struct2table(metrics);
        outCase=fullfile(C.runDir,'analysis');
        writetable(Tm,fullfile(outCase,sprintf('sato_jet_profile_metrics_zD_%0.2f.csv',zD)));
        Tp=table(xRef(:),Jmean(:),maskMean(:),uyMean(:), ...
            'VariableNames',{'x','meanJdownProxy','acceptedFrameFraction','meanUy'});
        writetable(Tp,fullfile(outCase,sprintf('sato_jet_profile_mean_zD_%0.2f.csv',zD)));

        row=table(string(C.tag),C.HoverD,zD,height(Tm),C.smoothPasses,targetSmooth, ...
            mean(Tm.integratedJ,'omitnan'),std(Tm.integratedJ,'omitnan'), ...
            mean(Tm.peakJ,'omitnan'),std(Tm.peakJ,'omitnan'), ...
            mean(Tm.FWHM,'omitnan'),std(Tm.FWHM,'omitnan'), ...
            mean(Tm.sigmaJ,'omitnan'),std(Tm.sigmaJ,'omitnan'), ...
            mean(Tm.centroidX,'omitnan'),mean(Tm.acceptedFraction,'omitnan'), ...
            'VariableNames',{'caseTag','HOverD','zOverD','nFrames','nativeSmoothPasses','effectiveSmoothPasses', ...
            'meanIntegratedJ','stdIntegratedJ','meanPeakJ','stdPeakJ','meanFWHM','stdFWHM', ...
            'meanSigmaJ','stdSigmaJ','meanCentroidX','meanAcceptedFraction'});
        allSummary=[allSummary;row]; %#ok<AGROW>
    end
end

cmpDir=fullfile(runsRoot,'0493x24bc_sato_jet_profile_comparison');
if ~isfolder(cmpDir), mkdir(cmpDir); end
writetable(allSummary,fullfile(cmpDir,'sato_jet_profile_comparison_summary.csv'));

ratioTable=table();
for iz=1:numel(zOverDList)
    zD=zOverDList(iz);
    B=allSummary(allSummary.HOverD==0.8 & abs(allSummary.zOverD-zD)<1e-12,:);
    C=allSummary(allSummary.HOverD==1.7 & abs(allSummary.zOverD-zD)<1e-12,:);
    if height(B)==1 && height(C)==1
        rr=table(zD,C.meanIntegratedJ/B.meanIntegratedJ,C.meanPeakJ/B.meanPeakJ, ...
            C.meanFWHM/B.meanFWHM,C.meanSigmaJ/B.meanSigmaJ, ...
            'VariableNames',{'zOverD','ratioIntegratedJ_CoverB','ratioPeakJ_CoverB','ratioFWHM_CoverB','ratioSigmaJ_CoverB'});
        ratioTable=[ratioTable;rr]; %#ok<AGROW>
    end
end
writetable(ratioTable,fullfile(cmpDir,'sato_jet_profile_ratios_x24c_over_x24b.csv'));

for iz=1:numel(zOverDList)
    zD=zOverDList(iz);
    fig=figure('Color','w','Name',sprintf('Sato J proxy z/D=%g',zD)); hold on; box on;
    for ic=1:numel(cases)
        P=profileStore{ic,iz};
        plot((P.x-jetCenterX)/D,P.J,'LineWidth',1.5,'DisplayName',sprintf('%s, H/D=%.1f',cases(ic).tag,cases(ic).HoverD));
    end
    xlabel('(x-x_c)/D'); ylabel('<rho_{tot} max(-u_y,0)^2> gas-masked');
    title(sprintf('Incident momentum-flux proxy, z/D = %.2f',zD));
    legend('Location','best'); grid on; xlim([-4 4]);
    saveas(fig,fullfile(cmpDir,sprintf('sato_Jdown_profiles_zD_%0.2f.png',zD)));
end

rep=fopen(fullfile(cmpDir,'sato_jet_profile_comparison_report.txt'),'w');
fprintf(rep,'0493x24b / x24c Sato incident-jet profile comparison V3\n');
fprintf(rep,'=======================================================\n');
fprintf(rep,'Window: steps %d:%d\n',stepMin,stepMax);
fprintf(rep,'Actual recorded fields: rho,ux,uy (rho1/rho2 were NOT recorded).\n');
fprintf(rep,'x24b native smoothPasses=%g; x24c native smoothPasses=%g.\n',cases(1).smoothPasses,cases(2).smoothPasses);
fprintf(rep,'Comparison equalized offline to %g recorder-compatible 3x3 box passes.\n',targetSmooth);
fprintf(rep,'Proxy: rho_total*max(-uy,0)^2/cellArea, masked where rho_total > %.3g expected gas-cell masses.\n',liquidRejectFactor);
fprintf(rep,'Expected gas mass comes from incidentGasMassDensity in the existing x14at dense-history analysis.\n');
fprintf(rep,'This is an advective gas-region proxy, NOT species-resolved rho_g and NOT a full stress tensor.\n\n');
for i=1:height(allSummary)
    r=allSummary(i,:);
    fprintf(rep,'%s z/D=%.2f: intJ=%.8g peakJ=%.8g FWHM/D=%.5g sigmaJ/D=%.5g accepted=%.4f\n', ...
        r.caseTag,r.zOverD,r.meanIntegratedJ,r.meanPeakJ,r.meanFWHM/D,r.meanSigmaJ/D,r.meanAcceptedFraction);
end
fprintf(rep,'\nRatios x24c/x24b:\n');
for i=1:height(ratioTable)
    r=ratioTable(i,:);
    fprintf(rep,'z/D=%.2f: intJ=%.5g peakJ=%.5g FWHM=%.5g sigmaJ=%.5g\n', ...
        r.zOverD,r.ratioIntegratedJ_CoverB,r.ratioPeakJ_CoverB,r.ratioFWHM_CoverB,r.ratioSigmaJ_CoverB);
end
fclose(rep);

fprintf('\nAnalysis complete.\nComparison outputs: %s\n',cmpDir);
disp(allSummary); disp(ratioTable);
end

function roots=findRecordingRoots(base)
roots={}; if ~isfolder(base), return; end
d=dir(fullfile(base,'**','timeline.csv'));
for i=1:numel(d), roots{end+1}=d(i).folder; end %#ok<AGROW>
end

function frames=collectFrames(roots,stepMin,stepMax)
frames=struct('step',{},'time',{},'nx',{},'ny',{},'Lx',{},'Ly',{},'rho',{},'uy',{});
for ir=1:numel(roots)
    root=roots{ir};
    tl=readtable(fullfile(root,'timeline.csv'),'VariableNamingRule','preserve');
    man=readManifest(fullfile(root,'manifest.kv'));
    Lx=str2double(man.Lx); Ly=str2double(man.Ly);
    steps=unique(tl.step(tl.step>=stepMin & tl.step<=stepMax));
    for is=1:numel(steps)
        s=steps(is); rows=tl(tl.step==s,:);
        pr=fieldPath(rows,root,'rho'); py=fieldPath(rows,root,'uy');
        if isempty(pr) || isempty(py), continue; end
        F.step=s; F.time=rows.time(1); F.nx=rows.nx(1); F.ny=rows.ny(1);
        F.Lx=Lx; F.Ly=Ly; F.rho=pr; F.uy=py;
        frames(end+1)=F; %#ok<AGROW>
    end
end
if ~isempty(frames), [~,ord]=sort([frames.step]); frames=frames(ord); end
end

function p=fieldPath(rows,root,field)
idx=find(strcmp(string(rows.field),field),1);
if isempty(idx), p=''; else, p=fullfile(root,char(rows.file(idx))); end
end

function S=readManifest(path)
S=struct(); lines=splitlines(fileread(path));
for i=1:numel(lines)
    q=strtrim(lines{i}); if isempty(q) || startsWith(q,'#'), continue; end
    k=strfind(q,'='); if isempty(k), continue; end
    key=matlab.lang.makeValidName(strtrim(q(1:k(1)-1))); S.(key)=strtrim(q(k(1)+1:end));
end
end

function v=getfielddef(S,name,default)
if isfield(S,name), v=S.(name); else, v=default; end
end

function A=readF32(path,nx,ny)
fid=fopen(path,'rb'); assert(fid>=0,'Cannot open %s',path); c=onCleanup(@() fclose(fid));
v=fread(fid,nx*ny,'single=>double'); assert(numel(v)==nx*ny,'Unexpected size in %s',path);
A=reshape(v,[nx,ny]).';
end

function A=smoothScalarRecorder(A,passes)
% Exact analogue of smooth_scalar_0432: 3x3 arithmetic mean, clipped at edges.
[ny,nx]=size(A);
for p=1:passes
    old=A; new=zeros(size(A));
    for iy=1:ny
        y0=max(1,iy-1); y1=min(ny,iy+1);
        for ix=1:nx
            x0=max(1,ix-1); x1=min(nx,ix+1);
            q=old(y0:y1,x0:x1); new(iy,ix)=mean(q(:));
        end
    end
    A=new;
end
end

function i=nearestHistoryRow(H,step)
[~,i]=min(abs(H.step-step));
end

function M=profileMetrics(x,J,xc,halfWindow)
valid=isfinite(J) & J>=0 & abs(x-xc)<=halfWindow;
Jv=J; Jv(~valid)=0;
integ=trapz(x,Jv); [peak,~]=max(Jv);
if integ>0
    cen=trapz(x,x.*Jv)/integ;
    sig=sqrt(max(0,trapz(x,(x-cen).^2.*Jv)/integ));
else
    cen=NaN; sig=NaN;
end
fwhm=NaN;
if peak>0
    ids=find(Jv>=0.5*peak);
    if ~isempty(ids), fwhm=x(ids(end))-x(ids(1)); end
end
M=struct('integratedJ',integ,'peakJ',peak,'FWHM',fwhm,'sigmaJ',sig,'centroidX',cen);
end

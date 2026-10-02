function analyze_0493x24bc_sato_level_volume_bias()
% ANALYZE_0493X24BC_SATO_LEVEL_VOLUME_BIAS
% Offline decomposition of the apparent free-surface rise for Sato x24b/x24c.
%
% Purpose
% -------
% Separate, as far as the recorded liquid-density field allows, three effects:
%   (1) geometric liquid-area excess reconstructed from the liquid recording;
%   (2) physical far-field rise caused by redistribution around the cavity;
%   (3) local cavity depth.
%
% The analysis reproduces the interface reconstruction used by
% analyze_0493x14at_sato_stageA_recording.py:
%   alpha = clip(rho_liquid_record / nominal_liquid_mass_per_record_cell,0,1)
%   then one cross smoother with lambda=0.125 before alpha=0.5 crossing.
%
% IMPORTANT
% ---------
% - This is an OFFLINE diagnostic. It does not alter any run.
% - 'rho' must be the LIQUID-filtered recording used by the historical Sato
%   recording analyser (recordMode=liquid_rho). The script reports the manifest
%   particleTypeFilter and refuses roots that do not contain rho.
% - Area excess is a geometric occupancy diagnostic, not particle mass.
% - The corrected Sato-like depth is diagnostic only until the area-offset
%   interpretation is independently accepted:
%       h_corr = (eta0 - etaMin) + (A_L(t)-A_L(0))/Lx.
%
% Outputs are written under
%   ../runs/0493x24bc_sato_level_volume_bias/
% and per-case CSV files under each run's analysis directory.

close all;
root = fileparts(mfilename('fullpath'));
runsRoot = fullfile(root,'..','runs');

cases = struct([]);
cases(1).tag='x24b_H0p8';
cases(1).runDir=fullfile(runsRoot,'0493x24b_sato_anchor_H0p8_Fr0p90_seed493205');
cases(1).HOverD=0.8;
cases(2).tag='x24c_H1p7';
cases(2).runDir=fullfile(runsRoot,'0493x24c_sato_corrected_H1p7_Fr0p90_seed493205');
cases(2).HOverD=1.7;

% Authoritative geometry for x24b/x24c.
Lx = 1.5625;
LyDefault = 1.0; %#ok<NASGU>
h = 0.00390625;
D = 20*h;
eta0 = 0.78125;       % initial bath height = 10 D
rhoLiquid = 20/(h*h); % nominal liquid mass density from gamma=20, mL=1
stepWindow = [3000 4000];

cmpDir=fullfile(runsRoot,'0493x24bc_sato_level_volume_bias');
if ~isfolder(cmpDir), mkdir(cmpDir); end

allSummary=table();
allHist=cell(numel(cases),1);

for ic=1:numel(cases)
    C=cases(ic);
    fprintf('\n===== %s =====\n',C.tag);
    assert(isfolder(C.runDir),'Missing run directory: %s',C.runDir);

    recRoots=findRecordingRoots(fullfile(C.runDir,'output','recordings'));
    assert(~isempty(recRoots),'No recording timeline under %s',C.runDir);
    [recRoot,man]=chooseLiquidRecordingRoot(recRoots);
    fprintf('recording root: %s\n',recRoot);
    fprintf('manifest: recordFields=%s particleTypeFilter=%s smoothPasses=%s\n', ...
        getfielddef(man,'recordFields','?'),getfielddef(man,'particleTypeFilter','?'),getfielddef(man,'smoothPasses','?'));

    frames=collectRhoFrames(recRoot);
    assert(~isempty(frames),'No rho frames in %s',recRoot);
    fprintf('rho frames: %d (steps %d ... %d)\n',numel(frames),frames(1).step,frames(end).step);

    rows=struct('step',{},'time',{},'nx',{},'ny',{},'Lx',{},'Ly',{}, ...
        'areaAlphaRaw',{},'areaAlphaSmooth',{},'areaExcessRaw',{},'areaExcessSmooth',{}, ...
        'equivLevelAreaRaw',{},'equivLevelAreaSmooth',{}, ...
        'etaMean',{},'etaMeanShift',{},'etaFar',{},'etaMin',{}, ...
        'rawDepthFromInitial',{},'localDepthRelativeFar',{}, ...
        'correctedDepthArea',{},'correctedFarLevel',{},'correctedFarShift',{}, ...
        'areaMeanConsistency',{},'validSurfaceFraction',{});

    A0raw=NaN; A0smooth=NaN; etaMean0=NaN;
    for k=1:numel(frames)
        F=frames(k);
        rho=readF32(F.rho,F.nx,F.ny);
        dx=F.Lx/F.nx; dy=F.Ly/F.ny; cellArea=dx*dy;
        refMass=rhoLiquid*cellArea;
        alphaRaw=min(1,max(0,rho/refMass));
        alphaSmooth=smoothCross(alphaRaw,0.125);

        Araw=sum(alphaRaw(:),'omitnan')*cellArea;
        Asmooth=sum(alphaSmooth(:),'omitnan')*cellArea;
        eta=surfaceFromAlpha(alphaSmooth,F.Lx,F.Ly);
        [etaFar,etaMin,etaMean,validFrac]=surfaceMetrics(eta,F.Lx,0.5*Lx,D);

        if k==1
            A0raw=Araw; A0smooth=Asmooth; etaMean0=etaMean;
        end
        dAraw=Araw-A0raw;
        dAsmooth=Asmooth-A0smooth;
        dEtaRaw=dAraw/F.Lx;
        dEtaSmooth=dAsmooth/F.Lx;
        etaMeanShift=etaMean-etaMean0;
        hRaw=eta0-etaMin;
        hLocal=etaFar-etaMin;
        hCorr=hRaw+dEtaSmooth;
        etaFarCorr=etaFar-dEtaSmooth;
        farCorrShift=etaFarCorr-eta0;
        consistency=etaMeanShift-dEtaSmooth;

        R.step=F.step; R.time=F.time; R.nx=F.nx; R.ny=F.ny; R.Lx=F.Lx; R.Ly=F.Ly;
        R.areaAlphaRaw=Araw; R.areaAlphaSmooth=Asmooth;
        R.areaExcessRaw=dAraw; R.areaExcessSmooth=dAsmooth;
        R.equivLevelAreaRaw=dEtaRaw; R.equivLevelAreaSmooth=dEtaSmooth;
        R.etaMean=etaMean; R.etaMeanShift=etaMeanShift; R.etaFar=etaFar; R.etaMin=etaMin;
        R.rawDepthFromInitial=hRaw; R.localDepthRelativeFar=hLocal;
        R.correctedDepthArea=hCorr; R.correctedFarLevel=etaFarCorr; R.correctedFarShift=farCorrShift;
        R.areaMeanConsistency=consistency; R.validSurfaceFraction=validFrac;
        rows(end+1)=R; %#ok<AGROW>
    end

    T=struct2table(rows);
    allHist{ic}=T;
    outCase=fullfile(C.runDir,'analysis');
    writetable(T,fullfile(outCase,'sato_level_volume_bias_history.csv'));

    W=T(T.step>=stepWindow(1) & T.step<=stepWindow(2),:);
    assert(height(W)>=5,'Too few samples in analysis window for %s',C.tag);

    S=table(string(C.tag),C.HOverD,height(W), ...
        mean(W.equivLevelAreaSmooth,'omitnan')/D, std(W.equivLevelAreaSmooth,'omitnan')/D, ...
        mean(W.etaMeanShift,'omitnan')/D, ...
        mean(W.etaFar-eta0,'omitnan')/D, ...
        mean(W.correctedFarShift,'omitnan')/D, ...
        mean(W.rawDepthFromInitial,'omitnan')/D, ...
        mean(W.correctedDepthArea,'omitnan')/D, ...
        mean(W.localDepthRelativeFar,'omitnan')/D, ...
        relDrift(W.time,W.rawDepthFromInitial), ...
        relDrift(W.time,W.correctedDepthArea), ...
        relDrift(W.time,W.localDepthRelativeFar), ...
        mean(abs(W.areaMeanConsistency),'omitnan')/D, ...
        mean(W.validSurfaceFraction,'omitnan'), ...
        'VariableNames',{'caseTag','HOverD','nWindowSamples', ...
        'meanAreaEquivalentRiseOverD','stdAreaEquivalentRiseOverD','meanEtaMeanShiftOverD', ...
        'meanFarShiftRawOverD','meanFarShiftAfterAreaCorrectionOverD', ...
        'meanRawDepthOverD','meanAreaCorrectedDepthOverD','meanLocalDepthOverD', ...
        'relativeDriftRawDepth','relativeDriftAreaCorrectedDepth','relativeDriftLocalDepth', ...
        'meanAbsAreaMeanMismatchOverD','meanValidSurfaceFraction'});
    allSummary=[allSummary;S]; %#ok<AGROW>

    fprintf('window %d:%d\n',stepWindow(1),stepWindow(2));
    fprintf('  area-equivalent rise /D = %.6g +/- %.3g\n',S.meanAreaEquivalentRiseOverD,S.stdAreaEquivalentRiseOverD);
    fprintf('  mean-surface rise /D    = %.6g\n',S.meanEtaMeanShiftOverD);
    fprintf('  far rise raw /D         = %.6g\n',S.meanFarShiftRawOverD);
    fprintf('  far rise corrected /D   = %.6g\n',S.meanFarShiftAfterAreaCorrectionOverD);
    fprintf('  h_raw/D                  = %.6g  drift=%.4g\n',S.meanRawDepthOverD,S.relativeDriftRawDepth);
    fprintf('  h_areaCorr/D             = %.6g  drift=%.4g\n',S.meanAreaCorrectedDepthOverD,S.relativeDriftAreaCorrectedDepth);
    fprintf('  h_local/D                = %.6g  drift=%.4g\n',S.meanLocalDepthOverD,S.relativeDriftLocalDepth);
end

writetable(allSummary,fullfile(cmpDir,'sato_level_volume_bias_summary.csv'));

% Combined histories on a common normalized representation.
fig=figure('Color','w','Name','Sato level decomposition'); hold on; box on; grid on;
for ic=1:numel(cases)
    T=allHist{ic};
    plot(T.time,T.equivLevelAreaSmooth/D,'LineWidth',1.5,'DisplayName',sprintf('%s: area-equivalent rise',cases(ic).tag));
    plot(T.time,T.etaMeanShift/D,'--','LineWidth',1.2,'DisplayName',sprintf('%s: mean-surface rise',cases(ic).tag));
end
xlabel('time'); ylabel('rise / D');
title('Geometric liquid-area excess versus mean free-surface rise');
legend('Location','best');
saveas(fig,fullfile(cmpDir,'sato_level_area_vs_mean_surface.png'));

fig=figure('Color','w','Name','Sato depth decomposition'); hold on; box on; grid on;
for ic=1:numel(cases)
    T=allHist{ic};
    plot(T.time,T.rawDepthFromInitial/D,':','LineWidth',1.1,'DisplayName',sprintf('%s: h raw',cases(ic).tag));
    plot(T.time,T.correctedDepthArea/D,'-','LineWidth',1.6,'DisplayName',sprintf('%s: h area-corrected',cases(ic).tag));
    plot(T.time,T.localDepthRelativeFar/D,'--','LineWidth',1.3,'DisplayName',sprintf('%s: h local',cases(ic).tag));
end
xlabel('time'); ylabel('depth / D');
title('Raw, area-corrected and local cavity depth');
legend('Location','best');
saveas(fig,fullfile(cmpDir,'sato_depth_raw_corrected_local.png'));

fig=figure('Color','w','Name','Sato far level correction'); hold on; box on; grid on;
for ic=1:numel(cases)
    T=allHist{ic};
    plot(T.time,(T.etaFar-eta0)/D,':','LineWidth',1.1,'DisplayName',sprintf('%s: far raw',cases(ic).tag));
    plot(T.time,T.correctedFarShift/D,'-','LineWidth',1.6,'DisplayName',sprintf('%s: far after area correction',cases(ic).tag));
end
xlabel('time'); ylabel('(eta_{far}-eta_0)/D');
title('Far-field level before and after geometric-area correction');
legend('Location','best');
saveas(fig,fullfile(cmpDir,'sato_far_level_raw_corrected.png'));

rep=fopen(fullfile(cmpDir,'sato_level_volume_bias_report.txt'),'w');
fprintf(rep,'0493x24b/x24c Sato free-surface level / geometric-volume offline analysis\n');
fprintf(rep,'=======================================================================\n');
fprintf(rep,'No simulation data were modified. Interface reconstruction follows the historical liquid-rho analyser.\n');
fprintf(rep,'D=%.12g, Lx=%.12g, eta0=%.12g, rhoLiquid=%.12g.\n',D,Lx,eta0,rhoLiquid);
fprintf(rep,'Window: steps %d:%d.\n\n',stepWindow(1),stepWindow(2));
fprintf(rep,'Definitions:\n');
fprintf(rep,'  delta_eta_area = (A_L(t)-A_L(first recorded frame))/Lx\n');
fprintf(rep,'  h_raw          = eta0-etaMin\n');
fprintf(rep,'  h_areaCorr     = h_raw + delta_eta_area\n');
fprintf(rep,'  h_local        = etaFar-etaMin\n');
fprintf(rep,'  etaFarCorr     = etaFar-delta_eta_area\n');
fprintf(rep,'Area is reconstructed from clipped liquid occupancy alpha and is a GEOMETRIC diagnostic, not particle mass.\n\n');
for i=1:height(allSummary)
    s=allSummary(i,:);
    fprintf(rep,'%s (H/D=%.1f):\n',s.caseTag,s.HOverD);
    fprintf(rep,'  <delta_eta_area>/D       = %.8g +/- %.3g\n',s.meanAreaEquivalentRiseOverD,s.stdAreaEquivalentRiseOverD);
    fprintf(rep,'  <delta_eta_mean>/D       = %.8g\n',s.meanEtaMeanShiftOverD);
    fprintf(rep,'  <etaFar-eta0>/D raw      = %.8g\n',s.meanFarShiftRawOverD);
    fprintf(rep,'  <etaFarCorr-eta0>/D      = %.8g\n',s.meanFarShiftAfterAreaCorrectionOverD);
    fprintf(rep,'  <h_raw>/D                = %.8g ; relative drift=%.6g\n',s.meanRawDepthOverD,s.relativeDriftRawDepth);
    fprintf(rep,'  <h_areaCorr>/D           = %.8g ; relative drift=%.6g\n',s.meanAreaCorrectedDepthOverD,s.relativeDriftAreaCorrectedDepth);
    fprintf(rep,'  <h_local>/D              = %.8g ; relative drift=%.6g\n',s.meanLocalDepthOverD,s.relativeDriftLocalDepth);
    fprintf(rep,'  <|delta_eta_mean-delta_eta_area|>/D = %.8g\n',s.meanAbsAreaMeanMismatchOverD);
    fprintf(rep,'  valid surface fraction   = %.6g\n\n',s.meanValidSurfaceFraction);
end
fprintf(rep,'Interpretation rule:\n');
fprintf(rep,'  If delta_eta_area tracks etaMeanShift while etaFarCorr and h_areaCorr are materially more stationary,\n');
fprintf(rep,'  a dominant spatially uniform geometric-volume offset is supported. If not, a scalar correction is inadequate.\n');
fclose(rep);

fprintf('\nAnalysis complete.\nComparison outputs: %s\n',cmpDir);
disp(allSummary);
end

function roots=findRecordingRoots(base)
roots={}; if ~isfolder(base), return; end
d=dir(fullfile(base,'**','timeline.csv'));
for i=1:numel(d), roots{end+1}=d(i).folder; end %#ok<AGROW>
end

function [root,man]=chooseLiquidRecordingRoot(roots)
% Prefer a root carrying rho and particleTypeFilter=1 when available.
best=-Inf; root=''; man=struct();
for i=1:numel(roots)
    m=readManifest(fullfile(roots{i},'manifest.kv'));
    fields=string(getfielddef(m,'recordFields',''));
    if ~contains(fields,'rho'), continue; end
    score=0;
    pf=strtrim(getfielddef(m,'particleTypeFilter',''));
    if strcmp(pf,'1'), score=score+10; end
    if ~contains(fields,'rho1') && ~contains(fields,'rho2'), score=score+2; end
    if score>best, best=score; root=roots{i}; man=m; end
end
assert(~isempty(root),'No recording root containing rho found');
end

function frames=collectRhoFrames(root)
tl=readtable(fullfile(root,'timeline.csv'),'VariableNamingRule','preserve');
man=readManifest(fullfile(root,'manifest.kv'));
Lx=str2double(getfielddef(man,'Lx','NaN')); Ly=str2double(getfielddef(man,'Ly','NaN'));
steps=unique(tl.step(strcmp(string(tl.field),'rho')));
frames=struct('step',{},'time',{},'nx',{},'ny',{},'Lx',{},'Ly',{},'rho',{});
for i=1:numel(steps)
    s=steps(i); rows=tl(tl.step==s & strcmp(string(tl.field),'rho'),:);
    if isempty(rows), continue; end
    F.step=s; F.time=rows.time(1); F.nx=rows.nx(1); F.ny=rows.ny(1);
    F.Lx=Lx; F.Ly=Ly;
    F.rho=fullfile(root,char(rows.file(1)));
    frames(end+1)=F; %#ok<AGROW>
end
[~,ord]=sort([frames.step]); frames=frames(ord);
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
fid=fopen(path,'rb'); assert(fid>=0,'Cannot open %s',path); c=onCleanup(@() fclose(fid)); %#ok<NASGU>
v=fread(fid,nx*ny,'single=>double'); assert(numel(v)==nx*ny,'Unexpected size in %s',path);
A=reshape(v,[nx,ny]).';
end

function out=smoothCross(A,lambda)
% Same 4-neighbour cross smoother as the historical Python analyser.
[ny,nx]=size(A); out=zeros(size(A));
for iy=1:ny
    for ix=1:nx
        c=A(iy,ix);
        w=c; e=c; s=c; n=c;
        if ix>1, w=A(iy,ix-1); end
        if ix<nx, e=A(iy,ix+1); end
        if iy>1, s=A(iy-1,ix); end
        if iy<ny, n=A(iy+1,ix); end
        v=c+lambda*((w-c)+(e-c)+(s-c)+(n-c));
        out(iy,ix)=min(1,max(0,v));
    end
end
end

function eta=surfaceFromAlpha(alpha,Lx,Ly)
[ny,nx]=size(alpha); dy=Ly/ny; %#ok<NASGU>
eta=nan(1,nx);
for ix=1:nx
    cross=NaN;
    for iy=1:ny-1
        a0=alpha(iy,ix); a1=alpha(iy+1,ix);
        if a0>=0.5 && a1<0.5
            y0=(iy-0.5)*(Ly/ny);
            y1=(iy+0.5)*(Ly/ny);
            if abs(a1-a0)>1e-14
                cross=y0+(0.5-a0)*(y1-y0)/(a1-a0);
            else
                cross=iy*(Ly/ny);
            end
        end
    end
    eta(ix)=cross;
end
end

function [etaFar,etaMin,etaMean,validFrac]=surfaceMetrics(eta,Lx,jetCenter,D)
nx=numel(eta); dx=Lx/nx; x=((1:nx)-0.5)*dx;
valid=isfinite(eta); validFrac=mean(valid);
etaMean=mean(eta(valid),'omitnan');
far=valid & x>0.08*Lx & x<0.92*Lx & abs(x-jetCenter)>=3*D;
etaFar=median(eta(far),'omitnan');
center=valid & abs(x-jetCenter)<=1.5*D;
if any(center), etaMin=min(eta(center),[],'omitnan'); else, etaMin=NaN; end
end

function d=relDrift(t,y)
mask=isfinite(t)&isfinite(y); t=t(mask); y=y(mask);
if numel(t)<3, d=NaN; return; end
p=polyfit(t,y,1); span=max(t)-min(t); mu=mean(abs(y),'omitnan');
if mu<=0, d=NaN; else, d=p(1)*span/mu; end
end

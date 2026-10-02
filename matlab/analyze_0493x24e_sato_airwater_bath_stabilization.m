function analyze_0493x24e_sato_airwater_bath_stabilization()
% ANALYZE_0493X24E_SATO_AIRWATER_BATH_STABILIZATION
% Offline stationarity diagnostic for the unforced Sato water/air-density bath.
% No simulation data are modified.  The goal is to decide whether a late dump
% can serve as the common RESTART state for later forced Sato runs.
%
% Authoritative observable philosophy:
%   - etaMean and etaFar are reconstructed from the recorded liquid rho field;
%   - integrated alpha-area is reported as a separate occupancy diagnostic and
%     is NEVER used as a correction to eta;
%   - stationarity is assessed on a user-visible late window.

close all;
root=fileparts(mfilename('fullpath'));
runsRoot=fullfile(root,'..','runs');
runDir=fullfile(runsRoot,'0493x24e_sato_airwater_bath_stabilization_seed493205');
assert(isfolder(runDir),'Missing run directory: %s',runDir);

% Geometry/physics fixed by the runner defaults.
Lx=1.5625; h=1/256; D=20*h; eta0=0.78125; rhoLiquid=20/(h*h);
stepWindow=[10000 15000];
plateauTolOverD=0.02; % diagnostic threshold on late-half shift, not a physics fit.

recRoots=findRecordingRoots(fullfile(runDir,'output','recordings'));
assert(~isempty(recRoots),'No recording timeline under %s',runDir);
[recRoot,man]=chooseLiquidRecordingRoot(recRoots);
fprintf('recording root: %s\n',recRoot);
fprintf('manifest: recordFields=%s particleTypeFilter=%s smoothPasses=%s\n', ...
    getfielddef(man,'recordFields','?'),getfielddef(man,'particleTypeFilter','?'),getfielddef(man,'smoothPasses','?'));
frames=collectRhoFrames(recRoot);
assert(~isempty(frames),'No rho frames in %s',recRoot);
fprintf('rho frames: %d (steps %d ... %d)\n',numel(frames),frames(1).step,frames(end).step);

rows=struct('step',{},'time',{},'etaMean',{},'etaFar',{},'etaMin',{},'etaMax',{}, ...
    'etaMeanShift',{},'etaFarShift',{},'surfaceRange',{},'areaAlpha',{}, ...
    'areaEquivalentShift',{},'validSurfaceFraction',{});
A0=NaN; etaMean0=NaN; etaFar0=NaN;
for k=1:numel(frames)
    F=frames(k);
    rho=readF32(F.rho,F.nx,F.ny);
    dx=F.Lx/F.nx; dy=F.Ly/F.ny; cellArea=dx*dy;
    refMass=rhoLiquid*cellArea;
    alpha=min(1,max(0,rho/refMass));
    alpha=smoothCross(alpha,0.125);
    eta=surfaceFromAlpha(alpha,F.Lx,F.Ly);
    [etaFar,etaMin,etaMean,validFrac,etaMax]=surfaceMetrics(eta,F.Lx,0.5*Lx,D);
    A=sum(alpha(:),'omitnan')*cellArea;
    if k==1
        A0=A; etaMean0=etaMean; etaFar0=etaFar;
    end
    R.step=F.step; R.time=F.time;
    R.etaMean=etaMean; R.etaFar=etaFar; R.etaMin=etaMin; R.etaMax=etaMax;
    R.etaMeanShift=etaMean-etaMean0; R.etaFarShift=etaFar-etaFar0;
    R.surfaceRange=etaMax-etaMin; R.areaAlpha=A;
    R.areaEquivalentShift=(A-A0)/F.Lx;
    R.validSurfaceFraction=validFrac;
    rows(end+1)=R; %#ok<AGROW>
end
T=struct2table(rows);
outDir=fullfile(runDir,'analysis'); if ~isfolder(outDir), mkdir(outDir); end
writetable(T,fullfile(outDir,'sato_bath_stabilization_history.csv'));

W=T(T.step>=stepWindow(1) & T.step<=stepWindow(2),:);
assert(height(W)>=5,'Too few samples in late stationarity window [%d,%d]',stepWindow(1),stepWindow(2));

[dMeanHalf,mean1,mean2]=halfDelta(W.etaMean,D);
[dFarHalf,far1,far2]=halfDelta(W.etaFar,D);
[dRangeHalf,range1,range2]=halfDelta(W.surfaceRange,D);
slopeMean=linearSlope(W.time,W.etaMean)/D;
slopeFar=linearSlope(W.time,W.etaFar)/D;
slopeRange=linearSlope(W.time,W.surfaceRange)/D;
status='PASS';
if abs(dMeanHalf)>plateauTolOverD || abs(dFarHalf)>plateauTolOverD
    status='REVIEW';
end

S=table(string(status),stepWindow(1),stepWindow(2),height(W), ...
    mean(W.etaMean)/D,std(W.etaMean)/D,mean(W.etaFar)/D,std(W.etaFar)/D, ...
    mean(W.surfaceRange)/D,std(W.surfaceRange)/D, ...
    dMeanHalf,dFarHalf,dRangeHalf,slopeMean,slopeFar,slopeRange, ...
    mean(W.areaEquivalentShift)/D,std(W.areaEquivalentShift)/D, ...
    mean(W.validSurfaceFraction), ...
    'VariableNames',{'status','windowStart','windowEnd','nSamples', ...
    'meanEtaMeanOverD','stdEtaMeanOverD','meanEtaFarOverD','stdEtaFarOverD', ...
    'meanSurfaceRangeOverD','stdSurfaceRangeOverD', ...
    'halfDeltaEtaMeanOverD','halfDeltaEtaFarOverD','halfDeltaSurfaceRangeOverD', ...
    'slopeEtaMeanOverDPerTime','slopeEtaFarOverDPerTime','slopeSurfaceRangeOverDPerTime', ...
    'meanAreaEquivalentShiftOverD','stdAreaEquivalentShiftOverD','meanValidSurfaceFraction'});
writetable(S,fullfile(outDir,'sato_bath_stabilization_summary.csv'));

fig=figure('Color','w'); hold on; box on; grid on;
plot(T.time,(T.etaMean-eta0)/D,'LineWidth',1.5,'DisplayName','mean surface');
plot(T.time,(T.etaFar-eta0)/D,'LineWidth',1.5,'DisplayName','far field');
xline(stepWindow(1)*0.0004,'--','window start');
xlabel('time'); ylabel('(\eta-\eta_0)/D'); title('Unforced bath level stabilization');
legend('Location','best');
saveas(fig,fullfile(outDir,'sato_bath_level_stabilization.png'));

fig=figure('Color','w'); hold on; box on; grid on;
plot(T.time,T.surfaceRange/D,'LineWidth',1.5,'DisplayName','max(\eta)-min(\eta)');
xline(stepWindow(1)*0.0004,'--','window start');
xlabel('time'); ylabel('surface range / D'); title('Residual free-surface nonuniformity');
legend('Location','best');
saveas(fig,fullfile(outDir,'sato_bath_surface_range.png'));

fig=figure('Color','w'); hold on; box on; grid on;
plot(T.time,T.areaEquivalentShift/D,'LineWidth',1.5,'DisplayName','integrated occupancy equivalent');
plot(T.time,T.etaMeanShift/D,'--','LineWidth',1.3,'DisplayName','mean geometric surface shift');
xline(stepWindow(1)*0.0004,'--','window start');
xlabel('time'); ylabel('shift / D'); title('Occupancy integral versus geometric surface level');
legend('Location','best');
saveas(fig,fullfile(outDir,'sato_bath_area_vs_geometric_level.png'));

rep=fopen(fullfile(outDir,'sato_bath_stabilization_report.txt'),'w');
fprintf(rep,'0493x24e Sato water/air-density bath stabilization (zero directed injection)\n');
fprintf(rep,'==========================================================================\n');
fprintf(rep,'No simulation data modified. Central top gas segment is a zero-mean hard-density reservoir, not a directed jet.\n');
fprintf(rep,'Geometry: Lx/D=20, liquidDepth/D=10, H/D=0.8 nozzle present, D=%.9g.\n',D);
fprintf(rep,'Window: steps %d:%d. Diagnostic plateau tolerance: |half shift|/D <= %.4g for etaMean and etaFar.\n\n',stepWindow(1),stepWindow(2),plateauTolOverD);
fprintf(rep,'status = %s\n',status);
fprintf(rep,'etaMean/D late mean = %.9g ; std/D = %.6g\n',S.meanEtaMeanOverD,S.stdEtaMeanOverD);
fprintf(rep,'etaFar/D  late mean = %.9g ; std/D = %.6g\n',S.meanEtaFarOverD,S.stdEtaFarOverD);
fprintf(rep,'surface range/D late mean = %.9g ; std/D = %.6g\n',S.meanSurfaceRangeOverD,S.stdSurfaceRangeOverD);
fprintf(rep,'halfDelta etaMean/D = %.9g (firstHalf=%.9g, secondHalf=%.9g)\n',dMeanHalf,mean1,mean2);
fprintf(rep,'halfDelta etaFar/D  = %.9g (firstHalf=%.9g, secondHalf=%.9g)\n',dFarHalf,far1,far2);
fprintf(rep,'halfDelta surfaceRange/D = %.9g (firstHalf=%.9g, secondHalf=%.9g)\n',dRangeHalf,range1,range2);
fprintf(rep,'linear slope etaMean/D/time = %.9g\n',slopeMean);
fprintf(rep,'linear slope etaFar/D/time  = %.9g\n',slopeFar);
fprintf(rep,'linear slope surfaceRange/D/time = %.9g\n',slopeRange);
fprintf(rep,'integrated-alpha equivalent shift/D = %.9g +/- %.6g (reported only; not used as a level correction)\n',S.meanAreaEquivalentShiftOverD,S.stdAreaEquivalentShiftOverD);
fprintf(rep,'valid surface fraction = %.9g\n\n',S.meanValidSurfaceFraction);
fprintf(rep,'Interpretation:\n');
fprintf(rep,'  PASS means the late geometric mean and far-field levels both satisfy the stated plateau criterion.\n');
fprintf(rep,'  REVIEW means extend the same unforced run by RESTART; do not tune physics from this result.\n');
fprintf(rep,'  A campaign restart dump should be selected from a late plateau only after this report is reviewed.\n');
fclose(rep);

fprintf('\n===== 0493x24e bath stabilization =====\n');
disp(S);
fprintf('report: %s\n',fullfile(outDir,'sato_bath_stabilization_report.txt'));
end

function [d,a,b]=halfDelta(x,D)
x=x(isfinite(x)); n=numel(x); m=floor(n/2); assert(m>=1);
a=mean(x(1:m),'omitnan')/D; b=mean(x(m+1:end),'omitnan')/D; d=b-a;
end
function s=linearSlope(t,x)
ok=isfinite(t)&isfinite(x); p=polyfit(t(ok),x(ok),1); s=p(1);
end
function roots=findRecordingRoots(base)
roots={}; if ~isfolder(base), return; end
d=dir(fullfile(base,'**','timeline.csv'));
for i=1:numel(d), roots{end+1}=d(i).folder; end %#ok<AGROW>
end
function [root,man]=chooseLiquidRecordingRoot(roots)
best=-Inf; root=''; man=struct();
for i=1:numel(roots)
    m=readManifest(fullfile(roots{i},'manifest.kv'));
    fields=string(getfielddef(m,'recordFields',''));
    if ~contains(fields,'rho'), continue; end
    score=0; pf=strtrim(getfielddef(m,'particleTypeFilter',''));
    if strcmp(pf,'1'), score=score+10; end
    if score>best, best=score; root=roots{i}; man=m; end
end
assert(~isempty(root),'No recording root containing rho found');
end
function frames=collectRhoFrames(root)
tl=readtable(fullfile(root,'timeline.csv'),'VariableNamingRule','preserve');
man=readManifest(fullfile(root,'manifest.kv'));
Lx=str2double(getfielddef(man,'Lx','NaN')); Ly=str2double(getfielddef(man,'Ly','NaN'));
steps=unique(tl.step(strcmp(string(tl.field),'rho'))); frames=struct([]);
for i=1:numel(steps)
    st=steps(i); q=tl(tl.step==st & strcmp(string(tl.field),'rho'),:); if isempty(q), continue; end
    fpath=fullfile(root,char(q.file(1))); if ~isfile(fpath), continue; end
    F.step=st; F.time=double(q.time(1)); F.nx=double(q.nx(1)); F.ny=double(q.ny(1));
    F.Lx=Lx; F.Ly=Ly; F.rho=fpath; frames(end+1)=F; %#ok<AGROW>
end
end
function A=readF32(path,nx,ny)
fid=fopen(path,'rb'); assert(fid>=0,'Cannot open %s',path); c=onCleanup(@()fclose(fid));
v=fread(fid,nx*ny,'single=>double'); assert(numel(v)==nx*ny,'Bad size %s',path); A=reshape(v,[nx ny])';
end
function B=smoothCross(A,lambda)
B=A; if lambda<=0, return; end
U=[A(1,:);A(1:end-1,:)]; Dn=[A(2:end,:);A(end,:)]; L=[A(:,1),A(:,1:end-1)]; R=[A(:,2:end),A(:,end)];
B=(1-4*lambda)*A+lambda*(U+Dn+L+R);
end
function eta=surfaceFromAlpha(alpha,Lx,Ly)
[ny,nx]=size(alpha); dy=Ly/ny; eta=nan(1,nx);
for ix=1:nx
    a=alpha(:,ix); j=find(a(1:end-1)>=0.5 & a(2:end)<0.5,1,'last');
    if isempty(j), j=find(a>=0.5,1,'last'); if isempty(j), continue; end; eta(ix)=(j-0.5)*dy; continue; end
    y1=(j-0.5)*dy; y2=(j+0.5)*dy; a1=a(j); a2=a(j+1);
    if abs(a2-a1)>1e-12, eta(ix)=y1+(0.5-a1)*(y2-y1)/(a2-a1); else, eta(ix)=0.5*(y1+y2); end
end
end
function [etaFar,etaMin,etaMean,validFrac,etaMax]=surfaceMetrics(eta,Lx,xc,D)
n=numel(eta); x=((1:n)-0.5)*(Lx/n); ok=isfinite(eta); validFrac=mean(ok);
etaMean=mean(eta(ok),'omitnan'); etaMin=min(eta(ok)); etaMax=max(eta(ok));
far=ok & abs(x-xc)>=2.0*D; if nnz(far)<10, far=ok & abs(x-xc)>=1.5*D; end
etaFar=mean(eta(far),'omitnan');
end
function m=readManifest(path)
m=struct(); if ~isfile(path), return; end
lines=splitlines(string(fileread(path)));
for i=1:numel(lines)
    z=strtrim(lines(i)); if strlength(z)==0 || startsWith(z,'#') || ~contains(z,'='), continue; end
    p=split(z,'=',2); key=matlab.lang.makeValidName(strtrim(p(1))); m.(key)=char(strtrim(p(2)));
end
end
function v=getfielddef(s,k,d)
kk=matlab.lang.makeValidName(k); if isfield(s,kk), v=s.(kk); else, v=d; end
end

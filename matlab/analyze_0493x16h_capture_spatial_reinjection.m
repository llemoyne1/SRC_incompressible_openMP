function result = analyze_0493x16h_capture_spatial_reinjection(runRoot)
% 0493x16h: local spatial reinjection of particles in newly swallowed cells.
% Historical binary mask + x16f temporal synchronization are retained. On a
% mask-shift step, particles encountered by the outward-bath pass in a newly
% solid cell are reflected across that cell's outward binary face, with their
% velocities left unchanged, and bypass the bath for that step.
%
% Run from repository matlab/:
%   analyze_0493x16h_capture_spatial_reinjection( ...
%       '../runs/0493x16h_capture_spatial_reinjection_galilean_case/fresh')

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x16h_capture_spatial_reinjection_galilean_case','fresh');
end
outDir = fullfile(runRoot,'output');
dynPath = fullfile(outDir,'chi_solid_dynamics_0493x16a.csv');
sumPath = fullfile(outDir,'summary_runtime.csv');
impPath = fullfile(outDir,'chi_solid_impulse_0493x15a.csv');
paramPath = fullfile(outDir,'params_used.kv');
assert(isfile(dynPath),'Missing %s',dynPath);
assert(isfile(sumPath),'Missing %s',sumPath);
assert(isfile(impPath),'Missing %s',impPath);
assert(isfile(paramPath),'Missing %s',paramPath);

D=readtable(dynPath,'VariableNamingRule','preserve');
S=readtable(sumPath,'VariableNamingRule','preserve');
I=readtable(impPath,'VariableNamingRule','preserve');
assert(~isempty(D)&&~isempty(S)&&~isempty(I),'Empty x16h input');

requiredD={'totalFluidImpulseX','brinkmanFluidImpulseX','bathFluidImpulseX','chiVpFluidImpulseX', ...
    'totalFluidImpulseY','fictitiousFluidMass0493x16c','centerXBefore','velocityXBefore','velocityXAfter', ...
    'solidMomentumBeforeX','solidMomentumAfterX','solidReactionImpulseX','actionReactionResidualX', ...
    'cellReactionSumX0493x16b','cellReactionSumY0493x16b','cellLoadClosureResidualX0493x16b', ...
    'cellLoadClosureResidualY0493x16b','primaryProjectionResidual0493x16b', ...
    'cudaResidentSolid0493x16e','subcellRaster0493x16e','historicalBinaryMask0493x16f', ...
    'poststreamTemporalSync0493x16f','hostGeometryFieldUploadBytes0493x16e','hostLoadFieldDownloadBytes0493x16e'};
for j=1:numel(requiredD), assert(ismember(requiredD{j},D.Properties.VariableNames),'Missing %s',requiredD{j}); end
requiredI={'captureSpatialReinjection0493x16h','captureCellParticles0493x16h', ...
    'captureReinjectedParticles0493x16h','captureReinjectedMass0493x16h','captureReinjectedMeanAbsDx0493x16h'};
for j=1:numel(requiredI), assert(ismember(requiredI{j},I.Properties.VariableNames),'Missing %s',requiredI{j}); end

[steps,id,is]=intersect(D.step,S.step,'stable'); keep=steps>0; steps=steps(keep); id=id(keep); is=is(keep);
[tf,ii]=ismember(steps,I.step); assert(all(tf),'Missing x16h impulse rows');
Lx=readKvNumber(paramPath,'Lx'); Nx=round(readKvNumber(paramPath,'Nx')); dx=Lx/Nx;
commonUx=readKvNumber(paramPath,'darcyUSolidX');
s0=find(S.step==0,1,'first'); assert(~isempty(s0),'Missing summary step 0');
initialCommonError=max(abs([S.meanVx(s0)-commonUx,D.velocityXBefore(id(1))-commonUx]));

center=D.centerXBefore(id); dc=diff(center); dc(dc>0.5*Lx)=dc(dc>0.5*Lx)-Lx; dc(dc<-0.5*Lx)=dc(dc<-0.5*Lx)+Lx;
centerUnwrapped=[center(1);center(1)+cumsum(dc)]; maskIndex=floor(centerUnwrapped/dx+0.5);
maskShift=[false;diff(maskIndex)~=0]; phase=mod(center/dx,1.0); steady=steps>=0.5*max(steps);
shift=steady&maskShift; away=steady&~maskShift;

fict=D.fictitiousFluidMass0493x16c(id); deltaFict=[NaN;diff(fict)];
total=D.totalFluidImpulseX(id); brink=D.brinkmanFluidImpulseX(id); bath=D.bathFluidImpulseX(id); vp=D.chiVpFluidImpulseX(id);
capCell=I.captureCellParticles0493x16h(ii); capN=I.captureReinjectedParticles0493x16h(ii);
capM=I.captureReinjectedMass0493x16h(ii); capDx=I.captureReinjectedMeanAbsDx0493x16h(ii);

nShift=sum(shift); meanDelta=meanFinite(deltaFict(shift)); meanCapN=meanFinite(capN(shift)); meanCapM=meanFinite(capM(shift)); meanDx=meanFinite(capDx(shift));
rmsShift=rmsFinite(total(shift)); rmsAway=rmsFinite(total(away)); amplification=rmsShift/max(rmsAway,1e-30);
rmsBrink=rmsFinite(brink(shift)); rmsBath=rmsFinite(bath(shift)); rmsVp=rmsFinite(vp(shift));
[maxH,harm]=phaseHarmonics(phase(steady),total(steady),4);
phaseCounts=histcounts(phase(steady),linspace(0,1,17)); coverage=min(phaseCounts)/max(mean(phaseCounts),1e-30);

% Event-centered cumulative impulse: tells whether x16h actually removes the
% delayed bath response instead of merely shifting it by one or two steps.
eventIdx=find(shift); maxLag=3; meanLag=nan(maxLag+1,1); meanCum=nan(maxLag+1,1);
for k=0:maxLag
    v=[]; c=[];
    for q=1:numel(eventIdx)
        j=eventIdx(q); if j+k<=numel(total), v(end+1,1)=total(j+k); c(end+1,1)=sum(total(j:j+k)); end %#ok<AGROW>
    end
    meanLag(k+1)=meanFinite(v); meanCum(k+1)=meanFinite(c);
end

fluidUx=S.meanVx(is); solidUx=D.velocityXAfter(id); rel=solidUx-fluidUx;
meanRel=mean(rel(steady)); rmsRel=rmsFinite(rel(steady)); meanKBT=mean(S.kBTEstimate(is(steady)));
Pfluid=S.Px(is); Psolid=D.solidMomentumAfterX(id); Ptotal=Pfluid+Psolid;
P0=S.Px(s0)+D.solidMomentumBeforeX(id(1)); scale=max([abs(P0);abs(Pfluid);abs(Psolid);1e-30]); maxP=max(abs(Ptotal-P0))/scale;
aScale=max([abs(D.totalFluidImpulseX(id));abs(D.solidReactionImpulseX(id));1e-30]); maxAR=max(abs(D.actionReactionResidualX(id)))/aScale;
cx=max([abs(D.cellReactionSumX0493x16b(id));abs(D.totalFluidImpulseX(id));1e-30]); cy=max([abs(D.cellReactionSumY0493x16b(id));abs(D.totalFluidImpulseY(id));1e-30]);
maxCX=max(abs(D.cellLoadClosureResidualX0493x16b(id)))/cx; maxCY=max(abs(D.cellLoadClosureResidualY0493x16b(id)))/cy;
ps=max([abs(D.cellReactionSumX0493x16b(id));abs(D.solidReactionImpulseX(id));1e-30]); maxProj=max(abs(D.primaryProjectionResidual0493x16b(id)))/ps;
resident=all(D.cudaResidentSolid0493x16e(id)==1)&all(D.subcellRaster0493x16e(id)==0)&all(D.historicalBinaryMask0493x16f(id)==1)&all(D.poststreamTemporalSync0493x16f(id)==1)&max(D.hostGeometryFieldUploadBytes0493x16e(id))==0&max(D.hostLoadFieldDownloadBytes0493x16e(id))==0;
gate=all(I.captureSpatialReinjection0493x16h(ii)==1); mechanics=max([maxP,maxAR,maxCX,maxCY,maxProj])<1e-9; initial=initialCommonError<1e-12*max(abs(commonUx),1.0);
phasePass=coverage>0.5 && maxH<0.10; pass=resident&&gate&&mechanics&&initial&&phasePass;
status="PASS"; if ~pass, status="REVIEW"; end

adir=fullfile(runRoot,'analysis_x16h'); if ~isfolder(adir), mkdir(adir); end
T=table(steps,S.time(is),phase,maskShift,deltaFict,total,brink,bath,vp,capCell,capN,capM,capDx,solidUx,fluidUx,rel, ...
    'VariableNames',{'step','time','phase','maskShift','deltaFictitiousMass','totalFluidImpulseX','brinkmanFluidImpulseX','bathFluidImpulseX','chiVpFluidImpulseX','captureCellParticles','reinjectedParticles','reinjectedMass','reinjectedMeanAbsDx','solidUx','fluidMeanUx','solidMinusFluidUx'});
writetable(T,fullfile(adir,'capture_spatial_steps_0493x16h.csv'));
H=table((1:4)',harm(:),'VariableNames',{'harmonic','forceAmplitudeOverRms'}); writetable(H,fullfile(adir,'phase_harmonics_0493x16h.csv'));
E=table((0:maxLag)',meanLag,meanCum,'VariableNames',{'lagSteps','meanImpulse','meanCumulativeImpulse'}); writetable(E,fullfile(adir,'event_lag_0493x16h.csv'));

fid=fopen(fullfile(adir,'summary_0493x16h.txt'),'w'); assert(fid>=0); cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'0493x16h local spatial reinjection / common translation\n'); fprintf(fid,'status=%s\n',status); fprintf(fid,'steps=%d\n',numel(steps)); fprintf(fid,'commonUx=%.17g\n',commonUx); fprintf(fid,'initialCommonError=%.17g\n',initialCommonError);
fprintf(fid,'maskShiftEventsSteady=%d\n',nShift); fprintf(fid,'meanDeltaFictMassAtMaskShift=%.17g\n',meanDelta); fprintf(fid,'meanReinjectedParticlesAtMaskShift=%.17g\n',meanCapN); fprintf(fid,'meanReinjectedMassAtMaskShift=%.17g\n',meanCapM); fprintf(fid,'meanReinjectedAbsDxAtMaskShift=%.17g\n',meanDx);
fprintf(fid,'rmsTotalImpulseAtMaskShift=%.17g\n',rmsShift); fprintf(fid,'rmsTotalImpulseAway=%.17g\n',rmsAway); fprintf(fid,'eventAmplification=%.17g\n',amplification); fprintf(fid,'rmsBrinkmanAtMaskShift=%.17g\n',rmsBrink); fprintf(fid,'rmsOutwardBathAtMaskShift=%.17g\n',rmsBath); fprintf(fid,'rmsChiVpAtMaskShift=%.17g\n',rmsVp);
for k=0:maxLag, fprintf(fid,'meanEventImpulseLag%d=%.17g\n',k,meanLag(k+1)); fprintf(fid,'meanEventCumulativeImpulseThroughLag%d=%.17g\n',k,meanCum(k+1)); end
fprintf(fid,'phaseCoverageRatio=%.17g\n',coverage); fprintf(fid,'maxForcePhaseHarmonicOverRms=%.17g\n',maxH); fprintf(fid,'meanSolidMinusFluidUx=%.17g\n',meanRel); fprintf(fid,'rmsSolidMinusFluidUx=%.17g\n',rmsRel); fprintf(fid,'meanKBT=%.17g\n',meanKBT);
fprintf(fid,'maxRelativeTotalMomentumDriftX=%.17g\n',maxP); fprintf(fid,'maxRelativeActionReactionX=%.17g\n',maxAR); fprintf(fid,'maxRelativeCellLoadClosureX=%.17g\n',maxCX); fprintf(fid,'maxRelativeCellLoadClosureY=%.17g\n',maxCY); fprintf(fid,'maxRelativePrimaryProjection=%.17g\n',maxProj);
fprintf(fid,'residentHistoricalBinaryPass=%d\n',resident); fprintf(fid,'spatialReinjectionGatePass=%d\n',gate); fprintf(fid,'mechanicsPass=%d\n',mechanics); fprintf(fid,'initialCommonTranslationPass=%d\n',initial); fprintf(fid,'phaseForcePass=%d\n',phasePass);

fprintf('\n===== 0493x16h SPATIAL REINJECTION =====\n'); fprintf('status=%s  shifts=%d\n',status,nShift); fprintf('reinjected particles/mass at shift = %.3f / %.3f\n',meanCapN,meanCapM); fprintf('impulse RMS shift/away = %.6g / %.6g (x%.3f)\n',rmsShift,rmsAway,amplification); fprintf('Brinkman/bath/chiVP at shift = %.6g / %.6g / %.6g\n',rmsBrink,rmsBath,rmsVp); fprintf('event cumulative lag0/1/2/3 = %.6g %.6g %.6g %.6g\n',meanCum); fprintf('phase harmonic/RMS = %.6g\n',maxH); fprintf('analysis=%s\n',adir); fprintf('=========================================\n');
result=struct('status',status,'runRoot',runRoot,'maskShiftEvents',nShift,'eventAmplification',amplification,'maxForcePhaseHarmonicOverRms',maxH,'analysisDir',adir);
end

function x=rmsFinite(v), v=v(isfinite(v)); if isempty(v),x=NaN;else,x=sqrt(mean(v.^2));end,end
function x=meanFinite(v), v=v(isfinite(v)); if isempty(v),x=NaN;else,x=mean(v);end,end
function [relMax,rel]=phaseHarmonics(phase,signal,nHarm), phase=phase(:); signal=signal(:); q=signal-mean(signal); rmsq=sqrt(mean(q.^2)); rel=zeros(nHarm,1); if rmsq<=0,relMax=0;return;end; for h=1:nHarm,amp=2*abs(mean(q.*exp(-1i*2*pi*h*phase)));rel(h)=amp/rmsq;end;relMax=max(rel); end
function value=readKvNumber(path,key), text=fileread(path); expr=['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)']; tok=regexp(text,expr,'tokens','once'); assert(~isempty(tok),'Missing key %s',key); value=str2double(strtrim(tok{1})); assert(isfinite(value),'Non-numeric key %s',key); end

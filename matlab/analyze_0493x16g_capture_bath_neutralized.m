function result = analyze_0493x16g_capture_bath_neutralized(runRoot)
% 0493x16g diagnostic ablation on one common-translation run.
% The rigid slab and fluid start with the same prescribed mean Ux. x16g keeps
% the x16f historical binary mask and temporal synchronization. The historical
% outward bath is applied unchanged, then only the collective bath increment of
% particles in newly swallowed cells is removed.
%
% Run from repository matlab/:
%   analyze_0493x16g_capture_bath_neutralized( ...
%       '../runs/0493x16g_capture_bath_neutralized_galilean_case/fresh')

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x16g_capture_bath_neutralized_galilean_case','fresh');
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

D = readtable(dynPath,'VariableNamingRule','preserve');
S = readtable(sumPath,'VariableNamingRule','preserve');
I = readtable(impPath,'VariableNamingRule','preserve');
assert(~isempty(D) && ~isempty(S) && ~isempty(I),'Empty x16g input');

requiredD = {'totalFluidImpulseX','brinkmanFluidImpulseX','bathFluidImpulseX', ...
    'chiVpFluidImpulseX','totalFluidImpulseY','fictitiousFluidMass0493x16c','centerXBefore', ...
    'velocityXBefore','velocityXAfter','solidMomentumBeforeX','solidMomentumAfterX','solidReactionImpulseX', ...
    'actionReactionResidualX','cellReactionSumX0493x16b','cellReactionSumY0493x16b', ...
    'cellLoadClosureResidualX0493x16b','cellLoadClosureResidualY0493x16b', ...
    'primaryProjectionResidual0493x16b', ...
    'cudaResidentSolid0493x16e','subcellRaster0493x16e', ...
    'historicalBinaryMask0493x16f','poststreamTemporalSync0493x16f', ...
    'hostGeometryFieldUploadBytes0493x16e','hostLoadFieldDownloadBytes0493x16e'};
for j=1:numel(requiredD)
    assert(ismember(requiredD{j},D.Properties.VariableNames),'Missing %s in %s',requiredD{j},dynPath);
end
requiredI = {'captureBathMeanNeutralization0493x16g','captureBathMass0493x16g', ...
    'captureBathRawFluidImpulseX0493x16g','captureBathCorrectionFluidImpulseX0493x16g', ...
    'captureBathResidualFluidImpulseX0493x16g'};
for j=1:numel(requiredI)
    assert(ismember(requiredI{j},I.Properties.VariableNames),'Missing %s in %s',requiredI{j},impPath);
end

[steps,id,is] = intersect(D.step,S.step,'stable');
keep = steps>0; steps=steps(keep); id=id(keep); is=is(keep);
assert(~isempty(steps),'No common nonzero steps');
[tf,ii] = ismember(steps,I.step);
assert(all(tf),'Missing x16g impulse rows');

Lx = readKvNumber(paramPath,'Lx');
Nx = round(readKvNumber(paramPath,'Nx'));
dx = Lx/Nx;
dt = readKvNumber(paramPath,'dt');
solidMass = readKvNumber(paramPath,'chiSolidMass');
commonUx = readKvNumber(paramPath,'darcyUSolidX');

s0 = find(S.step==0,1,'first');
assert(~isempty(s0),'Missing summary step 0');
initialFluidUx = S.meanVx(s0);
initialSolidUx = D.velocityXBefore(id(1));
initialCommonError = max(abs([initialFluidUx-commonUx,initialSolidUx-commonUx]));

center = D.centerXBefore(id);
dc = diff(center);
dc(dc >  0.5*Lx) = dc(dc >  0.5*Lx)-Lx;
dc(dc < -0.5*Lx) = dc(dc < -0.5*Lx)+Lx;
centerUnwrapped = [center(1); center(1)+cumsum(dc)];
maskIndex = floor(centerUnwrapped/dx + 0.5);
maskShift = [false; diff(maskIndex)~=0];
steady = steps >= 0.5*max(steps);
shiftSteady = steady & maskShift;
awaySteady = steady & ~maskShift;
phase = mod(center/dx,1.0);

fictMass = D.fictitiousFluidMass0493x16c(id);
deltaFict = [NaN; diff(fictMass)];
totalIx = D.totalFluidImpulseX(id);
brinkmanIx = D.brinkmanFluidImpulseX(id);
bathIx = D.bathFluidImpulseX(id);
chiVpIx = D.chiVpFluidImpulseX(id);
capMass = I.captureBathMass0493x16g(ii);
capRawIx = I.captureBathRawFluidImpulseX0493x16g(ii);
capCorrIx = I.captureBathCorrectionFluidImpulseX0493x16g(ii);
capResidualIx = I.captureBathResidualFluidImpulseX0493x16g(ii);

maskShiftEvents = sum(shiftSteady);
meanDeltaFictAtShift = meanFinite(deltaFict(shiftSteady));
meanCaptureBathMassAtShift = meanFinite(capMass(shiftSteady));
rmsTotalAtShift = rmsFinite(totalIx(shiftSteady));
rmsTotalAway = rmsFinite(totalIx(awaySteady));
eventAmplification = rmsTotalAtShift/max(rmsTotalAway,1e-30);
rmsBrinkmanAtShift = rmsFinite(brinkmanIx(shiftSteady));
rmsBathAtShift = rmsFinite(bathIx(shiftSteady));
rmsChiVpAtShift = rmsFinite(chiVpIx(shiftSteady));
rmsRawCaptureBathAtShift = rmsFinite(capRawIx(shiftSteady));
rmsCorrectionCaptureBathAtShift = rmsFinite(capCorrIx(shiftSteady));
rmsResidualCaptureBathAtShift = rmsFinite(capResidualIx(shiftSteady));
rawScale = max(rmsFinite(capRawIx(steady)),1e-30);
maxCaptureBathResidualOverRaw = max(abs(capResidualIx(steady)))/rawScale;

[maxForceHarmonicRel,forceHarmonics] = phaseHarmonics(phase(steady),totalIx(steady),4);
phaseCounts = histcounts(phase(steady),linspace(0,1,17));
phaseCoverageRatio = min(phaseCounts)/max(mean(phaseCounts),1e-30);

fluidUx = S.meanVx(is);
solidUx = D.velocityXAfter(id);
relativeUx = solidUx-fluidUx;
meanRelativeUx = mean(relativeUx(steady));
rmsRelativeUx = rmsFinite(relativeUx(steady));
meanKBT = mean(S.kBTEstimate(is(steady)));

% Global mechanical invariants.
Pfluid = S.Px(is);
Psolid = D.solidMomentumAfterX(id);
Ptotal = Pfluid+Psolid;
Ptotal0 = S.Px(s0) + D.solidMomentumBeforeX(id(1));
scaleTotal = max([abs(Ptotal0);abs(Pfluid);abs(Psolid);1e-30]);
maxRelTotalDrift = max(abs(Ptotal-Ptotal0))/scaleTotal;
actionScale = max([abs(D.totalFluidImpulseX(id));abs(D.solidReactionImpulseX(id));1e-30]);
maxRelActionReaction = max(abs(D.actionReactionResidualX(id)))/actionScale;
cellScaleX = max([abs(D.cellReactionSumX0493x16b(id));abs(D.totalFluidImpulseX(id));1e-30]);
cellScaleY = max([abs(D.cellReactionSumY0493x16b(id));abs(D.totalFluidImpulseY(id));1e-30]);
maxRelCellClosureX = max(abs(D.cellLoadClosureResidualX0493x16b(id)))/cellScaleX;
maxRelCellClosureY = max(abs(D.cellLoadClosureResidualY0493x16b(id)))/cellScaleY;
projScale = max([abs(D.cellReactionSumX0493x16b(id));abs(D.solidReactionImpulseX(id));1e-30]);
maxRelProjection = max(abs(D.primaryProjectionResidual0493x16b(id)))/projScale;

residentPass = all(D.cudaResidentSolid0493x16e(id)==1) && ...
    all(D.subcellRaster0493x16e(id)==0) && ...
    all(D.historicalBinaryMask0493x16f(id)==1) && ...
    all(D.poststreamTemporalSync0493x16f(id)==1) && ...
    max(D.hostGeometryFieldUploadBytes0493x16e(id))==0 && ...
    max(D.hostLoadFieldDownloadBytes0493x16e(id))==0;
neutralizationGatePass = all(I.captureBathMeanNeutralization0493x16g(ii)==1);
neutralizationClosurePass = maxCaptureBathResidualOverRaw < 1e-10;
mechanicsPass = max([maxRelTotalDrift,maxRelActionReaction,maxRelCellClosureX,maxRelCellClosureY,maxRelProjection]) < 1e-9;
initialPass = initialCommonError < 1e-12*max(abs(commonUx),1.0);
phaseForcePass = phaseCoverageRatio>0.5 && maxForceHarmonicRel<0.10;

% For this first ablation, PASS means the new operation itself is exact and the
% original Galilean force-lock criterion is met. REVIEW remains informative if
% Brinkman/chiVP leave a residual grid-locked event after the bath mean is gone.
pass = residentPass && neutralizationGatePass && neutralizationClosurePass && ...
    mechanicsPass && initialPass && phaseForcePass;
status = "PASS"; if ~pass, status = "REVIEW"; end

analysisDir = fullfile(runRoot,'analysis_x16g');
if ~isfolder(analysisDir), mkdir(analysisDir); end
T = table(steps,S.time(is),phase,maskShift,deltaFict,totalIx,brinkmanIx,bathIx,chiVpIx, ...
    capMass,capRawIx,capCorrIx,capResidualIx,solidUx,fluidUx,relativeUx, ...
    'VariableNames',{'step','time','phase','maskShift','deltaFictitiousMass', ...
    'totalFluidImpulseX','brinkmanFluidImpulseX','bathFluidImpulseX','chiVpFluidImpulseX', ...
    'captureBathMass','captureBathRawImpulseX','captureBathCorrectionImpulseX', ...
    'captureBathResidualImpulseX','solidUx','fluidMeanUx','solidMinusFluidUx'});
writetable(T,fullfile(analysisDir,'capture_bath_steps_0493x16g.csv'));
H=table((1:4)',forceHarmonics(:),'VariableNames',{'harmonic','forceAmplitudeOverRms'});
writetable(H,fullfile(analysisDir,'phase_harmonics_0493x16g.csv'));

fid=fopen(fullfile(analysisDir,'summary_0493x16g.txt'),'w');
assert(fid>=0,'Cannot create x16g summary');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'0493x16g captured-particle outward-bath mean-neutralization / common translation\n');
fprintf(fid,'status=%s\n',status);
fprintf(fid,'steps=%d\n',numel(steps));
fprintf(fid,'commonUx=%.17g\n',commonUx);
fprintf(fid,'initialCommonError=%.17g\n',initialCommonError);
fprintf(fid,'maskShiftEventsSteady=%d\n',maskShiftEvents);
fprintf(fid,'meanDeltaFictMassAtMaskShift=%.17g\n',meanDeltaFictAtShift);
fprintf(fid,'meanCaptureBathMassAtMaskShift=%.17g\n',meanCaptureBathMassAtShift);
fprintf(fid,'rmsTotalImpulseAtMaskShift=%.17g\n',rmsTotalAtShift);
fprintf(fid,'rmsTotalImpulseAway=%.17g\n',rmsTotalAway);
fprintf(fid,'eventAmplification=%.17g\n',eventAmplification);
fprintf(fid,'rmsBrinkmanAtMaskShift=%.17g\n',rmsBrinkmanAtShift);
fprintf(fid,'rmsOutwardBathAtMaskShift=%.17g\n',rmsBathAtShift);
fprintf(fid,'rmsChiVpAtMaskShift=%.17g\n',rmsChiVpAtShift);
fprintf(fid,'rmsRawCaptureBathImpulseAtMaskShift=%.17g\n',rmsRawCaptureBathAtShift);
fprintf(fid,'rmsCorrectionCaptureBathImpulseAtMaskShift=%.17g\n',rmsCorrectionCaptureBathAtShift);
fprintf(fid,'rmsResidualCaptureBathImpulseAtMaskShift=%.17g\n',rmsResidualCaptureBathAtShift);
fprintf(fid,'maxCaptureBathResidualOverRaw=%.17g\n',maxCaptureBathResidualOverRaw);
fprintf(fid,'phaseCoverageRatio=%.17g\n',phaseCoverageRatio);
fprintf(fid,'maxForcePhaseHarmonicOverRms=%.17g\n',maxForceHarmonicRel);
fprintf(fid,'meanSolidMinusFluidUx=%.17g\n',meanRelativeUx);
fprintf(fid,'rmsSolidMinusFluidUx=%.17g\n',rmsRelativeUx);
fprintf(fid,'meanKBT=%.17g\n',meanKBT);
fprintf(fid,'maxRelativeTotalMomentumDriftX=%.17g\n',maxRelTotalDrift);
fprintf(fid,'maxRelativeActionReactionX=%.17g\n',maxRelActionReaction);
fprintf(fid,'maxRelativeCellLoadClosureX=%.17g\n',maxRelCellClosureX);
fprintf(fid,'maxRelativeCellLoadClosureY=%.17g\n',maxRelCellClosureY);
fprintf(fid,'maxRelativePrimaryProjection=%.17g\n',maxRelProjection);
fprintf(fid,'residentHistoricalBinaryPass=%d\n',residentPass);
fprintf(fid,'neutralizationGatePass=%d\n',neutralizationGatePass);
fprintf(fid,'neutralizationClosurePass=%d\n',neutralizationClosurePass);
fprintf(fid,'mechanicsPass=%d\n',mechanicsPass);
fprintf(fid,'initialCommonTranslationPass=%d\n',initialPass);
fprintf(fid,'phaseForcePass=%d\n',phaseForcePass);

fprintf('\n===== 0493x16g COMMON-TRANSLATION ABLATION =====\n');
fprintf('status                                  = %s\n',status);
fprintf('common Ux                               = %.9g\n',commonUx);
fprintf('mask-shift events (steady)              = %d\n',maskShiftEvents);
fprintf('capture bath raw/correction/residual RMS= %.6g / %.6g / %.3e\n', ...
    rmsRawCaptureBathAtShift,rmsCorrectionCaptureBathAtShift,rmsResidualCaptureBathAtShift);
fprintf('total impulse RMS shift / away          = %.6g / %.6g (x%.3f)\n', ...
    rmsTotalAtShift,rmsTotalAway,eventAmplification);
fprintf('Brinkman / bath / chiVP RMS at shift    = %.6g / %.6g / %.6g\n', ...
    rmsBrinkmanAtShift,rmsBathAtShift,rmsChiVpAtShift);
fprintf('max force phase harmonic / RMS          = %.3e\n',maxForceHarmonicRel);
fprintf('max neutralization residual / raw       = %.3e\n',maxCaptureBathResidualOverRaw);
fprintf('analysis                                 = %s\n',analysisDir);
fprintf('=================================================\n');

figure;
plot(phase(steady),totalIx(steady),'.');
xlabel('sub-cell slab phase'); ylabel('fluid impulse x / step');
title('0493x16g total reaction versus grid phase'); grid on;

figure;
plot(S.time(is),capRawIx,'-',S.time(is),capCorrIx,'-',S.time(is),capResidualIx,'-');
xlabel('time'); ylabel('captured-population bath impulse x');
legend('raw bath','mean-removal correction','residual','Location','best');
title('0493x16g captured-population bath neutralization'); grid on;

result=struct('status',status,'runRoot',runRoot,'commonUx',commonUx, ...
    'maskShiftEvents',maskShiftEvents,'eventAmplification',eventAmplification, ...
    'rmsRawCaptureBathImpulseAtMaskShift',rmsRawCaptureBathAtShift, ...
    'rmsResidualCaptureBathImpulseAtMaskShift',rmsResidualCaptureBathAtShift, ...
    'maxForcePhaseHarmonicOverRms',maxForceHarmonicRel, ...
    'analysisDir',analysisDir);
end

function x=rmsFinite(v)
v=v(isfinite(v)); if isempty(v), x=NaN; else, x=sqrt(mean(v.^2)); end
end

function x=meanFinite(v)
v=v(isfinite(v)); if isempty(v), x=NaN; else, x=mean(v); end
end

function [relMax,rel]=phaseHarmonics(phase,signal,nHarm)
phase=phase(:); signal=signal(:); q=signal-mean(signal); rmsq=sqrt(mean(q.^2));
rel=zeros(nHarm,1); if rmsq<=0, relMax=0; return; end
for h=1:nHarm
    amp=2*abs(mean(q.*exp(-1i*2*pi*h*phase))); rel(h)=amp/rmsq;
end
relMax=max(rel);
end

function value=readKvNumber(path,key)
text=fileread(path);
expr=['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)'];
tok=regexp(text,expr,'tokens','once');
assert(~isempty(tok),'Missing key %s in %s',key,path);
value=str2double(strtrim(tok{1}));
assert(isfinite(value),'Non-numeric key %s in %s',key,path);
end

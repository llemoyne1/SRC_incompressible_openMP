function result = analyze_0493x16d_galilean_invariance(pairRoot)
% 0493x16d paired Galilean-invariance test for dynamic chi solids.
%
% The pair contains two statistically equivalent initial microstates:
%   rest  : <u_f,x>(0) = U_s(0) = 0
%   boost : <u_f,x>(0) = U_s(0) = U_G
% with the same thermal RNG seed. Random grid shifting makes trajectory-by-
% trajectory equality neither required nor expected; the qualification tests
% conservation, common-motion neutrality, sampled-geometry invariance and
% absence of a force locked to the sub-cell phase of the moving slab.
%
% Run from repository matlab/:
%   analyze_0493x16d_galilean_invariance('../runs/0493x16d_galilean_pair')

if nargin < 1 || isempty(pairRoot)
    pairRoot = fullfile('..','runs','0493x16d_galilean_pair');
end
restRoot = fullfile(pairRoot,'rest','fresh');
boostRoot = fullfile(pairRoot,'boost','fresh');
metaPath = fullfile(pairRoot,'pair_meta_0493x16d.txt');
assert(isfile(metaPath), 'Missing %s', metaPath);
UG = readKvNumber(metaPath, 'boostCommonUx');
assert(isfinite(UG) && abs(UG) > 0, 'x16d requires a non-zero boostCommonUx');

R = loadCase(restRoot);
B = loadCase(boostRoot);
assert(abs(R.solidMass-B.solidMass) <= 1e-14*max(abs(R.solidMass),1), ...
    'Rest/boost solid masses differ');
assert(R.Nx==B.Nx && R.Ny==B.Ny && abs(R.Lx-B.Lx)<1e-14 && abs(R.Ly-B.Ly)<1e-14, ...
    'Rest/boost geometries differ');
assert(numel(R.steps)==numel(B.steps) && all(R.steps==B.steps), ...
    'Rest/boost step sets differ');

% Initial-state boost check. The case generator removes finite-sample thermal
% drift, so these should be close to machine precision.
restInitCommonError = max(abs([R.initialFluidMeanVx, R.initialSolidVx]));
boostInitCommonError = max(abs([B.initialFluidMeanVx-UG, B.initialSolidVx-UG]));
boostShiftMeasured = (B.initialTotalMomentumX - R.initialTotalMomentumX) / ...
    (B.initialFluidMass + B.solidMass);
boostShiftError = abs(boostShiftMeasured - UG);

% Frame-invariant relative/bulk statistics over the second half of each run.
meanRelativeRest = mean(R.relativeBulkUx(R.steady));
meanRelativeBoost = mean(B.relativeBulkUx(B.steady));
rmsRelativeRest = sqrt(mean(R.relativeBulkUx(R.steady).^2));
rmsRelativeBoost = sqrt(mean(B.relativeBulkUx(B.steady).^2));
relativeMeanDifference = abs(meanRelativeBoost - meanRelativeRest);
relativeRmsScale = max(0.5*(rmsRelativeRest+rmsRelativeBoost),1e-30);
relativeMeanDifferenceOverRms = relativeMeanDifference / relativeRmsScale;
relativeRmsDifferenceFraction = abs(rmsRelativeBoost-rmsRelativeRest) / relativeRmsScale;

meanTempRest = mean(R.kBTEstimate(R.steady));
meanTempBoost = mean(B.kBTEstimate(B.steady));
temperatureRelativeDifference = abs(meanTempBoost-meanTempRest) / ...
    max(0.5*(abs(meanTempBoost)+abs(meanTempRest)),1e-30);

meanFictMassRest = mean(R.fictMass(R.steady));
meanFictMassBoost = mean(B.fictMass(B.steady));
fictMassRelativeDifference = abs(meanFictMassBoost-meanFictMassRest) / ...
    max(0.5*(abs(meanFictMassBoost)+abs(meanFictMassRest)),1e-30);

impulseRmsRest = sqrt(mean((R.totalFluidImpulseX(R.steady) - ...
    mean(R.totalFluidImpulseX(R.steady))).^2));
impulseRmsBoost = sqrt(mean((B.totalFluidImpulseX(B.steady) - ...
    mean(B.totalFluidImpulseX(B.steady))).^2));
impulseRmsDifferenceFraction = abs(impulseRmsBoost-impulseRmsRest) / ...
    max(0.5*(impulseRmsBoost+impulseRmsRest),1e-30);

% The boosted case sweeps the slab through the Eulerian grid. Measure any
% deterministic force/mass modulation locked to the sub-cell phase.
[maxForceHarmonicRel, forceHarmonics] = phaseHarmonics( ...
    B.phase(B.steady), B.totalFluidImpulseX(B.steady), 4);
[maxMassHarmonicRel, massHarmonics] = phaseHarmonics( ...
    B.phase(B.steady), B.fictMass(B.steady), 4);

edges = linspace(0,1,17);
phaseCounts = histcounts(B.phase(B.steady),edges);
phaseCoverageRatio = min(phaseCounts) / max(mean(phaseCounts),1e-30);

% Exact sampled geometry used by RigidSlab1DGeometry, reconstructed at the
% pre-coupling center for every step. This detects cell-phase volume pulsation.
maxSampledVolumeRelErrorRest = max(abs(R.sampledSolidVolume-R.expectedSolidVolume)) / ...
    max(abs(R.expectedSolidVolume),1e-30);
maxSampledVolumeRelErrorBoost = max(abs(B.sampledSolidVolume-B.expectedSolidVolume)) / ...
    max(abs(B.expectedSolidVolume),1e-30);
maxSampledVolumeRelError = max(maxSampledVolumeRelErrorRest,maxSampledVolumeRelErrorBoost);

% Mechanical regressions from x16a-c must remain qualified in both frames.
mechanicsPass = max([R.maxRelTotalDrift,B.maxRelTotalDrift]) < 1e-9 && ...
    max([R.maxRelFluidClosure,B.maxRelFluidClosure]) < 1e-9 && ...
    max([R.maxRelActionReaction,B.maxRelActionReaction]) < 1e-9 && ...
    max([R.maxRelCellClosureX,B.maxRelCellClosureX,R.maxRelCellClosureY,B.maxRelCellClosureY]) < 1e-9 && ...
    max([R.maxRelProjection,B.maxRelProjection]) < 1e-9;

% x16d Galilean criteria. These are deliberately dimensionless/statistical:
% - exact initial boost construction;
% - no sampled solid-volume pulsation;
% - adequate traversal of all sub-cell phases;
% - no first four grid harmonics above 10% of the stochastic impulse RMS;
% - rest/boost mean relative motion agrees within 25% of its natural RMS;
% - thermostat temperature is frame independent to 2%.
initialScale = max([abs(UG),1]);
initialPass = restInitCommonError < 1e-12*initialScale && ...
              boostInitCommonError < 1e-12*initialScale && ...
              boostShiftError < 1e-12*initialScale;
geometryPass = maxSampledVolumeRelError < 1e-12;
phasePass = phaseCoverageRatio > 0.5 && maxForceHarmonicRel < 0.10;
relativePass = relativeMeanDifferenceOverRms < 0.25;
temperaturePass = temperatureRelativeDifference < 0.02;

pass = mechanicsPass && initialPass && geometryPass && phasePass && ...
       relativePass && temperaturePass;
status = "PASS";
if ~pass, status = "REVIEW"; end

analysisDir = fullfile(pairRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end

% Pair time series for inspection.
T = table(R.steps, R.time, R.phase, B.phase, ...
    R.solidVx, B.solidVx, R.fluidMeanVx, B.fluidMeanVx, ...
    R.relativeBulkUx, B.relativeBulkUx, ...
    R.totalFluidImpulseX, B.totalFluidImpulseX, ...
    R.fictMass, B.fictMass, R.sampledSolidVolume, B.sampledSolidVolume, ...
    'VariableNames', {'step','time','restPhase','boostPhase', ...
    'restSolidVx','boostSolidVx','restFluidMeanVx','boostFluidMeanVx', ...
    'restSolidMinusFluidVx','boostSolidMinusFluidVx', ...
    'restFluidImpulseX','boostFluidImpulseX','restFictitiousMass','boostFictitiousMass', ...
    'restSampledSolidVolume','boostSampledSolidVolume'});
writetable(T, fullfile(analysisDir,'galilean_steps_0493x16d.csv'));

H = table((1:4)',forceHarmonics(:),massHarmonics(:), ...
    'VariableNames',{'harmonic','forceAmplitudeOverRms','fictitiousMassAmplitudeOverRms'});
writetable(H, fullfile(analysisDir,'galilean_phase_harmonics_0493x16d.csv'));

fid = fopen(fullfile(analysisDir,'summary_0493x16d.txt'),'w');
assert(fid >= 0, 'Cannot create x16d summary');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'0493x16d Galilean common-translation qualification / rigid slab 1D\n');
fprintf(fid,'status=%s\n',status);
fprintf(fid,'stepsPerCase=%d\n',numel(R.steps));
fprintf(fid,'galileanBoostUx=%.17g\n',UG);
fprintf(fid,'restInitCommonError=%.17g\n',restInitCommonError);
fprintf(fid,'boostInitCommonError=%.17g\n',boostInitCommonError);
fprintf(fid,'boostShiftMeasuredFromTotalMomentum=%.17g\n',boostShiftMeasured);
fprintf(fid,'boostShiftError=%.17g\n',boostShiftError);
fprintf(fid,'restMaxRelativeTotalMomentumDriftX=%.17g\n',R.maxRelTotalDrift);
fprintf(fid,'boostMaxRelativeTotalMomentumDriftX=%.17g\n',B.maxRelTotalDrift);
fprintf(fid,'restMaxRelativeActionReactionX=%.17g\n',R.maxRelActionReaction);
fprintf(fid,'boostMaxRelativeActionReactionX=%.17g\n',B.maxRelActionReaction);
fprintf(fid,'meanRelativeBulkUxRest=%.17g\n',meanRelativeRest);
fprintf(fid,'meanRelativeBulkUxBoost=%.17g\n',meanRelativeBoost);
fprintf(fid,'rmsRelativeBulkUxRest=%.17g\n',rmsRelativeRest);
fprintf(fid,'rmsRelativeBulkUxBoost=%.17g\n',rmsRelativeBoost);
fprintf(fid,'relativeMeanDifference=%.17g\n',relativeMeanDifference);
fprintf(fid,'relativeMeanDifferenceOverRms=%.17g\n',relativeMeanDifferenceOverRms);
fprintf(fid,'relativeRmsDifferenceFraction=%.17g\n',relativeRmsDifferenceFraction);
fprintf(fid,'meanKBTrest=%.17g\n',meanTempRest);
fprintf(fid,'meanKBTboost=%.17g\n',meanTempBoost);
fprintf(fid,'temperatureRelativeDifference=%.17g\n',temperatureRelativeDifference);
fprintf(fid,'meanFictitiousMassRest=%.17g\n',meanFictMassRest);
fprintf(fid,'meanFictitiousMassBoost=%.17g\n',meanFictMassBoost);
fprintf(fid,'fictitiousMassRelativeDifference=%.17g\n',fictMassRelativeDifference);
fprintf(fid,'impulseRmsRest=%.17g\n',impulseRmsRest);
fprintf(fid,'impulseRmsBoost=%.17g\n',impulseRmsBoost);
fprintf(fid,'impulseRmsDifferenceFraction=%.17g\n',impulseRmsDifferenceFraction);
fprintf(fid,'phaseCoverageRatioBoost=%.17g\n',phaseCoverageRatio);
fprintf(fid,'maxForcePhaseHarmonicOverRms=%.17g\n',maxForceHarmonicRel);
fprintf(fid,'maxFictitiousMassPhaseHarmonicOverRms=%.17g\n',maxMassHarmonicRel);
fprintf(fid,'maxSampledSolidVolumeRelativeErrorRest=%.17g\n',maxSampledVolumeRelErrorRest);
fprintf(fid,'maxSampledSolidVolumeRelativeErrorBoost=%.17g\n',maxSampledVolumeRelErrorBoost);
fprintf(fid,'mechanicsPass=%d\n',mechanicsPass);
fprintf(fid,'initialBoostPass=%d\n',initialPass);
fprintf(fid,'sampledGeometryPass=%d\n',geometryPass);
fprintf(fid,'phaseForcePass=%d\n',phasePass);
fprintf(fid,'relativeMotionPass=%d\n',relativePass);
fprintf(fid,'temperaturePass=%d\n',temperaturePass);

fprintf('\n===== 0493x16d GALILEAN COMMON-TRANSLATION =====\n');
fprintf('status                              = %s\n',status);
fprintf('boost U_G                           = %.9g\n',UG);
fprintf('boost reconstructed from total P    = %.9g (err %.3e)\n',boostShiftMeasured,boostShiftError);
fprintf('mean Us-Uf rest / boost             = %.3e / %.3e\n',meanRelativeRest,meanRelativeBoost);
fprintf('RMS Us-Uf rest / boost              = %.3e / %.3e\n',rmsRelativeRest,rmsRelativeBoost);
fprintf('relative-mean difference / RMS       = %.3e\n',relativeMeanDifferenceOverRms);
fprintf('temperature relative difference     = %.3e\n',temperatureRelativeDifference);
fprintf('max sampled-volume relative error    = %.3e\n',maxSampledVolumeRelError);
fprintf('boost phase coverage min/mean        = %.3f\n',phaseCoverageRatio);
fprintf('max force grid harmonic / RMS        = %.3e\n',maxForceHarmonicRel);
fprintf('max fict-mass grid harmonic / RMS    = %.3e (diagnostic only)\n',maxMassHarmonicRel);
fprintf('analysis                             = %s\n',analysisDir);
fprintf('===================================================\n');

figure;
plot(R.time,R.relativeBulkUx,'-',B.time,B.relativeBulkUx,'-');
xlabel('time'); ylabel('U_s-<U_f>');
legend('rest','boost','Location','best');
title('0493x16d frame-invariant relative bulk motion'); grid on;

figure;
plot(B.phase(B.steady),B.totalFluidImpulseX(B.steady),'.');
xlabel('sub-cell slab phase'); ylabel('fluid impulse x / step');
title('0493x16d boosted reaction versus grid phase'); grid on;

figure;
plot(B.time,B.sampledSolidVolume,'-');
xlabel('time'); ylabel('sampled solid volume');
title('0493x16d sampled chi-solid volume, boosted frame'); grid on;

result = struct('status',status,'boostUx',UG, ...
    'boostShiftError',boostShiftError, ...
    'relativeMeanDifferenceOverRms',relativeMeanDifferenceOverRms, ...
    'temperatureRelativeDifference',temperatureRelativeDifference, ...
    'maxForcePhaseHarmonicOverRms',maxForceHarmonicRel, ...
    'maxSampledSolidVolumeRelativeError',maxSampledVolumeRelError, ...
    'analysisDir',analysisDir);
end

function C = loadCase(runRoot)
outDir = fullfile(runRoot,'output');
dynPath = fullfile(outDir,'chi_solid_dynamics_0493x16a.csv');
sumPath = fullfile(outDir,'summary_runtime.csv');
paramPath = fullfile(outDir,'params_used.kv');
assert(isfile(dynPath),'Missing %s',dynPath);
assert(isfile(sumPath),'Missing %s',sumPath);
assert(isfile(paramPath),'Missing %s',paramPath);
D = readtable(dynPath,'VariableNamingRule','preserve');
S = readtable(sumPath,'VariableNamingRule','preserve');
assert(~isempty(D) && ~isempty(S),'Empty x16d case %s',runRoot);

required = {'spatialLoadAvailable0493x16b','fictitiousFluidDiagnostic0493x16c', ...
    'fictitiousFluidMass0493x16c','cellLoadClosureResidualX0493x16b', ...
    'cellLoadClosureResidualY0493x16b','primaryProjectionResidual0493x16b'};
for j=1:numel(required)
    assert(ismember(required{j},D.Properties.VariableNames),'Missing column %s in %s',required{j},dynPath);
end

[steps,id,is] = intersect(D.step,S.step,'stable');
keep = steps>0; steps=steps(keep); id=id(keep); is=is(keep);
assert(~isempty(steps),'No common nonzero steps in %s',runRoot);

C.runRoot=runRoot; C.D=D; C.S=S; C.steps=steps; C.id=id; C.is=is;
C.time=S.time(is);
C.solidMass=readKvNumber(paramPath,'chiSolidMass');
C.Lx=readKvNumber(paramPath,'Lx'); C.Ly=readKvNumber(paramPath,'Ly');
C.Nx=round(readKvNumber(paramPath,'Nx')); C.Ny=round(readKvNumber(paramPath,'Ny'));
C.dt=readKvNumber(paramPath,'dt');
C.xmin=readKvNumber(paramPath,'darcyBoxXMin'); C.xmax=readKvNumber(paramPath,'darcyBoxXMax');
C.interfaceWidth=readKvNumber(paramPath,'darcyInterfaceWidth');
C.dx=C.Lx/C.Nx; C.dy=C.Ly/C.Ny;
C.expectedSolidVolume=(C.xmax-C.xmin)*C.Ly;

s0=find(S.step==0,1,'first'); assert(~isempty(s0),'Missing summary step 0');
C.initialFluidMeanVx=S.meanVx(s0);
C.initialFluidMass=S.totalMass(s0);
C.initialSolidVx=D.velocityXBefore(id(1));
C.initialTotalMomentumX=S.Px(s0)+D.solidMomentumBeforeX(id(1));

C.solidVx=D.velocityXAfter(id);
C.fluidMeanVx=S.meanVx(is);
C.kBTEstimate=S.kBTEstimate(is);
C.relativeBulkUx=C.solidVx-C.fluidMeanVx;
C.totalFluidImpulseX=D.totalFluidImpulseX(id);
C.totalFluidImpulseY=D.totalFluidImpulseY(id);
C.fictMass=D.fictitiousFluidMass0493x16c(id);
C.phase=mod(D.centerXBefore(id)/C.dx,1.0);
C.steady=steps >= (0.5*max(steps));

% Sample the same cell-centered chi definition as RigidSlab1DGeometry.
C.sampledSolidVolume=zeros(size(steps));
xc=((0:C.Nx-1)+0.5)*C.dx;
half=0.5*(C.xmax-C.xmin);
for k=1:numel(steps)
    c=D.centerXBefore(id(k));
    delta=xc-c;
    delta=delta-round(delta/C.Lx)*C.Lx;
    sd=abs(delta)-half;
    if C.interfaceWidth>0
        chi=ones(size(sd));
        chi(sd<=0)=0;
        m=sd>0;
        t=min(1,max(0,sd(m)/C.interfaceWidth));
        chi(m)=t.^2.*(3-2*t);
    else
        chi=double(sd>0);
    end
    solidFrac=sum(1-chi)*C.Ny;
    C.sampledSolidVolume(k)=solidFrac*C.dx*C.dy;
end

% Mechanical closure using global scales, as in x16c.
Psolid0=D.solidMomentumBeforeX(id(1));
Ptotal0=S.Px(s0)+Psolid0;
Pfluid=S.Px(is); Psolid=D.solidMomentumAfterX(id);
Ptotal=Pfluid+Psolid;
scaleTotal=max([abs(Ptotal0);abs(Pfluid);abs(Psolid);1e-30]);
C.maxRelTotalDrift=max(abs(Ptotal-Ptotal0))/scaleTotal;

prevIndex=zeros(size(is)); valid=false(size(is));
for k=1:numel(is)
    j=find(S.step==steps(k)-1,1,'first');
    if ~isempty(j), prevIndex(k)=j; valid(k)=true; end
end
idC=id(valid); isC=is(valid); prevC=prevIndex(valid);
dPxFluid=S.Px(isC)-S.Px(prevC);
fluidImpulse=D.totalFluidImpulseX(idC);
fluidScale=max([abs(dPxFluid);abs(fluidImpulse);1e-30]);
C.maxRelFluidClosure=max(abs(dPxFluid-fluidImpulse))/fluidScale;

actionScale=max([abs(D.totalFluidImpulseX(id));abs(D.solidReactionImpulseX(id));1e-30]);
C.maxRelActionReaction=max(abs(D.actionReactionResidualX(id)))/actionScale;
cellScaleX=max([abs(D.cellReactionSumX0493x16b(id));abs(D.totalFluidImpulseX(id));1e-30]);
cellScaleY=max([abs(D.cellReactionSumY0493x16b(id));abs(D.totalFluidImpulseY(id));1e-30]);
C.maxRelCellClosureX=max(abs(D.cellLoadClosureResidualX0493x16b(id)))/cellScaleX;
C.maxRelCellClosureY=max(abs(D.cellLoadClosureResidualY0493x16b(id)))/cellScaleY;
projScale=max([abs(D.cellReactionSumX0493x16b(id));abs(D.solidReactionImpulseX(id));1e-30]);
C.maxRelProjection=max(abs(D.primaryProjectionResidual0493x16b(id)))/projScale;
end

function [relMax, rel] = phaseHarmonics(phase, signal, nHarm)
phase=phase(:); signal=signal(:);
q=signal-mean(signal);
rmsq=sqrt(mean(q.^2));
rel=zeros(nHarm,1);
if rmsq<=0
    relMax=0; return;
end
for h=1:nHarm
    amp=2*abs(mean(q.*exp(-1i*2*pi*h*phase)));
    rel(h)=amp/rmsq;
end
relMax=max(rel);
end

function value = readKvNumber(path,key)
text=fileread(path);
expr=['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)'];
tok=regexp(text,expr,'tokens','once');
assert(~isempty(tok),'Missing key %s in %s',key,path);
value=str2double(strtrim(tok{1}));
assert(isfinite(value),'Non-numeric key %s in %s',key,path);
end

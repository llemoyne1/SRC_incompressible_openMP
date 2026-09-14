function result = analyze_0493x16i_deformable_impermeable_compare(pairRoot)
% 0493x16i comparison: impermeable prescribed deformable wall.
%
% Priority policy encoded by this experiment:
%   1) qualify a single geometric representation suitable for strictly
%      impermeable fixed/mobile/deformable solids;
%   2) leave the historical porous-Darcy chi -> alpha path unchanged;
%   3) treat mobile porous optimization as a later, non-blocking question.
%
% Two CUDA-resident strict-exclusion representations are compared:
%   binary_event   : historical binary chi, position remap only when a cell
%                    center flips fluid -> solid;
%   swept_geometry : historical binary Darcy interior, but continuous exact
%                    prescribed-interface exclusion/remap in swept/cut cells.
%
% Each representation is run in a rest and a Galilean-boosted frame with the
% same deformation law and RNG seed. This analyzer is intentionally a
% comparison, not a final qualification of either wall law.
%
% Run from repository matlab/:
%   analyze_0493x16i_deformable_impermeable_compare( ...
%       '../runs/0493x16i_deformable_impermeable_compare')

if nargin < 1 || isempty(pairRoot)
    pairRoot = fullfile('..','runs','0493x16i_deformable_impermeable_compare');
end
metaPath = fullfile(pairRoot,'compare_meta_0493x16i.txt');
assert(isfile(metaPath),'Missing %s',metaPath);
UG = readKvNumber(metaPath,'boostCommonUx');
periodSteps = round(readKvNumber(metaPath,'deformPeriodSteps'));
ampCells = readKvNumber(metaPath,'deformAmplitudeCells');
assert(isfinite(UG) && abs(UG)>0,'x16i comparison requires non-zero boostCommonUx');
assert(periodSteps>4,'x16i requires deformPeriodSteps>4');

BR = loadCase(fullfile(pairRoot,'binary_event','rest','fresh'),1,periodSteps);
BB = loadCase(fullfile(pairRoot,'binary_event','boost','fresh'),1,periodSteps);
SR = loadCase(fullfile(pairRoot,'swept_geometry','rest','fresh'),2,periodSteps);
SB = loadCase(fullfile(pairRoot,'swept_geometry','boost','fresh'),2,periodSteps);
C = {BR,BB,SR,SB};
for k=2:numel(C)
    assert(C{k}.Nx==C{1}.Nx && C{k}.Ny==C{1}.Ny && ...
        abs(C{k}.Lx-C{1}.Lx)<1e-14 && abs(C{k}.Ly-C{1}.Ly)<1e-14 && ...
        abs(C{k}.dt-C{1}.dt)<1e-14,'x16i case geometries/dt differ');
    assert(numel(C{k}.steps)==numel(C{1}.steps) && all(C{k}.steps==C{1}.steps), ...
        'x16i case step sets differ');
end

% Initial Galilean construction, separately for each exclusion representation.
[binaryRestInit,binaryBoostInit,binaryShiftMeasured,binaryShiftError] = initialBoostMetrics(BR,BB,UG);
[sweptRestInit,sweptBoostInit,sweptShiftMeasured,sweptShiftError] = initialBoostMetrics(SR,SB,UG);

% Compare the force response as a function of prescribed deformation phase.
% This removes the physical periodic deformation signal and isolates the
% difference introduced by adding a uniform Galilean translation.
nPhaseBins = 32;
PB = phasePair(BR,BB,nPhaseBins);
PS = phasePair(SR,SB,nPhaseBins);

% Frame invariance of bulk relative motion and temperature.
[binaryRelMeanDiffOverRms,binaryRelRmsDiffFrac,binaryTempRelDiff,binaryFictRelDiff] = pairBulkMetrics(BR,BB);
[sweptRelMeanDiffOverRms,sweptRelRmsDiffFrac,sweptTempRelDiff,sweptFictRelDiff] = pairBulkMetrics(SR,SB);

% Continuous geometric occupancy is diagnostic only in x16i: theta is NEVER
% sent through the historical Borrvall-Petersson alpha(chi) interpolation.
% For the constant-thickness prescribed wall, positive and negative occupancy
% change should balance globally over a step/cycle apart from roundoff/quadrature.
occBR = occupancyMetrics(BR); occBB = occupancyMetrics(BB);
occSR = occupancyMetrics(SR); occSB = occupancyMetrics(SB);

% Cost comparison: d.totalSeconds is the measured CUDA Darcy/bath application
% time for each diagnostic step. Compare like-for-like within each frame and
% also a pooled rest+boost value.
binaryMeanDarcySeconds = mean([BR.meanDarcySeconds,BB.meanDarcySeconds]);
sweptMeanDarcySeconds = mean([SR.meanDarcySeconds,SB.meanDarcySeconds]);
sweptOverBinaryDarcyCost = sweptMeanDarcySeconds / max(binaryMeanDarcySeconds,1e-30);
sweptOverBinaryDarcyCostRest = SR.meanDarcySeconds / max(BR.meanDarcySeconds,1e-30);
sweptOverBinaryDarcyCostBoost = SB.meanDarcySeconds / max(BB.meanDarcySeconds,1e-30);

% Hard checks concern only implementation integrity, historical-Darcy
% preservation, residency, geometry volume and mechanical accounting. We do
% NOT impose an arbitrary Galilean threshold here: x16i is a design comparison.
allTechnical = BR.technicalPass && BB.technicalPass && SR.technicalPass && SB.technicalPass;
initialScale=max(abs(UG),1.0);
initialPass = max([binaryRestInit,binaryBoostInit,binaryShiftError, ...
                   sweptRestInit,sweptBoostInit,sweptShiftError]) < 1e-12*initialScale;
geometryPass = max([BR.maxSampledVolumeRelError,BB.maxSampledVolumeRelError, ...
                    SR.maxSampledVolumeRelError,SB.maxSampledVolumeRelError]) < 1e-10;
mechanicsPass = max([BR.maxRelTotalDrift,BB.maxRelTotalDrift,SR.maxRelTotalDrift,SB.maxRelTotalDrift, ...
                     BR.maxRelActionReaction,BB.maxRelActionReaction,SR.maxRelActionReaction,SB.maxRelActionReaction, ...
                     BR.maxRelCellClosureX,BB.maxRelCellClosureX,SR.maxRelCellClosureX,SB.maxRelCellClosureX, ...
                     BR.maxRelCellClosureY,BB.maxRelCellClosureY,SR.maxRelCellClosureY,SB.maxRelCellClosureY, ...
                     BR.maxRelProjection,BB.maxRelProjection,SR.maxRelProjection,SB.maxRelProjection]) < 1e-9;
status = "COMPARE_OK";
if ~(allTechnical && initialPass && geometryPass && mechanicsPass)
    status = "REVIEW";
end

if PS.forceCurveRmsDifferenceOverRms < PB.forceCurveRmsDifferenceOverRms
    lowerGalileanErrorMode = "swept_geometry";
else
    lowerGalileanErrorMode = "binary_event";
end
if sweptMeanDarcySeconds < binaryMeanDarcySeconds
    lowerDarcyCostMode = "swept_geometry";
else
    lowerDarcyCostMode = "binary_event";
end

analysisDir = fullfile(pairRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end

% One-row-per-case table.
mode = ["binary_event";"binary_event";"swept_geometry";"swept_geometry"];
frame = ["rest";"boost";"rest";"boost"];
meanForceX = [BR.meanForceX;BB.meanForceX;SR.meanForceX;SB.meanForceX];
rmsForceX = [BR.rmsForceX;BB.rmsForceX;SR.rmsForceX;SB.rmsForceX];
meanFictMass = [BR.meanFictMass;BB.meanFictMass;SR.meanFictMass;SB.meanFictMass];
meanReinjectedParticles = [BR.meanReinjectedParticles;BB.meanReinjectedParticles;SR.meanReinjectedParticles;SB.meanReinjectedParticles];
meanReinjectedMass = [BR.meanReinjectedMass;BB.meanReinjectedMass;SR.meanReinjectedMass;SB.meanReinjectedMass];
meanReinjectedAbsDx = [BR.meanReinjectedAbsDx;BB.meanReinjectedAbsDx;SR.meanReinjectedAbsDx;SB.meanReinjectedAbsDx];
meanPositiveDeltaThetaCells = [occBR.meanPositive;occBB.meanPositive;occSR.meanPositive;occSB.meanPositive];
meanNegativeDeltaThetaCells = [occBR.meanNegative;occBB.meanNegative;occSR.meanNegative;occSB.meanNegative];
occupancyChangeImbalance = [occBR.imbalance;occBB.imbalance;occSR.imbalance;occSB.imbalance];
meanDarcySeconds = [BR.meanDarcySeconds;BB.meanDarcySeconds;SR.meanDarcySeconds;SB.meanDarcySeconds];
medianDarcySeconds = [BR.medianDarcySeconds;BB.medianDarcySeconds;SR.medianDarcySeconds;SB.medianDarcySeconds];
maxVolumeRelError = [BR.maxSampledVolumeRelError;BB.maxSampledVolumeRelError;SR.maxSampledVolumeRelError;SB.maxSampledVolumeRelError];
maxActionReactionRel = [BR.maxRelActionReaction;BB.maxRelActionReaction;SR.maxRelActionReaction;SB.maxRelActionReaction];
technicalPass = [BR.technicalPass;BB.technicalPass;SR.technicalPass;SB.technicalPass];
CaseSummary = table(mode,frame,meanForceX,rmsForceX,meanFictMass, ...
    meanReinjectedParticles,meanReinjectedMass,meanReinjectedAbsDx, ...
    meanPositiveDeltaThetaCells,meanNegativeDeltaThetaCells,occupancyChangeImbalance, ...
    meanDarcySeconds,medianDarcySeconds,maxVolumeRelError,maxActionReactionRel,technicalPass);
writetable(CaseSummary,fullfile(analysisDir,'case_summary_0493x16i.csv'));

% Deformation-phase force/remap comparison for both representations.
ModeCol = [repmat("binary_event",nPhaseBins,1);repmat("swept_geometry",nPhaseBins,1)];
PhaseCenter = [PB.phaseCenter;PS.phaseCenter];
RestCount = [PB.restCount;PS.restCount]; BoostCount = [PB.boostCount;PS.boostCount];
RestMeanForceX = [PB.restMeanForce;PS.restMeanForce]; BoostMeanForceX = [PB.boostMeanForce;PS.boostMeanForce];
BoostMinusRestForceX = [PB.forceDifference;PS.forceDifference];
RestMeanReinjected = [PB.restMeanReinjected;PS.restMeanReinjected];
BoostMeanReinjected = [PB.boostMeanReinjected;PS.boostMeanReinjected];
RestMeanFictMass = [PB.restMeanFictMass;PS.restMeanFictMass];
BoostMeanFictMass = [PB.boostMeanFictMass;PS.boostMeanFictMass];
RestMeanPositiveDeltaTheta = [PB.restMeanPositiveDeltaTheta;PS.restMeanPositiveDeltaTheta];
BoostMeanPositiveDeltaTheta = [PB.boostMeanPositiveDeltaTheta;PS.boostMeanPositiveDeltaTheta];
PhaseTable=table(ModeCol,PhaseCenter,RestCount,BoostCount,RestMeanForceX,BoostMeanForceX, ...
    BoostMinusRestForceX,RestMeanReinjected,BoostMeanReinjected,RestMeanFictMass,BoostMeanFictMass, ...
    RestMeanPositiveDeltaTheta,BoostMeanPositiveDeltaTheta);
writetable(PhaseTable,fullfile(analysisDir,'deformation_phase_compare_0493x16i.csv'));

% Compact scalar architecture comparison.
Metric = ["forcePhaseCurveRmsDifferenceOverRms";"meanForceDifferenceOverRms"; ...
          "relativeMeanDifferenceOverRms";"relativeRmsDifferenceFraction"; ...
          "temperatureRelativeDifference";"fictitiousMassRelativeDifference"; ...
          "meanDarcySeconds";"meanReinjectedParticlesPerStep"];
BinaryEvent = [PB.forceCurveRmsDifferenceOverRms;PB.meanForceDifferenceOverRms; ...
               binaryRelMeanDiffOverRms;binaryRelRmsDiffFrac;binaryTempRelDiff;binaryFictRelDiff; ...
               binaryMeanDarcySeconds;mean([BR.meanReinjectedParticles,BB.meanReinjectedParticles])];
SweptGeometry = [PS.forceCurveRmsDifferenceOverRms;PS.meanForceDifferenceOverRms; ...
                 sweptRelMeanDiffOverRms;sweptRelRmsDiffFrac;sweptTempRelDiff;sweptFictRelDiff; ...
                 sweptMeanDarcySeconds;mean([SR.meanReinjectedParticles,SB.meanReinjectedParticles])];
Comparison = table(Metric,BinaryEvent,SweptGeometry);
writetable(Comparison,fullfile(analysisDir,'architecture_compare_0493x16i.csv'));

summaryPath=fullfile(analysisDir,'summary_0493x16i.txt');
fid=fopen(summaryPath,'w'); assert(fid>=0,'Cannot write %s',summaryPath); cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'0493x16i prescribed deformable impermeable-solid representation comparison\n');
fprintf(fid,'status=%s\n',status);
fprintf(fid,'priority=strict_impermeable_fixed_mobile_deformable\n');
fprintf(fid,'porousDarcyPolicy=historical_path_unchanged\n');
fprintf(fid,'comparisonOnly=1\n');
fprintf(fid,'boostCommonUx=%.17g\n',UG);
fprintf(fid,'deformAmplitudeCells=%.17g\n',ampCells);
fprintf(fid,'deformPeriodSteps=%d\n',periodSteps);
fprintf(fid,'stepsPerCase=%d\n',numel(BR.steps));
fprintf(fid,'\n');
fprintf(fid,'binaryRestInitCommonError=%.17g\n',binaryRestInit);
fprintf(fid,'binaryBoostInitCommonError=%.17g\n',binaryBoostInit);
fprintf(fid,'binaryBoostShiftMeasured=%.17g\n',binaryShiftMeasured);
fprintf(fid,'binaryBoostShiftError=%.17g\n',binaryShiftError);
fprintf(fid,'sweptRestInitCommonError=%.17g\n',sweptRestInit);
fprintf(fid,'sweptBoostInitCommonError=%.17g\n',sweptBoostInit);
fprintf(fid,'sweptBoostShiftMeasured=%.17g\n',sweptShiftMeasured);
fprintf(fid,'sweptBoostShiftError=%.17g\n',sweptShiftError);
fprintf(fid,'\n');
fprintf(fid,'binaryForcePhaseCurveRmsDifference=%.17g\n',PB.forceCurveRmsDifference);
fprintf(fid,'binaryForcePhaseCurveRmsDifferenceOverRms=%.17g\n',PB.forceCurveRmsDifferenceOverRms);
fprintf(fid,'binaryMeanForceDifferenceOverRms=%.17g\n',PB.meanForceDifferenceOverRms);
fprintf(fid,'binaryPhaseCoverageRest=%.17g\n',PB.restCoverage);
fprintf(fid,'binaryPhaseCoverageBoost=%.17g\n',PB.boostCoverage);
fprintf(fid,'sweptForcePhaseCurveRmsDifference=%.17g\n',PS.forceCurveRmsDifference);
fprintf(fid,'sweptForcePhaseCurveRmsDifferenceOverRms=%.17g\n',PS.forceCurveRmsDifferenceOverRms);
fprintf(fid,'sweptMeanForceDifferenceOverRms=%.17g\n',PS.meanForceDifferenceOverRms);
fprintf(fid,'sweptPhaseCoverageRest=%.17g\n',PS.restCoverage);
fprintf(fid,'sweptPhaseCoverageBoost=%.17g\n',PS.boostCoverage);
fprintf(fid,'lowerGalileanErrorMode=%s\n',lowerGalileanErrorMode);
fprintf(fid,'\n');
fprintf(fid,'binaryRelativeMeanDifferenceOverRms=%.17g\n',binaryRelMeanDiffOverRms);
fprintf(fid,'binaryRelativeRmsDifferenceFraction=%.17g\n',binaryRelRmsDiffFrac);
fprintf(fid,'binaryTemperatureRelativeDifference=%.17g\n',binaryTempRelDiff);
fprintf(fid,'binaryFictitiousMassRelativeDifference=%.17g\n',binaryFictRelDiff);
fprintf(fid,'sweptRelativeMeanDifferenceOverRms=%.17g\n',sweptRelMeanDiffOverRms);
fprintf(fid,'sweptRelativeRmsDifferenceFraction=%.17g\n',sweptRelRmsDiffFrac);
fprintf(fid,'sweptTemperatureRelativeDifference=%.17g\n',sweptTempRelDiff);
fprintf(fid,'sweptFictitiousMassRelativeDifference=%.17g\n',sweptFictRelDiff);
fprintf(fid,'\n');
fprintf(fid,'binaryMeanDarcySeconds=%.17g\n',binaryMeanDarcySeconds);
fprintf(fid,'sweptMeanDarcySeconds=%.17g\n',sweptMeanDarcySeconds);
fprintf(fid,'sweptOverBinaryDarcyCost=%.17g\n',sweptOverBinaryDarcyCost);
fprintf(fid,'sweptOverBinaryDarcyCostRest=%.17g\n',sweptOverBinaryDarcyCostRest);
fprintf(fid,'sweptOverBinaryDarcyCostBoost=%.17g\n',sweptOverBinaryDarcyCostBoost);
fprintf(fid,'lowerDarcyCostMode=%s\n',lowerDarcyCostMode);
fprintf(fid,'\n');
fprintf(fid,'binaryRestMeanReinjectedParticlesPerStep=%.17g\n',BR.meanReinjectedParticles);
fprintf(fid,'binaryBoostMeanReinjectedParticlesPerStep=%.17g\n',BB.meanReinjectedParticles);
fprintf(fid,'sweptRestMeanReinjectedParticlesPerStep=%.17g\n',SR.meanReinjectedParticles);
fprintf(fid,'sweptBoostMeanReinjectedParticlesPerStep=%.17g\n',SB.meanReinjectedParticles);
fprintf(fid,'binaryRestMeanFictitiousMass=%.17g\n',BR.meanFictMass);
fprintf(fid,'binaryBoostMeanFictitiousMass=%.17g\n',BB.meanFictMass);
fprintf(fid,'sweptRestMeanFictitiousMass=%.17g\n',SR.meanFictMass);
fprintf(fid,'sweptBoostMeanFictitiousMass=%.17g\n',SB.meanFictMass);
fprintf(fid,'\n');
fprintf(fid,'binaryRestOccupancyChangeImbalance=%.17g\n',occBR.imbalance);
fprintf(fid,'binaryBoostOccupancyChangeImbalance=%.17g\n',occBB.imbalance);
fprintf(fid,'sweptRestOccupancyChangeImbalance=%.17g\n',occSR.imbalance);
fprintf(fid,'sweptBoostOccupancyChangeImbalance=%.17g\n',occSB.imbalance);
fprintf(fid,'maxSampledSolidVolumeRelativeError=%.17g\n',max([BR.maxSampledVolumeRelError,BB.maxSampledVolumeRelError,SR.maxSampledVolumeRelError,SB.maxSampledVolumeRelError]));
fprintf(fid,'maxRelativeTotalMomentumDriftX=%.17g\n',max([BR.maxRelTotalDrift,BB.maxRelTotalDrift,SR.maxRelTotalDrift,SB.maxRelTotalDrift]));
fprintf(fid,'maxRelativeActionReactionX=%.17g\n',max([BR.maxRelActionReaction,BB.maxRelActionReaction,SR.maxRelActionReaction,SB.maxRelActionReaction]));
fprintf(fid,'maxRelativeCellLoadClosureX=%.17g\n',max([BR.maxRelCellClosureX,BB.maxRelCellClosureX,SR.maxRelCellClosureX,SB.maxRelCellClosureX]));
fprintf(fid,'maxRelativeCellLoadClosureY=%.17g\n',max([BR.maxRelCellClosureY,BB.maxRelCellClosureY,SR.maxRelCellClosureY,SB.maxRelCellClosureY]));
fprintf(fid,'maxRelativePrimaryProjection=%.17g\n',max([BR.maxRelProjection,BB.maxRelProjection,SR.maxRelProjection,SB.maxRelProjection]));
fprintf(fid,'allTechnicalPass=%d\n',allTechnical);
fprintf(fid,'initialBoostPass=%d\n',initialPass);
fprintf(fid,'geometryPass=%d\n',geometryPass);
fprintf(fid,'mechanicsPass=%d\n',mechanicsPass);

fprintf('\n===== 0493x16i DEFORMABLE IMPERMEABLE COMPARISON =====\n');
fprintf('status=%s\n',status);
fprintf('binary Galilean phase-curve error/RMS = %.6g\n',PB.forceCurveRmsDifferenceOverRms);
fprintf('swept  Galilean phase-curve error/RMS = %.6g\n',PS.forceCurveRmsDifferenceOverRms);
fprintf('lower Galilean error: %s\n',lowerGalileanErrorMode);
fprintf('Darcy cost binary/swept = %.6g / %.6g s, ratio swept/binary=%.4f\n', ...
    binaryMeanDarcySeconds,sweptMeanDarcySeconds,sweptOverBinaryDarcyCost);
fprintf('mean fictitious mass binary rest/boost = %.4f / %.4f\n',BR.meanFictMass,BB.meanFictMass);
fprintf('mean fictitious mass swept  rest/boost = %.4f / %.4f\n',SR.meanFictMass,SB.meanFictMass);
fprintf('analysis=%s\n',analysisDir);
fprintf('========================================================\n');

result=struct('status',status,'pairRoot',pairRoot,'analysisDir',analysisDir, ...
    'binaryGalileanError',PB.forceCurveRmsDifferenceOverRms, ...
    'sweptGalileanError',PS.forceCurveRmsDifferenceOverRms, ...
    'sweptOverBinaryDarcyCost',sweptOverBinaryDarcyCost, ...
    'lowerGalileanErrorMode',lowerGalileanErrorMode);
end

function C = loadCase(runRoot,expectedMode,periodSteps)
outDir=fullfile(runRoot,'output');
dynPath=fullfile(outDir,'chi_solid_dynamics_0493x16a.csv');
sumPath=fullfile(outDir,'summary_runtime.csv');
impPath=fullfile(outDir,'chi_solid_impulse_0493x15a.csv');
paramPath=fullfile(outDir,'params_used.kv');
assert(isfile(dynPath),'Missing %s',dynPath); assert(isfile(sumPath),'Missing %s',sumPath);
assert(isfile(impPath),'Missing %s',impPath); assert(isfile(paramPath),'Missing %s',paramPath);
D=readtable(dynPath,'VariableNamingRule','preserve'); S=readtable(sumPath,'VariableNamingRule','preserve');
I=readtable(impPath,'VariableNamingRule','preserve'); assert(~isempty(D)&&~isempty(S)&&~isempty(I),'Empty x16i case %s',runRoot);
reqD={'totalFluidImpulseX','totalFluidImpulseY','brinkmanFluidImpulseX','bathFluidImpulseX','chiVpFluidImpulseX', ...
    'fictitiousFluidMass0493x16c','velocityXBefore','velocityXAfter','centerXBefore','solidMomentumBeforeX','solidMomentumAfterX', ...
    'solidReactionImpulseX','actionReactionResidualX','cellReactionSumX0493x16b','cellReactionSumY0493x16b', ...
    'cellLoadClosureResidualX0493x16b','cellLoadClosureResidualY0493x16b','primaryProjectionResidual0493x16b', ...
    'cudaResidentSolid0493x16e','subcellRaster0493x16e','historicalBinaryMask0493x16f','poststreamTemporalSync0493x16f', ...
    'sampledSolidVolume0493x16e','expectedSolidVolume0493x16e','sampledSolidVolumeRelativeError0493x16e', ...
    'hostGeometryFieldUploadBytes0493x16e','hostLoadFieldDownloadBytes0493x16e', ...
    'prescribedDeformable0493x16i','deformAmplitude0493x16i','deformOmega0493x16i', ...
    'positiveSolidFractionChange0493x16i','negativeSolidFractionChange0493x16i','maxAbsSolidFractionChange0493x16i'};
for j=1:numel(reqD), assert(ismember(reqD{j},D.Properties.VariableNames),'Missing %s in %s',reqD{j},dynPath); end
reqI={'deformableExclusion0493x16i','deformableExclusionMode0493x16i','exclusionCandidateParticles0493x16i', ...
    'exclusionReinjectedParticles0493x16i','exclusionReinjectedMass0493x16i','exclusionReinjectedMeanAbsDx0493x16i', ...
    'darcyTotalSeconds0493x16i'};
for j=1:numel(reqI), assert(ismember(reqI{j},I.Properties.VariableNames),'Missing %s in %s',reqI{j},impPath); end
[steps,id,is]=intersect(D.step,S.step,'stable'); keep=steps>0; steps=steps(keep); id=id(keep); is=is(keep);
[tf,ii]=ismember(steps,I.step); assert(all(tf),'Missing x16i impulse rows in %s',runRoot);
C.runRoot=runRoot; C.steps=steps; C.time=S.time(is); C.D=D; C.S=S; C.I=I; C.id=id; C.is=is; C.ii=ii;
C.Lx=readKvNumber(paramPath,'Lx'); C.Ly=readKvNumber(paramPath,'Ly'); C.Nx=round(readKvNumber(paramPath,'Nx')); C.Ny=round(readKvNumber(paramPath,'Ny'));
C.dt=readKvNumber(paramPath,'dt'); C.dx=C.Lx/C.Nx; C.solidMass=readKvNumber(paramPath,'chiSolidMass');
C.periodSteps=periodSteps; C.deformPhase=mod(double(steps)/double(periodSteps),1.0); C.steady=steps>=0.5*max(steps);
s0=find(S.step==0,1,'first'); assert(~isempty(s0),'Missing summary step 0 in %s',runRoot);
C.initialFluidMeanVx=S.meanVx(s0); C.initialFluidMass=S.totalMass(s0); C.initialSolidVx=D.velocityXBefore(id(1));
C.initialTotalMomentumX=S.Px(s0)+D.solidMomentumBeforeX(id(1));
C.fluidMeanVx=S.meanVx(is); C.solidVx=D.velocityXAfter(id); C.relativeBulkUx=C.solidVx-C.fluidMeanVx; C.kBT=S.kBTEstimate(is);
C.totalFluidImpulseX=D.totalFluidImpulseX(id); C.totalFluidImpulseY=D.totalFluidImpulseY(id);
C.brinkmanIx=D.brinkmanFluidImpulseX(id); C.bathIx=D.bathFluidImpulseX(id); C.chiVpIx=D.chiVpFluidImpulseX(id);
C.fictMass=D.fictitiousFluidMass0493x16c(id);
C.positiveDeltaTheta=D.positiveSolidFractionChange0493x16i(id); C.negativeDeltaTheta=D.negativeSolidFractionChange0493x16i(id); C.maxAbsDeltaTheta=D.maxAbsSolidFractionChange0493x16i(id);
C.reinjectedParticles=I.exclusionReinjectedParticles0493x16i(ii); C.reinjectedMass=I.exclusionReinjectedMass0493x16i(ii); C.reinjectedAbsDx=I.exclusionReinjectedMeanAbsDx0493x16i(ii);
C.darcySeconds=I.darcyTotalSeconds0493x16i(ii);
C.meanForceX=meanFinite(C.totalFluidImpulseX(C.steady)); C.rmsForceX=rmsCentered(C.totalFluidImpulseX(C.steady));
C.meanFictMass=meanFinite(C.fictMass(C.steady)); C.meanReinjectedParticles=meanFinite(C.reinjectedParticles(C.steady)); C.meanReinjectedMass=meanFinite(C.reinjectedMass(C.steady));
activeDx=C.reinjectedParticles(C.steady)>0; tmp=C.reinjectedAbsDx(C.steady); C.meanReinjectedAbsDx=meanFinite(tmp(activeDx));
C.meanDarcySeconds=meanFinite(C.darcySeconds(C.steady)); C.medianDarcySeconds=medianFinite(C.darcySeconds(C.steady));
C.maxSampledVolumeRelError=max(abs(D.sampledSolidVolumeRelativeError0493x16e(id)));
C.cudaResident=all(D.cudaResidentSolid0493x16e(id)==1); C.historicalBinary=all(D.historicalBinaryMask0493x16f(id)==1); C.temporalSync=all(D.poststreamTemporalSync0493x16f(id)==1);
C.noSubcellDarcy=all(D.subcellRaster0493x16e(id)==0); C.prescribedDeformable=all(D.prescribedDeformable0493x16i(id)==1);
C.noFullGridHostTraffic=max(D.hostGeometryFieldUploadBytes0493x16e(id))==0 && max(D.hostLoadFieldDownloadBytes0493x16e(id))==0;
C.exclusionGate=all(I.deformableExclusion0493x16i(ii)==1) && all(round(I.deformableExclusionMode0493x16i(ii))==expectedMode);
% Mechanical closure, same global normalization convention as x16c/x16f.
P0=S.Px(s0)+D.solidMomentumBeforeX(id(1)); Pf=S.Px(is); Ps=D.solidMomentumAfterX(id); Ptot=Pf+Ps;
scaleP=max([abs(P0);abs(Pf);abs(Ps);1e-30]); C.maxRelTotalDrift=max(abs(Ptot-P0))/scaleP;
aScale=max([abs(D.totalFluidImpulseX(id));abs(D.solidReactionImpulseX(id));1e-30]); C.maxRelActionReaction=max(abs(D.actionReactionResidualX(id)))/aScale;
cx=max([abs(D.cellReactionSumX0493x16b(id));abs(D.totalFluidImpulseX(id));1e-30]); cy=max([abs(D.cellReactionSumY0493x16b(id));abs(D.totalFluidImpulseY(id));1e-30]);
C.maxRelCellClosureX=max(abs(D.cellLoadClosureResidualX0493x16b(id)))/cx; C.maxRelCellClosureY=max(abs(D.cellLoadClosureResidualY0493x16b(id)))/cy;
ps=max([abs(D.cellReactionSumX0493x16b(id));abs(D.solidReactionImpulseX(id));1e-30]); C.maxRelProjection=max(abs(D.primaryProjectionResidual0493x16b(id)))/ps;
C.technicalPass=C.cudaResident && C.historicalBinary && C.temporalSync && C.noSubcellDarcy && C.prescribedDeformable && C.noFullGridHostTraffic && C.exclusionGate;
end

function [restInit,boostInit,shiftMeasured,shiftError]=initialBoostMetrics(R,B,UG)
restInit=max(abs([R.initialFluidMeanVx,R.initialSolidVx])); boostInit=max(abs([B.initialFluidMeanVx-UG,B.initialSolidVx-UG]));
shiftMeasured=(B.initialTotalMomentumX-R.initialTotalMomentumX)/(B.initialFluidMass+B.solidMass); shiftError=abs(shiftMeasured-UG);
end

function P=phasePair(R,B,nBins)
edges=linspace(0,1,nBins+1); centers=0.5*(edges(1:end-1)+edges(2:end));
rs=R.steady; bs=B.steady; [~,~,rb]=histcounts(R.deformPhase(rs),edges); [~,~,bb]=histcounts(B.deformPhase(bs),edges);
rForce=R.totalFluidImpulseX(rs); bForce=B.totalFluidImpulseX(bs); rRe=R.reinjectedParticles(rs); bRe=B.reinjectedParticles(bs); rM=R.fictMass(rs); bM=B.fictMass(bs); rTheta=R.positiveDeltaTheta(rs); bTheta=B.positiveDeltaTheta(bs);
P.phaseCenter=centers(:); P.restCount=zeros(nBins,1); P.boostCount=zeros(nBins,1); P.restMeanForce=nan(nBins,1); P.boostMeanForce=nan(nBins,1); P.restMeanReinjected=nan(nBins,1); P.boostMeanReinjected=nan(nBins,1); P.restMeanFictMass=nan(nBins,1); P.boostMeanFictMass=nan(nBins,1); P.restMeanPositiveDeltaTheta=nan(nBins,1); P.boostMeanPositiveDeltaTheta=nan(nBins,1);
for q=1:nBins
    ir=rb==q; ib=bb==q; P.restCount(q)=sum(ir); P.boostCount(q)=sum(ib);
    if any(ir), P.restMeanForce(q)=meanFinite(rForce(ir)); P.restMeanReinjected(q)=meanFinite(rRe(ir)); P.restMeanFictMass(q)=meanFinite(rM(ir)); P.restMeanPositiveDeltaTheta(q)=meanFinite(rTheta(ir)); end
    if any(ib), P.boostMeanForce(q)=meanFinite(bForce(ib)); P.boostMeanReinjected(q)=meanFinite(bRe(ib)); P.boostMeanFictMass(q)=meanFinite(bM(ib)); P.boostMeanPositiveDeltaTheta(q)=meanFinite(bTheta(ib)); end
end
valid=P.restCount>=5 & P.boostCount>=5 & isfinite(P.restMeanForce) & isfinite(P.boostMeanForce); assert(any(valid),'Insufficient deformation-phase overlap');
P.forceDifference=P.boostMeanForce-P.restMeanForce; P.forceCurveRmsDifference=rmsFinite(P.forceDifference(valid));
rmsScale=sqrt(0.5*(rmsCentered(R.totalFluidImpulseX(rs))^2+rmsCentered(B.totalFluidImpulseX(bs))^2)); P.forceCurveRmsDifferenceOverRms=P.forceCurveRmsDifference/max(rmsScale,1e-30);
P.meanForceDifferenceOverRms=abs(meanFinite(B.totalFluidImpulseX(bs))-meanFinite(R.totalFluidImpulseX(rs)))/max(rmsScale,1e-30);
P.restCoverage=min(P.restCount)/max(mean(P.restCount),1e-30); P.boostCoverage=min(P.boostCount)/max(mean(P.boostCount),1e-30);
end

function [meanDiffOverRms,rmsDiffFrac,tempRelDiff,fictRelDiff]=pairBulkMetrics(R,B)
r=R.relativeBulkUx(R.steady); b=B.relativeBulkUx(B.steady); mr=meanFinite(r); mb=meanFinite(b); rr=rmsFinite(r); rb=rmsFinite(b); scale=max(0.5*(rr+rb),1e-30); meanDiffOverRms=abs(mb-mr)/scale; rmsDiffFrac=abs(rb-rr)/scale;
tr=meanFinite(R.kBT(R.steady)); tb=meanFinite(B.kBT(B.steady)); tempRelDiff=abs(tb-tr)/max(0.5*(abs(tb)+abs(tr)),1e-30);
fr=meanFinite(R.fictMass(R.steady)); fb=meanFinite(B.fictMass(B.steady)); fictRelDiff=abs(fb-fr)/max(0.5*(abs(fb)+abs(fr)),1e-30);
end

function O=occupancyMetrics(C)
p=C.positiveDeltaTheta(C.steady); n=C.negativeDeltaTheta(C.steady); O.meanPositive=meanFinite(p); O.meanNegative=meanFinite(n); O.maxAbs=max(C.maxAbsDeltaTheta(C.steady)); O.imbalance=abs(sum(p)-sum(n))/max(sum(p)+sum(n),1e-30);
end

function x=rmsFinite(v), v=v(isfinite(v)); if isempty(v),x=NaN;else,x=sqrt(mean(v.^2));end,end
function x=rmsCentered(v), v=v(isfinite(v)); if isempty(v),x=NaN;else,x=sqrt(mean((v-mean(v)).^2));end,end
function x=meanFinite(v), v=v(isfinite(v)); if isempty(v),x=NaN;else,x=mean(v);end,end
function x=medianFinite(v), v=v(isfinite(v)); if isempty(v),x=NaN;else,x=median(v);end,end
function value=readKvNumber(path,key), text=fileread(path); expr=['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)']; tok=regexp(text,expr,'tokens','once'); assert(~isempty(tok),'Missing key %s in %s',key,path); value=str2double(strtrim(tok{1})); assert(isfinite(value),'Non-numeric key %s in %s',key,path); end
